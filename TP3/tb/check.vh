// Solo testbench. Icarus acepta $fatal tambien en modo Verilog-2005.
integer checks = 0;
task check;
    input condition;
    input [8*120-1:0] description;
    begin
        checks = checks + 1;
        if (condition !== 1'b1) begin
            $display("FAIL: %0s (check %0d, t=%0t)", description, checks, $time);
            $fatal(1);
        end
    end
endtask
initial begin #1000000; $fatal(1, "FAIL: watchdog"); end
