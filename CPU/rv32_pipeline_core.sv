module rv32_pipeline_core (
    input  logic        clk,
    input  logic        reset,

    output logic [31:0] instr_addr,
    input  logic [31:0] instr_rdata,

    output logic [31:0] data_addr,
    output logic [31:0] data_wdata,
    output logic [3:0]  data_wstrb,
    output logic        data_write,
    input  logic [31:0] data_rdata
);

    import rv32_pkg::*;

    /*
     * ================================================================
     * Pipeline-register definitions
     * ================================================================
     */

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instruction;
    } if_id_pipe_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] pc_plus_4;

        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic [31:0] immediate;

        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [4:0]  rd;

        control_t    control;
    } id_ex_pipe_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] alu_result;
        logic [31:0] store_data;
        logic [31:0] pc_plus_4;
        logic [4:0]  rd;
        control_t    control;
    } ex_mem_pipe_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] alu_result;
        logic [31:0] load_data;
        logic [31:0] pc_plus_4;
        logic [4:0]  rd;
        control_t    control;
    } mem_wb_pipe_t;

    if_id_pipe_t  if_id_q;
    id_ex_pipe_t  id_ex_q;
    ex_mem_pipe_t ex_mem_q;
    mem_wb_pipe_t mem_wb_q;

    /*
     * ================================================================
     * IF stage
     * ================================================================
     */

    logic [31:0] fetch_pc;
    logic [31:0] next_pc;

    logic pc_stall;
    logic if_id_stall;
    logic if_id_flush;
    logic id_ex_flush;

    assign instr_addr = fetch_pc;

    /*
     * ================================================================
     * ID stage
     * ================================================================
     */

    logic [4:0] id_rs1;
    logic [4:0] id_rs2;
    logic [4:0] id_rd;

    logic [31:0] id_rs1_data;
    logic [31:0] id_rs2_data;
    logic [31:0] id_immediate;

    control_t id_control;
    logic     id_illegal_instruction;

    rv32_decoder decoder (
    .instruction         (if_id_q.instruction),
    .rs1_addr            (id_rs1),
    .rs2_addr            (id_rs2),
    .rd_addr             (id_rd),
    .control             (id_control),
    .illegal_instruction (id_illegal_instruction)
);

    rv32_imm_gen immediate_generator (
        .instruction(if_id_q.instruction),
        .imm_type   (id_control.imm_type),
        .immediate  (id_immediate)
    );

    /*
     * ================================================================
     * WB stage
     * ================================================================
     *
     * This appears before the register-file instance because the
     * register file's write port uses these signals.
     */

    logic [31:0] wb_data;
    logic        wb_write_enable;

    always_comb begin
        case (mem_wb_q.control.wb_sel)
            WB_ALU:
                wb_data = mem_wb_q.alu_result;

            WB_MEMORY:
                wb_data = mem_wb_q.load_data;

            WB_PC_PLUS_4:
                wb_data = mem_wb_q.pc_plus_4;

            default:
                wb_data = 32'b0;
        endcase
    end

    assign wb_write_enable =
        mem_wb_q.valid &&
        mem_wb_q.control.reg_write;

    rv32_regfile register_file (
        .clk            (clk),
        .reset          (reset),

        .rs1_addr       (id_rs1),
        .rs1_data       (id_rs1_data),

        .rs2_addr       (id_rs2),
        .rs2_data       (id_rs2_data),

        .rd_write_enable(wb_write_enable),
        .rd_addr        (mem_wb_q.rd),
        .rd_data        (wb_data)
    );

    /*
     * ================================================================
     * Forwarding logic
     * ================================================================
     */

    logic [1:0] forward_a;
    logic [1:0] forward_b;

    logic [31:0] ex_mem_forward_data;
    logic [31:0] ex_rs1_forwarded;
    logic [31:0] ex_rs2_forwarded;

    /*
     * Most EX/MEM instructions forward their ALU result.
     * JAL/JALR must forward PC+4 because that is written into rd.
     */
    always_comb begin
        case (ex_mem_q.control.wb_sel)
            WB_PC_PLUS_4:
                ex_mem_forward_data = ex_mem_q.pc_plus_4;

            default:
                ex_mem_forward_data = ex_mem_q.alu_result;
        endcase
    end

    rv32_forwarding_unit forwarding_unit (
        .id_ex_uses_rs1  (id_ex_q.control.uses_rs1),
        .id_ex_uses_rs2  (id_ex_q.control.uses_rs2),
        .id_ex_rs1       (id_ex_q.rs1),
        .id_ex_rs2       (id_ex_q.rs2),

        .ex_mem_valid    (ex_mem_q.valid),
        .ex_mem_reg_write(ex_mem_q.control.reg_write),
        .ex_mem_mem_read (ex_mem_q.control.mem_read),
        .ex_mem_rd       (ex_mem_q.rd),

        .mem_wb_valid    (mem_wb_q.valid),
        .mem_wb_reg_write(mem_wb_q.control.reg_write),
        .mem_wb_rd       (mem_wb_q.rd),

        .forward_a       (forward_a),
        .forward_b       (forward_b)
    );

    always_comb begin
        case (forward_a)
            2'b10:   ex_rs1_forwarded = ex_mem_forward_data;
            2'b01:   ex_rs1_forwarded = wb_data;
            default: ex_rs1_forwarded = id_ex_q.rs1_data;
        endcase

        case (forward_b)
            2'b10:   ex_rs2_forwarded = ex_mem_forward_data;
            2'b01:   ex_rs2_forwarded = wb_data;
            default: ex_rs2_forwarded = id_ex_q.rs2_data;
        endcase
    end

    /*
     * ================================================================
     * EX stage
     * ================================================================
     */

    logic [31:0] ex_operand_a;
    logic [31:0] ex_operand_b;
    logic [31:0] ex_alu_result;

    logic        ex_branch_taken;
    logic        ex_redirect;
    logic [31:0] ex_redirect_target;

    always_comb begin
        case (id_ex_q.control.operand_a_sel)
            OP_A_RS1:
                ex_operand_a = ex_rs1_forwarded;

            OP_A_PC:
                ex_operand_a = id_ex_q.pc;

            OP_A_ZERO:
                ex_operand_a = 32'b0;

            default:
                ex_operand_a = 32'b0;
        endcase

        case (id_ex_q.control.operand_b_sel)
            OP_B_RS2:
                ex_operand_b = ex_rs2_forwarded;

            OP_B_IMM:
                ex_operand_b = id_ex_q.immediate;

            default:
                ex_operand_b = 32'b0;
        endcase
    end

    rv32_alu alu (
        .operand_a(ex_operand_a),
        .operand_b(ex_operand_b),
        .alu_op   (id_ex_q.control.alu_op),
        .result   (ex_alu_result)
    );

    /*
     * Branch comparison uses the actual rs1 and rs2 values.
     * It does not use the general ALU operand-selection results.
     */
    rv32_branch_cmp branch_comparator (
        .operand_a   (ex_rs1_forwarded),
        .operand_b   (ex_rs2_forwarded),
        .branch_type (id_ex_q.control.branch_type),
        .branch_taken(ex_branch_taken)
    );

    always_comb begin
        /*
         * Branch and JAL:
         *     target = instruction PC + immediate
         *
         * JALR:
         *     target = rs1 + immediate, with bit zero cleared
         */
        if (id_ex_q.control.is_jalr) begin
            ex_redirect_target =
                (ex_rs1_forwarded + id_ex_q.immediate)
                & 32'hFFFF_FFFE;
        end
        else begin
            ex_redirect_target =
                id_ex_q.pc + id_ex_q.immediate;
        end

        ex_redirect =
            id_ex_q.valid &&
            (
                id_ex_q.control.is_jal ||
                id_ex_q.control.is_jalr ||
                ex_branch_taken
            );
    end

    /*
     * ================================================================
     * Hazard detection
     * ================================================================
     */

    rv32_hazard_unit hazard_unit (
        .if_id_valid  (if_id_q.valid),
        .id_uses_rs1  (id_control.uses_rs1),
        .id_uses_rs2  (id_control.uses_rs2),
        .id_rs1       (id_rs1),
        .id_rs2       (id_rs2),

        .id_ex_valid  (id_ex_q.valid),
        .id_ex_mem_read(id_ex_q.control.mem_read),
        .id_ex_rd     (id_ex_q.rd),

        .ex_redirect  (ex_redirect),

        .pc_stall     (pc_stall),
        .if_id_stall  (if_id_stall),
        .if_id_flush  (if_id_flush),
        .id_ex_flush  (id_ex_flush)
    );

    /*
     * ================================================================
     * MEM stage
     * ================================================================
     */

    logic [31:0] mem_load_data;
    logic        mem_misaligned;
    logic        lsu_write_enable;
    logic        memory_fault;
    logic data_read_enable;

    rv32_lsu lsu (
        .address            (ex_mem_q.alu_result),
        .store_data         (ex_mem_q.store_data),
        .memory_read_data   (data_rdata),
        .memory_read_enable(data_read_enable),

        .mem_read           (
            ex_mem_q.valid &&
            ex_mem_q.control.mem_read
        ),

        .mem_write          (
            ex_mem_q.valid &&
            ex_mem_q.control.mem_write
        ),

        .mem_size           (ex_mem_q.control.mem_size),
        .load_unsigned      (ex_mem_q.control.load_unsigned),

        .memory_address     (data_addr),
        .memory_write_data  (data_wdata),
        .memory_write_strobe(data_wstrb),
        .memory_write_enable(lsu_write_enable),

        .load_data          (mem_load_data),
        .misaligned_access(mem_misaligned)
    );

    assign data_write = lsu_write_enable;

    assign memory_fault =
        ex_mem_q.valid &&
        (
            ex_mem_q.control.mem_read ||
            ex_mem_q.control.mem_write
        ) &&
        mem_misaligned;

    /*
     * ================================================================
     * Sequential pipeline-register updates
     * ================================================================
     */

    always_ff @(posedge clk) begin
        if (reset) begin
            fetch_pc <= 32'b0;

            if_id_q  <= '0;
            id_ex_q  <= '0;
            ex_mem_q <= '0;
            mem_wb_q <= '0;
        end
        else begin
            /*
             * ---------------- PC register ----------------
             */
            if (ex_redirect) begin
                fetch_pc <= ex_redirect_target;
            end
            else if (!pc_stall) begin
                fetch_pc <= fetch_pc + 32'd4;
            end

            /*
             * ---------------- IF/ID register ----------------
             */
            if (if_id_flush) begin
                if_id_q <= '0;
            end
            else if (!if_id_stall) begin
                if_id_q.valid       <= 1'b1;
                if_id_q.pc          <= fetch_pc;
                if_id_q.instruction <= instr_rdata;
            end

            /*
             * ---------------- ID/EX register ----------------
             */
            if (id_ex_flush) begin
                id_ex_q <= '0;
            end
            else begin
                id_ex_q.valid <=
                    if_id_q.valid &&
                    !id_illegal_instruction;

                id_ex_q.pc         <= if_id_q.pc;
                id_ex_q.pc_plus_4  <= if_id_q.pc + 32'd4;
                id_ex_q.rs1_data   <= id_rs1_data;
                id_ex_q.rs2_data   <= id_rs2_data;
                id_ex_q.immediate  <= id_immediate;
                id_ex_q.rs1        <= id_rs1;
                id_ex_q.rs2        <= id_rs2;
                id_ex_q.rd         <= id_rd;
                id_ex_q.control    <= id_control;
            end

            /*
             * ---------------- EX/MEM register ----------------
             *
             * The branch instruction itself is allowed to continue.
             * Only the younger instructions in IF and ID are flushed.
             */
            ex_mem_q.valid       <= id_ex_q.valid;
            ex_mem_q.alu_result  <= ex_alu_result;
            ex_mem_q.store_data  <= ex_rs2_forwarded;
            ex_mem_q.pc_plus_4   <= id_ex_q.pc_plus_4;
            ex_mem_q.rd          <= id_ex_q.rd;
            ex_mem_q.control     <= id_ex_q.control;

            /*
             * ---------------- MEM/WB register ----------------
             */
            mem_wb_q.valid       <=
                ex_mem_q.valid &&
                !memory_fault;

            mem_wb_q.alu_result  <= ex_mem_q.alu_result;
            mem_wb_q.load_data   <= mem_load_data;
            mem_wb_q.pc_plus_4   <= ex_mem_q.pc_plus_4;
            mem_wb_q.rd          <= ex_mem_q.rd;
            mem_wb_q.control     <= ex_mem_q.control;
        end
    end

endmodule