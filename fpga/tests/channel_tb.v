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

    reg [7:0] channel_address;
    reg [7:0] channel_command;
    reg [7:0] channel_count;
    reg channel_start_strobe = 0;

    channel channel (
        .clk(clk),
        .reset(),

        .bus_in(bus_in),
        .bus_out(bus_out),
        .operational_out(operational_out),
        .request_in(request_in),
        .hold_out(hold_out),
        .select_out(select_out),
        .select_in(select_in),
        .address_out(address_out),
        .operational_in(operational_in),
        .address_in(address_in),
        .command_out(command_out),
        .status_in(status_in),
        .service_in(service_in),
        .service_out(service_out),
        .suppress_out(suppress_out),

        .address(channel_address),
        .command(channel_command),
        .count(channel_count),
        .start_strobe(channel_start_strobe)
    );

    wire cu_select_out;
    wire cu_select_in;

    reg cu_mock_busy = 0;
    reg [7:0] cu_mock_read_count = 0;
    reg [7:0] cu_mock_write_count = 0;

    mock_cu #(
        .ADDRESS(8'h1a),
        .ENABLE_SHORT_BUSY(0)
    ) cu (
        .clk(clk),

        .bus_in(bus_in),
        .bus_out(bus_out),
        .operational_out(operational_out),
        .request_in(request_in),
        .hold_out(hold_out),
        .a_select_out(select_out),
        .a_select_in(select_in),
        .address_out(address_out),
        .operational_in(operational_in),
        .address_in(address_in),
        .command_out(command_out),
        .status_in(status_in),
        .service_in(service_in),
        .service_out(service_out),
        .suppress_out(suppress_out),

        .b_select_out(cu_select_out),
        .b_select_in(cu_select_in),

        .mock_busy(cu_mock_busy),
        .mock_read_count(cu_mock_read_count),
        .mock_write_count(cu_mock_write_count)
    );

    terminator terminator (
        .clk(clk),

        .select_out(cu_select_out),
        .select_in(cu_select_in)
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

        channel_start(8'h10, 8'h02 /* READ */, 6);

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

        channel_start(8'h1a, 8'h02 /* READ */, 6);

        #60;

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
        cu_mock_read_count = 16; // CU can provide 16 bytes

        channel_start(8'h1a, 8'h02 /* READ */, 6);

        #170;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel.res_count, 0, "channel residual count should be 0")

        $display("END: test_read_command_cu_more");
    end
    endtask

    task test_read_command_cu_less;
    begin
        $display("START: test_read_command_cu_less");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_read_count = 6; // CU can provide 6 bytes

        channel_start(8'h1a, 8'h02 /* READ */, 16);

        #170;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel.res_count, 10, "channel residual count should be 10")

        $display("END: test_read_command_cu_less");
    end
    endtask

    task test_write_command_cu_more;
    begin
        $display("START: test_write_command_cu_more");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_write_count = 16; // CU can accept 16 bytes

        channel_start(8'h1a, 8'h01 /* WRITE */, 6);

        #170;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel.res_count, 0, "channel residual count should be 0")

        $display("END: test_write_command_cu_more");
    end
    endtask

    task test_write_command_cu_less;
    begin
        $display("START: test_write_command_cu_less");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;
        cu_mock_write_count = 6; // CU can accept 6 bytes

        channel_start(8'h1a, 8'h01 /* WRITE */, 16);

        #170;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        `assert_equal(channel.res_count, 10, "channel residual count should be 10")

        $display("END: test_write_command_cu_less");
    end
    endtask

    task test_nop_command;
    begin
        $display("START: test_nop_command");

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        #3;

        cu_mock_busy = 0;

        channel_start(8'h1a, 8'h03 /* NOP */, 0);

        #60;

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

        channel_start(8'h1a, 8'hff, 6);

        #60;

        `assert_equal(channel.state, channel.STATE_IDLE, "channel state should be IDLE")

        $display("END: test_invalid_command");
    end
    endtask

    task channel_start (
        input [7:0] address,
        input [7:0] command,
        input [7:0] count
    );
    begin
        channel_address = address;
        channel_command = command;
        channel_count = count;
        channel_start_strobe = 1;

        #2;
        channel_start_strobe = 0;
    end
    endtask
endmodule
