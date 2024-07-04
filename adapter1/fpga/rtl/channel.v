`default_nettype none

module channel (
    input wire clk,
    input wire enable,
    input wire reset,

    // Parallel Channel "A"...
    input wire [7:0] a_bus_in,
    input wire a_bus_in_parity,
    output reg [7:0] a_bus_out,
    output reg a_bus_out_parity,

    output reg a_operational_out,
    input wire a_request_in,
    output reg a_hold_out,
    output reg a_select_out,
    input wire a_select_in,
    output reg a_address_out,
    input wire a_operational_in,
    input wire a_address_in,
    output reg a_command_out,
    input wire a_status_in,
    input wire a_service_in,
    output reg a_service_out,
    output reg a_suppress_out = 1'b0,

    // ...
    input wire [7:0] addr,
    input wire [7:0] command,

    output wire active, // "subchannel active"
    output wire request,

    input wire start,
    input wire stop,

    output reg [1:0] condition_code,

    // AXI-Stream for status...
    output reg [7:0] status_tdata,
    output reg status_tvalid,

    // AXI-Stream for data being sent...
    input wire [7:0] data_send_tdata,
    input wire data_send_tvalid,
    output reg data_send_tready,

    // AXI-Stream for data being received...
    output reg [7:0] data_recv_tdata,
    output reg data_recv_tvalid,
    input wire data_recv_tready
);
    parameter CLOCKS_PER_100_NS = 5; // 50 MHz clock period is 20 ns

    localparam STATE_IDLE = 0;
    localparam STATE_SELECTION_ADDRESS_OUT_1 = 1;
    localparam STATE_SELECTION_ADDRESS_OUT_2 = 2;
    localparam STATE_SELECTION_SELECT_OUT = 3;
    localparam STATE_SELECTION_ADDRESS_IN = 4;
    localparam STATE_SELECTION_COMMAND_OUT_1 = 5;
    localparam STATE_SELECTION_COMMAND_OUT_2 = 6;
    localparam STATE_SELECTION_STATUS_IN = 7;
    localparam STATE_SELECTION_SERVICE_OUT = 8;
    localparam STATE_SELECTION_SHORT_BUSY = 9;

    localparam STATE_SELECTED = 10;

    localparam STATE_DATA_SEND_1 = 11;
    localparam STATE_DATA_SEND_2 = 12;
    localparam STATE_DATA_SEND_3 = 13;
    localparam STATE_DATA_RECV_1 = 14;
    localparam STATE_DATA_RECV_2 = 15;
    localparam STATE_STOP = 16;

    localparam STATE_ENDING = 17;

    reg [7:0] state = STATE_IDLE;
    reg [7:0] next_state;
    reg [7:0] state_timer;

    // verilator lint_off UNUSEDSIGNAL
    wire a_bus_in_parity_valid;
    // verilator lint_on UNUSEDSIGNAL

    assign a_bus_in_parity_valid = (~^a_bus_in == a_bus_in_parity); // Odd parity

    reg [7:0] next_bus_out;
    reg next_address_out;
    reg next_hold_out;
    reg next_select_out;
    reg next_command_out;
    reg next_service_out;

    reg [7:0] next_status_tdata;
    reg next_status_tvalid;
    reg next_data_send_tready;
    reg [7:0] next_data_recv_tdata;
    reg next_data_recv_tvalid;

    reg [1:0] next_condition_code;

    always @(*)
    begin
        next_state = state;

        next_bus_out = a_bus_out;
        next_hold_out = 0;
        next_select_out = 0;
        next_address_out = 0;
        next_command_out = 0;
        next_service_out = 0;

        next_status_tdata = status_tdata;
        next_status_tvalid = 0; // Will always be a 1-clock pulse
        next_data_send_tready = data_send_tready;
        next_data_recv_tdata = data_recv_tdata;
        next_data_recv_tvalid = data_recv_tvalid;

        next_condition_code = condition_code;

        case (state)
            STATE_IDLE:
            begin
                // Leave bus out low when not idle to reduce driver current.
                //
                // TODO: Compute parity when needed then we could leave that
                // low here too.
                next_bus_out = 8'b0;

                if (start)
                begin
                    next_condition_code = 0;

                    // TODO: 'Address out' can rise for device selection only
                    // when 'select out' (or 'hold out'), 'select in', 'status
                    // in', and 'operational in' are down at the channel.
                    next_state = STATE_SELECTION_ADDRESS_OUT_1;
                end
            end

            STATE_SELECTION_ADDRESS_OUT_1:
            begin
                next_bus_out = addr;

                // SPEC: 'Address out' rises at least 250 nanoseconds after
                // the I/O-device address is placed on 'bus out' or at least
                // 250 nanoseconds after the rise of 'operational out',
                // whichever occurs later.
                if (state_timer == 3 * CLOCKS_PER_100_NS)
                begin
                    next_state = STATE_SELECTION_ADDRESS_OUT_2;
                end
            end

            STATE_SELECTION_ADDRESS_OUT_2:
            begin
                next_address_out = 1;

                // SPEC: When an operation is being initiated by the channel,
                // 'select out' is raised not less than 400 nanoseconds after
                // the rise of 'address out', which indicates the address of
                // the device being selected.
                if (state_timer == 4 * CLOCKS_PER_100_NS)
                begin
                    next_state = STATE_SELECTION_SELECT_OUT;
                end
            end

            STATE_SELECTION_SELECT_OUT:
            begin
                next_address_out = 1;
                next_hold_out = 1; // TODO: Can this be done at the same time?
                next_select_out = 1;

                if (a_operational_in)
                begin
                    next_state = STATE_SELECTION_ADDRESS_IN;
                end
                else if (a_status_in)
                begin
                    next_status_tdata = a_bus_in;
                    next_status_tvalid = 1;

                    $display("chan: received status byte 0x%h (short busy)", next_status_tdata);

                    next_state = STATE_SELECTION_SHORT_BUSY;
                end
                else if (a_select_in)
                begin
                    next_condition_code = 3; // Not operational

                    next_state = STATE_IDLE;
                end

                // TODO: timeout
            end

            STATE_SELECTION_ADDRESS_IN:
            begin
                next_hold_out = 1;
                next_select_out = 1;

                // TODO: what happens if bus_in != addres???
                if (a_address_in && a_bus_in == addr)
                begin
                    next_state = STATE_SELECTION_COMMAND_OUT_1;
                end

                // TODO: timeout?
            end

            STATE_SELECTION_COMMAND_OUT_1:
            begin
                // SPEC: 'Hold out' with 'select out' may drop any time after
                // 'address in' rises.
                //
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                next_bus_out = command;

                // SPEC: The channel delays raising of the signal on the outbound
                // tag lines so that the information on 'bus out' precedes the
                // signal on the outbound tag line by at least 100 nanoseconds.
                if (state_timer == CLOCKS_PER_100_NS)
                begin
                    next_state = STATE_SELECTION_COMMAND_OUT_2;
                end
            end

            STATE_SELECTION_COMMAND_OUT_2:
            begin
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                next_command_out = 1;

                if (!a_address_in)
                begin
                    next_state = STATE_SELECTION_STATUS_IN;
                end

                // TODO: timeout?
            end

            STATE_SELECTION_STATUS_IN:
            begin
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                if (a_status_in)
                begin
                    // NOTE: for now we always "accept" status - we'll check in
                    // the next state what the status represents...
                    next_status_tdata = a_bus_in;
                    next_status_tvalid = 1;

                    $display("chan: received status byte 0x%h", next_status_tdata);

                    next_state = STATE_SELECTION_SERVICE_OUT;
                end
            end

            STATE_SELECTION_SERVICE_OUT:
            begin
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                next_service_out = 1;

                if (!a_status_in)
                begin
                    // NOTE: the status from the CU has been "accepted", but is
                    // the status something that means we can continue?

                    if (command == 8'h00)
                    begin
                        next_state = STATE_IDLE;
                    end
                    else if (status_tdata == 8'h00)
                    begin
                        next_state = STATE_SELECTED;
                    end
                    else
                    begin
                        next_state = STATE_IDLE;
                    end
                end
            end

            STATE_SELECTION_SHORT_BUSY:
            begin
                next_address_out = 1;

                if (!a_status_in)
                begin
                    next_state = STATE_IDLE;
                end
            end

            STATE_SELECTED:
            begin
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                if (a_service_in)
                begin
                    if (command[0] /* WRITE or CONTROL */) // TODO: not NOP...
                    begin
                        next_data_send_tready = 1'b1;

                        next_state = STATE_DATA_SEND_1;
                    end
                    else
                    begin
                        next_data_recv_tdata = a_bus_in;
                        next_data_recv_tvalid = 1'b1;

                        next_state = STATE_DATA_RECV_1;
                    end
                end
                else if (a_status_in)
                begin
                    // TODO: This is a hack, according to the PoP:
                    //
                    // | The channel subsystem does not modify the status bits received
                    // | from the I/O device. These bits appear in the SCSW as received
                    // | over the channel path.
                    //
                    // Which, I think, is why most assembly programs accumulate the device
                    // status using OC and test the accumulated status for channel and and
                    // device end.
                    //
                    // For now, we'll accumulate the status here until we have request in
                    // and status interrupts implemented.
                    next_status_tdata = status_tdata | a_bus_in;
                    next_status_tvalid = 1;

                    $display("chan: received status byte 0x%h", next_status_tdata);

                    next_state = STATE_ENDING;
                end
            end

            STATE_DATA_SEND_1:
            begin
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                if (stop)
                begin
                    next_data_send_tready = 1'b0;

                    next_state = STATE_STOP;
                end
                else if (data_send_tvalid && data_send_tready)
                begin
                    next_data_send_tready = 1'b0;

                    next_bus_out = data_send_tdata;

                    $display("chan: sending byte 0x%h", data_send_tdata);

                    next_state = STATE_DATA_SEND_2;
                end
            end

            STATE_DATA_SEND_2:
            begin
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                // SPEC: The channel delays raising of the signal on the outbound
                // tag lines so that the information on 'bus out' precedes the
                // signal on the outbound tag line by at least 100 nanoseconds.
                if (state_timer == CLOCKS_PER_100_NS)
                begin
                    next_state = STATE_DATA_SEND_3;
                end
            end

            STATE_DATA_SEND_3:
            begin
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                next_service_out = 1;

                if (!a_service_in)
                begin
                    next_state = STATE_SELECTED;
                end
            end

            STATE_DATA_RECV_1:
            begin
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                if (stop)
                begin
                    // TODO: this might be illegal per AXI-Stream spec...
                    next_data_recv_tvalid = 1'b0;

                    next_state = STATE_STOP;
                end
                else if (data_recv_tvalid && data_recv_tready)
                begin
                    next_data_recv_tvalid = 1'b0;

                    $display("chan: received byte 0x%h", data_recv_tdata);

                    next_state = STATE_DATA_RECV_2;
                end
            end

            STATE_DATA_RECV_2:
            begin
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                next_service_out = 1;

                if (!a_service_in)
                begin
                    next_state = STATE_SELECTED;
                end
            end

            STATE_STOP:
            begin
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                next_command_out = 1;

                if (!a_service_in)
                begin
                    // We are still waiting on an ending sequence...
                    next_state = STATE_SELECTED;
                end
            end

            STATE_ENDING:
            begin
                // TODO: Only if channel controlled burst...
                next_hold_out = 1;
                next_select_out = 1;

                next_service_out = 1;

                if (!a_status_in)
                begin
                    if (status_tdata[3] /* CE */ && status_tdata[2] /* DE */)
                    begin
                        next_state = STATE_IDLE;
                    end
                    else
                    begin
                        // We are still waiting on channel and device end...
                        next_state = STATE_SELECTED;
                    end
                end
            end
        endcase
    end

    always @(posedge clk)
    begin
        state <= next_state;

        state_timer <= state_timer + 1;

        if (state != next_state)
        begin
            state_timer <= 0;
        end

        a_bus_out <= next_bus_out;
        a_bus_out_parity <= ~^next_bus_out; // Odd parity
        a_address_out <= next_address_out;
        a_operational_out <= enable; // TODO
        a_hold_out <= next_hold_out;
        a_select_out <= next_select_out;
        a_command_out <= next_command_out;
        a_service_out <= next_service_out;

        status_tdata <= next_status_tdata;
        status_tvalid <= next_status_tvalid;
        data_send_tready <= next_data_send_tready;
        data_recv_tdata <= next_data_recv_tdata;
        data_recv_tvalid <= next_data_recv_tvalid;

        condition_code <= next_condition_code;

        if (reset)
        begin
            state <= STATE_IDLE;

            state_timer <= 0;

            status_tvalid <= 0;
            data_send_tready <= 0;
            data_recv_tvalid <= 0;

            condition_code <= 0;
        end
    end

    assign active = (state != STATE_IDLE);
    assign request = a_request_in;
endmodule
