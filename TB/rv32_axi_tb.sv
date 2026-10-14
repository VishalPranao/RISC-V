`timescale 1ns/1ps
module rv32_axi_tb;
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;
    logic bus_error;
    logic [3:0] i_arid, i_rid, d_arid, d_rid, d_awid, d_bid;
    logic [31:0] i_araddr, i_rdata, d_araddr, d_rdata;
    logic [31:0] d_awaddr, d_wdata;
    logic [7:0] i_arlen, d_arlen, d_awlen;
    logic [2:0] i_arsize, d_arsize, d_awsize;
    logic [1:0] i_arburst, d_arburst, d_awburst;
    logic i_arlock, d_arlock, d_awlock;
    logic [3:0] i_arcache, d_arcache, d_awcache;
    logic [3:0] i_arqos, d_arqos, d_awqos;
    logic [3:0] i_arregion, d_arregion, d_awregion;
    logic [2:0] i_arprot, d_arprot, d_awprot;
    logic [1:0] i_rresp, d_rresp, d_bresp;
    logic i_arvalid, i_arready, i_rlast, i_rvalid, i_rready;
    logic d_arvalid, d_arready, d_rlast, d_rvalid, d_rready;
    logic d_awvalid, d_awready, d_wlast, d_wvalid, d_wready;
    logic d_bvalid, d_bready;
    logic [3:0] d_wstrb;
    logic [31:0] imem [0:1023], dmem [0:1023];
    int cycles, reads, writes, fetches, redirects, mem_holds;
    int aw_first, w_first, stale_fetches;
    int i_delay, d_read_delay, d_write_delay;
    logic i_pending, d_read_pending, aw_seen, w_seen, write_pending;
    logic [31:0] i_addr_q, d_addr_q, aw_addr_q, w_data_q;
    logic [3:0] w_strb_q;

    rv32im_axi_top dut (.*);
    assign i_arready = !i_pending && !i_rvalid && (cycles % 3 != 0);
    assign d_arready = !d_read_pending && !d_rvalid && (cycles % 4 != 0);
    assign d_awready = !aw_seen && (cycles % 7 == 4);
    assign d_wready = !w_seen && (cycles % 5 == 2);
    assign i_rid = 0;
    assign d_rid = 0;
    assign d_bid = 0;
    assign i_rresp = 0;
    assign d_rresp = 0;
    assign d_bresp = 0;
    assign i_rlast = 1;
    assign d_rlast = 1;

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
    function automatic [31:0] lbu_inst(input [4:0] rd, rs1, input integer imm);
        return {imm[11:0], rs1, 3'b100, rd, 7'b0000011};
    endfunction
    function automatic [31:0] sw_inst(input [4:0] rs2, rs1, input integer imm);
        return {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction
    function automatic [31:0] sb_inst(input [4:0] rs2, rs1, input integer imm);
        return {imm[11:5], rs2, rs1, 3'b000, imm[4:0], 7'b0100011};
    endfunction
    function automatic [31:0] beq_inst(input [4:0] rs1, rs2, input integer imm);
        return {imm[12], imm[10:5], rs2, rs1, 3'b000,
                imm[4:1], imm[11], 7'b1100011};
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            cycles <= 0;
            reads <= 0;
            writes <= 0;
            fetches <= 0;
            redirects <= 0;
            mem_holds <= 0;
            aw_first <= 0;
            w_first <= 0;
            stale_fetches <= 0;
            i_pending <= 0;
            d_read_pending <= 0;
            aw_seen <= 0;
            w_seen <= 0;
            write_pending <= 0;
            i_rvalid <= 0;
            d_rvalid <= 0;
            d_bvalid <= 0;
            i_delay <= 0;
            d_read_delay <= 0;
            d_write_delay <= 0;
            i_rdata <= 0;
            d_rdata <= 0;
        end else begin
            cycles <= cycles + 1;
            if (cycles > 2000) $fatal(1, "AXI test timeout");
            if (bus_error) $fatal(1, "unexpected AXI response error");
            if (dut.core.ex_redirect) begin
                redirects <= redirects + 1;
                if (dut.core.fetch_pending_q) stale_fetches <= stale_fetches + 1;
            end
            if (dut.core.mem_hold) mem_holds <= mem_holds + 1;
            if (i_arvalid && i_arready) begin
                if (i_arlen !== 0 || i_arsize !== 3'd2 || i_arburst !== 2'b01)
                    $fatal(1, "invalid instruction AR attributes");
                i_pending <= 1;
                i_addr_q <= i_araddr;
                i_delay <= 4;
                fetches <= fetches + 1;
            end
            if (i_pending && !i_rvalid) begin
                if (i_delay != 0) i_delay <= i_delay - 1;
                else begin
                    i_rdata <= imem[i_addr_q[11:2]];
                    i_rvalid <= 1;
                end
            end
            if (i_rvalid && i_rready) begin
                i_rvalid <= 0;
                i_pending <= 0;
            end
            if (d_arvalid && d_arready) begin
                if (d_araddr[1:0] != 0 || d_arlen != 0 || d_arsize != 3'd2)
                    $fatal(1, "invalid data AR attributes");
                d_read_pending <= 1;
                d_addr_q <= d_araddr;
                d_read_delay <= 5;
                reads <= reads + 1;
            end
            if (d_read_pending && !d_rvalid) begin
                if (d_read_delay != 0) d_read_delay <= d_read_delay - 1;
                else begin
                    d_rdata <= dmem[d_addr_q[11:2]];
                    d_rvalid <= 1;
                end
            end
            if (d_rvalid && d_rready) begin
                d_rvalid <= 0;
                d_read_pending <= 0;
            end
            if (d_awvalid && d_awready) begin
                if (!w_seen && !(d_wvalid && d_wready)) aw_first <= aw_first + 1;
                if (d_awaddr[1:0] != 0 || d_awlen != 0 || d_awsize != 3'd2)
                    $fatal(1, "invalid data AW attributes");
                aw_addr_q <= d_awaddr;
                aw_seen <= 1;
            end
            if (d_wvalid && d_wready) begin
                if (!aw_seen && !(d_awvalid && d_awready)) w_first <= w_first + 1;
                if (!d_wlast) $fatal(1, "single beat write missing WLAST");
                w_data_q <= d_wdata;
                w_strb_q <= d_wstrb;
                w_seen <= 1;
            end
            if (aw_seen && w_seen && !write_pending && !d_bvalid) begin
                write_pending <= 1;
                d_write_delay <= 6;
                for (int lane = 0; lane < 4; lane++)
                    if (w_strb_q[lane])
                        dmem[aw_addr_q[11:2]][8*lane +: 8] <= w_data_q[8*lane +: 8];
                writes <= writes + 1;
                if (aw_addr_q == 'h3fc) begin
                    #1;
                    if (dmem[0] !== 'h00007f0f || dmem[1] !== 16 ||
                        dmem[2] !== 5 || dmem[3] !== 127 ||
                        dmem['h300/4] !== 0 || reads != 2 || writes != 6 ||
                        redirects < 1 || mem_holds < 12 ||
                        aw_first < 1 || w_first < 1 || stale_fetches < 1)
                        $fatal(1, "signature/counter mismatch: [0..2]=%d,%d,%d reads=%0d writes=%0d redirects=%0d holds=%0d",
                            dmem[0],dmem[1],dmem[2],reads,writes,redirects,mem_holds);
                    $display("PASS: delayed AXI IF/D, M, load-use, write, branch (%0d cycles, %0d fetches, AW-first=%0d, W-first=%0d, stale=%0d)", cycles, fetches, aw_first, w_first, stale_fetches);
                    $finish;
                end
            end
            if (write_pending && !d_bvalid) begin
                if (d_write_delay != 0) d_write_delay <= d_write_delay - 1;
                else d_bvalid <= 1;
            end
            if (d_bvalid && d_bready) begin
                d_bvalid <= 0;
                aw_seen <= 0;
                w_seen <= 0;
                write_pending <= 0;
            end
        end
    end

    initial begin
        for (int j=0; j<1024; j++) begin
            imem[j] = 32'h00000013;
            dmem[j] = 0;
        end
        imem[0]  = addi_inst(1,0,5);
        imem[1]  = addi_inst(2,0,3);
        imem[2]  = r_inst(3'b000,3,1,2,7'b0000001); // mul x3,x1,x2
        imem[3]  = sw_inst(3,0,0);
        imem[4]  = lw_inst(4,0,0);
        imem[5]  = addi_inst(5,4,1);
        imem[6]  = beq_inst(5,5,8);
        imem[7]  = sw_inst(5,0,'h300); // must be flushed
        imem[8]  = sw_inst(5,0,4);
        imem[9]  = r_inst(3'b100,6,5,2,7'b0000001); // div x6,x5,x2
        imem[10] = sw_inst(6,0,8);
        imem[11] = addi_inst(7,0,127);
        imem[12] = sb_inst(7,0,1); // byte lane 1, WSTRB=0010
        imem[13] = lbu_inst(8,0,1);
        imem[14] = sw_inst(8,0,12);
        imem[15] = addi_inst(31,0,1);
        imem[16] = sw_inst(31,0,'h3fc);
        imem[17] = 32'h0000006f; // jal x0,0
        repeat (4) @(posedge clk);
        @(negedge clk) reset = 0;
    end
endmodule
