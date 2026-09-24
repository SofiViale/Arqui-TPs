module alu #(
    parameter N_DATA = 8,
    parameter N_OP = 6
)(
    input wire [N_DATA-1:0] a,
    input wire [N_DATA-1:0] b,
    input wire [N_OP-1:0] op,
    output wire [N_DATA-1:0] res,
    output wire zero,
    output wire overflow,
    output wire carry_out
);

localparam ADD = 6'b100000;
localparam SUB = 6'b100010;
localparam AND = 6'b100100;
localparam OR  = 6'b100101;
localparam XOR = 6'b100110;
localparam SRA = 6'b000011;
localparam SRL = 6'b000010;
localparam NOR = 6'b100111;

reg [N_DATA-1:0] result;
reg zero_reg;
reg overflow_reg;
reg carry_out_reg;

always @(*) begin
    // Valores por defecto para operaciones que no generan estas banderas.
    overflow_reg = 1'b0;
    carry_out_reg = 1'b0;

    case(op)
        ADD: begin
            {carry_out_reg, result} = {1'b0, a} + {1'b0, b};
            overflow_reg = (a[N_DATA-1] == b[N_DATA-1]) && (result[N_DATA-1] != a[N_DATA-1]);
            zero_reg = (result == 0);
        end
        SUB: begin
            {carry_out_reg, result} = {1'b0, a} - {1'b0, b};
            overflow_reg = (a[N_DATA-1] != b[N_DATA-1]) && (result[N_DATA-1] != a[N_DATA-1]);
            zero_reg = (result == 0);
        end
        AND: begin
            result = a & b;
            zero_reg = (result == 0);
        end
        OR:  begin
            result = a | b;
            zero_reg = (result == 0);
        end
        XOR: begin
            result = a ^ b;
            zero_reg = (result == 0);
        end
        SRA: begin
            result = $signed(a) >>> b;
            zero_reg = (result == 0);
        end
        SRL: begin
            result = a >> b;
            zero_reg = (result == 0);
        end
        NOR: begin
            result = ~(a | b);
            zero_reg = (result == 0);
        end
        default: begin
            result = {N_DATA{1'b0}};
            zero_reg = 1'b1;
        end
    endcase
end

assign res = result;
assign zero = zero_reg;
assign overflow = overflow_reg;
assign carry_out = carry_out_reg;

endmodule
