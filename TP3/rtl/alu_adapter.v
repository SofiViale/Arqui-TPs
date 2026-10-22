`timescale 1ns / 1ps
`default_nettype none
`include "tp3_defs.vh"

module tp3_alu_adapter (
    input wire [31:0] a, b,
    input wire [3:0] alu_op,
    output reg [31:0] result,
    output wire zero
);
    reg [5:0] tp1_op;
    wire [31:0] tp1_result;
    // TP1 desplaza por todo B; RV32 solamente por B[4:0].
    wire [31:0] tp1_b = ((alu_op == `TP3_ALU_SRL) ||
                        (alu_op == `TP3_ALU_SRA)) ? {27'b0, b[4:0]} : b;

    alu #(.N_DATA(32), .N_OP(6)) original (
        .a(a), .b(tp1_b), .op(tp1_op), .res(tp1_result),
        .zero(), .overflow(), .carry_out()
    );
    always @(*) begin
        case (alu_op)
            `TP3_ALU_ADD: tp1_op = 6'b100000;
            `TP3_ALU_SUB: tp1_op = 6'b100010;
            `TP3_ALU_AND: tp1_op = 6'b100100;
            `TP3_ALU_OR:  tp1_op = 6'b100101;
            `TP3_ALU_XOR: tp1_op = 6'b100110;
            `TP3_ALU_SRL: tp1_op = 6'b000010;
            `TP3_ALU_SRA: tp1_op = 6'b000011;
            default:     tp1_op = 6'b100000;
        endcase
        case (alu_op)
            `TP3_ALU_ADD, `TP3_ALU_SUB, `TP3_ALU_AND, `TP3_ALU_OR,
            `TP3_ALU_XOR, `TP3_ALU_SRL, `TP3_ALU_SRA: result = tp1_result;
            // Solo estas tres operaciones faltan en TP1.
            `TP3_ALU_SLL:  result = a << b[4:0];
            `TP3_ALU_SLT:  result = {31'b0, ($signed(a) < $signed(b))};
            `TP3_ALU_SLTU: result = {31'b0, (a < b)};
            default:      result = 32'b0;
        endcase
    end
    assign zero = (result == 0);
endmodule
`default_nettype wire
