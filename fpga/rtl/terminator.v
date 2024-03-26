`default_nettype none

module terminator (
    input wire clk,

    input wire select_out,
    output reg select_in
);
    always @(posedge clk)
    begin
        select_in <= select_out;
    end
endmodule
