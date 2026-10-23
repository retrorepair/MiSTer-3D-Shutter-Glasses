// Copyright (c) 2026 Jamie Blanks

// Iterative NEC V810 single-precision floating-point engine. The parent owns
// instruction timing and commit.
module necv810_fp_engine
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        clk_en_i,
	input  wire        phi1_i,
	input  wire        start_i,
	input  wire        kill_i,
	input  wire        finish_i,
	input  wire [5:0]  subop_i,
	input  wire [31:0] lhs_i,
	input  wire [31:0] rhs_i,
	output wire        start_accept_o,
	output wire        busy_o,
	output wire        done_o,
	output wire [5:0]  step_o,
	output wire [31:0] result_o,
	output wire        result_we_o,
	output wire [9:0]  psw_mask_o,
	output wire [9:0]  psw_data_o,
	output wire        exception_valid_o,
	output wire [15:0] exception_code_o
);

	localparam [5:0] SUBOP_CMPF   = 6'b000000;
	localparam [5:0] SUBOP_CVTWS  = 6'b000010;
	localparam [5:0] SUBOP_CVTSW  = 6'b000011;
	localparam [5:0] SUBOP_ADDF   = 6'b000100;
	localparam [5:0] SUBOP_SUBF   = 6'b000101;
	localparam [5:0] SUBOP_MULF   = 6'b000110;
	localparam [5:0] SUBOP_DIVF   = 6'b000111;
	localparam [5:0] SUBOP_TRNCSW = 6'b001011;

	localparam [3:0] ST_CLASSIFY = 4'd1;
	localparam [3:0] ST_ALIGN    = 4'd2;
	localparam [3:0] ST_ARITH    = 4'd3;
	localparam [3:0] ST_NORM     = 4'd4;
	localparam [3:0] ST_MUL      = 4'd5;
	localparam [3:0] ST_DIV      = 4'd6;
	localparam [3:0] ST_PACK     = 4'd7;
	localparam [3:0] ST_DONE     = 4'd8;
	localparam [3:0] ST_UNDERFLOW = 4'd9;

	localparam [9:0] PSW_FRO_MASK = 10'h200;
	localparam [9:0] PSW_FIV_MASK = 10'h100;
	localparam [9:0] PSW_FZD_MASK = 10'h080;
	localparam [9:0] PSW_FOV_MASK = 10'h040;
	localparam [9:0] PSW_FUD_MASK = 10'h020;
	localparam [9:0] PSW_FPR_MASK = 10'h010;
	localparam [9:0] PSW_CY_MASK  = 10'h008;
	localparam [9:0] PSW_OV_MASK  = 10'h004;
	localparam [9:0] PSW_S_MASK   = 10'h002;
	localparam [9:0] PSW_Z_MASK   = 10'h001;
	localparam [9:0] PSW_FP_DIRECT_MASK =
		PSW_CY_MASK | PSW_OV_MASK | PSW_S_MASK | PSW_Z_MASK;
	localparam [9:0] PSW_CVT_DIRECT_MASK =
		PSW_OV_MASK | PSW_S_MASK | PSW_Z_MASK;

	localparam [15:0] EXC_CODE_FRO = 16'hff60;
	localparam [15:0] EXC_CODE_FOV = 16'hff64;
	localparam [15:0] EXC_CODE_FZD = 16'hff68;
	localparam [15:0] EXC_CODE_FIV = 16'hff70;

	reg        busy_q;
	reg        done_q;
	reg [3:0]  stage_q;
	reg [5:0]  step_q;
	reg [5:0]  subop_q;
	reg [31:0] lhs_q;
	reg [31:0] rhs_q;

	reg        add_q;
	reg        add_sign_q;
	reg signed [10:0] add_exp_q;
	reg [5:0]  add_shift_rem_q;
	reg [31:0] add_sig_hi_q;
	reg [31:0] add_sig_lo_q;
	reg [31:0] add_norm_q;

	reg        mul_sign_q;
	reg signed [10:0] mul_exp_q;
	reg [63:0] mul_multiplicand_q;
	reg [63:0] mul_multiplicand3_q;
	reg [23:0] mul_multiplier_q;
	reg [63:0] mul_acc_q;
	reg [63:0] mul_addend_q;
	reg        mul_prep_q;

	reg        div_sign_q;
	reg signed [10:0] div_exp_q;
	reg [23:0] div_den_q;
	reg [27:0] div_quot_q;
	reg [24:0] div_rem_q;

	reg        pack_sign_q;
	reg signed [10:0] pack_exp_q;
	reg [31:0] pack_norm_q;
	reg        pack_div_underflow_q;
	reg        pack_underflow_shifted_q;
	reg [5:0]  pack_shift_rem_q;

	reg [31:0] result_q;
	reg        result_we_q;
	reg [9:0]  psw_mask_q;
	reg [9:0]  psw_data_q;
	reg        exception_valid_q;
	reg [15:0] exception_code_q;

	wire        lhs_zero_w = fp_is_zero_fn(lhs_q[30:0]);
	wire        rhs_zero_w = fp_is_zero_fn(rhs_q[30:0]);
	wire        lhs_reserved_w = fp_reserved_operand_fn(lhs_q[30:0]);
	wire        rhs_reserved_w = fp_reserved_operand_fn(rhs_q[30:0]);
	wire        arithmetic_reserved_w = lhs_reserved_w || rhs_reserved_w;
	wire        add_rhs_sign_w = rhs_q[31] ^ (subop_q == SUBOP_SUBF);
	wire [31:0] add_lhs_sig_w = lhs_zero_w ?
		32'd0 : {5'd0, 1'b1, lhs_q[22:0], 3'b000};
	wire [31:0] add_rhs_sig_w = rhs_zero_w ?
		32'd0 : {5'd0, 1'b1, rhs_q[22:0], 3'b000};
	wire [8:0]  add_exp_delta_lhs_w =
		{1'b0, lhs_q[30:23]} - {1'b0, rhs_q[30:23]};
	wire [8:0]  add_exp_delta_rhs_w =
		{1'b0, rhs_q[30:23]} - {1'b0, lhs_q[30:23]};
	wire [2:0]  add_shift_chunk_w =
		(add_shift_rem_q > 6'd4) ? 3'd4 : add_shift_rem_q[2:0];
	wire [31:0] cvt_result_w = (subop_q == SUBOP_TRNCSW) ?
		fp_to_int_trunc_fn(rhs_q) : fp_to_int_nearest_fn(rhs_q);
	wire [31:0] int_float_result_w = fp_from_int_fn(rhs_q);
	wire        cvt_invalid_w = fp_to_int_invalid_fn(rhs_q);
	wire        cvt_fpr_w = fp_to_int_fpr_fn(rhs_q[30:0]);
	wire        int_float_fpr_w = fp_from_int_fpr_fn(rhs_q);

	wire [24:0] div_shift_rem_w = {div_rem_q[23:0], 1'b0};
	wire [27:0] div_shift_quot_w =
		{div_quot_q[27], div_quot_q[25:0], 1'b0};
	wire        div_subtract_w = div_shift_rem_w >= {1'b0, div_den_q};
	wire [24:0] div_next_rem_w = div_subtract_w ?
		(div_shift_rem_w - {1'b0, div_den_q}) : div_shift_rem_w;
	wire [27:0] div_next_quot_w = div_shift_quot_w |
		{27'd0, div_subtract_w};
	wire [42:0] mul_norm_bundle_w =
		fp_mul_norm_from_prod_fn(mul_exp_q, mul_acc_q[47:0]);
	wire [42:0] div_norm_bundle_w =
		fp_div_norm_from_qrem_fn(div_exp_q, div_quot_q, div_rem_q);
	wire [2:0] pack_shift_chunk_w =
		(pack_shift_rem_q > 6'd4) ? 3'd4 : pack_shift_rem_q[2:0];
	wire signed [11:0] pack_exp_ext_w = {pack_exp_q[10], pack_exp_q};
	wire [11:0] pack_underflow_shift_w = 12'd1 - pack_exp_ext_w;
	wire [24:0] pack_mant_base_w = {1'b0, pack_norm_q[26:3]};
	wire        pack_round_w = pack_norm_q[2] &&
		(pack_norm_q[1] || pack_norm_q[0] || pack_mant_base_w[0]);
	wire [24:0] pack_mant_rounded_w =
		pack_mant_base_w + {24'd0, pack_round_w};
	wire        pack_fpr_w = (pack_norm_q[2:0] != 3'd0);
	wire signed [11:0] pack_exp_rounded_w = pack_exp_ext_w +
		(pack_mant_rounded_w[24] ? 12'sd1 : 12'sd0);
	wire [22:0] pack_normal_mant_w = pack_mant_rounded_w[24] ?
		pack_mant_rounded_w[23:1] : pack_mant_rounded_w[22:0];
	wire [7:0] pack_corrected_exp_w =
		pack_exp_rounded_w[7:0] - 8'd192;
	wire [31:0] pack_underflow_result_w = pack_mant_rounded_w[23] ?
		{pack_sign_q, 8'd1, 23'd0} :
		{pack_sign_q, 8'd0, pack_mant_rounded_w[22:0]};
	wire [31:0] pack_overflow_result_w =
		{pack_sign_q, pack_corrected_exp_w, pack_normal_mant_w};
	wire [31:0] pack_normal_result_w =
		{pack_sign_q, pack_exp_rounded_w[7:0], pack_normal_mant_w};

	assign start_accept_o = clk_en_i && start_i && !busy_q;
	assign busy_o = busy_q;
	assign done_o = done_q;
	assign step_o = step_q;
	assign result_o = result_q;
	assign result_we_o = result_we_q;
	assign psw_mask_o = psw_mask_q;
	assign psw_data_o = psw_data_q;
	assign exception_valid_o = exception_valid_q;
	assign exception_code_o = exception_code_q;

	always @(posedge clk_i or posedge reset_i) begin
		if (reset_i) begin
			busy_q <= 1'b0;
			done_q <= 1'b0;
			stage_q <= ST_DONE;
			step_q <= 6'd0;
			subop_q <= 6'd0;
			lhs_q <= 32'd0;
			rhs_q <= 32'd0;
			add_q <= 1'b0;
			add_sign_q <= 1'b0;
			add_exp_q <= 11'sd0;
			add_shift_rem_q <= 6'd0;
			add_sig_hi_q <= 32'd0;
			add_sig_lo_q <= 32'd0;
			add_norm_q <= 32'd0;
			mul_sign_q <= 1'b0;
			mul_exp_q <= 11'sd0;
			mul_multiplicand_q <= 64'd0;
			mul_multiplicand3_q <= 64'd0;
			mul_multiplier_q <= 24'd0;
			mul_acc_q <= 64'd0;
			mul_addend_q <= 64'd0;
			mul_prep_q <= 1'b0;
			div_sign_q <= 1'b0;
			div_exp_q <= 11'sd0;
			div_den_q <= 24'd0;
			div_quot_q <= 28'd0;
			div_rem_q <= 25'd0;
			pack_sign_q <= 1'b0;
			pack_exp_q <= 11'sd0;
			pack_norm_q <= 32'd0;
			pack_div_underflow_q <= 1'b0;
			pack_underflow_shifted_q <= 1'b0;
			pack_shift_rem_q <= 6'd0;
			result_q <= 32'd0;
			result_we_q <= 1'b0;
			psw_mask_q <= 10'd0;
			psw_data_q <= 10'd0;
			exception_valid_q <= 1'b0;
			exception_code_q <= 16'd0;
		end else begin
			// Form the next radix-16 digit on the half-cycle edge.
			if (phi1_i && busy_q && !done_q && (stage_q == ST_MUL) &&
				(step_q < 6'd6)) begin
				if (!mul_prep_q) begin
					// Precompute 3X so each radix-16 digit needs one 64-bit add.
					mul_multiplicand3_q <=
						(mul_multiplicand_q << 1) + mul_multiplicand_q;
				end else begin
					mul_addend_q <= mul_digit_fn(
						mul_multiplicand_q, mul_multiplicand3_q,
						mul_multiplier_q[3:0]);
				end
			end

			if (clk_en_i) begin
				if (kill_i) begin
					busy_q <= 1'b0;
					done_q <= 1'b0;
					stage_q <= ST_DONE;
				end else if (start_i && !busy_q) begin
					busy_q <= 1'b1;
					done_q <= 1'b0;
					stage_q <= ST_CLASSIFY;
					step_q <= 6'd0;
					subop_q <= subop_i;
					lhs_q <= lhs_i;
					rhs_q <= rhs_i;
					add_q <= 1'b0;
					add_sign_q <= 1'b0;
					add_exp_q <= 11'sd0;
					add_shift_rem_q <= 6'd0;
					add_sig_hi_q <= 32'd0;
					add_sig_lo_q <= 32'd0;
					add_norm_q <= 32'd0;
					mul_sign_q <= 1'b0;
					mul_exp_q <= 11'sd0;
					mul_multiplicand_q <= 64'd0;
					mul_multiplicand3_q <= 64'd0;
					mul_multiplier_q <= 24'd0;
					mul_acc_q <= 64'd0;
					mul_addend_q <= 64'd0;
					mul_prep_q <= 1'b0;
					div_sign_q <= 1'b0;
					div_exp_q <= 11'sd0;
					div_den_q <= 24'd0;
					div_quot_q <= 28'd0;
					div_rem_q <= 25'd0;
					pack_sign_q <= 1'b0;
					pack_exp_q <= 11'sd0;
					pack_norm_q <= 32'd0;
					pack_div_underflow_q <= 1'b0;
					pack_underflow_shifted_q <= 1'b0;
					pack_shift_rem_q <= 6'd0;
					result_q <= 32'd0;
					result_we_q <= 1'b0;
					psw_mask_q <= 10'd0;
					psw_data_q <= 10'd0;
					exception_valid_q <= 1'b0;
					exception_code_q <= 16'd0;
				end else if (finish_i) begin
					busy_q <= 1'b0;
					done_q <= 1'b0;
					stage_q <= ST_DONE;
				end else if (busy_q && !done_q) begin
					case (stage_q)
						ST_CLASSIFY: begin
							if ((((subop_q == SUBOP_CMPF) ||
								  (subop_q == SUBOP_ADDF) ||
								  (subop_q == SUBOP_SUBF) ||
								  (subop_q == SUBOP_MULF) ||
								  (subop_q == SUBOP_DIVF)) &&
								 arithmetic_reserved_w) ||
								(((subop_q == SUBOP_CVTSW) ||
								  (subop_q == SUBOP_TRNCSW)) && rhs_reserved_w)) begin
								psw_mask_q <= PSW_FRO_MASK;
								psw_data_q <= PSW_FRO_MASK;
								exception_valid_q <= 1'b1;
								exception_code_q <= EXC_CODE_FRO;
								done_q <= 1'b1;
								stage_q <= ST_DONE;
							end else begin
								case (subop_q)
									SUBOP_CMPF: begin
										psw_mask_q <= PSW_FP_DIRECT_MASK;
										psw_data_q <= fp_compare_flags_fn(lhs_q, rhs_q);
										done_q <= 1'b1;
										stage_q <= ST_DONE;
									end

									SUBOP_CVTWS: begin
										result_q <= int_float_result_w;
										result_we_q <= 1'b1;
										psw_mask_q <= PSW_FP_DIRECT_MASK |
											(int_float_fpr_w ? PSW_FPR_MASK : 10'd0);
										psw_data_q <= fp_result_flags_fn(int_float_result_w) |
											(int_float_fpr_w ? PSW_FPR_MASK : 10'd0);
										done_q <= 1'b1;
										stage_q <= ST_DONE;
									end

									SUBOP_CVTSW,
									SUBOP_TRNCSW: begin
										if (cvt_invalid_w) begin
											psw_mask_q <= PSW_FIV_MASK;
											psw_data_q <= PSW_FIV_MASK;
											exception_valid_q <= 1'b1;
											exception_code_q <= EXC_CODE_FIV;
										end else begin
											result_q <= cvt_result_w;
											result_we_q <= 1'b1;
											psw_mask_q <= PSW_CVT_DIRECT_MASK |
												(cvt_fpr_w ? PSW_FPR_MASK : 10'd0);
											psw_data_q <= int_result_flags_fn(cvt_result_w) |
												(cvt_fpr_w ? PSW_FPR_MASK : 10'd0);
										end
										done_q <= 1'b1;
										stage_q <= ST_DONE;
									end

									SUBOP_ADDF,
									SUBOP_SUBF: begin
										if (lhs_zero_w && rhs_zero_w) begin
											result_q <= {
												(lhs_q[31] && add_rhs_sign_w), 31'd0};
											result_we_q <= 1'b1;
											psw_mask_q <= PSW_FP_DIRECT_MASK;
											psw_data_q <= PSW_Z_MASK;
											done_q <= 1'b1;
											stage_q <= ST_DONE;
										end else if (lhs_zero_w) begin
											result_q <= {add_rhs_sign_w, rhs_q[30:0]};
											result_we_q <= 1'b1;
											psw_mask_q <= PSW_FP_DIRECT_MASK;
											psw_data_q <= fp_result_flags_fn(
												{add_rhs_sign_w, rhs_q[30:0]});
											done_q <= 1'b1;
											stage_q <= ST_DONE;
										end else if (rhs_zero_w) begin
											result_q <= lhs_q;
											result_we_q <= 1'b1;
											psw_mask_q <= PSW_FP_DIRECT_MASK;
											psw_data_q <= fp_result_flags_fn(lhs_q);
											done_q <= 1'b1;
											stage_q <= ST_DONE;
										end else begin
											add_q <= (lhs_q[31] == add_rhs_sign_w);
											if (lhs_q[30:23] > rhs_q[30:23]) begin
												add_exp_q <= $signed({3'b000, lhs_q[30:23]});
												add_shift_rem_q <= (add_exp_delta_lhs_w > 9'd32) ?
													6'd32 : add_exp_delta_lhs_w[5:0];
												add_sig_hi_q <= add_lhs_sig_w;
												add_sig_lo_q <= add_rhs_sig_w;
												add_sign_q <= lhs_q[31];
											end else if (rhs_q[30:23] > lhs_q[30:23]) begin
												add_exp_q <= $signed({3'b000, rhs_q[30:23]});
												add_shift_rem_q <= (add_exp_delta_rhs_w > 9'd32) ?
													6'd32 : add_exp_delta_rhs_w[5:0];
												add_sig_hi_q <= add_rhs_sig_w;
												add_sig_lo_q <= add_lhs_sig_w;
												add_sign_q <= add_rhs_sign_w;
											end else if (add_lhs_sig_w >= add_rhs_sig_w) begin
												add_exp_q <= $signed({3'b000, lhs_q[30:23]});
												add_sig_hi_q <= add_lhs_sig_w;
												add_sig_lo_q <= add_rhs_sig_w;
												add_sign_q <= lhs_q[31];
											end else begin
												add_exp_q <= $signed({3'b000, rhs_q[30:23]});
												add_sig_hi_q <= add_rhs_sig_w;
												add_sig_lo_q <= add_lhs_sig_w;
												add_sign_q <= add_rhs_sign_w;
											end
											stage_q <= ST_ALIGN;
										end
									end

									SUBOP_MULF: begin
										if (lhs_zero_w || rhs_zero_w) begin
											result_q <= {lhs_q[31] ^ rhs_q[31], 31'd0};
											result_we_q <= 1'b1;
											psw_mask_q <= PSW_FP_DIRECT_MASK;
											psw_data_q <= PSW_Z_MASK;
											done_q <= 1'b1;
											stage_q <= ST_DONE;
										end else begin
											mul_sign_q <= lhs_q[31] ^ rhs_q[31];
											mul_exp_q <=
												$signed({3'b000, lhs_q[30:23]}) +
												$signed({3'b000, rhs_q[30:23]}) - 11'sd127;
											mul_multiplicand_q <= {40'd0, 1'b1, lhs_q[22:0]};
											mul_multiplier_q <= {1'b1, rhs_q[22:0]};
											mul_acc_q <= 64'd0;
											mul_addend_q <= 64'd0;
											step_q <= 6'd0;
											stage_q <= ST_MUL;
										end
									end

									SUBOP_DIVF: begin
										if (lhs_zero_w && rhs_zero_w) begin
											psw_mask_q <= PSW_FIV_MASK;
											psw_data_q <= PSW_FIV_MASK;
											exception_valid_q <= 1'b1;
											exception_code_q <= EXC_CODE_FIV;
											done_q <= 1'b1;
											stage_q <= ST_DONE;
										end else if (rhs_zero_w) begin
											psw_mask_q <= PSW_FZD_MASK;
											psw_data_q <= PSW_FZD_MASK;
											exception_valid_q <= 1'b1;
											exception_code_q <= EXC_CODE_FZD;
											done_q <= 1'b1;
											stage_q <= ST_DONE;
										end else if (lhs_zero_w) begin
											result_q <= {lhs_q[31] ^ rhs_q[31], 31'd0};
											result_we_q <= 1'b1;
											psw_mask_q <= PSW_FP_DIRECT_MASK;
											psw_data_q <= PSW_Z_MASK;
											done_q <= 1'b1;
											stage_q <= ST_DONE;
										end else begin
											div_sign_q <= lhs_q[31] ^ rhs_q[31];
											div_exp_q <=
												$signed({3'b000, lhs_q[30:23]}) -
												$signed({3'b000, rhs_q[30:23]}) + 11'sd127;
											div_den_q <= {1'b1, rhs_q[22:0]};
											if ({1'b1, lhs_q[22:0]} >=
												{1'b1, rhs_q[22:0]}) begin
												div_quot_q <= 28'h8000_000;
												div_rem_q <=
													{1'b1, lhs_q[22:0]} -
													{1'b0, {1'b1, rhs_q[22:0]}};
											end else begin
												div_quot_q <= 28'd0;
												div_rem_q <= {1'b0, {1'b1, lhs_q[22:0]}};
											end
											step_q <= 6'd0;
											stage_q <= ST_DIV;
										end
									end

									default: begin
										busy_q <= 1'b0;
										stage_q <= ST_DONE;
									end
								endcase
							end
						end

						ST_ALIGN: begin
							if (add_shift_rem_q != 6'd0) begin
								add_sig_lo_q <= rshift_sticky4_32_fn(
									add_sig_lo_q, add_shift_chunk_w);
								add_shift_rem_q <=
									add_shift_rem_q - {3'd0, add_shift_chunk_w};
							end else begin
								stage_q <= ST_ARITH;
							end
						end

						ST_ARITH: begin
							if (add_q) begin
								add_norm_q <= add_sig_hi_q + add_sig_lo_q;
							end else if (add_sig_hi_q == add_sig_lo_q) begin
								add_norm_q <= 32'd0;
								add_sign_q <= 1'b0;
							end else begin
								add_norm_q <= add_sig_hi_q - add_sig_lo_q;
							end
							stage_q <= ST_NORM;
						end

						ST_NORM: begin
							if ((subop_q == SUBOP_ADDF) ||
								(subop_q == SUBOP_SUBF)) begin
								if (add_q) begin
									pack_sign_q <= add_sign_q;
									if (add_norm_q[27]) begin
										pack_exp_q <= add_exp_q + 11'sd1;
										pack_norm_q <= {
											1'b0, add_norm_q[31:2],
											add_norm_q[1] || add_norm_q[0]};
									end else begin
										pack_exp_q <= add_exp_q;
										pack_norm_q <= add_norm_q;
									end
									pack_div_underflow_q <= 1'b0;
									stage_q <= ST_PACK;
								end else if (add_norm_q == 32'd0) begin
									result_q <= 32'd0;
									result_we_q <= 1'b1;
									psw_mask_q <= PSW_FP_DIRECT_MASK;
									psw_data_q <= PSW_Z_MASK;
									done_q <= 1'b1;
									stage_q <= ST_DONE;
								end else if (add_norm_q[26]) begin
									pack_sign_q <= add_sign_q;
									pack_exp_q <= add_exp_q;
									pack_norm_q <= add_norm_q;
									pack_div_underflow_q <= 1'b0;
									stage_q <= ST_PACK;
								end else begin
									if (add_norm_q[25]) begin
										add_norm_q <= add_norm_q << 1;
										add_exp_q <= add_exp_q - 11'sd1;
									end else if (add_norm_q[24]) begin
										add_norm_q <= add_norm_q << 2;
										add_exp_q <= add_exp_q - 11'sd2;
									end else if (add_norm_q[23]) begin
										add_norm_q <= add_norm_q << 3;
										add_exp_q <= add_exp_q - 11'sd3;
									end else begin
										add_norm_q <= add_norm_q << 4;
										add_exp_q <= add_exp_q - 11'sd4;
									end
								end
							end else if (subop_q == SUBOP_MULF) begin
								pack_sign_q <= mul_sign_q;
								pack_exp_q <= $signed(mul_norm_bundle_w[42:32]);
								pack_norm_q <= mul_norm_bundle_w[31:0];
								pack_div_underflow_q <= 1'b0;
								stage_q <= ST_PACK;
							end else begin
								pack_sign_q <= div_sign_q;
								pack_exp_q <= $signed(div_norm_bundle_w[42:32]);
								pack_norm_q <= div_norm_bundle_w[31:0];
								pack_div_underflow_q <= 1'b1;
								stage_q <= ST_PACK;
							end
						end

						ST_MUL: begin
							if (!mul_prep_q) begin
								mul_prep_q <= 1'b1;
							end else if (step_q < 6'd6) begin
								mul_acc_q <= mul_acc_q + mul_addend_q;
								mul_multiplicand_q <= mul_multiplicand_q << 4;
								mul_multiplicand3_q <= mul_multiplicand3_q << 4;
								mul_multiplier_q <= {4'd0, mul_multiplier_q[23:4]};
								step_q <= step_q + 6'd1;
							end else begin
								stage_q <= ST_NORM;
							end
						end

						ST_DIV: begin
							if (step_q < 6'd27) begin
								div_rem_q <= div_next_rem_w;
								div_quot_q <= div_next_quot_w;
								step_q <= step_q + 6'd1;
							end else begin
								stage_q <= ST_NORM;
							end
						end

						ST_PACK: begin
							if (pack_div_underflow_q &&
								!pack_underflow_shifted_q &&
								(pack_exp_ext_w <= 12'sd0)) begin
								pack_exp_q <= 11'sd0;
								pack_underflow_shifted_q <= 1'b1;
								pack_shift_rem_q <=
									(pack_underflow_shift_w >= 12'd32) ?
									6'd32 : pack_underflow_shift_w[5:0];
								stage_q <= ST_UNDERFLOW;
							end else begin
								result_we_q <= 1'b1;
								if (pack_underflow_shifted_q) begin
									result_q <= pack_underflow_result_w;
									psw_mask_q <= PSW_FP_DIRECT_MASK |
										PSW_FUD_MASK;
									psw_data_q <=
										fp_result_flags_fn(pack_underflow_result_w) |
										PSW_FUD_MASK;
								end else if (pack_exp_rounded_w >= 12'sd255) begin
									// Silicon unknown: overflow result bits have not been measured.
									// Use the corrected exponent and discarded-bit result.
									result_q <= pack_overflow_result_w;
									psw_mask_q <= PSW_FP_DIRECT_MASK |
										PSW_FOV_MASK |
										(pack_fpr_w ? PSW_FPR_MASK : 10'd0);
									psw_data_q <=
										fp_result_flags_fn(pack_overflow_result_w) |
										PSW_FOV_MASK |
										(pack_fpr_w ? PSW_FPR_MASK : 10'd0);
									exception_valid_q <= 1'b1;
									exception_code_q <= EXC_CODE_FOV;
								end else if (pack_exp_rounded_w <= 12'sd0) begin
									result_q <= {pack_sign_q, 31'd0};
									psw_mask_q <= PSW_FP_DIRECT_MASK |
										PSW_FUD_MASK;
									psw_data_q <= PSW_Z_MASK |
										PSW_FUD_MASK;
								end else begin
									result_q <= pack_normal_result_w;
									psw_mask_q <= PSW_FP_DIRECT_MASK |
										(pack_fpr_w ? PSW_FPR_MASK : 10'd0);
									psw_data_q <=
										fp_result_flags_fn(pack_normal_result_w) |
										(pack_fpr_w ? PSW_FPR_MASK : 10'd0);
								end
								done_q <= 1'b1;
								stage_q <= ST_DONE;
							end
						end

						ST_UNDERFLOW: begin
							if (pack_shift_rem_q != 6'd0) begin
								pack_norm_q <= rshift_sticky4_27_fn(
									pack_norm_q, pack_shift_chunk_w);
								pack_shift_rem_q <= pack_shift_rem_q -
									{3'd0, pack_shift_chunk_w};
								if (pack_shift_rem_q <= 6'd4) begin
									stage_q <= ST_PACK;
								end
							end else begin
								stage_q <= ST_PACK;
							end
						end

						default: begin
						end
					endcase
				end
			end
		end
	end

	function [9:0] fp_result_flags_fn;
		input [31:0] value;
		reg magnitude_zero_v;
		begin
			magnitude_zero_v = (value[30:0] == 31'd0);
			fp_result_flags_fn = 10'd0;
			fp_result_flags_fn[0] = magnitude_zero_v;
			fp_result_flags_fn[1] = value[31] && !magnitude_zero_v;
			fp_result_flags_fn[2] = 1'b0;
			fp_result_flags_fn[3] = value[31] && !magnitude_zero_v;
		end
	endfunction

	function [9:0] int_result_flags_fn;
		input [31:0] value;
		begin
			int_result_flags_fn = 10'd0;
			int_result_flags_fn[0] = (value == 32'd0);
			int_result_flags_fn[1] = value[31];
			int_result_flags_fn[2] = 1'b0;
		end
	endfunction

	function [9:0] fp_compare_flags_fn;
		input [31:0] lhs;
		input [31:0] rhs;
		reg equal_v;
		reg less_v;
		begin
			equal_v = fp_equal_fn(lhs, rhs);
			less_v = fp_less_fn(lhs, rhs);
			fp_compare_flags_fn = 10'd0;
			fp_compare_flags_fn[0] = equal_v;
			fp_compare_flags_fn[1] = less_v;
			fp_compare_flags_fn[2] = 1'b0;
			fp_compare_flags_fn[3] = less_v;
		end
	endfunction

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

	function [31:0] low_mask32_fn;
		input [5:0] bits;
		begin
			if (bits == 6'd0) begin
				low_mask32_fn = 32'd0;
			end else begin
				low_mask32_fn = 32'hffff_ffff >> (6'd32 - bits);
			end
		end
	endfunction

	function [5:0] msb_index32_fn;
		input [31:0] value;
		reg [15:0] upper16_v;
		reg [7:0]  upper8_v;
		reg [3:0]  upper4_v;
		begin
			msb_index32_fn = 6'd0;
			if (value[31:16] != 16'd0) begin
				msb_index32_fn = 6'd16;
				upper16_v = value[31:16];
			end else begin
				upper16_v = value[15:0];
			end
			if (upper16_v[15:8] != 8'd0) begin
				msb_index32_fn = msb_index32_fn + 6'd8;
				upper8_v = upper16_v[15:8];
			end else begin
				upper8_v = upper16_v[7:0];
			end
			if (upper8_v[7:4] != 4'd0) begin
				msb_index32_fn = msb_index32_fn + 6'd4;
				upper4_v = upper8_v[7:4];
			end else begin
				upper4_v = upper8_v[3:0];
			end
			casez (upper4_v)
				4'b1???: msb_index32_fn = msb_index32_fn + 6'd3;
				4'b01??: msb_index32_fn = msb_index32_fn + 6'd2;
				4'b001?: msb_index32_fn = msb_index32_fn + 6'd1;
				default: begin
				end
			endcase
		end
	endfunction

	function fp_is_zero_fn;
		input [30:0] value;
		begin
			fp_is_zero_fn = (value == 31'd0);
		end
	endfunction

	function fp_reserved_operand_fn;
		input [30:0] value;
		begin
			fp_reserved_operand_fn =
				((value[30:23] == 8'd0) && (value[22:0] != 23'd0)) ||
				(value[30:23] == 8'hff);
		end
	endfunction

	function [31:0] fp_order_key_fn;
		input [31:0] value;
		begin
			fp_order_key_fn = value[31] ? ~value : (value ^ 32'h8000_0000);
		end
	endfunction

	function fp_equal_fn;
		input [31:0] lhs;
		input [31:0] rhs;
		begin
			if (fp_is_zero_fn(lhs[30:0]) && fp_is_zero_fn(rhs[30:0])) begin
				fp_equal_fn = 1'b1;
			end else begin
				fp_equal_fn = (lhs == rhs);
			end
		end
	endfunction

	function fp_less_fn;
		input [31:0] lhs;
		input [31:0] rhs;
		begin
			if (fp_equal_fn(lhs, rhs)) begin
				fp_less_fn = 1'b0;
			end else begin
				fp_less_fn = fp_order_key_fn(lhs) < fp_order_key_fn(rhs);
			end
		end
	endfunction

	function [31:0] fp_from_int_fn;
		input [31:0] value;
		reg        sign_v;
		reg [31:0] abs_v;
		reg [5:0]  msb_v;
		reg [5:0]  shift_v;
		reg [31:0] sig_v;
		reg        round_v;
		reg [7:0]  exp_v;
		begin
			sign_v = 1'b0;
			abs_v = 32'd0;
			msb_v = 6'd0;
			shift_v = 6'd0;
			sig_v = 32'd0;
			round_v = 1'b0;
			exp_v = 8'd0;
			if (value == 32'd0) begin
				fp_from_int_fn = 32'd0;
			end else begin
				sign_v = value[31];
				abs_v = abs32_fn(value);
				msb_v = msb_index32_fn(abs_v);
				exp_v = 8'd127 + {2'd0, msb_v};
				if (msb_v <= 6'd23) begin
					sig_v = (abs_v << (6'd23 - msb_v)) & 32'h007f_ffff;
					fp_from_int_fn = {sign_v, exp_v, sig_v[22:0]};
				end else begin
					shift_v = msb_v - 6'd23;
					sig_v = abs_v >> shift_v;
					round_v = abs_v[shift_v[4:0] - 5'd1] &&
						(((shift_v > 6'd1) &&
						 ((abs_v & low_mask32_fn(shift_v - 6'd1)) != 32'd0)) ||
						 sig_v[0]);
					sig_v = sig_v + {31'd0, round_v};
					if (sig_v[24]) begin
						sig_v = sig_v >> 1;
						exp_v = exp_v + 8'd1;
					end
					fp_from_int_fn = {sign_v, exp_v, sig_v[22:0]};
				end
			end
		end
	endfunction

	function fp_from_int_fpr_fn;
		input [31:0] value;
		reg [31:0] abs_v;
		reg [5:0]  msb_v;
		reg [5:0]  shift_v;
		begin
			abs_v = 32'd0;
			msb_v = 6'd0;
			shift_v = 6'd0;
			if (value == 32'd0) begin
				fp_from_int_fpr_fn = 1'b0;
			end else begin
				abs_v = abs32_fn(value);
				msb_v = msb_index32_fn(abs_v);
				if (msb_v <= 6'd23) begin
					fp_from_int_fpr_fn = 1'b0;
				end else begin
					shift_v = msb_v - 6'd23;
					fp_from_int_fpr_fn =
						((abs_v & low_mask32_fn(shift_v)) != 32'd0);
				end
			end
		end
	endfunction

	function fp_to_int_invalid_fn;
		input [31:0] value;
		begin
			if (fp_is_zero_fn(value[30:0])) begin
				fp_to_int_invalid_fn = 1'b0;
			end else if (!value[31]) begin
				fp_to_int_invalid_fn = (value[30:23] >= 8'd158);
			end else begin
				fp_to_int_invalid_fn =
					(value[30:23] > 8'd158) ||
					((value[30:23] == 8'd158) && (value[22:0] != 23'd0));
			end
		end
	endfunction

	function fp_to_int_fpr_fn;
		input [30:0] value;
		reg [24:0] mant_v;
		reg [7:0]  shift_v;
		begin
			mant_v = 25'd0;
			shift_v = 8'd0;
			if (fp_is_zero_fn(value[30:0])) begin
				fp_to_int_fpr_fn = 1'b0;
			end else if (value[30:23] >= 8'd150) begin
				fp_to_int_fpr_fn = 1'b0;
			end else if (value[30:23] < 8'd127) begin
				fp_to_int_fpr_fn = 1'b1;
			end else begin
				mant_v = {1'b0, 1'b1, value[22:0]};
				shift_v = 8'd150 - value[30:23];
				if (shift_v >= 8'd32) begin
					fp_to_int_fpr_fn = (mant_v != 25'd0);
				end else begin
					fp_to_int_fpr_fn =
						(({7'd0, mant_v} &
						  low_mask32_fn(shift_v[5:0])) != 32'd0);
				end
			end
		end
	endfunction

	function [31:0] fp_to_int_trunc_fn;
		input [31:0] value;
		reg        sign_v;
		reg [7:0]  exp_v;
		reg [24:0] mant_v;
		reg [31:0] int_v;
		reg [7:0]  shift_v;
		begin
			sign_v = value[31];
			exp_v = value[30:23];
			mant_v = {1'b0, 1'b1, value[22:0]};
			int_v = 32'd0;
			shift_v = 8'd0;
			if (fp_is_zero_fn(value[30:0]) || (exp_v < 8'd127)) begin
				int_v = 32'd0;
			end else if (exp_v >= 8'd150) begin
				int_v = {7'd0, mant_v} << (exp_v - 8'd150);
			end else begin
				shift_v = 8'd150 - exp_v;
				if (shift_v >= 8'd32) begin
					int_v = 32'd0;
				end else begin
					int_v = {7'd0, mant_v} >> shift_v[5:0];
				end
			end
			fp_to_int_trunc_fn = sign_v ? neg32_fn(int_v) : int_v;
		end
	endfunction

	function [31:0] fp_to_int_nearest_fn;
		input [31:0] value;
		reg        sign_v;
		reg [7:0]  exp_v;
		reg [24:0] mant_v;
		reg [31:0] int_v;
		reg [7:0]  shift_v;
		reg        round_v;
		begin
			sign_v = value[31];
			exp_v = value[30:23];
			mant_v = {1'b0, 1'b1, value[22:0]};
			int_v = 32'd0;
			shift_v = 8'd0;
			round_v = 1'b0;
			if (fp_is_zero_fn(value[30:0]) || (exp_v < 8'd126)) begin
				int_v = 32'd0;
			end else if (exp_v == 8'd126) begin
				int_v = (value[22:0] != 23'd0) ? 32'd1 : 32'd0;
			end else if (exp_v >= 8'd150) begin
				int_v = {7'd0, mant_v} << (exp_v - 8'd150);
			end else begin
				shift_v = 8'd150 - exp_v;
				int_v = {7'd0, mant_v} >> shift_v[5:0];
				round_v = mant_v[shift_v[4:0] - 5'd1] &&
					(((shift_v > 8'd1) &&
					 (({7'd0, mant_v} &
					   low_mask32_fn(shift_v[5:0] - 6'd1)) != 32'd0)) ||
					 int_v[0]);
				int_v = int_v + {31'd0, round_v};
			end
			fp_to_int_nearest_fn = sign_v ? neg32_fn(int_v) : int_v;
		end
	endfunction

	function [31:0] rshift_sticky4_32_fn;
		input [31:0] value;
		input [2:0]  shift;
		begin
			case (shift)
				3'd0: rshift_sticky4_32_fn = value;
				3'd1: rshift_sticky4_32_fn =
					{1'b0, value[31:2], value[1] || value[0]};
				3'd2: rshift_sticky4_32_fn =
					{2'd0, value[31:3], |value[2:0]};
				3'd3: rshift_sticky4_32_fn =
					{3'd0, value[31:4], |value[3:0]};
				default: rshift_sticky4_32_fn =
					{4'd0, value[31:5], |value[4:0]};
			endcase
		end
	endfunction

	function [31:0] rshift_sticky4_27_fn;
		input [31:0] value;
		input [2:0]  shift;
		begin
			case (shift)
				3'd0: rshift_sticky4_27_fn = value;
				3'd1: rshift_sticky4_27_fn =
					{6'd0, value[26:2], value[1] || value[0]};
				3'd2: rshift_sticky4_27_fn =
					{7'd0, value[26:3], |value[2:0]};
				3'd3: rshift_sticky4_27_fn =
					{8'd0, value[26:4], |value[3:0]};
				default: rshift_sticky4_27_fn =
					{9'd0, value[26:5], |value[4:0]};
			endcase
		end
	endfunction

	function [42:0] fp_mul_norm_from_prod_fn;
		input signed [10:0] exp_i;
		input [47:0] prod_i;
		reg signed [10:0] exp_v;
		reg [31:0] norm_v;
		begin
			exp_v = exp_i;
			if (prod_i[47]) begin
				norm_v = {5'd0, prod_i[47:21]};
				if (prod_i[20:0] != 21'd0) begin
					norm_v[0] = 1'b1;
				end
				exp_v = exp_v + 11'sd1;
			end else begin
				norm_v = {5'd0, prod_i[46:20]};
				if (prod_i[19:0] != 20'd0) begin
					norm_v[0] = 1'b1;
				end
			end
			fp_mul_norm_from_prod_fn = {exp_v[10:0], norm_v};
		end
	endfunction

	function [42:0] fp_div_norm_from_qrem_fn;
		input signed [10:0] exp_i;
		input [27:0] quot_i;
		input [24:0] rem_i;
		reg signed [10:0] exp_v;
		reg [31:0] norm_v;
		begin
			exp_v = exp_i;
			if (quot_i[27]) begin
				norm_v = {5'd0, quot_i[27:1]};
				if (quot_i[0] || (rem_i != 25'd0)) begin
					norm_v[0] = 1'b1;
				end
			end else begin
				exp_v = exp_v - 11'sd1;
				norm_v = {5'd0, quot_i[26:0]};
				if (rem_i != 25'd0) begin
					norm_v[0] = 1'b1;
				end
			end
			fp_div_norm_from_qrem_fn = {exp_v[10:0], norm_v};
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
