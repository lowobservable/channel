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

module axis_sink_bfm (
    input wire aclk,

    input wire [23:0] s_axi_tdata,
    input wire s_axi_tvalid,
    output reg s_axi_tready
);
    initial
    begin
        s_axi_tready <= 0;
    end

    task recv (
        output [23:0] data
    );
    begin
        @(posedge aclk);

        s_axi_tready <= 1;

        @(posedge aclk);

        while (s_axi_tready)
        begin
            if (s_axi_tvalid)
            begin
                s_axi_tready <= 0;

                data <= s_axi_tdata;
            end

            @(posedge aclk);
        end
    end
    endtask
endmodule
