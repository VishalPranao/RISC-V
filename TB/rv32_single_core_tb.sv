`timescale 1ns/1ps

module rv32_single_cycle_tb;

    //==============================================================
    // Clock and reset
    //==============================================================
    logic clk;
    logic reset;

    //==============================================================
    // Instruction-memory interface
    //==============================================================
    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;

    //==============================================================
    // Data-memory interface
    //==============================================================
    logic [31:0] data_addr;
    logic        data_read;
    logic        data_write;
    logic [31:0] data_wdata;
    logic [3:0]  data_wstrb;
    logic [31:0] data_rdata;

    //==============================================================
    // CPU status
    //==============================================================
    logic illegal_instruction;
    logic misaligned_access;

    //==============================================================
    // Simple instruction and data memories
    //
    // 256 words × 4 bytes = 1024 bytes each
    //==============================================================
    logic [31:0] instruction_memory [0:255];
    logic [31:0] data_memory        [0:255];

    integer i;

    //==============================================================
    // DUT
    //==============================================================
    rv32_single_cycle_core #(
        .RESET_VECTOR (32'h00000000)
    ) dut (
        .clk                  (clk),
        .reset                (reset),

        .instr_addr           (instr_addr),
        .instr_rdata          (instr_rdata),

        .data_addr            (data_addr),
        .data_read            (data_read),
        .data_write           (data_write),
        .data_wdata           (data_wdata),
        .data_wstrb           (data_wstrb),
        .data_rdata           (data_rdata),

        .illegal_instruction  (illegal_instruction),
        .misaligned_access    (misaligned_access)
    );

    //==============================================================
    // Clock generation
    //==============================================================
    initial begin
        clk = 1'b0;
    end

    always #5 clk = ~clk;

    //==============================================================
    // Combinational instruction-memory read
    //
    // Each entry stores one 32-bit instruction.
    // Bits [1:0] are removed because instructions are four bytes.
    //==============================================================
    always_comb begin
        instr_rdata =
            instruction_memory[instr_addr[9:2]];
    end

    //==============================================================
    // Combinational data-memory read
    //==============================================================
    always_comb begin
        if (data_read)
            data_rdata = data_memory[data_addr[9:2]];
        else
            data_rdata = 32'b0;
    end

    //==============================================================
    // Synchronous data-memory write with byte strobes
    //==============================================================
    always @(posedge clk) begin
        if (data_write) begin

            if (data_wstrb[0]) begin
                data_memory[data_addr[9:2]][7:0]
                    <= data_wdata[7:0];
            end

            if (data_wstrb[1]) begin
                data_memory[data_addr[9:2]][15:8]
                    <= data_wdata[15:8];
            end

            if (data_wstrb[2]) begin
                data_memory[data_addr[9:2]][23:16]
                    <= data_wdata[23:16];
            end

            if (data_wstrb[3]) begin
                data_memory[data_addr[9:2]][31:24]
                    <= data_wdata[31:24];
            end

        end
    end

    //==============================================================
    // Display instruction execution
    //==============================================================
    always @(negedge clk) begin
    if (!reset) begin
        $display(
            "time=%0t PC=%08h instruction=%08h data_addr=%08h data_write=%b wdata=%08h wstrb=%b",
            $time,
            instr_addr,
            instr_rdata,
            data_addr,
            data_write,
            data_wdata,
            data_wstrb
        );
        end
    end

    //==============================================================
    // Test sequence
    //==============================================================
    initial begin
        reset = 1'b1;

        // Initialize instruction memory with NOPs:
        // addi x0, x0, 0
        for (i = 0; i < 256; i = i + 1) begin
            instruction_memory[i] = 32'h00000013;
        end

        // Initialize data memory to zero
        for (i = 0; i < 256; i = i + 1) begin
            data_memory[i] = 32'b0;
        end

        /*
         * Test program:
         *
         * Address 0x00: addi x1, x0, 5
         * Address 0x04: addi x2, x0, 3
         * Address 0x08: add  x3, x1, x2
         * Address 0x0C: sw   x3, 0(x0)
         * Address 0x10: nop
         */

        instruction_memory[0] = 32'h00500093;
        instruction_memory[1] = 32'h00300113;
        instruction_memory[2] = 32'h002081B3;
        instruction_memory[3] = 32'h00302023;
        instruction_memory[4] = 32'h00000013;

        // Hold reset for two positive clock edges
        repeat (2) @(posedge clk);

        // Deassert reset away from the active clock edge
        @(negedge clk);
        reset = 1'b0;

        // Execute four instructions
        repeat (4) @(posedge clk);

        // Wait for nonblocking memory/register writes to complete
        #1;

        //==========================================================
        // Final checks
        //==========================================================
        if (data_memory[0] !== 32'd8) begin
            $fatal(
                1,
                "TEST FAILED: memory[0] expected 8, received %0d",
                data_memory[0]
            );
        end

        if (misaligned_access) begin
            $fatal(
                1,
                "TEST FAILED: Unexpected misaligned access"
            );
        end

        $display("----------------------------------------");
        $display("TEST PASSED");
        $display("memory[0] = %0d", data_memory[0]);
        $display("----------------------------------------");

        $finish;
    end

endmodule