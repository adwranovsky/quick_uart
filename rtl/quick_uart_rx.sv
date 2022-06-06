/* ---------------------------------------------------------------------------------------------------------------------
 *
 * Copyright 2022 Alex Wranovsky
 *
 * This work is licensed under the CERN-OHL-W v2, a weakly reciprocal license for hardware. You may find the full
 * license text here if you have not received it with this source code distribution:
 *
 * https://ohwr.org/cern_ohl_w_v2.txt
 *
 * ---------------------------------------------------------------------------------------------------------------------
 *
 *
 * `quick_uart_rx` - Quickly add a UART RX interface to an FPGA project
 *
 * Parameters:
 *  `CLK_FREQ_HZ` - The input clock frequency. The UART baud rate. Ignored if DIV is manually set.
 *  `BAUD` - The UART baud rate. Ignored if DIV is manually set.
 *  `DIV` - The number of system clock cycles per bit. By default it is calculated from `CLK_FREQ_HZ` and `BAUD`, but
 *          can optionally be manually set.
 *  `IDLE_VALUE` - The value that `rx_o` idles at.
 *  `DATA_BITS` - The number of data bits per transfer
 *  `STOP_BITS` - The number of stop bits at the end of the transfer. Each stop bit should take a value of `IDLE_VALUE`.
 *  `START_BITS` - The number of start bits at the beginning of a transfer. Each start bit takes a value of
 *                 `~IDLE_VALUE`.
 *
 * Ports:
 *  `clk_i` - The system clock
 *  `rst_i` - An active high reset synchronous with `clk_i`
 *
 *  `busy_o` - Indicates when the device is busy receiving, though `data_o` may be valid despite `busy_o` being high.
 *             Hook up to an LED for a visual indicator of when the device is receiving.
 *
 *  `ready_i` - Raise high when the data sink is ready to accept more data. The module's internal buffer is only flushed
 *              when `ready_i` and `valid_o` are high on the same clock cycle.
 *  `valid_o` - Indicates that the UART has completed receiving a whole word and that `data_o` and `data_dropped_o` are
 *              valid. The module's internal buffer is only flushed when `ready_i` and `valid_o` are high on the same
 *              clock cycle.
 *  `data_o` - The data most recently received serially on `rx_i`. Valid when `valid_o` is high. The least significant
 *             bit is the first received on `rx_i`.
 *  `data_dropped_o` - Indicates that the UART has finished receiving at least two bytes since the last
 *                     `ready_i`/`valid_o` handshake, and therefore had to drop a byte. Only valid when `valid_o` is
 *                     high, and gets cleared on a `ready_i`/`valid_o` handshake.
 *
 *  `rx_i` - The UART serial input. There is no CDC synchronizer on this input, so make sure to add one external to this
 *           module.
 *
 * Description:
 *  `quick_uart_rx` is a quick way to integrate a UART into an FPGA design using a simple ready/valid handshake
 *  interface. Parameters are used to statically configure the baud rate and number of start, data, and stop bits.
 *
 *  A good reference on ready/valid handshake interfaces can be found [here](http://fpgacpu.ca/fpga/handshake.html).
 *  Data received on the UART is gotten by performing a handshake on the `ready_o`/`valid_i` interface.
 *
 *  Testing is admittedly bare-bones, using a testbench generated from a SystemVerilog cover statement. See the
 *  SymbiYosys `.sby` file and FuseSoC config files for details.
 */
