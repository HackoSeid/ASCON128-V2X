`timescale 1ns/1ps

module ascon_throughput_tb;

    localparam integer MAX_PT_BYTES = 400;
    localparam integer MAX_AD_BYTES = 64;

    // 100 MHz clock
    localparam real CLK_FREQ_MHZ  = 100.0;
    localparam real CLK_PERIOD_NS = 10.0;

    // U280 post-synthesis / post-implementation power from Vivado
    // Use total power for total energy calculation.
    localparam real POWER_W = 3.23;

    reg clk, rst, start, decrypt;

    reg  [127:0] key;
    reg  [127:0] nonce;
    reg  [MAX_PT_BYTES*8-1:0] data_in;
    reg  [15:0] pt_len_bytes;
    reg  [MAX_AD_BYTES*8-1:0] ad_in;
    reg  [15:0] ad_len_bytes;
    reg  [127:0] tag_in;

    wire [MAX_PT_BYTES*8-1:0] data_out;
    wire [127:0] tag_out;
    wire done;
    wire tag_valid;

    integer cycle_counter;
    integer i;

    ascon_core #(
        .MAX_PT_BYTES(MAX_PT_BYTES),
        .MAX_AD_BYTES(MAX_AD_BYTES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .decrypt(decrypt),
        .key(key),
        .nonce(nonce),
        .data_in(data_in),
        .pt_len_bytes(pt_len_bytes),
        .ad_in(ad_in),
        .ad_len_bytes(ad_len_bytes),
        .tag_in(tag_in),
        .data_out(data_out),
        .tag_out(tag_out),
        .done(done),
        .tag_valid(tag_valid)
    );

    // 100 MHz clock: 5 ns high + 5 ns low = 10 ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (rst)
            cycle_counter <= 0;
        else
            cycle_counter <= cycle_counter + 1;
    end

    task reset_dut;
    begin
        rst = 1;
        start = 0;
        decrypt = 0;
        data_in = 0;
        ad_in = 0;
        tag_in = 0;
        pt_len_bytes = 0;
        ad_len_bytes = 0;
        cycle_counter = 0;
        #100;
        rst = 0;
        #20;
    end
    endtask

    task pulse_start;
    begin
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;
    end
    endtask

    task wait_done;
        integer timeout;
    begin
        timeout = 0;
        while (!done && timeout < 10000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 10000)
            $display("ERROR: timeout waiting for done");
    end
    endtask

    task run_perf_case;
        input [15:0] msg_bytes;

        integer start_cycle;
        integer end_cycle;
        integer cycles;

        real latency_us;
        real throughput_mbps;
        real msg_rate;
        real energy_uj;

    begin
        data_in = 0;
        ad_in = 0;

        for (i = 0; i < MAX_PT_BYTES; i = i + 1)
            data_in[i*8 +: 8] = i[7:0];

        for (i = 0; i < MAX_AD_BYTES; i = i + 1)
            ad_in[i*8 +: 8] = (8'hA0 + i[7:0]);

        pt_len_bytes = msg_bytes;
        ad_len_bytes = 16'd16;

        decrypt = 0;
        tag_in = 0;

        start_cycle = cycle_counter;
        pulse_start();
        wait_done();
        end_cycle = cycle_counter;

        cycles = end_cycle - start_cycle;

        latency_us      = (cycles * CLK_PERIOD_NS) / 1000.0;
        throughput_mbps = (msg_bytes * 8.0 * CLK_FREQ_MHZ) / cycles;
        msg_rate        = 1000000.0 / latency_us;
        energy_uj       = POWER_W * latency_us;

        $display("------------------------------------------------------------");
        $display("Msg Size (bytes) = %0d", msg_bytes);
        $display("Cycles           = %0d", cycles);
        $display("Latency (us)     = %0f", latency_us);
        $display("Throughput Mbps  = %0f", throughput_mbps);
        $display("Msg Rate msg/s   = %0f", msg_rate);
        $display("Energy (uJ)      = %0f", energy_uj);
    end
    endtask

    initial begin
        key   = 128'h000102030405060708090A0B0C0D0E0F;
        nonce = 128'h101112131415161718191A1B1C1D1E1F;

        reset_dut();

        $display("============================================================");
        $display("ASCON PERFORMANCE RESULTS ON U280 @ 100 MHz");
        $display("Power used for energy calculation = %0f W", POWER_W);
        $display("============================================================");

        run_perf_case(16);
        run_perf_case(20);
        run_perf_case(64);
        run_perf_case(128);
        run_perf_case(320);
        run_perf_case(400);

        $display("============================================================");
        $display("PERFORMANCE TEST COMPLETE");
        $display("============================================================");

        $finish;
    end

endmodule