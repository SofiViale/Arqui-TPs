`timescale 1ns / 1ps
`include "tp3_defs.vh"
module alu_tb;
    reg [31:0] a, b;
    reg [3:0] op;
    wire [31:0] result;
    wire zero;
    tp3_alu_adapter dut (.a(a), .b(b), .alu_op(op), .result(result), .zero(zero));
    `include "check.vh"
    task vector;
        input [3:0] operation;
        input [31:0] av, bv, expected;
        begin
            op = operation; a = av; b = bv; #1;
            if (result !== expected) $display("op=%d a=%h b=%h got=%h expected=%h", op,a,b,result,expected);
            check(result === expected, "ALU result");
            check(zero === (expected == 0), "ALU zero");
        end
    endtask
    initial begin
        vector(`TP3_ALU_ADD,0,0,0);
        vector(`TP3_ALU_ADD,32'hffffffff,1,0);
        vector(`TP3_ALU_ADD,32'h7fffffff,1,32'h80000000);
        vector(`TP3_ALU_ADD,32'h80000000,32'h80000000,0);
        vector(`TP3_ALU_SUB,0,1,32'hffffffff);
        vector(`TP3_ALU_SUB,32'h80000000,1,32'h7fffffff);
        vector(`TP3_ALU_SUB,23,23,0);
        vector(`TP3_ALU_AND,32'hf0f0aaaa,32'h0ff05555,32'h00f00000);
        vector(`TP3_ALU_OR,32'hf0f0aaaa,32'h0ff05555,32'hfff0ffff);
        vector(`TP3_ALU_XOR,32'hf0f0aaaa,32'h0ff05555,32'hff00ffff);
        vector(`TP3_ALU_XOR,32'hffffffff,32'hffffffff,0);
        vector(`TP3_ALU_SLT,32'h80000000,32'h7fffffff,1);
        vector(`TP3_ALU_SLTU,32'h80000000,32'h7fffffff,0);
        vector(`TP3_ALU_SLT,32'h7fffffff,32'h80000000,0);
        vector(`TP3_ALU_SLTU,32'h7fffffff,32'h80000000,1);
        vector(`TP3_ALU_SLT,32'hffffffff,0,1);
        vector(`TP3_ALU_SLTU,32'hffffffff,0,0);
        vector(`TP3_ALU_SLT,1,1,0);
        vector(`TP3_ALU_SLTU,1,1,0);
        vector(`TP3_ALU_SLL,32'h80000001,0,32'h80000001);
        vector(`TP3_ALU_SLL,32'h80000001,1,2);
        vector(`TP3_ALU_SLL,1,31,32'h80000000);
        vector(`TP3_ALU_SLL,1,32'hffffffe1,2);
        vector(`TP3_ALU_SRL,32'h80000001,0,32'h80000001);
        vector(`TP3_ALU_SRL,32'h80000001,1,32'h40000000);
        vector(`TP3_ALU_SRL,32'h80000001,31,1);
        vector(`TP3_ALU_SRL,32'h80000001,32'hffffffe0,32'h80000001);
        vector(`TP3_ALU_SRA,32'h80000001,0,32'h80000001);
        vector(`TP3_ALU_SRA,32'h80000001,1,32'hc0000000);
        vector(`TP3_ALU_SRA,32'h80000001,31,32'hffffffff);
        vector(`TP3_ALU_SRA,32'h7fffffff,31,0);
        vector(`TP3_ALU_SRA,32'h80000001,32'hffffffff,32'hffffffff);
        vector(4'd15,1,1,0);
        $display("PASS: alu_tb (%0d checks)",checks); $finish;
    end
endmodule
