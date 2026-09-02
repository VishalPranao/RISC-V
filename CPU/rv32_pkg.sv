package rv32_pkg;

    // RV32I opcodes
    localparam logic [6:0] OPCODE_LUI     = 7'b0110111;
    localparam logic [6:0] OPCODE_AUIPC   = 7'b0010111;
    localparam logic [6:0] OPCODE_JAL     = 7'b1101111;
    localparam logic [6:0] OPCODE_JALR    = 7'b1100111;
    localparam logic [6:0] OPCODE_BRANCH  = 7'b1100011;
    localparam logic [6:0] OPCODE_LOAD    = 7'b0000011;
    localparam logic [6:0] OPCODE_STORE   = 7'b0100011;
    localparam logic [6:0] OPCODE_OP_IMM  = 7'b0010011;
    localparam logic [6:0] OPCODE_OP      = 7'b0110011;

    typedef enum logic [2:0] {
        IMM_I,
        IMM_S,
        IMM_B,
        IMM_U,
        IMM_J
    } imm_type_e;

    typedef enum logic [3:0] {
        ALU_ADD,
        ALU_SUB,
        ALU_SLL,
        ALU_SLT,
        ALU_SLTU,
        ALU_XOR,
        ALU_SRL,
        ALU_SRA,
        ALU_OR,
        ALU_AND,
        ALU_PASS_A,
        ALU_PASS_B
    } alu_op_e;

    typedef enum logic [2:0] {
        BR_NONE,
        BR_EQ,
        BR_NE,
        BR_LT,
        BR_GE,
        BR_LTU,
        BR_GEU
    } branch_type_e;

    typedef enum logic [1:0] {
        WB_ALU,
        WB_MEMORY,
        WB_PC_PLUS_4
    } wb_sel_e;

    typedef enum logic [1:0] {
    MEM_BYTE,
    MEM_HALF,
    MEM_WORD
    } mem_size_e;
    
typedef enum logic [1:0] {
    OP_A_RS1,
    OP_A_PC,
    OP_A_ZERO
} operand_a_sel_e;

typedef enum logic {
    OP_B_RS2,
    OP_B_IMM
} operand_b_sel_e;

typedef struct packed {
    logic             reg_write;

    logic             mem_read;
    logic             mem_write;
    mem_size_e        mem_size;
    logic             load_unsigned;

    logic             uses_rs1;
    logic             uses_rs2;

    logic             is_jal;
    logic             is_jalr;

    alu_op_e          alu_op;
    imm_type_e        imm_type;
    branch_type_e     branch_type;
    wb_sel_e          wb_sel;
    operand_a_sel_e   operand_a_sel;
    operand_b_sel_e   operand_b_sel;
} control_t;

endpackage

