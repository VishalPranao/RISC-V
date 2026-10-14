# Five-Stage RV32IM RISC-V Processor

This project implements a 32-bit, in-order RISC-V processor in SystemVerilog. It uses five pipeline stages—**instruction fetch (IF), decode (ID), execute (EX), memory (MEM), and writeback (WB)**—with forwarding, a load-use interlock, and control-flow flushing. The processor currently uses separate instruction and data memory ports suitable for a simple, zero-wait-state simulation memory.

The intended larger system is an RV32IM CPU with an AXI-connected INT8 matrix-multiplication accelerator. The C extension has been dropped from this design.

## Architecture

The CPU fetches one 32-bit instruction at the current PC. Pipeline registers carry each instruction's PC, operands, destination register, control signals, and `valid` bit to the next stage. Different instructions can occupy different stages simultaneously. Without a hazard or redirect, the pipeline can accept one instruction per cycle; an individual instruction passes through five stages.

### Instruction fetch (IF)

The PC addresses instruction memory. The fetched 32-bit instruction and its PC enter the IF/ID register. Sequential execution advances the PC by four bytes. A taken branch or jump redirects the PC to its computed target. PC hold and pipeline flush controls prevent incorrect instruction fetches from becoming architectural effects.

### Decode and register read (ID)

The decoder identifies the instruction type and generates the controls needed by later stages. The immediate generator extracts and sign-extends I-, S-, B-, U-, or J-type immediates as appropriate. The register file has two source reads and one destination write; `x0` reads as zero and ignores writes. The decoded fields, register values, PC, and controls enter ID/EX. A writeback-to-decode bypass or equivalent write-through behavior supplies a new register value when WB writes the register that ID reads in the same cycle.

### Execute (EX)

Two forwarding muxes select the current values of `rs1` and `rs2` before the ALU and other consumers use them. The ALU performs integer arithmetic, comparisons, logic, shifts, multiplication, and load/store address calculations. Divide and remainder use a 32-step iterative divider in EX. Branches compare the corrected source operands. `JAL` and `JALR` generate targets and a PC-plus-four link value; `JALR` uses the corrected `rs1` value and clears the target's low bit. A taken redirect flushes younger, wrong-path instructions.

### Memory (MEM)

The load/store unit uses the effective **byte address** to select a word or a byte/halfword lane. It generates store byte strobes and positions write data in the selected lanes. On loads, it selects the requested portion of the returned data word and sign-extends or zero-extends it according to the instruction. Arithmetic instructions pass their result through this stage without a data-memory write. Store writes are gated by the pipeline entry's `valid` bit.

### Writeback (WB)

The writeback mux selects the ALU result, load result, or `PC + 4` link value and writes it to `rd` when the instruction is valid and enables register writeback. Writes to `x0` have no effect.

## Supported functionality

