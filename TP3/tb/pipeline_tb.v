`timescale 1ns / 1ps
`include "tp3_defs.vh"
module pipeline_tb;
    localparam DEPTH=128;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, core_enable=0, fetch_enable=0, load_enable=0;
    reg [31:0] load_addr=0, load_data=0;
    reg [4:0] debug_addr=0;
    wire [31:0] pc, debug_data, wb_data, wb_pc, wb_inst;
    wire [4:0] wb_rd;
    wire accepted,rejected,lr,la,fv,fe,fr,fa,illegal,unsupported,empty,write_enable;
    wire [3:0] valid;
    wire [63:0] fi;
    wire [195:0] ie;
    wire [140:0] em;
    wire [102:0] mw;
    tp3_arithmetic_system #(.IMEM_DEPTH_WORDS(DEPTH)) dut (
        .clk(clk),.reset(reset),.core_enable(core_enable),.fetch_enable(fetch_enable),
        .load_enable(load_enable),.load_addr(load_addr),.load_data(load_data),
        .load_accepted(accepted),.load_rejected(rejected),.load_range_error(lr),.load_align_error(la),
        .debug_reg_addr(debug_addr),.pc(pc),.debug_reg_data(debug_data),
        .fetch_valid(fv),.fetch_error(fe),.fetch_range_error(fr),.fetch_align_error(fa),
        .decode_illegal(illegal),.decode_unsupported(unsupported),
        .pipeline_valid(valid),.pipeline_empty(empty),.debug_if_id(fi),.debug_id_ex(ie),
        .debug_ex_mem(em),.debug_mem_wb(mw),.wb_write_enable(write_enable),
        .wb_rd(wb_rd),.wb_data(wb_data),.wb_pc(wb_pc),.wb_instruction(wb_inst)
    );
    `include "check.vh"

    // Oraculo independiente: resultados literales y cola de indices de programa.
    // No usa el decoder ni la ALU del DUT para calcular valores esperados.
    reg [31:0] words[0:DEPTH-1], values[0:DEPTH-1], registers[0:31];
    reg [4:0] destinations[0:DEPTH-1];
    integer classification[0:DEPTH-1]; // 0 aritmetica; 1 ilegal; 2 futura
    integer count=0, mid=-1, mex=-1, mmem=-1, mwb=-1;
    integer edges=0, commits=0, overlaps=0, i, j, trace;
    reg [31:0] expected_pc=0;
    reg [8*512-1:0] trace_path;
    reg [539:0] saved_state;
    reg expected_write;

    // Codificadores del testbench, no un ensamblador de usuario.
    function [31:0] r;
        input [6:0] f7;
        input [2:0] f3;
        input [4:0] rd,rs1,rs2;
        begin r={f7,rs2,rs1,f3,rd,7'h33}; end
    endfunction
    function [31:0] imm;
        input [11:0] value;
        input [2:0] f3;
        input [4:0] rd,rs1;
        begin imm={value,rs1,f3,rd,7'h13}; end
    endfunction
    function [31:0] lui;
        input [19:0] value;
        input [4:0] rd;
        begin lui={value,rd,7'h37}; end
    endfunction
    task append;
        input [31:0] word;
        input [4:0] destination;
        input [31:0] value;
        input integer kind;
        begin
            check(count<DEPTH,"program fits test IMEM");
            words[count]=word; destinations[count]=destination;
            values[count]=value; classification[count]=kind; count=count+1;
        end
    endtask
    task nop;
        begin append(32'h00000013,0,0,0); end
    endtask
    task check_stage;
        input actual_valid;
        input [31:0] actual_pc,actual_inst;
        input integer index;
        begin
            check(actual_valid===(index>=0),"stage validity agrees with independent queue");
            if (index>=0) begin
                check(actual_pc===(32'd4*index),"PC travels with instruction");
                check(actual_inst===words[index],"instruction travels through every stage");
            end
        end
    endtask
    task bank;
        integer n;
        begin
            for(n=0;n<32;n=n+1) begin
                debug_addr=n; #0.01;
                if(debug_data!==registers[n]) $display("x%0d got=%h expected=%h edge=%0d",n,debug_data,registers[n],edges);
                check(debug_data===registers[n],"all architectural registers match scoreboard");
            end
        end
    endtask
    task cycle;
        input advance,fetch,rst;
        begin
            @(negedge clk); core_enable=advance; fetch_enable=fetch; reset=rst; #1;
            saved_state={pc,valid,fi,ie,em,mw};
            expected_write=0;
            if(!rst && advance && mwb>=0) expected_write=(destinations[mwb]!=0);
            check(write_enable===expected_write,"WB enable requires valid, advance, !reset and rd!=0");
            check(fv===(!rst && fetch && expected_pc<DEPTH*4),"fetch valid respects request and memory range");
            check(fe===(!rst && fetch && expected_pc>=DEPTH*4),"fetch error is explicit");
            if(expected_write) begin
                check(wb_rd===destinations[mwb],"writeback destination of correct instruction");
                check(wb_data===values[mwb],"writeback arithmetic value");
                check(wb_pc===32'd4*mwb && wb_inst===words[mwb],"writeback identity");
            end
            edges=edges+1;
            $fdisplay(trace,"%0d,%b,%b,%b,%b,%08h,%b,%08h,%08h,%b,%08h,%08h,%b,%08h,%08h,%b,%08h,%08h,%b,%0d,%08h",
                edges,reset,core_enable,fetch_enable,fv,pc,valid[0],fi[63:32],fi[31:0],
                valid[1],ie[195:164],ie[163:132],valid[2],em[140:109],em[108:77],
                valid[3],wb_pc,wb_inst,write_enable,wb_rd,wb_data);
            @(posedge clk); #1;
            if(rst) begin
                expected_pc=0; mid=-1; mex=-1; mmem=-1; mwb=-1;
                for(j=0;j<32;j=j+1) registers[j]=0;
                check({pc,valid,fi,ie,em,mw}===0,"reset clears PC and every pipeline field");
            end else if(advance) begin
                if(expected_write) begin registers[destinations[mwb]]=values[mwb]; commits=commits+1; end
                mwb=mmem; mmem=mex;
                if(mid>=0) mex=(classification[mid]==0) ? mid : -1;
                else mex=-1;
                if(fetch && expected_pc<DEPTH*4) begin
                    mid=expected_pc/4; expected_pc=expected_pc+4;
                end else mid=-1;
            end else check({pc,valid,fi,ie,em,mw}===saved_state,"global pause holds all pipeline bits and PC");
            check(pc===expected_pc,"PC advances four bytes only on accepted fetch");
            check_stage(valid[0],fi[63:32],fi[31:0],mid);
            check_stage(valid[1],ie[195:164],ie[163:132],mex);
            check_stage(valid[2],em[140:109],em[108:77],mmem);
            check_stage(valid[3],wb_pc,wb_inst,mwb);
            check(empty===((mid<0)&&(mex<0)&&(mmem<0)&&(mwb<0)),"empty is reduction of all four valids");
            if(!rst && mid>=0) begin
                check(illegal===(classification[mid]==1),"illegal diagnostic");
                check(unsupported===(classification[mid]==2),"recognized future instruction diagnostic");
            end else check(illegal===0 && unsupported===0,"invalid ID never raises decoder diagnostic");
            if(valid===4'b1111) overlaps=overlaps+1;
            bank;
        end
    endtask
    task load_program;
        integer n;
        begin
            cycle(0,0,1);
            @(negedge clk); reset=0;
            // Inicializar tambien el resto: ninguna comparacion presupone RAM cero.
            for(n=0;n<DEPTH;n=n+1) begin
                @(negedge clk); load_enable=1; load_addr=4*n;
                load_data=(n<count) ? words[n] : 32'h00000013;
                #1; check(accepted===1 && rejected===0,"logical program load while paused and empty");
                @(posedge clk); #1;
            end
            @(negedge clk); load_enable=0;
        end
    endtask
    task run_program;
        input pauses;
        integer n;
        begin
            for(n=0;n<count;n=n+1) begin
                if(pauses && (n%3==1)) begin cycle(0,1,0); cycle(0,0,0); end
                cycle(1,1,0);
            end
            // Dejar de admitir fetch no congela las instrucciones anteriores.
            for(n=0;n<4;n=n+1) cycle(1,0,0);
            check(empty===1,"four drain cycles after final admitted instruction");
            cycle(1,0,0); cycle(0,0,0);
        end
    endtask

    initial begin
        if(!$value$plusargs("TRACE=%s",trace_path)) trace_path="TP3/build/pipeline_trace.csv";
        trace=$fopen(trace_path,"w"); check(trace!=0,"trace file opened");
        $fdisplay(trace,"edge,reset,enable,fetch_enable,IF_valid,IF_pc,ID_valid,ID_pc,ID_inst,EX_valid,EX_pc,EX_inst,MEM_valid,MEM_pc,MEM_inst,WB_valid,WB_pc,WB_inst,WB_write,WB_rd,WB_data");
        // Semillas independientes. Dos NOP permiten incluso al ultimo productor
        // coincidir en WB con la lectura ID de su consumidor (bypass de etapa 1).
        append(imm(7,0,1,0),1,7,0);
        append(imm(-3,0,2,0),2,32'hfffffffd,0);
        append(lui(20'h80000,3),3,32'h80000000,0);
        append(imm(1,0,4,0),4,1,0);
        nop; nop;
        append(r(0,0,5,1,2),5,4,0);                    // ADD
        append(r(32,0,6,1,2),6,10,0);                  // SUB
        append(r(0,1,7,1,4),7,14,0);                   // SLL
        append(r(0,5,8,3,4),8,32'h40000000,0);          // SRL
        append(r(32,5,9,3,4),9,32'hc0000000,0);         // SRA
        append(r(0,7,10,1,2),10,5,0);                  // AND
        append(r(0,6,11,1,2),11,32'hffffffff,0);         // OR
        append(r(0,4,12,1,2),12,32'hfffffffa,0);         // XOR
        append(r(0,2,13,2,1),13,1,0);                  // SLT
        append(r(0,3,14,2,1),14,0,0);                  // SLTU
        append(imm(-8,0,15,1),15,32'hffffffff,0);       // ADDI
        append(imm(-2,7,16,1),16,6,0);                 // ANDI
        append(imm(8,6,17,1),17,15,0);                 // ORI
        append(imm(-1,4,18,1),18,32'hfffffff8,0);       // XORI
        append(imm(0,2,19,2),19,1,0);                  // SLTI
        append(imm(-1,3,20,1),20,1,0);                 // SLTIU
        append(imm(31,1,21,4),21,32'h80000000,0);       // SLLI
        append(imm(31,5,22,3),22,1,0);                 // SRLI
        append(imm(12'h41f,5,23,3),23,32'hffffffff,0);  // SRAI
        append(lui(20'habcde,24),24,32'habcde000,0);     // LUI
        append(imm(42,0,31,0),31,42,0);                // x31 general
        append(imm(99,0,0,0),0,99,0);                  // x0 protegido
        append(r(0,0,25,3,3),25,0,0);                  // overflow modular
        append(r(0,0,26,31,1),26,49,0);                // WB/ID con 2 separadores
        load_program; run_program(0);
        check(commits==27,"exact number of architectural writes, no x0/NOP commits");
        check(overlaps>0,"four simultaneous occupied pipeline registers");
        // Repetir con pausas en distintos puntos debe dar iguales resultados.
        load_program; run_program(1);
        check(commits==54,"pauses neither lose nor duplicate commits");

        // Consumidor con DOS NOP: captura WB mediante bypass en el mismo flanco.
        count=0;
        append(imm(9,0,1,0),1,9,0); nop; nop;
        append(imm(1,0,2,1),2,10,0); nop; nop;
        append(r(0,0,31,2,1),31,19,0);
        load_program;
        for(i=0;i<4;i=i+1) cycle(1,1,0);
        // Hay WB pendiente y un consumidor en ID. Intentar cargar no debe escribir.
        load_enable=1; load_addr=0; load_data=32'hfff00093;
        cycle(0,1,0); check(rejected===1 && accepted===0,"reject reprogramming paused but nonempty");
        cycle(1,1,0); check(rejected===1 && accepted===0,"reject reprogramming while running");
        load_enable=0;
        for(i=5;i<count;i=i+1) cycle(1,1,0);
        for(i=0;i<4;i=i+1) cycle(1,0,0);

        // Reset con pipeline lleno y WB a punto de escribir: domina enable.
        load_program;
        for(i=0;i<4;i=i+1) cycle(1,1,0);
        load_enable=1; load_addr=0; load_data=32'hfff00093;
        cycle(1,1,1); check(rejected===1,"reset blocks logical memory load");
        load_enable=0;
        cycle(0,0,1); // Reset tambien funciona con enable=0.
        run_program(0); // Sin recargar IMEM: reset conservo el programa.

        // Clasificar no equivale a ejecutar: ninguna instruccion futura/ilegal
        // puede escribir el resultado ALU accidentalmente ni cambiar el PC.
        count=0;
        append(imm(7,0,1,0),1,7,0);
        append(32'h00002103,2,0,2); // LW
        append(32'h00102023,0,0,2); // SW
        append(32'h00000463,0,0,2); // BEQ
        append(32'h00001463,0,0,2); // BNE
        append(32'h0080016f,2,0,2); // JAL
        append(32'h00000167,2,0,2); // JALR
        append(32'h00100073,0,0,2); // HALT reconocido, sin controlador aun
        append(32'h00000073,0,0,1); // ECALL ilegal
        append(32'h02000133,2,0,1); // MUL ilegal
        append(32'h00000000,0,0,1); // Palabra cero NO es NOP
        append(imm(3,0,31,0),31,3,0);
        load_program; run_program(1);
        check(registers[2]===0 && registers[31]===3,"unsupported/illegal have no write or halt effects");

        // Limite de IMEM: no alias de bits altos; ciclos de error introducen
        // burbujas mientras las instrucciones validas previas completan.
        count=0;
        for(i=0;i<DEPTH-1;i=i+1) nop;
        append(imm(11,0,31,0),31,11,0);
        load_program;
        for(i=0;i<count;i=i+1) cycle(1,1,0);
        for(i=0;i<5;i=i+1) cycle(1,1,0);
        check(pc===DEPTH*4 && fe===1 && empty===1,"out-of-range fetch holds PC, reports error and cannot alias");
        check(registers[31]===11,"last valid instruction still completes");
        $fclose(trace);
        $display("PASS: pipeline_tb (%0d checks, %0d edges, %0d commits, %0d overlap cycles)",checks,edges,commits,overlaps);
        $finish;
    end
endmodule
