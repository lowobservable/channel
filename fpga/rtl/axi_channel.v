`default_nettype none

module axi_channel (
    input wire aclk,
    input wire aresetn,

    output reg frontend_enable,
    output wire channel_active,

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

    // S_AXI...
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

    // M_AXI...
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
    output wire m_axi_bready
);
    localparam REG_CONTROL_1 = 8'h00;
    localparam REG_CONTROL_2 = 8'h04;
    localparam REG_STATUS_1 = 8'h08;
    localparam REG_STATUS_2 = 8'h0c;
    localparam REG_CCW_1 = 8'h10;
    localparam REG_CCW_2 = 8'h14;

    initial
    begin
        frontend_enable = 1'b0;

        s_axi_arready = 1'b1;
        s_axi_rvalid = 1'b0;

        s_axi_awready = 1'b1;
        s_axi_wready = 1'b1;
        s_axi_bvalid = 1'b0;
    end

    reg reset = 1'b0;

    reg channel_enable = 1'b0;
    reg [7:0] channel_addr;
    reg channel_start = 1'b0;
    reg channel_stop = 1'b0;
    wire [1:0] channel_condition_code;
    wire [7:0] channel_status_tdata;
    wire channel_status_tvalid;
    wire [7:0] channel_data_send_tdata;
    reg channel_data_send_tvalid;
    wire channel_data_send_tready;
    wire [7:0] channel_data_recv_tdata;
    wire channel_data_recv_tvalid;
    reg channel_data_recv_tready;

    reg [7:0] ccw_command;
    reg [15:0] ccw_count;
    reg [31:0] ccw_data_addr;

    reg [7:0] device_status;
    reg [15:0] count;

    channel channel (
        .clk(aclk),
        .enable(channel_enable),
        .reset(reset),

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
        .a_suppress_out(a_suppress_out),

        .active(channel_active),

        .addr(channel_addr),
        .command(ccw_command),
        .start(channel_start),
        .stop(channel_stop),
        .condition_code(channel_condition_code),

        .status_tdata(channel_status_tdata),
        .status_tvalid(channel_status_tvalid),

        .data_send_tdata(channel_data_send_tdata),
        .data_send_tvalid(channel_data_send_tvalid),
        .data_send_tready(channel_data_send_tready),

        .data_recv_tdata(channel_data_recv_tdata),
        .data_recv_tvalid(channel_data_recv_tvalid),
        .data_recv_tready(channel_data_recv_tready)
    );

    always @(posedge aclk)
    begin
        if (s_axi_arvalid && s_axi_arready)
        begin
            s_axi_rdata <= 32'b0;
            s_axi_rresp <= 2'b00;

            case (s_axi_araddr)
                REG_CONTROL_1:
                    s_axi_rdata <= { frontend_enable, 29'b0, channel_enable, reset };

                REG_CONTROL_2:
                    s_axi_rdata <= { channel_addr, 23'b0, channel_start || channel_active };

                REG_STATUS_1:
                    s_axi_rdata <= { 24'b0, channel_condition_code, 5'b0, channel_active };

                REG_STATUS_2:
                    s_axi_rdata <= { device_status, 8'b0, count };

                REG_CCW_1:
                    s_axi_rdata <= { ccw_command, 8'b0, ccw_count };

                REG_CCW_2:
                    s_axi_rdata <= ccw_data_addr;

                default:
                    s_axi_rresp <= 2'b10; // SLVERR
            endcase

            s_axi_rvalid <= 1'b1;
        end
        else if (s_axi_rvalid && s_axi_rready)
        begin
            s_axi_rdata <= 32'b0;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
        end

        s_axi_arready <= !s_axi_rvalid;

        if (!aresetn)
        begin
            s_axi_arready <= 1'b1;
            s_axi_rdata <= 32'b0;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
        end
    end

    reg [7:0] awaddr;
    reg awaddr_full;
    reg [31:0] wdata;
    reg wdata_full;

    always @(posedge aclk)
    begin
        // These are 1 clock "pulses"...
        reset <= 1'b0;
        channel_start <= 1'b0;

        if (s_axi_awvalid && s_axi_awready)
        begin
            awaddr <= s_axi_awaddr;
            awaddr_full <= 1'b1;

            // We can't accept anything more until the write is complete.
            s_axi_awready <= 1'b0;
        end

        if (s_axi_wvalid && s_axi_wready)
        begin
            wdata <= s_axi_wdata;
            wdata_full <= 1'b1;

            // We can't accept anything more until the write is complete.
            s_axi_wready <= 1'b0;
        end

        if (awaddr_full && wdata_full)
        begin
            s_axi_bresp <= 2'b00;

            // TODO: should consider s_axi_wstrb
            case (awaddr)
                REG_CONTROL_1:
                begin
                    reset <= wdata[0];

                    channel_enable <= wdata[1];
                    frontend_enable <= wdata[31];
                end

                REG_CONTROL_2:
                begin
                    channel_addr <= wdata[31:24];
                    channel_start <= wdata[0];
                end

                REG_CCW_1:
                begin
                    ccw_command <= wdata[31:24];
                    ccw_count <= wdata[15:0];
                end

                REG_CCW_2:
                    ccw_data_addr <= wdata;

                default:
                    s_axi_bresp <= 2'b10; // SLVERR
            endcase

            s_axi_bvalid <= 1'b1;

            awaddr_full <= 1'b0;
            wdata_full <= 1'b0;
        end

        if (s_axi_bvalid && s_axi_bready)
        begin
            s_axi_awready <= 1'b1;
            s_axi_wready <= 1'b1;

            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
        end

        if (!aresetn)
        begin
            reset <= 1'b1;

            channel_start <= 1'b0;
            channel_enable <= 1'b0;
            frontend_enable <= 1'b0;

            awaddr_full <= 1'b0;
            wdata_full <= 1'b0;

            s_axi_awready <= 1'b1;
            s_axi_wready <= 1'b1;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
        end
    end

    always @(posedge aclk)
    begin
        if (channel_start)
        begin
            device_status <= 8'b0;
        end

        if (channel_status_tvalid)
        begin
            device_status <= channel_status_tdata;
        end

        if (!aresetn)
        begin
            device_status <= 8'b0;
        end
    end

    reg [7:0] dma_state;
    wire dma_busy;
    reg [31:0] dma_addr;
    reg dma_start;
    wire dma_done;

    axi_byte_io axi_byte_io (
        .aclk(aclk),
        .aresetn(aresetn),

        .busy(dma_busy),
        .write(!ccw_command[0]), // READ command WRITES, WRITE command READS...
        .addr(dma_addr),
        .data_read(channel_data_send_tdata),
        .data_write(channel_data_recv_tdata),
        .start(dma_start),
        .done(dma_done),

        .m_axi_araddr(m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),

        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),

        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),

        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),

        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

    always @(posedge aclk)
    begin
        if (channel_start)
        begin
            // Capture the DMA address and count from the CCW when the channel starts.
            dma_addr <= ccw_data_addr;
            count <= ccw_count;
        end

        channel_stop <= 1'b0;
        dma_start <= 1'b0;

        case (dma_state)
            0:
            begin
                // TODO: we use TREADY to indicate that the read has been "accepted", confirm
                // that it is okay for the slave to wait on TVALID...
                channel_data_send_tvalid <= 1'b0;
                channel_data_recv_tready <= 1'b0;

                if ((ccw_command[0] && channel_data_send_tready)
                    || (!ccw_command[0] && channel_data_recv_tvalid))
                begin
                    if (count == 0)
                    begin
                        channel_stop <= 1'b1;
                    end
                    else if (!dma_busy)
                    begin
                        dma_start <= 1'b1;

                        dma_state <= 1;
                    end
                end
            end

            1: // wait on DMA completion
            begin
                if (dma_done)
                begin
                    // let the channel know using TVALID or TREADY depending on direction
                    if (ccw_command[0])
                        channel_data_send_tvalid <= 1'b1;
                    else
                        channel_data_recv_tready <= 1'b1;

                    dma_state <= 2;
                end
            end

            2: // wait on channel completion
            begin
                if ((ccw_command[0] && channel_data_send_tvalid && channel_data_send_tready)
                    || (!ccw_command[0] && channel_data_recv_tvalid && channel_data_recv_tready))
                begin
                    // Deassert these immediately...
                    channel_data_send_tvalid <= 1'b0;
                    channel_data_recv_tready <= 1'b0;

                    count <= count - 1;
                    dma_addr <= dma_addr + 1;

                    dma_state <= 0;
                end
            end
        endcase

        if (!aresetn)
        begin
            channel_data_send_tvalid <= 1'b0;
            channel_data_recv_tready <= 1'b0;

            dma_state <= 0;
        end
    end
endmodule
