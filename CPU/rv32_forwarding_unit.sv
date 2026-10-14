module rv32_forwarding_unit (
    input logic        id_ex_uses_rs1,
    input logic        id_ex_uses_rs2,
    input logic [4:0]  id_ex_rs1,
    input logic [4:0]  id_ex_rs2,

    input logic        ex_mem_valid,
    input logic        ex_mem_reg_write,
    input logic        ex_mem_mem_read,
    input logic [4:0]  ex_mem_rd,

    input logic        mem_wb_valid,
    input logic        mem_wb_reg_write,
    input logic [4:0]  mem_wb_rd,

    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    localparam logic [1:0] FORWARD_NONE   = 2'b00;
    localparam logic [1:0] FORWARD_MEM_WB = 2'b01;
    localparam logic [1:0] FORWARD_EX_MEM = 2'b10;

    always_comb begin
        forward_a = FORWARD_NONE;
        forward_b = FORWARD_NONE;

        /*
         * EX/MEM has priority because it contains the newer instruction.
         *
         * Do not forward an EX/MEM load. Its alu_result is the memory
         * address, not the loaded data.
         */
        if (
            id_ex_uses_rs1 &&
            ex_mem_valid &&
            ex_mem_reg_write &&
            !ex_mem_mem_read &&
            (ex_mem_rd != 5'd0) &&
            (ex_mem_rd == id_ex_rs1)
        ) begin
            forward_a = FORWARD_EX_MEM;
        end
        else if (
            id_ex_uses_rs1 &&
            mem_wb_valid &&
            mem_wb_reg_write &&
            (mem_wb_rd != 5'd0) &&
            (mem_wb_rd == id_ex_rs1)
        ) begin
            forward_a = FORWARD_MEM_WB;
        end

        if (
            id_ex_uses_rs2 &&
            ex_mem_valid &&
            ex_mem_reg_write &&
            !ex_mem_mem_read &&
            (ex_mem_rd != 5'd0) &&
            (ex_mem_rd == id_ex_rs2)
        ) begin
            forward_b = FORWARD_EX_MEM;
        end
        else if (
            id_ex_uses_rs2 &&
            mem_wb_valid &&
            mem_wb_reg_write &&
            (mem_wb_rd != 5'd0) &&
            (mem_wb_rd == id_ex_rs2)
        ) begin
            forward_b = FORWARD_MEM_WB;
        end
    end

endmodule