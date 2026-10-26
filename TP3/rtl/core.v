`timescale 1ns / 1ps
`default_nettype none
`include "tp3_defs.vh"

// Etapa de desarrollo 2: pipeline R/I aritmetico y LUI, sin riesgos ni saltos.
// instruction es una lectura combinacional de IMEM para la direccion pc.
module tp3_core #(
    parameter [31:0] RESET_PC = 32'b0
)(
    input wire clk, reset, core_enable, fetch_enable,
    input wire [31:0] instruction,
    input wire instruction_error,
    input wire [4:0] debug_reg_addr,
    output wire [31:0] pc, debug_reg_data,
    output wire fetch_valid, fetch_error, decode_illegal, decode_unsupported,
    output wire [3:0] pipeline_valid,
    output wire pipeline_empty,
    output wire [`TP3_IF_ID_WIDTH-1:0] debug_if_id,
    output wire [`TP3_ID_EX_WIDTH-1:0] debug_id_ex,
    output wire [`TP3_EX_MEM_WIDTH-1:0] debug_ex_mem,
    output wire [`TP3_MEM_WB_WIDTH-1:0] debug_mem_wb,
    output wire wb_write_enable,
    output wire [4:0] wb_rd,
    output wire [31:0] wb_data, wb_pc, wb_instruction
);
    wire id_valid, ex_valid, mem_valid, wb_valid;
    wire [31:0] id_pc, id_instruction, id_operand1, id_operand2, id_immediate;
    wire [4:0] id_rs1, id_rs2, id_rd;
    wire id_illegal, id_uses_rs1, id_uses_rs2, id_reg_write;
    wire id_mem_read, id_mem_write, id_src_b_imm, id_unsigned, id_halt;
    wire [3:0] id_alu_op;
    wire [1:0] id_src_a, id_wb_sel, id_mem_size;
    wire [2:0] id_imm_type, id_branch;

    wire [31:0] ex_pc, ex_instruction, ex_operand1, ex_operand2, ex_immediate;
    wire [4:0] ex_rs1, ex_rs2, ex_rd;
    wire ex_uses_rs1, ex_uses_rs2, ex_reg_write, ex_mem_read, ex_mem_write;
    wire ex_src_b_imm, ex_unsigned, ex_halt;
    wire [3:0] ex_alu_op;
    wire [1:0] ex_src_a, ex_wb_sel, ex_mem_size;
    wire [2:0] ex_branch;
    wire [31:0] ex_a, ex_b, ex_alu_result, ex_result;

    wire [31:0] mem_pc, mem_instruction, mem_result, mem_store_data;
    wire [4:0] mem_rd;
    wire mem_reg_write, mem_read, mem_write, mem_unsigned, mem_wb_from_mem, mem_halt;
    wire [1:0] mem_size;
    wire wb_reg_write, wb_halt;

    // fetch_enable es un estimulo externo provisional: permite dejar de buscar
    // y vaciar con ciclos normales, sin implementar HALT ni longitud de programa.
    assign fetch_error = !reset && fetch_enable && instruction_error;
    assign fetch_valid = !reset && fetch_enable && !instruction_error;
    tp3_pc #(.RESET_PC(RESET_PC)) program_counter (
        .clk(clk), .reset(reset), .enable(core_enable && fetch_valid),
        .next_pc(pc + 32'd4), .pc(pc)
    );
    tp3_pipeline_register #(.WIDTH(`TP3_IF_ID_WIDTH)) if_id (
        .clk(clk), .reset(reset), .flush(1'b0), .enable(core_enable),
        .valid_in(fetch_valid), .data_in({pc, instruction}),
        .valid_out(id_valid), .data_out(debug_if_id)
    );
    assign {id_pc, id_instruction} = debug_if_id;

    tp3_decoder decoder (
        .instruction(id_instruction), .opcode(), .funct7(), .funct3(),
        .rs1(id_rs1), .rs2(id_rs2), .rd(id_rd), .illegal(id_illegal),
        .uses_rs1(id_uses_rs1), .uses_rs2(id_uses_rs2), .reg_write(id_reg_write),
        .mem_read(id_mem_read), .mem_write(id_mem_write), .alu_op(id_alu_op),
        .src_a(id_src_a), .src_b_imm(id_src_b_imm), .imm_type(id_imm_type),
        .wb_sel(id_wb_sel), .mem_size(id_mem_size), .load_unsigned(id_unsigned),
        .branch_type(id_branch), .is_halt(id_halt)
    );
    tp3_immediate immediate_generator (
        .instruction(id_instruction), .imm_type(id_imm_type),
        .immediate(id_immediate), .shamt()
    );
    // Consumir la clasificacion existente, sin otra tabla de instrucciones.
    wire id_arithmetic = !id_illegal && id_reg_write && !id_mem_read &&
        !id_mem_write && (id_branch == `TP3_BR_NONE) && !id_halt &&
        ((id_wb_sel == `TP3_WB_EX) || (id_wb_sel == `TP3_WB_IMM));
    assign decode_illegal = !reset && id_valid && id_illegal;
    assign decode_unsupported = !reset && id_valid && !id_illegal && !id_arithmetic;

    tp3_register_file registers (
        .clk(clk), .reset(reset), .write_enable(wb_write_enable),
        .rs1(id_rs1), .rs2(id_rs2), .rd(wb_rd), .debug_addr(debug_reg_addr),
        .write_data(wb_data), .read_data1(id_operand1),
        .read_data2(id_operand2), .debug_data(debug_reg_data)
    );
    tp3_pipeline_register #(.WIDTH(`TP3_ID_EX_WIDTH)) id_ex (
        .clk(clk), .reset(reset), .flush(1'b0), .enable(core_enable),
        .valid_in(id_valid && id_arithmetic),
        .data_in({id_pc, id_instruction, id_rs1, id_rs2, id_rd,
            id_operand1, id_operand2, id_immediate, id_uses_rs1, id_uses_rs2,
            id_alu_op, id_src_a, id_src_b_imm, id_reg_write, id_mem_read,
            id_mem_write, id_wb_sel, id_mem_size, id_unsigned, id_branch, id_halt}),
        .valid_out(ex_valid), .data_out(debug_id_ex)
    );
    assign {ex_pc, ex_instruction, ex_rs1, ex_rs2, ex_rd, ex_operand1, ex_operand2,
        ex_immediate, ex_uses_rs1, ex_uses_rs2, ex_alu_op, ex_src_a, ex_src_b_imm,
        ex_reg_write, ex_mem_read, ex_mem_write, ex_wb_sel, ex_mem_size,
        ex_unsigned, ex_branch, ex_halt} = debug_id_ex;
    assign ex_a = (ex_src_a == `TP3_A_ZERO) ? 32'b0 :
                  ((ex_src_a == `TP3_A_PC) ? ex_pc : ex_operand1);
    assign ex_b = ex_src_b_imm ? ex_immediate : ex_operand2;
    tp3_alu_adapter execution_alu (
        .a(ex_a), .b(ex_b), .alu_op(ex_alu_op), .result(ex_alu_result), .zero()
    );
    // Normalizar el resultado antes de MEM simplifica WB y el forwarding futuro.
    assign ex_result = (ex_wb_sel == `TP3_WB_IMM) ? ex_immediate : ex_alu_result;
    tp3_pipeline_register #(.WIDTH(`TP3_EX_MEM_WIDTH)) ex_mem (
        .clk(clk), .reset(reset), .flush(1'b0), .enable(core_enable),
        .valid_in(ex_valid),
        .data_in({ex_pc, ex_instruction, ex_rd, ex_result, ex_operand2,
            ex_reg_write, ex_mem_read, ex_mem_write, ex_mem_size,
            ex_unsigned, 1'b0, ex_halt}),
        .valid_out(mem_valid), .data_out(debug_ex_mem)
    );
    assign {mem_pc, mem_instruction, mem_rd, mem_result, mem_store_data,
        mem_reg_write, mem_read, mem_write, mem_size, mem_unsigned,
        mem_wb_from_mem, mem_halt} = debug_ex_mem;

    // MEM solo transporta el resultado aritmetico. No hay acceso a DMEM.
    tp3_pipeline_register #(.WIDTH(`TP3_MEM_WB_WIDTH)) mem_wb (
        .clk(clk), .reset(reset), .flush(1'b0), .enable(core_enable),
        .valid_in(mem_valid),
        .data_in({mem_pc, mem_instruction, mem_rd, mem_result, mem_reg_write, mem_halt}),
        .valid_out(wb_valid), .data_out(debug_mem_wb)
    );
    assign {wb_pc, wb_instruction, wb_rd, wb_data, wb_reg_write, wb_halt} = debug_mem_wb;
    // Imprescindible: pausar el pipeline tambien debe deshabilitar su escritura.
    assign wb_write_enable = !reset && core_enable && wb_valid && wb_reg_write && (wb_rd != 0);
    assign pipeline_valid = {wb_valid, mem_valid, ex_valid, id_valid};
    assign pipeline_empty = !(|pipeline_valid);
endmodule
`default_nettype wire
