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
module channel_out_protocol (
    input wire clk,
    input wire reset,

    // 2222 1111 1111 11
    // 3210 9876 5432 1098 7654 3210
    // ---- ---- ---- ---- ---- ----
    //    0   1h 0000 0000 0000 0000 - Select Requestor  -> Service | Status | Error
    // C  1   1h AAAA AAAA CCCC CCCC - Initial Selection -> Status | Error
    //
    // C      2h                     - Accept Status     -> Ack
    // ^---- Chaining (TODO)
    //        3h                     - Stack Status      -> Ack
    //
    //        4h DDDD DDDD           - Send Data         -> Ack
    //        5h                     - Accept Data       -> Ack
    //        6h                     - Stop              -> Ack
    //
    //        dh                     - Interface Disconnect -> Ack
    //        fh                     - Selective Reset   -> Ack
    input wire [23:0] in_tdata,
    input wire in_tvalid,
    output reg in_tready,

    // 0000 0000                     - Ack ("null")
    // IS P   1h AAAA AAAA SSSS SSSS - Status
    // ^^ ^-- Parity valid
    // |+---- Short busy
    // +----- Initial status
    //    P   2h AAAA AAAA DDDD DDDD - Service
    //    ^-- Parity valid
    // 1111 1111 EEEE EEEE DDDD DDDD - Error
    output reg [23:0] out_tdata,
    output reg out_tvalid,
    input wire out_tready,

    input wire suppress_status,

    // TODO: The driver is currently responsible for lowering burst, to allow
    // the control unit to disconnect, when the connection is complete such as
    // when initial selection results in busy or a DE status is encountered.
    input wire burst,

    output reg connected,
    output reg request,

    // TODO: Ideally all errors could be reported through the AXI stream,
    // however that may require deferring errors while waiting on the driver to
    // receive a pending response or event. It's not clear to what extent an
    // error might be recoverable or what actions this module can, or should,
    // take to recover.
    //
    // NOTE: For now, errors will be reported immediately and the driver should
    // reset this module to recover.
    output reg [15:0] error,

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
    parameter SUPPRESS_STATUS_DELAY_100_NS = 3; // 250 ns
    parameter SELECT_OUT_IN_TIMEOUT_100_NS = 144; // 14.4 μs

    localparam ERROR_INVALID_IN = 8'h01;
    localparam ERROR_ADDRESS_NOT_OPERATIONAL = 8'h02;
    localparam ERROR_INITIAL_SELECTION_ADDRESS_MISMATCH = 8'h06;
    localparam ERROR_TIMEOUT = 8'hff;

    localparam STATE_SYSTEM_RESET = 0;
    localparam STATE_IDLE = 1;
    localparam STATE_CONNECTED = 2;
    localparam STATE_WAIT = 3;
    localparam STATE_ERROR = 4;
    localparam STATE_INITIAL_SELECTION_1 = 5;
    localparam STATE_INITIAL_SELECTION_2 = 6;
    localparam STATE_INITIAL_SELECTION_3 = 7;
    localparam STATE_INITIAL_SELECTION_4 = 8;
    localparam STATE_INITIAL_SELECTION_5 = 9;
    localparam STATE_INITIAL_SELECTION_6 = 10;
    localparam STATE_INITIAL_SELECTION_7 = 11;
    localparam STATE_INITIAL_SELECTION_8 = 12;
    localparam STATE_INITIAL_SELECTION_9 = 13;
    localparam STATE_INITIAL_SELECTION_10 = 14;
    localparam STATE_INITIAL_SELECTION_11 = 15;
    localparam STATE_INITIAL_SELECTION_12 = 16;
    localparam STATE_INITIAL_SELECTION_13 = 17;
    localparam STATE_INITIAL_SELECTION_14 = 18;
    localparam STATE_INITIAL_SELECTION_15 = 19;
    localparam STATE_INITIAL_SELECTION_16 = 20;
    localparam STATE_SELECT_REQUESTOR_1 = 21;
    localparam STATE_SELECT_REQUESTOR_2 = 22;
    localparam STATE_SELECT_REQUESTOR_3 = 23;
    localparam STATE_SELECT_REQUESTOR_4 = 24;
    localparam STATE_SELECT_REQUESTOR_5 = 25;
    localparam STATE_SELECT_REQUESTOR_6 = 26;
    localparam STATE_SELECT_REQUESTOR_7 = 27;
    localparam STATE_DATA_TRANSFER_1 = 28;
    localparam STATE_DATA_TRANSFER_2 = 29;
    localparam STATE_DATA_TRANSFER_3 = 30;
    localparam STATE_DATA_TRANSFER_4 = 31;
    localparam STATE_DATA_TRANSFER_5 = 32;
    localparam STATE_DATA_TRANSFER_6 = 33;
    localparam STATE_DATA_TRANSFER_7 = 34;
    localparam STATE_ENDING_1 = 35;
    localparam STATE_ENDING_2 = 36;
    localparam STATE_ENDING_3 = 37;
    localparam STATE_ENDING_4 = 38;
    localparam STATE_ENDING_5 = 39;
    localparam STATE_ENDING_6 = 40;

    reg [7:0] state = STATE_SYSTEM_RESET;
    reg [7:0] next_state;
    reg [15:0] state_timer = 0;

    reg next_in_tready = 0;
    reg [23:0] next_out_tdata;
    reg next_out_tvalid = 0;

    reg burst_valid;
    reg [7:0] address;
    reg [7:0] next_address;
    reg [7:0] command;
    reg [7:0] next_command;
    reg [7:0] data;
    reg [7:0] next_data;
    reg next_connected;
    reg next_request;
    reg ending;
    reg next_ending;
    reg [15:0] next_error;

    wire bus_in_parity_valid;

    // TODO: 3174 parity in for status byte does not appear to be valid, parity
    // looks to be constantly high... is parity only set for data?
    //
    // assign bus_in_parity_valid = (~^a_bus_in == a_bus_in_parity); // Odd parity
    assign bus_in_parity_valid = 1;

    reg [7:0] next_bus_out;
    reg next_operational_out;
    reg next_hold_out;
    reg next_select_out;
    reg next_address_out;
    reg next_command_out;
    reg next_service_out;
    reg next_suppress_out;

    // vvv
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

    reg [7:0] suppress_status_delay = 0;

    always @(posedge clk)
    begin
        if (!a_suppress_out)
        begin
            suppress_status_delay <= SUPPRESS_STATUS_DELAY_100_NS * CLOCKS_PER_100_NS;
        end
        else if (suppress_status_delay > 0)
        begin
            suppress_status_delay <= suppress_status_delay - 1;
        end
    end

    reg operational_in_violation;
    reg prev_operational_in;

    always @(posedge clk)
    begin
        operational_in_violation <= 0;

        // TODO: operational in can't just go up and down!!!

        // SPEC: 'Operational in' rises only when the incoming 'select out'
        // to the control unit is up.
        //
        // SPEC: Operational in' drops only after 'select out' drops.
        if (a_operational_in && !prev_operational_in)
        begin
            if (!a_select_out)
            begin
                $display("TODO: Operational in violation 1");
            end
        end
        else if (!a_operational_in && prev_operational_in)
        begin
            if (a_select_out)
            begin
                $display("TODO: Operational in violation 2");
            end
        end

        prev_operational_in <= a_operational_in;
    end
    // ^^^

    always @(*)
    begin
        next_state = state;

        next_in_tready = 0;
        next_out_tdata = out_tdata;
        next_out_tvalid = 0;

        next_address = address;
        next_command = command;
        next_data = data;
        next_connected = 0;
        next_request = a_request_in;
        next_ending = ending;
        next_error = error;

        // Leave bus out low when idle to reduce driver current.
        //
        // TODO: Compute parity when needed then we could leave that low here
        // too.
        next_bus_out = 8'b0;

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
                next_request = 0;

                // SPEC: To ensure a proper reset, 'operational out' and
                // 'suppress out' are down concurrently for at least
                // 6 microseconds.
                if (state_timer == SYSTEM_RESET_DURATION_100_NS * CLOCKS_PER_100_NS)
                begin
                    next_state = STATE_IDLE;
                end
            end

            STATE_IDLE:
            begin
                next_in_tready = 1;

                next_operational_out = 1;
                next_suppress_out = suppress_status;

                next_ending = 0;

                // TODO: Protocol violation check

                if (in_tready && in_tvalid)
                begin
                    next_in_tready = 0;

                    case (in_tdata[23:16])
                        8'h11: // Initial Selection
                        begin
                            next_address = in_tdata[15:8];
                            next_command = in_tdata[7:0];

                            next_state = STATE_INITIAL_SELECTION_1;
                        end

                        8'h01: // Select Requestor
                        begin
                            next_state = STATE_SELECT_REQUESTOR_1;
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

            STATE_CONNECTED:
            begin
                // TODO: Currently there are no requests supported while
                // selected, it is possible that selective reset will be
                // implemented here at some point.
                //
                // next_in_tready = 1;

                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;
                next_suppress_out = suppress_status && ending;

                next_connected = a_operational_in;

                // TODO: Protocol violation check

                if (!a_operational_in)
                begin
                    // if (in_tready && in_tvalid)
                    // begin
                    //     next_in_tready = 0;
                    //
                    //     $display("TODO: request is no longer valid");
                    //     $finish;
                    // end
                    // else
                    // begin
                    //     next_state = STATE_IDLE;
                    // end

                    next_state = STATE_IDLE;
                end
                // else if (in_tready && in_tvalid)
                // begin
                //     next_in_tready = 0;
                //
                //     $display("TODO: none implemented yet");
                //     $finish;
                // end
                else if (a_service_in && !a_select_in && !a_address_in && !a_status_in)
                begin
                    // TODO: if ending then this is a protocol violation
                    next_state = STATE_DATA_TRANSFER_1;
                end
                else if (a_status_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    next_state = STATE_ENDING_1;
                end
            end

            STATE_WAIT:
            begin
                next_out_tvalid = 1;

                next_operational_out = 1;
                next_suppress_out = a_suppress_out;

                // Preserve connection state while waiting on driver.
                if (connected)
                begin
                    next_hold_out = burst && burst_valid;
                    next_select_out = burst && burst_valid;

                    next_connected = connected;
                end

                // TODO: Protocol violation check

                if (out_tready && out_tvalid)
                begin
                    next_out_tvalid = 0;

                    if (a_operational_in)
                    begin
                        next_state = STATE_CONNECTED;
                    end
                    else
                    begin
                        next_state = STATE_IDLE;
                    end
                end
            end

            STATE_ERROR:
            begin
                // Nothing to do, for now...
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
                    protocol_violation;
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
                    protocol_violation;
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
                    protocol_violation;
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
                    next_connected = 1;

                    next_state = STATE_INITIAL_SELECTION_5;
                end
                else if (a_status_in && !a_operational_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    // Although 'operational in' is not raised during the short
                    // busy sequence, we'll consider this to be connected.
                    next_connected = 1;

                    next_state = STATE_INITIAL_SELECTION_14;
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
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_5:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;

                next_connected = 1;

                if (a_operational_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (a_address_in)
                    begin
                        next_state = STATE_INITIAL_SELECTION_6;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_6:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;

                next_connected = 1;

                if (a_operational_in && a_address_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (state_timer == BUS_IN_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_INITIAL_SELECTION_7;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_7:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;

                next_connected = 1;

                if (a_operational_in && a_address_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (!bus_in_parity_valid)
                    begin
                        protocol_violation;
                    end
                    else if (a_bus_in == address)
                    begin
                        next_state = STATE_INITIAL_SELECTION_8;
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
                else
                begin
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_8:
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
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                if (a_operational_in && a_address_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (state_timer == BUS_OUT_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_INITIAL_SELECTION_9;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_9:
            begin
                next_bus_out = command;
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;
                next_command_out = 1;

                next_connected = 1;

                if (a_operational_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (!a_address_in)
                    begin
                        next_state = STATE_INITIAL_SELECTION_10;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_10:
            begin
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                if (a_operational_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (a_status_in)
                    begin
                        next_state = STATE_INITIAL_SELECTION_11;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_11:
            begin
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                if (a_operational_in && a_status_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (state_timer == BUS_IN_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_INITIAL_SELECTION_12;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_12:
            begin
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                if (a_operational_in && a_status_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    next_out_tdata = out_status(a_bus_in, bus_in_parity_valid, 1, 0);

                    next_state = STATE_INITIAL_SELECTION_13;
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_13:
            begin
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                // SPEC: If the channel accepts the initial status, it responds
                // by raising 'service out', allowing the control unit to drop
                // 'status in'. If the channel does not accept the initial
                // status, it responds by raising 'command out', allowing the
                // control unit to drop 'status in'.
                //
                // NOTE: Initial status is always accepted here, it is assumed
                // that the driver can always handle initial status.
                next_service_out = 1;

                next_connected = 1;

                if (!operational_in_violation && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (!a_status_in)
                    begin
                        next_connected = a_operational_in;

                        // Out data set by previous state.
                        next_out_tvalid = 1;

                        next_state = STATE_WAIT;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_14:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;
                next_address_out = 1;

                next_connected = 1;

                if (a_status_in && !a_operational_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (state_timer == BUS_IN_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_INITIAL_SELECTION_15;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_15:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;
                next_address_out = 1;

                next_connected = 1;

                if (a_status_in && !a_operational_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    // SPEC: During execution of the short-busy sequence, the
                    // control unit presents status of either (1) busy and
                    // status modifier, (2) busy, status modifier, and
                    // control-unit end, or (3) busy. Presentation of any other
                    // status condition by the control unit or device may cause
                    // an error condition to be recognized.
                    //
                    // NOTE: Validation should be performed by the driver.
                    next_out_tdata = out_status(a_bus_in, bus_in_parity_valid, 1, 1);

                    next_state = STATE_INITIAL_SELECTION_16;
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_INITIAL_SELECTION_16:
            begin
                next_operational_out = 1;
                next_address_out = 1;

                next_connected = 1;

                if (!a_operational_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (!a_status_in)
                    begin
                        next_connected = 0;

                        // Out data set by previous state.
                        next_out_tvalid = 1;

                        next_state = STATE_WAIT;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_SELECT_REQUESTOR_1:
            begin
                next_operational_out = 1;
                next_suppress_out = suppress_status;

                if (!a_operational_in && !a_select_in && !a_address_in && !a_status_in && !a_service_in)
                begin
                    // SPEC: Once 'hold out' drops, it does not rise for at
                    // least 4 microseconds in general system configurations.
                    //
                    // SPEC: ‘Suppress out' is up at least 250 nanoseconds
                    // before 'select out' rises at the control unit to ensure
                    // suppression of status.
                    if (hold_out_delay == 0 && (!suppress_status || suppress_status_delay == 0))
                    begin
                        next_state = STATE_SELECT_REQUESTOR_2;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_SELECT_REQUESTOR_2:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;
                next_suppress_out = suppress_status;

                // Don't consider 'address in' here, it can rise at the same
                // time as 'operational in', we'll look for that next.
                if (a_operational_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    next_connected = 1;

                    next_state = STATE_SELECT_REQUESTOR_3;
                end
                else if (a_select_in && !a_operational_in && !a_address_in && !a_status_in && !a_service_in)
                begin
                    next_out_tdata = out_error(ERROR_ADDRESS_NOT_OPERATIONAL);
                    next_out_tvalid = 1;

                    next_state = STATE_WAIT;
                end
                else if (!a_operational_in && !a_select_in && !a_status_in && !a_service_in)
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
                    protocol_violation;
                end
            end

            STATE_SELECT_REQUESTOR_3:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;

                next_connected = 1;

                if (a_operational_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (a_address_in)
                    begin
                        next_state = STATE_SELECT_REQUESTOR_4;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_SELECT_REQUESTOR_4:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;

                next_connected = 1;

                if (a_operational_in && a_address_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (state_timer == BUS_IN_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_SELECT_REQUESTOR_5;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_SELECT_REQUESTOR_5:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;

                next_connected = 1;

                if (a_operational_in && a_address_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (!bus_in_parity_valid)
                    begin
                        protocol_violation;
                    end
                    else
                    begin
                        next_address = a_bus_in;

                        next_state = STATE_SELECT_REQUESTOR_6;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_SELECT_REQUESTOR_6:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;
                next_command_out = 1;

                next_connected = 1;

                if (a_operational_in && !a_select_in && !a_status_in && !a_service_in)
                begin
                    if (!a_address_in)
                    begin
                        next_state = STATE_SELECT_REQUESTOR_7;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_SELECT_REQUESTOR_7:
            begin
                next_operational_out = 1;
                next_hold_out = 1;
                next_select_out = 1;

                next_connected = 1;

                if (a_operational_in && a_service_in && !a_select_in && !a_address_in && !a_status_in)
                begin
                    next_state = STATE_DATA_TRANSFER_1;
                end
                if (a_operational_in && a_status_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    next_state = STATE_ENDING_1;
                end
                else if (!a_operational_in || a_select_in || a_address_in)
                begin
                    protocol_violation;
                end
            end

            STATE_DATA_TRANSFER_1:
            begin
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                if (a_operational_in && a_service_in && !a_select_in && !a_address_in && !a_status_in)
                begin
                    // TODO: This module is unaware of the transfer direction
                    // which means this delay is unecessary in some cases.
                    if (state_timer == BUS_IN_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_DATA_TRANSFER_2;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_DATA_TRANSFER_2:
            begin
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                if (a_operational_in && a_service_in && !a_select_in && !a_address_in && !a_status_in)
                begin
                    // This module is unaware of the the transfer direction, if
                    // data is being requested the bus in parity is not required
                    // to be valid therefore validation must be done by the
                    // driver.
                    next_out_tdata = { 3'b0, bus_in_parity_valid, 4'h2, address, a_bus_in };
                    next_out_tvalid = 1;

                    next_state = STATE_DATA_TRANSFER_3;
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_DATA_TRANSFER_3:
            begin
                next_out_tvalid = 1;

                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                // TODO: Protocol violation check

                if (out_tready && out_tvalid)
                begin
                    next_out_tvalid = 0;

                    next_state = STATE_DATA_TRANSFER_4;
                end
            end

            STATE_DATA_TRANSFER_4:
            begin
                next_in_tready = 1;

                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                // TODO: Protocol violation check

                if (in_tready && in_tvalid)
                begin
                    next_in_tready = 0;

                    case (in_tdata[23:16])
                        8'h04: // Send Data
                        begin
                            next_data = in_tdata[15:8];

                            next_state = STATE_DATA_TRANSFER_5;
                        end

                        8'h05: // Accept Data
                        begin
                            next_state = STATE_DATA_TRANSFER_6;
                        end

                        8'h06: // Stop
                        begin
                            next_state = STATE_DATA_TRANSFER_7;
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

            STATE_DATA_TRANSFER_5:
            begin
                next_bus_out = data;
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                if (a_operational_in && a_service_in && !a_select_in && !a_address_in && !a_status_in)
                begin
                    if (state_timer == BUS_OUT_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_DATA_TRANSFER_6;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_DATA_TRANSFER_6:
            begin
                next_bus_out = data;
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;
                next_service_out = 1;

                next_connected = 1;

                if (!operational_in_violation && !a_select_in && !a_address_in && !a_status_in)
                begin
                    if (!a_service_in)
                    begin
                        next_out_tdata = 24'b0;
                        next_out_tvalid = 1;

                        next_state = STATE_WAIT;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_DATA_TRANSFER_7:
            begin
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;
                next_command_out = 1;

                next_connected = 1;

                if (!operational_in_violation && !a_select_in && !a_address_in && !a_status_in)
                begin
                    if (!a_service_in)
                    begin
                        next_out_tdata = 24'b0;
                        next_out_tvalid = 1;

                        next_state = STATE_WAIT;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_ENDING_1:
            begin
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;
                next_ending = 1;

                if (a_operational_in && a_status_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (state_timer == BUS_IN_SKEW_DELAY_100_NS * CLOCKS_PER_100_NS)
                    begin
                        next_state = STATE_ENDING_2;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_ENDING_2:
            begin
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                if (a_operational_in && a_status_in && !a_select_in && !a_address_in && !a_service_in)
                begin
                    next_out_tdata = { 3'b0, bus_in_parity_valid, 4'h1, address, a_bus_in };
                    next_out_tvalid = 1;

                    next_state = STATE_ENDING_3;
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_ENDING_3:
            begin
                next_out_tvalid = 1;

                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                // TODO: Protocol violation check

                if (out_tready && out_tvalid)
                begin
                    next_out_tvalid = 0;

                    next_state = STATE_ENDING_4;
                end
            end

            STATE_ENDING_4:
            begin
                next_in_tready = 1;

                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;

                next_connected = 1;

                // TODO: Protocol violation check

                if (in_tready && in_tvalid)
                begin
                    next_in_tready = 0;

                    case (in_tdata[23:16])
                        8'h02: // Accept Status
                        begin
                            next_state = STATE_ENDING_5;
                        end

                        8'h03: // Stack Status
                        begin
                            next_state = STATE_ENDING_6;
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

            STATE_ENDING_5:
            begin
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;
                next_service_out = 1;

                next_connected = 1;

                if (!operational_in_violation && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (!a_status_in)
                    begin
                        next_out_tdata = 24'b0;
                        next_out_tvalid = 1;

                        next_state = STATE_WAIT;
                    end
                end
                else
                begin
                    protocol_violation;
                end
            end

            STATE_ENDING_6:
            begin
                next_operational_out = 1;
                next_hold_out = burst && burst_valid;
                next_select_out = burst && burst_valid;
                next_command_out = 1;
                next_suppress_out = suppress_status;

                next_connected = 1;

                if (!operational_in_violation && !a_select_in && !a_address_in && !a_service_in)
                begin
                    if (!a_status_in)
                    begin
                        next_out_tdata = 24'b0;
                        next_out_tvalid = 1;

                        next_state = STATE_WAIT;
                    end
                end
                else
                begin
                    protocol_violation;
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

        in_tready <= next_in_tready;
        out_tdata <= next_out_tdata;
        out_tvalid <= next_out_tvalid;

        // The channel cannot force burst mode once 'select out' has dropped.
        burst_valid <= next_select_out;

        address <= next_address;
        command <= next_command;
        data <= next_data;
        connected <= next_connected;
        request <= next_request;
        ending <= next_ending;
        error <= next_error;

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

            error <= 16'b0;
        end
    end

    task protocol_violation;
    begin
        next_error = {
            a_operational_out,
            a_request_in,
            a_hold_out,
            a_select_out,
            a_select_in,
            a_address_out,
            a_operational_in,
            a_address_in,
            a_command_out,
            a_status_in,
            a_service_in,
            a_service_out,
            a_suppress_out,
            operational_in_violation,
            bus_in_parity_valid,
            1'b1
        };

        next_state = STATE_ERROR;
    end
    endtask

    function [23:0] out_status (
        input [7:0] status,
        input parity_valid,
        input initial_selection,
        input short_busy
    );
    begin
        out_status = { initial_selection, short_busy, 1'b0, parity_valid, 4'h1, address, status };
    end
    endfunction

    function [23:0] out_error (
        input [7:0] code
    );
    begin
        out_error = { 8'hff, code, state };
    end
    endfunction
endmodule
