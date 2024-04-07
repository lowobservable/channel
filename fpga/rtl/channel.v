`default_nettype none

module channel (
    input wire clk,
    input wire reset,

    // Parallel Channel "A"...
    input wire [7:0] a_bus_in,
    output reg [7:0] a_bus_out,

    output reg a_operational_out = 1'b1,
    // verilator lint_off UNUSEDSIGNAL
    input wire a_request_in,
    // veriloator lint on UNUSEDSIGNAL
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
    input wire [7:0] address,
    input wire [7:0] command,

    output wire active, // "subchannel active"

    input wire start,
    input wire stop,

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
    localparam STATE_IDLE = 0;
    localparam STATE_SELECTION_ADDRESS_OUT = 1;
    localparam STATE_SELECTION_SELECT_OUT = 2;
    localparam STATE_SELECTION_ADDRESS_IN = 3;
    localparam STATE_SELECTION_COMMAND_OUT = 4;
    localparam STATE_SELECTION_STATUS_IN = 5;
    localparam STATE_SELECTION_SERVICE_OUT = 6;
    localparam STATE_SELECTED = 7;

    localparam STATE_DATA_SEND_1 = 8;
    localparam STATE_DATA_SEND_2 = 9;
    localparam STATE_DATA_RECV_1 = 10;
    localparam STATE_DATA_RECV_2 = 11;
    localparam STATE_STOP = 12;

    localparam STATE_ENDING = 13;

    reg [7:0] state = STATE_IDLE;
    reg [7:0] next_state;
    reg [7:0] state_timer;

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

    always @(*)
    begin
        next_state = state;

        next_bus_out = 8'b0;
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

        case (state)
            STATE_IDLE:
            begin
                if (start)
                begin
                    // TODO: 'Address out' can rise for device selection only
                    // when 'select out' (or 'hold out'), 'select in', 'status
                    // in', and 'operational in' are down at the channel.
                    next_state = STATE_SELECTION_ADDRESS_OUT;
                end
            end

            STATE_SELECTION_ADDRESS_OUT:
            begin
                // TODO: 'Address out' rises at least 250 nanoseconds after
                // the I/O-device address is placed on 'bus out' or at least
                // 250 nanoseconds after the rise of 'operational out',
                // whichever occurs later.
                next_bus_out = address;
                next_address_out = 1;

                // SPEC: When an operation is being initiated by the channel,
                // 'select out' is raised not less than 400 nanoseconds after
                // the rise of 'address out', which indicates the address of
                // the device being selected.
                if (state_timer == 4)
                begin
                    next_state = STATE_SELECTION_SELECT_OUT;
                end
            end

            STATE_SELECTION_SELECT_OUT:
            begin
                next_bus_out = address;
                next_address_out = 1;
                next_hold_out = 1; // TODO: Can this be done at the same time?
                next_select_out = 1;

                if (a_operational_in)
                begin
                    next_state = STATE_SELECTION_ADDRESS_IN;
                end
                else if (a_status_in)
                begin
                    // TODO: this is "short-busy"
                end
                else if (a_select_in)
                begin
                    next_state = STATE_IDLE;
                end

                // TODO: timeout?
            end

            STATE_SELECTION_ADDRESS_IN:
            begin
                next_hold_out = 1; // TODO: Can this be done at the same time?
                next_select_out = 1;

                // TODO: what happens if bus_in != addres???
                if (a_address_in && a_bus_in == address)
                begin
                    next_state = STATE_SELECTION_COMMAND_OUT;
                end

                // TODO: timeout?
            end

            STATE_SELECTION_COMMAND_OUT:
            begin
                // SPEC; 'Hold out' with 'select out' may drop any time after
                // 'address in' rises.

                // TODO: they go up with channel controlled burst, right?

                next_bus_out = command;
                next_command_out = 1;

                if (!a_address_in)
                begin
                    next_state = STATE_SELECTION_STATUS_IN;
                end

                // TODO: timeout?
            end

            STATE_SELECTION_STATUS_IN:
            begin
                if (a_status_in)
                begin
                    // NOTE: for now we always "accept" status - we'll check in
                    // the next state what the status represents...
                    next_status_tdata = a_bus_in;
                    next_status_tvalid = 1;

                    next_state = STATE_SELECTION_SERVICE_OUT;
                end
            end

            STATE_SELECTION_SERVICE_OUT:
            begin
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

            STATE_SELECTED:
            begin
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
                    next_status_tdata = a_bus_in;
                    next_status_tvalid = 1;

                    next_state = STATE_ENDING;
                end
            end

            STATE_DATA_SEND_1:
            begin
                if (stop)
                begin
                    next_data_send_tready = 1'b0;

                    next_state = STATE_STOP;
                end
                else if (data_send_tvalid && data_send_tready)
                begin
                    next_data_send_tready = 1'b0;

                    next_bus_out = data_send_tdata;
                    next_service_out = 1;

                    $display("chan: sent byte %h to device", data_send_tdata);

                    next_state = STATE_DATA_SEND_2;
                end
            end

            STATE_DATA_SEND_2:
            begin
                next_service_out = 1;

                if (!a_service_in)
                begin
                    next_state = STATE_SELECTED;
                end
            end

            STATE_DATA_RECV_1:
            begin
                if (stop)
                begin
                    // TODO: this might be illegal per AXI-Stream spec...
                    next_data_recv_tvalid = 1'b0;

                    next_state = STATE_STOP;
                end
                else if (data_recv_tvalid && data_recv_tready)
                begin
                    next_data_recv_tvalid = 1'b0;

                    $display("chan: received byte %h from device", data_recv_tdata);

                    next_state = STATE_DATA_RECV_2;
                end
            end

            STATE_DATA_RECV_2:
            begin
                next_service_out = 1;

                if (!a_service_in)
                begin
                    next_state = STATE_SELECTED;
                end
            end

            STATE_STOP:
            begin
                next_command_out = 1;

                if (!a_service_in)
                begin
                    // TODO: We are waiting for ending status!!!
                    next_state = STATE_SELECTED;
                end
            end

            STATE_ENDING:
            begin
                next_service_out = 1;

                if (!a_status_in)
                begin
                    if (status_tdata[5]) // DE
                    begin
                        next_state = STATE_IDLE;
                    end
                    else
                    begin
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
        a_address_out <= next_address_out;
        a_hold_out <= next_hold_out;
        a_select_out <= next_select_out;
        a_command_out <= next_command_out;
        a_service_out <= next_service_out;

        status_tdata <= next_status_tdata;
        status_tvalid <= next_status_tvalid;
        data_send_tready <= next_data_send_tready;
        data_recv_tdata <= next_data_recv_tdata;
        data_recv_tvalid <= next_data_recv_tvalid;

        if (reset)
        begin
            state <= STATE_IDLE;

            state_timer <= 0;

            status_tvalid <= 0;
            data_send_tready <= 0;
            data_recv_tvalid <= 0;
        end
    end

    assign active = (state != STATE_IDLE);
endmodule
