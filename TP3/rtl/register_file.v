`timescale 1ns / 1ps
`default_nettype none

module tp3_register_file (
    input wire clk, reset, write_enable,
    input wire [4:0] rs1, rs2, rd, debug_addr,
    input wire [31:0] write_data,
    output wire [31:0] read_data1, read_data2, debug_data
);
    reg [31:0] registers [0:31];
    integer i;
    wire writing = write_enable && !reset && (rd != 0);
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) registers[i] <= 0;
        end else if (writing) registers[rd] <= write_data;
    end
    // WB/ID: solo los operandos ven una escritura aun no almacenada.
    assign read_data1 = (rs1 == 0) ? 32'b0 :
                       ((writing && rd == rs1) ? write_data : registers[rs1]);
    assign read_data2 = (rs2 == 0) ? 32'b0 :
                       ((writing && rd == rs2) ? write_data : registers[rs2]);
    assign debug_data = (debug_addr == 0) ? 32'b0 : registers[debug_addr];
endmodule
`default_nettype wire
