`default_nettype none

`include "assert.v"

module channel_tb;
    reg clk = 0;

    wire [7:0] bus_in;
    wire [7:0] bus_out;
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

    reg [7:0] channel_addr;
    reg [7:0] channel_command;
    reg channel_start = 0;
    reg channel_stop = 0;

    reg [7:0] channel_count;

    reg channel_data_send_tvalid = 0;
    wire channel_data_send_tready;
    wire channel_data_recv_tvalid;
    reg channel_data_recv_tready = 0;

    channel channel (
        .clk(clk),
        .enable(1'b1),
        .reset(),

        .a_bus_in(bus_in),
        .a_bus_out(bus_out),
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
        .a_suppress_out(suppress_out),

        .addr(channel_addr),
        .command(channel_command),
        .start(channel_start),
        .stop(channel_stop),

        .data_send_tdata(8'h99),
        .data_send_tvalid(channel_data_send_tvalid),
        .data_send_tready(channel_data_send_tready),
        .data_recv_tvalid(channel_data_recv_tvalid),
        .data_recv_tready(channel_data_recv_tready)
    );

    wire terminator;

    reg cu_mock_busy = 0;
    reg [15:0] cu_mock_limit = 0;

    mock_cu #(
        .ADDRESS(8'h1a),
        .ENABLE_SHORT_BUSY(0)
    ) cu (
        .clk(clk),

        .b_bus_in(bus_in),
        .b_bus_out(bus_out),
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
        .a_bus_out(),
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
        $dumpfile("channel_tb.vcd");
        $dumpvars(0, channel_tb);

        test_no_cu;
        test_busy;
        test_read_command_cu_more;
        test_read_command_cu_less;
        test_write_command_cu_more;
        test_write_command_cu_less;
        test_nop_command;
        test_invalid_command;

        $finish;
    end

    task test_no_cu;
    begin
        $display("START: test_no_cu");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;

        start_channel(8'h10, 8'h02 /* READ */, 6);

        #40;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        $display("END: test_no_cu");
    end
    endtask

    task test_busy;
    begin
        $display("START: test_busy");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 1;

        start_channel(8'h1a, 8'h02 /* READ */, 6);

        #100;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        $display("END: test_busy");
    end
    endtask

    task test_read_command_cu_more;
    begin
        $display("START: test_read_command_cu_more");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_limit = 16; // CU can provide 16 bytes

        start_channel(8'h1a, 8'h02 /* READ */, 6);

        #300;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel_count, 0, "count should be 0")

        $display("END: test_read_command_cu_more");
    end
    endtask

    task test_read_command_cu_less;
    begin
        $display("START: test_read_command_cu_less");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_limit = 6; // CU can provide 6 bytes

        start_channel(8'h1a, 8'h02 /* READ */, 16);

        #300;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel_count, 10, "count should be 10")

        $display("END: test_read_command_cu_less");
    end
    endtask

    task test_write_command_cu_more;
    begin
        $display("START: test_write_command_cu_more");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_limit = 16; // CU can accept 16 bytes

        start_channel(8'h1a, 8'h01 /* WRITE */, 6);

        #300;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel_count, 0, "count should be 0")

        $display("END: test_write_command_cu_more");
    end
    endtask

    task test_write_command_cu_less;
    begin
        $display("START: test_write_command_cu_less");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_limit = 6; // CU can accept 6 bytes

        start_channel(8'h1a, 8'h01 /* WRITE */, 16);

        #300;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel_count, 10, "count should be 10")

        $display("END: test_write_command_cu_less");
    end
    endtask

    task test_nop_command;
    begin
        $display("START: test_nop_command");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;

        start_channel(8'h1a, 8'h03 /* NOP */, 0);

        #100;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        $display("END: test_nop_command");
    end
    endtask

    task test_invalid_command;
    begin
        $display("START: test_invalid_command");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;

        start_channel(8'h1a, 8'hff, 6);

        #100;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

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

        channel_start = 1;

        #2;
        channel_start = 0;
    end
    endtask

    always @(posedge clk)
    begin
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
    end
endmodule
