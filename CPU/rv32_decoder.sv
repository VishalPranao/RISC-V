module rv32_decoder (
    input  logic [31:0]          instruction,

    output logic [4:0]           rs1_addr,
    output logic [4:0]           rs2_addr,
    output logic [4:0]           rd_addr,

    output rv32_pkg::control_t   control,
    output logic                 illegal_instruction
);

    import rv32_pkg::*;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode   = instruction[6:0];
    assign rd_addr  = instruction[11:7];
    assign funct3   = instruction[14:12];
    assign rs1_addr = instruction[19:15];
    assign rs2_addr = instruction[24:20];
    assign funct7   = instruction[31:25];

    always_comb begin
        // Safe defaults: instruction has no architectural side effects
        control             = '0;
        illegal_instruction = 1'b0;

        case (opcode)

            // LUI: rd = immediate
            OPCODE_LUI: begin
                control.reg_write     = 1'b1;
                control.imm_type      = IMM_U;
                control.operand_a_sel = OP_A_ZERO;
                control.operand_b_sel = OP_B_IMM;
                control.alu_op        = ALU_PASS_B;
                control.wb_sel        = WB_ALU;
            end

            // AUIPC: rd = PC + immediate
            OPCODE_AUIPC: begin
                control.reg_write     = 1'b1;
                control.imm_type      = IMM_U;
                control.operand_a_sel = OP_A_PC;
                control.operand_b_sel = OP_B_IMM;
                control.alu_op        = ALU_ADD;
                control.wb_sel        = WB_ALU;
            end

            // JAL: rd = PC + 4; PC = PC + immediate
            OPCODE_JAL: begin
                control.reg_write = 1'b1;
                control.is_jal    = 1'b1;
                control.imm_type  = IMM_J;
                control.wb_sel    = WB_PC_PLUS_4;
            end

            // JALR: rd = PC + 4; PC = rs1 + immediate
            OPCODE_JALR: begin
                if (funct3 == 3'b000) begin
                    control.reg_write     = 1'b1;
                    control.uses_rs1      = 1'b1;
                    control.is_jalr       = 1'b1;
                    control.imm_type      = IMM_I;
                    control.operand_a_sel = OP_A_RS1;
                    control.operand_b_sel = OP_B_IMM;
                    control.alu_op        = ALU_ADD;
                    control.wb_sel        = WB_PC_PLUS_4;
                end
                else begin
                    illegal_instruction = 1'b1;
                end
            end

            // Conditional branches
            OPCODE_BRANCH: begin
                control.uses_rs1  = 1'b1;
                control.uses_rs2  = 1'b1;
                control.imm_type  = IMM_B;

                case (funct3)
                    3'b000: control.branch_type = BR_EQ;
                    3'b001: control.branch_type = BR_NE;
                    3'b100: control.branch_type = BR_LT;
                    3'b101: control.branch_type = BR_GE;
                    3'b110: control.branch_type = BR_LTU;
                    3'b111: control.branch_type = BR_GEU;

                    default: illegal_instruction = 1'b1;
                endcase
            end

            // Loads: address = rs1 + immediate
            OPCODE_LOAD: begin
                control.reg_write     = 1'b1;
                control.mem_read      = 1'b1;
                control.uses_rs1      = 1'b1;
                control.imm_type      = IMM_I;
                control.operand_a_sel = OP_A_RS1;
                control.operand_b_sel = OP_B_IMM;
                control.alu_op        = ALU_ADD;
                control.wb_sel        = WB_MEMORY;

                case (funct3)
                    3'b000: begin  // LB
                        control.mem_size      = MEM_BYTE;
                        control.load_unsigned = 1'b0;
                    end

                    3'b001: begin  // LH
                        control.mem_size      = MEM_HALF;
                        control.load_unsigned = 1'b0;
                    end

                    3'b010: begin  // LW
                        control.mem_size      = MEM_WORD;
                        control.load_unsigned = 1'b0;
                    end

                    3'b100: begin  // LBU
                        control.mem_size      = MEM_BYTE;
                        control.load_unsigned = 1'b1;
                    end

                    3'b101: begin  // LHU
                        control.mem_size      = MEM_HALF;
                        control.load_unsigned = 1'b1;
                    end

                    default: illegal_instruction = 1'b1;
                endcase
            end

            // Stores: address = rs1 + immediate
            OPCODE_STORE: begin
                control.mem_write     = 1'b1;
                control.uses_rs1      = 1'b1;
                control.uses_rs2      = 1'b1;
                control.imm_type      = IMM_S;
                control.operand_a_sel = OP_A_RS1;
                control.operand_b_sel = OP_B_IMM;
                control.alu_op        = ALU_ADD;

                case (funct3)
                    3'b000: control.mem_size = MEM_BYTE; // SB
                    3'b001: control.mem_size = MEM_HALF; // SH
                    3'b010: control.mem_size = MEM_WORD; // SW

                    default: illegal_instruction = 1'b1;
                endcase
            end

            // Immediate ALU instructions
            OPCODE_OP_IMM: begin
                control.reg_write     = 1'b1;
                control.uses_rs1      = 1'b1;
                control.imm_type      = IMM_I;
                control.operand_a_sel = OP_A_RS1;
                control.operand_b_sel = OP_B_IMM;
                control.wb_sel        = WB_ALU;

                case (funct3)
                    3'b000: control.alu_op = ALU_ADD;  // ADDI
                    3'b010: control.alu_op = ALU_SLT;  // SLTI
                    3'b011: control.alu_op = ALU_SLTU; // SLTIU
                    3'b100: control.alu_op = ALU_XOR;  // XORI
                    3'b110: control.alu_op = ALU_OR;   // ORI
                    3'b111: control.alu_op = ALU_AND;  // ANDI

                    3'b001: begin // SLLI
                        if (funct7 == 7'b0000000)
                            control.alu_op = ALU_SLL;
                        else
                            illegal_instruction = 1'b1;
                    end

                    3'b101: begin
                        case (funct7)
                            7'b0000000:
                                control.alu_op = ALU_SRL; // SRLI

                            7'b0100000:
                                control.alu_op = ALU_SRA; // SRAI

                            default:
                                illegal_instruction = 1'b1;
                        endcase
                    end

                    default: illegal_instruction = 1'b1;
                endcase
            end

            // Register-register ALU instructions
            OPCODE_OP: begin
                control.reg_write     = 1'b1;
                control.uses_rs1      = 1'b1;
                control.uses_rs2      = 1'b1;
                control.operand_a_sel = OP_A_RS1;
                control.operand_b_sel = OP_B_RS2;
                control.wb_sel        = WB_ALU;

                // M shares the OP opcode and uses funct7 = 0000001.
                // Existing I operations retain their original decode below.
                if (funct7 == 7'b0000001) begin
                    case (funct3)
                        3'b000: control.alu_op = ALU_MUL;
                        3'b001: control.alu_op = ALU_MULH;
                        3'b010: control.alu_op = ALU_MULHSU;
                        3'b011: control.alu_op = ALU_MULHU;
                        3'b100: control.alu_op = ALU_DIV;
                        3'b101: control.alu_op = ALU_DIVU;
                        3'b110: control.alu_op = ALU_REM;
                        3'b111: control.alu_op = ALU_REMU;
                    endcase
                end
                else begin
                case (funct3)
                    3'b000: begin
                        case (funct7)
                            7'b0000000:
                                control.alu_op = ALU_ADD;

                            7'b0100000:
                                control.alu_op = ALU_SUB;

                            default:
                                illegal_instruction = 1'b1;
                        endcase
                    end

                    3'b001: begin // SLL
                        if (funct7 == 7'b0000000)
                            control.alu_op = ALU_SLL;
                        else
                            illegal_instruction = 1'b1;
                    end

                    3'b010: begin // SLT
                        if (funct7 == 7'b0000000)
                            control.alu_op = ALU_SLT;
                        else
                            illegal_instruction = 1'b1;
                    end

                    3'b011: begin // SLTU
                        if (funct7 == 7'b0000000)
                            control.alu_op = ALU_SLTU;
                        else
                            illegal_instruction = 1'b1;
                    end

                    3'b100: begin // XOR
                        if (funct7 == 7'b0000000)
                            control.alu_op = ALU_XOR;
                        else
                            illegal_instruction = 1'b1;
                    end

                    3'b101: begin
                        case (funct7)
                            7'b0000000:
                                control.alu_op = ALU_SRL;

                            7'b0100000:
                                control.alu_op = ALU_SRA;

                            default:
                                illegal_instruction = 1'b1;
                        endcase
                    end

                    3'b110: begin // OR
                        if (funct7 == 7'b0000000)
                            control.alu_op = ALU_OR;
                        else
                            illegal_instruction = 1'b1;
                    end

                    3'b111: begin // AND
                        if (funct7 == 7'b0000000)
                            control.alu_op = ALU_AND;
                        else
                            illegal_instruction = 1'b1;
                    end

                    default: illegal_instruction = 1'b1;
                endcase
                end
            end

            default: begin
                illegal_instruction = 1'b1;
            end

        endcase

        // An illegal instruction must never modify registers or memory
        if (illegal_instruction) begin
            control = '0;
        end
    end

endmodule
