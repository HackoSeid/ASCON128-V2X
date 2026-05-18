// These are the roundcounter constants for ASCON going from F0-4b, P8 has b4-4b
function [7:0] get_p12_rc;
    input [3:0] r;
    begin
        case (r)
            4'd0:  get_p12_rc = 8'hf0;
            4'd1:  get_p12_rc = 8'he1;
            4'd2:  get_p12_rc = 8'hd2;
            4'd3:  get_p12_rc = 8'hc3;
            4'd4:  get_p12_rc = 8'hb4;
            4'd5:  get_p12_rc = 8'ha5;
            4'd6:  get_p12_rc = 8'h96;
            4'd7:  get_p12_rc = 8'h87;
            4'd8:  get_p12_rc = 8'h78;
            4'd9:  get_p12_rc = 8'h69;
            4'd10: get_p12_rc = 8'h5a;
            4'd11: get_p12_rc = 8'h4b;
            default: get_p12_rc = 8'h00;
        endcase
    end
endfunction

function [7:0] get_p8_rc;
    input [3:0] r;
    begin
        case (r)
            4'd0:  get_p8_rc = 8'hb4;
            4'd1:  get_p8_rc = 8'ha5;
            4'd2:  get_p8_rc = 8'h96;
            4'd3:  get_p8_rc = 8'h87;
            4'd4:  get_p8_rc = 8'h78;
            4'd5:  get_p8_rc = 8'h69;
            4'd6:  get_p8_rc = 8'h5a;
            4'd7:  get_p8_rc = 8'h4b;
            default: get_p8_rc = 8'h00;
        endcase
    end
endfunction
// this function exists only to swap byte order incase its needed.
function [63:0] bswap64;
    input [63:0] x;
    begin
        bswap64 = {
            x[7:0],
            x[15:8],
            x[23:16],
            x[31:24],
            x[39:32],
            x[47:40],
            x[55:48],
            x[63:56]
        };
    end
endfunction
// this function is made for partial cipherblocks, zero'ing every value that isnt of use. 
function [127:0] keep_low_bytes_128;
    input [127:0] val;
    input [4:0]   nbytes;
    integer i;
    reg [127:0] tmp;
    begin
        tmp = 128'd0;
        for (i = 0; i < 16; i = i + 1) begin
            if (i < nbytes)
                tmp[i*8 +: 8] = val[i*8 +: 8];
        end
        keep_low_bytes_128 = tmp;
    end
endfunction
// After the last real value byte the next byte is 0x01. This is done for padding. Without padding ascon doesnt know when to stop.
function [127:0] pad_low_bytes_128;
    input [127:0] val;
    input [4:0]   nbytes;
    integer i;
    reg [127:0] tmp;
    begin
        tmp = 128'd0;
        for (i = 0; i < 16; i = i + 1) begin
            if (i < nbytes)
                tmp[i*8 +: 8] = val[i*8 +: 8];
        end
        if (nbytes < 16)
            tmp[nbytes*8 +: 8] = 8'h01;
        pad_low_bytes_128 = tmp;
    end
endfunction