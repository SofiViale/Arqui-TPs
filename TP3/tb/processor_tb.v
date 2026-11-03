`timescale 1ns/1ps
module processor_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,restart=0,run_cmd=0,pause_cmd=0,step_cmd=0,program_valid=0,load_we=0,clear_we=0;
 reg [31:0] entry=0,program_bytes=0,cycle_limit=1000,load_addr=0,load_data=0,clear_addr=0,debug_mem_addr=0;
 reg [4:0] debug_reg_addr=0;
 wire [31:0] debug_reg_data,debug_mem_data,pc,cycles,fault_pc,used_lo,used_hi;
 wire used_valid,running,pipeline_empty,enabled,stall;wire [2:0] state;wire [7:0] cause;wire [3:0] valid,exceptions;
 wire [63:0] fi;wire [195:0] ix;wire [140:0] xm;wire [102:0] mw;
 tp3_processor dut(.clk(clk),
.reset(reset),
.restart(restart),
.run_cmd(run_cmd),
.pause_cmd(pause_cmd),
.step_cmd(step_cmd),
.entry(entry),
.program_bytes(program_bytes),
.cycle_limit(cycle_limit),
.program_valid(program_valid),
.load_we(load_we),
.load_addr(load_addr),
.load_data(load_data),
.clear_we(clear_we),
.clear_addr(clear_addr),
.debug_reg_addr(debug_reg_addr),
.debug_mem_addr(debug_mem_addr),
.debug_reg_data(debug_reg_data),
.debug_mem_data(debug_mem_data),
.pc(pc),
.cycles(cycles),
.fault_pc(fault_pc),
.used_lo(used_lo),
.used_hi(used_hi),
.used_valid(used_valid),
.state(state),
.cause(cause),
.running(running),
.pipeline_empty(pipeline_empty),
.enabled(enabled),
.stall(stall),
.fi(fi),
.ix(ix),
.xm(xm),
.mw(mw),
.exceptions(exceptions),.pipeline_valid(valid));
 integer checks=0,stalls=0,j,mode,steps;reg [31:0] prev_cycles;reg [539:0] frozen;
 task check;input condition;input [255:0] label;begin checks=checks+1;if(condition!==1'b1)begin $display("FAIL %s pc=%h cycles=%d cause=%d",label,pc,cycles,cause);$fatal(1);end end endtask
 task tick;begin @(posedge clk);#1;end endtask
 task begin_program;input [31:0] bytes,limit;begin
  @(negedge clk);reset=1;program_valid=0;run_cmd=0;step_cmd=0;pause_cmd=0;tick;
  @(negedge clk);reset=0;program_bytes=bytes;cycle_limit=limit;clear_we=1;
  for(j=0;j<256;j=j+1)begin clear_addr=j*4;tick;@(negedge clk);end
  clear_we=0;
 end endtask
 task put;input [31:0] address,word;begin load_we=1;load_addr=address;load_data=word;tick;@(negedge clk);load_we=0;end endtask
 task execute;input integer stepped;begin
  program_valid=1;restart=1;tick;@(negedge clk);restart=0;stalls=0;steps=0;
  if(!stepped)begin run_cmd=1;tick;@(negedge clk);run_cmd=0;end
  while(state!=3&&state!=4&&steps<1200)begin
   if(stepped)begin
    step_cmd=0;frozen={pc,valid,fi,ix,xm,mw};prev_cycles=cycles;
    repeat(3)tick;
    check(cycles==prev_cycles&&frozen==={pc,valid,fi,ix,xm,mw},"pause holds pipeline");
    @(negedge clk);step_cmd=1;
   end
   if(stall)stalls=stalls+1;
   prev_cycles=cycles;tick;
   check(cycles==prev_cycles+1,"one enabled cycle");
   @(negedge clk);step_cmd=0;steps=steps+1;
  end
  check(steps<1200,"execution timeout");check(pipeline_empty,"empty on stop");
 end endtask
 task regcheck;input [4:0] index;input [31:0] expected;begin
  debug_reg_addr=index;#0.01;
  if(debug_reg_data!==expected)$display("x%d got=%h expected=%h",index,debug_reg_data,expected);
  check(debug_reg_data===expected,"register result");
 end endtask
 task memcheck;input [31:0] address,expected;begin debug_mem_addr=address;#0.01;check(debug_mem_data===expected,"memory result");end endtask
 initial begin
  `include "processor_cases.vh"
  // PAUSE dominates RUN/STEP on an edge with both WB and MEM store pending.
  begin_program(24,1000);
  put(0,32'h00700093);put(4,32'h00508113);put(8,32'h00202023);
  put(12,32'h00002183);put(16,32'h00118233);put(20,32'h00100073);
  program_valid=1;run_cmd=1;tick;@(negedge clk);run_cmd=0;
  repeat(5)begin tick;@(negedge clk);end
  frozen={pc,valid,fi,ix,xm,mw};prev_cycles=cycles;
  pause_cmd=1;step_cmd=1;run_cmd=1;tick;@(negedge clk);
  pause_cmd=0;step_cmd=0;run_cmd=0;
  repeat(20)tick;
  check(cycles==prev_cycles && frozen==={pc,valid,fi,ix,xm,mw},"PAUSE overrides RUN and STEP");
  check(!dut.store_we&&!dut.wb_we,"paused side effects disabled");
  regcheck(1,7);regcheck(2,0);memcheck(0,0);check(!used_valid,"no access before pending store");
  @(negedge clk);run_cmd=1;tick;@(negedge clk);run_cmd=0;
  while(state!=3&&state!=4)begin tick;@(negedge clk);end
  regcheck(4,19);memcheck(0,12);check(cause==1&&pipeline_empty,"resume finishes normally");
  check(used_valid&&used_lo==0&&used_hi==3,"used extent includes all four bytes");
  // Reset with pending WB/MEM effects: no write survives the reset edge.
  begin_program(24,1000);put(0,32'h00700093);put(4,32'h00102023);put(8,32'h00100073);
  program_valid=1;run_cmd=1;tick;@(negedge clk);run_cmd=0;
  repeat(4)begin tick;@(negedge clk);end
  reset=1;tick;@(negedge clk);reset=0;
  check(pipeline_empty&&cycles==0,"reset flushes busy pipeline");regcheck(1,0);memcheck(0,0);
  $display("PASS: processor_tb (%0d checks)",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"processor timeout");end
endmodule
