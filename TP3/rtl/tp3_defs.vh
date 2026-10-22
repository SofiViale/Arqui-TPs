`ifndef TP3_DEFS_VH
`define TP3_DEFS_VH
// Codigos internos; no son opcode/funct de RISC-V ni operaciones de TP1.
`define TP3_ALU_ADD  4'd0
`define TP3_ALU_SUB  4'd1
`define TP3_ALU_AND  4'd2
`define TP3_ALU_OR   4'd3
`define TP3_ALU_XOR  4'd4
`define TP3_ALU_SLL  4'd5
`define TP3_ALU_SRL  4'd6
`define TP3_ALU_SRA  4'd7
`define TP3_ALU_SLT  4'd8
`define TP3_ALU_SLTU 4'd9
`define TP3_IMM_NONE 3'd0
`define TP3_IMM_I    3'd1
`define TP3_IMM_S    3'd2
`define TP3_IMM_B    3'd3
`define TP3_IMM_U    3'd4
`define TP3_IMM_J    3'd5
`define TP3_A_RS1  2'd0
`define TP3_A_PC   2'd1
`define TP3_A_ZERO 2'd2
`define TP3_WB_EX  2'd0
`define TP3_WB_MEM 2'd1
`define TP3_WB_PC4 2'd2
`define TP3_WB_IMM 2'd3
`define TP3_MEM_BYTE 2'd0
`define TP3_MEM_HALF 2'd1
`define TP3_MEM_WORD 2'd2
`define TP3_BR_NONE 3'd0
`define TP3_BR_BEQ  3'd1
`define TP3_BR_BNE  3'd2
`define TP3_BR_JAL  3'd3
`define TP3_BR_JALR 3'd4
`define TP3_HALT 32'h00100073
`endif
