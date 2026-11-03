`timescale 1ns/1ps
module board_tb;
 reg clk=0;always #5 clk=~clk;
 reg btnC=0,btnU=0,serial_rx=1;reg [6:0] sw=0;
 wire serial_tx,dp;wire [15:0] led;wire [6:0] seg;wire [3:0] an;
 tp3_basys3_top #(.DEBOUNCE_CYCLES(8)) dut(.clk(clk),
.btnC(btnC),
.btnU(btnU),
.serial_rx(serial_rx),
.sw(sw),
.serial_tx(serial_tx),
.led(led),
.seg(seg),
.an(an),
.dp(dp));
 integer pulses=0;
 always @(posedge clk)if(dut.step_pulse)pulses=pulses+1;
 initial begin
  repeat(30)@(negedge clk);
  btnU=1;repeat(3)@(negedge clk);btnU=0;repeat(3)@(negedge clk);btnU=1;
  repeat(100)@(negedge clk);
  if(pulses!=1)$fatal(1,"held/bouncing button created %d steps",pulses);
  btnU=0;repeat(20)@(negedge clk);btnU=1;repeat(20)@(negedge clk);
  if(pulses!=2)$fatal(1,"second press missing");
  btnC=1;repeat(20)@(negedge clk);btnC=0;repeat(20)@(negedge clk);
  if(led[7]!==0||led[3:0]!==0||serial_tx!==1||dp!==1)$fatal(1,"board reset/idle outputs");
  $display("PASS: board_tb (debounce, sustained press, reset and outputs)");$finish;
 end
 initial begin #100000;$fatal(1,"board timeout");end
endmodule
