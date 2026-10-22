`timescale 1ns / 1ps
`default_nettype none
module tp3_dmem #(
    parameter integer DEPTH_WORDS = 256
)(
    input wire clk, write_enable,
    input wire [31:0] addr, write_data, debug_addr,
    input wire [3:0] byte_enable,
    output reg [31:0] read_data, debug_data,
    output wire range_error, align_error, debug_range_error, debug_align_error
);
    localparam integer INDEX_BITS = (DEPTH_WORDS > 1) ? $clog2(DEPTH_WORDS) : 1;
    localparam [32:0] SIZE_BYTES = 33'd4 * DEPTH_WORDS;
    (* ram_style = "distributed" *) reg [31:0] memory [0:DEPTH_WORDS-1];
    wire [INDEX_BITS-1:0] index = addr[INDEX_BITS+1:2];
    wire [INDEX_BITS-1:0] debug_index = debug_addr[INDEX_BITS+1:2];
    assign range_error = ({1'b0, addr} >= SIZE_BYTES);
    assign debug_range_error = ({1'b0, debug_addr} >= SIZE_BYTES);
    assign align_error = (addr[1:0] != 0);
    assign debug_align_error = (debug_addr[1:0] != 0);
    always @(*) begin
        read_data = 0; debug_data = 0;
        if (!range_error && !align_error) read_data = memory[index];
        if (!debug_range_error && !debug_align_error) debug_data = memory[debug_index];
    end
    // Little-endian: lane 0 contiene el byte de menor direccion.
    // La interfaz futura SB/SH entrega el dato ya desplazado y la mascara.
    genvar lane;
    generate for (lane = 0; lane < 4; lane = lane + 1) begin: bytes
        always @(posedge clk) begin
            if (write_enable && !range_error && !align_error && byte_enable[lane])
                memory[index][8*lane +: 8] <= write_data[8*lane +: 8];
        end
    end endgenerate
endmodule
`default_nettype wire
