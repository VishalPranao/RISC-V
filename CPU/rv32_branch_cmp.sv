module rv32_branch_cmp (
    input  logic [31:0]               operand_a,
    input  logic [31:0]               operand_b,
    input  rv32_pkg::branch_type_e    branch_type,
    output logic                      branch_taken
);

    import rv32_pkg::*;

    always_comb begin
        // By default, do not take the branch
        branch_taken = 1'b0;

        case (branch_type)

            BR_EQ: begin
                branch_taken = (operand_a == operand_b);
            end

            BR_NE: begin
                branch_taken = (operand_a != operand_b);
            end

            BR_LT: begin
                branch_taken =
                    ($signed(operand_a) < $signed(operand_b));
            end

            BR_GE: begin
                branch_taken =
                    ($signed(operand_a) >= $signed(operand_b));
            end

            BR_LTU: begin
                branch_taken = (operand_a < operand_b);
            end

            BR_GEU: begin
                branch_taken = (operand_a >= operand_b);
            end

            BR_NONE: begin
                branch_taken = 1'b0;
            end

            default: begin
                branch_taken = 1'b0;
            end

        endcase
    end

endmodule