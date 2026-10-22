`timescale 1ns / 1ps
module memory_case #(parameter integer DEPTH=3)(output reg done=0, output wire [31:0] check_count);
    reg clk=0;
    always #5 clk=~clk;
    reg load=0,we=0;
    reg [31:0] fa=0,la=0,ld=0,da=0,wd=0,dbga=0;
    reg [3:0] mask=0;
    wire [31:0] inst,read_data,debug_data;
    wire fre,fae,lre,lae,dre,dae,dbgre,dbgae;
    reg [31:0] captured_im,captured_dm;
    reg [31:0] expected=0;
    integer i,m,lane;
    tp3_imem #(.DEPTH_WORDS(DEPTH)) im (.clk(clk),.load_enable(load),.fetch_addr(fa),
        .load_addr(la),.load_data(ld),.instruction(inst),.fetch_range_error(fre),
        .fetch_align_error(fae),.load_range_error(lre),.load_align_error(lae));
    tp3_dmem #(.DEPTH_WORDS(DEPTH)) dm (.clk(clk),.write_enable(we),.addr(da),
        .write_data(wd),.debug_addr(dbga),.byte_enable(mask),.read_data(read_data),
        .debug_data(debug_data),.range_error(dre),.align_error(dae),
        .debug_range_error(dbgre),.debug_align_error(dbgae));
    always @(posedge clk) begin
        captured_im <= inst;
        captured_dm <= read_data;
    end
    `include "check.vh"
    assign check_count=checks;

    task bad_access;
        input [31:0] address;
        input range_bad, align_bad;
        begin
            @(negedge clk); fa=address; la=address; da=address; dbga=address;
            load=1; we=1; mask=15; ld=32'hbadbad01; wd=32'hbadbad02; #1;
            check({fre,lre,dre,dbgre}==={4{range_bad}},"full address range errors on every port");
            check({fae,lae,dae,dbgae}==={4{align_bad}},"alignment errors on every port");
            check(inst===0 && read_data===0 && debug_data===0,"invalid reads return zero plus error");
            @(posedge clk); #1;
            @(negedge clk); load=0; we=0; fa=0; la=0; da=0; dbga=0; #1;
            check(inst===32'h00100073 && read_data===expected && debug_data===expected,"invalid writes do not alias first word");
            fa=4*(DEPTH-1); da=fa; dbga=fa; #1;
            check(inst===(DEPTH==1 ? 32'h00100073 : 32'h10000000+DEPTH-1),"invalid IM write preserves last word");
            check(read_data===(DEPTH==1 ? expected : 32'h20000000+DEPTH-1),"invalid DM write preserves last word");
        end
    endtask

    initial begin
        // Ninguna lectura esperada de RAM antes de escribir esa palabra.
        for (i=0;i<DEPTH;i=i+1) begin
            @(negedge clk); load=1; we=1; mask=15;
            la=4*i; da=4*i; ld=32'h10000000+i; wd=32'h20000000+i;
            @(posedge clk); #1;
        end
        @(negedge clk); load=0; we=0;
        for (i=0;i<DEPTH;i=i+1) begin
            fa=4*i; la=4*i; da=4*i; dbga=4*(DEPTH-1-i); #1;
            check({fre,fae,lre,lae,dre,dae,dbgre,dbgae}===0,"valid first/interior/last addresses");
            check(inst===32'h10000000+i && read_data===32'h20000000+i,"explicit initialized read");
            check(debug_data===32'h20000000+DEPTH-1-i,"independent debug address");
        end
        @(negedge clk); fa=0; la=0; da=0; dbga=0;
        load=1; we=1; mask=15; ld=32'h00100073; wd=32'h12345678; #1;
        check(inst===32'h10000000 && read_data===32'h20000000 && debug_data===32'h20000000,"old data visible before write edge");
        @(posedge clk); #1;
        check(captured_im===32'h10000000 && captured_dm===32'h20000000,"same edge consumer captures old value");
        check(inst===ld && read_data===wd && debug_data===wd,"new value after write settles");
        expected=32'h12345678;
        @(negedge clk); load=0; we=0; ld=0; wd=0;
        @(posedge clk); #1;
        check(inst===32'h00100073 && read_data===expected,"disabled writes preserve contents");
        // Las 16 mascaras: incluye cero, cada byte, combinaciones y todos.
        for (m=0;m<16;m=m+1) begin
            @(negedge clk); we=1; mask=m; wd=32'ha5b6c7d8 ^ (32'h01010101*m);
            #1; check(read_data===expected && debug_data===expected,"no asynchronous write bypass");
            for (lane=0;lane<4;lane=lane+1)
                if ((m>>lane)&1) expected[8*lane +: 8]=wd[8*lane +: 8];
            @(posedge clk); #1;
            check(read_data===expected && debug_data===expected,"byte mask updates only selected little-endian lanes");
        end
        bad_access(4*DEPTH,1,0);
        bad_access(32'h80000000,1,0);
        bad_access(32'hfffffffc,1,0);
        bad_access(32'hffffffff,1,1);
        bad_access(1,0,1);
        bad_access(2,0,1);
        bad_access(4*DEPTH-1,0,1);
        @(negedge clk); fa=0; la=4*DEPTH; load=0; da=0; dbga=4*DEPTH;
        #1;
        check(inst===32'h00100073 && fre===0 && lre===1,"IM fetch independent from invalid load port");
        check(read_data===expected && dre===0 && dbgre===1 && debug_data===0,"DM core independent from invalid debug port");
        $display("memory depth=%0d PASS (%0d checks)",DEPTH,checks);
        done=1;
    end
endmodule

module memory_tb;
    wire d1,d3,d256;
    wire [31:0] c1,c3,c256;
    memory_case #(.DEPTH(1)) m1 (.done(d1),.check_count(c1));
    memory_case #(.DEPTH(3)) m3 (.done(d3),.check_count(c3));
    memory_case #(.DEPTH(256)) m256 (.done(d256),.check_count(c256));
    initial begin
        wait(d1 && d3 && d256);
        $display("PASS: memory_tb (%0d checks)",c1+c3+c256); $finish;
    end
    initial begin #1000000; $fatal(1,"FAIL: memory top watchdog"); end
endmodule
