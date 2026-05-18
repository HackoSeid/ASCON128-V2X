`timescale 1ns/1ps

module ascon_core #(
    parameter integer MAX_PT_BYTES = 400,
    parameter integer MAX_AD_BYTES = 400
)(
    input  wire                             clk,
    input  wire                             rst,
    input  wire                             start,

    // NEW: 1 = decrypt, 0 = encrypt
    input  wire                             decrypt,

    input  wire [127:0]                     key,
    input  wire [127:0]                     nonce,

    input  wire [MAX_PT_BYTES*8-1:0]        data_in,
    input  wire [15:0]                      pt_len_bytes,

    input  wire [MAX_AD_BYTES*8-1:0]        ad_in,
    input  wire [15:0]                      ad_len_bytes,

    // NEW: expected tag input (used for tag verification during decryption)
    input  wire [127:0]                     tag_in,

    output reg  [MAX_PT_BYTES*8-1:0]        data_out,
    output reg  [127:0]                     tag_out,
    output reg                              done,

    // NEW: 1 = tag matched (valid), 0 = tag mismatch (invalid) - only meaningful after done
    output reg                              tag_valid
);

    // ------------------------------------------------------------
    // Helper functions
    // ------------------------------------------------------------
    `include "ascon_helpers.vh"

    // ------------------------------------------------------------
    // FSM states
    // ------------------------------------------------------------
    localparam IDLE          = 4'd0;
    localparam INIT_PERM     = 4'd1;
    localparam INIT_KEY_XOR  = 4'd2;
    localparam AD_ABSORB     = 4'd3;
    localparam AD_PERM       = 4'd4;
    localparam DOMAIN_SEP    = 4'd5;
    localparam PT_PROC       = 4'd6;
    localparam PT_PERM       = 4'd7;
    localparam FINAL_KEY_XOR = 4'd8;
    localparam FINAL_PERM    = 4'd9;
    localparam TAG_GEN       = 4'd10;
    localparam DONE_ST       = 4'd11;

    // Extra padding states for empty/full-block edge cases
    localparam AD_PAD_ABSORB = 4'd12; // we are on the last AD block and its exactly 16 bytes.
    localparam AD_PAD_PERM   = 4'd13;
    localparam PT_PAD_PROC   = 4'd14; // Same logic here but for PT.

    // ------------------------------------------------------------
    // Main control/state registers
    // ------------------------------------------------------------
    reg [3:0] state;

    // ASCON state
    reg [63:0] x0, x1, x2, x3, x4;

    // Stored input buffers
    reg [MAX_PT_BYTES*8-1:0] data_reg;
    reg [MAX_AD_BYTES*8-1:0] ad_reg;
    reg [15:0]               pt_len_reg;
    reg [15:0]               ad_len_reg;

    // Private key - divided into words to fit the 5-states naturally
    reg [63:0] k0, k1;

    // Round control
    reg [3:0] round_ctr; //  what permutation round are we on? 
    reg [7:0] rc; // Round constant.

    // Index of the current block being processed
    reg [7:0] ad_block_idx;
    reg [7:0] pt_block_idx;

    // NEW: store decrypt mode at start so it stays stable throughout operation
    reg decrypt_reg;

    // ------------------------------------------------------------
    // One ASCON round reused every cycle
    // ------------------------------------------------------------
    wire [63:0] x0_round, x1_round, x2_round, x3_round, x4_round;

    ascon_round round_inst (
        .x0_in(x0),
        .x1_in(x1),
        .x2_in(x2),
        .x3_in(x3),
        .x4_in(x4),
        .rc(rc),
        .x0_out(x0_round),
        .x1_out(x1_round),
        .x2_out(x2_round),
        .x3_out(x3_round),
        .x4_out(x4_round)
    );

    // ------------------------------------------------------------
    // Current block extraction
    // ------------------------------------------------------------
    wire [127:0] curr_ad_block_w;
    wire [127:0] curr_pt_block_w;

    assign curr_ad_block_w = ad_reg[(ad_block_idx*128) +: 128];
    assign curr_pt_block_w = data_reg[(pt_block_idx*128) +: 128];

    // ------------------------------------------------------------
    // Calculate number of 16-byte blocks needed (ceil division by 16) + adds a case where value = 0:
    // ------------------------------------------------------------
    wire [15:0] total_ad_blocks_w;
    wire [15:0] total_pt_blocks_w;

    assign total_ad_blocks_w = (ad_len_reg == 0) ? 16'd0 : ((ad_len_reg + 16'd15) >> 4);
    assign total_pt_blocks_w = (pt_len_reg == 0) ? 16'd0 : ((pt_len_reg + 16'd15) >> 4);

    // ------------------------------------------------------------
    // Current byte offset = idx * 16
    // ------------------------------------------------------------
    wire [15:0] ad_offset_bytes_w;
    wire [15:0] pt_offset_bytes_w;

    assign ad_offset_bytes_w = {4'd0, ad_block_idx, 4'd0};
    assign pt_offset_bytes_w = {4'd0, pt_block_idx, 4'd0};

    // ------------------------------------------------------------
    // Remaining bytes in current block, length - offset
    // ------------------------------------------------------------
    wire [15:0] ad_remaining_bytes_w;
    wire [15:0] pt_remaining_bytes_w;

    assign ad_remaining_bytes_w = ad_len_reg - ad_offset_bytes_w;
    assign pt_remaining_bytes_w = pt_len_reg - pt_offset_bytes_w;

    // ------------------------------------------------------------
    // Actual length of current block
    // 16 for full block, otherwise remaining bytes
    // ------------------------------------------------------------
    wire [4:0] curr_ad_len_w;
    wire [4:0] curr_pt_len_w;

    assign curr_ad_len_w = (ad_remaining_bytes_w >= 16) ? 5'd16 : ad_remaining_bytes_w[4:0];
    assign curr_pt_len_w = (pt_remaining_bytes_w >= 16) ? 5'd16 : pt_remaining_bytes_w[4:0];

    // ------------------------------------------------------------
    // Last block flags, checkes if we are on the last block.
    // ------------------------------------------------------------
    wire is_last_ad_block_w;
    wire is_last_pt_block_w;

    assign is_last_ad_block_w = (total_ad_blocks_w != 0) && (ad_block_idx == total_ad_blocks_w - 1);
    assign is_last_pt_block_w = (total_pt_blocks_w != 0) && (pt_block_idx == total_pt_blocks_w - 1);

    // ------------------------------------------------------------
    // Datapath helpers
    // rate = {x1, x0}
    // ------------------------------------------------------------
    wire [127:0] rate_w;
    wire [127:0] ad_pad_w;
    wire [127:0] pt_ct_full_w;
    wire [127:0] pt_ct_keep_w;
    wire [127:0] pt_pad_w;
    wire [127:0] next_rate_partial_w;

    // Padding-only block used when AD/PT length is 0 or exactly full-block aligned
    wire [127:0] pad_only_w;
    wire [127:0] next_rate_pad_only_w;

    // NEW: decryption datapath helpers
    // During decryption: output = rate XOR ciphertext (same XOR as encryption, symmetric)
    // For partial block decryption: state is updated with rate XOR pad(plaintext)
    // where plaintext = keep_low_bytes(rate XOR ciphertext)
    wire [127:0] next_rate_dec_partial_w;

    assign rate_w              = {x1, x0};
    assign ad_pad_w            = pad_low_bytes_128(curr_ad_block_w, curr_ad_len_w);
    assign pt_ct_full_w        = rate_w ^ curr_pt_block_w;
    assign pt_ct_keep_w        = keep_low_bytes_128(pt_ct_full_w, curr_pt_len_w);
    assign pt_pad_w            = pad_low_bytes_128(curr_pt_block_w, curr_pt_len_w);
    assign next_rate_partial_w = rate_w ^ pt_pad_w;

    assign pad_only_w          = pad_low_bytes_128(128'd0, 5'd0);
    assign next_rate_pad_only_w = rate_w ^ pad_only_w;

    // NEW: for partial decryption block, pad the recovered plaintext (pt_ct_keep_w)
    // and XOR with rate to get the correct next state
    assign next_rate_dec_partial_w = rate_w ^ pad_low_bytes_128(pt_ct_keep_w, curr_pt_len_w);

    // ------------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------------
    // all Values are reset to 0.
    always @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            done         <= 1'b0;
            data_out     <= {(MAX_PT_BYTES*8){1'b0}};
            tag_out      <= 128'd0;
            tag_valid    <= 1'b0;

            x0 <= 64'd0;
            x1 <= 64'd0;
            x2 <= 64'd0;
            x3 <= 64'd0;
            x4 <= 64'd0;

            data_reg     <= {(MAX_PT_BYTES*8){1'b0}};
            ad_reg       <= {(MAX_AD_BYTES*8){1'b0}};
            pt_len_reg   <= 16'd0;
            ad_len_reg   <= 16'd0;

            k0 <= 64'd0;
            k1 <= 64'd0;

            round_ctr    <= 4'd0;
            rc           <= 8'd0;

            ad_block_idx <= 8'd0;
            pt_block_idx <= 8'd0;

            decrypt_reg  <= 1'b0;

        end else begin
            case (state)

                // ============================================================
                // IDLE
                // ============================================================
                IDLE: begin
                    done      <= 1'b0;
                    tag_valid <= 1'b0;

                    if (start) begin
                        data_reg     <= data_in;
                        ad_reg       <= ad_in;
                        pt_len_reg   <= pt_len_bytes;
                        ad_len_reg   <= ad_len_bytes;

                        data_out     <= {(MAX_PT_BYTES*8){1'b0}};
                        tag_out      <= 128'd0;
                        tag_valid    <= 1'b0;

                        ad_block_idx <= 8'd0;
                        pt_block_idx <= 8'd0;

                        // NEW: latch decrypt mode so it stays stable through the operation
                        decrypt_reg  <= decrypt;

                        k0 <= bswap64(key[127:64]);
                        k1 <= bswap64(key[63:0]);

                        // Initial state
                        x0 <= 64'h00001000808c0001;
                        x1 <= bswap64(key[127:64]);
                        x2 <= bswap64(key[63:0]);
                        x3 <= bswap64(nonce[127:64]);
                        x4 <= bswap64(nonce[63:0]);

                        round_ctr <= 4'd0;
                        rc        <= get_p12_rc(4'd0);
                        state     <= INIT_PERM;
                    end
                end

                // ============================================================
                // INIT_PERM 
                // ============================================================
                INIT_PERM: begin
                    x0 <= x0_round;
                    x1 <= x1_round;
                    x2 <= x2_round;
                    x3 <= x3_round;
                    x4 <= x4_round;

                    if (round_ctr == 4'd11) begin
                        round_ctr <= 4'd0;
                        state     <= INIT_KEY_XOR;
                    end else begin
                        round_ctr <= round_ctr + 4'd1;
                        rc        <= get_p12_rc(round_ctr + 4'd1);
                    end
                end

                // ============================================================
                // INIT_KEY_XOR
                // ============================================================
                INIT_KEY_XOR: begin
                    x3 <= x3 ^ k0;
                    x4 <= x4 ^ k1;

                    if (total_ad_blocks_w == 16'd0) begin
                        state <= DOMAIN_SEP;
                    end else begin
                        ad_block_idx <= 8'd0;
                        state        <= AD_ABSORB;
                    end
                end

                // ============================================================
                // AD_ABSORB
                // absorb current AD block into rate
                // AD processing is identical for encryption and decryption
                // ============================================================
                AD_ABSORB: begin
                    x1        <= x1 ^ ad_pad_w[127:64];
                    x0        <= x0 ^ ad_pad_w[63:0];
                    round_ctr <= 4'd0;
                    rc        <= get_p8_rc(4'd0);
                    state     <= AD_PERM;
                end

                // ============================================================
                // AD_PERM
                // run p8 after each AD block
                // ============================================================
                AD_PERM: begin
                    x0 <= x0_round;
                    x1 <= x1_round;
                    x2 <= x2_round;
                    x3 <= x3_round;
                    x4 <= x4_round;

                    if (round_ctr == 4'd7) begin
                        round_ctr <= 4'd0;

                        if (is_last_ad_block_w) begin
                            if (curr_ad_len_w == 5'd16) begin
                                state <= AD_PAD_ABSORB;
                            end else begin
                                state <= DOMAIN_SEP;
                            end
                        end else begin
                            ad_block_idx <= ad_block_idx + 8'd1;
                            state        <= AD_ABSORB;
                        end
                    end else begin
                        round_ctr <= round_ctr + 4'd1;
                        rc        <= get_p8_rc(round_ctr + 4'd1);
                    end
                end

                // ============================================================
                // AD_PAD_ABSORB
                // Extra AD padding block when AD length is exact multiple of 16
                // ============================================================
                AD_PAD_ABSORB: begin
                    x1        <= x1 ^ pad_only_w[127:64];
                    x0        <= x0 ^ pad_only_w[63:0];
                    round_ctr <= 4'd0;
                    rc        <= get_p8_rc(4'd0);
                    state     <= AD_PAD_PERM;
                end

                // ============================================================
                // AD_PAD_PERM
                // Run p8 after extra AD padding block
                // ============================================================
                AD_PAD_PERM: begin
                    x0 <= x0_round;
                    x1 <= x1_round;
                    x2 <= x2_round;
                    x3 <= x3_round;
                    x4 <= x4_round;

                    if (round_ctr == 4'd7) begin
                        round_ctr <= 4'd0;
                        state     <= DOMAIN_SEP;
                    end else begin
                        round_ctr <= round_ctr + 4'd1;
                        rc        <= get_p8_rc(round_ctr + 4'd1);
                    end
                end

                // ============================================================
                // DOMAIN_SEP
                // ============================================================
                DOMAIN_SEP: begin
                    x4 <= x4 ^ 64'h8000000000000000;

                    if (total_pt_blocks_w == 16'd0) begin
                        state <= PT_PAD_PROC;
                    end else begin
                        pt_block_idx <= 8'd0;
                        state        <= PT_PROC;
                    end
                end

                // ============================================================
                // PT_PROC
                // Encryption: output = rate XOR plaintext, update state with ciphertext
                // Decryption: output = rate XOR ciphertext (=plaintext), update state with ciphertext
                //
                // The key difference between encryption and decryption:
                //   Encryption state update (full):    x1,x0 <= ciphertext  (= rate XOR plaintext)
                //   Decryption state update (full):    x1,x0 <= ciphertext  (= the input data itself)
                //
                // For partial blocks:
                //   Encryption: state <= rate XOR pad(plaintext)
                //   Decryption: state <= rate XOR pad(recovered_plaintext)
                //               where recovered_plaintext = keep(rate XOR ciphertext)
                // ============================================================
                PT_PROC: begin
                    if (curr_pt_len_w == 5'd16) begin
                        // full block - output is rate XOR input (symmetric for both modes)
                        data_out[(pt_block_idx*128) +: 128] <= pt_ct_full_w;

                        if (decrypt_reg) begin
                            // Decryption: update state with ciphertext (the original input)
                            x1 <= curr_pt_block_w[127:64];
                            x0 <= curr_pt_block_w[63:0];
                        end else begin
                            // Encryption: update state with ciphertext (the XOR output)
                            x1 <= pt_ct_full_w[127:64];
                            x0 <= pt_ct_full_w[63:0];
                        end
                    end else begin
                        // partial final block
                        data_out[(pt_block_idx*128) +: 128] <= pt_ct_keep_w;

                        if (decrypt_reg) begin
                            // Decryption: state update uses pad(recovered_plaintext)
                            x1 <= next_rate_dec_partial_w[127:64];
                            x0 <= next_rate_dec_partial_w[63:0];
                        end else begin
                            // Encryption: state update uses pad(plaintext)
                            x1 <= next_rate_partial_w[127:64];
                            x0 <= next_rate_partial_w[63:0];
                        end
                    end

                    if (is_last_pt_block_w) begin
                        if (curr_pt_len_w == 5'd16) begin
                            round_ctr <= 4'd0;
                            rc        <= get_p8_rc(4'd0);
                            state     <= PT_PERM;
                        end else begin
                            state <= FINAL_KEY_XOR;
                        end
                    end else begin
                        round_ctr <= 4'd0;
                        rc        <= get_p8_rc(4'd0);
                        state     <= PT_PERM;
                    end
                end

                // ============================================================
                // PT_PERM
                // run p8 between PT blocks
                // ============================================================
                PT_PERM: begin
                    x0 <= x0_round;
                    x1 <= x1_round;
                    x2 <= x2_round;
                    x3 <= x3_round;
                    x4 <= x4_round;

                    if (round_ctr == 4'd7) begin
                        round_ctr <= 4'd0;

                        if (is_last_pt_block_w && curr_pt_len_w == 5'd16) begin
                            state <= PT_PAD_PROC;
                        end else begin
                            pt_block_idx <= pt_block_idx + 8'd1;
                            state        <= PT_PROC;
                        end
                    end else begin
                        round_ctr <= round_ctr + 4'd1;
                        rc        <= get_p8_rc(round_ctr + 4'd1);
                    end
                end

                // ============================================================
                // PT_PAD_PROC
                // Extra plaintext padding block for PT length 0 or multiple of 16
                // ============================================================
                PT_PAD_PROC: begin
                    x1 <= next_rate_pad_only_w[127:64];
                    x0 <= next_rate_pad_only_w[63:0];

                    state <= FINAL_KEY_XOR;
                end

                // ============================================================
                // FINAL_KEY_XOR
                // ============================================================
                FINAL_KEY_XOR: begin
                    x2        <= x2 ^ k0;
                    x3        <= x3 ^ k1;
                    round_ctr <= 4'd0;
                    rc        <= get_p12_rc(4'd0);
                    state     <= FINAL_PERM;
                end

                // ============================================================
                // FINAL_PERM
                // ============================================================
                FINAL_PERM: begin
                    x0 <= x0_round;
                    x1 <= x1_round;
                    x2 <= x2_round;
                    x3 <= x3_round;
                    x4 <= x4_round;

                    if (round_ctr == 4'd11) begin
                        round_ctr <= 4'd0;
                        state     <= TAG_GEN;
                    end else begin
                        round_ctr <= round_ctr + 4'd1;
                        rc        <= get_p12_rc(round_ctr + 4'd1);
                    end
                end

                // ============================================================
                // TAG_GEN
                // Encryption: compute and output the authentication tag
                // Decryption: compute tag and compare against tag_in
                //             tag_valid = 1 if they match, 0 if they don't
                // ============================================================
                TAG_GEN: begin
                    tag_out <= {bswap64(x3 ^ k0), bswap64(x4 ^ k1)};

                    if (decrypt_reg) begin
                        // NEW: verify received tag against computed tag
                        tag_valid <= ({bswap64(x3 ^ k0), bswap64(x4 ^ k1)} == tag_in) ? 1'b1 : 1'b0;
                    end else begin
                        // Encryption: tag_valid not meaningful, set high as convenience
                        tag_valid <= 1'b1;
                    end

                    state <= DONE_ST;
                end

                // ============================================================
                // DONE_ST
                // ============================================================
                DONE_ST: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule