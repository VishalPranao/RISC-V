RV32I Single-Cycle Processor

This project currently implements a functional single-cycle RV32I processor in SystemVerilog. The single-cycle core is an intermediate architectural checkpoint: it verifies instruction decoding and the complete datapath before the design is divided into the classic IF, ID, EX, MEM, and WB pipeline stages.

The long-term goal is to extend the processor toward an RV32IMC-based SoC with a GEMM accelerator. The current implementation focuses only on the RV32I base integer datapath.

Current Features

32-bit RV32I instruction decoding

32 × 32-bit integer register file

Hardwired x0 register

I-, S-, B-, U-, and J-type immediate generation

Integer arithmetic, logical, comparison, and shift operations

Conditional branches, JAL, and JALR

Byte, halfword, and word loads and stores

Signed and unsigned load extension

Store byte strobes

Misaligned halfword and word detection

Separate instruction-memory and data-memory interfaces

One CPU-level SystemVerilog testbench

The current version does not implement the M or C extensions, CSRs, exceptions, interrupts, caches, AXI, or pipelining.

Datapath Overview

flowchart TD
    PC["Program counter"] --> IMEM["Instruction memory"]
    IMEM --> DEC["Decoder"]
    IMEM --> IMM["Immediate generator"]
    DEC --> RF["Register file"]
    DEC --> MUX["Operand muxes"]
    IMM --> MUX
    RF --> MUX
    MUX --> ALU["ALU"]
    RF --> BR["Branch comparator"]
    ALU --> LSU["Load/store unit"]
    RF --> LSU
    LSU <--> DMEM["Data memory"]
    ALU --> WB["Writeback mux"]
    LSU --> WB
    PC --> WB
    WB --> RF

The decoder creates the control signals, while the register values, immediate, ALU result, memory data, and writeback value form the data path.

Implemented Modules

rv32_pkg.sv

Contains the shared architectural and control definitions used throughout the processor:

RV32I opcode constants

ALU operation enum

Immediate-type enum

Branch-type enum

Operand-selection enums

Memory-size enum

Writeback-selection enum

Packed control_t structure

The package must be compiled before every module that references its definitions.

rv32_imm_gen.sv

Extracts, rearranges, and extends the immediate embedded in an instruction. It supports:

I-type immediates for immediate ALU operations, loads, and JALR

S-type immediates for stores

B-type offsets for conditional branches

U-type upper immediates for LUI and AUIPC

J-type offsets for JAL

The decoder selects the required immediate format through control.imm_type.

rv32_alu.sv

Performs the RV32I integer operations:

Addition and subtraction

AND, OR, and XOR

Logical and arithmetic shifts

Signed and unsigned less-than comparisons

Operand pass-through

The ALU does not know whether an operand came from a register, the PC, or the immediate generator. Operand muxes in the core select the values before they enter the ALU.

For loads and stores, the ALU calculates the effective byte address:

effective address = rs1_data + immediate

rv32_branch_cmp.sv

Compares rs1_data and rs2_data for the six RV32I conditional branches:

BEQ

BNE

BLT

BGE

BLTU

BGEU

The comparator determines whether a branch is taken. The core separately calculates the target as PC + branch immediate.

rv32_regfile.sv

Implements the architectural integer register file:

32 registers of 32 bits each

Two asynchronous read ports

One synchronous write port

Writes to x0 are ignored

Reads from x0 always return zero

The decoder extracts rs1, rs2, and rd addresses from the instruction. The register file performs the actual source-register reads and destination-register write.

rv32_decoder.sv

Translates the RISC-V instruction encoding into internal control signals. It examines the opcode, funct3, and funct7 fields and produces:

Register read/write controls

ALU operation

Immediate format

ALU operand selections

Branch or jump information

Memory read/write information

Load/store width

Signed or unsigned load selection

Writeback source

Illegal-instruction indication

Unsupported or reserved encodings produce an illegal-instruction indication and no register or memory side effects.

rv32_lsu.sv

The load/store unit sits between the CPU datapath and data memory. It does not contain the memory itself.

For loads, it:

Selects the requested byte, halfword, or word

Sign-extends LB and LH

Zero-extends LBU and LHU

Passes all 32 bits for LW

For stores, it:

Positions byte or halfword data in the correct 32-bit lane

Generates four byte-write strobes

Passes all 32 bits and enables every strobe for SW

The lower address bits select a location inside a 32-bit word:

address[31:2] = memory-word index
address[1:0]  = byte position within that word

Misaligned halfword and word operations are detected and suppressed. Architectural misalignment exceptions are not implemented yet.

rv32_pc.sv

Stores the current program counter. On reset, it loads the configurable reset vector. During normal operation, it loads next_pc at every positive clock edge.

The core selects next_pc from:

PC + 4 for sequential execution

PC + immediate for a taken conditional branch

PC + immediate for JAL

(rs1 + immediate) & ~1 for JALR

rv32_single_cycle_core.sv

Connects the PC, decoder, immediate generator, register file, operand muxes, ALU, branch comparator, LSU, and writeback mux.

The writeback mux selects the value written to rd:

Instruction type

Writeback value

Integer ALU, LUI, AUIPC

ALU result

Load

LSU load data

JAL, JALR

PC + 4

Store or branch

No register write

Instruction Execution Examples

Integer operation

addi x5, x1, 10

The decoder selects an I-type immediate and the ADD operation.

The register file reads x1.

The immediate generator produces 10.

The operand muxes select x1 and the immediate.

The ALU adds them.

The result is written into x5 at the clock edge.

Load

lw x5, 8(x1)

The register file reads the base address from x1.

The immediate generator produces 8.

The ALU calculates x1 + 8.

The core requests a data-memory read at that address.

The external memory returns data_rdata.

The LSU produces load_data.

The writeback mux selects load_data and writes it to x5.

Store

sw x5, 8(x1)

The register file reads the base address from x1 and store data from x5.

The ALU calculates x1 + 8.

The LSU receives the address and rs2_data.

The LSU generates data_wdata, data_wstrb, and data_write.

The external data memory performs the write at the clock edge.

Memory Model

The processor exposes separate instruction- and data-memory ports. The actual memory arrays currently live in the testbench rather than inside the core.

The instruction memory performs a combinational read using the PC:

instr_rdata = instruction_memory[instr_addr[9:2]];

The data memory performs combinational reads and synchronous strobed writes. This is a zero-wait-state simulation model. Real cache, SRAM, and AXI latency will be introduced after the pipelined core works.

Current Test

rv32_single_cycle_tb.sv executes this program:

addi x1, x0, 5
addi x2, x0, 3
add  x3, x1, x2
sw   x3, 0(x0)

The expected result is:

x3        = 8
memory[0] = 8

The testbench checks memory[0] automatically. It currently initializes the instruction memory with complete 32-bit machine instructions. The next verification improvement is to load program images using $readmemh after compiling assembly through a RISC-V cross-toolchain.

Compilation

The package must be compiled first:

vlog -sv CPU/rv32_pkg.sv
vlog -sv CPU/rv32_pc.sv
vlog -sv CPU/rv32_imm_gen.sv
vlog -sv CPU/rv32_alu.sv
vlog -sv CPU/rv32_branch_cmp.sv
vlog -sv CPU/rv32_regfile.sv
vlog -sv CPU/rv32_decoder.sv
vlog -sv CPU/rv32_lsu.sv
vlog -sv CPU/rv32_single_cycle_core.sv
vlog -sv TB/rv32_single_core_tb.sv

Run the test in Questa/ModelSim:

vsim work.rv32_single_cycle_tb
run -all

Current Assumptions and Limitations

One instruction completes per clock cycle.

Instruction and data reads are combinational and have zero latency.

There are no valid/ready handshakes.

Misaligned accesses are detected but do not generate architectural traps.

Unsupported instructions advance to the next PC without a trap handler.

FENCE, system instructions, CSRs, interrupts, and exceptions are unsupported.

The M and C extensions are not implemented.

There is no forwarding, hazard detection, branch prediction, or pipeline flushing because the core is not pipelined yet.

The testbench currently uses small, separate instruction and data memories.

Next Steps

Replace manually entered machine instructions with assembly-generated hex files.

Add arithmetic, branch, jump, and load/store program regressions.

Freeze the single-cycle core as a known-good functional reference.

Divide the datapath into IF, ID, EX, MEM, and WB stages.

Add pipeline registers, forwarding, load-use stalls, and control-flow flushing.

Add variable-latency memory interfaces and AXI.

Add the RV32M multiply/divide unit.

Add RV32C decompression after the 32-bit pipeline is stable.

