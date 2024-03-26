`default_nettype none

module axi_channel (
    input wire aclk,
    input wire aresetn,

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
    input wire [3:0] s_axi_wstrb,
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
    localparam REG_ADDR = 8'h08;
    localparam REG_COUNT = 8'h0c;
    localparam REG_DATA = 8'h10;

    initial
    begin
        s_axi_arready = 1'b1;
        s_axi_rvalid = 1'b0;

        s_axi_awready = 1'b1;
        s_axi_wready = 1'b1;
        s_axi_bvalid = 1'b0;
    end

    reg reset = 1'b0;

    wire mock_busy;
    reg mock_write = 1'b0;
    reg mock_start = 1'b0;
    reg [31:0] mock_addr;
    reg [31:0] mock_count;
    reg [7:0] mock_data_read;
    reg [7:0] mock_data_write;

    always @(posedge aclk)
    begin
        if (s_axi_arready && s_axi_arvalid)
        begin
            s_axi_rdata <= 32'b0;
            s_axi_rresp <= 2'b00;

            case (s_axi_araddr)
                REG_CONTROL:
                    s_axi_rdata <= { 29'b0, mock_write, mock_start || mock_busy, reset };

                REG_STATUS:
                    s_axi_rdata <= { 30'b0, mock_busy, 1'b0 };

                REG_ADDR:
                    s_axi_rdata <= mock_addr;

                REG_COUNT:
                    s_axi_rdata <= mock_count;

                REG_DATA:
                    s_axi_rdata <= { 16'b0, mock_data_read, mock_data_write };

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
        mock_start <= 1'b0;

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

            case (awaddr)
                REG_CONTROL:
                begin
                    reset <= wdata[0];
                    mock_start <= wdata[1];
                    mock_write <= wdata[2];
                end

                REG_ADDR:
                    mock_addr <= wdata;

                REG_COUNT:
                    mock_count <= wdata;

                REG_DATA:
                    mock_data_write <= wdata[7:0];

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
            mock_start <= 1'b0;

            awaddr_full <= 1'b0;
            wdata_full <= 1'b0;

            s_axi_awready <= 1'b1;
            s_axi_wready <= 1'b1;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
        end
    end

    wire x_busy;
    reg x_write;
    reg [31:0] x_addr;
    reg [31:0] x_count;
    wire [7:0] x_data_read;
    reg [7:0] x_data_write;
    reg x_start;
    wire x_done;

    axi_byte_io axi_byte_io (
        .aclk(aclk),
        .aresetn(aresetn),

        .busy(x_busy),
        .write(x_write),
        .addr(x_addr),
        .data_read(x_data_read),
        .data_write(x_data_write ^ x_count[7:0]), // XXX
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

    assign mock_busy = (x_state != 0);

    always @(posedge aclk)
    begin
        x_start <= 1'b0;

        case (x_state)
            0:
            begin
                if (mock_start)
                begin
                    x_write <= mock_write;
                    x_addr <= mock_addr;
                    x_count <= mock_count;
                    x_data_write <= mock_data_write;

                    x_state <= 1;
                end
            end

            1:
            begin
                if (x_count == 0)
                begin
                    x_state <= 0;
                end
                else if (!x_busy)
                begin
                    x_start <= 1'b1;
                    x_state <= 2;
                end
            end

            2:
            begin
                if (x_done)
                begin
                    mock_data_read <= x_data_read;

                    x_addr <= x_addr + 1;
                    x_count <= x_count - 1;
                    x_state <= 1;
                end
            end
        endcase

        if (!aresetn)
        begin
            x_state <= 0;
        end
    end
endmodule
