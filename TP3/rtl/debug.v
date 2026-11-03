`timescale 1ns/1ps
`default_nettype none
module tp3_debug #(parameter WORDS=256)(
 input wire clk,reset,local_step,link_busy,
 input wire request,input wire [7:0] command,input wire [15:0] length,
 output reg accept,output reg [9:0] request_index,input wire [7:0] request_data,
 output reg response,output reg [15:0] response_length,
 input wire [9:0] response_index,output wire [7:0] response_data,
 output reg restart,run_cmd,pause_cmd,step_cmd,
 output reg program_valid,load_we,clear_we,
 output reg [31:0] entry,program_bytes,cycle_limit,load_addr,load_data,clear_addr,
 output reg [4:0] debug_reg_addr,input wire [31:0] debug_reg_data,
 output reg [31:0] debug_mem_addr,input wire [31:0] debug_mem_data,
 input wire [31:0] pc,cycles,fault_pc,used_lo,used_hi,
 input wire used_valid,running,pipeline_empty,input wire [2:0] core_state,input wire [7:0] cause,
 input wire [3:0] pipeline_valid,exceptions,
 input wire [63:0] fi,input wire [195:0] ix,input wire [140:0] xm,input wire [102:0] mw,
 output wire busy
);
 localparam IDLE=0,COPY=1,EXEC=2,CLEAR=3,LOAD=4,WAIT=5,SNAP=6,MEM=7,REPLY=8;
 reg [3:0] state;reg [7:0] cmd;reg [15:0] len;
 reg [9:0] index;reg [31:0] loaded,mem_start,mem_count;
 reg [7:0] payload[0:131]; reg [7:0] reply[0:256];
 assign response_data=reply[response_index];
 assign busy=(state!=IDLE)||link_busy;
 wire [31:0] p0={payload[3],payload[2],payload[1],payload[0]};
 wire [31:0] p1={payload[7],payload[6],payload[5],payload[4]};
 task word_reply;input integer offset;input [31:0] value;begin
 reply[offset]<=value[7:0];reply[offset+1]<=value[15:8];reply[offset+2]<=value[23:16];reply[offset+3]<=value[31:24];end endtask
 task fail;input [7:0] error;begin reply[0]<=error;response_length<=1;state<=REPLY;end endtask
 integer j;
 always @(posedge clk) begin
  if(reset)begin
   state<=IDLE;accept<=0;response<=0;response_length<=0;request_index<=0;restart<=0;run_cmd<=0;pause_cmd<=0;step_cmd<=0;
   program_valid<=0;load_we<=0;clear_we<=0;entry<=0;program_bytes<=0;cycle_limit<=1000000;load_addr<=0;load_data<=0;clear_addr<=0;
   debug_reg_addr<=0;debug_mem_addr<=0;cmd<=0;len<=0;index<=0;loaded<=0;mem_start<=0;mem_count<=0;
  end else begin
   accept<=0;response<=0;restart<=0;run_cmd<=0;pause_cmd<=0;step_cmd<=0;load_we<=0;clear_we<=0;
   case(state)
    IDLE:begin
     if(request&&!accept&&!response)begin cmd<=command;len<=length;request_index<=0;state<=(length==0||length>132)?EXEC:COPY;end
     else if(local_step&&!link_busy&&!running&&(core_state==0||core_state==2))step_cmd<=1;
    end
    COPY:begin
     payload[request_index]<=request_data;
     if(request_index+1>=len)state<=EXEC;else request_index<=request_index+1;
    end
    EXEC:begin
     reply[0]<=0;response_length<=1;index<=0;
     case(cmd)
      1:if(len!=0)fail(2);else begin
       word_reply(1,32'h33545031);word_reply(5,WORDS*4);word_reply(9,512);word_reply(13,128);
       word_reply(17,64);word_reply(21,196);word_reply(25,141);word_reply(29,103);
       word_reply(33,{16'b0,cause,4'b0,program_valid,core_state});word_reply(37,pc);word_reply(41,cycles);
       response_length<=45;state<=REPLY;
      end
      2:if(len!=9)fail(2);else if(running||!pipeline_empty)fail(3);
        else if(p0==0||p0>WORDS*4||p0[1:0]!=0||p1>=p0||p1[1:0]!=0||payload[8]>1)fail(4);
        else begin
         program_valid<=0;program_bytes<=p0;entry<=p1;loaded<=0;restart<=1;
         if(payload[8]==0)begin clear_addr<=0;state<=CLEAR;end else state<=WAIT;
        end
      3:if(len<8||len>132||len[1:0]!=0)fail(2);
        else if(running||!pipeline_empty||program_valid)fail(3);
        else if(program_bytes==0||p0!=loaded||({1'b0,p0}+len-4)>program_bytes)fail(4);
        else begin index<=4;state<=LOAD;end
      4:if(len!=0)fail(2);else if(program_bytes==0||loaded!=program_bytes)fail(5);
        else if(running||!pipeline_empty)fail(3);else begin program_valid<=1;restart<=1;state<=WAIT;end
      5,6:if(len!=0)fail(2);else if(!program_valid)fail(5);
        else if(core_state==3||core_state==4||(cmd==6&&running))fail(3);
        else begin if(cmd==5)run_cmd<=1;else step_cmd<=1;state<=WAIT;end
      7:if(len!=0)fail(2);else begin pause_cmd<=1;state<=WAIT;end
      8:if(len!=1)fail(2);else if(payload[0]>1)fail(4);
        else begin restart<=1;if(payload[0]==0)begin clear_addr<=0;state<=CLEAR;end else state<=WAIT;end
      9:if(len!=0)fail(2);else begin pause_cmd<=1;state<=WAIT;index<=0;end
      10:if(len!=8)fail(2);else if(p0[1:0]!=0||p1==0||p1>128||p1[1:0]!=0||({1'b0,p0}+{1'b0,p1})>WORDS*4)fail(4);
         else begin pause_cmd<=1;mem_start<=p0;mem_count<=p1;debug_mem_addr<=p0;state<=WAIT;end
      11:if(len!=4)fail(2);else if(running)fail(3);else begin cycle_limit<=p0;state<=REPLY;end
      default:fail(1);
     endcase
    end
    CLEAR:begin
     clear_we<=1;
     if(index==WORDS-1)begin state<=WAIT;index<=0;end
     else index<=index+1;
     clear_addr<=index*4;
    end
    LOAD:begin
     load_we<=1;load_addr<=loaded+index-4;
     load_data<={payload[index+3],payload[index+2],payload[index+1],payload[index]};
     if(index+4>=len)begin loaded<=loaded+len-4;state<=WAIT;end else index<=index+4;
    end
    WAIT:begin
     if(cmd==9)begin
      // Pause pulse is consumed on this edge; capture begins on the next edge.
      debug_reg_addr<=0;index<=0;state<=SNAP;
     end else if(cmd==10)begin index<=0;state<=MEM;end else state<=REPLY;
    end
    SNAP:begin
     if(index==0)begin
      word_reply(1,32'h33545031);word_reply(5,{29'b0,core_state});word_reply(9,pc);word_reply(13,cycles);
      word_reply(17,{24'b0,cause});word_reply(21,fault_pc);word_reply(25,{28'b0,pipeline_valid});
      word_reply(29,{28'b0,exceptions});word_reply(33,{31'b0,used_valid});word_reply(37,used_lo);
      word_reply(41,used_hi);word_reply(45,program_bytes);word_reply(49,entry);word_reply(53,cycle_limit);
      word_reply(57,{31'b0,running});word_reply(61,{31'b0,program_valid});
      for(j=0;j<8;j=j+1)reply[193+j]<=fi>>(8*j);
      for(j=0;j<25;j=j+1)reply[201+j]<=ix>>(8*j);
      for(j=0;j<18;j=j+1)reply[226+j]<=xm>>(8*j);
      for(j=0;j<13;j=j+1)reply[244+j]<=mw>>(8*j);
     end
     word_reply(65+index*4,debug_reg_data);
     if(index==31)begin response_length<=257;state<=REPLY;end
     else begin index<=index+1;debug_reg_addr<=debug_reg_addr+1;end
    end
    MEM:begin
     word_reply(1+index,debug_mem_data);
     if(index+4>=mem_count)begin response_length<=mem_count+1;state<=REPLY;end
     else begin index<=index+4;debug_mem_addr<=debug_mem_addr+4;end
    end
    REPLY:begin response<=1;accept<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
`default_nettype wire
