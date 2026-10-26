`timescale 1ns / 1ps
`default_nettype none
`include "tp3_defs.vh"

// Integracion de laboratorio: IMEM + nucleo aritmetico. No es un top de placa.
module tp3_arithmetic_system #(
    parameter integer IMEM_DEPTH_WORDS = 256,
    parameter [31:0] RESET_PC = 32'b0
)(
    input wire clk, reset, core_enable, fetch_enable,
    input wire load_enable,
    input wire [31:0] load_addr, load_data,
    output wire load_accepted, load_rejected, load_range_error, load_align_error,
    input wire [4:0] debug_reg_addr,
    output wire [31:0] pc, debug_reg_data,
    output wire fetch_valid, fetch_error, fetch_range_error, fetch_align_error,
    output wire decode_illegal, decode_unsupported,
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
    wire [31:0] instruction;
    // Interlock combinacional del puerto de laboratorio; sin protocolo/loader.
    assign load_accepted = load_enable && !reset && !core_enable && pipeline_empty &&
                           !load_range_error && !load_align_error;
    assign load_rejected = load_enable && !load_accepted;
    tp3_imem #(.DEPTH_WORDS(IMEM_DEPTH_WORDS)) instruction_memory (
        .clk(clk), .load_enable(load_accepted), .fetch_addr(pc),
        .load_addr(load_addr), .load_data(load_data), .instruction(instruction),
        .fetch_range_error(fetch_range_error), .fetch_align_error(fetch_align_error),
        .load_range_error(load_range_error), .load_align_error(load_align_error)
    );
    tp3_core #(.RESET_PC(RESET_PC)) core (
        .clk(clk), .reset(reset), .core_enable(core_enable), .fetch_enable(fetch_enable),
        .instruction(instruction), .instruction_error(fetch_range_error || fetch_align_error),
        .debug_reg_addr(debug_reg_addr), .pc(pc), .debug_reg_data(debug_reg_data),
        .fetch_valid(fetch_valid), .fetch_error(fetch_error),
        .decode_illegal(decode_illegal), .decode_unsupported(decode_unsupported),
        .pipeline_valid(pipeline_valid), .pipeline_empty(pipeline_empty),
        .debug_if_id(debug_if_id), .debug_id_ex(debug_id_ex),
        .debug_ex_mem(debug_ex_mem), .debug_mem_wb(debug_mem_wb),
        .wb_write_enable(wb_write_enable), .wb_rd(wb_rd), .wb_data(wb_data),
        .wb_pc(wb_pc), .wb_instruction(wb_instruction)
    );
endmodule
`default_nettype wire
