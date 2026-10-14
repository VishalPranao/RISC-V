`timescale 1ns/1ps
module rv32m_tb;
    logic clk = 0;
    logic reset = 1;
    always #5 clk = ~clk;
    logic [31:0] instr_addr, instr_rdata;
    logic [31:0] data_addr, data_wdata, data_rdata;
    logic [3:0] data_wstrb;
    logic data_write;
    logic [31:0] imem [0:1023];
    logic [31:0] dmem [0:1023];
    integer pc_word;
    integer cycle_count;
    integer store_count;

    rv32_pipeline_core dut (
        .clk(clk), .reset(reset), .instr_addr(instr_addr),
        .instr_rdata(instr_rdata), .data_addr(data_addr),
        .data_wdata(data_wdata), .data_rdata(data_rdata),
        .data_wstrb(data_wstrb), .data_write(data_write)
    );

    function automatic [31:0] r_inst(input [2:0] f3, input [4:0] rd, rs1, rs2,
                                      input [6:0] f7);
        return {f7, rs2, rs1, f3, rd, 7'b0110011};
    endfunction
    function automatic [31:0] addi_inst(input [4:0] rd, rs1, input integer imm);
        return {imm[11:0], rs1, 3'b000, rd, 7'b0010011};
    endfunction
    function automatic [31:0] lw_inst(input [4:0] rd, rs1, input integer imm);
        return {imm[11:0], rs1, 3'b010, rd, 7'b0000011};
    endfunction
    function automatic [31:0] sw_inst(input [4:0] rs2, rs1, input integer imm);
        return {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction
    function automatic [31:0] beq_inst(input [4:0] rs1, rs2, input integer imm);
        return {imm[12], imm[10:5], rs2, rs1, 3'b000,
                imm[4:1], imm[11], 7'b1100011};
    endfunction
    task automatic emit(input [31:0] instruction);
        imem[pc_word] = instruction;
        pc_word++;
    endtask

    always_comb begin
        instr_rdata = imem[instr_addr[11:2]];
        data_rdata = dmem[data_addr[11:2]];
    end
    always @(posedge clk) begin
        if (!reset) begin
            cycle_count <= cycle_count + 1;
            if (data_write) begin
                store_count = store_count + 1;
                for (int lane = 0; lane < 4; lane++)
                    if (data_wstrb[lane])
                        dmem[data_addr[11:2]][8*lane +: 8] <= data_wdata[8*lane +: 8];
                if (data_addr == 'h3fc) begin
                    #1;
                    if (store_count != 18)
                        $fatal(1, "expected 17 data stores plus completion, saw %0d", store_count);
                    if (dmem['h3c0/4] !== 0) $fatal(1, "wrong-path store committed");
                    check('h180, 32'd3); // older store drains when DIV starts
                    check('h200, 32'hffff_ffeb); // MUL -7*3 = -21
                    check('h204, 32'hffff_ffff); // MULH signed
                    check('h208, 32'hffff_ffff); // MULHSU signed*unsigned
                    check('h20c, 32'h0000_0002); // MULHU unsigned
                    check('h210, 32'hffff_fffe); // DIV signed -2
                    check('h214, 32'hffff_ffff); // REM signed -1
                    check('h218, 32'h5555_5553); // DIVU 0xfffffff9 / 3
                    check('h21c, 32'h0000_0000); // REMU
                    check('h220, 32'hffff_ffff); // DIV by zero
                    check('h224, 32'hffff_fff9); // REM by zero = dividend
                    check('h228, 32'h8000_0000); // signed division overflow
                    check('h22c, 32'h0000_0000); // signed overflow remainder
                    check('h230, 32'h0000_000c); // MUL -> ADD forwarding
                    check('h234, 32'h0000_0012); // LW -> MUL load-use stall
                    check('h238, 32'h0000_0002); // loaded operand -> DIV
                    check('h23c, 32'h0000_0005); // DIV -> ADD in-order result
                    $display("PASS: RV32IM M-extension signatures and pipeline hazards (%0d cycles)", cycle_count);
                    $finish;
                end
            end
        end
    end
    task automatic check(input integer addr, input [31:0] expected);
        if (dmem[addr/4] !== expected)
            $fatal(1, "addr=%h expected=%h got=%h", addr, expected, dmem[addr/4]);
    endtask

    initial begin
        pc_word = 0;
        cycle_count = 0;
        store_count = 0;
        for (int j = 0; j < 1024; j++) begin
            imem[j] = 32'h00000013; // addi x0,x0,0
            dmem[j] = 32'b0;
        end
        dmem['h100/4] = 6;
        emit(addi_inst(1, 0, -7));
        emit(addi_inst(2, 0, 3));
        emit(r_inst(3'b000, 3, 1, 2, 7'b0000001)); // MUL
        emit(r_inst(3'b001, 4, 1, 2, 7'b0000001)); // MULH
        emit(r_inst(3'b010, 5, 1, 2, 7'b0000001)); // MULHSU
        emit(r_inst(3'b011, 6, 1, 2, 7'b0000001)); // MULHU
        emit(sw_inst(2, 0, 'h180)); // older store immediately before DIV
        emit(r_inst(3'b100, 7, 1, 2, 7'b0000001)); // DIV
        emit(r_inst(3'b110, 8, 1, 2, 7'b0000001)); // REM
        emit(r_inst(3'b101, 9, 1, 2, 7'b0000001)); // DIVU
        emit(r_inst(3'b111, 10, 1, 2, 7'b0000001)); // REMU
        emit(r_inst(3'b100, 11, 1, 0, 7'b0000001)); // DIV by zero
        emit(r_inst(3'b110, 12, 1, 0, 7'b0000001)); // REM by zero
        emit(32'h800006b7); // lui x13,0x80000
        emit(addi_inst(14, 0, -1));
        emit(r_inst(3'b100, 15, 13, 14, 7'b0000001)); // overflow
        emit(r_inst(3'b110, 16, 13, 14, 7'b0000001)); // overflow remainder
        emit(r_inst(3'b000, 17, 2, 2, 7'b0000001)); // x17=9
        emit(r_inst(3'b000, 18, 17, 2, 7'b0000000)); // x18=12, forwarding
        emit(lw_inst(19, 0, 'h100));
        emit(r_inst(3'b000, 20, 19, 2, 7'b0000001)); // x20=18, load-use
        emit(r_inst(3'b100, 21, 19, 2, 7'b0000001)); // x21=2
        emit(r_inst(3'b000, 22, 21, 2, 7'b0000000)); // x22=5
        emit(beq_inst(22, 22, 8)); // skip wrong-path store
        emit(sw_inst(1, 0, 'h3c0));
        emit(sw_inst(3, 0, 'h200));
        emit(sw_inst(4, 0, 'h204));
        emit(sw_inst(5, 0, 'h208));
        emit(sw_inst(6, 0, 'h20c));
        emit(sw_inst(7, 0, 'h210));
        emit(sw_inst(8, 0, 'h214));
        emit(sw_inst(9, 0, 'h218));
        emit(sw_inst(10, 0, 'h21c));
        emit(sw_inst(11, 0, 'h220));
        emit(sw_inst(12, 0, 'h224));
        emit(sw_inst(15, 0, 'h228));
        emit(sw_inst(16, 0, 'h22c));
        emit(sw_inst(18, 0, 'h230));
        emit(sw_inst(20, 0, 'h234));
        emit(sw_inst(21, 0, 'h238));
        emit(sw_inst(22, 0, 'h23c));
        emit(addi_inst(31, 0, 1));
        emit(sw_inst(31, 0, 'h3fc));
        repeat (4) @(posedge clk);
        @(negedge clk) reset = 0;
        repeat (1500) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule
