`timescale 1ns / 1ps
module state_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, enable=0, flush=0, vin=0;
    reg [31:0] next_pc=0;
    reg [6:0] d7=0;
    reg [72:0] d73=0;
    wire [31:0] pc, pc_custom;
    wire [6:0] q7;
    wire [72:0] q73;
    wire v7,v73;
    integer mask;
    tp3_pc p0 (.clk(clk),.reset(reset),.enable(enable),.next_pc(next_pc),.pc(pc));
    tp3_pc #(.RESET_PC(32'h100)) p1 (.clk(clk),.reset(reset),.enable(enable),.next_pc(next_pc),.pc(pc_custom));
    tp3_pipeline_register #(.WIDTH(7)) r7 (.clk(clk),.reset(reset),.flush(flush),.enable(enable),.valid_in(vin),.data_in(d7),.valid_out(v7),.data_out(q7));
    tp3_pipeline_register #(.WIDTH(73)) r73 (.clk(clk),.reset(reset),.flush(flush),.enable(enable),.valid_in(vin),.data_in(d73),.valid_out(v73),.data_out(q73));
    `include "check.vh"
    initial begin
        @(posedge clk); #1;
        check(pc===0 && pc_custom===32'h100,"PC initial parameters after reset edge");
        check({v7,q7,v73,q73}===0,"pipeline initial reset");
        // Ejercitar todas las combinaciones reset/flush/enable desde estado no cero.
        for (mask=0;mask<8;mask=mask+1) begin
            @(negedge clk); reset=0; flush=0; enable=1; vin=1;
            next_pc=32'h12345678; d7=7'h55; d73={9'h155,64'hfedcba9876543210};
            @(posedge clk); #1;
            check(pc===next_pc && pc_custom===next_pc,"PC capture");
            check(q7===d7 && q73===d73 && v7===1 && v73===1,"capture both widths");
            @(negedge clk); reset=mask[2]; flush=mask[1]; enable=mask[0];
            next_pc=32'h87654320; d7=7'h2a; d73={9'h0aa,64'h0123456789abcdef}; vin=0;
            #1;
            check(pc===32'h12345678 && q7===7'h55,"state never changes before edge");
            @(posedge clk); #1;
            if (reset) check(pc===0 && pc_custom===32'h100,"PC reset priority");
            else if (enable) check(pc===next_pc && pc_custom===next_pc,"PC enabled");
            else check(pc===32'h12345678 && pc_custom===32'h12345678,"PC hold");
            if (reset || flush) check({v7,q7,v73,q73}===0,"reset/flush override enable");
            else if (enable) check(q7===d7 && q73===d73 && v7===0 && v73===0,"capture invalid payload");
            else check(q7===7'h55 && q73==={9'h155,64'hfedcba9876543210} && v7===1 && v73===1,"hold data and valid");
        end
        $display("PASS: state_tb (%0d checks)",checks); $finish;
    end
endmodule
