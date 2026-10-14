`timescale 1ns/1ps
module rv32_pipeline_tb;
    logic clk = 0;
    logic reset = 1;
    always #5 clk = ~clk;

    logic [31:0] instr_addr, instr_rdata;
    logic [31:0] data_addr, data_wdata, data_rdata;
    logic [3:0] data_wstrb;
    logic data_write;
    logic [31:0] imem [0:1023];
    logic [31:0] dmem [0:1023];
    string hex_file;
    bit regression;
    integer errors = 0;

    // Check ONLY this instance against your actual top-level port names.
    // Assumptions: active-high reset; reset PC=0; no memory handshakes.
    rv32_pipeline_core dut (
        .clk(clk), .reset(reset),
        .instr_addr(instr_addr), .instr_rdata(instr_rdata),
        .data_addr(data_addr), .data_wdata(data_wdata),
        .data_rdata(data_rdata), .data_wstrb(data_wstrb),
        .data_write(data_write)
    );

    // Word memory: CPU addresses are BYTE addresses.
    // LSU must shift store data/strobes into byte lanes and select load bytes.
    always_comb begin
        instr_rdata = 32'h00000013;
        if (!$isunknown(instr_addr) && instr_addr < 4096)
            instr_rdata = imem[instr_addr >> 2];
        data_rdata = 0;
        if (!$isunknown(data_addr) && data_addr < 4096)
            data_rdata = dmem[data_addr >> 2];
    end

    task automatic check_word(input int addr, input logic [31:0] expected);
        if (dmem[addr >> 2] !== expected) begin
            $error("memory[0x%03h]: expected %0d (0x%08h), got 0x%08h",
                   addr, expected, expected, dmem[addr >> 2]);
            errors++;
        end
    endtask

    task automatic check_results;
        if (regression) begin
            check_word('h200, 6);  // EX/MEM -> rs1
            check_word('h204, 7);  // EX/MEM -> rs2
            check_word('h208, 16); // both operands
            check_word('h20c, 17); // two different forwarding sources
            check_word('h210, 12); // MEM/WB -> EX
            check_word('h214, 3);  // newest producer priority
            check_word('h218, 21); // WB and ID in the same cycle
            check_word('h21c, 42); // load -> ALU
            check_word('h220, 41); // load -> store data
            check_word('h224, 77); // ALU -> store address
            check_word('h228, 77); // load -> store address
            check_word('h22c, 1);  // ALU -> taken branch
            check_word('h230, 1);  // load -> taken branch
            check_word('h234, 0);  // JAL link = PC+4
            check_word('h238, 0);  // ALU -> JALR and JALR link
            check_word('h23c, 1);  // load -> JALR
            check_word('h240, 0);  // x0 cannot be forwarded/written
            check_word('h244, 15); // loop; taken and untaken branches
            check_word('h248, 1);  // consecutive taken branches
            check_word('h004, 41);
            check_word('h080, 77);
            check_word('h084, 77);
        end else begin
            check_word(0, 8);
            check_word(4, 16);
            check_word(8, 17);
        end
        if (errors != 0) $fatal(1, "FAIL: %0d memory checks failed", errors);
        $display("PASS: %s memory signatures matched",
                 regression ? "regression" : "smoke test");
        $finish;
    endtask

    // Synchronous writes; inspect the store presented BEFORE this clock edge.
    always @(posedge clk) begin
        if (!reset) begin
            if ($isunknown(instr_addr) || instr_addr >= 4096 || instr_addr[1:0] != 0)
                $fatal(1, "Invalid instruction address: %h", instr_addr);
            if ($isunknown(data_write)) $fatal(1, "Unknown memory write enable");
            if (data_write) begin
                if ($isunknown({data_addr, data_wstrb, data_wdata}) || data_addr >= 4096)
                    $fatal(1, "Invalid store: addr=%h data=%h", data_addr, data_wdata);
                if (data_addr == 'h300)
                    $fatal(1, "Wrong-path store executed: branch/jump flush failed");
                for (int lane = 0; lane < 4; lane++)
                    if (data_wstrb[lane])
                        dmem[data_addr >> 2][8*lane +: 8] <= data_wdata[8*lane +: 8];
                if (data_addr == 'h3fc) begin
                    if (data_wstrb !== 4'b1111 || data_wdata !== 1)
                        $fatal(1, "Invalid completion store");
                    // Wait until nonblocking memory updates have completed.
                    #1;
                    check_results();
                end
            end
        end
    end

    initial begin
        regression = $test$plusargs("REGRESSION");
        for (int i = 0; i < 1024; i++) begin
            imem[i] = 32'h00000013;
            dmem[i] = 0;
        end
        for (int i = 'h200/4; i <= 'h248/4; i++) dmem[i] = 32'hdeadbeef;
        // Smoke: arithmetic -> store -> load -> dependent arithmetic -> store.
        imem[0]  = 32'h00500093; // addi x1,x0,5
        imem[1]  = 32'h00300113; // addi x2,x0,3
        imem[2]  = 32'h002081b3; // add  x3,x1,x2
        imem[3]  = 32'h00302023; // sw   x3,0(x0)
        imem[4]  = 32'h00002203; // lw   x4,0(x0)
        imem[5]  = 32'h004202b3; // add  x5,x4,x4
        imem[6]  = 32'h00502223; // sw   x5,4(x0)
        imem[7]  = 32'h00128313; // addi x6,x5,1
        imem[8]  = 32'h00602423; // sw   x6,8(x0)
        imem[9]  = 32'h00100f93; // addi x31,x0,1
        imem[10] = 32'h3ff02e23; // sw   x31,1020(x0): done
        imem[11] = 32'h0000006f; // jal  x0,0
        if ($value$plusargs("HEX=%s", hex_file)) begin
            integer fd;
            fd = $fopen(hex_file, "r");
            if (!fd) $fatal(1, "Cannot open %s", hex_file);
            $fclose(fd);
            // Remove the built-in program before loading an external image.
            for (int i = 0; i < 1024; i++) imem[i] = 32'h00000013;
            $readmemh(hex_file, imem);
        end else if (regression) $fatal(1, "REGRESSION requires +HEX=program.hex");
        repeat (4) @(posedge clk);
        @(negedge clk); // Avoid racing the DUT's reset sampling.
        reset = 0;
        repeat (2000) @(posedge clk);
        $fatal(1, "TIMEOUT: program did not perform completion store");
    end
endmodule
