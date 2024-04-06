`default_nettype none

module axi_byte_io (
    input wire aclk,
    input wire aresetn,

    output wire busy,
    input wire [31:0] addr,
    input wire write,
    output reg [7:0] data_read,
    input wire [7:0] data_write,
    input wire start,
    output reg done,

    // M_AXI...
    output reg [31:0] m_axi_araddr,
    output reg m_axi_arvalid,
    input wire m_axi_arready,

    input wire [63:0] m_axi_rdata,
    // verilator lint_off UNUSEDSIGNAL
    input wire [1:0] m_axi_rresp,
    // veriltor lint on UNUSEDSIGNAL
    input wire m_axi_rvalid,
    output reg m_axi_rready,

    output reg [31:0] m_axi_awaddr,
    output reg m_axi_awvalid,
    input wire m_axi_awready,

    output reg [63:0] m_axi_wdata,
    output reg [7:0] m_axi_wstrb,
    output reg m_axi_wvalid,
    input wire m_axi_wready,

    // verilator lint_off UNUSEDSIGNAL
    input wire [1:0] m_axi_bresp,
    // veriltor lint on UNUSEDSIGNAL
    input wire m_axi_bvalid,
    output reg m_axi_bready
);
    initial
    begin
        m_axi_arvalid = 1'b0;
        m_axi_rready = 1'b0;

        m_axi_awvalid = 1'b0;
        m_axi_wvalid = 1'b0;
        m_axi_bready = 1'b0;
    end

    reg [7:0] state = 0;

    assign busy = (state != 0);

    wire [31:0] y_addr;
    wire [7:0] y_strb;
    wire [7:0] y_data;

    axi_byte_addresser axi_byte_addresser (
        .addr_in(addr),
        .addr_out(y_addr),
        .strb(y_strb),
        .data_in(m_axi_rdata),
        .data_out(y_data)
    );

    reg a_beat;
    reg d_beat;

    always @(posedge aclk)
    begin
        done <= 1'b0;

        case (state)
            0:
            begin
                if (start)
                begin
                    a_beat <= 1'b0;
                    d_beat <= 1'b0;

                    if (write)
                        state <= 2;
                    else
                        state <= 1;
                end
            end

            1: // READ
            begin
                m_axi_araddr <= y_addr;
                m_axi_arvalid <= !a_beat;
                m_axi_rready <= 1'b1;

                if (m_axi_arvalid && m_axi_arready)
                begin
                    a_beat <= 1'b1;
                    m_axi_arvalid <= 1'b0; // deassert cycle "early"
                end

                if (a_beat && m_axi_rvalid && m_axi_rready)
                begin
                    m_axi_rready <= 1'b0;

                    // TODO: check m_axi_rresp
                    data_read <= y_data;
                    done <= 1'b1;

                    state <= 0;
                end
            end

            2: // WRITE
            begin
                m_axi_awaddr <= y_addr;
                m_axi_awvalid <= !a_beat;
                m_axi_wdata <= { 8{data_write} };
                m_axi_wstrb <= y_strb;
                m_axi_wvalid <= !d_beat;
                m_axi_bready <= 1'b1;

                if (m_axi_awvalid && m_axi_awready)
                begin
                    a_beat <= 1'b1;
                    m_axi_awvalid <= 1'b0; // deassert cycle "early"
                end

                if (m_axi_wvalid && m_axi_wready)
                begin
                    d_beat <= 1'b1;
                    m_axi_wvalid <= 1'b0; // deassert cycle "early"
                end

                // TODO: this probably isn't 100% correct but I don't think these can ALL
                // happen on the same cycle as above.
                if (a_beat && d_beat && m_axi_bvalid && m_axi_bready)
                begin
                    m_axi_bready <= 1'b0;

                    // TODO: check m_axi_bresp
                    done <= 1'b1;

                    state <= 0;
                end
            end
        endcase

        if (!aresetn)
        begin
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid <= 1'b0;
            m_axi_bready <= 1'b0;

            state <= 0;
        end
    end
endmodule
