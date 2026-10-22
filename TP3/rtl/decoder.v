`timescale 1ns / 1ps
`default_nettype none
`include "tp3_defs.vh"

module tp3_decoder (
    input wire [31:0] instruction,
    output wire [6:0] opcode, funct7,
    output wire [2:0] funct3,
    output wire [4:0] rs1, rs2, rd,
    output reg illegal, uses_rs1, uses_rs2,
    output reg reg_write, mem_read, mem_write,
    output reg [3:0] alu_op,
    output reg [1:0] src_a,
    output reg src_b_imm,
    output reg [2:0] imm_type,
    output reg [1:0] wb_sel, mem_size,
    output reg load_unsigned,
    output reg [2:0] branch_type,
    output reg is_halt
);
    assign opcode = instruction[6:0];
    assign rd = instruction[11:7];
    assign funct3 = instruction[14:12];
    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];
    assign funct7 = instruction[31:25];

    always @(*) begin
        illegal = 0;
        uses_rs1 = 0; uses_rs2 = 0;
        reg_write = 0; mem_read = 0; mem_write = 0;
        alu_op = `TP3_ALU_ADD;
        src_a = `TP3_A_RS1; src_b_imm = 0;
        imm_type = `TP3_IMM_NONE; wb_sel = `TP3_WB_EX;
        mem_size = `TP3_MEM_WORD; load_unsigned = 0;
        branch_type = `TP3_BR_NONE; is_halt = 0;
        case (opcode)
            7'b0110011: begin
                uses_rs1 = 1; uses_rs2 = 1; reg_write = 1;
                // Validar los 7 bits evita interpretar MUL u otras extensiones.
                case ({funct7, funct3})
                    {7'b0000000,3'b000}: alu_op = `TP3_ALU_ADD;
                    {7'b0100000,3'b000}: alu_op = `TP3_ALU_SUB;
                    {7'b0000000,3'b001}: alu_op = `TP3_ALU_SLL;
                    {7'b0000000,3'b010}: alu_op = `TP3_ALU_SLT;
                    {7'b0000000,3'b011}: alu_op = `TP3_ALU_SLTU;
                    {7'b0000000,3'b100}: alu_op = `TP3_ALU_XOR;
                    {7'b0000000,3'b101}: alu_op = `TP3_ALU_SRL;
                    {7'b0100000,3'b101}: alu_op = `TP3_ALU_SRA;
                    {7'b0000000,3'b110}: alu_op = `TP3_ALU_OR;
                    {7'b0000000,3'b111}: alu_op = `TP3_ALU_AND;
                    default: illegal = 1;
                endcase
            end
            7'b0010011: begin
                uses_rs1 = 1; reg_write = 1;
                src_b_imm = 1; imm_type = `TP3_IMM_I;
                case (funct3)
                    3'b000: alu_op = `TP3_ALU_ADD;
                    3'b010: alu_op = `TP3_ALU_SLT;
                    3'b011: alu_op = `TP3_ALU_SLTU;
                    3'b100: alu_op = `TP3_ALU_XOR;
                    3'b110: alu_op = `TP3_ALU_OR;
                    3'b111: alu_op = `TP3_ALU_AND;
                    3'b001: begin
                        alu_op = `TP3_ALU_SLL;
                        if (funct7 != 0) illegal = 1;
                    end
                    3'b101: begin
                        case (funct7)
                            7'b0000000: alu_op = `TP3_ALU_SRL;
                            7'b0100000: alu_op = `TP3_ALU_SRA;
                            default: illegal = 1;
                        endcase
                    end
                    default: illegal = 1;
                endcase
            end
            7'b0000011: begin
                uses_rs1 = 1; reg_write = 1; mem_read = 1;
                src_b_imm = 1; imm_type = `TP3_IMM_I; wb_sel = `TP3_WB_MEM;
                case (funct3)
                    3'b000: mem_size = `TP3_MEM_BYTE;
                    3'b001: mem_size = `TP3_MEM_HALF;
                    3'b010: mem_size = `TP3_MEM_WORD;
                    3'b100: begin mem_size = `TP3_MEM_BYTE; load_unsigned = 1; end
                    3'b101: begin mem_size = `TP3_MEM_HALF; load_unsigned = 1; end
                    default: illegal = 1;
                endcase
            end
            7'b0100011: begin
                uses_rs1 = 1; uses_rs2 = 1; mem_write = 1;
                src_b_imm = 1; imm_type = `TP3_IMM_S;
                case (funct3)
                    3'b000: mem_size = `TP3_MEM_BYTE;
                    3'b001: mem_size = `TP3_MEM_HALF;
                    3'b010: mem_size = `TP3_MEM_WORD;
                    default: illegal = 1;
                endcase
            end
            7'b1100011: begin
                uses_rs1 = 1; uses_rs2 = 1;
                src_a = `TP3_A_PC; src_b_imm = 1; imm_type = `TP3_IMM_B;
                case (funct3)
                    3'b000: branch_type = `TP3_BR_BEQ;
                    3'b001: branch_type = `TP3_BR_BNE;
                    default: illegal = 1;
                endcase
            end
            7'b1101111: begin
                reg_write = 1; src_a = `TP3_A_PC; src_b_imm = 1;
                imm_type = `TP3_IMM_J; wb_sel = `TP3_WB_PC4;
                branch_type = `TP3_BR_JAL;
            end
            7'b1100111: begin
                uses_rs1 = 1; reg_write = 1; src_b_imm = 1;
                imm_type = `TP3_IMM_I; wb_sel = `TP3_WB_PC4;
                branch_type = `TP3_BR_JALR;
                if (funct3 != 0) illegal = 1;
            end
            7'b0110111: begin
                reg_write = 1; src_a = `TP3_A_ZERO; src_b_imm = 1;
                imm_type = `TP3_IMM_U; wb_sel = `TP3_WB_IMM;
            end
            7'b1110011: begin
                if (instruction == `TP3_HALT) is_halt = 1;
                else illegal = 1;
            end
            default: illegal = 1;
        endcase
        // No propagar controles parciales de una familia con funct invalido.
        if (illegal) begin
            uses_rs1 = 0; uses_rs2 = 0;
            reg_write = 0; mem_read = 0; mem_write = 0;
            alu_op = `TP3_ALU_ADD;
            src_a = `TP3_A_RS1; src_b_imm = 0;
            imm_type = `TP3_IMM_NONE; wb_sel = `TP3_WB_EX;
            mem_size = `TP3_MEM_WORD; load_unsigned = 0;
            branch_type = `TP3_BR_NONE; is_halt = 0;
        end
    end
endmodule
`default_nettype wire
