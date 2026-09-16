`timescale 1ns / 1ps
module uart_rx_tb;
    localparam BIT_TIME = 640;
    reg clk = 0, reset = 1, serial_rx = 1;
    wire tick, valid, error;
    wire [7:0] data;
    reg [7:0] expected [0:15];
    integer expected_count = 0, received_count = 0, error_count = 0;
    integer before_valid, before_error;
    reg previous_valid = 0, previous_error = 0;
    always #5 clk = ~clk;
    baud_rate_generator #(.CLK_FREQ(100000000), .BAUD_RATE(1562500)) baud (
        .clk(clk), .reset(reset), .tick_16x(tick)
    );
    uart_rx dut (.clk(clk), .reset(reset), .tick_16x(tick), .serial_rx(serial_rx),
        .rx_data(data), .rx_valid_pulse(valid), .frame_error(error));
    `include "tb_helpers.vh"
    always @(posedge clk) begin
        #1;
        if (reset) begin previous_valid = 0; previous_error = 0; end
        else begin
            check(!(valid && error), "valid and frame error mutually exclusive");
            check(!(valid && previous_valid), "valid pulse one cycle");
            check(!(error && previous_error), "error pulse one cycle");
            if (valid) begin
                check(received_count < expected_count, "no unexpected or duplicated byte");
                check(data === expected[received_count], "received byte equals expected");
                received_count = received_count + 1;
            end
            if (error) error_count = error_count + 1;
            previous_valid = valid; previous_error = error;
        end
    end
    task send_frame;
        input [7:0] value;
        input good_stop;
        integer bit_no;
        begin
            if (good_stop) begin
                expected[expected_count] = value;
                expected_count = expected_count + 1;
            end
            serial_rx = 0; #(BIT_TIME);
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                serial_rx = value[bit_no]; #(BIT_TIME);
            end
            serial_rx = good_stop; #(BIT_TIME);
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        check(data === 0 && valid === 0 && error === 0, "RX reset outputs");
        reset = 0;
        // Non-clock-aligned input, with exactly one stop bit between frames.
        #137;
        send_frame(8'h00, 1); send_frame(8'hFF, 1);
        send_frame(8'h55, 1); send_frame(8'hAA, 1); send_frame(8'h93, 1);
        #(BIT_TIME);
        check(received_count == 5 && error_count == 0, "five consecutive valid bytes");
        before_valid = received_count;
        serial_rx = 0; #(BIT_TIME/4); serial_rx = 1;
        #(BIT_TIME*11);
        check(received_count == before_valid && error_count == 0, "false start rejected without error");
        before_error = error_count;
        send_frame(8'h31, 0);
        // A persistent break must not turn into repeated stale bytes/errors.
        #(BIT_TIME*12);
        check(error_count == before_error + 1, "invalid stop emits exactly one error, including break");
        check(received_count == before_valid, "invalid stop never delivers stale byte");
        serial_rx = 1; #(BIT_TIME*2);
        send_frame(8'hA6, 1);
        #(BIT_TIME);
        check(received_count == expected_count, "valid reception after frame error");
        serial_rx = 0; #(BIT_TIME*3);
        @(negedge clk); reset = 1; serial_rx = 1;
        @(posedge clk); #2;
        check(dut.state === 0 && dut.tick_count === 0 && dut.bit_index === 0, "reset aborts RX and clears counters");
        check(data === 0 && valid === 0 && error === 0, "reset clears RX data and pulses");
        @(negedge clk); reset = 0;
        #(BIT_TIME);
        send_frame(8'h42, 1);
        #(BIT_TIME);
        @(negedge clk); force dut.state = 3'b111;
        #1; check(valid === 0 && error === 0, "invalid RX state suppresses pulses");
        release dut.state;
        @(posedge clk); #2;
        check(dut.state === 3'd0, "invalid RX state recovers on next clock");
        #123; send_frame(8'h7E, 1);
        #(BIT_TIME);
        check(received_count == expected_count, "all expected bytes received once");
        finish_test;
    end
    initial begin #1000000; $fatal(1, "FAIL: RX watchdog"); end
endmodule
