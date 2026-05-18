`timescale 1ns/1ps
// ports
module ascon_power_top (
    input  wire clk,
    input  wire rst,
    output wire done_o,
    output wire [127:0] tag_o,
    output wire [31:0] activity_o
);
    // these parameters are for power testing only.
    parameter integer MAX_PT_BYTES = 64;
    parameter integer MAX_AD_BYTES = 32;

    reg                             start;
    reg  [127:0]                    key;
    reg  [127:0]                    nonce;
    reg  [MAX_PT_BYTES*8-1:0]       data_in;
    reg  [15:0]                     pt_len_bytes;
    reg  [MAX_AD_BYTES*8-1:0]       ad_in;
    reg  [15:0]                     ad_len_bytes;
    //outputs from ascon core
    wire [MAX_PT_BYTES*8-1:0]       data_out;
    wire [127:0]                    tag_out;
    wire                            done;

    integer i;
    reg [31:0] hold_ctr;
    reg [1:0]  state;

    // small observable register so logic stays alive
    reg [31:0] activity_reg;
    // the wrappers own mini FSM 
    localparam S_LOAD  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_WAIT  = 2'd2;
    localparam S_HOLD  = 2'd3;

    // here is the connection to the real ascon_core feeding ascon_core with data.
    ascon_core #(
        .MAX_PT_BYTES(MAX_PT_BYTES),
        .MAX_AD_BYTES(MAX_AD_BYTES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .key(key),
        .nonce(nonce),
        .data_in(data_in),
        .pt_len_bytes(pt_len_bytes),
        .ad_in(ad_in),
        .ad_len_bytes(ad_len_bytes),
        .data_out(data_out),
        .tag_out(tag_out),
        .done(done),
        .decrypt(decrypt),
        .tag_in(tag_in),
        .tag_valid(tag_valid)
    );

    // Tie internal activity to external outputs, shows vivado that results are being used otherwise they get discarded.
    assign done_o     = done;
    assign tag_o      = tag_out;
    assign activity_o = activity_reg;

    //Values are reset before new ones are added. 
    always @(posedge clk) begin
        if (rst) begin
            start        <= 1'b0;
            key          <= 128'h000102030405060708090A0B0C0D0E0F;
            nonce        <= 128'h101112131415161718191A1B1C1D1E1F;
            data_in      <= {(MAX_PT_BYTES*8){1'b0}};
            ad_in        <= {(MAX_AD_BYTES*8){1'b0}};
            pt_len_bytes <= 16'd32;
            ad_len_bytes <= 16'd16;
            hold_ctr     <= 32'd0;
            state        <= S_LOAD;
            activity_reg <= 32'd0;
        end else begin
            // make some internal switching observable so vivado doesnt remove the logic
            activity_reg <= activity_reg ^ data_out[31:0] ^ tag_out[31:0] ^ {31'd0, done};

            case (state)
                // S_LOAD just 
                S_LOAD: begin
                    start <= 1'b0;

                    for (i = 0; i < MAX_PT_BYTES; i = i + 1)
                        data_in[i*8 +: 8] <= i[7:0];

                    for (i = 0; i < MAX_AD_BYTES; i = i + 1)
                        ad_in[i*8 +: 8] <= (8'hA0 + i[7:0]);

                    state <= S_START;
                end
                //Start signal sent to ascon_core
                S_START: begin
                    start <= 1'b1;
                    state <= S_WAIT;
                end
                // Wait until ASCON_CORE returns done = 1;
                S_WAIT: begin
                    start <= 1'b0;
                    if (done) begin
                        hold_ctr <= 32'd0;
                        state    <= S_HOLD;
                    end
                end
                // hold for 20 clockcycles before doing the same process again.
                S_HOLD: begin
                    if (hold_ctr == 32'd20) begin
                        hold_ctr <= 32'd0;
                        state    <= S_START;
                    end else begin
                        hold_ctr <= hold_ctr + 1;
                    end
                end

                default: begin
                    state <= S_LOAD;
                end
            endcase
        end
    end

endmodule