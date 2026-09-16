// Included only by testbenches, never by synthesizable modules.
integer checks = 0;
integer failures = 0;
task check;
    input condition;
    input [8*120-1:0] description;
    begin
        checks = checks + 1;
        if (condition !== 1'b1) begin
            failures = failures + 1;
            $display("FAIL: %0s (time=%0t)", description, $time);
        end
    end
endtask
task finish_test;
    begin
        if (failures != 0) begin
            $display("FAIL: %0d checks, %0d failures", checks, failures);
            $fatal(1, "Testbench failed");
        end
        $display("PASS: %0d checks, 0 failures", checks);
        $finish;
    end
endtask
