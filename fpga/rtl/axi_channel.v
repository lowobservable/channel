`default_nettype none

module axi_channel (
    input wire aclk,
    input wire aresetn,

    // Parallel Channel "A"...
    input wire [7:0] a_bus_in,
    output wire [7:0] a_bus_out,

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
    output reg s_axi_arready,
    input wire [7:0] s_axi_araddr,
    input wire s_axi_arvalid,

    input wire s_axi_rready,
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,

    output reg s_axi_awready,
    input wire [7:0] s_axi_awaddr,
    input wire s_axi_awvalid,

    output reg s_axi_wready,
    input wire [31:0] s_axi_wdata,
    // verilator lint_off UNUSEDSIGNAL
    input wire [3:0] s_axi_wstrb,
    // verilator lint_on UNUSEDSIGNAL
    input wire s_axi_wvalid,

    input wire s_axi_bready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,

    // M_AXI...
    input wire m_axi_arready,
    output wire [31:0] m_axi_araddr,
    output wire m_axi_arvalid,

    output wire m_axi_rready,
    input wire [63:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rvalid,

    input wire m_axi_awready,
    output wire [31:0] m_axi_awaddr,
    output wire m_axi_awvalid,

    input wire m_axi_wready,
    output wire [63:0] m_axi_wdata,
    output wire [7:0] m_axi_wstrb,
    output wire m_axi_wvalid,

    output wire m_axi_bready,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid
);
    localparam REG_CONTROL = 8'h00;
    localparam REG_STATUS = 8'h04;
    localparam REG_DMA_ADDR = 8'h08;

    initial
    begin
        s_axi_arready = 1'b1;
        s_axi_rvalid = 1'b0;

        s_axi_awready = 1'b1;
        s_axi_wready = 1'b1;
        s_axi_bvalid = 1'b0;
    end

    reg reset = 1'b0;

    reg [7:0] channel_address;
    reg [7:0] channel_command;
    reg [7:0] channel_count;
    reg [31:0] dma_addr;
    reg channel_start = 1'b0;
    wire channel_active;
    wire [7:0] channel_status;
    wire [7:0] channel_res_count;

    always @(posedge aclk)
    begin
        if (s_axi_arready && s_axi_arvalid)
        begin
            s_axi_rdata <= 32'b0;
            s_axi_rresp <= 2'b00;

            case (s_axi_araddr)
                REG_CONTROL:
                    s_axi_rdata <= { channel_address, channel_command, channel_count, 6'b0, channel_start || channel_active, reset };

                REG_STATUS:
                    s_axi_rdata <= { channel_status, 8'b0, channel_res_count, 6'b0, channel_active, 1'b0 };

                REG_DMA_ADDR:
                    s_axi_rdata <= dma_addr;

                default:
                    s_axi_rresp <= 2'b10; // SLVERR
            endcase

            s_axi_rvalid <= 1'b1;
        end
        else if (s_axi_rready && s_axi_rvalid)
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

        if (s_axi_awready && s_axi_awvalid)
        begin
            awaddr <= s_axi_awaddr;
            awaddr_full <= 1'b1;

            // We can't accept anything more until the write is complete.
            s_axi_awready <= 1'b0;
        end

        if (s_axi_wready && s_axi_wvalid)
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
                REG_CONTROL:
                begin
                    reset <= wdata[0];
                    channel_start <= wdata[1];
                    channel_address <= wdata[31:24];
                    channel_command <= wdata[23:16];
                    channel_count <= wdata[15:8];
                end

                REG_DMA_ADDR:
                    dma_addr <= wdata;

                default:
                    s_axi_bresp <= 2'b10; // SLVERR
            endcase

            s_axi_bvalid <= 1'b1;

            awaddr_full <= 1'b0;
            wdata_full <= 1'b0;
        end

        if (s_axi_bready && s_axi_bvalid)
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

            awaddr_full <= 1'b0;
            wdata_full <= 1'b0;

            s_axi_awready <= 1'b1;
            s_axi_wready <= 1'b1;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
        end
    end

    wire x_busy;
    reg [31:0] x_addr;
    reg x_start;
    wire x_done;

    wire [7:0] channel_data_send_tdata;
    reg channel_data_send_tvalid;
    wire channel_data_send_tready;

    wire [7:0] channel_data_recv_tdata;
    wire channel_data_recv_tvalid;
    reg channel_data_recv_tready;

    axi_byte_io axi_byte_io (
        .aclk(aclk),
        .aresetn(aresetn),

        .busy(x_busy),
        .write(!channel_command[0]), // READ command WRITES, WRITE command READS...
        .addr(x_addr),
        .data_read(channel_data_send_tdata),
        .data_write(channel_data_recv_tdata),
        .start(x_start),
        .done(x_done),

        .m_axi_arready(m_axi_arready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),

        .m_axi_rready(m_axi_rready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),

        .m_axi_awready(m_axi_awready),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),

        .m_axi_wready(m_axi_wready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),

        .m_axi_bready(m_axi_bready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid)
    );

    reg [7:0] x_state;

    reg [7:0] x_count;

    always @(posedge aclk)
    begin
        // Capture the DMA address and count when the channel starts.
        if (channel_start)
        begin
            x_count <= channel_count;
            x_addr <= dma_addr;
        end

        x_start <= 1'b0;

        case (x_state)
            0:
            begin
                // TODO: we use TREADY to indicate that the read has been "accepted", confirm
                // that it is okay for the slave to wait on TVALID...
                channel_data_send_tvalid <= 1'b0;
                channel_data_recv_tready <= 1'b0;

                if (x_count != 0 && !x_busy)
                begin
                    if ((channel_command[0] && channel_data_send_tready)
                        || (!channel_command[0] && channel_data_recv_tvalid))
                    begin
                        x_start <= 1'b1;

                        x_state <= 1;
                    end
                end
            end

            1: // wait on DMA completion
            begin
                if (x_done)
                begin
                    // let the channel know using TVALID or TREADY depending on direction
                    if (channel_command[0])
                        channel_data_send_tvalid <= 1'b1;
                    else
                        channel_data_recv_tready <= 1'b1;

                    x_state <= 2;
                end
            end

            2: // wait on channel completion
            begin
                if ((channel_command[0] && channel_data_send_tready && channel_data_send_tvalid)
                    || (!channel_command[0] && channel_data_recv_tready && channel_data_recv_tvalid))
                begin
                    // Deassert these immediately...
                    channel_data_send_tvalid <= 1'b0;
                    channel_data_recv_tready <= 1'b0;

                    x_count <= x_count - 1;
                    x_addr <= x_addr + 1;

                    x_state <= 0;
                end
            end
        endcase

        if (!aresetn)
        begin
            channel_data_send_tvalid <= 1'b0;
            channel_data_recv_tready <= 1'b0;

            x_state <= 0;
        end
    end

    channel channel (
        .clk(aclk),
        .reset(reset),

        .a_bus_in(a_bus_in),
        .a_bus_out(a_bus_out),

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

        .address(channel_address),
        .command(channel_command),
        .count(channel_count),
        .start_strobe(channel_start),

        .active(channel_active),

        .status(channel_status),
        .status_strobe(), // TODO

        .res_count(channel_res_count),

        .data_send_tdata(channel_data_send_tdata),
        .data_send_tvalid(channel_data_send_tvalid),
        .data_send_tready(channel_data_send_tready),

        .data_recv_tdata(channel_data_recv_tdata),
        .data_recv_tvalid(channel_data_recv_tvalid),
        .data_recv_tready(channel_data_recv_tready)
    );
endmodule
