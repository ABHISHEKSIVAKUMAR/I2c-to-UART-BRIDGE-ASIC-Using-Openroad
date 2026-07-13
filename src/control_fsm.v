`timescale 1ns/1ps
// =============================================================================
// control_fsm.v — Datapath glue (v2, TI-pattern TX gating)
//
// Key change from TI reference (SWRA796A):
//   TX FIFO is NOT drained continuously. It is held until i2c_stop fires,
//   then fully drained. This matches TI's gUartTxReady flag pattern:
//   collect the full I2C packet, then transmit the whole thing over UART.
//   Prevents partial/split UART frames on back-to-back I2C writes.
// =============================================================================
module control_fsm (
    input  wire       clk,
    input  wire       rst_n,

    // TX FIFO drain → UART TX
    input  wire       tx_fifo_empty,
    output reg        tx_fifo_rd_en,
    input  wire [7:0] tx_fifo_rd_data,
    output reg  [7:0] uart_tx_data,
    output reg        uart_tx_valid,
    input  wire       uart_tx_ready,

    // UART RX → RX FIFO fill
    input  wire [7:0] uart_rx_data,
    input  wire       uart_rx_valid,
    output reg        rx_fifo_wr_en,
    output reg  [7:0] rx_fifo_wr_data,
    input  wire       rx_fifo_full,

    // I2C stop pulse — triggers TX drain (TI pattern: transmit on STOP)
    input  wire       i2c_stop,     // 1-clk pulse when I2C STOP detected

    // IRQ generation
    input  wire       tx_fifo_full,
    input  wire       rx_fifo_empty,
    input  wire [3:0] fifo_thresh,
    input  wire [4:0] rx_fifo_count,
    output reg  [7:0] irq_set,

    // Power mode
    input  wire [1:0] pwr_mode
);

    // -----------------------------------------------------------------------
    // TX enable gate — set on I2C STOP, cleared when FIFO drains
    // Matches TI's gUartTxReady flag in while(1) loop
    // -----------------------------------------------------------------------
    reg tx_enable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_enable <= 1'b0;
        end else begin
            if (i2c_stop && !tx_fifo_empty)
                tx_enable <= 1'b1;          // STOP received — start draining
            else if (tx_fifo_empty)
                tx_enable <= 1'b0;          // fully drained — go idle
        end
    end

    // -----------------------------------------------------------------------
    // TX drain pipeline (only runs when tx_enable=1)
    // Cycle 0: rd_en=1 → FIFO increments rd_ptr, rd_data valid next cycle
    // Cycle 1: uart_tx_data loaded, uart_tx_valid=1
    // -----------------------------------------------------------------------
    reg tx_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_fifo_rd_en <= 1'b0;
            uart_tx_data  <= 8'h00;
            uart_tx_valid <= 1'b0;
            tx_pending    <= 1'b0;
        end else begin
            tx_fifo_rd_en <= 1'b0;
            uart_tx_valid <= 1'b0;

            if (tx_pending) begin
                uart_tx_data  <= tx_fifo_rd_data;
                uart_tx_valid <= 1'b1;
                tx_pending    <= 1'b0;
            end else if (tx_enable && !tx_fifo_empty && uart_tx_ready) begin
                tx_fifo_rd_en <= 1'b1;
                tx_pending    <= 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // RX fill: UART RX bytes → RX FIFO
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_fifo_wr_en   <= 1'b0;
            rx_fifo_wr_data <= 8'h00;
        end else begin
            rx_fifo_wr_en <= 1'b0;
            if (uart_rx_valid && !rx_fifo_full) begin
                rx_fifo_wr_en   <= 1'b1;
                rx_fifo_wr_data <= uart_rx_data;
            end
        end
    end

    // -----------------------------------------------------------------------
    // IRQ set pulses (1-clk wide → reg_file irq_stat via irq_set)
    // bit0=RXRDY  bit1=RXFULL  bit2=TXEMPTY  bit4=OVRN(tx overflow)
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_set <= 8'h00;
        end else begin
            irq_set <= 8'h00;
            if (rx_fifo_count >= {1'b0, fifo_thresh}) irq_set[0] <= 1'b1;
            if (rx_fifo_full)                          irq_set[1] <= 1'b1;
            if (tx_fifo_empty && uart_tx_ready)        irq_set[2] <= 1'b1;
            if (tx_fifo_full)                          irq_set[4] <= 1'b1;
        end
    end

endmodule
