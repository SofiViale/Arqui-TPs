`timescale 1ns / 1ps
module tp2_top_tb;
    parameter integer CLK_FREQ = 100000000;
    parameter integer BAUD_RATE = 1562500;
    localparam real CLOCK_TIME = 1000000000.0 / CLK_FREQ;
    // Independent serial peer uses the requested baud, not the DUT divider.
    localparam real BIT_TIME = 1000000000.0 / BAUD_RATE;
    reg clk = 0, reset = 1, serial_rx = 1;
    wire serial_tx, frame_error, protocol_error;
    integer responses = 0, frame_errors = 0, protocol_errors = 0;
    reg allow_response = 0;
    always #(CLOCK_TIME/2.0) clk = ~clk;
    tp2_top #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) dut (
        .clk(clk), .reset(reset), .serial_rx(serial_rx), .serial_tx(serial_tx),
        .frame_error(frame_error), .protocol_error(protocol_error));
    `include "tb_helpers.vh"
    always @(posedge clk) begin
        #1;
        if (!reset) begin
            if (frame_error) frame_errors = frame_errors + 1;
            if (protocol_error) protocol_errors = protocol_errors + 1;
        end
    end
    always @(negedge serial_tx) begin
        if (!reset) check(allow_response, "no unsolicited serial transmission");
    end
    task send_byte;
        input [7:0] value;
        input good_stop;
        integer bit_no;
        begin
            serial_rx = 0; #(BIT_TIME);
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                serial_rx = value[bit_no]; #(BIT_TIME);
            end
            serial_rx = good_stop; #(BIT_TIME);
        end
    endtask
    task receive_response;
        input [7:0] expected;
        reg [7:0] decoded;
        integer bit_no;
        begin
            @(negedge serial_tx);
            #(BIT_TIME/2.0);
            check(serial_tx === 0, "response start center low");
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                #(BIT_TIME); decoded[bit_no] = serial_tx;
            end
            #(BIT_TIME);
            check(serial_tx === 1, "response stop center high");
            check(decoded === expected, "end-to-end decoded ALU result");
            if (decoded !== expected) $display("Expected %02h, received %02h", expected, decoded);
            responses = responses + 1;
            #(BIT_TIME/2.0);
        end
    endtask
    task transact;
        input [7:0] value_a, value_b, value_op, expected;
        begin
            allow_response = 1;
            // Listening starts before OP ends: the DUT may reply during its stop.
            fork
                begin
                    send_byte(8'hCD, 1); send_byte(value_a, 1);
                    send_byte(value_b, 1); send_byte(value_op, 1);
                end
                receive_response(expected);
            join
            #(BIT_TIME);
            allow_response = 0;
            check(dut.tx_interface_inst.operation_ready === 1, "ready after response");
        end
    endtask
    task quiet_interval;
        begin
            serial_rx = 1;
            #(BIT_TIME*12);
            check(serial_tx === 1 && dut.tx_busy === 0, "no response to incomplete or invalid request");
        end
    endtask
    initial begin
        repeat (4) @(negedge clk);
        check(serial_tx === 1 && frame_error === 0 && protocol_error === 0, "top reset outputs");
        reset = 0;
        @(posedge clk); #1;
        check(dut.reset_internal === 1, "reset release held for synchronization");
        @(posedge clk); #1;
        check(dut.reset_internal === 0, "reset releases after two clock edges");
        #(BIT_TIME*2 + CLOCK_TIME*0.37);
        transact(8'h05, 8'h0A, 8'h20, 8'h0F);
        transact(8'h7F, 8'h01, 8'h20, 8'h80);
        transact(8'hFF, 8'h01, 8'h20, 8'h00);
        transact(8'h05, 8'h0A, 8'h22, 8'hFB);
        transact(8'hCC, 8'hAA, 8'h24, 8'h88);
        transact(8'hCC, 8'hAA, 8'h25, 8'hEE);
        transact(8'hCC, 8'hAA, 8'h26, 8'h66);
        transact(8'hCC, 8'h02, 8'h03, 8'hF3);
        transact(8'hCC, 8'h02, 8'h02, 8'h33);
        transact(8'hCC, 8'hAA, 8'h27, 8'h11);
        transact(8'hCD, 8'hCD, 8'h20, 8'h9A);
        transact(8'h80, 8'hFF, 8'h03, 8'hFF);
        transact(8'h80, 8'hFF, 8'h02, 8'h00);
        transact(8'h12, 8'h34, 8'h00, 8'h00);
        send_byte(8'hD1, 1); quiet_interval;
        send_byte(8'hCD, 1); send_byte(8'h01, 1); send_byte(8'h02, 1); send_byte(8'hE0, 1);
        quiet_interval;
        check(protocol_errors == 1, "invalid opcode high bits diagnosed");
        send_byte(8'hCD, 1); send_byte(8'h55, 0);
        quiet_interval;
        check(frame_errors == 1, "framing error aborts partial protocol");
        transact(8'h05, 8'h0A, 8'h20, 8'h0F);
        send_byte(8'hCD, 1); send_byte(8'h44, 1);
        @(negedge clk); reset = 1;
        repeat (4) @(negedge clk);
        check(dut.a === 0 && dut.b === 0 && dut.op === 0 && serial_tx === 1, "top reset clears partial request");
        reset = 0;
        #(BIT_TIME*2);
        send_byte(8'h12, 1); send_byte(8'h20, 1); quiet_interval;
        transact(8'h05, 8'h0A, 8'h20, 8'h0F);
        check(responses == 16, "sixteen independently decoded responses");
        check(frame_errors == 1 && protocol_errors == 1, "only injected errors occurred");
        $display("Configuration: CLK_FREQ=%0d BAUD_RATE=%0d", CLK_FREQ, BAUD_RATE);
        finish_test;
    end
    initial begin #(BIT_TIME*4000); $fatal(1, "FAIL: top watchdog / missing response"); end
endmodule
