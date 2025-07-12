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
// This module supports multiplexing by reselecting devices but this module
// does not maintain the state of multiple devices.
module channel_out_protocol (
    input wire clk,
    input wire reset,

    // A connection begins at the time 'select out' rises at the control unit
    // for the purpose of executing any sequence or sequences The connection
    // is considered to be ended when 'operational in' is dropped.
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

    // 0000 0000                     - Ack ("null")
    //        1h AAAA AAAA SSSS SSSS - Status
    // P      2h AAAA AAAA DDDD DDDD - Data
    // ^-- Parity valid
    // 1111 1111 EEEE EEEE DDDD DDDD - Error
    output reg [23:0] out_tdata,
    output reg out_tvalid,
    input wire out_tready,

    output wire request,

    input wire channel_burst,

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
    parameter BUS_IN_SKEW_DELAY_100_NS = 1; // 100 ns
    parameter BUS_OUT_SKEW_DELAY_100_NS = 1; // 100 ns
    parameter ADDRESS_BUS_OUT_SKEW_DELAY_100_NS = 3; // 250 ns
    parameter ADDRESS_OUT_SELECT_OUT_DELAY_100_NS = 4; // 400 ns
    parameter HOLD_OUT_DELAY_100_NS = 40; // 4 μs, reduce this for tests
    parameter SELECT_OUT_IN_TIMEOUT_100_NS = 144; // 14.4 μs

    localparam ERROR_INVALID_IN = 8'h01;
    localparam ERROR_ADDRESS_NOT_OPERATIONAL = 8'h02;
    localparam ERROR_TAGS = 8'h03; // Protocol violations...
    localparam ERROR_PARITY = 8'h04;
    localparam ERROR_INVALID_SHORT_BUSY_STATUS = 8'h05;
    localparam ERROR_INITIAL_SELECTION_ADDRESS_MISMATCH = 8'h06;
    localparam ERROR_TIMEOUT = 8'hff;

    localparam STATE_SYSTEM_RESET = 0;
    localparam STATE_READY = 1;
    localparam STATE_WAIT = 2;
    localparam STATE_INITIAL_SELECTION_1 = 3;
    localparam STATE_INITIAL_SELECTION_2 = 4;
    localparam STATE_INITIAL_SELECTION_3 = 5;
    localparam STATE_INITIAL_SELECTION_4 = 6;
    localparam STATE_INITIAL_SELECTION_5 = 7;
    localparam STATE_INITIAL_SELECTION_6 = 8;
    localparam STATE_INITIAL_SELECTION_7 = 9;
    localparam STATE_INITIAL_SELECTION_8 = 10;
    localparam STATE_INITIAL_SELECTION_9 = 11;
    localparam STATE_INITIAL_SELECTION_10 = 12;
    localparam STATE_INITIAL_SELECTION_11 = 13;
    localparam STATE_INITIAL_SELECTION_12 = 14;
    localparam STATE_INITIAL_SELECTION_13 = 15;
    localparam STATE_INITIAL_SELECTION_14 = 16;
    localparam STATE_INITIAL_SELECTION_15 = 17;

    reg [7:0] state = STATE_SYSTEM_RESET;
    reg [7:0] next_state;
    reg [15:0] state_timer = 0;

    reg [7:0] address;
    reg [7:0] next_address;
    reg [7:0] command;
    reg [7:0] next_command;

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
            hold_out_delay <= HOLD_OUT_DELAY_100_NS * CLOCKS_PER_100_NS;
        end
        else if (hold_out_delay > 0)
        begin
            hold_out_delay <= hold_out_delay - 1;
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
                // SPEC: To ensure a proper reset, 'operational out' and
                // 'suppress out' are down concurrently for at least
                // 6 microseconds.
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

                if (!a_operational_in && !a_select_in && !a_address_in && !a_status_in && !a_service_in)
                begin
                    // SPEC: 'Address out' rises at least 250 nanoseconds after
                    // the I/O-device address is placed on 'bus out' or at least
                    // 250 nanoseconds after the rise of 'operational out',
                    // whichever occurs later. 'Address out' is down for at
                    // least 250 nanoseconds before its rise for I/O-device
                    // selection.
                    if (state_timer == ADDRESS_BUS_OUT_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_INITIAL_SELECTION_2;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_2:
            begin
                next_bus_out = address;
                next_operational_out = 1;

                if (!a_operational_in && !a_select_in && !a_address_in && !a_status_in && !a_service_in)
                begin
                    // SPEC: Once 'hold out' drops, it does not rise for at
                    // least 4 microseconds in general system configurations.
                    if (hold_out_delay == 0)
                    begin
                        next_state = STATE_INITIAL_SELECTION_3;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_3:
            begin
                next_bus_out = address;
                next_operational_out = 1;
                next_address_out = 1;

                if (!a_operational_in && !a_select_in && !a_address_in && !a_status_in && !a_service_in)
                begin
                    // SPEC: When an operation is being initiated by the channel,
                    // 'select out' is raised not less than 400 nanoseconds
                    // after the rise of 'address out', which indicates the
                    // address of the device being selected.
                    if (state_timer == ADDRESS_OUT_SELECT_OUT_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_INITIAL_SELECTION_4;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_4:
            begin
                next_bus_out = address;
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;
                next_address_out = 1;

                if (a_operational_in && !a_select_in && !a_address_in && !a_status_in && !a_service_in)
                begin
                    next_state = STATE_INITIAL_SELECTION_5;
                end
                else if (a_status_in && !a_operational_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    next_state = STATE_INITIAL_SELECTION_13;
                end
                else if (a_select_in && !a_operational_in && !a_address_in && !a_status_in && !a_service_in)
                begin
                    next_out_tdata = out_error(ERROR_ADDRESS_NOT_OPERATIONAL);
                    next_out_tvalid = 1;

                    next_state = STATE_WAIT;
                end
                else if (!a_operational_in && !a_select_in && !a_address_in && !a_status_in && !a_service_in)
                begin
                    if (state_timer == SELECT_OUT_IN_TIMEOUT_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_out_tdata = out_error(ERROR_TIMEOUT);
                        next_out_tvalid = 1;

                        next_state = STATE_WAIT;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_5:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;

                if (a_operational_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (a_address_in)
                    begin
                        next_state = STATE_INITIAL_SELECTION_6;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_6:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;

                if (a_operational_in && a_address_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (state_timer == BUS_IN_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        if (!bus_in_parity_valid)
                        begin
                            error_parity;
                        end
                        else if (a_bus_in == address)
                        begin
                            next_state = STATE_INITIAL_SELECTION_7;
                        end
                        else
                        begin
                            // NOTE: It's not clear what can, or should, be done
                            // when the address does not match.
                            next_out_tdata = out_error(ERROR_INITIAL_SELECTION_ADDRESS_MISMATCH);
                            next_out_tvalid = 1;

                            next_state = STATE_WAIT;
                        end
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_7:
            begin
                next_bus_out = command;
                next_operational_out = 1;

                // SPEC: 'Hold out' with 'select out' may drop any time after
                // 'address in' rises.
                //
                // SPEC: To provide a channel with a method of controlling the
                // duration of the connection, a control unit does not
                // disconnect from the I/O interface before ‘select out' ('hold
                // out') falls.
                next_hold_out = channel_burst;
                next_select_out = channel_burst;

                if (a_operational_in && a_address_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (state_timer == BUS_OUT_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_INITIAL_SELECTION_8;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_8:
            begin
                next_bus_out = command;
                next_operational_out = 1;
                next_hold_out = channel_burst;
                next_select_out = channel_burst;
                next_command_out = 1;

                if (a_operational_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (!a_address_in)
                    begin
                        next_state = STATE_INITIAL_SELECTION_9;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_9:
            begin
                next_operational_out = 1;
                next_hold_out = channel_burst;
                next_select_out = channel_burst;

                if (a_operational_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (a_status_in)
                    begin
                        next_state = STATE_INITIAL_SELECTION_10;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_10:
            begin
                next_operational_out = 1;
                next_hold_out = channel_burst;
                next_select_out = channel_burst;

                if (a_operational_in && a_status_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (state_timer == BUS_IN_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_INITIAL_SELECTION_11;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_11:
            begin
                next_operational_out = 1;
                next_hold_out = channel_burst;
                next_select_out = channel_burst;

                if (a_operational_in && a_status_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (!bus_in_parity_valid)
                    begin
                        error_parity;
                    end
                    else
                    begin
                        next_out_tdata = out_status(a_bus_in);

                        next_state = STATE_INITIAL_SELECTION_12;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_12:
            begin
                next_operational_out = 1;
                next_hold_out = channel_burst;
                next_select_out = channel_burst;

                // SPEC: If the channel accepts the initial status, it responds
                // by raising 'service out', allowing the control unit to drop
                // 'status in'. If the channel does not accept the initial
                // status, it responds by raising 'command out', allowing the
                // control unit to drop 'status in'.
                //
                // NOTE: Initial status is always accepted here, it is assumed
                // that the caller can always handle initial status.
                next_service_out = 1;

                if (a_operational_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (!a_status_in)
                    begin
                        next_out_tvalid = 1;

                        next_state = STATE_WAIT;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_13:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;
                next_address_out = 1;

                if (a_status_in && !a_operational_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (state_timer == BUS_IN_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_INITIAL_SELECTION_14;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_14:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;
                next_address_out = 1;

                if (a_status_in && !a_operational_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    // SPEC: During execution of the short-busy sequence, the
                    // control unit presents status of either (1) busy and
                    // status modifier, (2) busy, status modifier, and
                    // control-unit end, or (3) busy. Presentation of any other
                    // status condition by the control unit or device may cause
                    // an error condition to be recognized.
                    //
                    // NOTE: Only busy is checked here, additional validation
                    // should be performed by the caller.
                    if (!bus_in_parity_valid)
                    begin
                        error_parity;
                    end
                    else
                    begin
                        if (a_bus_in[4])
                        begin
                            next_out_tdata = out_status(a_bus_in);
                        end
                        else
                        begin
                            next_out_tdata = out_error(ERROR_INVALID_SHORT_BUSY_STATUS);
                        end

                        next_state = STATE_INITIAL_SELECTION_15;
                    end
                end
                else
                begin
                    error_tags;
                end
            end

            STATE_INITIAL_SELECTION_15:
            begin
                next_operational_out = 1;
                next_address_out = 1;

                if (!a_operational_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (!a_status_in)
                    begin
                        next_out_tvalid = 1;

                        next_state = STATE_WAIT;
                    end
                end
                else
                begin
                    error_tags;
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

    function [23:0] out_status (
        input [7:0] status
    );
    begin
        out_status = { 8'h01, address, status };
    end
    endfunction

    function [23:0] out_error (
        input [7:0] code
    );
    begin
        out_error = { 8'hff, code, state };
    end
    endfunction

    task error_tags;
    begin
        next_out_tdata = { 8'hff, ERROR_TAGS, { a_operational_in, a_select_in, a_request_in, 2'b0, a_address_in, a_status_in, a_service_in } };
        next_out_tvalid = 1;

        next_state = STATE_WAIT;
    end
    endtask

    task error_parity;
    begin
        next_out_tdata = { 8'hff, ERROR_PARITY, 8'h00 };
        next_out_tvalid = 1;

        next_state = STATE_WAIT;
    end
    endtask
endmodule
