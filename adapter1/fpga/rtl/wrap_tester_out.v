// Copyright (c) 2023, Andrew Kay
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

`default_nettype none

module wrap_tester_out (
    input wire clk,
    input wire enable,

    input wire [19:0] driver,
    output reg [19:0] receiver,

    // Parallel Channel "B"...
    output reg [7:0] b_bus_in,
    output reg b_bus_in_parity,
    input wire [7:0] b_bus_out,
    input wire b_bus_out_parity,
    output reg b_mark_0_in,
    input wire b_mark_0_out,

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
    output reg b_data_in,
    input wire b_data_out,
    output reg b_disconnect_in,
    output reg b_metering_in,
    input wire b_metering_out,
    input wire b_clock_out,

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
        if (enable)
        begin
            b_bus_in <= 8'b0;
            b_bus_in_parity <= 1'b0;
            b_mark_0_in <= 1'b0;
            b_request_in <= 1'b0;
            b_select_in <= b_select_out;
            b_operational_in <= 1'b0;
            b_address_in <= 1'b0;
            b_status_in <= 1'b0;
            b_service_in <= 1'b0;
            b_data_in <= 1'b0;
            b_disconnect_in <= 1'b0;
            b_metering_in <= 1'b0;

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

            a_bus_out_parity <= driver[19];
            a_bus_out <= driver[18:11];
            a_mark_0_out <= driver[10];
            a_clock_out <= driver[9]; // -> Operational In
            a_metering_out <= driver[8]; // -> Status In
            a_data_out <= driver[5]; // -> Service In
            a_suppress_out <= driver[3]; // -> Disconnect In
            a_service_out <= driver[1]; // -> Data In
            a_command_out <= driver[4]; // -> Request In
            a_address_out <= driver[6]; // -> Metering In
            a_select_out <= driver[7]; // -> Address In
            a_hold_out <= driver[2]; // -> Select In
            a_operational_out <= driver[0];

            receiver <= {
                a_bus_in_parity,
                a_bus_in,
                a_mark_0_in,
                a_operational_in,
                a_status_in,
                a_address_in,
                a_metering_in,
                a_service_in,
                a_request_in,
                a_disconnect_in,
                a_select_in,
                a_data_in,
                1'b0
            };
        end
        else
        begin
            b_bus_in <= a_bus_in;
            b_bus_in_parity <= a_bus_in_parity;
            b_mark_0_in <= a_mark_0_in;
            b_request_in <= a_request_in;
            b_select_in <= a_select_in;
            b_operational_in <= a_operational_in;
            b_address_in <= a_address_in;
            b_status_in <= a_status_in;
            b_service_in <= a_service_in;
            b_data_in <= a_data_in;
            b_disconnect_in <= a_disconnect_in;
            b_metering_in <= a_metering_in;

            a_bus_out <= b_bus_out;
            a_bus_out_parity <= b_bus_out_parity;
            a_mark_0_out <= b_mark_0_out;
            a_operational_out <= b_operational_out;
            a_hold_out <= b_hold_out;
            a_select_out <= b_select_out;
            a_address_out <= b_address_out;
            a_command_out <= b_command_out;
            a_service_out <= b_service_out;
            a_suppress_out <= b_suppress_out;
            a_data_out <= b_data_out;
            a_metering_out <= b_metering_out;
            a_clock_out <= b_clock_out;
        end
    end
endmodule
