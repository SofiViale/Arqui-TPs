`timescale 1ns/1ps
// Physical 9600-baud timing, separate from the accelerated end-to-end test.
module uart_baud_tb;
 localparam CLK_FREQ=100000000, BAUD=9600, BIT_NS=1000000000/BAUD;
 reg clk=0;always #(500000000/CLK_FREQ) clk=~clk;
 reg reset=1,serial_rx=1;
 wire serial_tx;
 tp3_system #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD)) dut(.clk(clk),.reset(reset),.serial_rx(serial_rx),
 .local_step(1'b0),.local_reg(5'b0),.serial_tx(serial_tx),.local_value(),.pc(),.state(),.cause(),
 .pipeline_valid(),.program_valid(),.busy(),.running());
 integer i,count=0;reg [7:0] received,decoded,raw[0:127];reg escaped=0,inside_frame=0;
 reg [15:0] crc=16'hffff;
 function [15:0] crc_byte;input [15:0] c;input [7:0] v;integer n;reg [15:0] r;
 begin r=c^v;for(n=0;n<8;n=n+1)r=r[0]?(r>>1)^16'ha001:r>>1;crc_byte=r;end endfunction
 task send;input [7:0] v;integer n;begin
  serial_rx=0;#BIT_NS;for(n=0;n<8;n=n+1)begin serial_rx=v[n];#BIT_NS;end serial_rx=1;#BIT_NS;
 end endtask
 initial begin
  repeat(10)@(negedge clk);reset=0;
  // A bad stop bit/break must recover after the input returns high.
  serial_rx=0;#(BIT_NS*12);serial_rx=1;#(BIT_NS*3);
  send(8'h7e);send(1);send(1);send(0);send(0);send(0);send(8'h18);send(8'h3c);send(8'h7e);
 end
 initial begin
  wait(!reset);
  forever begin
   @(negedge serial_tx);#(BIT_NS+BIT_NS/2);
   for(i=0;i<8;i=i+1)begin received[i]=serial_tx;#BIT_NS;end
   if(serial_tx!==1)$fatal(1,"bad TX stop at 9600 baud");
   if(received==8'h7e)begin
    if(inside_frame)begin
     if(count!=52||crc!=0||raw[0]!=1||raw[1]!=8'h81||raw[2]!=0||raw[3]!=45||raw[4]!=0||raw[5]!=0||
        {raw[9],raw[8],raw[7],raw[6]}!=32'h33545031)$fatal(1,"bad physical baud response");
     if(dut.packet.rejected==0)$fatal(1,"RX framing error not observed");
     $display("PASS: uart_baud_tb (9600 baud, RX break recovery, full STATUS TX CRC)");$finish;
    end
    inside_frame=1;count=0;crc=16'hffff;escaped=0;
   end else if(received==8'h7d&&!escaped)escaped=1;
   else begin
    decoded=escaped?(received^8'h20):received;escaped=0;
    raw[count]=decoded;count=count+1;crc=crc_byte(crc,decoded);
   end
  end
 end
 initial begin #200000000;$fatal(1,"physical baud timeout");end
endmodule
