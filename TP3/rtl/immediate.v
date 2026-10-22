`timescale 1ns / 1ps
`default_nettype none
`include "tp3_defs.vh"

module tp3_immediate (
    input wire [31:0] instruction,
    input wire [2:0] imm_type,
    output reg [31:0] immediate,
    output wire [4:0] shamt
);
    wire [31:0] inst = instruction;
    assign shamt = inst[24:20];
    always @(*) begin
        case (imm_type)
            `TP3_IMM_I: immediate = {{20{inst[31]}}, inst[31:20]};
            `TP3_IMM_S: immediate = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            // B/J ya incluyen el cero inferior: no desplazar nuevamente.
            `TP3_IMM_B: immediate = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            `TP3_IMM_U: immediate = {inst[31:12], 12'b0};
            `TP3_IMM_J: immediate = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
            default: immediate = 32'b0;
        endcase
    end
endmodule
`default_nettype wire
