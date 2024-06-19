`default_nettype none

module frontend_a (
    input wire clk,
    input wire reset,
    input wire enable,

    // Parallel Channel "B"...
    output reg [7:0] b_bus_in,
    output reg b_bus_in_parity,
    input wire [7:0] b_bus_out,
    input wire b_bus_out_parity,
    output reg b_mark_0_in,
    input wire b_mark_0_out,

    input wire b_operational_out,
    output reg b_request_in,
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
    output reg b_data_in,
    input wire b_data_out,
    output reg b_disconnect_in,
    output reg b_metering_in,
    input wire b_metering_out,
    input wire b_clock_out,

    // Parallel Channel "A"...
    input wire [7:0] a_bus_in_n,
    input wire a_bus_in_parity_n,
    output reg [7:0] a_bus_out,
    output reg a_bus_out_parity,
    input wire a_mark_0_in_n,
    output reg a_mark_0_out,

    output reg a_operational_out,
    input wire a_request_in_n,
    output reg a_hold_out,
    output reg a_select_out,
    input wire a_select_in_n,
    output reg a_address_out,
    input wire a_operational_in_n,
    input wire a_address_in_n,
    output reg a_command_out,
    input wire a_status_in_n,
    input wire a_service_in_n,
    output reg a_service_out,
    output reg a_suppress_out,
    input wire a_data_in_n,
    output reg a_data_out,
    input wire a_disconnect_in_n,
    input wire a_metering_in_n,
    output reg a_metering_out,
    output reg a_clock_out,

    output reg driver_enable
);
    reg [15:0] bus_in_n_d;
    reg [1:0] bus_in_parity_n_d;
    reg [1:0] mark_0_in_n_d;
    reg [1:0] request_in_n_d;
    reg [1:0] select_in_n_d;
    reg [1:0] operational_in_n_d;
    reg [1:0] address_in_n_d;
    reg [1:0] status_in_n_d;
    reg [1:0] service_in_n_d;
    reg [1:0] data_in_n_d;
    reg [1:0] disconnect_in_n_d;
    reg [1:0] metering_in_n_d;

    always @(posedge clk)
    begin
        // 2FF synchronizer...
        bus_in_n_d <= { bus_in_n_d[7:0], a_bus_in_n };
        bus_in_parity_n_d <= { bus_in_parity_n_d[0], a_bus_in_parity_n };
        mark_0_in_n_d <= { mark_0_in_n_d[0], a_mark_0_in_n };
        request_in_n_d <= { request_in_n_d[0], a_request_in_n };
        select_in_n_d <= { select_in_n_d[0], a_select_in_n };
        operational_in_n_d <= { operational_in_n_d[0], a_operational_in_n };
        address_in_n_d <= { address_in_n_d[0], a_address_in_n };
        status_in_n_d <= { status_in_n_d[0], a_status_in_n };
        service_in_n_d <= { service_in_n_d[0], a_service_in_n };
        data_in_n_d <= { data_in_n_d[0], a_data_in_n };
        disconnect_in_n_d <= { disconnect_in_n_d[0], a_disconnect_in_n };
        metering_in_n_d <= { metering_in_n_d[0], a_metering_in_n };

        if (reset)
        begin
            bus_in_n_d <= 16'b0;
            bus_in_parity_n_d <= 2'b0;
            mark_0_in_n_d <= 2'b0;
            request_in_n_d <= 2'b0;
            select_in_n_d <= 2'b0;
            operational_in_n_d <= 2'b0;
            address_in_n_d <= 2'b0;
            status_in_n_d <= 2'b0;
            service_in_n_d <= 2'b0;
            data_in_n_d <= 2'b0;
            disconnect_in_n_d <= 2'b0;
            metering_in_n_d <= 2'b0;
        end
    end

    always @(posedge clk)
    begin
        if (enable)
        begin
            b_bus_in <= ~bus_in_n_d[15:8];
            b_bus_in_parity <= ~bus_in_parity_n_d[1];
            b_mark_0_in <= ~mark_0_in_n_d[1];
            b_request_in <= ~request_in_n_d[1];
            b_select_in <= ~select_in_n_d[1];
            b_operational_in <= ~operational_in_n_d[1];
            b_address_in <= ~address_in_n_d[1];
            b_status_in <= ~status_in_n_d[1];
            b_service_in <= ~service_in_n_d[1];
            b_data_in <= ~data_in_n_d[1];
            b_disconnect_in <= ~disconnect_in_n_d[1];
            b_metering_in <= ~metering_in_n_d[1];
        end
        else
        begin
            b_bus_in <= 8'b0;
            b_bus_in_parity <= 1'b0;
            b_mark_0_in <= 1'b0;
            b_request_in <= 1'b0;
            b_select_in <= a_select_out;
            b_operational_in <= 1'b0;
            b_address_in <= 1'b0;
            b_status_in <= 1'b0;
            b_service_in <= 1'b0;
            b_data_in <= 1'b0;
            b_disconnect_in <= 1'b0;
            b_metering_in <= 1'b0;
        end

        if (reset)
        begin
            b_bus_in <= 8'b0;
            b_bus_in_parity <= 1'b0;
            b_mark_0_in <= 1'b0;
            b_request_in <= 1'b0;
            b_select_in <= 1'b0;
            b_operational_in <= 1'b0;
            b_address_in <= 1'b0;
            b_status_in <= 1'b0;
            b_service_in <= 1'b0;
            b_data_in <= 1'b0;
            b_disconnect_in <= 1'b0;
            b_metering_in <= 1'b0;
        end
    end

    always @(posedge clk)
    begin
        if (enable)
        begin
            a_bus_out <= b_bus_out;
            a_bus_out_parity <= b_bus_out_parity;
            a_mark_0_out <= b_mark_0_out;
            a_operational_out <= b_operational_out;
            a_hold_out <= b_hold_out;
            a_select_out <= b_select_out;
            a_address_out <= b_address_out;
            a_command_out <= b_command_out;
            a_service_out <= b_service_out;
            a_suppress_out <= b_suppress_out;
            a_data_out <= b_data_out;
            a_metering_out <= b_metering_out;
            a_clock_out <= b_clock_out;

            // TODO: is this correct?
            driver_enable <= a_operational_out; // For wrap test set to 1'b1
        end
        else
        begin
            a_bus_out <= 8'b0;
            a_bus_out_parity <= 1'b0;
            a_mark_0_out <= 1'b0;
            a_operational_out <= 1'b0;
            a_hold_out <= 1'b0;
            a_select_out <= 1'b0;
            a_address_out <= 1'b0;
            a_command_out <= 1'b0;
            a_service_out <= 1'b0;
            a_suppress_out <= 1'b0;
            a_data_out <= 1'b0;
            a_metering_out <= 1'b0;
            a_clock_out <= 1'b0;

            driver_enable <= 1'b0;
        end

        if (reset)
        begin
            a_bus_out <= 8'b0;
            a_bus_out_parity <= 1'b0;
            a_mark_0_out <= 1'b0;
            a_operational_out <= 1'b0;
            a_hold_out <= 1'b0;
            a_select_out <= 1'b0;
            a_address_out <= 1'b0;
            a_command_out <= 1'b0;
            a_service_out <= 1'b0;
            a_suppress_out <= 1'b0;
            a_data_out <= 1'b0;
            a_metering_out <= 1'b0;
            a_clock_out <= 1'b0;

            driver_enable <= 1'b0;
        end
    end
endmodule
