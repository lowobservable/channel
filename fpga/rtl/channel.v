`default_nettype none

module channel (
    input wire clk,
    input wire reset,

    //

    input wire [7:0] bus_in,
    output reg [7:0] bus_out,

    output reg operational_out = 1, // TODO
    input wire request_in,
    output reg hold_out,
    output reg select_out,
    input wire select_in,
    output reg address_out,
    input wire operational_in,
    input wire address_in,
    output reg command_out,
    input wire status_in,
    input wire service_in,
    output reg service_out,
    output reg suppress_out,

    //

    input wire [7:0] address,
    input wire [7:0] command,
    input wire [7:0] count,
    input wire start_strobe,

    output wire active, // "subchannel active"

    output reg [7:0] status,
    output reg status_strobe,

    output reg [7:0] res_count
);

    localparam STATE_IDLE = 0;
    localparam STATE_SELECTION_ADDRESS_OUT = 1;
    localparam STATE_SELECTION_SELECT_OUT = 2;
    localparam STATE_SELECTION_ADDRESS_IN = 3;
    localparam STATE_SELECTION_COMMAND_OUT = 4;
    localparam STATE_SELECTION_STATUS_IN = 5;
    localparam STATE_SELECTION_SERVICE_OUT = 6;
    localparam STATE_SELECTED = 7;

    localparam STATE_DATA = 8;
    localparam STATE_STOP = 9;

    localparam STATE_ENDING = 10;

    reg [7:0] state = STATE_IDLE;
    reg [7:0] next_state;
    reg [7:0] state_timer;

    reg [7:0] next_bus_out;
    reg next_address_out;
    reg next_hold_out;
    reg next_select_out;
    reg next_command_out;
    reg next_service_out;

    reg [7:0] next_status;
    reg next_status_strobe;
    reg [7:0] next_res_count;

    always @(*)
    begin
        next_state = state;

        next_bus_out = 8'b0;
        next_hold_out = 0;
        next_select_out = 0;
        next_address_out = 0;
        next_command_out = 0;
        next_service_out = 0;

        next_status = status; // TODO: hack to allow us to use status internaly
        next_status_strobe = 0;
        next_res_count = res_count;

        case (state)
            STATE_IDLE:
            begin
                if (start_strobe)
                begin
                    next_res_count = count; // capture the count here...

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

                if (operational_in)
                begin
                    next_state = STATE_SELECTION_ADDRESS_IN;
                end
                else if (status_in)
                begin
                    // TODO: this is "short-busy"
                end
                else if (select_in)
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
                if (address_in && bus_in == address)
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

                if (!address_in)
                begin
                    next_state = STATE_SELECTION_STATUS_IN;
                end

                // TODO: timeout?
            end

            STATE_SELECTION_STATUS_IN:
            begin
                if (status_in)
                begin
                    next_status = bus_in;
                    next_status_strobe = 1;

                    // NOTE: for now we always "accept" status - we'll check in
                    // the next state what the status represents...
                    next_state = STATE_SELECTION_SERVICE_OUT;
                end
            end

            STATE_SELECTION_SERVICE_OUT:
            begin
                next_service_out = 1;

                if (!status_in)
                begin
                    // NOTE: the status from the CU has been "accepted", but is
                    // the status something that means we can continue?

                    if (command == 8'h00)
                    begin
                        next_state = STATE_IDLE;
                    end
                    else if (status == 8'h00)
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
                if (service_in)
                begin
                    if (res_count == 0)
                    begin
                        next_state = STATE_STOP;
                    end
                    else if (command[0] /* WRITE or CONTROL */) // TODO: not NOP...
                    begin
                        next_state = STATE_DATA;
                    end
                    else
                    begin
                        $display("received byte %h from device", bus_in);
                        next_state = STATE_DATA;
                    end
                end
                else if (status_in)
                begin
                    next_status = bus_in;
                    next_status_strobe = 1;

                    next_state = STATE_ENDING;
                end
            end

            STATE_DATA:
            begin
                if (command[0] /* WRITE or CONTROL */)
                begin
                    next_bus_out = res_count;
                end

                next_service_out = 1;

                if (!service_in)
                begin
                    next_res_count = res_count - 1;
                    next_state = STATE_SELECTED;
                end
            end

            STATE_STOP:
            begin
                next_command_out = 1;

                if (!service_in)
                begin
                    // TODO: We are waiting for ending status!!!
                    next_state = STATE_SELECTED;
                end
            end

            STATE_ENDING:
            begin
                next_service_out = 1;

                if (!status_in)
                begin
                    if (status[5]) // DE
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

        bus_out <= next_bus_out;
        address_out <= next_address_out;
        hold_out <= next_hold_out;
        select_out <= next_select_out;
        command_out <= next_command_out;
        service_out <= next_service_out;

        status <= next_status;
        status_strobe <= next_status_strobe;
        res_count <= next_res_count;

        if (reset)
        begin
            state <= STATE_IDLE;

            status <= 0;
            status_strobe <= 0;
            res_count <= 0;
        end
    end

    assign active = (state != STATE_IDLE);
endmodule
