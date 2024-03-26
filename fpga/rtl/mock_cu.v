`default_nettype none

module mock_cu (
    input wire clk,
    input wire reset,

    //

    output reg [7:0] bus_in,
    input wire [7:0] bus_out,

    input wire operational_out,
    output reg request_in,
    input wire hold_out,
    input wire a_select_out,
    output reg a_select_in,
    input wire address_out,
    output reg operational_in,
    output reg address_in,
    input wire command_out,
    output reg status_in,
    output reg service_in,
    input wire service_out,
    input wire suppress_out,

    output reg b_select_out,
    input wire b_select_in,

    //

    input wire mock_busy,
    input wire [7:0] mock_read_count,
    input wire [7:0] mock_write_count
);
    parameter ADDRESS = 8'hff;
    parameter ENABLE_SHORT_BUSY = 1;

    reg [7:0] state = 0;
    reg [7:0] after_status_state = 0;

    reg [7:0] command;
    reg [7:0] status = 8'b0011_0000; // CE + DE

    reg [7:0] count;

    always @(posedge clk)
    begin
        a_select_in <= b_select_in;

        if (operational_out)
        begin
            case (state)
                0:
                begin
                    if (address_out && a_select_out && bus_out == ADDRESS)
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
                        b_select_out <= a_select_out;
                    end
                end

                2:
                begin
                    operational_in <= 1;

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
                    operational_in <= 1;

                    bus_in <= status;
                    status_in <= 1;

                    if (service_out)
                    begin
                        status_in <= 0;
                        state <= 7;
                    end
                end

                7:
                begin
                    operational_in <= 1;

                    if (!service_out)
                    begin
                        if (status[3] || (status[4] && status[5]))
                        begin
                            state <= 0;
                        end
                        else if (command == 8'h01 /* WRITE */)
                        begin
                            count <= mock_write_count;

                            state <= 11;
                        end
                        else if (command == 8'h02 /* READ */)
                        begin
                            count <= mock_read_count;

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

                        bus_in <= count;
                        service_in <= 1;

                        if (command_out)
                        begin
                            $display("STOP!");

                            service_in <= 0;
                            state <= 13;
                        end
                        else if (service_out)
                        begin
                            // Data has been accepted...
                            count <= count - 1;

                            service_in <= 0;
                            state <= 9;
                        end
                    //end
                end

                9:
                begin
                    if (!service_out)
                    begin
                        if (count == 0)
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
                    //if (!suppress_out)
                    //begin
                        service_in <= 1;

                        if (command_out)
                        begin
                            $display("STOP!");

                            service_in <= 0;
                            state <= 13;
                        end
                        if (service_out)
                        begin
                            // TODO: data is available on bus_out!
                            $display("received byte %h from channel", bus_out);

                            count <= count - 1;

                            service_in <= 0;
                            state <= 12;
                        end
                    //end
                end

                12:
                begin
                    if (!service_out)
                    begin
                        if (count == 0)
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
                    if (!command_out)
                    begin
                        status <= 8'b0011_0000; // CE + DE
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
    end
endmodule
