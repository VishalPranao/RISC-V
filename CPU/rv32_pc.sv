module rv32_pc #(
    parameter logic [31:0] RESET_VECTOR = 32'h00000000
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        enable,

    input  logic [31:0] next_pc,

    output logic [31:0] pc
);

    always_ff @(posedge clk) begin
        if (reset) begin
            pc <= RESET_VECTOR;
        end
        else if (enable) begin
            pc <= next_pc;
        end
    end

endmodule