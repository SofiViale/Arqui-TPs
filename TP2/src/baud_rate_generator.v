`timescale 1ns / 1ps
`default_nettype none

module baud_rate_generator #(
    parameter integer CLK_FREQ = 100000000,
    parameter integer BAUD_RATE = 9600
)(
    input wire clk,
    input wire reset,
    output reg tick_16x
);
    // Supported configuration: CLK_FREQ >= BAUD_RATE * 16, both positive.
    // Divide in two steps to avoid overflowing the BAUD_RATE * 16 product.
    localparam integer DIVISOR = (CLK_FREQ / BAUD_RATE) / 16;
    localparam integer COUNT_WIDTH = (DIVISOR > 1) ? $clog2(DIVISOR) : 1;
    localparam [COUNT_WIDTH-1:0] LAST_COUNT = DIVISOR - 1;
    reg [COUNT_WIDTH-1:0] counter;

    always @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            tick_16x <= 1'b0;
        end else begin
            tick_16x <= 1'b0;
            if (counter == LAST_COUNT) begin
                counter <= 0;
                tick_16x <= 1'b1;
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
