`timescale 1ns/1ps
`default_nettype none
`include "tp3_defs.vh"
// Complete core. Legacy core.v is retained exclusively for stage-2 regression.
module tp3_processor #(parameter WORDS=256)(
 input wire clk, reset, restart, run_cmd, pause_cmd, step_cmd,
 input wire [31:0] entry, program_bytes, cycle_limit,
 input wire program_valid, load_we,
 input wire [31:0] load_addr, load_data,
 input wire clear_we, input wire [31:0] clear_addr,
 input wire [4:0] debug_reg_addr, input wire [31:0] debug_mem_addr,
 output wire [31:0] debug_reg_data, debug_mem_data,
 output reg [31:0] pc, cycles, fault_pc, used_lo, used_hi,
 output reg used_valid,
 output wire [2:0] state, output reg [7:0] cause,
 output wire running, pipeline_empty, enabled, stall,
 output wire [3:0] pipeline_valid,
 output reg [63:0] fi,
 output reg [195:0] ix,
 output reg [140:0] xm,
 output reg [102:0] mw,
 output wire [3:0] exceptions
);
 reg active, draining, terminal;
 reg fv,xv,mv,wv, f_fault,x_fault,x_illegal;
 wire rst=reset||restart;
 assign state=terminal ? ((cause==1)?3'd3:3'd4) : draining?3'd2:active?3'd1:3'd0;
 assign running=active;
 assign enabled=!rst && !pause_cmd && !terminal && program_valid && (active||step_cmd);
 assign pipeline_valid={wv,mv,xv,fv};
 assign pipeline_empty=!(|pipeline_valid);
 assign exceptions={1'b0,x_illegal,x_fault,f_fault};
 wire [31:0] instruction;
 wire fetch_range,fetch_align;
 tp3_imem #(.DEPTH_WORDS(WORDS)) imem(.clk(clk),.load_enable(load_we),.fetch_addr(pc),
 .load_addr(load_addr),.load_data(load_data),.instruction(instruction),
 .fetch_range_error(fetch_range),.fetch_align_error(fetch_align),.load_range_error(),.load_align_error());
 wire [31:0] ip=fi[63:32], inst=fi[31:0];
 wire [4:0] rs1,rs2,rd; wire illegal,u1,u2,rw,mr,ms,bi,uns,halt;
 wire [3:0] op; wire [1:0] sa,ws,size; wire [2:0] it,br;
 wire [31:0] imm,r1,r2;
 tp3_decoder dec(.instruction(inst),.opcode(),.funct7(),.funct3(),.rs1(rs1),.rs2(rs2),.rd(rd),
 .illegal(illegal),.uses_rs1(u1),.uses_rs2(u2),.reg_write(rw),.mem_read(mr),.mem_write(ms),
 .alu_op(op),.src_a(sa),.src_b_imm(bi),.imm_type(it),.wb_sel(ws),.mem_size(size),
 .load_unsigned(uns),.branch_type(br),.is_halt(halt));
 tp3_immediate immediate_gen(.instruction(inst),.imm_type(it),.immediate(imm),.shamt());
 wire [31:0] xp,xi,xa,xb,xim; wire [4:0] xr1,xr2,xd;
 wire xu1,xu2,xbi,xrw,xmr,xms,xuns,xhalt;
 wire [3:0] xop; wire [1:0] xsa,xws,xsize; wire [2:0] xbr;
 assign {xp,xi,xr1,xr2,xd,xa,xb,xim,xu1,xu2,xop,xsa,xbi,xrw,xmr,xms,xws,xsize,xuns,xbr,xhalt}=ix;
 wire [31:0] mp,mi,mres,mstore; wire [4:0] md;
 wire mrw,mmr,mms,muns,mfrom,mhalt; wire [1:0] msize;
 assign {mp,mi,md,mres,mstore,mrw,mmr,mms,msize,muns,mfrom,mhalt}=xm;
 wire [31:0] wp,wi,wdata; wire [4:0] wd; wire wrw,whalt;
 assign {wp,wi,wd,wdata,wrw,whalt}=mw;
 wire wb_we=enabled&&wv&&wrw&&(wd!=0);
 tp3_register_file regs(.clk(clk),.reset(rst),.write_enable(wb_we),.rs1(rs1),.rs2(rs2),
 .rd(wd),.debug_addr(debug_reg_addr),.write_data(wdata),.read_data1(r1),.read_data2(r2),.debug_data(debug_reg_data));
 wire [31:0] a=(xr1==0)?0:(mv&&mrw&&!mmr&&md!=0&&md==xr1)?mres:
                          (wv&&wrw&&wd!=0&&wd==xr1)?wdata:xa;
 wire [31:0] b=(xr2==0)?0:(mv&&mrw&&!mmr&&md!=0&&md==xr2)?mres:
                          (wv&&wrw&&wd!=0&&wd==xr2)?wdata:xb;
 wire [31:0] alu_a=(xsa==`TP3_A_PC)?xp:(xsa==`TP3_A_ZERO)?0:a;
 wire [31:0] alu_b=xbi?xim:b;
 wire [31:0] result;
 tp3_alu_adapter alu_exec(.a(alu_a),.b(alu_b),.alu_op(xop),.result(result),.zero());
 wire [31:0] ex_result=(xws==`TP3_WB_PC4)?xp+32'd4:(xws==`TP3_WB_IMM)?xim:result;
 wire taken=(xbr==`TP3_BR_JAL)||(xbr==`TP3_BR_JALR)||
             ((xbr==`TP3_BR_BEQ)&&(a==b))||((xbr==`TP3_BR_BNE)&&(a!=b));
 wire [31:0] target=(xbr==`TP3_BR_JALR)?((a+xim)&32'hfffffffe):(xp+xim);
 wire target_bad=taken&&(target[1:0]!=0);
 assign stall=xv&&xmr&&xd!=0&&fv&&((u1&&rs1==xd)||(u2&&rs2==xd));
 // Validate original byte address including full access extent BEFORE rounding.
 wire [32:0] extent=(msize==0)?33'd1:(msize==1)?33'd2:33'd4;
 wire mem_align=((msize==1)&&mres[0])||((msize==2)&&(mres[1:0]!=0));
 // Equivalent full-extent comparison, with constant thresholds (no 33-bit adder).
 localparam [32:0] DMEM_BYTES=WORDS*33'd4;
 wire mem_range=(msize==0)?({1'b0,mres}>DMEM_BYTES-33'd1):
                (msize==1)?({1'b0,mres}>DMEM_BYTES-33'd2):({1'b0,mres}>DMEM_BYTES-33'd4);
 wire mem_bad=mv&&(mmr||mms)&&(mem_align||mem_range);
 wire ex_bad=xv&&(x_fault||x_illegal||target_bad);
 wire stop_ex=xv&&(xhalt||ex_bad);
 wire [31:0] ram_word;
 wire [31:0] shifted=ram_word >> {mres[1:0],3'b000};
 wire [31:0] load_value=(msize==0)?(muns?{24'b0,shifted[7:0]}:{{24{shifted[7]}},shifted[7:0]}):
 (msize==1)?(muns?{16'b0,shifted[15:0]}:{{16{shifted[15]}},shifted[15:0]}):shifted;
 wire [3:0] mask=((msize==0)?4'b0001:(msize==1)?4'b0011:4'b1111)<<mres[1:0];
 wire store_we=enabled&&mv&&mms&&!mem_bad;
 tp3_dmem #(.DEPTH_WORDS(WORDS)) dmem(.clk(clk),.write_enable(clear_we||store_we),
 .addr(clear_we?clear_addr:{mres[31:2],2'b00}),.write_data(clear_we?32'b0:(mstore<<{mres[1:0],3'b000})),
 .byte_enable(clear_we?4'b1111:mask),.debug_addr(debug_mem_addr),.read_data(ram_word),.debug_data(debug_mem_data),
 .range_error(),.align_error(),.debug_range_error(),.debug_align_error());
 always @(posedge clk) begin
  if(rst) begin
   pc<=entry; cycles<=0; cause<=0; fault_pc<=0; active<=0; draining<=0; terminal<=0;
   fv<=0;xv<=0;mv<=0;wv<=0;fi<=0;ix<=0;xm<=0;mw<=0;f_fault<=0;x_fault<=0;x_illegal<=0;
   used_valid<=0;used_lo<=0;used_hi<=0;
  end else begin
   if(pause_cmd) active<=0;
   else if(run_cmd&&program_valid&&!terminal) active<=1;
   if(enabled) begin
    cycles<=cycles+1;
    // Payload captures independently of flush/stall; only valid controls effects.
    ix<={ip,inst,rs1,rs2,rd,r1,r2,imm,u1,u2,op,sa,bi,rw,mr,ms,ws,size,uns,br,halt};
    wv<=mv&&!mem_bad; mw<={mp,mi,md,mmr?load_value:mres,mrw,mhalt};
    mv<=xv&&!stop_ex&&!mem_bad; xm<={xp,xi,xd,ex_result,b,xrw,xmr,xms,xsize,xuns,xws==`TP3_WB_MEM,xhalt};
    if(mv&&(mmr||mms)&&!mem_bad) begin
     used_valid<=1;
     if(!used_valid||mres<used_lo) used_lo<=mres;
     if(!used_valid||(mres+extent[31:0]-1)>used_hi) used_hi<=mres+extent[31:0]-1;
    end
    if(mem_bad||stop_ex) begin
     draining<=1;fv<=0;xv<=0;f_fault<=0;x_fault<=0;x_illegal<=0;
     cause<=mem_bad?(mem_align?8'd4:8'd5):x_fault?8'd3:x_illegal?8'd2:target_bad?8'd6:8'd1;
     fault_pc<=mem_bad?mp:xp;
    end else if(draining) begin
     fv<=0;xv<=0;
     if(!mv&&!wv) begin terminal<=1;active<=0;draining<=0;end
    end else if(xv&&taken) begin
     pc<=target;fv<=0;xv<=0;f_fault<=0;x_fault<=0;x_illegal<=0;
    end else if(stall) begin xv<=0;x_fault<=0;x_illegal<=0; end
    else begin
     xv<=fv;x_fault<=f_fault;x_illegal<=illegal;
     fv<=1;fi<={pc,(fetch_range||fetch_align||pc>=program_bytes)?32'b0:instruction};pc<=pc+4;
     f_fault<=fetch_range||fetch_align||(pc>=program_bytes);
    end
    // Last cycle: synchronous precise faults and completed drain win.
    // Otherwise cancel in-flight work, preserving this edge's WB and valid MEM store.
    if(cycle_limit!=0 && cycles>=cycle_limit-1 && !mem_bad&&!ex_bad && !(draining&&!mv&&!wv)) begin
     cause<=7;fault_pc<=pc;active<=0;terminal<=1;draining<=0;
     fv<=0;xv<=0;mv<=0;wv<=0;
    end
   end
  end
 end
endmodule
`default_nettype wire
