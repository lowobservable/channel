`default_nettype none

`include "assert.v"

`timescale 10ns / 1ns

module axi_mm_channel_out_tb;
    reg clk = 0;

    reg channel_reset = 1;

    wire [7:0] bus_in;
    wire bus_in_parity;
    wire [7:0] bus_out;
    wire bus_out_parity;
    wire operational_out;
    wire request_in;
    wire hold_out;
    wire select_out;
    wire select_in;
    wire address_out;
    wire operational_in;
    wire address_in;
    wire command_out;
    wire status_in;
    wire service_in;
    wire service_out;
    wire suppress_out;

    axi_mm_channel_out #(
        .CLOCKS_PER_100_NS(5)
    ) channel (
        .aclk(clk),
        .aresetn(!channel_reset),

        // ...

        .a_bus_in(bus_in),
        .a_bus_in_parity(bus_in_parity),
        .a_bus_out(bus_out),
        .a_bus_out_parity(bus_out_parity),
        .a_operational_out(operational_out),
        .a_request_in(request_in),
        .a_hold_out(hold_out),
        .a_select_out(select_out),
        .a_select_in(select_in),
        .a_address_out(address_out),
        .a_operational_in(operational_in),
        .a_address_in(address_in),
        .a_command_out(command_out),
        .a_status_in(status_in),
        .a_service_in(service_in),
        .a_service_out(service_out),
        .a_suppress_out(suppress_out)
    );

    wire terminator;

    reg cu_mock_busy = 0;
    reg cu_mock_short_busy = 0;
    reg [15:0] cu_mock_limit = 0;

    mock_cu #(
        .ADDRESS(8'h1a)
    ) cu (
        .clk(clk),

        .b_bus_in(bus_in),
        .b_bus_in_parity(bus_in_parity),
        .b_bus_out(bus_out),
        .b_bus_out_parity(bus_out_parity),
        .b_operational_out(operational_out),
        .b_request_in(request_in),
        .b_hold_out(hold_out),
        .b_select_out(select_out),
        .b_select_in(select_in),
        .b_address_out(address_out),
        .b_operational_in(operational_in),
        .b_address_in(address_in),
        .b_command_out(command_out),
        .b_status_in(status_in),
        .b_service_in(service_in),
        .b_service_out(service_out),
        .b_suppress_out(suppress_out),

        .a_bus_in(8'b0),
        .a_bus_in_parity(1'b0),
        .a_bus_out(),
        .a_bus_out_parity(),
        .a_operational_out(),
        .a_request_in(1'b0),
        .a_hold_out(),
        .a_select_out(terminator),
        .a_select_in(terminator),
        .a_address_out(),
        .a_operational_in(1'b0),
        .a_address_in(1'b0),
        .a_command_out(),
        .a_status_in(1'b0),
        .a_service_in(1'b0),
        .a_service_out(),
        .a_suppress_out(),

        .mock_busy(cu_mock_busy),
        .mock_short_busy(cu_mock_short_busy),
        .mock_limit(cu_mock_limit)
    );

    initial
    begin
        forever
        begin
            #1 clk = ~clk;
        end
    end

    initial
    begin
        $dumpfile("axi_mm_channel_out_tb.vcd");
        $dumpvars(0, axi_mm_channel_out_tb);

        #200;

        $finish;
    end
endmodule
