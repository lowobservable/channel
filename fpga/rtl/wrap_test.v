`default_nettype none

module wrap_test (
    input wire clk,

    input wire [31:0] test_driver,
    output reg [31:0] test_receiver,

    output reg frontend_enable,

    // Parallel Channel "A"...
    input wire [7:0] a_bus_in,
    input wire a_bus_in_parity,
    output reg [7:0] a_bus_out,
    output reg a_bus_out_parity,
    input wire a_mark_0_in,
    output reg a_mark_0_out,

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
    input wire a_data_in,
    output reg a_data_out,
    input wire a_disconnect_in,
    input wire a_metering_in,
    output reg a_metering_out,
    output reg a_clock_out
);
    always @(posedge clk)
    begin
        frontend_enable <= test_driver[31];

        // L to R:
        // - Bus Out P
        // - Bus In P
        // - Bus Out 0
        // - Bus In 0
        // - Bus Out 1
        // - Bus In 1
        // - Bus Out 2
        // - Bus In 2
        // - Bus Out 3
        // - Bus In 3
        // - Bus Out 4
        // - Bus In 4
        // - Bus Out 5
        // - Bus In 5
        // - Bus Out 6
        // - Bus In 6
        // - Bus Out 7
        // - Bus In 7
        // - Mark 0 Out
        // - Mark 0 In
        //
        // - Operational In
        // - Clock Out
        // - Status In
        // - Metering Out
        // - Address In
        // - Metering In
        // - Service In
        // - Request In
        // - Select In
        // - Data In
        // - Select Out
        // - X
        // - Address Out
        // - Data Out
        // - Command Out
        // - Disconnect In
        // - Suppress Out
        // - Hold Out
        // - Service Out
        // - Operational Out

        a_bus_out <= { test_driver[11], test_driver[12], test_driver[13], test_driver[14], test_driver[15], test_driver[16], test_driver[17], test_driver[18] };
        a_bus_out_parity <= test_driver[19];
        a_mark_0_out <= test_driver[10];

        a_operational_out <= test_driver[0];
        a_hold_out <= test_driver[2]; // -> Select In
        a_select_out <= test_driver[7]; // -> Address In
        a_address_out <= test_driver[6]; // -> Metering In
        a_command_out <= test_driver[4]; // -> Request In
        a_service_out <= test_driver[1]; // -> Data In
        a_suppress_out <= test_driver[3]; // -> Disconnect In
        a_data_out <= test_driver[5]; // -> Service In
        a_metering_out <= test_driver[8]; // -> Status In
        a_clock_out <= test_driver[9]; // -> Operational In

        test_receiver <= {
            12'b0,
            a_bus_in_parity, a_bus_in[0], a_bus_in[1], a_bus_in[2], a_bus_in[3], a_bus_in[4], a_bus_in[5], a_bus_in[6], a_bus_in[7], a_mark_0_in,
            a_operational_in, a_status_in, a_address_in, a_metering_in, a_service_in, a_request_in, a_disconnect_in, a_select_in, a_data_in, 1'b0
        };
    end
endmodule
