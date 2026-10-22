`timescale 1ns / 1ps
`default_nettype none
module tp3_imem #(
    parameter integer DEPTH_WORDS = 256
)(
    input wire clk, load_enable,
    input wire [31:0] fetch_addr, load_addr, load_data,
    output reg [31:0] instruction,
    output wire fetch_range_error, fetch_align_error,
    output wire load_range_error, load_align_error
);
    localparam integer INDEX_BITS = (DEPTH_WORDS > 1) ? $clog2(DEPTH_WORDS) : 1;
    localparam [32:0] SIZE_BYTES = 33'd4 * DEPTH_WORDS;
    (* ram_style = "distributed" *) reg [31:0] memory [0:DEPTH_WORDS-1];
    wire [INDEX_BITS-1:0] fetch_index = fetch_addr[INDEX_BITS+1:2];
    wire [INDEX_BITS-1:0] load_index = load_addr[INDEX_BITS+1:2];
    assign fetch_range_error = ({1'b0, fetch_addr} >= SIZE_BYTES);
    assign load_range_error = ({1'b0, load_addr} >= SIZE_BYTES);
    assign fetch_align_error = (fetch_addr[1:0] != 0);
    assign load_align_error = (load_addr[1:0] != 0);
    always @(*) begin
        instruction = 0;
        if (!fetch_range_error && !fetch_align_error) instruction = memory[fetch_index];
    end
    // Sin reset ni inicializacion: programar explicitamente antes de buscar.
    always @(posedge clk) begin
        if (load_enable && !load_range_error && !load_align_error)
            memory[load_index] <= load_data;
    end
endmodule
`default_nettype wire
