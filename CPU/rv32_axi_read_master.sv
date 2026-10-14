// AXI4 single-beat, single-outstanding 32-bit read master.
module rv32_axi_read_master (
    input  logic clk, reset,
    input  logic req_valid,
    output logic req_ready,
    input  logic [31:0] req_addr,
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
    input  logic rlast,
    input  logic rvalid,
    output logic rready
);
    typedef enum logic [1:0] {IDLE, SEND_AR, WAIT_R} state_t;
    state_t state_q;
    assign req_ready = (state_q == IDLE) && !resp_valid;
    assign arvalid = (state_q == SEND_AR);
    assign rready = (state_q == WAIT_R);
    assign arid = '0;
    assign arlen = 8'd0;
    assign arsize = 3'd2;
    assign arburst = 2'b01;

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= IDLE;
            araddr <= '0;
            resp_valid <= 1'b0;
            resp_data <= '0;
            resp_error <= 1'b0;
        end else begin
            resp_valid <= 1'b0;
            case (state_q)
                IDLE: if (req_valid && req_ready) begin
                    araddr <= req_addr;
                    state_q <= SEND_AR;
                end
                SEND_AR: if (arvalid && arready) state_q <= WAIT_R;
                WAIT_R: if (rvalid && rready) begin
                    resp_data <= rdata;
                    resp_error <= (rresp != 2'b00) || !rlast || (rid != 4'd0);
                    resp_valid <= 1'b1;
                    state_q <= IDLE;
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
