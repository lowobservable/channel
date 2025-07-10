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

// The channel out protocol module translates the parallel channel sequences
// to the bus and tag signals.
//
// This module supports multi-plexing (TODO: what is the definition of this,
// multiple devices SELECTED? or multiple devices ACTIVE etc.) by reselecting
// devices but this module does not maintain the state of multiple devices.
module channel_out_protocol (
    input wire clk,
    input wire reset,

    // TODO: input wire [1:0] config_type, // selector vs byte mux bs block mux

    // A connection begins at the time 'select out' rises at the control unit
    // for the purpose of executing any sequence or sequences
    // The connection is considered to be ended when 'operational in' is dropped.
    //output reg connected,

    // 2222 1111 1111 11
    // 3210 9876 5432 1098 7654 3210
    // ---- ---- ---- ---- ---- ----
    // ...0   1h 0000 0000 0000 0000 - Select Requestor  -> Status | Data | Error
    // ...1   1h AAAA AAAA CCCC CCCC - Initial Selection -> Status | Error
    //        2h       Chaining -> H - Accept Status     -> Ack | Error
    // ...0   3h                     - Stack Status      -> Ack | Error
    // ...1   3h                     - Suppress Status   -> Ack | Error
    //        4h                     - Accept Data       -> Ack | Error
    //        5h                     - Stop              -> Ack | Error
    //                                 ??? receive
    //        7h AAAA AAAA DDDD DDDD - Send Data         -> Ack | Status | Error
    //        8h AAAA AAAA           - Selective Reset   -> Ack | Error
    input wire [23:0] in_tdata,
    input wire in_tvalid,
    output reg in_tready,

    //      0000                     - Ack ("null")
    //        1h AAAA AAAA SSSS SSSS - Status
    //        2h AAAA AAAA DDDD DDDD - Data
    // 1111 1111 EEEE EEEE           - Error
    output reg [23:0] out_tdata,
    output reg out_tvalid,
    input wire out_tready,

    output wire request,

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
    output reg a_suppress_out
);
    parameter CLOCKS_PER_100_NS = 5; // 50 MHz clock period is 20 ns

    parameter SYSTEM_RESET_DURATION_100_NS = 60; // 6 μs, reduce this for tests
    parameter BUS_OUT_SKEW_DELAY_100_NS = 1; // 100 ns
    parameter ADDRESS_BUS_OUT_SKEW_DELAY_100_NS = 3; // 250 ns
    parameter HOLD_OUT_DELAY_100_NS = 40; // 4 μs, reduce this for tests
    parameter SELECT_OUT_IN_TIMEOUT_100_NS = 144; // 14.4 μs

    localparam ERROR_INVALID_IN = 8'h01;
    localparam ERROR_ADDRESS_NOT_OPERATIONAL = 8'h02;
    localparam ERROR_INVALID_SHORT_BUSY_STATUS = 8'h03;
    localparam ERROR_TIMEOUT = 8'hff;

    localparam STATE_SYSTEM_RESET = 0;
    localparam STATE_READY = 1;
    localparam STATE_WAIT = 2;
    localparam STATE_INITIAL_SELECTION_1 = 3;
    localparam STATE_INITIAL_SELECTION_2 = 4;
    localparam STATE_INITIAL_SELECTION_3 = 5;
    localparam STATE_INITIAL_SELECTION_4 = 6;
    localparam STATE_INITIAL_SELECTION_5 = 7;

    reg [7:0] state = STATE_SYSTEM_RESET;
    reg [7:0] next_state;
    reg [15:0] state_timer = 0;

// vvv
    reg [7:0] address;
    reg [7:0] next_address;
    reg [7:0] command;
    reg [7:0] next_command;
