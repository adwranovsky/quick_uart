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
 * `quick_uart_tx` - Quickly add a UART TX interface to an FPGA project
 *
 * Parameters:
 *  `CLK_FREQ_HZ` - The input clock frequency. The UART baud rate. Ignored if DIV is manually set.
 *  `BAUD` - The UART baud rate. Ignored if DIV is manually set.
 *  `DIV` - The number of system clock cycles per bit. By default it is calculated from `CLK_FREQ_HZ` and `BAUD`, but
 *          can optionally be manually set.
 *  `IDLE_VALUE` - The value that `tx_o` should idle at when not transmitting.
 *  `DATA_BITS` - The number of data bits per transfer
 *  `STOP_BITS` - The number of stop bits at the end of the transfer. Each stop bit takes a value of `IDLE_VALUE`.
 *  `START_BITS` - The number of start bits at the beginning of a transfer. Each start bit takes a value of
 *                 `~IDLE_VALUE`.
 *
 * Ports:
 *  `clk_i` - The system clock
 *  `rst_i` - An active high reset synchronous with `clk_i`
 *
 *  `busy_o` - Indicates when the device is busy transmitting, though when low it doesn't necessarily indicate that the
 *             device is ready to receive more data. Hook up to an LED for a visual indicator of when the device is
 *             transmitting.
 *
 *  `ready_o` - Indicates that the module is ready to accept new data for transmission. The UART begins transmitting
 *              only when both `valid_i` and `ready_o` are high on the same clock cycle.
 *  `valid_i` - Indicates that `data_i` is valid. The UART begins transmitting only when both `valid_i` and
 *              `ready_o` are high on the same clock cycle.
 *  `data_i` - The data to write out serially on `tx_o`. The least significant bit is sent first.
 *
 *  `tx_o` - The UART serial output
 *
 * Description:
 *  `quick_uart_tx` is a quick way to integrate a UART into an FPGA design using a simple ready/valid handshake
 *  interface. Parameters are used to statically configure the baud rate and number of start, data, and stop bits.
 *
 *  A good reference on ready/valid handshake interfaces can be found [here](http://fpgacpu.ca/fpga/handshake.html).
 *  A UART transaction is started by performing a handshake on the `ready_o`/`valid_i` interface.
 *
 *  Testing is admittedly bare-bones, using a testbench generated from a SystemVerilog cover statement. See the
 *  SymbiYosys `.sby` file and FuseSoC config files for details.
 */
`default_nettype none
module quick_uart_tx #(
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

    output logic ready_o,
    input  logic valid_i,
    input  logic [DATA_BITS-1:0] data_i,

    output logic tx_o
);
    localparam TOTAL_BITS = START_BITS + DATA_BITS + STOP_BITS;

    // register tx_o
    logic tx;
    initial tx_o = IDLE_VALUE;
    always_ff @(posedge clk_i)
        if (rst_i)
            tx_o <= IDLE_VALUE;
        else
            tx_o <= tx;

    // Convert parallel data to serial data
    logic load_data, shift_data;
    shift_register_piso #(
        .WIDTH(TOTAL_BITS),
        .DEFAULT_VALUE({TOTAL_BITS{IDLE_VALUE}}),
        .FILL_VALUE(IDLE_VALUE)
    ) shift_reg (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .set_i(load_data),
        .value_i(
            {{STOP_BITS{IDLE_VALUE}}, data_i, {START_BITS{~IDLE_VALUE}}}
        ),
        .advance_i(shift_data),
        .bit_o(tx)
    );

    // A timer to count out the bit period
    logic start_timer, timer_done;
    timer #(
        .WIDTH($clog2(DIV+1))
    ) bit_timer (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(start_timer),
        .count_i(DIV[$clog2(DIV+1)-1:0]),
        .done_o(timer_done)
    );

    // Count bits sent
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


    // State register
    typedef enum {
        RESET = 0,
        READY = 1,
        TRANSMITTING = 2
    } uart_tx_state_t;
    uart_tx_state_t state, next_state;

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
                next_state = READY;
            READY:
                if (valid_i)
                    next_state = TRANSMITTING;
            TRANSMITTING:
                if (bit_counter_done)
                    next_state = READY;
            default:
                next_state = RESET;
        endcase
    end

    // State machine outputs
    always_comb begin
        ready_o = 0;
        start_timer = 0;
        load_data = 0;
        shift_data = 0;
        increment_bit_counter = 0;
        reset_bit_counter = 0;
        case (state)
            READY: begin
                ready_o = 1;
                reset_bit_counter = 1;
                load_data = valid_i;
                start_timer = valid_i;
            end
            TRANSMITTING: begin
                start_timer = timer_done;
                increment_bit_counter = timer_done;
                shift_data = timer_done;
            end
            default: begin
                // use default values
            end
        endcase
    end

    // Set busy when transmitting
    always_comb
        busy_o = state == TRANSMITTING;

endmodule
`default_nettype wire
