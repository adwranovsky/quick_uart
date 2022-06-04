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

    input  logic ready_i,
    output logic valid_o,
    output logic [DATA_BITS-1:0] data_o,
    output logic data_lost_o,

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
    logic [$clog2(DIV):0] timer_count;
    timer #(
        .WIDTH($clog2(DIV))
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
    initial data_lost_o = 0;
    always_ff @(posedge clk_i)
        if (rst_i)
            data_lost_o <= 0;
        else if (valid_o && ready_i)
            data_lost_o <= 0;
        else if (valid_o && load_data)
            data_lost_o <= 1;
        else
            data_lost_o <= data_lost_o;

    // State register
    typedef enum {
        RESET,
        IDLE,
        RECEIVING,
        STROBE,
        WAIT_FOR_IDLE
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
                next_state = WAIT_FOR_IDLE;
            WAIT_FOR_IDLE:
                if (rx_i == IDLE_VALUE)
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
            end
            WAIT_FOR_IDLE: begin
                reset_bit_counter = 1;
            end
            default: begin
                // defaults
            end
        endcase
    end


endmodule
`default_nettype wire

