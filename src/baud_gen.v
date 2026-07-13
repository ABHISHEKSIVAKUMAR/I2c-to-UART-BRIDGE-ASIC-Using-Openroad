`timescale 1ns/1ps
// baud_gen.v — Programmable baud rate generator
// baud_tick pulses 1 clk every DIV clk cycles
// baud = clk_sys / DIV
module baud_gen #(parameter DIV_WIDTH = 16)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [DIV_WIDTH-1:0]  div,
    output reg                   baud_tick
);
    reg [DIV_WIDTH-1:0] cnt;
    wire [DIV_WIDTH-1:0] div_safe = (div == 0) ? 1 : div;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin cnt <= 0; baud_tick <= 0; end
        else if (cnt >= div_safe - 1) begin cnt <= 0; baud_tick <= 1; end
        else begin cnt <= cnt + 1; baud_tick <= 0; end
    end
endmodule
