`timescale 1ns/1ps
`default_nettype none
// HDLC-like framing, CRC-16/MODBUS; one outstanding request, no implicit retries.
module tp3_packet #(parameter TIMEOUT=25000000, MAX_PAYLOAD=512)(
 input wire clk,reset, input wire [7:0] rx_data, input wire rx_valid,rx_error,
 output reg [7:0] tx_data, output reg tx_start, input wire tx_busy,
 output reg request, input wire accept, output reg [7:0] command,sequence,
 output reg [15:0] length, input wire [9:0] request_index, output wire [7:0] request_data,
 input wire response, input wire [15:0] response_length,
 output wire [9:0] response_index, input wire [7:0] response_data,
 output wire busy, receiving, output reg [31:0] rejected
);
 function [15:0] crc_byte;
 input [15:0] crc; input [7:0] val; integer k; reg [15:0] c;
 begin c=crc^{8'b0,val};for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^16'ha001:c>>1;crc_byte=c;end
 endfunction
 (* ram_style="distributed" *) reg [7:0] buffer[0:MAX_PAYLOAD-1];
 reg [7:0] rx_version,rx_command,rx_sequence;
 reg [15:0] rx_length;
 reg [9:0] count;reg [31:0] timer;reg started,escaped,overflow;
 reg [15:0] rx_crc;
 wire [7:0] decoded=escaped?(rx_data^8'h20):rx_data;
 assign request_data=buffer[request_index];
 // Single-write/single-read payload RAM; header has independent registers.
 always @(posedge clk) begin
  if(!reset&&rx_valid&&!rx_error&&!busy&&started&&rx_data!=8'h7e&&
     !(rx_data==8'h7d&&!escaped)&&count>=5&&count<rx_length+5&&count<MAX_PAYLOAD+5)
    buffer[count-10'd5]<=decoded;
 end
 reg [2:0] send_state;
 reg [9:0] pos;
 reg [15:0] send_len,tx_crc;
 reg escape_tail;
 reg [7:0] escaped_byte;
 assign receiving=started&&(count!=0);
 assign busy=request||(send_state!=0);
 assign response_index=pos>=5?pos-10'd5:10'd0;
 reg [7:0] raw_byte;
 always @* begin
  case(pos)
   0:raw_byte=1;1:raw_byte=command|8'h80;2:raw_byte=sequence;
   3:raw_byte=send_len[7:0];4:raw_byte=send_len[15:8];
   default:raw_byte=(pos<send_len+5)?response_data:(pos==send_len+5)?tx_crc[7:0]:tx_crc[15:8];
  endcase
 end
 always @(posedge clk) begin
  if(reset) begin
   rx_version<=0;rx_command<=0;rx_sequence<=0;rx_length<=0;
   request<=0;command<=0;sequence<=0;length<=0;count<=0;timer<=0;started<=0;escaped<=0;overflow<=0;rx_crc<=16'hffff;
   tx_data<=8'hff;tx_start<=0;send_state<=0;pos<=0;send_len<=0;tx_crc<=16'hffff;escape_tail<=0;escaped_byte<=0;rejected<=0;
  end else begin
   tx_start<=0;
   if(accept)request<=0;
   if(started&&count!=0)begin
    if(timer>=TIMEOUT-1)begin started<=0;count<=0;escaped<=0;rejected<=rejected+1;end
    else timer<=timer+1;
   end
   if(rx_error)begin started<=0;count<=0;escaped<=0;rejected<=rejected+1;end
   else if(rx_valid&&!busy)begin
    timer<=0;
    if(rx_data==8'h7e)begin
     if(started&&count!=0)begin
      if(!overflow&&!escaped&&count>=7&&rx_crc==0&&rx_version==1&&
         rx_length<=MAX_PAYLOAD&&count==rx_length+7)begin
       command<=rx_command;sequence<=rx_sequence;length<=rx_length;request<=1;
      end else rejected<=rejected+1;
     end
     started<=1;count<=0;escaped<=0;overflow<=0;rx_crc<=16'hffff;
    end else if(started)begin
     if(rx_data==8'h7d&&!escaped)escaped<=1;
     else begin
      escaped<=0;
      if(count<MAX_PAYLOAD+7)begin
       case(count)
        0:rx_version<=decoded;1:rx_command<=decoded;2:rx_sequence<=decoded;
        3:rx_length[7:0]<=decoded;4:rx_length[15:8]<=decoded;
        default:begin end
       endcase
       count<=count+1;rx_crc<=crc_byte(rx_crc,decoded);
      end
      else overflow<=1;
     end
    end
   end
   if(response&&send_state==0)begin send_state<=1;send_len<=response_length;pos<=0;tx_crc<=16'hffff;escape_tail<=0;end
   if(!tx_busy&&!tx_start)begin
    case(send_state)
     1:begin tx_data<=8'h7e;tx_start<=1;send_state<=2;end
     2:begin
      tx_start<=1;
      if(escape_tail)begin tx_data<=escaped_byte;escape_tail<=0;pos<=pos+1;if(pos==send_len+6)send_state<=3;end
      else if(raw_byte==8'h7e||raw_byte==8'h7d)begin
       tx_data<=8'h7d;escaped_byte<=raw_byte^8'h20;escape_tail<=1;
       if(pos<send_len+5)tx_crc<=crc_byte(tx_crc,raw_byte);
      end else begin
       tx_data<=raw_byte;pos<=pos+1;
       if(pos<send_len+5)tx_crc<=crc_byte(tx_crc,raw_byte);
       if(pos==send_len+6)send_state<=3;
      end
     end
     3:begin tx_data<=8'h7e;tx_start<=1;send_state<=4;end
     4:send_state<=0;
     default:begin end
    endcase
   end
  end
 end
endmodule
`default_nettype wire
