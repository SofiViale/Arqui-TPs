`timescale 1ns/1ps
`default_nettype none
module tp3_system #(parameter CLK_FREQ=100000000,BAUD_RATE=9600,WORDS=256)(
 input wire clk,reset,serial_rx,local_step,input wire [4:0] local_reg,
 output wire serial_tx,output wire [31:0] local_value,pc,
 output wire [2:0] state,output wire [7:0] cause,output wire [3:0] pipeline_valid,
 output wire program_valid,busy,running
);
 wire tick,rxv,rxe,txbusy,txstart;wire [7:0] rxdata,txdata;
 baud_rate_generator #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD_RATE)) baud(.clk(clk),.reset(reset),.tick_16x(tick));
 uart_rx rx(.clk(clk),.reset(reset),.tick_16x(tick),.serial_rx(serial_rx),.rx_data(rxdata),.rx_valid_pulse(rxv),.frame_error(rxe));
 uart_tx tx(.clk(clk),.reset(reset),.tick_16x(tick),.tx_start_pulse(txstart),.tx_data(txdata),.serial_tx(serial_tx),.tx_busy(txbusy),.tx_done_pulse());
 wire request,accept,response,linkbusy,receiving;wire [7:0] command,seq,reqdata,rspdata;
 wire [15:0] length,rsplen;wire [9:0] reqindex,rspindex;
 tp3_packet #(.TIMEOUT(CLK_FREQ/4)) packet(.clk(clk),.reset(reset),.rx_data(rxdata),.rx_valid(rxv),.rx_error(rxe),
 .tx_data(txdata),.tx_start(txstart),.tx_busy(txbusy),.request(request),.accept(accept),.command(command),.sequence(seq),
 .length(length),.request_index(reqindex),.request_data(reqdata),.response(response),.response_length(rsplen),
 .response_index(rspindex),.response_data(rspdata),.busy(linkbusy),.receiving(receiving),.rejected());
 wire restart,run_cmd,pause_cmd,step_cmd,load_we,clear_we,empty,used_valid;
 wire [31:0] entry,bytes,limit,load_addr,load_data,clear_addr,regdata,memaddr,memdata,cycles,fault_pc,lo,hi;
 wire [4:0] regaddr;wire [3:0] exceptions;
 wire [63:0] fi;wire [195:0] ix;wire [140:0] xm;wire [102:0] mw;
 // Local selection is visible while idle; debug owns the register port while busy.
 wire [4:0] reg_select=busy?regaddr:local_reg;
 assign local_value=regdata;
 tp3_debug #(.WORDS(WORDS)) debug_unit(.clk(clk),.reset(reset),.local_step(local_step),.link_busy(linkbusy||receiving||rxv),
 .request(request),.command(command),.length(length),.accept(accept),.request_index(reqindex),.request_data(reqdata),
 .response(response),.response_length(rsplen),.response_index(rspindex),.response_data(rspdata),
 .restart(restart),.run_cmd(run_cmd),.pause_cmd(pause_cmd),.step_cmd(step_cmd),.program_valid(program_valid),
 .load_we(load_we),.clear_we(clear_we),.entry(entry),.program_bytes(bytes),.cycle_limit(limit),.load_addr(load_addr),.load_data(load_data),.clear_addr(clear_addr),
 .debug_reg_addr(regaddr),.debug_reg_data(regdata),.debug_mem_addr(memaddr),.debug_mem_data(memdata),.pc(pc),.cycles(cycles),
 .fault_pc(fault_pc),.used_lo(lo),.used_hi(hi),.used_valid(used_valid),.running(running),.pipeline_empty(empty),.core_state(state),
 .cause(cause),.pipeline_valid(pipeline_valid),.exceptions(exceptions),.fi(fi),.ix(ix),.xm(xm),.mw(mw),.busy(busy));
 tp3_processor #(.WORDS(WORDS)) cpu(.clk(clk),.reset(reset),.restart(restart),.run_cmd(run_cmd),.pause_cmd(pause_cmd),.step_cmd(step_cmd),
 .entry(entry),.program_bytes(bytes),.cycle_limit(limit),.program_valid(program_valid),.load_we(load_we),.load_addr(load_addr),.load_data(load_data),
 .clear_we(clear_we),.clear_addr(clear_addr),.debug_reg_addr(reg_select),.debug_mem_addr(memaddr),.debug_reg_data(regdata),.debug_mem_data(memdata),
 .pc(pc),.cycles(cycles),.fault_pc(fault_pc),.used_lo(lo),.used_hi(hi),.used_valid(used_valid),.state(state),.cause(cause),.running(running),
 .pipeline_empty(empty),.enabled(),.stall(),.pipeline_valid(pipeline_valid),.fi(fi),.ix(ix),.xm(xm),.mw(mw),.exceptions(exceptions));
endmodule
`default_nettype wire
