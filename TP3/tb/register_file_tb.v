`timescale 1ns / 1ps
module register_file_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, we = 0;
    reg [4:0] rs1 = 0, rs2 = 0, rd = 0, dbg = 0;
    reg [31:0] wd = 0;
    wire [31:0] r1,r2,dd;
    integer i;
    tp3_register_file dut (.clk(clk),.reset(reset),.write_enable(we),
        .rs1(rs1),.rs2(rs2),.rd(rd),.debug_addr(dbg),.write_data(wd),
        .read_data1(r1),.read_data2(r2),.debug_data(dd));
    `include "check.vh"
    initial begin
        @(posedge clk); #1;
        for (i=0;i<32;i=i+1) begin
            rs1=i; rs2=31-i; dbg=i; #1;
            check(r1===0 && r2===0 && dd===0,"reset clears every register");
        end
        @(negedge clk); reset=0;
        for (i=0;i<32;i=i+1) begin
            @(negedge clk); we=1; rd=i; wd=32'habc00000+i; rs1=i; rs2=i; dbg=i;
            #1;
            check(r1===(i==0 ? 0 : wd) && r2===(i==0 ? 0 : wd),"bypass both ports, x0 protected");
            check(dd===0,"debug before posedge shows stored data");
            @(posedge clk); #1;
            check(dd===(i==0 ? 0 : wd),"debug after write, including x31");
        end
        @(negedge clk); we=0; wd=32'hffffffff;
        for (i=0;i<32;i=i+1) begin
            rs1=i; rs2=31-i; dbg=i; #1;
            check(r1===(i==0 ? 0 : 32'habc00000+i),"port1 independent stored read");
            check(r2===(i==31 ? 0 : 32'habc00000+31-i),"port2 independent stored read");
            check(dd===r1,"debug equals stored data when bypass disabled");
        end
        @(negedge clk); rd=31; rs1=31; rs2=30; dbg=31;
        @(posedge clk); #1;
        check(dd===32'habc0001f,"disabled write holds");
        @(negedge clk); we=1; wd=32'h12345678; #1;
        check(r1===wd && r2===32'habc0001e && dd===32'habc0001f,"bypass only matching port");
        reset=1; #1;
        check(r1===32'habc0001f && dd===32'habc0001f,"reset suppresses bypass before edge");
        @(posedge clk); #1;
        check(r1===0 && r2===0 && dd===0,"reset overrides enabled write");
        @(negedge clk); reset=0; rd=0; rs1=0; rs2=0; dbg=0;
        @(posedge clk); #1;
        check(r1===0 && r2===0 && dd===0,"x0 ignores nonzero write");
        $display("PASS: register_file_tb (%0d checks)",checks); $finish;
    end
endmodule
