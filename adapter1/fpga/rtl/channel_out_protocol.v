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
    // ..00 0001 0000 0000 0000 0000 - Select Requestor  -> Status | Data | Error
    // ..01 0001 AAAA AAAA CCCC CCCC - Initial Selection -> Status | Error
    //      xxxx                   C - Accept Status     -> Ack | Error
    //      xxxx                     - Stack Status      -> Ack | Error
    //      xxxx                     - Suppress Status   -> Ack | Error
    //      xxxx AAAA AAAA DDDD DDDD - Send Data         -> Ack | Status | Error
    //      xxxx                     - Accept Data       -> Ack | Error
    //      xxxx                     - Stop              -> Ack | Error
    //      xxxx AAAA AAAA           - Selective Reset   -> Ack | Error
    input wire [23:0] in_tdata,
    input wire in_tvalid,
    output reg in_tready,

    //      0000                     - Ack ("null")
    //                                  -> is this really needed?
    //                                  -> can it be inferred?
    //                                  -> probably easier just to include it though
    //      xxxx AAAA AAAA SSSS SSSS - Status
    //      xxxx AAAA AAAA DDDD DDDD - Data
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
    parameter SYSTEM_RESET_DURATION_100_NS = 60; // 6 μs is 6000 ns, reduce this for tests

    localparam ERROR_INVALID_COMMAND = 8'h01;

    localparam STATE_SYSTEM_RESET = 0;
    localparam STATE_IDLE = 1;

    reg [7:0] state = STATE_SYSTEM_RESET;
    reg [7:0] next_state;
    reg [15:0] state_timer = 0;

    reg next_in_tready;
    reg [23:0] next_out_tdata;
    reg next_out_tvalid;

// vvv
reg [7:0] device_address;
reg device_selected;
// ^^^

    // verilator lint_off UNUSEDSIGNAL
    wire bus_in_parity_valid;
    // verilator lint_on UNUSEDSIGNAL

    assign bus_in_parity_valid = (~^a_bus_in == a_bus_in_parity); // Odd parity

    reg [7:0] next_bus_out;
    reg next_operational_out;
    reg next_hold_out;
    reg next_select_out;
    reg next_address_out;
    reg next_command_out;
    reg next_service_out;
    reg next_suppress_out;

    always @(*)
    begin
        next_state = state;

        next_in_tready = 0; // ???
        next_out_tdata = out_tdata;
        next_out_tvalid = out_tvalid;

        next_bus_out = a_bus_out; // ???
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
                if (state_timer == CLOCKS_PER_100_NS * SYSTEM_RESET_DURATION_100_NS)
                begin
                    next_state = STATE_IDLE;
                end
            end

            STATE_IDLE:
            begin
                next_operational_out = 1;

                // We are ready to accept something if there is no output pending.
                next_in_tready = ~out_tvalid;

                // Leave bus out low when idle to reduce driver current.
                //
                // TODO: Compute parity when needed then we could leave that
                // low here too.
                next_bus_out = 8'b0;

                if (in_tready && in_tvalid)
                begin
                    next_out_tdata = error_tdata(ERROR_INVALID_COMMAND);

                    // This will cause input ready to go low on next clock.
                    next_out_tvalid = 1;
                end

                if (out_tready && out_tvalid)
                begin
                    // Our output has been accepted.
                    next_out_tvalid = 0;
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

        a_bus_out <= next_bus_out;
        a_bus_out_parity <= ~^next_bus_out; // Odd parity
        a_operational_out <= next_operational_out;
        a_hold_out <= next_hold_out;
        a_select_out <= next_select_out;
        a_address_out <= next_address_out;
        a_command_out <= next_command_out;
        a_service_out <= next_service_out;
        a_suppress_out <= next_suppress_out;

        in_tready <= next_in_tready;
        out_tdata <= next_out_tdata;
        out_tvalid <= next_out_tvalid;

        if (reset)
        begin
            state <= STATE_SYSTEM_RESET;
            state_timer <= 0;

            in_tready <= 0;
            out_tvalid <= 0;
        end
    end

    assign request = a_request_in;

    function [23:0] error_tdata (
        input [7:0] code
    );
    begin
        error_tdata = { 8'hff, code, 8'h00 };
    end
    endfunction
endmodule