`default_nettype none
module quick_uart_rx #(
    parameter int   CLK_FREQ = 100000000,
    parameter int   BAUD = 115200,
    parameter int   DIV = CLK_FREQ / BAUD,
    parameter logic IDLE_VALUE = 1'b1,
    parameter int   DATA_BITS = 8,
    parameter int   STOP_BITS = 1,
    parameter int   START_BITS = 1
) (
    input  logic clk_i,
    input  logic rst_i,
    output logic busy_o,

    input  logic ready_i,
    output logic valid_o,
    output logic [DATA_BITS-1:0] data_o,
    output logic data_dropped_o,

    input  logic rx_i
);
    localparam TOTAL_BITS = START_BITS + DATA_BITS + STOP_BITS;

    // Serial-in parallel-out Shift register
    logic [0:TOTAL_BITS-1] shift_reg_data;
    logic shift_data;
    shift_register_sipo #(
        .WIDTH(TOTAL_BITS)
    ) shift_reg (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .advance_i(shift_data),
        .bit_i(rx_i),
        .value_o(shift_reg_data)
    );

    // A timer to count out the bit period and align the clock in the center of the bit
    logic start_timer, timer_done;
    logic [$clog2(DIV+1)-1:0] timer_count;
    timer #(
        .WIDTH($clog2(DIV+1))
    ) bit_timer (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(start_timer),
        .count_i(timer_count),
        .done_o(timer_done)
    );

    // Count bits received
    logic reset_bit_counter, increment_bit_counter;
    logic [$clog2(TOTAL_BITS):0] bit_counter = TOTAL_BITS[$bits(bit_counter)-1:0];
    always_ff @(posedge clk_i) begin
        if (rst_i || reset_bit_counter)
            bit_counter <= TOTAL_BITS[$bits(bit_counter)-1:0];
        else if (increment_bit_counter)
            bit_counter <= bit_counter - 1;
        else
            bit_counter <= bit_counter;
    end
    logic bit_counter_done = bit_counter == 0;

    // Register the shift register data as soon as it's received
    logic load_data;
    initial data_o = 0;
    always_ff @(posedge clk_i)
        if (rst_i)
            data_o <= 0;
        else if (load_data)
            data_o <= shift_reg_data[START_BITS +: DATA_BITS];
        else
            data_o <= data_o;

    // Handshake logic
    initial valid_o = 0;
    always_ff @(posedge clk_i)
        if (rst_i)
            valid_o <= 0;
        else if (load_data)
            valid_o <= 1;
        else if (ready_i)
            valid_o <= 0;
        else
            valid_o <= valid_o;

    // Indicate on each handshake whether or not any data was discarded since the last handshake
    initial data_dropped_o = 0;
    always_ff @(posedge clk_i)
        if (rst_i)
            data_dropped_o <= 0;
        else if (valid_o && ready_i)
            data_dropped_o <= 0;
        else if (valid_o && load_data)
            data_dropped_o <= 1;
        else
            data_dropped_o <= data_dropped_o;

    // State register
    typedef enum {
        RESET,
        IDLE,
        RECEIVING,
        STROBE
    } uart_rx_state_t;
    uart_rx_state_t state, next_state;

    initial state = RESET;
    always_ff @(posedge clk_i)
        if (rst_i)
            state <= RESET;
        else
            state <= next_state;

    // State machine transition logic
    always_comb begin
        next_state = state;
        case (state)
            RESET:
                next_state = IDLE;
            IDLE:
                if (rx_i != IDLE_VALUE)
                    next_state = RECEIVING;
            RECEIVING:
                if (bit_counter_done)
                    next_state = STROBE;
            STROBE:
                next_state = IDLE;
            default:
                next_state = RESET;
        endcase
    end

    // State machine outputs
    always_comb begin
        shift_data = 0;
        load_data = 0;
        start_timer = 0;
        timer_count = DIV[$bits(timer_count)-1:0];
        reset_bit_counter = 0;
        increment_bit_counter = 0;

        case (state)
            RESET: begin
                reset_bit_counter = 1;
            end
            IDLE: begin
                timer_count = DIV[$bits(timer_count)-1:0]/2;
                start_timer = rx_i != IDLE_VALUE;
            end
            RECEIVING: begin
                start_timer = timer_done;
                shift_data = timer_done;
                increment_bit_counter = timer_done;
            end
            STROBE: begin
                load_data = 1;
                reset_bit_counter = 1;
            end
            default: begin
                // defaults
            end
        endcase
    end

    // Set busy_o when receiving
    always_comb
        busy_o = state == RECEIVING;


endmodule
`default_nettype wire

