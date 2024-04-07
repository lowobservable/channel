`default_nettype none

module mock_cu (
    input wire clk,
    input wire reset,

    // Parallel Channel "B"...
    // verilator lint_off UNUSEDSIGNAL
    output reg [7:0] b_bus_in,
    input wire [7:0] b_bus_out,

    input wire b_operational_out,
    output reg b_request_in = 1'b0,
    input wire b_hold_out,
    input wire b_select_out,
    output reg b_select_in,
    input wire b_address_out,
    output reg b_operational_in,
    output reg b_address_in,
    input wire b_command_out,
    output reg b_status_in,
    output reg b_service_in,
    input wire b_service_out,
    input wire b_suppress_out,
    // verilator lint_on UNUSEDSIGNAL

    // Parallel Channel "A"...
    // verilator lint_off UNUSEDSIGNAL
    output reg a_select_out,
    input wire a_select_in,
    // verilator lint_on UNUSEDSIGNAL

    // ...
    input wire mock_busy,
    input wire [15:0] mock_limit,

    output reg [7:0] command,
    output reg [15:0] count
);
    parameter ADDRESS = 8'hff;
    parameter ENABLE_SHORT_BUSY = 0;

    reg [7:0] state = 0;

    reg [7:0] status = 8'b0011_0000; // CE + DE

    always @(posedge clk)
    begin
        b_select_in <= a_select_in;

        if (b_operational_out)
        begin
            case (state)
                0:
                begin
                    if (b_address_out && b_select_out && b_bus_out == ADDRESS)
                    begin
                        if (mock_busy && ENABLE_SHORT_BUSY)
                        begin
                            // TODO...
                        end
                        else
                        begin
                            state <= 2;
                        end
                    end
                    else
                    begin
                        a_select_out <= b_select_out;
                    end
                end

                2:
                begin
                    b_operational_in <= 1;

                    if (!b_address_out)
                    begin
                        state <= 3;
                    end
                end

                3:
                begin
                    b_operational_in <= 1;

                    b_bus_in <= ADDRESS;
                    b_address_in <= 1;

                    if (b_command_out)
                    begin
                        command <= b_bus_out;

                        b_address_in <= 0;
                        state <= 4;
                    end
                end

                4:
                begin
                    b_operational_in <= 1;

                    if (!b_command_out)
                    begin
                        state <= 5;
                    end
                end

                5:
                begin
                    b_operational_in <= 1;

                    if (mock_busy)
                    begin
                        status <= 8'b0000_1000; // BUSY

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
                        status <= 8'b0011_0000; // CE + DE

                        state <= 6;
                    end
                    else
                    begin
                        // SET COMMAND REJECT IN SENSE

                        status <= 8'b0111_0000; // CE + DE + UC

                        state <= 6;
                    end
                end

                6: // Initial status
                begin
                    b_operational_in <= 1;

                    b_bus_in <= status;
                    b_status_in <= 1;

                    if (b_service_out)
                    begin
                        b_status_in <= 0;
                        state <= 7;
                    end
                end

                7:
                begin
                    b_operational_in <= 1;

                    if (!b_service_out)
                    begin
                        if (status[3] || (status[4] && status[5]))
                        begin
                            state <= 0;
                        end
                        else if (command == 8'h01 /* WRITE */)
                        begin
                            count <= 0;

                            state <= 11;
                        end
                        else if (command == 8'h02 /* READ */)
                        begin
                            count <= 0;

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
                    //if (!b_suppress_out)
                    //begin
                        b_bus_in <= count[7:0] + 1;
                        b_service_in <= 1;

                        if (b_command_out)
                        begin
                            $display("cu: stop");

                            b_service_in <= 0;
                            state <= 13;
                        end
                        else if (b_service_out)
                        begin
                            // Data has been accepted...
                            $display("cu: sent byte %h to channel", b_bus_in);

                            count <= count + 1;

                            b_service_in <= 0;
                            state <= 9;
                        end
                    //end
                end

                9:
                begin
                    if (!b_service_out)
                    begin
                        if (count == mock_limit)
                        begin
                            status <= 8'b0011_0000; // CE + DE
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
                    //if (!b_suppress_out)
                    //begin
                        b_service_in <= 1;

                        if (b_command_out)
                        begin
                            $display("cu: stop");

                            b_service_in <= 0;
                            state <= 13;
                        end
                        else if (b_service_out)
                        begin
                            $display("cu: received byte %h from channel", b_bus_out);

                            count <= count + 1;

                            b_service_in <= 0;
                            state <= 12;
                        end
                    //end
                end

                12:
                begin
                    if (!b_service_out)
                    begin
                        if (count == mock_limit)
                        begin
                            status <= 8'b0011_0000; // CE + DE
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
                    if (!b_command_out)
                    begin
                        status <= 8'b0011_0000; // CE + DE
                        state <= 10;
                    end
                end

                10:
                begin
                    b_operational_in <= 1;

                    b_bus_in <= status;
                    b_status_in <= 1;

                    if (b_service_out)
                    begin
                        b_status_in <= 0;
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
