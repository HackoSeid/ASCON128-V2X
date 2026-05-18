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