- Five-stage, single-issue, in-order execution of the implemented RV32I integer datapath.
- RV32M: `MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, and `REMU`.
- Integer register operations and immediate operations: arithmetic, logical, shifts, and comparisons.
- `LUI` and `AUIPC`; conditional branches; `JAL` and `JALR`.
- Byte, halfword, and word loads/stores, including signed and unsigned load variants and per-byte store strobes.
- Hardwired zero register (`x0`) and register-file write-through for same-cycle WB/ID dependencies.
- Data hazard handling through EX/MEM-to-EX and MEM/WB-to-EX forwarding, with EX/MEM priority when both match the same destination register.
- One-cycle interlock and bubble for an immediately dependent load when using the zero-wait-state memory model.
- Forwarded operands for ALU operations, store addresses, store data, branch comparisons, and `JALR` targets.
- Redirect and invalidation of younger instructions after taken branches and jumps.

The decoder and datapath recognize the implemented RV32I and RV32M encodings. This is not a claim of privileged or system-instruction support.

## How hazards are handled

For each EX-stage source register, the forwarding unit checks whether a valid older instruction will write that register. It ignores destination register `x0`. It first checks the immediately older instruction in EX/MEM, then MEM/WB; otherwise it uses the operand saved in ID/EX. This lets an ALU result be consumed by the next instruction without waiting for its register-file write.

A load is different: its EX/MEM ALU result is the **address**, not the data read from memory. If the next instruction needs that load's destination, the hazard unit holds the PC and IF/ID for one cycle and inserts an invalid ID/EX entry (a bubble). The load continues to MEM. When the dependent instruction reaches EX, it can use the load value through MEM/WB forwarding.

Multiplication produces its result in EX and uses the existing forwarding paths. A divide or remainder instruction stays in ID/EX while its operands are captured by the divider. The PC and IF/ID hold, EX/MEM receives invalid bubbles, and older instructions drain through MEM/WB. On completion, the result moves into EX/MEM exactly once. Divide by zero and signed overflow return the values specified by RV32M.

On a taken branch or jump resolved in EX, younger instructions in IF and ID are invalidated. A bubble or flushed entry has `valid = 0`; register and memory writes are permitted only for valid entries. The redirecting instruction itself continues through the older pipeline stages.

WAR and WAW register hazards do not require separate handling in this fixed-stage, in-order pipeline: source reads occur in ID and register writes occur in WB in program order.

## Memory and simulation assumptions

The CPU's instruction and data memory interfaces are separate. The accompanying simulation environment supplies combinational reads and synchronous, byte-strobed data writes. Memory responses are available without a variable-latency handshake. Instruction addresses are byte addresses and normally advance by four; the testbench indexes its 32-bit instruction words using the address shifted right by two.

This memory model is useful for pipeline bring-up. It does **not** establish AXI compliance, delayed memory response handling, cache behavior, or operation with arbitrary memory stalls. Data access alignment can be detected by the LSU, but detection alone is not an architectural trap or misaligned-access recovery mechanism.

## Unsupported functionality and limits

- **RV32C:** 16-bit compressed instructions, instruction decompression, mixed-width fetch, and PC increments of two bytes.
- **System/privileged behavior:** CSRs, traps, exceptions, interrupts, privilege modes, and an operating-system execution environment. In particular, an unsupported or misaligned access is not handled as a complete architectural exception.
- **Additional ISA features:** atomics, floating point, and other extensions; `FENCE`/system instruction behavior is not claimed.
- **Variable-latency memory and full AXI protocol:** no CPU request/response stalls, independent AXI channel handshakes, or burst transactions are described by the current simulation memory ports.
- **GEMM SoC:** no INT8 GEMM datapath, memory-mapped accelerator control/status registers, GEMM AXI master, shared-memory arbitration, or CPU-driven accelerator program is part of this implementation.

## Build and test

This bundle follows the directories and module ports of commit
`7faa0ed3fcb681f5971d2902a45eb8249fa2cef1` of
`VishalPranao/RISC-V`. You can copy its `CPU/` and `TB/` files into a checkout
of that commit, or apply `RV32IM.patch` from the checkout root with
`git apply RV32IM.patch`. Review local changes before applying a patch to a
different revision. The package and existing module names are preserved.

Compile with `CPU/rv32_pkg.sv` first, followed by the other `CPU/*.sv` files,
then one testbench from `TB/`. Include the new `CPU/rv32_m_divider.sv` file.
In Questa/ModelSim, from the repository root:

```tcl
vlib work
vlog -sv CPU/rv32_pkg.sv CPU/rv32_alu.sv CPU/rv32_branch_cmp.sv CPU/rv32_decoder.sv CPU/rv32_forwarding_unit.sv CPU/rv32_hazard_unit.sv CPU/rv32_imm_gen.sv CPU/rv32_lsu.sv CPU/rv32_m_divider.sv CPU/rv32_regfile.sv CPU/rv32_pipeline_core.sv TB/rv32_pipeline_tb.sv TB/rv32m_tb.sv
vsim -c rv32_pipeline_tb -do "run -all; quit -f"
vsim -c rv32m_tb -do "run -all; quit -f"
```

The original smoke test and the directed RV32M signature test both pass with
Verilator. The M test covers all eight operations, signed high products,
divide-by-zero and overflow, consecutive divides, `LW`→`MUL`, `DIV`→`ADD`,
branch flush, and exactly-once store behavior. For assembly programs, use
`-march=rv32im -mabi=ilp32` so compressed instructions are not emitted.
