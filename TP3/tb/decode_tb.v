`timescale 1ns / 1ps
`include "tp3_defs.vh"
module decode_tb;
    reg [31:0] inst=0, operand1=0, operand2=0;
    wire [6:0] opcode,f7;
    wire [2:0] f3,it,br;
    wire [4:0] rs1,rs2,rd,shamt;
    wire illegal,u1,u2,rw,mr,mw,bi,uns,halt;
    wire [3:0] op;
    wire [1:0] sa,wb,size;
    reg direct=0;
    reg [2:0] direct_type=0;
    wire [31:0] imm,result;
    wire zero;
    wire [31:0] a=(sa==`TP3_A_ZERO) ? 0 : ((sa==`TP3_A_PC) ? 32'h100 : operand1);
    wire [31:0] b=bi ? imm : operand2;
    wire [31:0] arithmetic_result=(wb==`TP3_WB_IMM) ? imm : result;
    wire [24:0] controls={illegal,u1,u2,rw,mr,mw,op,sa,bi,it,wb,size,uns,br,halt};
    integer i,j;
    tp3_decoder dut (.instruction(inst),.opcode(opcode),.funct7(f7),.funct3(f3),
        .rs1(rs1),.rs2(rs2),.rd(rd),.illegal(illegal),.uses_rs1(u1),.uses_rs2(u2),
        .reg_write(rw),.mem_read(mr),.mem_write(mw),.alu_op(op),.src_a(sa),
        .src_b_imm(bi),.imm_type(it),.wb_sel(wb),.mem_size(size),
        .load_unsigned(uns),.branch_type(br),.is_halt(halt));
    tp3_immediate ig (.instruction(inst),.imm_type(direct ? direct_type : it),.immediate(imm),.shamt(shamt));
    tp3_alu_adapter alu (.a(a),.b(b),.alu_op(op),.result(result),.zero(zero));
    `include "check.vh"

    task fields;
        begin
            check({f7,rs2,rs1,f3,rd,opcode}===inst,"all raw instruction fields");
        end
    endtask
    // Expected controls son literales del contrato, nunca salidas del DUT.
    task decoded;
        input [31:0] word;
        input [1:0] sources;
        input [2:0] effects; // reg_write, mem_read, mem_write
        input [3:0] operation;
        input [1:0] source_a;
        input immediate_b;
        input [2:0] immediate_type;
        input [1:0] writeback, access_size;
        input unsigned_load;
        input [2:0] branch;
        input stop;
        reg [24:0] expected;
        reg [31:0] variant;
        integer k;
        begin
            expected={1'b0,sources,effects,operation,source_a,immediate_b,
                      immediate_type,writeback,access_size,unsigned_load,branch,stop};
            // Variar indices sin tocar inmediatos/codificacion de cada formato.
            for (k=0;k<33;k=k+1) begin
                variant=word;
                if (k<32 && !stop) begin
                    case (word[6:0])
                        7'h33: begin variant[11:7]=k; variant[19:15]=31-k; variant[24:20]=k; end
                        7'h13,7'h03,7'h67: begin variant[11:7]=k; variant[19:15]=31-k; end
                        7'h23,7'h63: begin variant[19:15]=31-k; variant[24:20]=k; end
                        7'h37,7'h6f: variant[11:7]=k;
                    endcase
                end
                inst=variant; #1;
                if (controls!==expected) $display("inst=%h controls=%h expected=%h",inst,controls,expected);
                check(controls===expected,"all decoder controls and real sources");
                fields;
            end
        end
    endtask
    task rejected;
        input [31:0] word;
        begin
            inst=word; #1;
            check(controls==={1'b1,2'b00,3'b000,4'd0,2'd0,1'b0,3'd0,2'd0,2'd2,1'b0,3'd0,1'b0},"illegal clears every control");
            fields;
        end
    endtask
    task immediate_vector;
        input [31:0] word;
        input [2:0] kind;
        input [31:0] expected;
        begin
            direct=1; direct_type=kind; inst=word; #1;
            check(imm===expected,"immediate exact value");
            check(shamt===word[24:20],"separate 5-bit shamt");
        end
    endtask
    // Inversas de codificacion para pruebas; el esperado es el valor matematico
    // de entrada, no una reconstruccion ni una llamada al RTL.
    task offsets;
        input integer value;
        begin
            immediate_vector({value[11:0],20'b0},`TP3_IMM_I,value);
            immediate_vector({value[11:5],13'b0,value[4:0],7'b0},`TP3_IMM_S,value);
        end
    endtask
    task branch_offset;
        input integer value;
        begin
            immediate_vector({value[12],value[10:5],13'b0,value[4:1],value[11],7'b0},`TP3_IMM_B,value);
        end
    endtask
    task jump_offset;
        input integer value;
        begin
            immediate_vector({value[20],value[10:1],value[11],value[19:12],12'b0},`TP3_IMM_J,value);
        end
    endtask
    task arithmetic;
        input [31:0] word,av,bv,expected;
        begin
            direct=0; inst=word; operand1=av; operand2=bv; #1;
            check(!illegal && rw && !mr && !mw && br==0 && !halt,"arithmetic integration classification");
            check(arithmetic_result===expected,"decoder + immediate + selectors + TP1 ALU");
        end
    endtask

    initial begin
        // word, uses, RW/MR/MW, ALU, A, Bimm, IMM, WB, SIZE, UNS, BR, HALT.
        decoded(32'h002081b3,3,4,`TP3_ALU_ADD,0,0,0,0,2,0,0,0);
        decoded(32'h402081b3,3,4,`TP3_ALU_SUB,0,0,0,0,2,0,0,0);
        decoded(32'h002091b3,3,4,`TP3_ALU_SLL,0,0,0,0,2,0,0,0);
        decoded(32'h0020d1b3,3,4,`TP3_ALU_SRL,0,0,0,0,2,0,0,0);
        decoded(32'h4020d1b3,3,4,`TP3_ALU_SRA,0,0,0,0,2,0,0,0);
        decoded(32'h0020f1b3,3,4,`TP3_ALU_AND,0,0,0,0,2,0,0,0);
        decoded(32'h0020e1b3,3,4,`TP3_ALU_OR,0,0,0,0,2,0,0,0);
        decoded(32'h0020c1b3,3,4,`TP3_ALU_XOR,0,0,0,0,2,0,0,0);
        decoded(32'h0020a1b3,3,4,`TP3_ALU_SLT,0,0,0,0,2,0,0,0);
        decoded(32'h0020b1b3,3,4,`TP3_ALU_SLTU,0,0,0,0,2,0,0,0);
        decoded(32'hfff08193,2,4,`TP3_ALU_ADD,0,1,1,0,2,0,0,0);
        decoded(32'hfff0f193,2,4,`TP3_ALU_AND,0,1,1,0,2,0,0,0);
        decoded(32'hfff0e193,2,4,`TP3_ALU_OR,0,1,1,0,2,0,0,0);
        decoded(32'hfff0c193,2,4,`TP3_ALU_XOR,0,1,1,0,2,0,0,0);
        decoded(32'h8000a193,2,4,`TP3_ALU_SLT,0,1,1,0,2,0,0,0);
        decoded(32'hfff0b193,2,4,`TP3_ALU_SLTU,0,1,1,0,2,0,0,0);
        decoded(32'h01f09193,2,4,`TP3_ALU_SLL,0,1,1,0,2,0,0,0);
        decoded(32'h01f0d193,2,4,`TP3_ALU_SRL,0,1,1,0,2,0,0,0);
        decoded(32'h41f0d193,2,4,`TP3_ALU_SRA,0,1,1,0,2,0,0,0);
        decoded(32'hfff08183,2,6,0,0,1,1,1,0,0,0,0); // LB
        decoded(32'h80009183,2,6,0,0,1,1,1,1,0,0,0); // LH
        decoded(32'h7ff0a183,2,6,0,0,1,1,1,2,0,0,0); // LW
        decoded(32'hfff0c183,2,6,0,0,1,1,1,0,1,0,0); // LBU
        decoded(32'hfff0d183,2,6,0,0,1,1,1,1,1,0,0); // LHU
        decoded(32'hfe208fa3,3,1,0,0,1,2,0,0,0,0,0); // SB
        decoded(32'hfe209fa3,3,1,0,0,1,2,0,1,0,0,0); // SH
        decoded(32'hfe20afa3,3,1,0,0,1,2,0,2,0,0,0); // SW
        decoded(32'hfe208ee3,3,0,0,1,1,3,0,2,0,1,0); // BEQ
        decoded(32'hfe209ee3,3,0,0,1,1,3,0,2,0,2,0); // BNE
        decoded(32'hffdff1ef,0,4,0,1,1,5,2,2,0,3,0); // JAL
        decoded(32'hfff081e7,2,4,0,0,1,1,2,2,0,4,0); // JALR
        decoded(32'habcde1b7,0,4,0,2,1,4,3,2,0,0,0); // LUI
        decoded(32'h00100073,0,0,0,0,0,0,0,2,0,0,1); // HALT

        // Exhaustivo funct7/funct3 R y funct7 de shifts I invalidos.
        for (i=0;i<128;i=i+1) begin
            for (j=0;j<8;j=j+1) begin
                if (!(i==0 || (i==32 && (j==0 || j==5))))
                    rejected((i<<25)|(2<<20)|(1<<15)|(j<<12)|(3<<7)|32'h33);
            end
            if (i!=0) rejected((i<<25)|32'h01f09193);
            if (i!=0 && i!=32) rejected((i<<25)|32'h01f0d193);
        end
        for (j=0;j<8;j=j+1) begin
            if (j!=0 && j!=1 && j!=2 && j!=4 && j!=5) rejected((j<<12)|32'h00000003);
            if (j>2) rejected((j<<12)|32'h00000023);
            if (j>1) rejected((j<<12)|32'h00000063);
            if (j!=0) rejected((j<<12)|32'h00000067);
        end
        for (i=0;i<128;i=i+1)
            if (i!=51 && i!=19 && i!=3 && i!=35 && i!=99 && i!=111 && i!=103 && i!=55 && i!=115)
                rejected(i); // Incluye AUIPC/FENCE y palabras no de 32 bits.
        rejected(32'h00000073); // ECALL no es HALT.
        for (i=7;i<32;i=i+1) rejected(32'h00100073 ^ (32'b1<<i));
        // Un legal despues del barrido ilegal tambien debe restaurar controles.
        decoded(32'h002081b3,3,4,0,0,0,0,0,2,0,0,0);

        offsets(0); offsets(1); offsets(-1); offsets(2047); offsets(-2048); offsets(1365); offsets(-683);
        branch_offset(0); branch_offset(2); branch_offset(-2); branch_offset(4094); branch_offset(-4096);
        for (i=1;i<12;i=i+1) branch_offset(1<<i);
        branch_offset(-1366);
        jump_offset(0); jump_offset(2); jump_offset(-2); jump_offset(1048574); jump_offset(-1048576);
        for (i=1;i<20;i=i+1) jump_offset(1<<i);
        jump_offset(-349526);
        immediate_vector(32'h000001b7,4,0);
        immediate_vector(32'h000011b7,4,32'h00001000);
        immediate_vector(32'h7ffff1b7,4,32'h7ffff000);
        immediate_vector(32'h800001b7,4,32'h80000000);
        immediate_vector(32'hfffff1b7,4,32'hfffff000);
        immediate_vector(32'habcde1b7,4,32'habcde000);
        immediate_vector(32'h41f0d193,1,32'h0000041f); // SRAI: shamt=31, no 1055-bit shift.
        immediate_vector(32'h01f09193,1,31);
        immediate_vector(32'hfff0b193,1,32'hffffffff); // SLTIU con -1 extendido con signo.
        immediate_vector(32'hffffffff,0,0);
        immediate_vector(32'hffffffff,7,0);

        // Integracion combinacional: no reloj, PC, fetch ni efectos de escritura.
        arithmetic(32'h002081b3,32'hffffffff,2,1);
        arithmetic(32'h402081b3,0,1,32'hffffffff);
        arithmetic(32'h002091b3,1,32'hffffffe1,2);
        arithmetic(32'h0020d1b3,32'h80000000,31,1);
        arithmetic(32'h4020d1b3,32'h80000000,31,32'hffffffff);
        arithmetic(32'h0020a1b3,32'hffffffff,0,1);
        arithmetic(32'h0020b1b3,32'hffffffff,0,0);
        arithmetic(32'hfff08193,5,99,4);
        arithmetic(32'hfff0f193,32'h12345678,0,32'h12345678);
        arithmetic(32'hfff0e193,0,0,32'hffffffff);
        arithmetic(32'hfff0c193,32'hffffffff,0,0);
        arithmetic(32'hfff0a193,32'hfffffffe,0,1);
        arithmetic(32'hfff0b193,32'hfffffffe,0,1);
        arithmetic(32'hfff0b193,32'hffffffff,0,0);
        arithmetic(32'h01f09193,1,0,32'h80000000);
        arithmetic(32'h01f0d193,32'h80000000,0,1);
        arithmetic(32'h41f0d193,32'h80000000,0,32'hffffffff);
        arithmetic(32'habcde1b7,32'hffffffff,32'hffffffff,32'habcde000);
        $display("PASS: decode_tb (%0d checks)",checks); $finish;
    end
endmodule
