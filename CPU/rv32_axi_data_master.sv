// AXI4 single-beat 32-bit data master; AW and W handshakes are independent.
module rv32_axi_data_master (
    input  logic clk, reset,
    input  logic req_valid,
    output logic req_ready,
    input  logic req_write,
    input  logic [31:0] req_addr, req_wdata,
    input  logic [3:0] req_wstrb,
    output logic resp_valid,
    output logic [31:0] resp_data,
    output logic resp_error,
    output logic [3:0] arid,
    output logic [31:0] araddr,
    output logic [7:0] arlen,
    output logic [2:0] arsize,
    output logic [1:0] arburst,
    output logic arvalid,
    input  logic arready,
    input  logic [3:0] rid,
    input  logic [31:0] rdata,
    input  logic [1:0] rresp,
    input  logic rlast, rvalid,
    output logic rready,
    output logic [3:0] awid,
    output logic [31:0] awaddr,
    output logic [7:0] awlen,
    output logic [2:0] awsize,
    output logic [1:0] awburst,
    output logic awvalid,
    input  logic awready,
    output logic [31:0] wdata,
    output logic [3:0] wstrb,
    output logic wlast, wvalid,
    input  logic wready,
    input  logic [3:0] bid,
    input  logic [1:0] bresp,
    input  logic bvalid,
    output logic bready
);
    typedef enum logic [2:0] {IDLE, SEND_AR, WAIT_R, SEND_AW_W, WAIT_B} state_t;
    state_t state_q;
    logic aw_pending_q, w_pending_q;

    assign req_ready = (state_q == IDLE) && !resp_valid;
    assign arvalid = (state_q == SEND_AR);
    assign rready = (state_q == WAIT_R);
    assign awvalid = (state_q == SEND_AW_W) && aw_pending_q;
    assign wvalid = (state_q == SEND_AW_W) && w_pending_q;
    assign bready = (state_q == WAIT_B);
    assign arid = '0;
    assign awid = '0;
    assign arlen = 8'd0;
    assign awlen = 8'd0;
    assign arsize = 3'd2;
    assign awsize = 3'd2;
    assign arburst = 2'b01;
    assign awburst = 2'b01;
    assign wlast = 1'b1;

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= IDLE;
            araddr <= '0;
            awaddr <= '0;
            wdata <= '0;
            wstrb <= '0;
            aw_pending_q <= 1'b0;
            w_pending_q <= 1'b0;
            resp_valid <= 1'b0;
            resp_data <= '0;
            resp_error <= 1'b0;
        end else begin
            resp_valid <= 1'b0;
            case (state_q)
                IDLE: if (req_valid && req_ready) begin
                    if (req_write) begin
                        awaddr <= req_addr;
                        wdata <= req_wdata;
                        wstrb <= req_wstrb;
                        aw_pending_q <= 1'b1;
                        w_pending_q <= 1'b1;
                        state_q <= SEND_AW_W;
                    end else begin
                        araddr <= req_addr;
                        state_q <= SEND_AR;
                    end
                end
                SEND_AR: if (arvalid && arready) state_q <= WAIT_R;
                WAIT_R: if (rvalid && rready) begin
                    resp_data <= rdata;
                    resp_error <= (rresp != 2'b00) || !rlast || (rid != 4'd0);
                    resp_valid <= 1'b1;
                    state_q <= IDLE;
                end
                SEND_AW_W: begin
                    if (awvalid && awready) aw_pending_q <= 1'b0;
                    if (wvalid && wready) w_pending_q <= 1'b0;
                    if ((!aw_pending_q || awready) &&
                        (!w_pending_q || wready)) state_q <= WAIT_B;
                end
                WAIT_B: if (bvalid && bready) begin
                    resp_data <= '0;
                    resp_error <= (bresp != 2'b00) || (bid != 4'd0);
                    resp_valid <= 1'b1;
                    state_q <= IDLE;
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
