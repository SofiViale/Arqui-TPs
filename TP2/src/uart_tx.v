`timescale 1ns / 1ps
`default_nettype none

module uart_tx #(
    parameter integer DATA_BITS = 8
)(
    input wire clk,
    input wire reset,
    input wire tick_16x,
    input wire tx_start_pulse,
    input wire [DATA_BITS-1:0] tx_data,
    output reg serial_tx,
    output reg tx_busy,
    output wire tx_done_pulse
);
    localparam [2:0] S_IDLE = 3'd0, S_ALIGN = 3'd1, S_START = 3'd2,
                     S_DATA = 3'd3, S_STOP = 3'd4, S_DONE = 3'd5;
    localparam integer BIT_WIDTH = (DATA_BITS > 1) ? $clog2(DATA_BITS) : 1;
    localparam [BIT_WIDTH-1:0] LAST_BIT = DATA_BITS - 1;
    reg [2:0] state, next_state;
    reg [3:0] tick_count;
    reg [BIT_WIDTH-1:0] bit_index;
    reg [DATA_BITS-1:0] data_reg;

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: if (tx_start_pulse) next_state = S_ALIGN;
            // Align the start edge to the enable: every bit lasts 16 FULL ticks.
            S_ALIGN: if (tick_16x) next_state = S_START;
            S_START: if (tick_16x && tick_count == 4'd15) next_state = S_DATA;
            S_DATA: if (tick_16x && tick_count == 4'd15 && bit_index == LAST_BIT)
                next_state = S_STOP;
            S_STOP: if (tick_16x && tick_count == 4'd15) next_state = S_DONE;
            S_DONE: next_state = S_IDLE;
            default: next_state = S_IDLE;
        endcase
    end

    always @(*) begin
        serial_tx = 1'b1;
        tx_busy = 1'b0;
        if (!reset) begin
            case (state)
                S_ALIGN, S_STOP, S_DONE: tx_busy = 1'b1;
                S_START: begin
                    serial_tx = 1'b0;
                    tx_busy = 1'b1;
                end
                S_DATA: begin
                    serial_tx = data_reg[bit_index];
                    tx_busy = 1'b1;
                end
                S_IDLE: begin
                    serial_tx = 1'b1;
                    tx_busy = 1'b0;
                end
                default: begin
                    serial_tx = 1'b1;
                    tx_busy = 1'b0;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            tick_count <= 0;
            bit_index <= 0;
            data_reg <= 0;
        end else begin
            state <= next_state;
            case (state)
                S_IDLE: begin
                    tick_count <= 0;
                    bit_index <= 0;
                    if (tx_start_pulse) data_reg <= tx_data;
                end
                S_ALIGN: begin
                    tick_count <= 0;
                    bit_index <= 0;
                end
                S_START, S_DATA, S_STOP: if (tick_16x) begin
                    if (tick_count == 4'd15) begin
                        tick_count <= 0;
                        if (state == S_DATA) begin
                            if (bit_index == LAST_BIT) bit_index <= 0;
                            else bit_index <= bit_index + 1'b1;
                        end
                    end else tick_count <= tick_count + 1'b1;
                end
                S_DONE: begin
                    tick_count <= 0;
                    bit_index <= 0;
                end
                default: begin
                    tick_count <= 0;
                    bit_index <= 0;
                    data_reg <= 0;
                end
            endcase
        end
    end

    assign tx_done_pulse = !reset && (state == S_DONE);
endmodule

`default_nettype wire
