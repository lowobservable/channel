`default_nettype none

`include "assert.v"

`timescale 10ns / 1ns

module channel_out_protocol_tb;
    reg clk = 0;

    reg protocol_reset = 1;
    reg [23:0] protocol_in_tdata = 24'b0;
    reg protocol_in_tvalid = 0;
    reg protocol_out_tready = 0;

    reg [1:0] protocol_data_direction = 2'b00; // Not specified
    reg protocol_burst = 0; // Selector channel behavior

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

        .in_tdata(source.m_axi_tdata),
        .in_tvalid(source.m_axi_tvalid),

        .out_tready(sink.s_axi_tready),

        .data_direction(protocol_data_direction),
        .suppress_status(1'b0),
        .burst(protocol_burst),

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

    axis_source_bfm source (
        .aclk(clk),

        .m_axi_tready(protocol.in_tready)
    );

    axis_sink_bfm sink (
        .aclk(clk),

        .s_axi_tdata(protocol.out_tdata),
        .s_axi_tvalid(protocol.out_tvalid)
    );

    wire terminator;

    reg cu_mock_busy = 0;
    reg cu_mock_short_busy = 0;
    reg cu_mock_request = 0;
    reg [15:0] cu_mock_limit = 0;

    mock_cu #(
        .ADDRESS(8'h1a)
    ) cu (
        .clk(clk),

        .mock_busy(cu_mock_busy),
        .mock_short_busy(cu_mock_short_busy),
        .mock_request(cu_mock_request),
        .mock_limit(cu_mock_limit),

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
        .a_suppress_out()
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
        test_initial_selection_address_not_operational;
        test_initial_selection_busy;
        test_initial_selection_short_busy;
        test_read_command_channel_stop;
        test_write_command_channel_stop;
        test_command_chaining;
        test_request_status_accept;

        $finish;
    end

    task test_system_reset;
        realtime low_time;
        realtime low_duration;
    begin
        $display("START: test_system_reset");

        // Initial, untimed reset...
        reset;

        // Timed reset...
        protocol_reset <= 1;

        @(posedge clk);

        protocol_reset <= 0;

        @(posedge clk);

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

        @(posedge clk);

        $display("END: test_system_reset");
    end
    endtask

    task test_invalid_in;
        reg [23:0] out;
    begin
        $display("START: test_invalid_in");

        reset;

        exec({ 8'h00, 8'h00, 8'h00 }, out); // Invalid

        `assert_equal(out[23:8], { 8'hff, 8'h01 }, "response should be invalid in error");

        @(posedge clk);

        $display("END: test_invalid_in");
    end
    endtask

    task test_initial_selection_address_not_operational;
        reg [23:0] out;
    begin
        $display("START: test_initial_selection_address_not_operational");

        reset;

        exec({ 8'h02, 8'h1b, 8'h02 }, out); // Initial Selection - READ

        `assert_equal(out[23:8], { 8'hff, 8'h02 }, "response should be address not operational error");

        @(posedge clk);

        $display("END: test_initial_selection_address_not_operational");
    end
    endtask

    task test_initial_selection_busy;
        reg [23:0] out;
    begin
        $display("START: test_initial_selection_busy");

        reset;

        cu_mock_busy <= 1;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;

        @(posedge clk);

        exec({ 8'h02, 8'h1a, 8'h02 }, out); // Initial Selection - READ

        `assert_equal(out[23:16], 8'h91, "response should be initial status with valid parity");
        `assert_equal(out[15:8], 8'h1a, "address should be 1A");
        `assert_equal(out[7:0], 8'h10, "status should be BUSY");

        @(posedge clk);

        $display("END: test_initial_selection_busy");
    end
    endtask

    task test_initial_selection_short_busy;
        reg [23:0] out;
    begin
        $display("START: test_initial_selection_short_busy");

        reset;

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 1;
        cu_mock_request <= 0;

        @(posedge clk);

        exec({ 8'h02, 8'h1a, 8'h02 }, out); // Initial Selection - READ

        `assert_equal(out[23:16], 8'hd1, "response should be short busy status with valid parity");
        `assert_equal(out[15:8], 8'h1a, "address should be 1A");
        `assert_equal(out[7:0], 8'h10, "status should be BUSY");

        @(posedge clk);

        $display("END: test_initial_selection_short_busy");
    end
    endtask

    task test_read_command_channel_stop;
        reg [23:0] out;
        reg [7:0] byte;
    begin
        $display("START: test_read_command_channel_stop");

        reset;

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;
        cu_mock_limit <= 16; // CU can provide 16 bytes

        protocol_data_direction <= 2'b10; // Should also work for "not specified"

        @(posedge clk);

        exec({ 8'h02, 8'h1a, 8'h02 }, out); // Initial Selection - READ

        `assert_equal(out[23:16], 8'h91, "response should be initial status with valid parity");
        `assert_equal(out[15:8], 8'h1a, "address should be 1A");
        `assert_equal(out[7:0], 8'h00, "status should be accepted");

        `assert_equal(cu.command, 8'h02, "command should be READ");

        for (byte = 1; byte <= 7; byte = byte + 1)
        begin
            sink.recv(out);

            `assert_equal(out[23:16], 8'h12, "response should be service with valid parity");
            `assert_equal(out[15:8], 8'h1a, "address should be 1A");
            `assert_equal(out[7:0], byte, "data should be expected byte");

            if (byte == 7)
            begin
                exec({ 8'h07, 16'h00 }, out); // Stop
            end
            else
            begin
                exec({ 8'h06, 16'h00 }, out); // Accept Data
            end

            `assert_equal(out, 24'h00, "response should be acknowledgement");
        end

        `assert_equal(cu.count, 6, "count should be 6");

        sink.recv(out);

        `assert_equal(out[23:16], 8'h11, "response should be status with valid parity");
        `assert_equal(out[15:8], 8'h1a, "address should be 1A");
        `assert_equal(out[7:0], 8'h0c, "status should be CE + DE");

        exec({ 8'h03, 16'h00 }, out); // Accept Status - No Chaining

        `assert_equal(out, 24'h00, "response should be acknowledgement");

        `assert_low(cu.command_chaining, "no command chaining");

        @(posedge clk);

        $display("END: test_read_command_channel_stop");
    end
    endtask

    task test_write_command_channel_stop;
        reg [23:0] out;
        reg [7:0] byte;
    begin
        $display("START: test_write_command_channel_stop");

        reset;

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;
        cu_mock_limit <= 16; // CU can provide 16 bytes

        protocol_data_direction <= 2'b11; // Should also work for "not specified"

        @(posedge clk);

        exec({ 8'h02, 8'h1a, 8'h01 }, out); // Initial Selection - WRITE

        `assert_equal(out[23:16], 8'h91, "response should be initial status with valid parity");
        `assert_equal(out[15:8], 8'h1a, "address should be 1A");
        `assert_equal(out[7:0], 8'h00, "status should be accepted");

        `assert_equal(cu.command, 8'h01, "command should be WRITE");

        for (byte = 1; byte <= 7; byte = byte + 1)
        begin
            sink.recv(out);

            `assert_equal(out[19:16], 8'h2, "response should be service");
            `assert_equal(out[15:8], 8'h1a, "address should be 1A");

            if (byte == 7)
            begin
                exec({ 8'h07, 16'h00 }, out); // Stop
            end
            else
            begin
                exec({ 8'h05, byte, 8'h00 }, out); // Send Data
            end

            `assert_equal(out, 24'h00, "response should be acknowledgement");
        end

        `assert_equal(cu.count, 6, "count should be 6");

        sink.recv(out);

        `assert_equal(out[23:16], 8'h11, "response should be status with valid parity");
        `assert_equal(out[15:8], 8'h1a, "address should be 1A");
        `assert_equal(out[7:0], 8'h0c, "status should be CE + DE");

        exec({ 8'h03, 16'h00 }, out); // Accept Status - No Chaining

        `assert_equal(out, 24'h00, "response should be acknowledgement");

        `assert_low(cu.command_chaining, "no command chaining");

        @(posedge clk);

        $display("END: test_write_command_channel_stop");
    end
    endtask

    task test_command_chaining;
        reg [23:0] out;
        reg [7:0] byte;
    begin
        $display("START: test_command_chaining");

        reset;

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;
        cu_mock_limit <= 16; // CU can provide 16 bytes

        protocol_data_direction <= 2'b10; // Should also work for "not specified"

        @(posedge clk);

        exec({ 8'h02, 8'h1a, 8'h02 }, out); // Initial Selection - READ

        `assert_equal(out[23:16], 8'h91, "response should be initial status with valid parity");
        `assert_equal(out[15:8], 8'h1a, "address should be 1A");
        `assert_equal(out[7:0], 8'h00, "status should be accepted");

        `assert_equal(cu.command, 8'h02, "command should be READ");

        for (byte = 1; byte <= 7; byte = byte + 1)
        begin
            sink.recv(out);

            `assert_equal(out[23:16], 8'h12, "response should be service with valid parity");
            `assert_equal(out[15:8], 8'h1a, "address should be 1A");
            `assert_equal(out[7:0], byte, "data should be expected byte");

            if (byte == 7)
            begin
                exec({ 8'h07, 16'h00 }, out); // Stop
            end
            else
            begin
                exec({ 8'h06, 16'h00 }, out); // Accept Data
            end

            `assert_equal(out, 24'h00, "response should be acknowledgement");
        end

        `assert_equal(cu.count, 6, "count should be 6");

        sink.recv(out);

        `assert_equal(out[23:16], 8'h11, "response should be status with valid parity");
        `assert_equal(out[15:8], 8'h1a, "address should be 1A");
        `assert_equal(out[7:0], 8'h0c, "status should be CE + DE");

        exec({ 8'h13, 16'h00 }, out); // Accept Status - Command Chaining

        `assert_equal(out, 24'h00, "response should be acknowledgement");

        `assert_high(cu.command_chaining, "command chaining");

        @(posedge clk);

        exec({ 8'h12, 8'h1a, 8'h03 }, out); // Initial Selection - NOP, Command Chaining

        `assert_equal(out[23:16], 8'h91, "response should be initial status with valid parity");
        `assert_equal(out[15:8], 8'h1a, "address should be 1A");
        `assert_equal(out[7:0], 8'h0c, "status should be CE + DE");

        `assert_equal(cu.command, 8'h03, "command should be NOP");
        `assert_high(cu.command_chained, "command should be chained");

        $display("END: test_command_chaining");
    end
    endtask

    task test_request_status_accept;
        reg [23:0] out;
    begin
        $display("START: test_request_status_accept");

        reset;

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 1;

        @(posedge clk);

        wait(protocol.request);

        exec({ 8'h01, 16'h00 }, out); // Select Requestor

        `assert_equal(out[23:16], 8'h11, "response should be status with valid parity");
        `assert_equal(out[15:8], 8'h1a, "address should be 1A");
        `assert_equal(out[7:0], 8'h85, "status should be ATTN + DE + UX");

        exec({ 8'h03, 16'h00 }, out); // Accept Status - No Chaining

        `assert_equal(out, 24'h00, "response should be acknowledgement");

        @(posedge clk);

        $display("END: test_request_status_accept");
    end
    endtask

    task reset;
    begin
        protocol_reset <= 1;

        @(posedge clk);

        protocol_reset <= 0;

        @(posedge clk);

        wait(operational_out);
    end
    endtask

    task exec (
        input [23:0] in,
        output [23:0] out
    );
    begin
        source.send(in);

        sink.recv(out);
    end
    endtask
endmodule
