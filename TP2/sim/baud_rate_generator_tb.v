`timescale 1ns / 1ps
module baud_rate_generator_tb;
    reg clk = 0, reset = 1;
    wire tick, nominal_tick, every_cycle;
    integer i, since_tick, ticks;
    reg previous_tick;
    always #5 clk = ~clk;
    baud_rate_generator #(.CLK_FREQ(100000000), .BAUD_RATE(1562500)) dut (
        .clk(clk), .reset(reset), .tick_16x(tick)
    ); // DIVISOR = 4
    baud_rate_generator nominal (.clk(clk), .reset(reset), .tick_16x(nominal_tick));
    baud_rate_generator #(.CLK_FREQ(100000000), .BAUD_RATE(6250000)) minimum (
        .clk(clk), .reset(reset), .tick_16x(every_cycle)
    );
    `include "tb_helpers.vh"
    initial begin
        repeat (3) @(negedge clk);
        check(tick === 0 && nominal_tick === 0 && every_cycle === 0, "reset clears ticks");
        check(dut.counter === 0 && nominal.counter === 0, "reset clears counters");
        reset = 0;
        since_tick = 0; ticks = 0; previous_tick = 0;
        for (i = 1; i <= 1302; i = i + 1) begin
            @(posedge clk); #1;
            since_tick = since_tick + 1;
            check(tick === ((i % 4) == 0), "reduced divisor interval");
            check(nominal_tick === ((i % 651) == 0), "100 MHz / 9600: divisor 651");
            check(every_cycle === 1'b1, "divisor 1 enables every clock");
            check(!(tick && previous_tick), "isolated one-cycle tick when divisor > 1");
            if (tick) begin
                check(since_tick == 4, "four cycles between ticks");
                since_tick = 0; ticks = ticks + 1;
            end
            previous_tick = tick;
        end
        check(ticks == 325, "tick count");
        @(negedge clk); reset = 1;
        @(posedge clk); #1;
        check(dut.counter === 0 && tick === 0, "reset in middle of counting");
        @(negedge clk); reset = 0;
        for (i = 1; i <= 4; i = i + 1) begin
            @(posedge clk); #1;
            check(tick === (i == 4), "full interval after reset");
        end
        finish_test;
    end
    initial begin #100000; $fatal(1, "FAIL: baud watchdog"); end
endmodule
