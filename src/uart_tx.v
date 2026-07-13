`timescale 1ns/1ps
// uart_tx.v — UART transmitter, LSB first
// 1 start + 8 data + optional parity + 1/2 stop bits
module uart_tx (
    input  wire       clk, rst_n, baud_tick,
    input  wire [1:0] parity_cfg, // 00=none 01=odd 10=even
    input  wire       stop2,
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output reg        tx_ready,
    output reg        tx_out
);
    localparam [2:0] IDLE=0,START=1,DATA=2,PAR=3,STOP1=4,STOP2S=5;
    reg [2:0] state;
    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;
    reg       parity_acc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE;tx_out<=1;tx_ready<=1;shift_reg<=0;bit_cnt<=0;parity_acc<=0;
        end else begin
            case (state)
                IDLE: begin
                    tx_out<=1; tx_ready<=1;
                    if (tx_valid && tx_ready) begin
                        shift_reg<=tx_data; parity_acc<=^tx_data;
                        tx_ready<=0; state<=START;
                    end
                end
                START:  if (baud_tick) begin tx_out<=0; bit_cnt<=7; state<=DATA; end
                DATA: if (baud_tick) begin
                    tx_out<=shift_reg[0]; shift_reg<={1'b0,shift_reg[7:1]};
                    if (bit_cnt==0) state<=(parity_cfg==0)?STOP1:PAR;
                    else bit_cnt<=bit_cnt-1;
                end
                PAR: if (baud_tick) begin
                    tx_out<=(parity_cfg==2'b01)?~parity_acc:parity_acc; state<=STOP1;
                end
                STOP1:  if (baud_tick) begin tx_out<=1; state<=stop2?STOP2S:IDLE; end
                STOP2S: if (baud_tick) begin tx_out<=1; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
