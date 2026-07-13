`timescale 1ns/1ps
// =============================================================================
// top.v — I2C-to-UART Bridge ASIC (v5, TI-pattern improvements)
//
// Changes from v4:
//   1. i2c_stop pulse wired from i2c_slave to control_fsm (TX-on-STOP pattern)
//   2. uart_rx frame_err / parity_err wired to reg_file ERR_CODE register
//   3. TX FIFO overflow (i2c write when full) wired to ERR_CODE bit5
//   4. control_fsm gets i2c_stop input
// =============================================================================
module top (
    input  wire clk,
    input  wire rst_n,
    input  wire scl_in,
    input  wire sda_in,
    output wire sda_oe,
    output wire uart_tx,
    input  wire uart_rx,
    output wire irq_n
);

    // -----------------------------------------------------------------------
    // Register file decoded outputs
    // -----------------------------------------------------------------------
    wire [15:0] baud_div;
    wire [7:0]  uart_cfg, pwr_ctrl;
    wire [6:0]  i2c_addr_cfg;
    wire [3:0]  fifo_thresh;
    wire [7:0]  irq_en, irq_stat, irq_set_w;

    // -----------------------------------------------------------------------
    // Baud generators
    // -----------------------------------------------------------------------
    reg [15:0] baud_div_rx;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) baud_div_rx <= 16'd1;
        else baud_div_rx <= (baud_div < 16) ? 16'd1 : {4'b0, baud_div[15:4]};

    wire baud_tick, baud_tick_x16;
    baud_gen #(.DIV_WIDTH(16)) u_baud_tx (
        .clk(clk), .rst_n(rst_n), .div(baud_div), .baud_tick(baud_tick));
    baud_gen #(.DIV_WIDTH(16)) u_baud_rx (
        .clk(clk), .rst_n(rst_n), .div(baud_div_rx), .baud_tick(baud_tick_x16));

    // -----------------------------------------------------------------------
    // I2C slave — exposes stop_det for TX gating
    // -----------------------------------------------------------------------
    wire [7:0] i2c_rx_data;
    wire       i2c_rx_valid, i2c_tx_req, i2c_busy;
    wire [7:0] i2c_tx_data;
    wire       i2c_stop_det;   // 1-clk pulse on STOP condition

    i2c_slave u_i2c (
        .clk(clk), .rst_n(rst_n),
        .scl_in(scl_in), .sda_in(sda_in), .sda_oe(sda_oe),
        .slave_addr(i2c_addr_cfg),
        .rx_data(i2c_rx_data), .rx_valid(i2c_rx_valid),
        .tx_data(i2c_tx_data), .tx_req(i2c_tx_req),
        .busy(i2c_busy), .addr_match());

    // Derive stop pulse: i2c_busy falls (was busy, now idle)
    reg i2c_busy_r;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) i2c_busy_r <= 1'b0;
        else        i2c_busy_r <= i2c_busy;
    assign i2c_stop_det = i2c_busy_r & ~i2c_busy;  // falling edge of busy

    // -----------------------------------------------------------------------
    // Pointer-byte decoder
    // -----------------------------------------------------------------------
    reg first_byte, ptr_valid, is_reg_access;
    reg [3:0] reg_ptr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            first_byte <= 1; ptr_valid <= 0;
            is_reg_access <= 0; reg_ptr <= 0;
        end else begin
            if (!i2c_busy) begin first_byte <= 1; ptr_valid <= 0; end
            if (i2c_rx_valid) begin
                if (first_byte) begin
                    is_reg_access <= i2c_rx_data[7];
                    reg_ptr       <= i2c_rx_data[3:0];
                    ptr_valid     <= 1;
                    first_byte    <= 0;
                end else if (is_reg_access) begin
                    reg_ptr <= reg_ptr + 1'b1;
                end
            end
        end
    end

    wire is_data_byte  = i2c_rx_valid & ptr_valid & ~first_byte;
    wire rf_wr_en      = is_data_byte &  is_reg_access;
    wire tx_fifo_wr_en = is_data_byte & ~is_reg_access;

    // -----------------------------------------------------------------------
    // TX FIFO (I2C → UART)
    // -----------------------------------------------------------------------
    wire        tx_fifo_full, tx_fifo_empty, tx_fifo_rd_en;
    wire [7:0]  tx_fifo_rd_data;

    fifo #(.WIDTH(8), .DEPTH(16), .ADDR_W(4)) u_tx_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(tx_fifo_wr_en), .wr_data(i2c_rx_data),
        .full(tx_fifo_full),   .almost_full(),
        .rd_en(tx_fifo_rd_en), .rd_data(tx_fifo_rd_data),
        .empty(tx_fifo_empty), .almost_empty(), .count());

    // TX FIFO overflow error: data arrived when FIFO was full
    wire err_buf_ovf = tx_fifo_wr_en & tx_fifo_full;

    // -----------------------------------------------------------------------
    // RX FIFO (UART → I2C read path)
    // -----------------------------------------------------------------------
    wire        rx_fifo_full, rx_fifo_empty, rx_fifo_wr_en, rx_fifo_rd_en;
    wire [7:0]  rx_fifo_wr_data, rx_fifo_rd_data;
    wire [4:0]  rx_fifo_count;

    fifo #(.WIDTH(8), .DEPTH(16), .ADDR_W(4)) u_rx_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx_fifo_wr_en), .wr_data(rx_fifo_wr_data),
        .full(rx_fifo_full),   .almost_full(),
        .rd_en(rx_fifo_rd_en), .rd_data(rx_fifo_rd_data),
        .empty(rx_fifo_empty), .almost_empty(), .count(rx_fifo_count));

    assign rx_fifo_rd_en = i2c_tx_req & ~rx_fifo_empty;

    // -----------------------------------------------------------------------
    // UART TX
    // -----------------------------------------------------------------------
    wire [7:0] uart_tx_data;
    wire       uart_tx_valid, uart_tx_ready;

    uart_tx u_uart_tx (
        .clk(clk), .rst_n(rst_n), .baud_tick(baud_tick),
        .parity_cfg(uart_cfg[3:2]), .stop2(uart_cfg[4]),
        .tx_data(uart_tx_data), .tx_valid(uart_tx_valid),
        .tx_ready(uart_tx_ready), .tx_out(uart_tx));

    // -----------------------------------------------------------------------
    // UART RX — expose error signals for ERR_CODE register
    // -----------------------------------------------------------------------
    wire [7:0] uart_rx_data;
    wire       uart_rx_valid;
    wire       uart_frame_err, uart_parity_err;

    uart_rx u_uart_rx (
        .clk(clk), .rst_n(rst_n), .baud_tick_x16(baud_tick_x16),
        .parity_cfg(uart_cfg[3:2]), .stop2(uart_cfg[4]),
        .rx_in(uart_rx),
        .rx_data(uart_rx_data), .rx_valid(uart_rx_valid),
        .frame_err(uart_frame_err),      // now connected to ERR_CODE
        .parity_err(uart_parity_err));   // now connected to ERR_CODE

    // UART overrun: new byte arrived at RX FIFO when it was already full
    wire err_uart_overrun = uart_rx_valid & rx_fifo_full;

    // -----------------------------------------------------------------------
    // Control FSM (v2: gated by i2c_stop)
    // -----------------------------------------------------------------------
    control_fsm u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .tx_fifo_empty(tx_fifo_empty),
        .tx_fifo_rd_en(tx_fifo_rd_en),
        .tx_fifo_rd_data(tx_fifo_rd_data),
        .uart_tx_data(uart_tx_data),
        .uart_tx_valid(uart_tx_valid),
        .uart_tx_ready(uart_tx_ready),
        .uart_rx_data(uart_rx_data),
        .uart_rx_valid(uart_rx_valid),
        .rx_fifo_wr_en(rx_fifo_wr_en),
        .rx_fifo_wr_data(rx_fifo_wr_data),
        .rx_fifo_full(rx_fifo_full),
        .tx_fifo_full(tx_fifo_full),
        .rx_fifo_empty(rx_fifo_empty),
        .fifo_thresh(fifo_thresh),
        .rx_fifo_count(rx_fifo_count),
        .i2c_stop(i2c_stop_det),         // TI pattern: transmit on STOP
        .irq_set(irq_set_w),
        .pwr_mode(pwr_ctrl[1:0]));

    // -----------------------------------------------------------------------
    // Register file (v3: ERR_CODE register + STATUS + irq_stat)
    // -----------------------------------------------------------------------
    wire [7:0] rf_rd_data;

    reg_file u_reg (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rf_wr_en), .wr_addr(reg_ptr), .wr_data(i2c_rx_data),
        .rd_addr(reg_ptr), .rd_data(rf_rd_data),
        .baud_div(baud_div), .uart_cfg(uart_cfg), .uart_flow(),
        .i2c_addr(i2c_addr_cfg), .i2c_cfg(),
        .fifo_thresh(fifo_thresh), .irq_en(irq_en),
        .pwr_ctrl(pwr_ctrl), .irq_set(irq_set_w), .irq_stat(irq_stat),
        // Error code inputs (TI pattern)
        .err_uart_frame  (uart_frame_err),
        .err_uart_parity (uart_parity_err),
        .err_uart_overrun(err_uart_overrun),
        .err_rxfifo_ovf  (rx_fifo_full & uart_rx_valid),
        .err_txfifo_udf  (tx_fifo_rd_en & tx_fifo_empty),
        .err_buf_ovf     (err_buf_ovf),
        .err_code        (),
        // Live STATUS signals
        .status_i2c_busy     (i2c_busy),
        .status_uart_tx_busy (~uart_tx_ready),
        .status_tx_fifo_full (tx_fifo_full),
        .status_tx_fifo_empty(tx_fifo_empty),
        .status_rx_fifo_full (rx_fifo_full),
        .status_rx_data_rdy  (~rx_fifo_empty)
    );

    assign i2c_tx_data = rf_rd_data;

    // -----------------------------------------------------------------------
    // IRQ (active-low, masked by IRQ_EN)
    // -----------------------------------------------------------------------
    assign irq_n = ~|(irq_stat & irq_en);

endmodule
