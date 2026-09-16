`timescale 1ns / 1ps
`default_nettype none

module reset_sync (
    input wire clk,
    input wire reset,
    output wire reset_out
);
    // Assert immediately; release after two clock edges. Consumers reset on clk.
    // The external reset must span at least one rising clock edge.
    (* ASYNC_REG = "TRUE" *) reg [1:0] release_pipe;
    always @(posedge clk) begin
        if (reset)
            release_pipe <= 2'b11;
        else
            release_pipe <= {release_pipe[0], 1'b0};
    end
    assign reset_out = reset | release_pipe[1];
endmodule

`default_nettype wire
