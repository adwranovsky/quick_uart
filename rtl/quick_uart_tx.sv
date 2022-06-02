`default_nettype none
module quick_uart_tx #(
    parameter integer CLK_FREQ = 100000000,
    parameter integer BAUD = 115200,
    parameter integer DIV = CLK_FREQ / BAUD,
    parameter logic   IDLE_VALUE = 1'b1,
    parameter integer DATA_BITS = 8,
    parameter integer STOP_BITS = 1,
    parameter integer START_BITS = 1
) (
    input  logic clk_i,
    input  logic rst_i,

    output logic ready_o,
    input  logic valid_i,
    input  logic [DATA_BITS-1:0] data_i,

    output logic tx_o
);
    localparam TOTAL_BITS = START_BITS + DATA_BITS + STOP_BITS;

    // Convert parallel data to serial data
    logic load_data, shift_data;
    shift_register_piso #(
        .WIDTH(TOTAL_BITS),
    ) shift_reg (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .set_i(load_data),
        .value_i(
            {{STOP_BITS{IDLE_VALUE}}, data_i, {START_BITS{~IDLE_VALUE}}}
        ),
        .advance_i(shift_data),
        .bit_o(tx_o),
    );

    // A timer to set the bit period
    logic start_timer, timer_done;
    timer #(
        .WIDTH($clog2(DIV))
    ) bit_timer (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(start_timer),
        .count_i(DIV),
        .done_o(timer_done)
    );

    // Count bits sent
    logic reset_bit_counter, increment_bit_counter;
    logic [$clog2(TOTAL_BITS):0] bit_counter = TOTAL_BITS;
    always_ff @(posedge clk_i) begin
        if (rst_i || reset_bit_counter)
            bit_counter <= TOTAL_BITS;
        else
            bit_counter <= bit_counter - increment_bit_counter;
    end
    logic bit_counter_done = bit_counter == 0;


    // State register
    typedef enum {
        RESET = 2'h0,
        READY = 2'h1,
        TRANSMITTING = 2'h2
    } uart_tx_state_t;
    state_t state, next_state;

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
        load_data = 0;
        shift_data = 0;
        increment_bit_counter = 0;
        reset_bit_counter = 0;
        case (state)
            READY: begin
                reset_bit_counter = 1;
                load_data = valid_i;
                start_timer = valid_i;
            end
            TRANSMITTING: begin
                start_timer = timer_done;
                increment_bit_counter = timer_done;
            end
            default: begin
                // use default values
            end
        endcase
    end

endmodule
`default_nettype wire
