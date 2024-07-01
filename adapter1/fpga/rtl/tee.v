`default_nettype none

module tee (
    input wire clk,

    // Parallel Channel "B"...
    output reg [7:0] b_bus_in,
    output reg b_bus_in_parity,
    input wire [7:0] b_bus_out,
    input wire b_bus_out_parity,

    input wire b_operational_out,
    output reg b_request_in,
    input wire b_hold_out,
    input wire b_select_out,
    output reg b_select_in,
    input wire b_address_out,
    output reg b_operational_in,
    output reg b_address_in,
    input wire b_command_out,
    output reg b_status_in,
    output reg b_service_in,
    input wire b_service_out,
    input wire b_suppress_out,

    // Parallel Channel "A"...
    input wire [7:0] a_bus_in,
    input wire a_bus_in_parity,
    output reg [7:0] a_bus_out,
    output reg a_bus_out_parity,

    output reg a_operational_out,
    input wire a_request_in,
    output reg a_hold_out,
    output reg a_select_out,
    input wire a_select_in,
    output reg a_address_out,
    input wire a_operational_in,
    input wire a_address_in,
    output reg a_command_out,
    input wire a_status_in,
    input wire a_service_in,
    output reg a_service_out,
    output reg a_suppress_out,

    // Device...
    input wire [7:0] bus_in,
    input wire bus_in_parity,
    output reg [7:0] bus_out,
    output reg bus_out_parity,

    output reg operational_out,
    input wire request_in,
    output reg hold_out,
    output reg address_out,
    input wire operational_in,
    input wire address_in,
    output reg command_out,
    input wire status_in,
    input wire service_in,
    output reg service_out,
    output reg suppress_out,

    output reg selection_x,
    input wire selection_y
);
    parameter PRIORITY = 1'b1;
    parameter BYPASS = 1'b0;

    always @(posedge clk)
    begin
        b_bus_in <= a_bus_in | bus_in;
        b_bus_in_parity <= a_bus_in_parity | bus_in_parity;
        b_request_in <= a_request_in | request_in;
        b_select_in <= !PRIORITY && !BYPASS ? selection_y : a_select_in;
        b_operational_in <= a_operational_in | operational_in;
        b_address_in <= a_address_in | address_in;
        b_status_in <= a_status_in | status_in;
        b_service_in <= a_service_in | service_in;

        a_bus_out <= b_bus_out;
        a_bus_out_parity <= b_bus_out_parity;
        a_operational_out <= b_operational_out;
        a_hold_out <= b_hold_out;
        a_select_out <= PRIORITY && !BYPASS ? selection_y : b_select_out;
        a_address_out <= b_address_out;
        a_command_out <= b_command_out;
        a_service_out <= b_service_out;
        a_suppress_out <= b_suppress_out;

        bus_out <= b_bus_out;
        bus_out_parity <= b_bus_out_parity;
        operational_out <= b_operational_out;
        hold_out <= b_hold_out;
        address_out <= b_address_out;
        command_out <= b_command_out;
        service_out <= b_service_out;
        suppress_out <= b_suppress_out;

        selection_x <= !BYPASS ? (PRIORITY ? b_select_out : a_select_in) : 1'b0;
    end
endmodule
