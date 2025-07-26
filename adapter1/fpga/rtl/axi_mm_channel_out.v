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
    input wire [3:0] s_axi_wstrb,
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

    output wire debug_0,
    output wire debug_1
);
    parameter CLOCKS_PER_100_NS = 5; // 50 MHz clock period is 20 ns

    localparam REG_CHANNEL_1 = 8'h00;
    localparam REG_CHANNEL_3 = 8'h08;
    localparam REG_CHANNEL_4 = 8'h0c;
    localparam REG_DEVICE_1 = 8'h10;
    localparam REG_DEVICE_2 = 8'h14;
    localparam REG_DEVICE_3 = 8'h18;
    localparam REG_DEVICE_4 = 8'h1c;

    reg channel_enable = 0;

    reg [7:0] device_address;
    reg device_enable;
    reg [7:0] status;
    reg status_pending;
    reg clear_status_pending;
    reg status_stacked;
    reg status_suppressed;
    reg [7:0] command;
    reg [15:0] count;
    reg start_pending;
    reg clear_start_pending;
    reg [3:0] condition_code;

    // The control interface...
    //
    //     ---- ---- | ---- ---- | ---- ---- | ---- ----
    // C1:           |           |           |         E <- "Channel enable"
    //               |           |           |
    // C3: DDDD DDDD | DDDD DDDD | DDDD    W |         F <- Frontend enable
    // C4: RRRR RRRR | RRRR RRRR | RRRR    ^--------------- Wrap tester enable
    //     ---- ---- | ---- ---- | ---- ---- | ---- ----
    // D1: AAAA AAAA |           |           |         E <- "Device enable"
    // D2:           | SSSS SSSS | RTPA      | CCCC    S <- Start / Start Pending
    //                             ^^^^-------------------- Active
    //                             +++--------------------- Supr'd / Stack'd / Pending
    // D3: AAAA AAAA | AAAA AAAA | AAAA AAAA | AAAA AAAA <- Storage address
    // D4:           | NNNN NNNN | NNNN NNNN | CCCC CCCC
    //
    always @(posedge aclk)
    begin
        // TODO: Without a buffer, we cannot accept a read with a response
        // pending.
        s_axi_arready <= !s_axi_rvalid;

        if (s_axi_arvalid && s_axi_arready)
        begin
            s_axi_arready <= 0;

            s_axi_rresp <= 2'b00;

            case (s_axi_araddr)
                REG_CHANNEL_1:
                begin
                    s_axi_rdata <= { 31'b0, channel_enable };
                end

                8'h04: // TODO: Temporary debug register
                begin
                    s_axi_rdata <= { channel_state, channel_error, 8'b0 };
                end

                REG_CHANNEL_3:
                begin
                    s_axi_rdata <= { wrap_tester_driver, 3'b0, wrap_tester_enable, 7'b0, frontend_enable };
                end

                REG_CHANNEL_4:
                begin
                    s_axi_rdata <= { wrap_tester_receiver, 12'b0 };
                end

                REG_DEVICE_1:
                begin
                    s_axi_rdata <= { device_address, 23'b0, device_enable };
                end

                REG_DEVICE_2:
                begin
                    s_axi_rdata <= { 8'b0, status, status_suppressed, status_stacked, status_pending, 5'b0, condition_code, 3'b0, start_pending };
                end

                REG_DEVICE_3:
                begin
                    s_axi_rdata <= 32'b0;
                end

                REG_DEVICE_4:
                begin
                    s_axi_rdata <= { 8'b0, count, command };
                end

                default:
                begin
                    s_axi_rresp <= 2'b10; // SLVERR
                end
            endcase

            s_axi_rvalid <= 1;
        end

        if (s_axi_rvalid && s_axi_rready)
        begin
            s_axi_rvalid <= 0;
            s_axi_arready <= 1;
        end

        if (!aresetn)
        begin
            s_axi_arready <= 0;
            s_axi_rvalid <= 0;
        end
    end

    reg [7:0] waddr;
    reg waddr_loaded;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg wdata_loaded;

    always @(posedge aclk)
    begin
        // 1-clock pulses to communicate with channel state machine...
        clear_status_pending <= 0;

        if (clear_start_pending)
        begin
            start_pending <= 0;
        end

        s_axi_awready <= !waddr_loaded && !s_axi_bvalid;

        if (s_axi_awvalid && s_axi_awready)
        begin
            s_axi_awready <= 0;

            waddr <= s_axi_awaddr;
            waddr_loaded <= 1;
        end

        s_axi_wready <= !wdata_loaded && !s_axi_bvalid;

        if (s_axi_wvalid && s_axi_wready)
        begin
            s_axi_wready <= 0;

            wdata <= s_axi_wdata;
            wstrb <= s_axi_wstrb;
            wdata_loaded <= 1;
        end

        if (waddr_loaded && wdata_loaded)
        begin
            s_axi_bresp <= 2'b00;

            case (waddr)
                REG_CHANNEL_1:
                begin
                    // TODO: wstrb
                    channel_enable <= wdata[0];
                end

                REG_CHANNEL_3:
                begin
                    // TODO: wstrb
                    frontend_enable <= wdata[0];

                    // NOTE: Enabling the wrap test while the channel is enabled
                    // is probably undesirable, but not enforced here.
                    wrap_tester_enable <= wdata[8];
                    wrap_tester_driver <= wdata[31:12];
                end

                REG_DEVICE_1:
                begin
                    // TODO: wstrb
                    device_enable <= wdata[0];
                    device_address <= wdata[31:24];
                end

                REG_DEVICE_2:
                begin
                    // TODO: wstrb
                    if (wdata[0])
                    begin
                        // TODO: Should not be allowed if start is pending.
                        start_pending <= 1;
                    end

                    if (wdata[13])
                    begin
                        clear_status_pending <= 1;
                    end
                end

                REG_DEVICE_3:
                begin
                    // TODO: Storage address not used yet
                end

                REG_DEVICE_4:
                begin
                    // TODO: Command and count not used yet
                end

                default:
                begin
                    s_axi_bresp <= 2'b10; // SLVERR
                end
            endcase

            s_axi_bvalid <= 1;

            waddr_loaded <= 0;
            wdata_loaded <= 0;
        end

        if (s_axi_bvalid && s_axi_bready)
        begin
            s_axi_bvalid <= 0;
            s_axi_awready <= 1;
            s_axi_wready <= 1;
        end

        if (!aresetn)
        begin
            s_axi_awready <= 0;
            s_axi_wready <= 0;
            s_axi_bvalid <= 0;

            waddr_loaded <= 0;
            wdata_loaded <= 0;

            channel_enable <= 0;
            device_enable <= 0;
            start_pending <= 0;

            frontend_enable <= 0;

            wrap_tester_enable <= 0;
        end
    end

    // The channel side of things...
    reg [7:0] channel_state;

    localparam CHANNEL_STATE_IDLE = 0;
    localparam CHANNEL_STATE_START_1 = 90;
    localparam CHANNEL_STATE_START_2 = 91;
    localparam CHANNEL_STATE_REQUEST_1 = 1;
    localparam CHANNEL_STATE_REQUEST_2 = 2;
    localparam CHANNEL_STATE_CONNECTED = 3;
    localparam CHANNEL_STATE_ACCEPT_STATUS_1 = 4;
    localparam CHANNEL_STATE_ACCEPT_STATUS_2 = 5;
    localparam CHANNEL_STATE_STACK_STATUS_1 = 6;
    localparam CHANNEL_STATE_STACK_STATUS_2 = 7;
    localparam CHANNEL_STATE_TODO = 8;

    reg [23:0] channel_in_tdata;
    reg channel_in_tvalid;
    wire channel_in_tready;

    wire [23:0] channel_out_tdata;
    wire channel_out_tvalid;
    reg channel_out_tready;

    reg channel_burst = 0;
    wire channel_connected;
    wire channel_request;
    wire [15:0] channel_error;

    channel_out_protocol #(
        .CLOCKS_PER_100_NS(CLOCKS_PER_100_NS)
    ) protocol (
        .clk(aclk),
        .reset(!channel_enable),

        .in_tdata(channel_in_tdata),
        .in_tvalid(channel_in_tvalid),
        .in_tready(channel_in_tready),

        .out_tdata(channel_out_tdata),
        .out_tvalid(channel_out_tvalid),
        .out_tready(channel_out_tready),

        .burst(channel_burst),
        .connected(channel_connected),
        .request(channel_request),
        .error(channel_error),

        .a_bus_in(a_bus_in),
        .a_bus_in_parity(a_bus_in_parity),
        .a_bus_out(a_bus_out),
        .a_bus_out_parity(a_bus_out_parity),
        .a_operational_out(a_operational_out),
        .a_request_in(a_request_in),
        .a_hold_out(a_hold_out),
        .a_select_out(a_select_out),
        .a_select_in(a_select_in),
        .a_address_out(a_address_out),
        .a_operational_in(a_operational_in),
        .a_address_in(a_address_in),
        .a_command_out(a_command_out),
        .a_status_in(a_status_in),
        .a_service_in(a_service_in),
        .a_service_out(a_service_out),
        .a_suppress_out(a_suppress_out)
    );

    always @(posedge aclk)
    begin
        // 1-clock pulses to communicate with channel state machine...
        clear_start_pending <= 0;

        if (clear_status_pending)
        begin
            status_pending <= 0;
        end

        channel_in_tvalid <= 0;
        channel_out_tready <= 0;

        if (channel_error[0])
        begin
            // Something is going wrong...
        end
        else if (!channel_enable)
        begin
            channel_state <= CHANNEL_STATE_IDLE;

            status_pending <= 0;
            status_stacked <= 0;
            status_suppressed <= 0;
        end
        else
        begin
            case (channel_state)
                CHANNEL_STATE_IDLE:
                begin
                    if (channel_request)
                    begin
                        channel_state <= CHANNEL_STATE_REQUEST_1;
                    end
                    else if (start_pending)
                    begin
                        if (!device_enable)
                        begin
                            condition_code <= 4'h1; // XXX - Device Disabled
                            clear_start_pending <= 1;
                        end
                        else if (status_pending)
                        begin
                            // Reject the takeoff.
                            condition_code <= 4'h3; // XXX - Status Pending
                            clear_start_pending <= 1;
                        end
                        else
                        begin
                            channel_state <= CHANNEL_STATE_START_1;
                        end
                    end
                    else if (!device_enable)
                    begin
                        // Nothing to do, if a CU wants something we would
                        // answer them above.
                    end
                    else if (status_suppressed && !status_pending)
                    begin
                        // Unsuppress that status, with TEST
                    end
                end

                CHANNEL_STATE_START_1:
                begin
                    channel_in_tdata <= { 8'h11, device_address, command }; // XXX - Initial Selection
                    channel_in_tvalid <= 1;

                    if (channel_in_tready && channel_in_tvalid)
                    begin
                        channel_in_tvalid <= 0;

                        channel_state <= CHANNEL_STATE_START_2;
                    end
                end

                CHANNEL_STATE_START_2:
                begin
                    //
                end

                CHANNEL_STATE_REQUEST_1:
                begin
                    channel_in_tdata <= 24'h010000; // XXX - Select Requestor
                    channel_in_tvalid <= 1;

                    if (channel_in_tready && channel_in_tvalid)
                    begin
                        channel_in_tvalid <= 0;

                        channel_state <= CHANNEL_STATE_REQUEST_2;
                    end
                end

                CHANNEL_STATE_REQUEST_2:
                begin
                    if (channel_connected)
                    begin
                        channel_state <= CHANNEL_STATE_CONNECTED;
                    end

                    // TODO: A seperate connected event may be required so we
                    // can determine if the requestor did not respond.
                    // Alternatavely we could try peeking when TVALID without
                    // asserting TREADY but that would not be correct.
                end

                CHANNEL_STATE_CONNECTED:
                begin
                    channel_out_tready <= 1;

                    // TODO: channel_burst <= no contention, probably

                    // TODO: !device_enable handling here is probably a little
                    // more complex than outlined... this works for the simple
                    // case where a device is enabled or disabled outside of
                    // a channel initiated operation.

                    if (channel_out_tready && channel_out_tvalid)
                    begin
                        channel_out_tready <= 0;

                        if (channel_out_tdata[19:16] == 4'h1) // XXX - Status
                        begin
                            if (!channel_out_tdata[20])
                            begin
                                // Invalid parity...
                                channel_state <= CHANNEL_STATE_TODO;
                            end
                            else if (channel_out_tdata[15:8] == device_address && device_enable && !status_pending)
                            begin
                                // Ok, we can accept the status...
                                status <= channel_out_tdata[7:0];
                                status_pending <= 1;
                                status_stacked <= 0;
                                status_suppressed <= 0;

                                channel_state <= CHANNEL_STATE_ACCEPT_STATUS_1;
                            end
                            else if (!status_stacked)
                            begin
                                // We gotta stack that status.
                                status_stacked <= 1;

                                channel_state <= CHANNEL_STATE_STACK_STATUS_1;
                            end
                            else
                            begin
                                // We probably ned to suppress now.
                                channel_state <= CHANNEL_STATE_TODO;
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
                    channel_in_tdata <= 24'h020000; // XXX - Accept Status
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

                        if (channel_connected)
                        begin
                            channel_state <= CHANNEL_STATE_CONNECTED;
                        end
                        else
                        begin
                            channel_state <= CHANNEL_STATE_IDLE;
                        end
                    end
                end

                CHANNEL_STATE_STACK_STATUS_1:
                begin
                    channel_in_tdata <= 24'h030000; // XXX - Stack Status
                    channel_in_tvalid <= 1;

                    if (channel_in_tready && channel_in_tvalid)
                    begin
                        channel_in_tvalid <= 0;

                        channel_state <= CHANNEL_STATE_STACK_STATUS_2;
                    end
                end

                CHANNEL_STATE_STACK_STATUS_2:
                begin
                    channel_out_tready <= 1;

                    if (channel_out_tready && channel_out_tvalid)
                    begin
                        channel_out_tready <= 0;

                        if (channel_connected)
                        begin
                            channel_state <= CHANNEL_STATE_CONNECTED;
                        end
                        else
                        begin
                            channel_state <= CHANNEL_STATE_IDLE;
                        end
                    end
                end

                CHANNEL_STATE_TODO:
                begin
                    $display("TODO");
                    $finish;
                end
            endcase
        end

        if (!aresetn)
        begin
            channel_state <= CHANNEL_STATE_IDLE;

            status_pending <= 0;
            status_stacked <= 0;
            status_suppressed <= 0;
        end
    end

    assign debug_0 = frontend_enable;
    assign debug_1 = channel_connected;
endmodule
