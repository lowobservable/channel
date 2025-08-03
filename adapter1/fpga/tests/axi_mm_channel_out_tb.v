`default_nettype none

`include "assert.v"

`timescale 10ns / 1ns

module axi_mm_channel_out_tb;
    reg clk = 0;

    reg channel_reset = 1;

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

    wire [19:0] wrap;

    axi_mm_channel_out #(
        .CLOCKS_PER_100_NS(5)
    ) channel (
        .aclk(clk),
        .aresetn(!channel_reset),

        // AXI4-Lite control interface...
        .s_axi_araddr(control_bfm.m_axi_araddr),
        .s_axi_arvalid(control_bfm.m_axi_arvalid),
        .s_axi_rready(control_bfm.m_axi_rready),
        .s_axi_awaddr(control_bfm.m_axi_awaddr),
        .s_axi_awvalid(control_bfm.m_axi_awvalid),
        .s_axi_wdata(control_bfm.m_axi_wdata),
        .s_axi_wstrb(control_bfm.m_axi_wstrb),
        .s_axi_wvalid(control_bfm.m_axi_wvalid),
        .s_axi_bready(control_bfm.m_axi_bready),

        // AXI4-Lite storage interface...
        .m_axi_arready(storage_bfm.s_axi_arready),
        .m_axi_rdata(storage_bfm.s_axi_rdata),
        .m_axi_rresp(storage_bfm.s_axi_rresp),
        .m_axi_rvalid(storage_bfm.s_axi_rvalid),
        .m_axi_awready(storage_bfm.s_axi_awready),
        .m_axi_wready(storage_bfm.s_axi_wready),
        .m_axi_bresp(storage_bfm.s_axi_bresp),
        .m_axi_bvalid(storage_bfm.s_axi_bvalid),

        // Parallel Channel "A"...
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
        .a_suppress_out(suppress_out),

        .wrap_tester_driver(wrap),
        .wrap_tester_receiver(wrap)
    );

    axil_master_bfm control_bfm (
        .aclk(clk),

        .m_axi_arready(channel.s_axi_arready),
        .m_axi_rdata(channel.s_axi_rdata),
        .m_axi_rresp(channel.s_axi_rresp),
        .m_axi_rvalid(channel.s_axi_rvalid),
        .m_axi_awready(channel.s_axi_awready),
        .m_axi_wready(channel.s_axi_wready),
        .m_axi_bresp(channel.s_axi_bresp),
        .m_axi_bvalid(channel.s_axi_bvalid)
    );

    axil_slave_bfm storage_bfm (
        .aclk(clk),

        .s_axi_araddr(channel.m_axi_araddr),
        .s_axi_arvalid(channel.m_axi_arvalid),
        .s_axi_rready(channel.m_axi_rready),
        .s_axi_awaddr(channel.m_axi_awaddr),
        .s_axi_awvalid(channel.m_axi_awvalid),
        .s_axi_wdata(channel.m_axi_wdata),
        .s_axi_wstrb(channel.m_axi_wstrb),
        .s_axi_wvalid(channel.m_axi_wvalid),
        .s_axi_bready(channel.m_axi_bready)
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
        .mock_request(cu_mock_request),
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
        $dumpfile("axi_mm_channel_out_tb.vcd");
        $dumpvars(0, axi_mm_channel_out_tb);

        test_read_register;
        test_write_register;
        test_enable_disable_channel;
        test_unsolicited_status_device_disabled;
        test_unsolicited_status_device_enabled;
        test_start_device_disabled;
        test_start_device_not_operational;
        test_start_status_pending;
        test_start_device_busy;
        test_start_reserved_command;
        test_start_immediate_command;
        test_read_command_channel_stop;
        test_read_command_cu_stop;
        test_write_command_channel_stop;
        test_write_command_cu_stop;
        test_wrap_tester;

        $finish;
    end

    task test_read_register;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_read_register");

        reset;

        control_bfm.read(channel.REG_CHANNEL_1, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");
        `assert_equal(data, 32'b0, "register should be zero");

        $display("END: test_read_register");
    end
    endtask

    task test_write_register;
        reg [1:0] resp;
    begin
        $display("START: test_write_register");

        reset;

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        $display("END: test_write_register");
    end
    endtask

    task test_enable_disable_channel;
        reg [1:0] resp;
    begin
        $display("START: test_enable_disable_channel");

        reset;

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        wait(channel.channel_enable);
        wait(channel.a_operational_out);

        repeat(10) @(posedge clk);

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        wait(!channel.channel_enable);
        wait(!channel.a_operational_out);

        $display("END: test_enable_disable_channel");
    end
    endtask

    task test_wrap_tester;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_wrap_tester");

        reset;

        // Enable only the wrap tester, in a practical design the frontend would
        // also need to be enabled for a wrap test.
        control_bfm.write(channel.REG_CHANNEL_3, 32'hfffff100, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        wait(channel.wrap_tester_enable);

        `assert_equal(channel.wrap_tester_driver, 20'hfffff, "wrap tester driver should be HIGH");

        control_bfm.read(channel.REG_CHANNEL_4, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");
        `assert_equal(data[31:12], channel.wrap_tester_receiver, "register should match receiver");

        control_bfm.write(channel.REG_CHANNEL_3, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        wait(!channel.wrap_tester_enable);

        $display("END: test_wrap_tester");
    end
    endtask

    task test_unsolicited_status_device_disabled;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_unsolicited_status_device_disabled");

        reset;

        // Ensure that one-shot request mock is reset.
        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;

        @(posedge clk);

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 1;

        @(posedge clk);

        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b0;

        while (!data[14])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (!data[14])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_high(data[14], "status should be stacked");

        // Enable the device.
        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b0;

        while (!data[15])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (!data[15])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_high(data[15], "status should be pending");
        `assert_equal(data[23:16], 8'h85, "status should be ATTN + DE + UX");

        // Clear the pending status.
        control_bfm.write(channel.REG_DEVICE_2, 32'h00008000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.read(channel.REG_DEVICE_2, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");
        `assert_low(data[15], "not status pending");

        $display("END: test_unsolicited_status_device_disabled");
    end
    endtask

    task test_unsolicited_status_device_enabled;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_unsolicited_status_device_enabled");

        reset;

        // Ensure that one-shot request mock is reset.
        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;

        @(posedge clk);

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 1;

        @(posedge clk);

        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b0;

        while (!data[15])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (!data[15])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_high(data[15], "status should be pending");
        `assert_equal(data[23:16], 8'h85, "status should be ATTN + DE + UX");

        // Clear the pending status.
        control_bfm.write(channel.REG_DEVICE_2, 32'h00008000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.read(channel.REG_DEVICE_2, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");
        `assert_low(data[15], "not status pending");

        $display("END: test_unsolicited_status_device_enabled");
    end
    endtask

    task test_start_device_disabled;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_start_device_disabled");

        reset;

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        // Start NOP.
        control_bfm.write(channel.REG_DEVICE_3, 32'h00000003, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_4, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_2, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b1;

        while (data[0])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (data[0])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_low(data[0], "not start pending");
        `assert_equal(data[7:4], 4'h1, "condition code should be device disabled");

        $display("END: test_start_device_disabled");
    end
    endtask

    task test_start_device_not_operational;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_start_device_not_operational");

        reset;

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_1, 32'h1b000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        // Start NOP.
        control_bfm.write(channel.REG_DEVICE_3, 32'h00000003, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_4, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_2, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b1;

        while (data[0])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (data[0])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_low(data[0], "not start pending");
        `assert_equal(data[7:4], 4'h2, "condition code should be device not operational");

        $display("END: test_start_device_not_operational");
    end
    endtask

    task test_start_status_pending;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_start_status_pending");

        reset;

        // Ensure that one-shot request mock is reset.
        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;

        @(posedge clk);

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 1;

        @(posedge clk);

        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b0;

        while (!data[15])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (!data[15])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_high(data[15], "status should be pending");
        `assert_equal(data[23:16], 8'h85, "status should be ATTN + DE + UX");

        // Start NOP.
        control_bfm.write(channel.REG_DEVICE_3, 32'h00000003, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_4, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_2, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b1;

        while (data[0])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (data[0])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_low(data[0], "not start pending");
        `assert_equal(data[7:4], 4'h3, "condition code should be status pending");

        $display("END: test_start_status_pending");
    end
    endtask

    task test_start_device_busy;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_start_device_busy");

        reset;

        cu_mock_busy <= 1;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;

        @(posedge clk);

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        // Start NOP.
        control_bfm.write(channel.REG_DEVICE_3, 32'h00000003, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_4, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_2, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b1;

        while (data[0])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (data[0])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_low(data[0], "not start pending");
        `assert_equal(data[7:4], 4'h4, "condition code should be device busy");

        $display("END: test_start_device_busy");
    end
    endtask

    task test_start_reserved_command;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_start_reserved_command");

        reset;

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;

        @(posedge clk);

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        // Start TEST I/O.
        control_bfm.write(channel.REG_DEVICE_3, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_4, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_2, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b1;

        while (data[0])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (data[0])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_low(data[0], "not start pending");
        `assert_equal(data[7:4], 4'h5, "condition code should be reserved command");

        $display("END: test_start_reserved_command");
    end
    endtask

    task test_start_immediate_command;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_start_immediate_command");

        reset;

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;

        @(posedge clk);

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        // Start NOP.
        control_bfm.write(channel.REG_DEVICE_3, 32'h00000003, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_4, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_2, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b1;

        while (data[0])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (data[0])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_low(data[0], "not start pending");
        `assert_equal(data[7:4], 4'h0, "condition code should be started");

        `assert_high(data[15], "status should be pending");
        `assert_equal(data[23:16], 8'h0c, "status should be CE + DE");

        `assert_low(channel.subchannel_active, "not subchannel active");
        `assert_low(channel.device_active, "not device active");

        // Clear the pending status.
        control_bfm.write(channel.REG_DEVICE_2, 32'h00008000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.read(channel.REG_DEVICE_2, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");
        `assert_low(data[15], "not status pending");

        $display("END: test_start_immediate_command");
    end
    endtask

    task test_read_command_channel_stop;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_read_command_channel_stop");

        reset;

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;
        cu_mock_limit <= 16; // CU can provide 16 bytes

        @(posedge clk);

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        // Start READ with count 6.
        control_bfm.write(channel.REG_DEVICE_3, 32'h00060002, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_4, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_2, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b1;

        while (data[0])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (data[0])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_low(data[0], "not start pending");
        `assert_equal(data[7:4], 4'h0, "condition code should be started");

        data = 32'b0;

        while (!data[15])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (!data[15])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_high(data[15], "status should be pending");
        `assert_equal(data[23:16], 8'h0c, "status should be CE + DE");

        `assert_low(channel.subchannel_active, "not subchannel active");
        `assert_low(channel.device_active, "not device active");

        control_bfm.read(channel.REG_DEVICE_3, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");

        `assert_equal(data[31:16], 0, "residual count should be 0");

        // Clear the pending status.
        control_bfm.write(channel.REG_DEVICE_2, 32'h00008000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.read(channel.REG_DEVICE_2, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");
        `assert_low(data[15], "not status pending");

        $display("END: test_read_command_channel_stop");
    end
    endtask

    task test_read_command_cu_stop;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_read_command_cu_stop");

        reset;

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;
        cu_mock_limit <= 6; // CU can provide 6 bytes

        @(posedge clk);

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        // Start READ with count 6.
        control_bfm.write(channel.REG_DEVICE_3, 32'h00100002, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_4, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_2, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b1;

        while (data[0])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (data[0])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_low(data[0], "not start pending");
        `assert_equal(data[7:4], 4'h0, "condition code should be started");

        data = 32'b0;

        while (!data[15])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (!data[15])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_high(data[15], "status should be pending");
        `assert_equal(data[23:16], 8'h0c, "status should be CE + DE");

        `assert_low(channel.subchannel_active, "not subchannel active");
        `assert_low(channel.device_active, "not device active");

        control_bfm.read(channel.REG_DEVICE_3, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");

        `assert_equal(data[31:16], 10, "residual count should be 10");

        // Clear the pending status.
        control_bfm.write(channel.REG_DEVICE_2, 32'h00008000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.read(channel.REG_DEVICE_2, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");
        `assert_low(data[15], "not status pending");

        $display("END: test_read_command_cu_stop");
    end
    endtask

    task test_write_command_channel_stop;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_write_command_channel_stop");

        reset;

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;
        cu_mock_limit <= 16; // CU can accept 16 bytes

        @(posedge clk);

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        // Start WRITE with count 6.
        control_bfm.write(channel.REG_DEVICE_3, 32'h00060001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_4, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_2, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b1;

        while (data[0])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (data[0])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_low(data[0], "not start pending");
        `assert_equal(data[7:4], 4'h0, "condition code should be started");

        data = 32'b0;

        while (!data[15])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (!data[15])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_high(data[15], "status should be pending");
        `assert_equal(data[23:16], 8'h0c, "status should be CE + DE");

        `assert_low(channel.subchannel_active, "not subchannel active");
        `assert_low(channel.device_active, "not device active");

        control_bfm.read(channel.REG_DEVICE_3, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");

        `assert_equal(data[31:16], 0, "residual count should be 0");

        // Clear the pending status.
        control_bfm.write(channel.REG_DEVICE_2, 32'h00008000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.read(channel.REG_DEVICE_2, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");
        `assert_low(data[15], "not status pending");

        $display("END: test_write_command_channel_stop");
    end
    endtask

    task test_write_command_cu_stop;
        reg [31:0] data;
        reg [1:0] resp;
    begin
        $display("START: test_write_command_cu_stop");

        reset;

        cu_mock_busy <= 0;
        cu_mock_short_busy <= 0;
        cu_mock_request <= 0;
        cu_mock_limit <= 6; // CU can accept 6 bytes

        @(posedge clk);

        control_bfm.write(channel.REG_CHANNEL_1, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_1, 32'h1a000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        // Start WRITE with count 6.
        control_bfm.write(channel.REG_DEVICE_3, 32'h00100001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_4, 32'h00000000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.write(channel.REG_DEVICE_2, 32'h00000001, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        data = 32'b1;

        while (data[0])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (data[0])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_low(data[0], "not start pending");
        `assert_equal(data[7:4], 4'h0, "condition code should be started");

        data = 32'b0;

        while (!data[15])
        begin
            control_bfm.read(channel.REG_DEVICE_2, data, resp);

            `assert_equal(resp, 2'b00, "read should be successful");

            if (!data[15])
            begin
                repeat (100) @(posedge clk);
            end
        end

        `assert_high(data[15], "status should be pending");
        `assert_equal(data[23:16], 8'h0c, "status should be CE + DE");

        `assert_low(channel.subchannel_active, "not subchannel active");
        `assert_low(channel.device_active, "not device active");

        control_bfm.read(channel.REG_DEVICE_3, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");

        `assert_equal(data[31:16], 10, "residual count should be 10");

        // Clear the pending status.
        control_bfm.write(channel.REG_DEVICE_2, 32'h00008000, resp);

        `assert_equal(resp, 2'b00, "write should be successful");

        control_bfm.read(channel.REG_DEVICE_2, data, resp);

        `assert_equal(resp, 2'b00, "read should be successful");
        `assert_low(data[15], "not status pending");

        $display("END: test_write_command_cu_stop");
    end
    endtask

    task reset;
    begin
        @(posedge clk)
        begin
            channel_reset = 1;
        end

        @(posedge clk)
        begin
            channel_reset = 0;
        end

        @(posedge channel.s_axi_arready);
    end
    endtask
endmodule
