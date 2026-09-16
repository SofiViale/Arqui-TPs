`timescale 1ns / 1ps
module interface_tb;
    reg clk = 0, reset = 1;
    reg [7:0] rx_data = 0;
    reg rx_valid = 0, frame_error = 0, tx_busy = 1, tx_done = 0;
    wire [7:0] a, b, result, tx_data;
    wire [5:0] op;
    wire operation_valid, ready, protocol_error, start;
    integer operations = 0, starts = 0, protocol_errors = 0;
    integer before_operations, before_starts;
    reg previous_operation = 0, previous_start = 0, previous_error = 0;
    always #5 clk = ~clk;
    rx_interface_fsm rxif (.clk(clk), .reset(reset), .rx_data(rx_data),
        .rx_valid_pulse(rx_valid), .frame_error(frame_error), .operation_ready(ready),
        .a(a), .b(b), .op(op), .operation_valid_pulse(operation_valid),
        .protocol_error(protocol_error));
    alu #(.N_DATA(8), .N_OP(6)) original_alu (.a(a), .b(b), .op(op), .res(result),
        .zero(), .overflow(), .carry_out());
    tx_interface_fsm txif (.clk(clk), .reset(reset), .operation_valid_pulse(operation_valid),
        .alu_result(result), .tx_busy(tx_busy), .tx_done_pulse(tx_done),
        .tx_data(tx_data), .tx_start_pulse(start), .operation_ready(ready));
    `include "tb_helpers.vh"
    always @(posedge clk) begin
        #1;
        if (reset) begin previous_operation = 0; previous_start = 0; previous_error = 0; end
        else begin
            check(!(operation_valid && previous_operation), "operation_valid one cycle");
            check(!(start && previous_start), "tx_start one cycle");
            check(!(protocol_error && previous_error), "protocol_error one cycle");
            if (operation_valid) operations = operations + 1;
            if (start) starts = starts + 1;
            if (protocol_error) protocol_errors = protocol_errors + 1;
            previous_operation = operation_valid;
            previous_start = start;
            previous_error = protocol_error;
        end
    end
    task put_byte;
        input [7:0] value;
        begin
            @(negedge clk); rx_data = value; rx_valid = 1;
            @(negedge clk); rx_valid = 0;
        end
    endtask
    task operation;
        input [7:0] value_a, value_b, value_op, expected;
        integer old_operations, old_starts;
        reg [7:0] previous_result;
        begin
            old_operations = operations; old_starts = starts;
            previous_result = tx_data;
            tx_busy = 1;
            put_byte(8'hCD); put_byte(value_a); put_byte(value_b); put_byte(value_op);
            check(operation_valid === 1 && tx_data === previous_result, "OP registered before result capture");
            @(negedge clk);
            check(txif.state === 3'd1 && tx_data === previous_result, "one full cycle reserved for ALU settling");
            repeat (3) @(negedge clk);
            check(a === value_a && b === value_b && op === value_op[5:0], "A B OP registered correctly");
            check(result === expected && tx_data === expected, "original ALU result and captured result");
            check(operations == old_operations + 1, "exactly one accepted operation");
            check(start === 0 && ready === 0, "waits for UART ready");
            repeat (7) @(negedge clk);
            check(starts == old_starts, "no arbitrary timeout bypasses busy handshake");
            tx_busy = 0;
            wait (start === 1); #2;
            check(tx_data === expected, "captured byte at start");
            @(negedge clk); tx_busy = 1;
            // A command arriving while occupied must not change the operands.
            put_byte(8'hCD); put_byte(8'h66);
            check(a === value_a && b === value_b, "busy command ignored");
            repeat (5) @(negedge clk);
            check(tx_data === expected && ready === 0 && starts == old_starts + 1,
                  "result stable and exactly one start while waiting for done");
            tx_done = 1;
            @(negedge clk); tx_done = 0; tx_busy = 0;
            repeat (3) @(negedge clk);
            check(ready === 1, "returns idle only after done handshake");
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        check(a === 0 && b === 0 && op === 0 && tx_data === 0, "interface reset registers");
        check(start === 0 && operation_valid === 0 && protocol_error === 0, "interface reset pulses");
        reset = 0;
        put_byte(8'h05); put_byte(8'hD1);
        check(operations == 0, "ignores noise and unsupported D1 command");
        operation(8'h05, 8'h0A, 8'h20, 8'h0F);
        // Expected values from TP1's testbench, including arithmetic boundaries.
        operation(8'h0A, 8'h05, 8'h20, 8'h0F);
        operation(8'h7F, 8'h01, 8'h20, 8'h80);
        operation(8'hFF, 8'h01, 8'h20, 8'h00);
        operation(8'h00, 8'h00, 8'h20, 8'h00);
        operation(8'h0A, 8'h05, 8'h22, 8'h05);
        operation(8'h00, 8'h01, 8'h22, 8'hFF);
        operation(8'h05, 8'h05, 8'h22, 8'h00);
        operation(8'h05, 8'h0A, 8'h22, 8'hFB);
        operation(8'hCC, 8'hAA, 8'h24, 8'h88);
        operation(8'hCC, 8'hAA, 8'h25, 8'hEE);
        operation(8'hCC, 8'hAA, 8'h26, 8'h66);
        operation(8'hCC, 8'h02, 8'h03, 8'hF3);
        operation(8'hCC, 8'h02, 8'h02, 8'h33);
        operation(8'hCC, 8'hAA, 8'h27, 8'h11);
        operation(8'hCD, 8'hCD, 8'h20, 8'h9A);
        operation(8'h80, 8'h08, 8'h03, 8'hFF);
        operation(8'h80, 8'h08, 8'h02, 8'h00);
        operation(8'hCC, 8'h00, 8'h03, 8'hCC);
        operation(8'hCC, 8'hFF, 8'h03, 8'hFF);
        operation(8'hCC, 8'hFF, 8'h02, 8'h00);
        operation(8'h12, 8'h34, 8'h00, 8'h00); // Original ALU default.
        before_operations = operations; before_starts = starts;
        put_byte(8'hCD); put_byte(8'h01); put_byte(8'h02); put_byte(8'hE0);
        repeat (5) @(negedge clk);
        check(protocol_errors == 1 && operations == before_operations && starts == before_starts,
              "nonzero OP high bits rejected without response");
        put_byte(8'hCD); put_byte(8'h12);
        @(negedge clk); frame_error = 1;
        @(negedge clk); frame_error = 0;
        put_byte(8'h34); put_byte(8'h20);
        check(operations == before_operations, "frame error discards partial request");
        operation(8'h05, 8'h0A, 8'h20, 8'h0F);
        put_byte(8'hCD); put_byte(8'h22);
        @(negedge clk); reset = 1;
        @(negedge clk); reset = 0;
        put_byte(8'h33); put_byte(8'h20);
        repeat (3) @(negedge clk);
        check(ready === 1 && a === 0 && b === 0 && op === 0, "reset aborts partial request");
        @(negedge clk); force rxif.state = 3'b111; force txif.state = 3'b111;
        #1; check(operation_valid === 0 && start === 0, "invalid interface states suppress control pulses");
        release rxif.state; release txif.state;
        @(posedge clk); #2;
        check(rxif.state === 0 && txif.state === 0, "both interfaces recover on next clock");
        operation(8'h05, 8'h0A, 8'h20, 8'h0F);
        finish_test;
    end
    initial begin #1000000; $fatal(1, "FAIL: interface watchdog"); end
endmodule
