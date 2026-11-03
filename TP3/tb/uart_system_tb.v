`timescale 1ns/1ps
module uart_system_tb;
 localparam BIT_NS=160, CLK_FREQ=1600000, BAUD=100000;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,serial_rx=1,local_step=0;reg [4:0] local_reg=0;
 wire serial_tx;wire [31:0] local_value,pc;wire [2:0] state;wire [7:0] cause;wire [3:0] pipeline_valid;wire program_valid,busy,running;
 tp3_system #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD)) dut(.clk(clk),
.reset(reset),
.serial_rx(serial_rx),
.local_step(local_step),
.local_reg(local_reg),
.serial_tx(serial_tx),
.local_value(local_value),
.pc(pc),
.state(state),
.cause(cause),
.pipeline_valid(pipeline_valid),
.program_valid(program_valid),
.busy(busy),
.running(running));
 integer output_fd,input_fd,token,scanned,i,frames=0,expected_frames=0;
 reg inside_frame=0;reg [7:0] received;
 reg [4095:0] input_path,output_path;
 task byte_send;input [7:0] data;integer bitno;begin
  serial_rx=0;#BIT_NS;
  for(bitno=0;bitno<8;bitno=bitno+1)begin serial_rx=data[bitno];#BIT_NS;end
  serial_rx=1;#BIT_NS;
 end endtask
 // Independent UART decoder, sampling physical TX, not DUT internal data/strobes.
 initial begin
  wait(!reset);
  forever begin
   @(negedge serial_tx);#(BIT_NS+BIT_NS/2);
   for(i=0;i<8;i=i+1)begin received[i]=serial_tx;#BIT_NS;end
   if(serial_tx!==1)$fatal(1,"TX stop bit invalid");
   $fwrite(output_fd,"%02x\n",received);
   if(received==8'h7e)begin
    if(inside_frame)frames=frames+1;
    inside_frame=!inside_frame;
   end
  end
 end
 initial begin
  if(!$value$plusargs("INPUT=%s",input_path))$fatal(1,"missing INPUT");
  if(!$value$plusargs("OUTPUT=%s",output_path))$fatal(1,"missing OUTPUT");
  input_fd=$fopen(input_path,"r");output_fd=$fopen(output_path,"w");
  if(!input_fd||!output_fd)$fatal(1,"cannot open vectors");
  repeat(10)@(negedge clk);reset=0;
  while(!$feof(input_fd))begin
   scanned=$fscanf(input_fd,"%d",token);
   if(scanned==1)begin
    if(token<256)byte_send(token[7:0]);
    else if(token==256)begin expected_frames=expected_frames+1;wait(frames==expected_frames);#(BIT_NS*3);end
    else if(token==257)begin repeat(CLK_FREQ/4+100)@(negedge clk);end
    else if(token==259)begin
     #(BIT_NS*20);$fclose(output_fd);$fclose(input_fd);
     $display("PASS: uart_system_tb (%0d response frames)",frames);$finish;
    end
   end
  end
  $fatal(1,"missing end marker");
 end
 initial begin #100000000;$fatal(1,"UART timeout, response=%0d expected=%0d",frames,expected_frames);end
endmodule
