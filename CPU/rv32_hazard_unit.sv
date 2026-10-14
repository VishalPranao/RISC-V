module rv32_hazard_unit (
    // Instruction currently in ID
    input logic       if_id_valid,
    input logic       id_uses_rs1,
    input logic       id_uses_rs2,
    input logic [4:0] id_rs1,
    input logic [4:0] id_rs2,

    // Instruction currently in EX
    input logic       id_ex_valid,
    input logic       id_ex_mem_read,
    input logic [4:0] id_ex_rd,

    // Branch or jump redirect from EX
    input logic       ex_redirect,

    output logic      pc_stall,
    output logic      if_id_stall,
    output logic      if_id_flush,
    output logic      id_ex_flush
);

    logic load_use_hazard;

    always_comb begin
        load_use_hazard =
            if_id_valid &&
            id_ex_valid &&
            id_ex_mem_read &&
            (id_ex_rd != 5'd0) &&
            (
                (id_uses_rs1 && (id_rs1 == id_ex_rd)) ||
                (id_uses_rs2 && (id_rs2 == id_ex_rd))
            );    // the first condition checks if the inst are valid but the second one check if ID rs1 is same as EX later inst Rd. 

        pc_stall   = 1'b0;
        if_id_stall = 1'b0;
        if_id_flush = 1'b0;
        id_ex_flush = 1'b0;

        /*
         * Redirect has priority over a stall because instructions in IF
         * and ID are from the wrong execution path.
         */
        if (ex_redirect) begin
            if_id_flush = 1'b1;
            id_ex_flush = 1'b1;
        end
        else if (load_use_hazard) begin
            pc_stall    = 1'b1;
            if_id_stall = 1'b1;
            id_ex_flush = 1'b1;
        end
    end

endmodule