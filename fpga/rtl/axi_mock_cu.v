`default_nettype none

module axi_mock_cu (
    input wire aclk,
    input wire aresetn,

    // Parallel Channel "B"...
    output wire [7:0] b_bus_in,
    output wire b_bus_in_parity,
    input wire [7:0] b_bus_out,
    input wire b_bus_out_parity,

    input wire b_operational_out,
    output wire b_request_in,
    input wire b_hold_out,
    input wire b_select_out,
    output wire b_select_in,
    input wire b_address_out,
    output wire b_operational_in,
    output wire b_address_in,
    input wire b_command_out,
    output wire b_status_in,
    output wire b_service_in,
    input wire b_service_out,
    input wire b_suppress_out,

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
    input wire s_axi_bready
);
    localparam REG_CONTROL = 8'h00;
    localparam REG_STATUS = 8'h04;

    initial
    begin
        s_axi_arready = 1'b1;
        s_axi_rvalid = 1'b0;

        s_axi_awready = 1'b1;
        s_axi_wready = 1'b1;
        s_axi_bvalid = 1'b0;
    end

    reg mock_busy;
    reg [15:0] mock_limit;
    wire [7:0] command;
    wire [15:0] count;

    always @(posedge aclk)
    begin
        if (s_axi_arvalid && s_axi_arready)
        begin
            s_axi_rdata <= 32'b0;
            s_axi_rresp <= 2'b00;

            case (s_axi_araddr)
                REG_CONTROL:
                    s_axi_rdata <= { mock_limit, 14'b0, mock_busy, 1'b0 };

                REG_STATUS:
                    s_axi_rdata <= { count, command, 8'b0 };

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
    // verilator lint_off UNUSEDSIGNAL
    reg [31:0] wdata;
    // verilator lint_on UNUSEDSIGNAL
    reg wdata_full;

    always @(posedge aclk)
    begin
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
                REG_CONTROL:
                begin
                    mock_busy <= wdata[1];
                    mock_limit <= wdata[31:16];
                end

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
            awaddr_full <= 1'b0;
            wdata_full <= 1'b0;

            s_axi_awready <= 1'b1;
            s_axi_wready <= 1'b1;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
        end
    end

    mock_cu mock_cu (
        .clk(aclk),
        .reset(~aresetn),

        .b_bus_in(b_bus_in),
        .b_bus_in_parity(b_bus_in_parity),
        .b_bus_out(b_bus_out),
        .b_bus_out_parity(b_bus_out_parity),
        .b_operational_out(b_operational_out),
        .b_request_in(b_request_in),
        .b_hold_out(b_hold_out),
        .b_select_out(b_select_out),
        .b_select_in(b_select_in),
        .b_address_out(b_address_out),
        .b_operational_in(b_operational_in),
        .b_address_in(b_address_in),
        .b_command_out(b_command_out),
        .b_status_in(b_status_in),
        .b_service_in(b_service_in),
        .b_service_out(b_service_out),
        .b_suppress_out(b_suppress_out),

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

        .mock_busy(mock_busy),
        .mock_limit(mock_limit),

        .command(command),
        .count(count)
    );
endmodule
