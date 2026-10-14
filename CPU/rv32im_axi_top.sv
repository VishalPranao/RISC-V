// Two independent AXI4 master ports. External interconnect/RAM is separate.
module rv32im_axi_top (
    input logic clk, reset,
    output logic bus_error,
    output logic [3:0] i_arid,
    output logic [31:0] i_araddr,
    output logic [7:0] i_arlen,
    output logic [2:0] i_arsize,
    output logic [1:0] i_arburst,
    output logic i_arlock,
    output logic [3:0] i_arcache, i_arqos, i_arregion,
    output logic [2:0] i_arprot,
    output logic i_arvalid,
    input logic i_arready,
    input logic [3:0] i_rid,
    input logic [31:0] i_rdata,
    input logic [1:0] i_rresp,
    input logic i_rlast, i_rvalid,
    output logic i_rready,
    output logic [3:0] d_arid,
    output logic [31:0] d_araddr,
    output logic [7:0] d_arlen,
    output logic [2:0] d_arsize,
    output logic [1:0] d_arburst,
    output logic d_arlock,
    output logic [3:0] d_arcache, d_arqos, d_arregion,
    output logic [2:0] d_arprot,
    output logic d_arvalid,
    input logic d_arready,
    input logic [3:0] d_rid,
    input logic [31:0] d_rdata,
    input logic [1:0] d_rresp,
    input logic d_rlast, d_rvalid,
    output logic d_rready,
    output logic [3:0] d_awid,
    output logic [31:0] d_awaddr,
    output logic [7:0] d_awlen,
    output logic [2:0] d_awsize,
    output logic [1:0] d_awburst,
    output logic d_awlock,
    output logic [3:0] d_awcache, d_awqos, d_awregion,
    output logic [2:0] d_awprot,
    output logic d_awvalid,
    input logic d_awready,
    output logic [31:0] d_wdata,
    output logic [3:0] d_wstrb,
    output logic d_wlast, d_wvalid,
    input logic d_wready,
    input logic [3:0] d_bid,
    input logic [1:0] d_bresp,
    input logic d_bvalid,
    output logic d_bready
);
    logic i_req_valid, i_req_ready, i_resp_valid, i_resp_error;
    logic [31:0] i_req_addr, i_resp_data;
    logic d_req_valid, d_req_ready, d_req_write;
    logic [31:0] d_req_addr, d_req_wdata, d_resp_data;
    logic [3:0] d_req_wstrb;
    logic d_resp_valid, d_resp_error;

    // Fixed unprivileged, secure, data accesses and non-cached attributes.
    // The AXI adapters perform no caching, protection checks, or bursting.
    assign i_arlock = 1'b0;
    assign d_arlock = 1'b0;
    assign d_awlock = 1'b0;
    assign i_arcache = 4'b0000;
    assign d_arcache = 4'b0000;
    assign d_awcache = 4'b0000;
    assign i_arprot = 3'b100;
    assign d_arprot = 3'b000;
    assign d_awprot = 3'b000;
    assign i_arqos = 4'b0000;
    assign d_arqos = 4'b0000;
    assign d_awqos = 4'b0000;
    assign i_arregion = 4'b0000;
    assign d_arregion = 4'b0000;
    assign d_awregion = 4'b0000;

    rv32_pipeline_core_axi core (
        .clk, .reset, .bus_error,
        .i_req_valid, .i_req_ready, .i_req_addr,
        .i_resp_valid, .i_resp_data, .i_resp_error,
        .d_req_valid, .d_req_ready, .d_req_write, .d_req_addr,
        .d_req_wdata, .d_req_wstrb,
        .d_resp_valid, .d_resp_data, .d_resp_error
    );
    rv32_axi_read_master instruction_master (
        .clk, .reset, .req_valid(i_req_valid), .req_ready(i_req_ready),
        .req_addr(i_req_addr), .resp_valid(i_resp_valid),
        .resp_data(i_resp_data), .resp_error(i_resp_error),
        .arid(i_arid), .araddr(i_araddr), .arlen(i_arlen),
        .arsize(i_arsize), .arburst(i_arburst), .arvalid(i_arvalid),
        .arready(i_arready), .rid(i_rid), .rdata(i_rdata),
        .rresp(i_rresp), .rlast(i_rlast), .rvalid(i_rvalid),
        .rready(i_rready)
    );
    rv32_axi_data_master data_master (
        .clk, .reset, .req_valid(d_req_valid), .req_ready(d_req_ready),
        .req_write(d_req_write), .req_addr(d_req_addr),
        .req_wdata(d_req_wdata), .req_wstrb(d_req_wstrb),
        .resp_valid(d_resp_valid), .resp_data(d_resp_data),
        .resp_error(d_resp_error),
        .arid(d_arid), .araddr(d_araddr), .arlen(d_arlen),
        .arsize(d_arsize), .arburst(d_arburst), .arvalid(d_arvalid),
        .arready(d_arready), .rid(d_rid), .rdata(d_rdata),
        .rresp(d_rresp), .rlast(d_rlast), .rvalid(d_rvalid),
        .rready(d_rready),
        .awid(d_awid), .awaddr(d_awaddr), .awlen(d_awlen),
        .awsize(d_awsize), .awburst(d_awburst), .awvalid(d_awvalid),
        .awready(d_awready), .wdata(d_wdata), .wstrb(d_wstrb),
        .wlast(d_wlast), .wvalid(d_wvalid), .wready(d_wready),
        .bid(d_bid), .bresp(d_bresp), .bvalid(d_bvalid),
        .bready(d_bready)
    );
endmodule
