`timescale 1ns / 1ps
module uart_tx_tb;
    reg clk = 0, reset = 1, start = 0;
    reg [7:0] data = 0;
    wire tick, serial_tx, busy, done;
    integer done_count = 0;
    reg previous_done = 0;
    always #5 clk = ~clk;
    baud_rate_generator #(.CLK_FREQ(100000000), .BAUD_RATE(1562500)) baud (
        .clk(clk), .reset(reset), .tick_16x(tick)
    ); // 4 clocks/tick; 64 clocks/bit
    uart_tx dut (.clk(clk), .reset(reset), .tick_16x(tick),
        .tx_start_pulse(start), .tx_data(data), .serial_tx(serial_tx),
        .tx_busy(busy), .tx_done_pulse(done));
    `include "tb_helpers.vh"
    always @(posedge clk) begin
        #1;
        if (reset) previous_done = 0;
        else begin
            check(!(previous_done && done), "done lasts one cycle");
            if (done) done_count = done_count + 1;
            previous_done = done;
        end
    end
    task send_and_check;
        input [7:0] value;
        input inject_busy;
        integer bit_no, cycle_no, old_done;
        reg expected_bit;
        begin
            old_done = done_count;
            check(serial_tx === 1 && busy === 0, "idle high and available");
            @(negedge clk); data = value; start = 1;
            @(negedge clk); start = 0; data = ~value;
            check(busy === 1, "busy immediately after accepting request");
            @(negedge serial_tx); #2;
            // Check every clock of all ten bits, not just their center.
            for (bit_no = 0; bit_no < 10; bit_no = bit_no + 1) begin
                if (bit_no == 0) expected_bit = 0;
                else if (bit_no == 9) expected_bit = 1;
                else expected_bit = value[bit_no-1];
                for (cycle_no = 0; cycle_no < 64; cycle_no = cycle_no + 1) begin
                    check(serial_tx === expected_bit, "bit value / LSB order / full 16-tick duration");
                    check(busy === 1 && done === 0, "busy throughout frame, no early done");
                    if (inject_busy && bit_no == 3 && cycle_no == 10) start = 1;
                    if (inject_busy && bit_no == 3 && cycle_no == 11) start = 0;
                    @(posedge clk); #2;
                end
            end
            check(done === 1 && serial_tx === 1, "done follows full stop bit");
            @(posedge clk); #2;
            check(done === 0 && busy === 0, "done clears and returns idle");
            repeat (10) @(negedge clk);
            check(done_count == old_done + 1, "exactly one completed transmission");
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        check(serial_tx === 1 && busy === 0 && done === 0, "reset outputs");
        reset = 0;
        send_and_check(8'h00, 0);
        send_and_check(8'hFF, 0);
        send_and_check(8'h55, 0);
        send_and_check(8'hAA, 0);
        send_and_check(8'h93, 1);
        @(negedge clk); data = 8'h55; start = 1;
        @(negedge clk); start = 0;
        @(negedge serial_tx);
        repeat (80) @(negedge clk);
        reset = 1;
        @(posedge clk); #2;
        check(serial_tx === 1 && busy === 0 && done === 0, "reset aborts transmission");
        check(dut.tick_count === 0 && dut.bit_index === 0 && dut.data_reg === 0, "reset clears TX registers");
        @(negedge clk); reset = 0;
        send_and_check(8'h93, 0);
        @(negedge clk); force dut.state = 3'b111;
        #1; check(serial_tx === 1 && busy === 0 && done === 0, "invalid TX state safe outputs");
        release dut.state;
        @(posedge clk); #2;
        check(dut.state === 3'd0, "invalid TX state recovers on next clock");
        send_and_check(8'h55, 0);
        finish_test;
    end
    initial begin #1000000; $fatal(1, "FAIL: TX watchdog"); end
endmodule
