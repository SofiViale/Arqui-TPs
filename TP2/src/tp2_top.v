`timescale 1ns / 1ps
`default_nettype none

module tp2_top #(
    parameter integer CLK_FREQ = 100000000,
    parameter integer BAUD_RATE = 9600
)(
    input wire clk,
    input wire reset,
    input wire serial_rx,
    output wire serial_tx,
    output wire frame_error,
    output wire protocol_error
);
    // The byte protocol fixes the integration to 8 bits; UART cores are generic.
    wire reset_internal, tick_16x;
    wire [7:0] rx_data, tx_data, a, b, alu_result;
    wire [5:0] op;
    wire rx_valid_pulse, operation_valid_pulse, operation_ready;
    wire tx_start_pulse, tx_busy, tx_done_pulse;

    reset_sync reset_inst (.clk(clk), .reset(reset), .reset_out(reset_internal));
    baud_rate_generator #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) baud_inst (
        .clk(clk), .reset(reset_internal), .tick_16x(tick_16x)
    );
    uart_rx #(.DATA_BITS(8)) rx_inst (
        .clk(clk), .reset(reset_internal), .tick_16x(tick_16x),
        .serial_rx(serial_rx), .rx_data(rx_data),
        .rx_valid_pulse(rx_valid_pulse), .frame_error(frame_error)
    );
    rx_interface_fsm rx_interface_inst (
        .clk(clk), .reset(reset_internal), .rx_data(rx_data),
        .rx_valid_pulse(rx_valid_pulse), .frame_error(frame_error),
        .operation_ready(operation_ready), .a(a), .b(b), .op(op),
        .operation_valid_pulse(operation_valid_pulse), .protocol_error(protocol_error)
    );
    alu #(.N_DATA(8), .N_OP(6)) alu_inst (
        .a(a), .b(b), .op(op), .res(alu_result),
        .zero(), .overflow(), .carry_out()
    );
    tx_interface_fsm #(.DATA_BITS(8)) tx_interface_inst (
        .clk(clk), .reset(reset_internal), .operation_valid_pulse(operation_valid_pulse),
        .alu_result(alu_result), .tx_busy(tx_busy), .tx_done_pulse(tx_done_pulse),
        .tx_data(tx_data), .tx_start_pulse(tx_start_pulse), .operation_ready(operation_ready)
    );
    uart_tx #(.DATA_BITS(8)) tx_inst (
        .clk(clk), .reset(reset_internal), .tick_16x(tick_16x),
        .tx_start_pulse(tx_start_pulse), .tx_data(tx_data),
        .serial_tx(serial_tx), .tx_busy(tx_busy), .tx_done_pulse(tx_done_pulse)
    );
endmodule

`default_nettype wire