// ^^^

    reg next_in_tready = 0;
    reg [23:0] next_out_tdata;
    reg next_out_tvalid = 0;

    wire bus_in_parity_valid;

    assign bus_in_parity_valid = (~^a_bus_in == a_bus_in_parity); // Odd parity

    reg [7:0] next_bus_out;
    reg next_operational_out;
    reg next_hold_out;
    reg next_select_out;
    reg next_address_out;
    reg next_command_out;
    reg next_service_out;
    reg next_suppress_out;

    reg [7:0] hold_out_delay = 0;

    always @(posedge clk)
    begin
        if (a_hold_out)
        begin
            hold_out_delay = HOLD_OUT_DELAY_100_NS * CLOCKS_PER_100_NS;
        end
        else if (hold_out_delay > 0)
        begin
            hold_out_delay = hold_out_delay - 1;
        end
    end

    always @(*)
    begin
        next_state = state;

        next_address = address;
        next_command = command;

        next_in_tready = 0;
        next_out_tdata = out_tdata;
        next_out_tvalid = 0;

        next_bus_out = a_bus_out;
        next_operational_out = 0;
        next_hold_out = 0;
        next_select_out = 0;
        next_address_out = 0;
        next_command_out = 0;
        next_service_out = 0;
        next_suppress_out = 0;

        case (state)
            STATE_SYSTEM_RESET:
            begin
                // SPEC: To ensure a proper reset, 'operational out' and 'suppress
                // out' are down concurrently for at least 6 microseconds.
                if (state_timer == SYSTEM_RESET_DURATION_100_NS * CLOCKS_PER_100_NS)
                begin
                    next_state = STATE_READY;
                end
            end

            STATE_READY:
            begin
                next_in_tready = 1;

                next_operational_out = 1;

                // Leave bus out low when idle to reduce driver current.
                //
                // TODO: Compute parity when needed then we could leave that
                // low here too.
                next_bus_out = 8'b0;

                if (in_tready && in_tvalid)
                begin
                    next_in_tready = 0;

                    case (in_tdata[23:16])
                        8'h11:
                        begin
                            next_address = in_tdata[15:8];
                            next_command = in_tdata[7:0];

                            next_state = STATE_INITIAL_SELECTION_1;
                        end

                        default:
                        begin
                            next_out_tdata = out_error(ERROR_INVALID_IN);
                            next_out_tvalid = 1;

                            next_state = STATE_WAIT;
                        end
                    endcase
                end
            end

            STATE_WAIT:
            begin
                next_out_tvalid = 1;

                next_operational_out = 1;

                if (out_tready && out_tvalid)
                begin
                    next_out_tvalid = 0;

                    next_state = STATE_READY;
                end
            end

            STATE_INITIAL_SELECTION_1:
            begin
                next_bus_out = address;
                next_operational_out = 1;

                // SPEC: 'Address out' rises at least 250 nanoseconds after the
                // I/O-device address is placed on 'bus out' or at least 250
                // nanoseconds after the rise of 'operational out', whichever
                // occurs later. 'Address out' is down for at least 250 nanoseconds
                // before its rise for I/O-device selection.
                if (state_timer == ADDRESS_BUS_OUT_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                begin
                    next_state = STATE_INITIAL_SELECTION_2;
                end
            end

            STATE_INITIAL_SELECTION_2:
            begin
                next_bus_out = address;
                next_operational_out = 1;

                // SPEC: Address out' can rise for device selection only when
                // 'select out' (or 'hold out'), 'select in', 'status in', and
                // 'operational in' are down at the channel.
                //
                // SPEC: To prevent overlapping of interface sequences [...]:
                // 'Select out' is not raised until all inbound signals for the
                // preceding sequence are in a down state.
                //
                // SPEC: Once 'hold out' drops, it does not rise for at least 4
                // microseconds in general system configurations. The minimum
                // downtime of this signal may be optionally adjusted at
                // installation time to a minimum of 2 microseconds to handle
                // high-speed channel configurations.
                if (!a_operational_in && !a_status_in && !a_service_in && hold_out_delay == 0)
                begin
                    next_state = STATE_INITIAL_SELECTION_3;
                end
            end

            STATE_INITIAL_SELECTION_3:
            begin
                next_bus_out = address;
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;
                next_address_out = 1;

                if (a_status_in)
                begin
                    next_state = STATE_INITIAL_SELECTION_4;
                end
                else if (a_operational_in)
                begin
                    // ...
                end
                else if (a_select_in)
                begin
                    next_out_tdata = out_error(ERROR_ADDRESS_NOT_OPERATIONAL);
                    next_out_tvalid = 1;

                    next_state = STATE_WAIT;
                end
                else if (state_timer == SELECT_OUT_IN_TIMEOUT_100_NS * CLOCKS_PER_100_NS)
                begin
                    next_out_tdata = out_error(ERROR_TIMEOUT);
                    next_out_tvalid = 1;

                    next_state = STATE_WAIT;
                end
            end

            STATE_INITIAL_SELECTION_4:
            begin
                next_operational_out = 1;
                next_address_out = 1;

                // SPEC: During execution of the short-busy sequence, the control
                // unit presents status of either (1) busy and status modifier,
                // (2) busy, status modifier, and control-unit end, or (3) busy.
                // Presentation of any other status condition by the control unit
                // or device may cause an error condition to be recognized.
                if (a_bus_in[4])
                begin
                    next_out_tdata = out_status(a_bus_in);
                end
                else
                begin
                    next_out_tdata = out_error(ERROR_INVALID_SHORT_BUSY_STATUS);
                end

                next_state = STATE_INITIAL_SELECTION_5;
            end

            STATE_INITIAL_SELECTION_5:
            begin
                next_operational_out = 1;
                next_address_out = 1;

                if (!a_status_in)
                begin
                    next_out_tvalid = 1;

                    next_state = STATE_WAIT;
                end
            end
        endcase
    end

    always @(posedge clk)
    begin
        state <= next_state;

        state_timer <= state_timer + 1;

        if (state != next_state)
        begin
            state_timer <= 0;
        end

        address <= next_address;
        command <= next_command;

        in_tready <= next_in_tready;
        out_tdata <= next_out_tdata;
        out_tvalid <= next_out_tvalid;

        a_bus_out <= next_bus_out;
        a_bus_out_parity <= ~^next_bus_out; // Odd parity
        a_operational_out <= next_operational_out;
        a_hold_out <= next_hold_out;
        a_select_out <= next_select_out;
        a_address_out <= next_address_out;
        a_command_out <= next_command_out;
        a_service_out <= next_service_out;
        a_suppress_out <= next_suppress_out;

        if (reset)
        begin
            state <= STATE_SYSTEM_RESET;
            state_timer <= 0;

            in_tready <= 0;
            out_tvalid <= 0;
        end
    end

    assign request = a_request_in;

    function [23:0] out_error (
        input [7:0] code
    );
    begin
        out_error = { 8'hff, code, state };
    end
    endfunction

    function [23:0] out_status (
        input [7:0] status
    );
    begin
        out_status = { 8'h01, status, 8'h00 };
    end
    endfunction
endmodule
