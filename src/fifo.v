`timescale 1ns/1ps
// fifo.v — Synchronous FIFO, parameterised width/depth
// DEPTH must be power of 2. rd_data is combinational.
module fifo #(
    parameter WIDTH  = 8,
    parameter DEPTH  = 16,
    parameter ADDR_W = 4
)(
    input  wire             clk, rst_n,
    input  wire             wr_en,
    input  wire [WIDTH-1:0] wr_data,
    output wire             full, almost_full,
    input  wire             rd_en,
    output wire [WIDTH-1:0] rd_data,
    output wire             empty, almost_empty,
    output wire [ADDR_W:0]  count
);
    reg [WIDTH-1:0]  mem [0:DEPTH-1];
    reg [ADDR_W:0]   wr_ptr, rd_ptr;
    assign count        = wr_ptr - rd_ptr;
    assign full         = (count == DEPTH);
    assign empty        = (count == 0);
    assign almost_full  = (count >= DEPTH - 1);
    assign almost_empty = (count <= 1);
    assign rd_data      = mem[rd_ptr[ADDR_W-1:0]];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_ptr <= 0;
        else if (wr_en && !full) begin
            mem[wr_ptr[ADDR_W-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rd_ptr <= 0;
        else if (rd_en && !empty) rd_ptr <= rd_ptr + 1;
    end
endmodule
