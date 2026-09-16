`timescale 1ns / 1ps
`default_nettype none

module tx_interface_fsm #(
    parameter integer DATA_BITS = 8
)(
    input wire clk,
    input wire reset,
    input wire operation_valid_pulse,
    input wire [DATA_BITS-1:0] alu_result,
    input wire tx_busy,
    input wire tx_done_pulse,
    output reg [DATA_BITS-1:0] tx_data,
    output wire tx_start_pulse,
    output wire operation_ready
);
    localparam [2:0] S_IDLE = 3'd0, S_CAPTURE_RESULT = 3'd1,
                     S_WAIT_READY = 3'd2, S_START_TX = 3'd3,
                     S_WAIT_TX_DONE = 3'd4, S_DONE = 3'd5;
    reg [2:0] state, next_state;

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: if (operation_valid_pulse) next_state = S_CAPTURE_RESULT;
            S_CAPTURE_RESULT: next_state = S_WAIT_READY;
            S_WAIT_READY: if (!tx_busy) next_state = S_START_TX;
            S_START_TX: next_state = S_WAIT_TX_DONE;
            S_WAIT_TX_DONE: if (tx_done_pulse) next_state = S_DONE;
            S_DONE: next_state = S_IDLE;
            default: next_state = S_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            tx_data <= 0;
        end else begin
            state <= next_state;
            case (state)
                // One full clock elapsed since accepting operation_valid_pulse.
                S_CAPTURE_RESULT: tx_data <= alu_result;
                S_IDLE, S_WAIT_READY, S_START_TX, S_WAIT_TX_DONE, S_DONE: begin end
                default: tx_data <= 0;
            endcase
        end
    end

    assign tx_start_pulse = !reset && (state == S_START_TX);
    assign operation_ready = !reset && (state == S_IDLE);
endmodule

`default_nettype wire
