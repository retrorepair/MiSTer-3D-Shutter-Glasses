// Copyright (c) 2026 Jamie Blanks

// Iterative NEC V810 unit for MUL, DIV, MPYHW, and REV. The parent owns timing
// and commit.
module necv810_integer_engine
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        clk_en_i,
	input  wire        phi1_i,
	input  wire        start_i,
	input  wire        kill_i,
	input  wire        finish_i,
	input  wire [3:0]  kind_i,
	input  wire [31:0] lhs_i,
	input  wire [31:0] rhs_i,
	output wire        start_accept_o,
	output wire        busy_o,
	output wire        done_o,
	output wire [5:0]  step_o,
	output wire [31:0] result_hi_o,
	output wire [31:0] result_lo_o,
	output wire        result_zero_o,
	output wire        result_sign_o,
	output wire        result_overflow_o
);

	localparam [3:0] LONG_REV   = 4'd4;
	localparam [3:0] LONG_MPYHW = 4'd5;
	localparam [3:0] LONG_MUL   = 4'd12;
	localparam [3:0] LONG_DIV   = 4'd13;
	localparam [3:0] LONG_MULU  = 4'd14;
	localparam [3:0] LONG_DIVU  = 4'd15;

	reg        busy_q;
	reg        done_q;
	reg [3:0]  kind_q;
	reg [5:0]  step_q;
	reg        negate_q;
	reg        rem_negate_q;
	reg        mul_prep_q;
	reg [63:0] acc_q;
	reg [63:0] addend_q;
	reg [63:0] multiplicand_q;
	reg [63:0] multiplicand3_q;
	reg [31:0] multiplier_q;
	reg [31:0] divisor_q;
	reg [31:0] quot_q;
	reg [31:0] rem_q;
	reg [31:0] shift_q;
	reg [31:0] reverse_q;
	reg [31:0] result_hi_q;
	reg [31:0] result_lo_q;
	reg        result_zero_q;
	reg        result_sign_q;
	reg        result_overflow_q;

	wire        mul_kind_w = (kind_q == LONG_MUL) || (kind_q == LONG_MULU) ||
		(kind_q == LONG_MPYHW);
	wire [5:0]  mul_steps_w = (kind_q == LONG_MPYHW) ? 6'd5 : 6'd8;
	wire [63:0] product_final_w = negate_q ? neg64_fn(acc_q) : acc_q;
	wire [32:0] div_shift_rem_w = {rem_q, quot_q[31]};
	wire [31:0] div_shift_quot_w = {quot_q[30:0], 1'b0};
	wire        div_subtract_w = div_shift_rem_w >= {1'b0, divisor_q};
	wire [31:0] div_next_rem_w = div_subtract_w ?
		(div_shift_rem_w[31:0] - divisor_q) : div_shift_rem_w[31:0];
	wire [31:0] div_next_quot_w = div_shift_quot_w |
		{31'd0, div_subtract_w};
	wire [31:0] div_final_quot_w = negate_q ? neg32_fn(quot_q) : quot_q;
	wire [31:0] div_final_rem_w = rem_negate_q ? neg32_fn(rem_q) : rem_q;

	assign start_accept_o = clk_en_i && start_i && !busy_q;
	assign busy_o = busy_q;
	assign done_o = done_q;
	assign step_o = step_q;
	assign result_hi_o = result_hi_q;
	assign result_lo_o = result_lo_q;
	assign result_zero_o = result_zero_q;
	assign result_sign_o = result_sign_q;
	assign result_overflow_o = result_overflow_q;

	always @(posedge clk_i or posedge reset_i) begin
		if (reset_i) begin
			busy_q <= 1'b0;
			done_q <= 1'b0;
			kind_q <= 4'd0;
			step_q <= 6'd0;
			negate_q <= 1'b0;
			rem_negate_q <= 1'b0;
			mul_prep_q <= 1'b0;
			acc_q <= 64'd0;
			addend_q <= 64'd0;
			multiplicand_q <= 64'd0;
			multiplicand3_q <= 64'd0;
			multiplier_q <= 32'd0;
			divisor_q <= 32'd0;
			quot_q <= 32'd0;
			rem_q <= 32'd0;
			shift_q <= 32'd0;
			reverse_q <= 32'd0;
			result_hi_q <= 32'd0;
			result_lo_q <= 32'd0;
			result_zero_q <= 1'b0;
			result_sign_q <= 1'b0;
			result_overflow_q <= 1'b0;
		end else begin
			// Form a radix-16 digit on phi1, then add it on CE.
			if (phi1_i && busy_q && !done_q && mul_kind_w &&
				(step_q < mul_steps_w)) begin
				if (!mul_prep_q) begin
					// Precompute 3X so each radix-16 digit needs one 64-bit add.
					multiplicand3_q <=
						(multiplicand_q << 1) + multiplicand_q;
				end else begin
					addend_q <= mul_digit_fn(
						multiplicand_q, multiplicand3_q,
						multiplier_q[3:0]);
				end
			end

			if (clk_en_i) begin
				if (kill_i) begin
					busy_q <= 1'b0;
					done_q <= 1'b0;
				end else if (start_i && !busy_q) begin
					busy_q <= 1'b1;
					done_q <= 1'b0;
					kind_q <= kind_i;
					step_q <= 6'd0;
					negate_q <= 1'b0;
					rem_negate_q <= 1'b0;
					mul_prep_q <= 1'b0;
					acc_q <= 64'd0;
					addend_q <= 64'd0;
					multiplicand_q <= 64'd0;
					multiplicand3_q <= 64'd0;
					multiplier_q <= 32'd0;
					divisor_q <= 32'd0;
					quot_q <= 32'd0;
					rem_q <= 32'd0;
					shift_q <= 32'd0;
					reverse_q <= 32'd0;
					result_hi_q <= 32'd0;
					result_lo_q <= 32'd0;
					result_zero_q <= 1'b0;
					result_sign_q <= 1'b0;
					result_overflow_q <= 1'b0;
					case (kind_i)
						LONG_MUL: begin
							negate_q <= lhs_i[31] ^ rhs_i[31];
							multiplicand_q <= {32'd0, abs32_fn(lhs_i)};
							multiplier_q <= abs32_fn(rhs_i);
						end

						LONG_MULU: begin
							multiplicand_q <= {32'd0, lhs_i};
							multiplier_q <= rhs_i;
						end

						LONG_MPYHW: begin
							negate_q <= lhs_i[31] ^ rhs_i[16];
							multiplicand_q <= {32'd0, abs32_fn(lhs_i)};
							multiplier_q <= abs32_fn(mpyhw_rhs_fn(rhs_i[16:0]));
						end

						LONG_DIV: begin
							if ((lhs_i == 32'h8000_0000) &&
								(rhs_i == 32'hffff_ffff)) begin
								result_hi_q <= 32'd0;
								result_lo_q <= 32'h8000_0000;
								result_zero_q <= 1'b0;
								result_sign_q <= 1'b1;
								result_overflow_q <= 1'b1;
								done_q <= 1'b1;
							end else begin
								negate_q <= lhs_i[31] ^ rhs_i[31];
								rem_negate_q <= lhs_i[31];
								quot_q <= abs32_fn(lhs_i);
								divisor_q <= abs32_fn(rhs_i);
							end
						end

						LONG_DIVU: begin
							quot_q <= lhs_i;
							divisor_q <= rhs_i;
						end

						LONG_REV: begin
							shift_q <= rhs_i;
						end

						default: begin
							busy_q <= 1'b0;
							done_q <= 1'b0;
						end
					endcase
				end else if (finish_i) begin
					busy_q <= 1'b0;
					done_q <= 1'b0;
				end else if (busy_q && !done_q) begin
					case (kind_q)
						LONG_MUL,
						LONG_MULU,
						LONG_MPYHW: begin
							if (!mul_prep_q) begin
								mul_prep_q <= 1'b1;
							end else if (step_q < mul_steps_w) begin
								acc_q <= acc_q + addend_q;
								multiplicand_q <= multiplicand_q << 4;
								multiplicand3_q <= multiplicand3_q << 4;
								multiplier_q <= {4'd0, multiplier_q[31:4]};
								step_q <= step_q + 6'd1;
							end else begin
								result_hi_q <= product_final_w[63:32];
								result_lo_q <= product_final_w[31:0];
								result_zero_q <= (product_final_w[31:0] == 32'd0);
								result_sign_q <= product_final_w[31];
								if (kind_q == LONG_MUL) begin
									result_overflow_q <=
										(product_final_w[63:32] != {32{product_final_w[31]}});
								end else begin
									result_overflow_q <= (product_final_w[63:32] != 32'd0);
								end
								done_q <= 1'b1;
							end
						end

						LONG_DIV,
						LONG_DIVU: begin
							if (step_q < 6'd32) begin
								rem_q <= div_next_rem_w;
								quot_q <= div_next_quot_w;
								step_q <= step_q + 6'd1;
							end else begin
								result_hi_q <= div_final_rem_w;
								result_lo_q <= div_final_quot_w;
								result_zero_q <= (div_final_quot_w == 32'd0);
								result_sign_q <= div_final_quot_w[31];
								result_overflow_q <= 1'b0;
								done_q <= 1'b1;
							end
						end

						LONG_REV: begin
							if (step_q < 6'd16) begin
								reverse_q <= {
									reverse_q[29:0], shift_q[0], shift_q[1]};
								shift_q <= {2'd0, shift_q[31:2]};
								step_q <= step_q + 6'd1;
							end else begin
								result_lo_q <= reverse_q;
								done_q <= 1'b1;
							end
						end

						default: begin
							busy_q <= 1'b0;
						end
					endcase
				end
			end
		end
	end

	function [31:0] abs32_fn;
		input [31:0] value;
		begin
			abs32_fn = value[31] ? neg32_fn(value) : value;
		end
	endfunction

	function [31:0] neg32_fn;
		input [31:0] value;
		begin
			neg32_fn = (~value) + 32'd1;
		end
	endfunction

	function [63:0] neg64_fn;
		input [63:0] value;
		begin
			neg64_fn = (~value) + 64'd1;
		end
	endfunction

	function [31:0] mpyhw_rhs_fn;
		input [16:0] value;
		begin
			mpyhw_rhs_fn = {{15{value[16]}}, value};
		end
	endfunction

	function [63:0] mul_digit_fn;
		input [63:0] multiplicand;
		input [63:0] multiplicand3;
		input [3:0]  digit;
		reg [63:0] low_v;
		reg [63:0] high_v;
		begin
			case (digit[1:0])
				2'd0: low_v = 64'd0;
				2'd1: low_v = multiplicand;
				2'd2: low_v = multiplicand << 1;
				default: low_v = multiplicand3;
			endcase
			case (digit[3:2])
				2'd0: high_v = 64'd0;
				2'd1: high_v = multiplicand << 2;
				2'd2: high_v = multiplicand << 3;
				default: high_v = multiplicand3 << 2;
			endcase
			mul_digit_fn = low_v + high_v;
		end
	endfunction

endmodule
