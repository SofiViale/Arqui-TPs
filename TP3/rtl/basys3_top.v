`timescale 1ns/1ps
`default_nettype none
module tp3_basys3_top #(parameter DEBOUNCE_CYCLES=1000000)(
 input wire clk,btnC,btnU,serial_rx,input wire [6:0] sw,
 output wire serial_tx,output wire [15:0] led,output reg [6:0] seg,
 output wire [3:0] an,output wire dp
);
 reg [7:0] power_on=8'hff;
 (* ASYNC_REG="TRUE" *) reg [1:0] reset_button=0,step_button=0;
 (* ASYNC_REG="TRUE" *) reg [6:0] sw_meta=0,sw_sync=0;
 always @(posedge clk)begin
  power_on<={power_on[6:0],1'b0};reset_button<={reset_button[0],btnC};step_button<={step_button[0],btnU};
  sw_meta<=sw;sw_sync<=sw_meta;
 end
 wire reset;
 reset_sync reset_conditioner(.clk(clk),.reset(power_on[7]||reset_button[1]),.reset_out(reset));
 reg [19:0] debounce_count;reg stable_button,step_pulse;
 always @(posedge clk)begin
  if(reset)begin debounce_count<=0;stable_button<=0;step_pulse<=0;end
  else begin
   step_pulse<=0;
   if(step_button[1]==stable_button)debounce_count<=0;
   else if(debounce_count==DEBOUNCE_CYCLES-1)begin
    stable_button<=step_button[1];step_pulse<=step_button[1];debounce_count<=0;
   end else debounce_count<=debounce_count+1;
  end
 end
 wire [31:0] value,pc;wire [2:0] state;wire [7:0] cause;wire [3:0] valid;wire program_valid,busy,running;
 tp3_system system(.clk(clk),.reset(reset),.serial_rx(serial_rx),.local_step(step_pulse),.local_reg(sw_sync[4:0]),
 .serial_tx(serial_tx),.local_value(value),.pc(pc),.state(state),.cause(cause),.pipeline_valid(valid),
 .program_valid(program_valid),.busy(busy),.running(running));
 assign led={cause[5:0],busy,running,program_valid,state,valid};
 wire [31:0] selected=sw_sync[5]?pc:value;
 wire [15:0] halfword=sw_sync[6]?selected[31:16]:selected[15:0];
 reg [17:0] scan;
 always @(posedge clk)if(reset)scan<=0;else scan<=scan+1;
 wire [1:0] digit=scan[17:16];wire [3:0] nibble=halfword>>(digit*4);
 assign an=~(4'b0001<<digit);assign dp=1'b1;
 always @* case(nibble)
  0:seg=7'b1000000;1:seg=7'b1111001;2:seg=7'b0100100;3:seg=7'b0110000;
  4:seg=7'b0011001;5:seg=7'b0010010;6:seg=7'b0000010;7:seg=7'b1111000;
  8:seg=7'b0000000;9:seg=7'b0010000;10:seg=7'b0001000;11:seg=7'b0000011;
  12:seg=7'b1000110;13:seg=7'b0100001;14:seg=7'b0000110;15:seg=7'b0001110;
 endcase
endmodule
`default_nettype wire
