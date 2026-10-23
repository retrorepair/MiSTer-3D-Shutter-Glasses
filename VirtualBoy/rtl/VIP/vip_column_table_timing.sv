// Copyright (c) 2026 Jamie Blanks

`timescale 1ns/1ps

// Native CTA four-column timing.
//
// Nintendo documents one column-table entry for each four columns. The low
// CTC byte is the column length minus one in 200 ns units. At the native
// 20 MHz enable, one four-column period is therefore:
//
//     16 * (CTC[7:0] + 1) enabled clocks.
//
// Group zero starts at the eye boundary. Later groups follow the previous group
// boundary, not request acceptance. A bad or late result ends the field as
// incomplete instead of shifting its timing.
// Nintendo characterizes useful CTC low bytes from 2c through ff.
// Silicon unknown: scanner behavior below 0x2c is not documented. This block
// still uses the written value without clamping it.
//
// The shipped MiSTer core sets FIXED_GROUP_PERIOD_CE (vip_core.sv), which
// replaces the CTC-derived cadence entirely; the CTC path below is exercised
// only by the standalone bench, which leaves the parameter at zero.

module vip_native_cta_group_source
#(
	// A nonzero value selects MiSTer's serialized eye-group cadence.
	parameter [12:0] FIXED_GROUP_PERIOD_CE = 13'd0
)
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	// Sample abort on the raw clock so DPRST is not lost while CE is paused.
	input  wire        abort_i,

	// Start a new eye only after the CTA sequencer drains.
	input  wire        consumer_busy_i,
	input  wire        left_field_start_i,
	input  wire        left_field_end_i,
	input  wire        right_field_start_i,
	input  wire        right_field_end_i,

	input  wire        group_ready_i,
	input  wire        ctc_valid_i,
	// Cadence uses only the low CTC byte; the high byte holds brightness data.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [15:0] ctc_data_i,
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire        ctc_eye_i,
	input  wire [6:0]  ctc_ordinal_i,
	output wire        group_valid_o,
	output wire        group_accept_o,

	output wire        field_active_o,
	output wire        field_eye_o,
	output wire [6:0]  field_accept_count_o,
	output reg         field_complete_o,
	output reg         field_complete_eye_o,
	output reg         field_incomplete_o,
	output reg         field_incomplete_eye_o,
	output reg         field_overlap_o,
	output reg         field_underrun_o,
	// Combinational completion is for same-edge timing; registered pulses follow.
	output wire        field_terminal_fire_o,
	output wire        field_terminal_eye_o
);

	localparam [1:0] STATE_OFFER = 2'd0;
	localparam [1:0] STATE_WAIT_CTC = 2'd1;
	localparam [1:0] STATE_WAIT_BOUNDARY = 2'd2;
	// 96 four-column groups cover the 384-column field.
	localparam [6:0] GROUP_COUNT = 7'd96;
	// Longest legal group period: CTC low byte ff gives 255*16 + 16 = 4096 CE.
	localparam [12:0] MAX_GROUP_PERIOD = 13'd4096;

	reg [1:0]  state_q;
	reg        field_active_q;
	reg        field_eye_q;
	reg [6:0]  field_accept_count_q;
	// The timer counts elapsed request time, then remaining group time.
	reg [12:0] state_timer_q;

	wire any_start_w = left_field_start_i || right_field_start_i;
	wire simultaneous_start_w = left_field_start_i &&
		right_field_start_i;
	wire any_end_w = left_field_end_i || right_field_end_i;
	wire simultaneous_end_w = left_field_end_i && right_field_end_i;
	wire refused_start_w = any_start_w && !simultaneous_start_w &&
		!any_end_w && (field_active_q || consumer_busy_i);
	wire matching_end_w = field_eye_q ? right_field_end_i :
		left_field_end_i;
	wire mismatched_end_w = field_eye_q ? left_field_end_i :
		right_field_end_i;
	wire ctc_tag_match_w = (ctc_eye_i == field_eye_q) &&
		(ctc_ordinal_i == (field_accept_count_q - 7'd1));
	wire [12:0] elapsed_next_w = state_timer_q + 13'd1;
	// Concatenation implements the documented shift without a multiplier.
	wire [12:0] ctc_period_w =
		(FIXED_GROUP_PERIOD_CE != 13'd0) ? FIXED_GROUP_PERIOD_CE :
		({1'b0, ctc_data_i[7:0], 4'b0000} + 13'd16);
	wire ctc_boundary_now_w = field_active_q &&
		(state_q == STATE_WAIT_CTC) && ctc_valid_i &&
		ctc_tag_match_w && (elapsed_next_w == ctc_period_w);
	wire timer_boundary_now_w = field_active_q &&
		(state_q == STATE_WAIT_BOUNDARY) && (state_timer_q == 13'd1);
	wire natural_complete_w = (field_accept_count_q == GROUP_COUNT) &&
		(ctc_boundary_now_w || timer_boundary_now_w);
	wire offer_failure_now_w = (state_q == STATE_OFFER) &&
		(ctc_valid_i || (state_timer_q == (MAX_GROUP_PERIOD - 13'd1)));
	wire wait_ctc_failure_now_w = (state_q == STATE_WAIT_CTC) &&
		((ctc_valid_i && (!ctc_tag_match_w ||
			(elapsed_next_w > ctc_period_w))) ||
		 (!ctc_valid_i &&
			(state_timer_q == (MAX_GROUP_PERIOD - 13'd1))));
	wire wait_boundary_failure_now_w =
		(state_q == STATE_WAIT_BOUNDARY) && ctc_valid_i;
	wire illegal_state_failure_now_w = (state_q == 2'd3);

	assign group_valid_o = field_active_q &&
		(state_q == STATE_OFFER) && !reset_i && !abort_i &&
		(field_accept_count_q < GROUP_COUNT) && !offer_failure_now_w &&
		!refused_start_w;
	assign group_accept_o = ce_i && group_valid_o && group_ready_i;
	assign field_active_o = field_active_q && !abort_i;
	assign field_eye_o = field_eye_q;
	assign field_accept_count_o = field_accept_count_q;
	assign field_terminal_fire_o = ce_i && !reset_i && !abort_i &&
		field_active_q && (natural_complete_w || refused_start_w ||
		offer_failure_now_w || wait_ctc_failure_now_w ||
		wait_boundary_failure_now_w || illegal_state_failure_now_w);
	assign field_terminal_eye_o = field_eye_q;

	// End the field as incomplete because a group missed its timing.
	task end_field_underrun_task;
		begin
			state_q <= STATE_OFFER;
			field_active_q <= 1'b0;
			state_timer_q <= 13'd0;
			field_incomplete_o <= 1'b1;
			field_incomplete_eye_o <= field_eye_q;
			field_underrun_o <= 1'b1;
		end
	endtask

	// Close a group on its boundary; the final group completes the field.
	task end_group_boundary_task;
		begin
			state_q <= STATE_OFFER;
			state_timer_q <= 13'd0;
			if (field_accept_count_q == GROUP_COUNT) begin
				field_active_q <= 1'b0;
				field_complete_o <= 1'b1;
				field_complete_eye_o <= field_eye_q;
			end
		end
	endtask

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_OFFER;
			field_active_q <= 1'b0;
			field_eye_q <= 1'b0;
			field_accept_count_q <= 7'd0;
			state_timer_q <= 13'd0;
			field_complete_o <= 1'b0;
			field_complete_eye_o <= 1'b0;
			field_incomplete_o <= 1'b0;
			field_incomplete_eye_o <= 1'b0;
			field_overlap_o <= 1'b0;
			field_underrun_o <= 1'b0;
		end else if (abort_i) begin
			// Eye tags survive abort so the last pulses keep their labels.
			state_q <= STATE_OFFER;
			field_active_q <= 1'b0;
			field_accept_count_q <= 7'd0;
			state_timer_q <= 13'd0;
			field_complete_o <= 1'b0;
			field_incomplete_o <= 1'b0;
			field_overlap_o <= 1'b0;
			field_underrun_o <= 1'b0;
		end else if (ce_i) begin
			field_complete_o <= 1'b0;
			field_incomplete_o <= 1'b0;
			field_overlap_o <= 1'b0;
			field_underrun_o <= 1'b0;

			// Overlapping eye boundaries cannot start a valid field.
			if (any_start_w) begin
				if (simultaneous_start_w || any_end_w) begin
					field_overlap_o <= 1'b1;
				end else if (field_active_q || consumer_busy_i) begin
					// End the old eye, then mark the accepted new eye incomplete.
					state_q <= STATE_OFFER;
					field_active_q <= 1'b0;
					state_timer_q <= 13'd0;
					field_overlap_o <= 1'b1;
					field_incomplete_o <= 1'b1;
					field_incomplete_eye_o <= right_field_start_i;
				end else if (ctc_valid_i) begin
					// Do not reuse a stale result for group zero.
					state_q <= STATE_OFFER;
					field_active_q <= 1'b0;
					field_eye_q <= right_field_start_i;
					field_accept_count_q <= 7'd0;
					state_timer_q <= 13'd0;
					field_incomplete_o <= 1'b1;
					field_incomplete_eye_o <= right_field_start_i;
					field_underrun_o <= 1'b1;
				end else begin
					state_q <= STATE_OFFER;
					field_active_q <= 1'b1;
					field_eye_q <= right_field_start_i;
					field_accept_count_q <= 7'd0;
					state_timer_q <= 13'd0;
				end
			end

			// Each arm keys off the same *_failure_now_w wires that drive
			// field_terminal_fire_o, so the two views cannot drift apart.
			if (field_active_q && !refused_start_w) begin
				case (state_q)
					STATE_OFFER: begin
						// A result with no outstanding read, or a timed-out
						// offer, ends the field. group_valid_o already
						// excludes both, so an accepted group is never late.
						if (offer_failure_now_w) begin
							end_field_underrun_task;
						end else if (group_accept_o) begin
							field_accept_count_q <=
								field_accept_count_q + 7'd1;
							state_q <= STATE_WAIT_CTC;
							state_timer_q <= elapsed_next_w;
						end else begin
							state_timer_q <= elapsed_next_w;
						end
					end

					STATE_WAIT_CTC: begin
						if (wait_ctc_failure_now_w) begin
							end_field_underrun_task;
						end else if (ctc_valid_i) begin
							if (elapsed_next_w == ctc_period_w) begin
								end_group_boundary_task;
							end else begin
								state_q <= STATE_WAIT_BOUNDARY;
								state_timer_q <=
									ctc_period_w - elapsed_next_w;
							end
						end else begin
							state_timer_q <= elapsed_next_w;
						end
					end

					STATE_WAIT_BOUNDARY: begin
						if (wait_boundary_failure_now_w) begin
							end_field_underrun_task;
						end else if (state_timer_q == 13'd1) begin
							end_group_boundary_task;
						end else begin
							state_timer_q <= state_timer_q - 13'd1;
						end
					end

					// Unreachable 2'd3 parking value; matches
					// illegal_state_failure_now_w for the terminal pulse.
					default: begin
						end_field_underrun_task;
					end
				endcase
			end

			// Ignore a wrong-eye end. A matching end stops new groups.
			if (field_active_q && any_end_w) begin
				if (simultaneous_end_w || mismatched_end_w) begin
					field_overlap_o <= 1'b1;
				end else if (matching_end_w) begin
					state_q <= STATE_OFFER;
					field_active_q <= 1'b0;
					state_timer_q <= 13'd0;
					if (!natural_complete_w) begin
						field_incomplete_o <= 1'b1;
						field_incomplete_eye_o <= field_eye_q;
					end
				end
			end
		end
	end

endmodule
