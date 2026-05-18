`timescale 1ns/1ps

module ascon_kat_enc_dec_tb;

    localparam integer MAX_PT_BYTES = 64;
    localparam integer MAX_AD_BYTES = 64;

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

    integer errors;
    integer case_no;
    integer i;

    // Global cycle counter used for latency and throughput measurement
    integer cycle_counter;

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

    // 100 MHz clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Counts clock cycles during simulation.
    // At 100 MHz, one cycle = 10 ns.
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

        if (timeout >= 10000) begin
            $display("ERROR: timeout waiting for done");
            errors = errors + 1;
        end
    end
    endtask

    task run_kat_case;
        input [15:0] pt_len;
        input [15:0] ad_len;
        input [127:0] kat_key;
        input [127:0] kat_nonce;
        input [MAX_AD_BYTES*8-1:0] kat_ad;
        input [MAX_PT_BYTES*8-1:0] kat_pt;
        input [MAX_PT_BYTES*8-1:0] kat_ct;
        input [127:0] kat_tag;

        reg [MAX_PT_BYTES*8-1:0] mask;

        integer enc_start_cycle;
        integer enc_end_cycle;
        integer enc_cycles;
        real enc_throughput_mbps;

        integer dec_start_cycle;
        integer dec_end_cycle;
        integer dec_cycles;
        real dec_throughput_mbps;

    begin
        case_no = case_no + 1;
        mask = 0;

        for (i = 0; i < pt_len; i = i + 1)
            mask[i*8 +: 8] = 8'hFF;

        $display("------------------------------------------------------------");
        $display("KAT CASE %0d: PT=%0d bytes, AD=%0d bytes", case_no, pt_len, ad_len);

        key = kat_key;
        nonce = kat_nonce;
        ad_in = kat_ad;
        ad_len_bytes = ad_len;
        pt_len_bytes = pt_len;

        // ============================================================
        // ENCRYPTION KAT
        // ============================================================
        decrypt = 0;
        data_in = kat_pt;
        tag_in = 0;

        enc_start_cycle = cycle_counter;
        pulse_start();
        wait_done();
        enc_end_cycle = cycle_counter;

        enc_cycles = enc_end_cycle - enc_start_cycle;

        // Throughput = (plaintext bits * clock frequency MHz) / cycles
        // Frequency is 100 MHz because clk period is 10 ns.
        if (pt_len != 0)
            enc_throughput_mbps = (pt_len * 8.0 * 100.0) / enc_cycles;
        else
            enc_throughput_mbps = 0.0;

        if ((data_out & mask) !== (kat_ct & mask)) begin
            $display("ERROR ENC CT mismatch");
            $display("Expected CT = %h", kat_ct & mask);
            $display("Got CT      = %h", data_out & mask);
            errors = errors + 1;
        end else begin
            $display("KAT-ENC CT PASS");
        end

        if (tag_out !== kat_tag) begin
            $display("ERROR ENC TAG mismatch");
            $display("Expected TAG = %032h", kat_tag);
            $display("Got TAG      = %032h", tag_out);
            errors = errors + 1;
        end else begin
            $display("KAT-ENC TAG PASS");
        end

        $display("ENC cycles      = %0d", enc_cycles);
        $display("ENC throughput  = %0f Mbps", enc_throughput_mbps);

        // ============================================================
        // DECRYPTION KAT WITH CORRECT TAG
        // ============================================================
        decrypt = 1;
        data_in = kat_ct;
        tag_in = kat_tag;

        dec_start_cycle = cycle_counter;
        pulse_start();
        wait_done();
        dec_end_cycle = cycle_counter;

        dec_cycles = dec_end_cycle - dec_start_cycle;

        if (pt_len != 0)
            dec_throughput_mbps = (pt_len * 8.0 * 100.0) / dec_cycles;
        else
            dec_throughput_mbps = 0.0;

        if ((data_out & mask) !== (kat_pt & mask)) begin
            $display("ERROR DEC PT mismatch");
            $display("Expected PT = %h", kat_pt & mask);
            $display("Got PT      = %h", data_out & mask);
            errors = errors + 1;
        end else begin
            $display("KAT-DEC PT PASS");
        end

        if (tag_valid !== 1'b1) begin
            $display("ERROR DEC tag_valid should be 1");
            errors = errors + 1;
        end else begin
            $display("KAT-DEC TAG VALID PASS");
        end

        $display("DEC cycles      = %0d", dec_cycles);
        $display("DEC throughput  = %0f Mbps", dec_throughput_mbps);

        // ============================================================
        // DECRYPTION WITH CORRUPTED TAG
        // ============================================================
        decrypt = 1;
        data_in = kat_ct;
        tag_in = kat_tag ^ 128'h1;

        pulse_start();
        wait_done();

        if (tag_valid !== 1'b0) begin
            $display("ERROR corrupt tag was accepted");
            errors = errors + 1;
        end else begin
            $display("KAT-DEC CORRUPT TAG REJECTED PASS");
        end
    end
    endtask

    initial begin
        errors = 0;
        case_no = 0;

        reset_dut();

        // ============================================================
        // Lägg in KAT vectors här
        // OBS: data ligger low-byte first i din core/testbench.
        // Om hex från KAT är normal big-endian kan byteordning behöva vändas.
        // ============================================================

        // Count 1: PT=0 bytes, AD=0 bytes
        run_kat_case(
            16'd0,
            16'd0,
            128'h000102030405060708090A0B0C0D0E0F,
            128'h101112131415161718191A1B1C1D1E1F,
            512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
            512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
            512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
            128'h4F9C278211BEC9316BF68F46EE8B2EC6
        );

        // Count 17: PT=0 bytes, AD=16 bytes
        run_kat_case(
            16'd0,
            16'd16,
            128'h000102030405060708090A0B0C0D0E0F,
            128'h101112131415161718191A1B1C1D1E1F,
            512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003F3E3D3C3B3A39383736353433323130,
            512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
            512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
            128'hE4230CDB8330EE9DC0CFD7C7B346E6DC
        );

        // Count 529: PT=16 bytes, AD=0 bytes
        run_kat_case(
            16'd16,
            16'd0,
            128'h000102030405060708090A0B0C0D0E0F,
            128'h101112131415161718191A1B1C1D1E1F,
            512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
            512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002F2E2D2C2B2A29282726252423222120,
            512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000BBA297383172E8E3EAC56C24EEDEC3E8,
            128'h9EAA915C9DD3245D77048F24D46D27A7
        );

        // Count 1057: PT=32 bytes, AD=0 bytes
        run_kat_case(
            16'd32,
            16'd0,
            128'h000102030405060708090A0B0C0D0E0F,
            128'h101112131415161718191A1B1C1D1E1F,
            512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
            512'h00000000000000000000000000000000000000000000000000000000000000003F3E3D3C3B3A393837363534333231302F2E2D2C2B2A29282726252423222120,
            512'h0000000000000000000000000000000000000000000000000000000000000000C25466001F2D0F970703E8153EAA8960BBA297383172E8E3EAC56C24EEDEC3E8,
            128'hAAA5FA172CB9F07D07463CEFC7440BC1
        );

        $display("============================================================");
        if (errors == 0)
            $display("ALL KAT ENCRYPTION/DECRYPTION TESTS PASSED");
        else
            $display("KAT TEST FAILED: %0d errors", errors);
        $display("============================================================");

        $finish;
    end

endmodule