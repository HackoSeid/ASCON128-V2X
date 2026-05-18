`timescale 1ns/1ps

module ascon_power_top_tb;

    reg clk;
    reg rst;

    wire done_o;
    wire [127:0] tag_o;
    wire [31:0] activity_o;

    ascon_power_top dut (
        .clk(clk),
        .rst(rst),
        .done_o(done_o),
        .tag_o(tag_o),
        .activity_o(activity_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // 100 MHz
    end

    initial begin
        $dumpfile("ascon_power_top.vcd");
        $dumpvars(0, ascon_power_top_tb);

        rst = 1'b1;
        #100;
        rst = 1'b0;

        #500000;
        $finish;
    end

endmodule