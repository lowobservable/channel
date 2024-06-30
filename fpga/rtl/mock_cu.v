`default_nettype none

module mock_cu (
    input wire clk,
    input wire reset,

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

    // ...
    input wire mock_busy,
    input wire mock_short_busy,
    input wire [15:0] mock_limit,

    output reg [7:0] command,
    output reg [15:0] count
);
    parameter ADDRESS = 8'hff;

    reg [7:0] bus_in;
    wire bus_in_parity;
    wire [7:0] bus_out;
    wire bus_out_parity;
    wire operational_out;
    reg request_in;
    wire address_out;
    reg operational_in;
    reg address_in;
    wire command_out;
    reg status_in;
    reg service_in;
    wire service_out;
    wire selection_x;
    reg selection_y;

    assign bus_in_parity = ~^bus_in; // Odd parity

    // verilator lint_off UNUSEDSIGNAL
    wire bus_out_parity_valid;
    // verilator lint_on UNUSEDSIGNAL

    assign bus_out_parity_valid = (~^bus_out == bus_out_parity); // Odd parity

    tee tee (
        .clk(clk),

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

        .bus_in(bus_in),
        .bus_in_parity(bus_in_parity),
        .bus_out(bus_out),
        .bus_out_parity(bus_out_parity),
        .operational_out(operational_out),
        .request_in(request_in),
        .hold_out(), // TODO
        .address_out(address_out),
        .operational_in(operational_in),
        .address_in(address_in),
        .command_out(command_out),
        .status_in(status_in),
        .service_in(service_in),
        .service_out(service_out),
        .suppress_out(), // TODO

        .selection_x(selection_x),
        .selection_y(selection_y)
    );

    reg [7:0] state = 0;

    reg [7:0] status = 8'b0000_1100; // CE + DE

    always @(posedge clk)
    begin
        request_in <= 1'b0;

        if (operational_out)
        begin
            case (state)
                0:
                begin
                    operational_in <= 0;
                    address_in <= 0;
                    status_in <= 0;
                    service_in <= 0;

                    selection_y <= selection_x;

                    if (address_out && selection_x && bus_out == ADDRESS)
                    begin
                        selection_y <= 1'b0; // Intercept the selection

                        if (mock_short_busy)
                        begin
                            status <= 8'b0001_0000; // BUSY

                            state <= 99;
                        end
                        else
                        begin
                            state <= 2;
                        end
                    end
                end

                2:
                begin
                    operational_in <= 1;

                    count <= 0; // Reset the mock count

                    if (!address_out)
                    begin
                        state <= 3;
                    end
                end

                3:
                begin
                    operational_in <= 1;

                    bus_in <= ADDRESS;
                    address_in <= 1;

                    if (command_out)
                    begin
                        command <= bus_out;

                        address_in <= 0;
                        state <= 4;
                    end
                end

                4:
                begin
                    operational_in <= 1;

                    if (!command_out)
                    begin
                        state <= 5;
                    end
                end

                5:
                begin
                    operational_in <= 1;

                    if (mock_busy)
                    begin
                        status <= 8'b0001_0000; // BUSY

                        state <= 6;
                    end
                    else if (command == 8'h00 /* TEST I/O */)
                    begin
                        // TODO
                    end
                    else if (command == 8'h01 /* WRITE */)
                    begin
                        status <= 8'b0000_0000;

                        state <= 6;
                    end
                    else if (command == 8'h02 /* READ */)
                    begin
                        status <= 8'b0000_0000;

                        state <= 6;
                    end
                    else if (command == 8'h03 /* NOP */)
                    begin
                        status <= 8'b0000_1100; // CE + DE

                        state <= 6;
                    end
                    else
                    begin
                        // SET COMMAND REJECT IN SENSE

                        status <= 8'b0000_1110; // CE + DE + UC

                        state <= 6;
                    end
                end

                6: // Initial status
                begin
                    operational_in <= 1;

                    bus_in <= status;
                    status_in <= 1;

                    if (service_out)
                    begin
                        status_in <= 0;
                        state <= 7;
                    end
                end

                99: // Short busy
                begin
                    // SPEC: operational in is not raised for short busy

                    bus_in <= status;
                    status_in <= 1;

                    if (!selection_x)
                    begin
                        status_in <= 0;
                        state <= 0;
                    end
                end

                7:
                begin
                    operational_in <= 1;

                    if (!service_out)
                    begin
                        if (status[4] || (status[3] && status[2]))
                        begin
                            state <= 0;
                        end
                        else if (command == 8'h01 /* WRITE */)
                        begin
                            state <= 11;
                        end
                        else if (command == 8'h02 /* READ */)
                        begin
                            state <= 8;
                        end
                        else
                        begin
                            $display("PANIC");
                            $finish;
                        end
                    end
                end

                8: // Send a byte...
                begin
                    //if (!suppress_out)
                    //begin
                        bus_in <= count[7:0] + 1;
                        service_in <= 1;

                        // Kinda hacky way to show this once per byte...
                        if (service_in == 0)
                        begin
                            $display("cu: sending byte 0x%h to channel", count[7:0] + 8'b1);
                        end

                        if (command_out)
                        begin
                            $display("cu: stop");

                            service_in <= 0;
                            state <= 13;
                        end
                        else if (service_out)
                        begin
                            count <= count + 1;

                            service_in <= 0;
                            state <= 9;
                        end
                    //end
                end

                9:
                begin
                    if (!service_out)
                    begin
                        if (count == mock_limit)
                        begin
                            status <= 8'b0000_1100; // CE + DE
                            state <= 10;
                        end
                        else
                        begin
                            state <= 8;
                        end
                    end
                end

                11: // Receive a byte...
                begin
                    //if (!suppress_out)
                    //begin
                        service_in <= 1;

                        if (command_out)
                        begin
                            $display("cu: stop");

                            service_in <= 0;
                            state <= 13;
                        end
                        else if (service_out)
                        begin
                            $display("cu: received byte 0x%h from channel", bus_out);

                            count <= count + 1;

                            service_in <= 0;
                            state <= 12;
                        end
                    //end
                end

                12:
                begin
                    if (!service_out)
                    begin
                        if (count == mock_limit)
                        begin
                            status <= 8'b0000_1100; // CE + DE
                            state <= 10;
                        end
                        else
                        begin
                            state <= 11;
                        end
                    end
                end

                13: // Wait for STOP to be accepted...
                begin
                    if (!command_out)
                    begin
                        status <= 8'b0000_1100; // CE + DE
                        state <= 10;
                    end
                end

                10:
                begin
                    operational_in <= 1;

                    bus_in <= status;
                    status_in <= 1;

                    if (service_out)
                    begin
                        status_in <= 0;
                        state <= 0;
                    end
                end
            endcase
        end
        else
        begin
            state <= 0;
        end

        if (reset)
        begin
            state <= 0;
        end
    end
endmodule
