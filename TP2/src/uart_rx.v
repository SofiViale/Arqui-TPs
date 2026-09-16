`timescale 1ns / 1ps
`default_nettype none

module uart_rx #(
    parameter integer DATA_BITS = 8
)(
    input wire clk,
    input wire reset,
    input wire tick_16x,
    input wire serial_rx,
    output reg [DATA_BITS-1:0] rx_data,
    output wire rx_valid_pulse,
    output wire frame_error
);
    localparam [2:0] S_IDLE = 3'd0, S_START = 3'd1, S_DATA = 3'd2,
                     S_STOP = 3'd3, S_DONE = 3'd4, S_ERROR = 3'd5,
                     S_WAIT_HIGH = 3'd6;
    localparam integer BIT_WIDTH = (DATA_BITS > 1) ? $clog2(DATA_BITS) : 1;
    localparam [BIT_WIDTH-1:0] LAST_BIT = DATA_BITS - 1;
    reg [2:0] state, next_state;
    reg [3:0] tick_count;
    reg [BIT_WIDTH-1:0] bit_index;
    reg [DATA_BITS-1:0] shift_reg;
    (* ASYNC_REG = "TRUE" *) reg rx_meta, rx_sync;

    always @(posedge clk) begin
        if (reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= serial_rx;
            rx_sync <= rx_meta;
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: if (!rx_sync) next_state = S_START;
            S_START: if (tick_16x && tick_count == 4'd7) begin
                if (!rx_sync) next_state = S_DATA;
                else next_state = S_IDLE;
            end
            S_DATA: if (tick_16x && tick_count == 4'd15 && bit_index == LAST_BIT)
                next_state = S_STOP;
            S_STOP: if (tick_16x && tick_count == 4'd15) begin
                if (rx_sync) next_state = S_DONE;
                else next_state = S_ERROR;
            end
            S_DONE: next_state = S_IDLE;
            S_ERROR: next_state = S_WAIT_HIGH;
            S_WAIT_HIGH: if (rx_sync) next_state = S_IDLE;
            default: next_state = S_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            tick_count <= 0;
            bit_index <= 0;
            shift_reg <= 0;
            rx_data <= 0;
        end else begin
            state <= next_state;
            case (state)
                S_IDLE: begin
                    tick_count <= 0;
                    bit_index <= 0;
                    shift_reg <= 0;
                end
                S_START: if (tick_16x) begin
                    if (tick_count == 4'd7) tick_count <= 0;
                    else tick_count <= tick_count + 1'b1;
                end
                S_DATA: if (tick_16x) begin
                    if (tick_count == 4'd15) begin
                        tick_count <= 0;
                        shift_reg[bit_index] <= rx_sync;
                        if (bit_index == LAST_BIT) bit_index <= 0;
                        else bit_index <= bit_index + 1'b1;
                    end else tick_count <= tick_count + 1'b1;
                end
                S_STOP: if (tick_16x) begin
                    if (tick_count == 4'd15) begin
                        tick_count <= 0;
                        if (rx_sync) rx_data <= shift_reg;
                    end else tick_count <= tick_count + 1'b1;
                end
                S_DONE, S_ERROR, S_WAIT_HIGH: begin
                    tick_count <= 0;
                    bit_index <= 0;
                end
                default: begin
                    tick_count <= 0;
                    bit_index <= 0;
                    shift_reg <= 0;
                    rx_data <= 0;
                end
            endcase
        end
    end

    assign rx_valid_pulse = !reset && (state == S_DONE);
    assign frame_error = !reset && (state == S_ERROR);
endmodule

`default_nettype wire
