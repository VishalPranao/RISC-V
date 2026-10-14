// One restoring division bit per cycle. start is accepted only when idle.
// The result appears with done for one cycle; the in-order core holds its EX
// instruction until that cycle and inserts bubbles behind older instructions.
module rv32_m_divider (
    input  logic clk, reset, start,
    input  logic [31:0] dividend, divisor,
    input  logic signed_operation, want_remainder,
    output logic busy, done,
    output logic [31:0] result
);
    logic [31:0] quotient_q, divisor_q;
    logic [32:0] remainder_q;
    logic [5:0] bits_left_q;
    logic negate_quotient_q, negate_remainder_q, want_remainder_q;
    logic [31:0] dividend_abs, divisor_abs;
    logic [32:0] trial_remainder;
    logic [31:0] quotient_next, remainder_next;
    logic [31:0] quotient_signed, remainder_signed;

    always_comb begin
        dividend_abs = (signed_operation && dividend[31]) ?
                       (~dividend + 32'd1) : dividend;
        divisor_abs  = (signed_operation && divisor[31]) ?
                       (~divisor + 32'd1) : divisor;
        trial_remainder = {remainder_q[31:0], quotient_q[31]};
        quotient_next = {quotient_q[30:0], 1'b0};
        if (trial_remainder >= {1'b0, divisor_q}) begin
            trial_remainder = trial_remainder - {1'b0, divisor_q};
            quotient_next[0] = 1'b1;
        end
        remainder_next = trial_remainder[31:0];
        quotient_signed = negate_quotient_q ? (~quotient_next + 32'd1) : quotient_next;
        remainder_signed = negate_remainder_q ? (~remainder_next + 32'd1) : remainder_next;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            busy <= 1'b0;
            done <= 1'b0;
            result <= 32'b0;
            quotient_q <= 32'b0;
            divisor_q <= 32'b0;
            remainder_q <= 33'b0;
            bits_left_q <= 6'b0;
            negate_quotient_q <= 1'b0;
            negate_remainder_q <= 1'b0;
            want_remainder_q <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                if (divisor == 32'b0) begin
                    result <= want_remainder ? dividend : 32'hffff_ffff;
                    done <= 1'b1;
                end else begin
                    quotient_q <= dividend_abs;
                    divisor_q <= divisor_abs;
                    remainder_q <= 33'b0;
                    bits_left_q <= 6'd32;
                    negate_quotient_q <= signed_operation && (dividend[31] ^ divisor[31]);
                    negate_remainder_q <= signed_operation && dividend[31];
                    want_remainder_q <= want_remainder;
                    busy <= 1'b1;
                end
            end else if (busy) begin
                quotient_q <= quotient_next;
                remainder_q <= trial_remainder;
                bits_left_q <= bits_left_q - 6'd1;
                if (bits_left_q == 6'd1) begin
                    result <= want_remainder_q ? remainder_signed : quotient_signed;
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end
endmodule
