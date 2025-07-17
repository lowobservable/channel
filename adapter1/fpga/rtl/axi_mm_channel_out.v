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

module axi_mm_channel_out (
    input wire aclk,
    input wire aresetn,

    // AXI4-Lite control interface...
    input wire [7:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output reg s_axi_arready,

    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,

    input wire [7:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output reg s_axi_awready,

    input wire [31:0] s_axi_wdata,
    // verilator lint_off UNUSEDSIGNAL
    input wire [3:0] s_axi_wstrb,
    // verilator lint_on UNUSEDSIGNAL
    input wire s_axi_wvalid,
    output reg s_axi_wready,

    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,

    // AXI4-Lite storage interface...
    output wire [31:0] m_axi_araddr,
    output wire m_axi_arvalid,
    input wire m_axi_arready,

    input wire [63:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rvalid,
    output wire m_axi_rready,

    output wire [31:0] m_axi_awaddr,
    output wire m_axi_awvalid,
    input wire m_axi_awready,

    output wire [63:0] m_axi_wdata,
    output wire [7:0] m_axi_wstrb,
    output wire m_axi_wvalid,
    input wire m_axi_wready,

    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready,

    // Parallel Channel "A"...
    input wire [7:0] a_bus_in,
    input wire a_bus_in_parity,
    output wire [7:0] a_bus_out,
    output wire a_bus_out_parity,

    output wire a_operational_out,
    input wire a_request_in,
    output wire a_hold_out,
    output wire a_select_out,
    input wire a_select_in,
    output wire a_address_out,
    input wire a_operational_in,
    input wire a_address_in,
    output wire a_command_out,
    input wire a_status_in,
    input wire a_service_in,
    output wire a_service_out,
    output wire a_suppress_out,

    output reg frontend_enable,

    output reg wrap_tester_enable,
    output reg [19:0] wrap_tester_driver,
    input wire [19:0] wrap_tester_receiver,

    output wire debug
);
    reg channel_enable = 0;

    reg [7:0] address;
    reg device_enable;
    reg [7:0] status;
    reg status_pending;
    reg status_stacked;
    reg status_suppressed;
    reg [7:0] command;
    reg [15:0] count;
    reg start_pending;

    // The control interface...
    //
    // ---- ---- | ---- ---- | ---- ---- | ---- ----
    //           |           |           |        FE <- "Channel enable"
    //           |           |           |        ^---- "Frontend enable"
    // DDDD DDDD | DDDD DDDD | DDDD      |         W <- Wrap tester enable
    // RRRR RRRR | RRRR RRRR | RRRR      |
    // ---- ---- | ---- ---- | ---- ---- | ---- ----
    // AAAA AAAA |           |           |         E <- "Device enable"
    //           |           |           |         S <- Start
    //           | NNNN NNNN | NNNN NNNN | CCCC CCCC
    //           |           | SSSS SSSS |       RTP <- Supr... / Stack... / Pending
    //
    always @(posedge clk)
    begin
        // ...

        if (!aresetn)
        begin
            channel_enable <= 0;
            device_enable <= 0;
            status_pending <= 0;
            status_stacked <= 0;
            status_suppressed <= 0;
            start_pending <= 0;

            frontend_enable <= 0;

            wrap_tester_enable <= 0;
        end
    end

    // The channel side of things...
    reg channel_burst = 0;
    wire channel_connected;
    wire channel_request;
    wire [7:0] channel_error;

    channel_out_protocol #(
        // ...
    ) protocol (
        .clk(aclk),
        .reset(!channel_enable),

        .in_tdata(),
        .in_tvalid(),
        .in_tready(),

        .out_tdata(),
        .out_tvalid(),
        .out_tready(),

        .burst(channel_burst),
        .connected(channel_connected),
        .request(channel_request),
        .error(channel_error),

        .a_operational_out(),
        .a_request_in(),
        .a_hold_out(),
        .a_select_out(),
        .a_select_in(),
        .a_address_out(),
        .a_operational_in(),
        .a_address_in(),
        .a_command_out(),
        .a_status_in(),
        .a_service_in(),
        .a_service_out(),
        .a_suppress_out()
    );

    always @(posedge clk)
    begin
        channel_in_tvalid <= 0;
        channel_out_tready <= 0;

        if (channel_error)
        begin
            // Something is going wrong...
        end

        case (channel_state)
            CHANNEL_STATE_IDLE:
            begin
                if (!channel_enable)
                begin
                    // Nothing should be happening, the channel should be held
                    // in system reset.
                end
                else if (channel_request)
                begin
                    channel_state <= CHANNEL_STATE_REQUEST_1;
                end
                else if (!device_enable)
                begin
                    // Nothing to do, if the CU wants something we'd answer them
                    // above.
                end
                else if (status_suppressed && !status_pending)
                begin
                    // Unsuppress that status, with TEST
                end
                // else if (start_pending)
                // begin
                //     if (status_pending)
                //     begin
                //         // Reject the takeoff
                //     end
                //     else
                //     begin
                //         -> START
                //     end
                // end
            end

            // CHANNEL_START:
            // begin
            //     // ...
            // end

            CHANNEL_STATE_REQUEST_1:
            begin
                channel_in_tdata <= XXX_SELECT_REQUESTOR_XXX;
                channel_in_tvalid <= 1;

                if (channel_in_tready && channel_in_tvalid)
                begin
                    channel_in_tvalid <= 0;

                    channel_state <= CHANNEL_STATE_REQUEST_2;
                end
            end

            CHANNEL_STATE_REQUEST_2:
            begin
                channel_out_tready <= 1;

                if (channel_out_tready && channel_out_tvalid)
                begin
                    channel_out_tready <= 0;

                    if (channel_out_tdata = 24'h000000)
                    begin
                        // The requestor did not respond.
                        channel_state <= CHANNEL_STATE_IDLE;
                    end
                    else if (channel_out_tdata[19:16] == XXX_CONNECTED_XXX)
                    begin
                        channel_state <= CHANNEL_STATE_CONNECTED;
                    end
                    else
                    begin
                        channel_state <= CHANNEL_STATE_TODO;
                    end
                end
            end

            CHANNEL_STATE_CONNECTED:
            begin
                channel_out_tready <= 1;

                // TODO: channel_burst <= no contention, probably

                // TODO: !device_enable handling here is probably a little more
                // complex than outlined... this works for the simple case where
                // a device is enabled or disabled outside of a channel
                // initiated operation.

                if (channel_out_tready && channel_out_tvalid)
                begin
                    channel_out_tready <= 0;

                    if (channel_out_tdata[19:16] == XXX_STATUS_XXX) // Status
                    begin
                        if (!channel_out_tdata[20])
                        begin
                            // Invalid parity...
                            channel_state <= CHANNEL_STATE_TODO;
                        end
                        else if (channel_out_tdata[15:8] == device_address && device_enabled && !status_pending)
                        begin
                            // Ok, we can accept the status...
                            status <= channel_out_tdata[7:0];
                            status_pending <= 1;
                            status_stacked <= 0;
                            status_suppressed <= 0;

                            channel_state <= CHANNEL_STATE_ACCEPT_STATUS_1;
                        end
                        else
                        begin
                            // We gotta suppress that status.
                            status_suppressed <= 1;

                            channel_state <= CHANNEL_STATE_SUPPRESS_STATUS_1;
                        end
                    end
                    // else if (channel_out_tdata[19:16] == 4'h2) // Data Service
                    // begin
                    //     // ...
                    // end
                    else
                    begin
                        channel_state <= CHANNEL_STATE_TODO;
                    end
                end
                else if (!channel_connected)
                begin
                    channel_state <= CHANNEL_STATE_IDLE;
                end
            end

            CHANNEL_STATE_ACCEPT_STATUS_1:
            begin
                channel_in_tdata <= XXX_ACCEPT_STATUS_XXX;
                channel_in_tvalid <= 1;

                if (channel_in_tready && channel_in_tvalid)
                begin
                    channel_in_tvalid <= 0;

                    channel_state <= CHANNEL_STATE_ACCEPT_STATUS_2;
                end
            end

            CHANNEL_STATE_ACCEPT_STATUS_2:
            begin
                channel_out_tready <= 1;

                if (channel_out_tready && channel_out_tvalid)
                begin
                    channel_out_tready <= 0;

                    TODO
                end
            end

            CHANNEL_STATE_SUPPRESS_STATUS_1:
            begin
                channel_in_tdata <= XXX_SUPPRESS_STATUS_XXX;
                channel_in_tvalid <= 1;

                if (channel_in_tready && channel_in_tvalid)
                begin
                    channel_in_tvalid <= 0;

                    channel_state <= CHANNEL_STATE_SUPPRESS_STATUS_2;
                end
            end

            CHANNEL_STATE_SUPPRESS_STATUS_2:
            begin
                channel_out_tready <= 1;

                if (channel_out_tready && channel_out_tvalid)
                begin
                    channel_out_tready <= 0;

                    TODO
                end
            end
        endcase
    end
endmodule
