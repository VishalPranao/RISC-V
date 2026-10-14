module rv32_alu(
    input logic[31:0] operand_a,
    input logic[31:0] operand_b,
    input rv32_pkg::alu_op_e alu_op,
    output logic[31:0] result
);

import rv32_pkg::*;

logic signed [63:0] signed_a, signed_b, unsigned_b;
logic signed [63:0] signed_product, mixed_product;
logic        [63:0] unsigned_product;

always_comb begin

signed_a = {{32{operand_a[31]}}, operand_a};
signed_b = {{32{operand_b[31]}}, operand_b};
unsigned_b = {32'b0, operand_b};
signed_product = signed_a * signed_b;
mixed_product = signed_a * unsigned_b;
unsigned_product = {32'b0, operand_a} * {32'b0, operand_b};

case (alu_op)
            ALU_ADD:    result = operand_a + operand_b;
            ALU_SUB:    result = operand_a - operand_b;
            ALU_SLL:    result = operand_a << operand_b[4:0];
            ALU_SLT:    result = ($signed(operand_a) <
                                  $signed(operand_b));
            ALU_SLTU:   result = (operand_a < operand_b);
            ALU_XOR:    result = operand_a ^ operand_b;
            ALU_SRL:    result = operand_a >> operand_b[4:0];
            ALU_SRA:    result = $signed(operand_a) >>>
                                  operand_b[4:0];
            ALU_OR:     result = operand_a | operand_b;
            ALU_AND:    result = operand_a & operand_b;
            ALU_PASS_A: result = operand_a;
            ALU_PASS_B: result = operand_b;
            ALU_MUL:    result = unsigned_product[31:0];
            ALU_MULH:   result = signed_product[63:32];
            ALU_MULHSU: result = mixed_product[63:32];
            ALU_MULHU:  result = unsigned_product[63:32];
            // DIV/REM results come from rv32_m_divider in the core.
            default:    result = 32'b0;
        endcase
    end

endmodule
