// Copyright (c) 2025, Andrew Kay
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

module axil_master_bfm (
    input wire aclk,
    input wire aresetn,

    output reg [7:0] m_axi_araddr,
    output reg m_axi_arvalid,
    input wire m_axi_arready,

    input wire [31:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rvalid,
    output reg m_axi_rready,

    output reg [7:0] m_axi_awaddr,
    output reg m_axi_awvalid,
    input wire m_axi_awready,

    output reg [31:0] m_axi_wdata,
    output reg [3:0] m_axi_wstrb,
    output reg m_axi_wvalid,
    input wire m_axi_wready,

    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output reg m_axi_bready
);
    initial
    begin
        m_axi_arvalid <= 0;
        m_axi_rready <= 0;
    end

    task read (
        input [7:0] addr,
        output [31:0] data,
        output [1:0] resp
    );
    begin
        @(posedge aclk);

        m_axi_araddr <= addr;
        m_axi_arvalid <= 1;
        m_axi_rready <= 1;

        @(posedge aclk);

        while (m_axi_arvalid)
        begin
            if (m_axi_arready)
            begin
                m_axi_arvalid <= 0;
            end

            @(posedge aclk);
        end

        while (m_axi_rready)
        begin
            if (m_axi_rvalid)
            begin
                m_axi_rready <= 0;

                data <= m_axi_rdata;
                resp <= m_axi_rresp;
            end

            @(posedge aclk);
        end
    end
    endtask

    task write (
        input [7:0] addr,
        input [31:0] data,
        output [1:0] resp
    );
    begin
        @(posedge aclk);

        m_axi_awaddr <= addr;
        m_axi_awvalid <= 1;
        m_axi_wdata <= data;
        m_axi_wvalid <= 1;
        m_axi_bready <= 1;

        @(posedge aclk);

        while (m_axi_awvalid || m_axi_wvalid)
        begin
            if (m_axi_awready && m_axi_awvalid)
            begin
                m_axi_awvalid <= 0;
            end

            if (m_axi_wready && m_axi_wvalid)
            begin
                m_axi_wvalid <= 0;
            end

            @(posedge aclk);
        end

        while (m_axi_bready)
        begin
            if (m_axi_bvalid)
            begin
                m_axi_bready <= 0;

                resp <= m_axi_bresp;
            end

            @(posedge aclk);
        end
    end
    endtask
endmodule
