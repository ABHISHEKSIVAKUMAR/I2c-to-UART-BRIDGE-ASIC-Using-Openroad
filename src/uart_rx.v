`timescale 1ns/1ps
// uart_rx.v — UART receiver, 16x oversampling, LSB first
// parity_err latched in PAR state, re-asserted with rx_valid in STOP1
module uart_rx (
    input  wire       clk, rst_n, baud_tick_x16,
    input  wire [1:0] parity_cfg, // 00=none 01=odd 10=even
    input  wire       stop2,
    input  wire       rx_in,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        frame_err,
    output reg        parity_err
);
    reg rx_r, rx_rr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rx_r<=1;rx_rr<=1; end
        else begin rx_r<=rx_in;rx_rr<=rx_r; end
    end
    localparam [2:0] IDLE=0,START=1,DATA=2,PAR=3,STOP1=4,STOP2S=5;
    reg [2:0] state;
    reg [3:0] tick_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;
    reg       parity_acc, parity_err_lat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE;tick_cnt<=0;bit_cnt<=7;shift_reg<=0;
            rx_data<=0;rx_valid<=0;frame_err<=0;parity_err<=0;
            parity_acc<=0;parity_err_lat<=0;
        end else begin
            rx_valid<=0; frame_err<=0; parity_err<=0;
            case (state)
                IDLE: if (!rx_rr) begin tick_cnt<=0; state<=START; end
                START: if (baud_tick_x16) begin
                    if (tick_cnt==7) begin
                        if (!rx_rr) begin tick_cnt<=0;bit_cnt<=7;parity_acc<=0;parity_err_lat<=0;state<=DATA; end
                        else state<=IDLE;
                    end else tick_cnt<=tick_cnt+1;
                end
                DATA: if (baud_tick_x16) begin
                    if (tick_cnt==15) begin
                        tick_cnt<=0;
                        shift_reg<={rx_rr,shift_reg[7:1]};
                        parity_acc<=parity_acc^rx_rr;
                        if (bit_cnt==0) state<=(parity_cfg==0)?STOP1:PAR;
                        else bit_cnt<=bit_cnt-1;
                    end else tick_cnt<=tick_cnt+1;
                end
                PAR: if (baud_tick_x16) begin
                    if (tick_cnt==15) begin
                        tick_cnt<=0;
                        case (parity_cfg)
                            2'b01: parity_err_lat<=~(parity_acc^rx_rr);
                            2'b10: parity_err_lat<= (parity_acc^rx_rr);
                            default: parity_err_lat<=0;
                        endcase
                        state<=STOP1;
                    end else tick_cnt<=tick_cnt+1;
                end
                STOP1: if (baud_tick_x16) begin
                    if (tick_cnt==15) begin
                        tick_cnt<=0; rx_data<=shift_reg; rx_valid<=1;
                        frame_err<=~rx_rr; parity_err<=parity_err_lat;
                        parity_err_lat<=0;
                        state<=stop2?STOP2S:IDLE;
                    end else tick_cnt<=tick_cnt+1;
                end
                STOP2S: if (baud_tick_x16) begin
                    if (tick_cnt==15) begin tick_cnt<=0; state<=IDLE; end
                    else tick_cnt<=tick_cnt+1;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
