`timescale 1ns/1ps
// =============================================================================
// reg_file.v — 16-byte configuration register file (v3, TI error code pattern)
//
// New in v3 (from TI SWRA796A reference):
//   0x0B ERR_CODE — sticky error register, write-1-to-clear
//   Bit encoding (mirrors TI error_codes enum):
//     [0] UART frame error       (was UART_FRAMING_ERROR)
//     [1] UART parity error      (was UART_PARITY_ERROR)
//     [2] UART overrun           (was UART_OVERRUN_ERROR)
//     [3] RX FIFO overflow       (was I2C_TARGET_RXFIFO_OVERFLOW)
//     [4] TX FIFO underflow      (was I2C_TARGET_TXFIFO_UNDERFLOW)
//     [5] RX buffer overflow     (was DATA_BUFFER_OVERFLOW)
//     [7:6] reserved
//
// 0x0A STATUS — combinational live datapath view (added in v2)
// 0x09 IRQ_STAT — write-1-to-clear interrupt flags
// 0x0E CHIP_ID = 0xB5, 0x0F REV = 0x10 — hardwired read-only
// =============================================================================
module reg_file (
    input  wire        clk,
    input  wire        rst_n,

    // Write port
    input  wire        wr_en,
    input  wire [3:0]  wr_addr,
    input  wire [7:0]  wr_data,

    // Read port (combinational)
    input  wire [3:0]  rd_addr,
    output reg  [7:0]  rd_data,

    // Decoded config outputs
    output wire [15:0] baud_div,
    output wire [7:0]  uart_cfg,
    output wire [7:0]  uart_flow,
    output wire [6:0]  i2c_addr,
    output wire [7:0]  i2c_cfg,
    output wire [3:0]  fifo_thresh,
    output wire [7:0]  irq_en,
    output wire [7:0]  pwr_ctrl,

    // IRQ status — write-1-to-clear
    input  wire [7:0]  irq_set,
    output wire [7:0]  irq_stat,

    // Error code inputs (TI pattern: sticky flags, W1C)
    input  wire        err_uart_frame,   // from uart_rx frame_err
    input  wire        err_uart_parity,  // from uart_rx parity_err
    input  wire        err_uart_overrun, // from control_fsm rx_fifo_full during uart_rx_valid
    input  wire        err_rxfifo_ovf,   // RX FIFO was full when UART byte arrived
    input  wire        err_txfifo_udf,   // TX FIFO underflow (read when empty)
    input  wire        err_buf_ovf,      // TX FIFO was full when I2C byte arrived
    output wire [7:0]  err_code,         // live readable error status

    // Live STATUS signals (v2: combinational window into datapath)
    input  wire        status_i2c_busy,
    input  wire        status_uart_tx_busy,
    input  wire        status_tx_fifo_full,
    input  wire        status_tx_fifo_empty,
    input  wire        status_rx_fifo_full,
    input  wire        status_rx_data_rdy
);

    reg [7:0] r [0:15];

    // Error sticky register (0x0B) — OR-set by hardware, W1C by software
    reg [7:0] err_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r[0]  <= 8'hD9; r[1]  <= 8'h01;
            r[2]  <= 8'h03; r[3]  <= 8'h00;
            r[4]  <= 8'h48; r[5]  <= 8'h01;
            r[6]  <= 8'h08; r[7]  <= 8'h00;
            r[8]  <= 8'h00;
            r[9]  <= 8'h00;
            r[10] <= 8'h00;   // STATUS placeholder — avoids undriven warning in synthesis
            // 0x0B ERR_CODE handled separately below
            r[11] <= 8'h00;
            r[12] <= 8'h01; r[13] <= 8'h00;
            r[14] <= 8'hB5; r[15] <= 8'h10;
            err_reg <= 8'h00;
        end else begin
            // IRQ_STAT: OR new bits, then W1C mask
            r[9] <= (r[9] | irq_set) &
                    ~(wr_en && (wr_addr == 4'h9) ? wr_data : 8'h00);

            // ERR_CODE (0x0B): sticky set from hardware, W1C from software
            // Same pattern as TI's gErrorStatus — hardware OR-sets bits,
            // software clears by writing 1 to the relevant bit
            err_reg <= (err_reg |
                        {2'b00,
                         err_buf_ovf,
                         err_txfifo_udf,
                         err_rxfifo_ovf,
                         err_uart_overrun,
                         err_uart_parity,
                         err_uart_frame}) &
                       ~(wr_en && (wr_addr == 4'hB) ? wr_data : 8'h00);

            // R/W registers
            if (wr_en) case (wr_addr)
                4'h0: r[0]  <= wr_data;
                4'h1: r[1]  <= wr_data;
                4'h2: r[2]  <= wr_data;
                4'h3: r[3]  <= wr_data;
                4'h4: r[4]  <= wr_data;
                4'h5: r[5]  <= wr_data;
                4'h6: r[6]  <= wr_data;
                4'h8: r[8]  <= wr_data;
                4'hC: r[12] <= wr_data;
                default: ;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // STATUS register (0x0A) — combinational live view
    // -----------------------------------------------------------------------
    wire [7:0] status_live = {
        2'b00,
        status_rx_fifo_full,
        status_tx_fifo_full,
        status_tx_fifo_empty,
        status_i2c_busy,
        status_uart_tx_busy,
        status_rx_data_rdy
    };

    // Read mux — STATUS and ERR_CODE are live/registered, not in r[]
    always @(*) begin
        case (rd_addr)
            4'hA:    rd_data = status_live;
            4'hB:    rd_data = err_reg;
            default: rd_data = r[rd_addr];
        endcase
    end

    assign baud_div    = {r[1], r[0]};
    assign uart_cfg    = r[2];
    assign uart_flow   = r[3];
    assign i2c_addr    = r[4][6:0];
    assign i2c_cfg     = r[5];
    assign fifo_thresh = r[6][3:0];
    assign irq_en      = r[8];
    assign irq_stat    = r[9];
    assign pwr_ctrl    = r[12];
    assign err_code    = err_reg;

endmodule
