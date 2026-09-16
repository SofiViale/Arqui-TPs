`timescale 1ns / 1ps
`default_nettype none

module rx_interface_fsm (
    input wire clk,
    input wire reset,
    input wire [7:0] rx_data,
    input wire rx_valid_pulse,
    input wire frame_error,
    input wire operation_ready,
    output reg [7:0] a,
    output reg [7:0] b,
    output reg [5:0] op,
    output wire operation_valid_pulse,
    output wire protocol_error
);
    localparam [2:0] S_WAIT_CMD = 3'd0, S_WAIT_A = 3'd1, S_WAIT_B = 3'd2,
                     S_WAIT_OP = 3'd3, S_LOAD = 3'd4, S_ERROR = 3'd5;
    reg [2:0] state, next_state;

    always @(*) begin
        next_state = state;
        case (state)
            S_WAIT_CMD: if (rx_valid_pulse && rx_data == 8'hCD && operation_ready)
                next_state = S_WAIT_A;
            S_WAIT_A: if (rx_valid_pulse) next_state = S_WAIT_B;
            S_WAIT_B: if (rx_valid_pulse) next_state = S_WAIT_OP;
            S_WAIT_OP: if (rx_valid_pulse) begin
                if (rx_data[7:6] == 2'b00) next_state = S_LOAD;
                else next_state = S_ERROR;
            end
            S_LOAD: next_state = S_WAIT_CMD;
            S_ERROR: next_state = S_WAIT_CMD;
            default: next_state = S_WAIT_CMD;
        endcase
        // A damaged UART frame invalidates the partial command.
        if (frame_error) next_state = S_WAIT_CMD;
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= S_WAIT_CMD;
            a <= 0;
            b <= 0;
            op <= 0;
        end else begin
            state <= next_state;
            case (state)
                S_WAIT_A: if (rx_valid_pulse && !frame_error) a <= rx_data;
                S_WAIT_B: if (rx_valid_pulse && !frame_error) b <= rx_data;
                S_WAIT_OP: if (rx_valid_pulse && !frame_error && rx_data[7:6] == 0)
                    op <= rx_data[5:0];
                S_WAIT_CMD, S_LOAD, S_ERROR: begin end
                default: begin
                    a <= 0;
                    b <= 0;
                    op <= 0;
                end
            endcase
        end
    end

    assign operation_valid_pulse = !reset && !frame_error && (state == S_LOAD);
    assign protocol_error = !reset && (state == S_ERROR);
endmodule

`default_nettype wire
