module rv32_single_cycle_core #(
    parameter logic [31:0] RESET_VECTOR = 32'h00000000
) (
    input  logic        clk,
    input  logic        reset,

    //==============================================================
    // Instruction-memory interface
    //==============================================================
    output logic [31:0] instr_addr,
    input  logic [31:0] instr_rdata,

    //==============================================================
    // Data-memory interface
    //==============================================================
    output logic [31:0] data_addr,
    output logic        data_read,
    output logic        data_write,
    output logic [31:0] data_wdata,
    output logic [3:0]  data_wstrb,
    input  logic [31:0] data_rdata,

    //==============================================================
    // Status/debug outputs
    //==============================================================
    output logic        illegal_instruction,
    output logic        misaligned_access
);

    import rv32_pkg::*;

    //==============================================================
    // Decoder signals
    //==============================================================
    control_t control;

    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    logic [4:0] rd_addr;

    //==============================================================
    // Program-counter signals
    //==============================================================
    logic [31:0] pc;
    logic [31:0] next_pc;
    logic [31:0] pc_plus_4;

    logic [31:0] branch_target;
    logic [31:0] jal_target;
    logic [31:0] jalr_target;

    //==============================================================
    // Register-file signals
    //==============================================================
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    logic [31:0] rd_write_data;
    logic        regfile_write_enable;

    //==============================================================
    // Immediate-generator signal
    //==============================================================
    logic [31:0] immediate;

    //==============================================================
    // ALU signals
    //==============================================================
    logic [31:0] alu_operand_a;
    logic [31:0] alu_operand_b;
    logic [31:0] alu_result;

    //==============================================================
    // Branch signal
    //==============================================================
    logic branch_taken;

    //==============================================================
    // LSU signals
    //==============================================================
    logic [31:0] load_data;

    logic lsu_mem_read;
    logic lsu_mem_write;

    //==============================================================
    // General execution-valid signal
    //==============================================================
    logic valid_execution;

    assign valid_execution =
        !reset && !illegal_instruction;

    //==============================================================
    // 1. Program counter
    //==============================================================
    rv32_pc #(
        .RESET_VECTOR (RESET_VECTOR)
    ) pc_register (
        .clk     (clk),
        .reset   (reset),
        .enable  (1'b1),
        .next_pc (next_pc),
        .pc      (pc)
    );

    // Current PC is sent to instruction memory
    assign instr_addr = pc;

    //==============================================================
    // 2. Decoder
    //==============================================================
    rv32_decoder decoder (
        .instruction          (instr_rdata),

        .rs1_addr             (rs1_addr),
        .rs2_addr             (rs2_addr),
        .rd_addr              (rd_addr),

        .control              (control),
        .illegal_instruction  (illegal_instruction)
    );

    //==============================================================
    // 3. Immediate generator
    //==============================================================
    rv32_imm_gen immediate_generator (
        .instruction (instr_rdata),
        .imm_type    (control.imm_type),
        .immediate   (immediate)
    );

    //==============================================================
    // 4. Register file
    //==============================================================
    rv32_regfile register_file (
        .clk              (clk),
        .reset            (reset),

        .rs1_addr         (rs1_addr),
        .rs1_data         (rs1_data),

        .rs2_addr         (rs2_addr),
        .rs2_data         (rs2_data),

        .rd_write_enable  (regfile_write_enable),
        .rd_addr          (rd_addr),
        .rd_data          (rd_write_data)
    );

    //==============================================================
    // 5. ALU operand-A selection
    //==============================================================
    always_comb begin
        case (control.operand_a_sel)

            OP_A_RS1: begin
                alu_operand_a = rs1_data;
            end

            OP_A_PC: begin
                alu_operand_a = pc;
            end

            OP_A_ZERO: begin
                alu_operand_a = 32'b0;
            end

            default: begin
                alu_operand_a = 32'b0;
            end

        endcase
    end

    //==============================================================
    // 6. ALU operand-B selection
    //==============================================================
    always_comb begin
        case (control.operand_b_sel)

            OP_B_RS2: begin
                alu_operand_b = rs2_data;
            end

            OP_B_IMM: begin
                alu_operand_b = immediate;
            end

            default: begin
                alu_operand_b = 32'b0;
            end

        endcase
    end

    //==============================================================
    // 7. ALU
    //==============================================================
    rv32_alu alu (
        .operand_a (alu_operand_a),
        .operand_b (alu_operand_b),
        .alu_op    (control.alu_op),
        .result    (alu_result)
    );

    //==============================================================
    // 8. Branch comparator
    //==============================================================
    rv32_branch_cmp branch_comparator (
        .operand_a     (rs1_data),
        .operand_b     (rs2_data),
        .branch_type   (control.branch_type),
        .branch_taken  (branch_taken)
    );

    //==============================================================
    // 9. Next-PC calculations
    //==============================================================
    assign pc_plus_4     = pc + 32'd4;
    assign branch_target = pc + immediate;
    assign jal_target    = pc + immediate;

    /*
     * For JALR, the decoder configures the ALU as:
     *
     * operand A = rs1_data
     * operand B = immediate
     * operation = ADD
     *
     * Therefore alu_result is rs1 + immediate.
     * RISC-V requires bit zero of a JALR target to be cleared.
     */
    assign jalr_target = {
        alu_result[31:1],
        1'b0
    };

    //==============================================================
    // 10. Next-PC selection
    //==============================================================
    always_comb begin
        // Normal sequential instruction
        next_pc = pc_plus_4;

        // Conditional branch
        if (branch_taken) begin
            next_pc = branch_target;
        end

        // Unconditional PC-relative jump
        if (control.is_jal) begin
            next_pc = jal_target;
        end

        // Unconditional register-relative jump
        if (control.is_jalr) begin
            next_pc = jalr_target;
        end
    end

    //==============================================================
    // 11. LSU memory-control gating
    //==============================================================
    assign lsu_mem_read =
        control.mem_read && valid_execution;

    assign lsu_mem_write =
        control.mem_write && valid_execution;

    //==============================================================
    // 12. Load/store unit
    //==============================================================
    rv32_lsu load_store_unit (
        .address              (alu_result),
        .store_data           (rs2_data),
        .memory_read_data     (data_rdata),

        .mem_read             (lsu_mem_read),
        .mem_write            (lsu_mem_write),
        .mem_size             (control.mem_size),
        .load_unsigned        (control.load_unsigned),

        .memory_address       (data_addr),
        .memory_write_data    (data_wdata),
        .memory_write_strobe  (data_wstrb),
        .memory_read_enable   (data_read),
        .memory_write_enable  (data_write),

        .load_data            (load_data),
        .misaligned_access    (misaligned_access)
    );

    //==============================================================
    // 13. Writeback mux
    //==============================================================
    always_comb begin
        case (control.wb_sel)

            WB_ALU: begin
                rd_write_data = alu_result;
            end

            WB_MEMORY: begin
                rd_write_data = load_data;
            end

            WB_PC_PLUS_4: begin
                rd_write_data = pc_plus_4;
            end

            default: begin
                rd_write_data = 32'b0;
            end

        endcase
    end

    //==============================================================
    // 14. Final register-file write enable
    //==============================================================
    assign regfile_write_enable =
        control.reg_write
        && valid_execution
        && !misaligned_access;

endmodule