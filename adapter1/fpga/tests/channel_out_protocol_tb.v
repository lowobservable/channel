`default_nettype none

`include "assert.v"

`timescale 10ns / 1ns

module channel_out_protocol_tb;
    reg clk = 0;

    reg protocol_reset = 1;
    reg [23:0] protocol_in_tdata = 24'b0;
    reg protocol_in_tvalid = 0;
    reg protocol_out_tready = 0;

    wire [7:0] bus_in;
    wire bus_in_parity;
    wire [7:0] bus_out;
    wire bus_out_parity;
    wire operational_out;
    wire request_in;
    wire hold_out;
    wire select_out;
    wire select_in;
    wire address_out;
    wire operational_in;
    wire address_in;
    wire command_out;
    wire status_in;
    wire service_in;
    wire service_out;
    wire suppress_out;

    channel_out_protocol #(
        .CLOCKS_PER_100_NS(5),
        .SYSTEM_RESET_DURATION_100_NS(6) // Reduced for testing, should be 60 (6 μs)
    ) protocol (
        .clk(clk),
        .reset(protocol_reset),

        .in_tdata(protocol_in_tdata),
        .in_tvalid(protocol_in_tvalid),
        .in_tready(),

        .out_tdata(),
        .out_tvalid(),
        .out_tready(protocol_out_tready),

        .a_bus_in(bus_in),
        .a_bus_in_parity(bus_in_parity),
        .a_bus_out(bus_out),
        .a_bus_out_parity(bus_out_parity),
        .a_operational_out(operational_out),
        .a_request_in(request_in),
        .a_hold_out(hold_out),
        .a_select_out(select_out),
        .a_select_in(select_in),
        .a_address_out(address_out),
        .a_operational_in(operational_in),
        .a_address_in(address_in),
        .a_command_out(command_out),
        .a_status_in(status_in),
        .a_service_in(service_in),
        .a_service_out(service_out),
        .a_suppress_out(suppress_out)
    );

    wire terminator;

    reg cu_mock_busy = 0;
    reg cu_mock_short_busy = 0;
    reg [15:0] cu_mock_limit = 0;

    mock_cu #(
        .ADDRESS(8'h1a)
    ) cu (
        .clk(clk),

        .b_bus_in(bus_in),
        .b_bus_in_parity(bus_in_parity),
        .b_bus_out(bus_out),
        .b_bus_out_parity(bus_out_parity),
        .b_operational_out(operational_out),
        .b_request_in(request_in),
        .b_hold_out(hold_out),
        .b_select_out(select_out),
        .b_select_in(select_in),
        .b_address_out(address_out),
        .b_operational_in(operational_in),
        .b_address_in(address_in),
        .b_command_out(command_out),
        .b_status_in(status_in),
        .b_service_in(service_in),
        .b_service_out(service_out),
        .b_suppress_out(suppress_out),

        .a_bus_in(8'b0),
        .a_bus_in_parity(1'b0),
        .a_bus_out(),
        .a_bus_out_parity(),
        .a_operational_out(),
        .a_request_in(1'b0),
        .a_hold_out(),
        .a_select_out(terminator),
        .a_select_in(terminator),
        .a_address_out(),
        .a_operational_in(1'b0),
        .a_address_in(1'b0),
        .a_command_out(),
        .a_status_in(1'b0),
        .a_service_in(1'b0),
        .a_service_out(),
        .a_suppress_out(),

        .mock_busy(cu_mock_busy),
        .mock_short_busy(cu_mock_short_busy),
        .mock_limit(cu_mock_limit)
    );

    initial
    begin
        forever
        begin
            #1 clk = ~clk;
        end
    end

    initial
    begin
        $dumpfile("channel_out_protocol_tb.vcd");
        $dumpvars(0, channel_out_protocol_tb);

        test_system_reset;
        test_invalid_in;

        /*
        test_no_cu;
        test_busy;
        test_short_busy;
        test_read_command_cu_more;
        test_read_command_cu_less;
        test_write_command_cu_more;
        test_write_command_cu_less;
        test_nop_command;
        test_invalid_command;
        */

        $finish;
    end

    task test_system_reset;
        realtime low_time;
        realtime low_duration;
    begin
        $display("START: test_system_reset");

        // Initial, untimed reset...
        @(posedge clk)
        begin
            protocol_reset = 0;
        end

        @(posedge operational_out);

        // Timed reset...
        @(posedge clk)
        begin
            protocol_reset = 1;
        end

        @(posedge clk)
        begin
            protocol_reset = 0;
        end

        @(negedge operational_out)
        begin
            low_time = $time;
        end

        `assert_low(operational_out, "operational_out should be LOW");
        `assert_low(suppress_out, "suppress_out should be LOW");

        @(posedge operational_out or suppress_out)
        begin
            low_duration = $time - low_time;
        end

        `assert_high(operational_out, "operational_out should be HIGH");
        `assert_low(suppress_out, "suppress_out should be LOW");

        $display("operational_out and suppress_out were LOW for %0t ns", low_duration);

        if (low_duration * 10 < 600)
        begin
            // 6 μs (6000 ns) is scaled to 600 ns for this test.
            `assert_fail("To ensure a proper reset, 'operational out' and 'suppress out' are down concurrently for at least 6 μs");
        end

        `assert_high(protocol.in_tready, "in should be TREADY");

        $display("END: test_system_reset");
    end
    endtask

    task test_invalid_in;
        reg [23:0] out;
    begin
        $display("START: test_invalid_in");

        @(posedge clk);

        exec({ 8'h00, 8'h00, 8'h00 }, out);

        `assert_equal(out, { 8'hff, 8'h01, 8'h00 }, "out should be invalid in error");

        $display("END: test_invalid_in");
    end
    endtask

    task exec (
        input [23:0] in,
        output [23:0] out
    );
    begin
        @(posedge clk)
        begin
            protocol_in_tdata = in;
            protocol_in_tvalid = 1;

            protocol_out_tready = 1;
        end

        while (protocol_in_tvalid)
        begin
            @(posedge clk)
            begin
                if (protocol.in_tready)
                begin
                    $display("Request: %h", in);

                    protocol_in_tvalid = 0;
                end
            end
        end

        while (protocol_out_tready)
        begin
            @(posedge clk)
            begin
                if (protocol.out_tvalid)
                begin
                    out = protocol.out_tdata;

                    $display("Response: %h", out);

                    protocol_out_tready = 0;
                end
            end
        end
    end
    endtask

    /*
    task test_no_cu;
    begin
        $display("START: test_no_cu");

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_short_busy = 0;

        start_channel(8'h10, 8'h02, 6); // READ

        #200;

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel_condition_code, 3, "condition code should be not operational");

        $display("END: test_no_cu");
    end
    endtask

    task test_busy;
    begin
        $display("START: test_busy");

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 1;
        cu_mock_short_busy = 0;

        start_channel(8'h1a, 8'h02, 6); // READ

        #200;

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel_status, 8'h10, "status should be BUSY");

        $display("END: test_busy");
    end
    endtask

    task test_short_busy;
    begin
        $display("START: test_short_busy");

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_short_busy = 1;

        start_channel(8'h1a, 8'h02, 6); // READ

        #200;

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel_status, 8'h10, "status should be BUSY");

        $display("END: test_short_busy");
    end
    endtask

    task test_read_command_cu_more;
    begin
        $display("START: test_read_command_cu_more");

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_short_busy = 0;
        cu_mock_limit = 16; // CU can provide 16 bytes

        start_channel(8'h1a, 8'h02, 6); // READ

        #600;

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel_count, 0, "count should be 0")

        $display("END: test_read_command_cu_more");
    end
    endtask

    task test_read_command_cu_less;
    begin
        $display("START: test_read_command_cu_less");

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_short_busy = 0;
        cu_mock_limit = 6; // CU can provide 6 bytes

        start_channel(8'h1a, 8'h02, 16); // READ

        #500;

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel_count, 10, "count should be 10")

        $display("END: test_read_command_cu_less");
    end
    endtask

    task test_write_command_cu_more;
    begin
        $display("START: test_write_command_cu_more");

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_short_busy = 0;
        cu_mock_limit = 16; // CU can accept 16 bytes

        start_channel(8'h1a, 8'h01, 6); // WRITE

        #500;

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel_count, 0, "count should be 0")

        $display("END: test_write_command_cu_more");
    end
    endtask

    task test_write_command_cu_less;
    begin
        $display("START: test_write_command_cu_less");

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_short_busy = 0;
        cu_mock_limit = 6; // CU can accept 6 bytes

        start_channel(8'h1a, 8'h01, 16); // WRITE

        #500;

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel_count, 10, "count should be 10")

        $display("END: test_write_command_cu_less");
    end
    endtask

    task test_nop_command;
    begin
        $display("START: test_nop_command");

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_short_busy = 0;

        start_channel(8'h1a, 8'h03, 0); // NOP

        #200;

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        $display("END: test_nop_command");
    end
    endtask

    task test_invalid_command;
    begin
        $display("START: test_invalid_command");

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_short_busy = 0;

        start_channel(8'h1a, 8'hff, 6);

        #200;

        `assert_equal(protocol.state, protocol.STATE_IDLE, "channel state should be IDLE")

        $display("END: test_invalid_command");
    end
    endtask

    task start_channel (
        input [7:0] addr,
        input [7:0] command,
        input [7:0] count
    );
    begin
        channel_addr = addr;
        channel_command = command;
        channel_count = count;

        channel_data_send_tdata = 1;

        channel_start = 1;

        #2;
        channel_start = 0;
    end
    endtask

    always @(posedge clk)
    begin
        if (channel_status_tvalid)
        begin
            channel_status <= channel_status_tdata;
        end

        channel_stop <= 0;

        channel_data_send_tvalid <= 0;
        channel_data_recv_tready <= 0;

        if (channel_data_send_tready || channel_data_recv_tvalid)
        begin
            if (channel_count == 0)
            begin
                channel_stop <= 1;
            end
            else
            begin
                channel_data_send_tvalid <= 1;
                channel_data_recv_tready <= 1;
            end
        end

        if ((channel_data_send_tvalid && channel_data_send_tready) || (channel_data_recv_tvalid && channel_data_recv_tready))
        begin
            channel_count <= channel_count - 1;
        end

        if ((channel_data_send_tvalid && channel_data_send_tready))
        begin
            channel_data_send_tdata <= channel_data_send_tdata + 1;
        end
    end
    */
endmodule
