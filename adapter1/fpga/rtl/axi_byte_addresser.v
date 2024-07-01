`default_nettype none

module axi_byte_addresser (
    input wire [31:0] addr_in,

    output wire [31:0] addr_out,
    output reg [7:0] strb,

    input wire [63:0] data_in,
    output reg [7:0] data_out
);
    always @(*)
    begin
        case (addr_in[2:0])
            0:
                strb = 8'b00000001;

            1:
                strb = 8'b00000010;

            2:
                strb = 8'b00000100;

            3:
                strb = 8'b00001000;

            4:
                strb = 8'b00010000;

            5:
                strb = 8'b00100000;

            6:
                strb = 8'b01000000;

            7:
                strb = 8'b10000000;
        endcase
    end

    assign addr_out = { addr_in[31:3], 3'b0 };

    always @(*)
    begin
        case (addr_in[2:0])
            0:
                data_out = data_in[7:0];

            1:
                data_out = data_in[15:8];

            2:
                data_out = data_in[23:16];

            3:
                data_out = data_in[31:24];

            4:
                data_out = data_in[39:32];

            5:
                data_out = data_in[47:40];

            6:
                data_out = data_in[55:48];

            7:
                data_out = data_in[63:56];
        endcase
    end
endmodule
