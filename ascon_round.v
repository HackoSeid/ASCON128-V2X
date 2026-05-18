`timescale 1ns/1ps

module ascon_round (
    input  wire [63:0] x0_in,
    input  wire [63:0] x1_in,
    input  wire [63:0] x2_in,
    input  wire [63:0] x3_in,
    input  wire [63:0] x4_in,
    input  wire [7:0]  rc,

    output wire [63:0] x0_out,
    output wire [63:0] x1_out,
    output wire [63:0] x2_out,
    output wire [63:0] x3_out,
    output wire [63:0] x4_out
);
// this function is responsible for the rotation in Linear diffusion. Function is divided into 2 parts one shifting and one returning the "lost" bits back to the word.
    function [63:0] rotr64;
        input [63:0] value;
        input integer shift;
        begin
            rotr64 = (value >> shift) | (value << (64 - shift));
        end
    endfunction

    reg [63:0] x0, x1, x2, x3, x4;
    reg [63:0] y0, y1, y2, y3, y4;

    always @(*) begin
        x0 = x0_in;
        x1 = x1_in;
        x2 = x2_in;
        x3 = x3_in;
        x4 = x4_in;

        // 1. ADD ROUND CONSTANT
        x2 = x2 ^ {56'd0, rc};

        // 2. SUBSTITUTION LAYER (S-BOX)
        x0 = x0 ^ x4;
        x4 = x4 ^ x3;
        x2 = x2 ^ x1;

        y0 = x0;
        y1 = x1;
        y2 = x2;
        y3 = x3;
        y4 = x4;

        x0 = y0 ^ ((~y1) & y2);
        x1 = y1 ^ ((~y2) & y3);
        x2 = y2 ^ ((~y3) & y4);
        x3 = y3 ^ ((~y4) & y0);
        x4 = y4 ^ ((~y0) & y1);

        x1 = x1 ^ x0;
        x0 = x0 ^ x4;
        x3 = x3 ^ x2;
        x2 = ~x2;

        // 3. LINEAR DIFFUSION LAYER
        x0 = x0 ^ rotr64(x0, 19) ^ rotr64(x0, 28);
        x1 = x1 ^ rotr64(x1, 61) ^ rotr64(x1, 39);
        x2 = x2 ^ rotr64(x2,  1) ^ rotr64(x2,  6);
        x3 = x3 ^ rotr64(x3, 10) ^ rotr64(x3, 17);
        x4 = x4 ^ rotr64(x4,  7) ^ rotr64(x4, 41);
    end

    assign x0_out = x0;
    assign x1_out = x1;
    assign x2_out = x2;
    assign x3_out = x3;
    assign x4_out = x4;

endmodule