`timescale 1ns / 1ps
`default_nettype none

module tp3_pc #(
    parameter [31:0] RESET_PC = 32'b0
)(
    input wire clk, reset, enable,
    input wire [31:0] next_pc,
    output reg [31:0] pc
);
    always @(posedge clk) begin
        if (reset) pc <= RESET_PC;
        else if (enable) pc <= next_pc;
    end
endmodule

module tp3_pipeline_register #(
    parameter integer WIDTH = 32
)(
    input wire clk, reset, flush, enable, valid_in,
    input wire [WIDTH-1:0] data_in,
    output reg valid_out,
    output reg [WIDTH-1:0] data_out
);
    // La integracion futura debe condicionar flush por core_enable.
    always @(posedge clk) begin
        if (reset) begin
            data_out <= 0;
            valid_out <= 0;
        end else if (flush) begin
            data_out <= 0;
            valid_out <= 0;
        end else if (enable) begin
            data_out <= data_in;
            valid_out <= valid_in;
        end
    end
endmodule
`default_nettype wire
