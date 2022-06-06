// Super lazy testbench generation using cover properties on a uart tx and rx hooked together
`default_nettype none
module formal_top;

    (* gclk *) logic clk;
    logic rst = $anyseq();
    logic serial_data;

    localparam int DIV = 5;
    localparam int LEN = 8;

    logic tx_ready;
    logic tx_valid = $anyseq();
    logic [LEN-1:0] tx_data = $anyseq();
    quick_uart_tx #(
        .DIV(DIV),
        .DATA_BITS(LEN)
    ) uart_tx (
        .clk_i(clk),
        .rst_i(rst),
        .busy_o(),

        .ready_o(tx_ready),
        .valid_i(tx_valid),
        .data_i(tx_data),
        .tx_o(serial_data)
    );

    logic rx_ready = $anyseq();
    logic rx_valid, rx_dropped;
    logic [LEN-1:0] rx_data;
    quick_uart_rx #(
        .DIV(DIV),
        .DATA_BITS(LEN)
    ) uart_rx (
        .clk_i(clk),
        .rst_i(rst),
        .busy_o(),

        .ready_i(rx_ready),
        .valid_o(rx_valid),
        .data_o(rx_data),
        .data_dropped_o(rx_dropped),

        .rx_i(serial_data)
    );

    // start in reset
    always_ff @(posedge clk)
        if ($initstate())
            assume(rst);

    // detect handshakes
    logic tx_handshake, rx_handshake;
    always_comb begin
        tx_handshake = tx_ready && tx_valid && !rst;
        rx_handshake = rx_ready && rx_valid && !rst;
    end

    // Count oustanding handshakes
    int outstanding_handshakes = 0;
    always_ff @(posedge clk) begin
        if (rx_handshake) begin
            if (tx_handshake) begin
                outstanding_handshakes <= 1;
            end else begin
                outstanding_handshakes <= 0;
            end
        end else if (tx_handshake) begin
            outstanding_handshakes <= outstanding_handshakes + 1;
        end else begin
            outstanding_handshakes <= outstanding_handshakes;
        end
    end

    // Make sure rx_dropped is asserted when it absolutely must be
    always_ff @(posedge clk)
        if (outstanding_handshakes > 2 && rx_handshake)
            assert(rx_dropped);

    // Make testbenches
    always_ff @(posedge clk) begin
        cover(rx_handshake && rx_dropped==0 && rx_data==8'ha5);
        cover(rx_handshake && rx_dropped==1);
    end


endmodule
