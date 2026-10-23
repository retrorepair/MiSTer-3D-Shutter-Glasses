// Copyright (c) 2026 Jamie Blanks

`timescale 1ns/1ps
/* verilator lint_off DECLFILENAME */

// H-bias and Affine background renderers.

// H-bias world engine.
//
// Accept a command only while all work is idle. Start the scheduler and capture
// descriptor and GPLT state on that edge.
//
// H-bias owns PARAM reads and shares CELL, character, and blend hardware. Abort
// drops new work and drains accepted reads.

module vip_xp_hbias_engine
#(
	parameter integer COMPOSED_TIMING_CREDIT_ENABLE = 0
)
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,

	// Held H-bias command.
	input  wire                 engine_cmd_valid_i,
	output wire                 engine_cmd_ready_o,
	input  wire [1:0]           engine_cmd_kind_i,
	input  wire [4:0]           engine_cmd_strip_i,
	input  wire [4:0]           engine_cmd_world_i,
	input  wire [255:0]         engine_cmd_descriptor_i,
	input  wire                 engine_cmd_first_visit_i,
	output wire                 engine_done_o,
	input  wire                 engine_abort_i,
	input  wire [2:0]           parallax_scale_i,
	input  wire [31:0]          gplt_active_i,

	// PARAM client shared with background CELL reads.
	output wire                 param_dram_req_o,
	output wire [15:0]          param_dram_addr_o,
	input  wire                 param_dram_accept_i,
	input  wire                 param_dram_resp_valid_i,
	input  wire [15:0]          param_dram_resp_data_i,
	input  wire                 param_dram_cleanup_busy_i,
	input  wire                 param_dram_stale_discard_i,

	// Rearm diagnostics when the command is accepted.
	output wire                 bg_diagnostic_rearm_o,
	input  wire                 bg_diagnostic_rearm_ready_i,
	input  wire                 bg_diagnostic_rearm_accept_i,
	input  wire                 bg_diagnostic_rearm_rejected_i,

	// Shared background settings and work.
	output wire [3:0]           bg_maps_wide_o,
	output wire [3:0]           bg_maps_high_o,
	output wire [3:0]           bg_effective_map_columns_o,
	output wire [3:0]           bg_bgmap_base_rounded_o,
	output wire                 bg_over_o,
	output wire [15:0]          bg_overplane_o,
	output wire                 bg_left_on_o,
	output wire                 bg_right_on_o,
	output wire signed [17:0]   bg_left_source_start_o,
	output wire signed [17:0]   bg_right_source_start_o,
	output wire signed [17:0]   bg_left_destination_start_o,
	output wire signed [17:0]   bg_right_destination_start_o,
	output wire [12:0]          bg_semantic_width_o,
	output wire [31:0]          bg_gplt_active_o,
	output wire                 bg_tile_row_valid_o,
	input  wire                 bg_tile_row_ready_i,
	output wire [0:0]           bg_tile_row_load_o,
	output wire [8:0]           bg_tile_row_screen_y_o,
	output wire signed [16:0]   bg_tile_row_source_y_o,
	output wire                 bg_tile_valid_o,
	input  wire                 bg_tile_ready_i,
	output wire [0:0]           bg_tile_load_o,
	output wire [12:0]          bg_tile_ordinal_o,
	output wire signed [15:0]   bg_tile_x_o,
	output wire                 bg_row_valid_o,
	input  wire                 bg_row_ready_i,
	output wire [0:0]           bg_row_load_o,
	output wire [12:0]          bg_row_tile_ordinal_o,
	output wire [2:0]           bg_row_ordinal_o,
	output wire [2:0]           bg_row_source_index_o,
	output wire [8:0]           bg_row_screen_y_o,
	output wire signed [16:0]   bg_row_source_y_o,
	output wire                 bg_result_permit_o,

	input  wire                 bg_raw_result_valid_i,
	input  wire                 bg_raw_result_accept_i,
	input  wire [1:0]           bg_raw_result_owner_i,
	input  wire [0:0]           bg_raw_result_load_i,
	input  wire [12:0]          bg_raw_result_tile_ordinal_i,
	input  wire [2:0]           bg_raw_result_row_ordinal_i,
	input  wire signed [15:0]   bg_raw_result_tile_x_i,
	input  wire [8:0]           bg_raw_result_screen_y_i,
	input  wire signed [16:0]   bg_raw_result_source_y_i,
	input  wire [2:0]           bg_raw_result_source_index_i,
	input  wire [8:0]           bg_raw_result_tile_row_screen_y_i,
	input  wire signed [16:0]   bg_raw_result_tile_row_source_y_i,
	input  wire                 bg_raw_result_overplane_selected_i,
	input  wire                 bg_raw_result_strict_overplane_i,

	input  wire                 bg_token_valid_i,
	output wire                 bg_token_ready_o,
	input  wire                 bg_token_accept_i,
	input  wire [2:0]           bg_token_row_i,
	input  wire signed [15:0]   bg_token_left_base_x_i,
	input  wire                 bg_token_left_enable_i,
	input  wire [7:0]           bg_token_left_active_i,
	input  wire [7:0]           bg_token_left_opaque_i,
	input  wire [15:0]          bg_token_left_values_i,
	input  wire signed [15:0]   bg_token_right_base_x_i,
	input  wire                 bg_token_right_enable_i,
	input  wire [7:0]           bg_token_right_active_i,
	input  wire [7:0]           bg_token_right_opaque_i,
	input  wire [15:0]          bg_token_right_values_i,
	input  wire [1:0]           bg_token_owner_i,
	input  wire [0:0]           bg_token_load_i,
	input  wire [12:0]          bg_token_tile_ordinal_i,
	input  wire [2:0]           bg_token_row_ordinal_i,
	input  wire signed [15:0]   bg_token_tile_x_i,
	input  wire [8:0]           bg_token_screen_y_i,
	input  wire signed [16:0]   bg_token_source_y_i,
	input  wire [2:0]           bg_token_source_index_i,
	input  wire [8:0]           bg_token_tile_row_screen_y_i,
	input  wire signed [16:0]   bg_token_tile_row_source_y_i,
	input  wire                 bg_token_overplane_selected_i,
	input  wire                 bg_token_strict_overplane_i,

	input  wire                 bg_context_accept_i,
	input  wire                 bg_context_owner_valid_i,
	input  wire [1:0]           bg_active_context_owner_i,
	input  wire                 bg_busy_i,
	input  wire                 bg_fetch_busy_i,
	input  wire                 bg_cleanup_busy_i,
	input  wire                 bg_dram_read_pending_i,
	input  wire                 bg_vrm_read_pending_i,
	input  wire                 bg_cell_accept_i,
	input  wire                 bg_vrm_accept_i,
	input  wire                 bg_unexpected_dram_response_i,
	input  wire                 bg_unexpected_vrm_response_i,
	input  wire                 bg_response_capture_overflow_i,
	input  wire                 bg_scheduler_tag_mismatch_i,
	input  wire                 bg_concurrent_work_error_i,
	input  wire                 bg_strict_overplane_seen_i,
	input  wire                 bg_map_index_overflow_seen_i,

	// Registered stereo row token.
	output wire                 row_producer_valid_o,
	input  wire                 row_producer_ready_i,
	output wire [15:0]          row_producer_tile_ordinal_o,
	output wire [2:0]           row_producer_row_o,
	output wire signed [15:0]   row_producer_left_base_x_o,
	output wire                 row_producer_left_enable_o,
	output wire [7:0]           row_producer_left_active_o,
	output wire [7:0]           row_producer_left_opaque_o,
	output wire [15:0]          row_producer_left_values_o,
	output wire signed [15:0]   row_producer_right_base_x_o,
	output wire                 row_producer_right_enable_o,
	output wire [7:0]           row_producer_right_active_o,
	output wire [7:0]           row_producer_right_opaque_o,
	output wire [15:0]          row_producer_right_values_o,
	input  wire                 row_producer_done_i,

	// Command ownership state.
	output wire                 hbias_active_o,
	output wire                 hbias_quiescent_o,
	output wire                 command_accept_o,
	output wire [15:0]          active_visual_height_o,
	output wire signed [16:0]   active_timing_height_o,

	// Scheduler and row progress.
	output wire                 scheduler_busy_o,
	output wire                 scheduler_done_pulse_o,
	output wire                 scheduler_aborted_o,
	output wire [2:0]           scheduler_state_o,
	output wire [9:0]           scheduler_ticks_remaining_o,
	output wire [31:0]          scheduler_elapsed_ticks_o,
	output wire [15:0]          scheduler_row_accept_count_o,
	output wire [31:0]          scheduler_tile_accept_count_o,
	output wire [3:0]           scheduler_rows_in_strip_o,
	output wire [7:0]           timing_reference_strip_ticks_o,
	output wire [3:0]           timing_reference_rows_o,
	output wire [3:0]           visual_only_rows_o,
	output wire                 extent_conflict_o,
	output wire                 pipeline_busy_o,
	output wire                 pipeline_cleanup_busy_o,
	output wire                 pipeline_downstream_idle_o,
	output wire [1:0]           producer_outstanding_o,
	output wire                 param_read_pending_o,
	output wire                 cell_dram_read_pending_o,
	output wire                 cell_vrm_read_pending_o,

	// Sticky behavior and protocol diagnostics.
	output reg                  command_kind_mismatch_o,
	output wire                 descriptor_kind_mismatch_o,
	output wire                 strict_overplane_high_o,
	output wire                 raw_h_timing_conflict_o,
	output wire                 source_conflict_o,
	output reg                  geometry_error_o,
	output reg                  protocol_error_o,
`ifndef SYNTHESIS
	output reg  [31:0]          diag_command_accept_count_o,
	output reg  [31:0]          diag_command_done_count_o
`else
	output wire [31:0]          diag_command_accept_count_o,
	output wire [31:0]          diag_command_done_count_o
`endif
);

	reg hbias_active_q;
	reg scheduler_complete_q;

	// Descriptor state captured for the draw.
	reg left_on_q;
	reg right_on_q;
	reg signed [9:0] gx_q;
	reg signed [9:0] gp_q;
	reg signed [15:0] gy_q;
	reg signed [12:0] mx_q;
	reg signed [14:0] mp_q;
	reg [12:0] semantic_width_q;
	reg [15:0] visual_height_q;
	reg signed [16:0] timing_height_q;
	reg [15:0] param_base_q;
	reg [3:0] maps_wide_q;
	reg [3:0] maps_high_q;
	reg [3:0] effective_map_columns_q;
	reg [3:0] bgmap_base_rounded_q;
	reg over_q;
	reg [15:0] overplane_q;
	reg [31:0] gplt_active_q;

	// Live descriptor decode, sampled only at command acceptance.
	wire descriptor_left_on_w;
	wire descriptor_right_on_w;
	wire descriptor_over_w;
	wire signed [9:0] descriptor_gx_w;
	wire signed [9:0] descriptor_gp_w;
	wire signed [15:0] descriptor_gy_w;
	wire signed [12:0] descriptor_mx_w;
	wire signed [14:0] descriptor_mp_w;
	wire signed [12:0] descriptor_my_w;
	wire [12:0] descriptor_semantic_width_w;
	wire [15:0] descriptor_visual_height_w;
	wire signed [16:0] descriptor_timing_height_w;
	wire [15:0] descriptor_param_base_w;
	wire [15:0] descriptor_overplane_w;
	wire [3:0] descriptor_maps_wide_w;
	wire [3:0] descriptor_maps_high_w;
	wire [3:0] descriptor_effective_map_columns_w;
	wire [3:0] descriptor_bgmap_base_rounded_w;

	// Scheduler and row-pipeline interface.
	wire scheduler_start_ready_w;
	wire scheduler_start_valid_w;
	wire scheduler_done_w;
	wire scheduler_row_start_valid_w;
	wire scheduler_row_start_ready_w;
	wire [4:0] scheduler_row_start_world_w;
	wire [4:0] scheduler_row_start_strip_w;
	wire scheduler_row_start_first_w;
	wire [8:0] scheduler_row_start_screen_y_w;
	wire [15:0] scheduler_row_start_local_y_w;
	wire signed [17:0] scheduler_row_start_source_y_w;
	wire scheduler_geometry_valid_w;
	wire scheduler_geometry_ready_w;
	wire signed [14:0] scheduler_geometry_tile_start_w;
	wire signed [15:0] scheduler_geometry_tile_count_w;
	wire scheduler_prime_valid_w;
	wire scheduler_prime_ready_w;
	wire scheduler_tile_valid_w;
	wire scheduler_tile_ready_w;
	wire [4:0] scheduler_tile_world_w;
	wire [4:0] scheduler_tile_strip_w;
	wire [8:0] scheduler_tile_screen_y_w;
	wire [15:0] scheduler_tile_local_y_w;
	wire signed [17:0] scheduler_tile_source_y_w;
	wire [15:0] scheduler_tile_ordinal_w;
	wire [15:0] scheduler_tile_count_w;
	wire signed [14:0] scheduler_tile_index_w;
	wire signed [17:0] scheduler_tile_source_x_w;
	wire scheduler_tile_uses_prime_w;
	wire scheduler_tile_last_in_row_w;
	wire scheduler_tile_last_in_strip_w;

	// Row-pipeline diagnostics.
	wire pipeline_component_error_w;
	wire pipeline_row_context_mismatch_w;
	wire pipeline_geometry_unsupported_w;
	wire pipeline_scheduler_tag_mismatch_w;
	wire pipeline_ordinal_overflow_w;
	wire pipeline_coordinate_overflow_w;
	wire pipeline_producer_overflow_w;
	wire pipeline_producer_underflow_w;
	wire pipeline_row_context_valid_w;
	wire pipeline_param_busy_w;
	wire pipeline_geometry_busy_w;

	// Scheduler protocol diagnostics.
	wire scheduler_invalid_height_w;
	wire scheduler_invalid_strip_w;
	wire scheduler_invalid_geometry_w;
	wire scheduler_tile_index_overflow_w;
	wire scheduler_geometry_before_row_start_w;

	wire backend_quiescent_w = pipeline_downstream_idle_o &&
		!pipeline_busy_o && !pipeline_cleanup_busy_o &&
		(producer_outstanding_o == 2'd0) &&
		!row_producer_valid_o;
	// Admit commands from local state and the backend's rearm-ready signal.
	wire controller_quiescent_w = !pipeline_row_context_valid_w &&
		!pipeline_param_busy_w && !pipeline_geometry_busy_w &&
		!param_read_pending_o && !param_dram_cleanup_busy_i &&
		(producer_outstanding_o == 2'd0) && !row_producer_valid_o;
	wire command_window_w = !hbias_active_q && !scheduler_busy_o &&
		controller_quiescent_w && bg_diagnostic_rearm_ready_i;
	wire selected_kind_w = engine_cmd_kind_i == 2'd1;
	wire command_fire_w = scheduler_start_valid_w &&
		scheduler_start_ready_w;
	wire command_complete_w = hbias_active_q &&
		(scheduler_complete_q || scheduler_done_w) &&
		backend_quiescent_w && !scheduler_busy_o;
	wire scheduler_downstream_idle_w = pipeline_downstream_idle_o &&
		!pipeline_cleanup_busy_o;

	assign scheduler_start_valid_w = !reset_i && !engine_abort_i &&
		engine_cmd_valid_i && selected_kind_w && command_window_w;
	assign engine_cmd_ready_o = selected_kind_w && command_window_w &&
		scheduler_start_ready_w;
	assign engine_done_o = !reset_i && !engine_abort_i &&
		command_complete_w;
	assign command_accept_o = command_fire_w;
	assign hbias_active_o = hbias_active_q;
	assign hbias_quiescent_o = command_window_w;
	assign active_visual_height_o = visual_height_q;
	assign active_timing_height_o = timing_height_q;
	assign scheduler_done_pulse_o = scheduler_done_w;
	assign bg_diagnostic_rearm_o = command_fire_w;

	wire geometry_error_w = pipeline_geometry_unsupported_w ||
		pipeline_coordinate_overflow_w || scheduler_invalid_geometry_w ||
		scheduler_tile_index_overflow_w;
	wire protocol_error_w = pipeline_component_error_w ||
		pipeline_row_context_mismatch_w ||
		pipeline_scheduler_tag_mismatch_w ||
		pipeline_ordinal_overflow_w || pipeline_producer_overflow_w ||
		pipeline_producer_underflow_w ||
		scheduler_geometry_before_row_start_w ||
		scheduler_invalid_height_w || scheduler_invalid_strip_w ||
		(bg_diagnostic_rearm_o &&
		 !bg_diagnostic_rearm_accept_i) ||
		(hbias_active_q && bg_diagnostic_rearm_rejected_i);

`ifdef SYNTHESIS
	assign diag_command_accept_count_o = 32'd0;
	assign diag_command_done_count_o = 32'd0;
`endif

	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_hbias_decode u_hbias_decode
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.descriptor_accept_i(command_fire_w),
		.descriptor_i(engine_cmd_descriptor_i),
		.descriptor_raw_o(),
		.word0_o(),
		.lon_o(descriptor_left_on_w),
		.ron_o(descriptor_right_on_w),
		.kind_o(),
		.scx_o(),
		.scy_o(),
		.over_o(descriptor_over_w),
		.end_o(),
		.dummy_o(),
		.bgmap_base_raw_o(),
		.gx_o(descriptor_gx_w),
		.gp_o(descriptor_gp_w),
		.gy_o(descriptor_gy_w),
		.mx_o(descriptor_mx_w),
		.mp_o(descriptor_mp_w),
		.my_o(descriptor_my_w),
		.raw_w_o(),
		.raw_h_o(),
		.param_base_o(descriptor_param_base_w),
		.overplane_o(descriptor_overplane_w),
		.semantic_width_o(descriptor_semantic_width_w),
		.semantic_height_o(),
		.visual_height_o(descriptor_visual_height_w),
		.timing_height_o(descriptor_timing_height_w),
		.visual_end_y_exclusive_o(),
		.timing_end_y_exclusive_o(),
		.maps_wide_o(descriptor_maps_wide_w),
		.maps_high_o(descriptor_maps_high_w),
		.effective_map_count_o(),
		.effective_map_columns_o(
			descriptor_effective_map_columns_w),
		.bgmap_base_rounded_o(descriptor_bgmap_base_rounded_w),
		.descriptor_kind_mismatch_o(descriptor_kind_mismatch_o),
		.strict_overplane_high_o(strict_overplane_high_o),
		.raw_h_timing_conflict_o(raw_h_timing_conflict_o)
	);

	vip_xp_hbias_scheduler
	#(
		.COMPOSED_TIMING_CREDIT_ENABLE(
			COMPOSED_TIMING_CREDIT_ENABLE)
	)
	u_hbias_scheduler
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(engine_abort_i),
		.start_valid_i(scheduler_start_valid_w),
		.start_ready_o(scheduler_start_ready_w),
		.world_i(engine_cmd_world_i),
		.strip_i(engine_cmd_strip_i),
		.first_visit_i(engine_cmd_first_visit_i),
		.gy_i(descriptor_gy_w),
		.my_i(descriptor_my_w),
		.visual_height_i(descriptor_visual_height_w),
		.timing_height_i(descriptor_timing_height_w),
		.busy_o(scheduler_busy_o),
		.done_o(scheduler_done_w),
		.aborted_o(scheduler_aborted_o),
		.row_start_valid_o(scheduler_row_start_valid_w),
		.row_start_ready_i(scheduler_row_start_ready_w),
		.row_start_world_o(scheduler_row_start_world_w),
		.row_start_strip_o(scheduler_row_start_strip_w),
		.row_start_first_in_strip_o(scheduler_row_start_first_w),
		.row_start_screen_y_o(scheduler_row_start_screen_y_w),
		.row_start_local_y_o(scheduler_row_start_local_y_w),
		.row_start_source_y_o(scheduler_row_start_source_y_w),
		.row_geometry_valid_i(scheduler_geometry_valid_w),
		.row_geometry_ready_o(scheduler_geometry_ready_w),
		.row_geometry_tile_start_i(scheduler_geometry_tile_start_w),
		.row_geometry_tile_count_i(scheduler_geometry_tile_count_w),
		.row_prime_valid_i(scheduler_prime_valid_w),
		.row_prime_ready_o(scheduler_prime_ready_w),
		.tile_valid_o(scheduler_tile_valid_w),
		.tile_ready_i(scheduler_tile_ready_w),
		.tile_world_o(scheduler_tile_world_w),
		.tile_strip_o(scheduler_tile_strip_w),
		.tile_screen_y_o(scheduler_tile_screen_y_w),
		.tile_local_y_o(scheduler_tile_local_y_w),
		.tile_source_y_o(scheduler_tile_source_y_w),
		.tile_ordinal_o(scheduler_tile_ordinal_w),
		.tile_count_o(scheduler_tile_count_w),
		.tile_index_o(scheduler_tile_index_w),
		.tile_source_x_o(scheduler_tile_source_x_w),
		.tile_uses_prime_o(scheduler_tile_uses_prime_w),
		.tile_last_in_row_o(scheduler_tile_last_in_row_w),
		.tile_last_in_strip_o(scheduler_tile_last_in_strip_w),
		.downstream_idle_i(scheduler_downstream_idle_w),
		.state_o(scheduler_state_o),
		.state_ticks_remaining_o(scheduler_ticks_remaining_o),
		.diag_timing_reference_strip_ticks_o(
			timing_reference_strip_ticks_o),
		.diag_timing_reference_rows_o(timing_reference_rows_o),
		.diag_visual_only_rows_o(visual_only_rows_o),
		.diag_extent_conflict_o(extent_conflict_o),
		.diag_elapsed_ticks_o(scheduler_elapsed_ticks_o),
		.diag_fixed_ticks_o(),
		.diag_strip_ticks_o(),
		.diag_row_setup_ticks_o(),
		.diag_tile_ticks_o(),
		.diag_stall_ticks_o(),
		.diag_row_start_accept_count_o(
			scheduler_row_accept_count_o),
		.diag_geometry_accept_count_o(),
		.diag_prime_accept_count_o(),
		.diag_tile_accept_count_o(scheduler_tile_accept_count_o),
		.diag_rows_in_strip_o(scheduler_rows_in_strip_o),
		.diag_bottom_reserve_o(),
		.invalid_height_o(scheduler_invalid_height_w),
		.invalid_strip_o(scheduler_invalid_strip_w),
		.invalid_geometry_o(scheduler_invalid_geometry_w),
		.tile_index_overflow_o(scheduler_tile_index_overflow_w),
		.geometry_before_row_start_o(
			scheduler_geometry_before_row_start_w)
	);

	vip_xp_hbias_row_pipeline u_row_pipeline
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(engine_abort_i),
		.parallax_scale_i(parallax_scale_i),
		.gy_i(gy_q),
		.param_base_i(param_base_q),
		.mx_i(mx_q),
		.mp_i(mp_q),
		.semantic_width_i(semantic_width_q),
		.gx_i(gx_q),
		.gp_i(gp_q),
		.left_on_i(left_on_q),
		.right_on_i(right_on_q),
		.maps_wide_i(maps_wide_q),
		.maps_high_i(maps_high_q),
		.effective_map_columns_i(effective_map_columns_q),
		.bgmap_base_rounded_i(bgmap_base_rounded_q),
		.over_i(over_q),
		.overplane_i(overplane_q),
		.gplt_active_i(gplt_active_q),
		.scheduler_row_start_valid_i(scheduler_row_start_valid_w),
		.scheduler_row_start_ready_o(scheduler_row_start_ready_w),
		.scheduler_row_start_world_i(scheduler_row_start_world_w),
		.scheduler_row_start_strip_i(scheduler_row_start_strip_w),
		.scheduler_row_start_first_in_strip_i(
			scheduler_row_start_first_w),
		.scheduler_row_start_screen_y_i(
			scheduler_row_start_screen_y_w),
		.scheduler_row_start_local_y_i(
			scheduler_row_start_local_y_w),
		.scheduler_row_start_source_y_i(
			scheduler_row_start_source_y_w),
		.scheduler_row_geometry_valid_o(scheduler_geometry_valid_w),
		.scheduler_row_geometry_ready_i(scheduler_geometry_ready_w),
		.scheduler_row_geometry_tile_start_o(
			scheduler_geometry_tile_start_w),
		.scheduler_row_geometry_tile_count_o(
			scheduler_geometry_tile_count_w),
		.scheduler_row_prime_valid_o(scheduler_prime_valid_w),
		.scheduler_row_prime_ready_i(scheduler_prime_ready_w),
		.scheduler_tile_valid_i(scheduler_tile_valid_w),
		.scheduler_tile_ready_o(scheduler_tile_ready_w),
		.scheduler_tile_world_i(scheduler_tile_world_w),
		.scheduler_tile_strip_i(scheduler_tile_strip_w),
		.scheduler_tile_screen_y_i(scheduler_tile_screen_y_w),
		.scheduler_tile_local_y_i(scheduler_tile_local_y_w),
		.scheduler_tile_source_y_i(scheduler_tile_source_y_w),
		.scheduler_tile_ordinal_i(scheduler_tile_ordinal_w),
		.scheduler_tile_count_i(scheduler_tile_count_w),
		.scheduler_tile_index_i(scheduler_tile_index_w),
		.scheduler_tile_source_x_i(scheduler_tile_source_x_w),
		.scheduler_tile_uses_prime_i(scheduler_tile_uses_prime_w),
		.scheduler_tile_last_in_row_i(
			scheduler_tile_last_in_row_w),
		.scheduler_tile_last_in_strip_i(
			scheduler_tile_last_in_strip_w),
		.param_dram_req_o(param_dram_req_o),
		.param_dram_addr_o(param_dram_addr_o),
		.param_dram_accept_i(param_dram_accept_i),
		.param_dram_resp_valid_i(param_dram_resp_valid_i),
		.param_dram_resp_data_i(param_dram_resp_data_i),
		.param_dram_cleanup_busy_i(param_dram_cleanup_busy_i),
		.param_dram_stale_discard_i(param_dram_stale_discard_i),
		.bg_maps_wide_o(bg_maps_wide_o),
		.bg_maps_high_o(bg_maps_high_o),
		.bg_effective_map_columns_o(bg_effective_map_columns_o),
		.bg_bgmap_base_rounded_o(bg_bgmap_base_rounded_o),
		.bg_over_o(bg_over_o),
		.bg_overplane_o(bg_overplane_o),
		.bg_left_on_o(bg_left_on_o),
		.bg_right_on_o(bg_right_on_o),
		.bg_left_source_start_o(bg_left_source_start_o),
		.bg_right_source_start_o(bg_right_source_start_o),
		.bg_left_destination_start_o(bg_left_destination_start_o),
		.bg_right_destination_start_o(bg_right_destination_start_o),
		.bg_semantic_width_o(bg_semantic_width_o),
		.bg_gplt_active_o(bg_gplt_active_o),
		.bg_tile_row_valid_o(bg_tile_row_valid_o),
		.bg_tile_row_ready_i(bg_tile_row_ready_i),
		.bg_tile_row_load_o(bg_tile_row_load_o),
		.bg_tile_row_screen_y_o(bg_tile_row_screen_y_o),
		.bg_tile_row_source_y_o(bg_tile_row_source_y_o),
		.bg_tile_valid_o(bg_tile_valid_o),
		.bg_tile_ready_i(bg_tile_ready_i),
		.bg_tile_load_o(bg_tile_load_o),
		.bg_tile_ordinal_o(bg_tile_ordinal_o),
		.bg_tile_x_o(bg_tile_x_o),
		.bg_row_valid_o(bg_row_valid_o),
		.bg_row_ready_i(bg_row_ready_i),
		.bg_row_load_o(bg_row_load_o),
		.bg_row_tile_ordinal_o(bg_row_tile_ordinal_o),
		.bg_row_ordinal_o(bg_row_ordinal_o),
		.bg_row_source_index_o(bg_row_source_index_o),
		.bg_row_screen_y_o(bg_row_screen_y_o),
		.bg_row_source_y_o(bg_row_source_y_o),
		.bg_result_permit_o(bg_result_permit_o),
		.bg_raw_result_valid_i(bg_raw_result_valid_i),
		.bg_raw_result_accept_i(bg_raw_result_accept_i),
		.bg_raw_result_owner_i(bg_raw_result_owner_i),
		.bg_raw_result_load_i(bg_raw_result_load_i),
		.bg_raw_result_tile_ordinal_i(
			bg_raw_result_tile_ordinal_i),
		.bg_raw_result_row_ordinal_i(bg_raw_result_row_ordinal_i),
		.bg_raw_result_tile_x_i(bg_raw_result_tile_x_i),
		.bg_raw_result_screen_y_i(bg_raw_result_screen_y_i),
		.bg_raw_result_source_y_i(bg_raw_result_source_y_i),
		.bg_raw_result_source_index_i(bg_raw_result_source_index_i),
		.bg_raw_result_tile_row_screen_y_i(
			bg_raw_result_tile_row_screen_y_i),
		.bg_raw_result_tile_row_source_y_i(
			bg_raw_result_tile_row_source_y_i),
		.bg_raw_result_overplane_selected_i(
			bg_raw_result_overplane_selected_i),
		.bg_raw_result_strict_overplane_i(
			bg_raw_result_strict_overplane_i),
		.bg_token_valid_i(bg_token_valid_i),
		.bg_token_ready_o(bg_token_ready_o),
		.bg_token_accept_i(bg_token_accept_i),
		.bg_token_row_i(bg_token_row_i),
		.bg_token_left_base_x_i(bg_token_left_base_x_i),
		.bg_token_left_enable_i(bg_token_left_enable_i),
		.bg_token_left_active_i(bg_token_left_active_i),
		.bg_token_left_opaque_i(bg_token_left_opaque_i),
		.bg_token_left_values_i(bg_token_left_values_i),
		.bg_token_right_base_x_i(bg_token_right_base_x_i),
		.bg_token_right_enable_i(bg_token_right_enable_i),
		.bg_token_right_active_i(bg_token_right_active_i),
		.bg_token_right_opaque_i(bg_token_right_opaque_i),
		.bg_token_right_values_i(bg_token_right_values_i),
		.bg_token_owner_i(bg_token_owner_i),
		.bg_token_load_i(bg_token_load_i),
		.bg_token_tile_ordinal_i(bg_token_tile_ordinal_i),
		.bg_token_row_ordinal_i(bg_token_row_ordinal_i),
		.bg_token_tile_x_i(bg_token_tile_x_i),
		.bg_token_screen_y_i(bg_token_screen_y_i),
		.bg_token_source_y_i(bg_token_source_y_i),
		.bg_token_source_index_i(bg_token_source_index_i),
		.bg_token_tile_row_screen_y_i(
			bg_token_tile_row_screen_y_i),
		.bg_token_tile_row_source_y_i(
			bg_token_tile_row_source_y_i),
		.bg_token_overplane_selected_i(
			bg_token_overplane_selected_i),
		.bg_token_strict_overplane_i(bg_token_strict_overplane_i),
		.bg_context_accept_i(bg_context_accept_i),
		.bg_context_owner_valid_i(bg_context_owner_valid_i),
		.bg_active_context_owner_i(bg_active_context_owner_i),
		.bg_busy_i(bg_busy_i),
		.bg_fetch_busy_i(bg_fetch_busy_i),
		.bg_cleanup_busy_i(bg_cleanup_busy_i),
		.bg_dram_read_pending_i(bg_dram_read_pending_i),
		.bg_vrm_read_pending_i(bg_vrm_read_pending_i),
		.bg_cell_accept_i(bg_cell_accept_i),
		.bg_vrm_accept_i(bg_vrm_accept_i),
		.bg_unexpected_dram_response_i(
			bg_unexpected_dram_response_i),
		.bg_unexpected_vrm_response_i(
			bg_unexpected_vrm_response_i),
		.bg_response_capture_overflow_i(
			bg_response_capture_overflow_i),
		.bg_scheduler_tag_mismatch_i(bg_scheduler_tag_mismatch_i),
		.bg_concurrent_work_error_i(bg_concurrent_work_error_i),
		.bg_strict_overplane_seen_i(bg_strict_overplane_seen_i),
		.bg_map_index_overflow_seen_i(
			bg_map_index_overflow_seen_i),
		.row_producer_valid_o(row_producer_valid_o),
		.row_producer_ready_i(row_producer_ready_i),
		.row_producer_tile_ordinal_o(row_producer_tile_ordinal_o),
		.row_producer_row_o(row_producer_row_o),
		.row_producer_left_base_x_o(row_producer_left_base_x_o),
		.row_producer_left_enable_o(row_producer_left_enable_o),
		.row_producer_left_active_o(row_producer_left_active_o),
		.row_producer_left_opaque_o(row_producer_left_opaque_o),
		.row_producer_left_values_o(row_producer_left_values_o),
		.row_producer_right_base_x_o(row_producer_right_base_x_o),
		.row_producer_right_enable_o(row_producer_right_enable_o),
		.row_producer_right_active_o(row_producer_right_active_o),
		.row_producer_right_opaque_o(row_producer_right_opaque_o),
		.row_producer_right_values_o(row_producer_right_values_o),
		.row_producer_done_i(row_producer_done_i),
		.busy_o(pipeline_busy_o),
		.cleanup_busy_o(pipeline_cleanup_busy_o),
		.downstream_idle_o(pipeline_downstream_idle_o),
		.row_context_valid_o(pipeline_row_context_valid_w),
		.geometry_context_valid_o(),
		.active_tile_ordinal_o(),
		.active_tile_source_x_o(),
		.producer_outstanding_o(producer_outstanding_o),
		.param_busy_o(pipeline_param_busy_w),
		.geometry_busy_o(pipeline_geometry_busy_w),
		.fetch_busy_o(),
		.fetch_cleanup_busy_o(),
		.param_read_pending_o(param_read_pending_o),
		.cell_dram_read_pending_o(cell_dram_read_pending_o),
		.cell_vrm_read_pending_o(cell_vrm_read_pending_o),
		.blend_pending_o(),
		.source_conflict_o(source_conflict_o),
		.component_error_o(pipeline_component_error_w),
		.row_context_mismatch_o(pipeline_row_context_mismatch_w),
		.geometry_unsupported_o(pipeline_geometry_unsupported_w),
		.scheduler_tile_tag_mismatch_o(
			pipeline_scheduler_tag_mismatch_w),
		.ordinal_overflow_o(pipeline_ordinal_overflow_w),
		.coordinate_overflow_o(pipeline_coordinate_overflow_w),
		.producer_overflow_o(pipeline_producer_overflow_w),
		.producer_underflow_o(pipeline_producer_underflow_w),
		.diag_row_start_accept_count_o(),
		.diag_parameter_accept_count_o(),
		.diag_geometry_accept_count_o(),
		.diag_prime_accept_count_o(),
		.diag_cell_accept_count_o(),
		.diag_vrm_accept_count_o(),
		.diag_fetch_result_accept_count_o(),
		.diag_producer_accept_count_o(),
		.diag_producer_done_count_o()
	);

	/* verilator lint_on PINCONNECTEMPTY */

	always @(posedge clk_i) begin
		if (reset_i) begin
			hbias_active_q <= 1'b0;
			scheduler_complete_q <= 1'b0;
			left_on_q <= 1'b0;
			right_on_q <= 1'b0;
			gx_q <= 10'sd0;
			gp_q <= 10'sd0;
			gy_q <= 16'sd0;
			mx_q <= 13'sd0;
			mp_q <= 15'sd0;
			semantic_width_q <= 13'd0;
			visual_height_q <= 16'd0;
			timing_height_q <= 17'sd0;
			param_base_q <= 16'd0;
			maps_wide_q <= 4'd1;
			maps_high_q <= 4'd1;
			effective_map_columns_q <= 4'd1;
			bgmap_base_rounded_q <= 4'd0;
			over_q <= 1'b0;
			overplane_q <= 16'd0;
			gplt_active_q <= 32'd0;
			command_kind_mismatch_o <= 1'b0;
			geometry_error_o <= 1'b0;
			protocol_error_o <= 1'b0;
`ifndef SYNTHESIS
			diag_command_accept_count_o <= 32'd0;
			diag_command_done_count_o <= 32'd0;
`endif
		end else begin
			// Raw abort cancels work while memory tags remain until drained.
			if (engine_abort_i) begin
				hbias_active_q <= 1'b0;
				scheduler_complete_q <= 1'b0;
			end

			if (ce_i) begin
				if (geometry_error_w) begin
					geometry_error_o <= 1'b1;
				end
				if (protocol_error_w) begin
					protocol_error_o <= 1'b1;
				end
				if (engine_cmd_valid_i && !selected_kind_w &&
					command_window_w) begin
					command_kind_mismatch_o <= 1'b1;
				end

				if (!engine_abort_i) begin
					if (command_fire_w) begin
						hbias_active_q <= 1'b1;
						scheduler_complete_q <= 1'b0;
						left_on_q <= descriptor_left_on_w;
						right_on_q <= descriptor_right_on_w;
						gx_q <= descriptor_gx_w;
						gp_q <= descriptor_gp_w;
						gy_q <= descriptor_gy_w;
						mx_q <= descriptor_mx_w;
						mp_q <= descriptor_mp_w;
						semantic_width_q <=
							descriptor_semantic_width_w;
						visual_height_q <=
							descriptor_visual_height_w;
						timing_height_q <=
							descriptor_timing_height_w;
						param_base_q <= descriptor_param_base_w;
						maps_wide_q <= descriptor_maps_wide_w;
						maps_high_q <= descriptor_maps_high_w;
						effective_map_columns_q <=
							descriptor_effective_map_columns_w;
						bgmap_base_rounded_q <=
							descriptor_bgmap_base_rounded_w;
						over_q <= descriptor_over_w;
						overplane_q <= descriptor_overplane_w;
						gplt_active_q <= gplt_active_i;
`ifndef SYNTHESIS
						diag_command_accept_count_o <=
							diag_command_accept_count_o + 32'd1;
`endif
					end else if (command_complete_w) begin
						hbias_active_q <= 1'b0;
						scheduler_complete_q <= 1'b0;
					end else if (hbias_active_q && scheduler_done_w) begin
						scheduler_complete_q <= 1'b1;
					end

`ifndef SYNTHESIS
					if (engine_done_o) begin
						diag_command_done_count_o <=
							diag_command_done_count_o + 32'd1;
					end
`endif
				end
			end
		end
	end

endmodule

`timescale 1ns/1ps

// H-bias adapter for the common background descriptor record.
//
// Thin adapter: apart from three sticky policy bits, every port is a
// verbatim vip_xp_bg_descriptor_decode pass-through, kept so the decode
// cross-check bench can compare the two side by side.
//
// HOFST is row data read by the parameter streamer, not descriptor state.

module vip_xp_hbias_decode
(
	input  wire         clk_i,
	input  wire         reset_i,
	input  wire         ce_i,
	input  wire         descriptor_accept_i,
	input  wire [255:0] descriptor_i,

	output wire [255:0] descriptor_raw_o,
	output wire [15:0]  word0_o,
	output wire         lon_o,
	output wire         ron_o,
	output wire [1:0]   kind_o,
	output wire [1:0]   scx_o,
	output wire [1:0]   scy_o,
	output wire         over_o,
	output wire         end_o,
	output wire         dummy_o,
	output wire [3:0]   bgmap_base_raw_o,

	output wire signed [9:0]  gx_o,
	output wire signed [9:0]  gp_o,
	output wire signed [15:0] gy_o,
	output wire signed [12:0] mx_o,
	output wire signed [14:0] mp_o,
	output wire signed [12:0] my_o,
	output wire [15:0]        raw_w_o,
	output wire [15:0]        raw_h_o,
	output wire [15:0]        param_base_o,
	output wire [15:0]        overplane_o,

	output wire [12:0]        semantic_width_o,
	output wire signed [16:0] semantic_height_o,
	output wire [15:0]        visual_height_o,
	output wire signed [16:0] timing_height_o,
	output wire signed [17:0] visual_end_y_exclusive_o,
	output wire signed [17:0] timing_end_y_exclusive_o,

	output wire [3:0] maps_wide_o,
	output wire [3:0] maps_high_o,
	output wire [3:0] effective_map_count_o,
	output wire [3:0] effective_map_columns_o,
	output wire [3:0] bgmap_base_rounded_o,

	output reg descriptor_kind_mismatch_o,
	output reg strict_overplane_high_o,
	output reg raw_h_timing_conflict_o
);

	wire strict_overplane_high_w;
	wire raw_h_timing_conflict_w;

	vip_xp_bg_descriptor_decode u_common_decode
	(
		.descriptor_i(descriptor_i),
		.descriptor_raw_o(descriptor_raw_o),
		.word0_o(word0_o),
		.lon_o(lon_o),
		.ron_o(ron_o),
		.kind_o(kind_o),
		.scx_o(scx_o),
		.scy_o(scy_o),
		.over_o(over_o),
		.end_o(end_o),
		.dummy_o(dummy_o),
		.bgmap_base_raw_o(bgmap_base_raw_o),
		.gx_o(gx_o),
		.gp_o(gp_o),
		.gy_o(gy_o),
		.mx_o(mx_o),
		.mp_o(mp_o),
		.my_o(my_o),
		.raw_w_o(raw_w_o),
		.raw_h_o(raw_h_o),
		.param_base_o(param_base_o),
		.overplane_o(overplane_o),
		.semantic_width_o(semantic_width_o),
		.semantic_height_o(semantic_height_o),
		.visual_height_o(visual_height_o),
		.timing_height_o(timing_height_o),
		.visual_end_y_exclusive_o(visual_end_y_exclusive_o),
		.timing_end_y_exclusive_o(timing_end_y_exclusive_o),
		.maps_wide_o(maps_wide_o),
		.maps_high_o(maps_high_o),
		.effective_map_count_o(effective_map_count_o),
		.effective_map_columns_o(effective_map_columns_o),
		.bgmap_base_rounded_o(bgmap_base_rounded_o),
		.raw_h_timing_conflict_o(raw_h_timing_conflict_w),
		.strict_overplane_high_o(strict_overplane_high_w)
	);

	always @(posedge clk_i) begin
		if (reset_i) begin
			descriptor_kind_mismatch_o <= 1'b0;
			strict_overplane_high_o <= 1'b0;
			raw_h_timing_conflict_o <= 1'b0;
		end else if (ce_i && descriptor_accept_i) begin
			if (kind_o != 2'd1) begin
				descriptor_kind_mismatch_o <= 1'b1;
			end
			if (strict_overplane_high_w) begin
				strict_overplane_high_o <= 1'b1;
			end
			if (raw_h_timing_conflict_w) begin
				raw_h_timing_conflict_o <= 1'b1;
			end
		end
	end

endmodule

`timescale 1ns/1ps

// H-bias strip scheduler.
//
// One command visits one strip. The shipped core uses composed timing
// (COMPOSED_TIMING_CREDIT_ENABLE = 1): 23 command ticks per strip, with the
// remaining fixed work spread as 20 ticks on the first visit and eight later.
// Each row setup costs 98 CE and each source-union tile costs four CE. Late
// work extends only its state.
//
// The non-composed path (parameter = 0, bench-only) charges the full 880 CE
// fixed cost on the first visit instead.
//
// row_start_o begins parameter and geometry work for the real output row.
// Clipping does not rebase local row or source Y. Each tile covers both eyes.
//
// Subtract the measured nine-tick bottom adjustment from first-visit work on
// any strip whose world reaches the bottom of the screen.
// Completion waits for downstream work to drain.

module vip_xp_hbias_scheduler
#(
	parameter integer COMPOSED_TIMING_CREDIT_ENABLE = 0
)
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	// Held strip command.
	input  wire                 start_valid_i,
	output wire                 start_ready_o,
	input  wire [4:0]           world_i,
	input  wire [4:0]           strip_i,
	input  wire                 first_visit_i,
	input  wire signed [15:0]   gy_i,
	input  wire signed [12:0]   my_i,
	input  wire [15:0]          visual_height_i,
	input  wire signed [16:0]   timing_height_i,

	output wire                 busy_o,
	output reg                  done_o,
	output reg                  aborted_o,

	// Held row-start request for the non-rebased output row.
	output wire                 row_start_valid_o,
	input  wire                 row_start_ready_i,
	output wire [4:0]           row_start_world_o,
	output wire [4:0]           row_start_strip_o,
	output wire                 row_start_first_in_strip_o,
	output wire [8:0]           row_start_screen_y_o,
	output wire [15:0]          row_start_local_y_o,
	output wire signed [17:0]   row_start_source_y_o,

	// Held row geometry result.
	input  wire                 row_geometry_valid_i,
	output wire                 row_geometry_ready_o,
	input  wire signed [14:0]   row_geometry_tile_start_i,
	input  wire signed [15:0]   row_geometry_tile_count_i,

	// Held first-tile prime result; row setup waits for both it and geometry.
	input  wire                 row_prime_valid_i,
	output wire                 row_prime_ready_o,

	// Held stereo source tile with a four-CE minimum.
	output wire                 tile_valid_o,
	input  wire                 tile_ready_i,
	output wire [4:0]           tile_world_o,
	output wire [4:0]           tile_strip_o,
	output wire [8:0]           tile_screen_y_o,
	output wire [15:0]          tile_local_y_o,
	output wire signed [17:0]   tile_source_y_o,
	output wire [15:0]          tile_ordinal_o,
	output wire [15:0]          tile_count_o,
	output wire signed [14:0]   tile_index_o,
	output wire signed [17:0]   tile_source_x_o,
	output wire                 tile_uses_prime_o,
	output wire                 tile_last_in_row_o,
	output wire                 tile_last_in_strip_o,

	// Finish only after all accepted downstream work drains.
	input  wire                 downstream_idle_i,

	output wire [2:0]           state_o,
	output wire [9:0]           state_ticks_remaining_o,
`ifndef SYNTHESIS
	output reg  [7:0]           diag_timing_reference_strip_ticks_o,
	output reg  [3:0]           diag_timing_reference_rows_o,
	output reg  [3:0]           diag_visual_only_rows_o,
	output reg                  diag_extent_conflict_o,
	output reg  [31:0]          diag_elapsed_ticks_o,
	output reg  [15:0]          diag_fixed_ticks_o,
	output reg  [7:0]           diag_strip_ticks_o,
	output reg  [31:0]          diag_row_setup_ticks_o,
	output reg  [31:0]          diag_tile_ticks_o,
	output reg  [31:0]          diag_stall_ticks_o,
	output reg  [15:0]          diag_row_start_accept_count_o,
	output reg  [15:0]          diag_geometry_accept_count_o,
	output reg  [15:0]          diag_prime_accept_count_o,
	output reg  [31:0]          diag_tile_accept_count_o,
	output reg  [3:0]           diag_rows_in_strip_o,
	output reg  [3:0]           diag_bottom_reserve_o,
	output reg                  invalid_height_o,
	output reg                  invalid_strip_o,
	output reg                  invalid_geometry_o,
	output reg                  tile_index_overflow_o,
	output reg                  geometry_before_row_start_o
`else
	output wire [7:0]           diag_timing_reference_strip_ticks_o,
	output wire [3:0]           diag_timing_reference_rows_o,
	output wire [3:0]           diag_visual_only_rows_o,
	output wire                 diag_extent_conflict_o,
	output wire [31:0]          diag_elapsed_ticks_o,
	output wire [15:0]          diag_fixed_ticks_o,
	output wire [7:0]           diag_strip_ticks_o,
	output wire [31:0]          diag_row_setup_ticks_o,
	output wire [31:0]          diag_tile_ticks_o,
	output wire [31:0]          diag_stall_ticks_o,
	output wire [15:0]          diag_row_start_accept_count_o,
	output wire [15:0]          diag_geometry_accept_count_o,
	output wire [15:0]          diag_prime_accept_count_o,
	output wire [31:0]          diag_tile_accept_count_o,
	output wire [3:0]           diag_rows_in_strip_o,
	output wire [3:0]           diag_bottom_reserve_o,
	output wire                 invalid_height_o,
	output wire                 invalid_strip_o,
	output wire                 invalid_geometry_o,
	output wire                 tile_index_overflow_o,
	output wire                 geometry_before_row_start_o
`endif
);

	localparam [2:0]
		STATE_IDLE      = 3'd0,
		STATE_FIXED     = 3'd1,
		STATE_STRIP     = 3'd2,
		STATE_ROW_SETUP = 3'd3,
		STATE_TILE      = 3'd4,
		STATE_DRAIN     = 3'd5;

	localparam [9:0]
		FIXED_TICKS               = 10'd880,
		FIXED_WITH_BOTTOM_RESERVE = 10'd871,
		ROW_SETUP_TICKS           = 10'd98,
		TILE_TICKS                = 10'd4,
		COMPOSED_BASE_TICKS       = 10'd8,
		COMPOSED_FIRST_REMAINDER  = 10'd12,
		COMPOSED_BOTTOM_ADJUST    = 10'd9;

	reg [2:0] state_q;
	reg [9:0] state_ticks_remaining_q;

	reg [4:0] world_q;
	reg [4:0] strip_q;
	reg signed [15:0] gy_q;
	reg signed [12:0] my_q;
	reg [8:0] row_screen_start_q;
	reg [3:0] row_count_q;
	reg [3:0] row_ordinal_q;
	reg [5:0] strip_cost_q;

	reg row_start_accepted_q;
	reg geometry_accepted_q;
	reg prime_accepted_q;
	reg tile_accepted_q;
	reg signed [14:0] row_tile_start_q;
	reg [15:0] row_tile_count_q;
	reg [15:0] tile_ordinal_q;

	reg [9:0] fixed_cost_t;
	reg [5:0] strip_cost_t;
	reg [3:0] rows_t;
	reg [8:0] row_screen_start_t;
	reg signed [17:0] gy_ext_t;
	reg signed [17:0] height_ext_t;
	reg signed [17:0] end_y_t;
	reg signed [17:0] strip_y_t;
	reg signed [17:0] strip_end_t;
	reg signed [17:0] row_start_t;
	reg signed [17:0] row_end_t;
	reg signed [17:0] row_count_wide_t;
	reg height_positive_t;
	reg reaches_bottom_t;
	reg contains_top_t;
	reg contains_bottom_t;

`ifndef SYNTHESIS
	reg [5:0] timing_reference_strip_cost_t;
	reg [3:0] timing_reference_rows_t;
	reg [3:0] visual_only_rows_t;
	reg signed [17:0] timing_height_ext_t;
	reg signed [17:0] timing_end_y_t;
	reg signed [17:0] timing_row_start_t;
	reg signed [17:0] timing_row_end_t;
	reg signed [17:0] timing_row_count_wide_t;
	reg timing_contains_top_t;
	reg timing_contains_bottom_t;
	reg extent_conflict_t;
`endif

	// Keep bit nine through the add, then narrow explicitly.
	/* verilator lint_off UNUSEDSIGNAL */
	wire [9:0] current_screen_y_extended_w =
		{1'b0, row_screen_start_q} + {6'd0, row_ordinal_q};
	/* verilator lint_on UNUSEDSIGNAL */
	wire [8:0] current_screen_y_w =
		current_screen_y_extended_w[8:0];
	wire signed [16:0] current_local_y_signed_w =
		$signed({8'd0, current_screen_y_w}) -
		$signed({gy_q[15], gy_q});
	wire [15:0] current_local_y_w =
		current_local_y_signed_w[15:0];
	wire signed [17:0] current_source_y_w =
		{{5{my_q[12]}}, my_q} +
		{{1{current_local_y_signed_w[16]}},
		 current_local_y_signed_w};

	wire row_start_fire_w = ce_i && row_start_valid_o &&
		row_start_ready_i;
	wire geometry_fire_w = ce_i && row_geometry_valid_i &&
		row_geometry_ready_o;
	wire prime_fire_w = ce_i && row_prime_valid_i &&
		row_prime_ready_o;
	wire tile_fire_w = ce_i && tile_valid_o && tile_ready_i;

	wire row_start_complete_w = row_start_accepted_q ||
		row_start_fire_w;
	wire geometry_complete_w = geometry_accepted_q || geometry_fire_w;
	wire prime_complete_w = prime_accepted_q || prime_fire_w;
	wire tile_complete_w = tile_accepted_q || tile_fire_w;
	wire signed [14:0] completed_tile_start_w = geometry_fire_w ?
		row_geometry_tile_start_i : row_tile_start_q;
	wire signed [15:0] completed_tile_count_signed_w = geometry_fire_w ?
		row_geometry_tile_count_i : $signed(row_tile_count_q);
	wire [15:0] completed_tile_count_w =
		completed_tile_count_signed_w[15:0];
	wire completed_geometry_usable_w =
		!completed_tile_count_signed_w[15] &&
		(completed_tile_count_signed_w != 16'sd0);

	wire [16:0] next_tile_ordinal_w =
		{1'b0, tile_ordinal_q} + 17'd1;
	wire tile_is_last_w = next_tile_ordinal_w >=
		{1'b0, row_tile_count_q};
	wire row_is_last_w = ({1'b0, row_ordinal_q} + 5'd1) >=
		{1'b0, row_count_q};
	wire signed [16:0] current_tile_index_extended_w =
		{{2{row_tile_start_q[14]}}, row_tile_start_q} +
		$signed({1'b0, tile_ordinal_q});
	/* verilator lint_off UNUSEDSIGNAL */
	wire signed [19:0] current_tile_source_x_extended_w =
		{current_tile_index_extended_w, 3'b000};
	/* verilator lint_on UNUSEDSIGNAL */
`ifndef SYNTHESIS
	wire current_tile_index_overflow_w =
		(current_tile_index_extended_w[16:15] !=
		 {2{current_tile_index_extended_w[14]}});
`endif

	assign start_ready_o = ce_i && !reset_i && !abort_i && !done_o &&
		(state_q == STATE_IDLE);
	assign busy_o = state_q != STATE_IDLE;
	assign state_o = state_q;
	assign state_ticks_remaining_o = state_ticks_remaining_q;

	assign row_start_valid_o = !reset_i && !abort_i &&
		(state_q == STATE_ROW_SETUP) && !row_start_accepted_q;
	assign row_start_world_o = world_q;
	assign row_start_strip_o = strip_q;
	assign row_start_first_in_strip_o = row_ordinal_q == 4'd0;
	assign row_start_screen_y_o = current_screen_y_w;
	assign row_start_local_y_o = current_local_y_w;
	assign row_start_source_y_o = current_source_y_w;

	assign row_geometry_ready_o = ce_i && !reset_i && !abort_i &&
		(state_q == STATE_ROW_SETUP) && !geometry_accepted_q &&
		(row_start_accepted_q || row_start_fire_w);
	assign row_prime_ready_o = ce_i && !reset_i && !abort_i &&
		(state_q == STATE_ROW_SETUP) && !prime_accepted_q &&
		(geometry_accepted_q || geometry_fire_w);

	assign tile_valid_o = !reset_i && !abort_i &&
		(state_q == STATE_TILE) && !tile_accepted_q;
	assign tile_world_o = world_q;
	assign tile_strip_o = strip_q;
	assign tile_screen_y_o = current_screen_y_w;
	assign tile_local_y_o = current_local_y_w;
	assign tile_source_y_o = current_source_y_w;
	assign tile_ordinal_o = tile_ordinal_q;
	assign tile_count_o = row_tile_count_q;
	assign tile_index_o = current_tile_index_extended_w[14:0];
	assign tile_source_x_o = current_tile_source_x_extended_w[17:0];
	// Tile zero uses the row-prime context; later tiles issue normal fetches.
	assign tile_uses_prime_o = tile_ordinal_q == 16'd0;
	assign tile_last_in_row_o = tile_is_last_w;
	assign tile_last_in_strip_o = tile_is_last_w && row_is_last_w;

`ifdef SYNTHESIS
	assign diag_timing_reference_strip_ticks_o = 8'd0;
	assign diag_timing_reference_rows_o = 4'd0;
	assign diag_visual_only_rows_o = 4'd0;
	assign diag_extent_conflict_o = 1'b0;
	assign diag_elapsed_ticks_o = 32'd0;
	assign diag_fixed_ticks_o = 16'd0;
	assign diag_strip_ticks_o = 8'd0;
	assign diag_row_setup_ticks_o = 32'd0;
	assign diag_tile_ticks_o = 32'd0;
	assign diag_stall_ticks_o = 32'd0;
	assign diag_row_start_accept_count_o = 16'd0;
	assign diag_geometry_accept_count_o = 16'd0;
	assign diag_prime_accept_count_o = 16'd0;
	assign diag_tile_accept_count_o = 32'd0;
	assign diag_rows_in_strip_o = 4'd0;
	assign diag_bottom_reserve_o = 4'd0;
	assign invalid_height_o = 1'b0;
	assign invalid_strip_o = 1'b0;
	assign invalid_geometry_o = 1'b0;
	assign tile_index_overflow_o = 1'b0;
	assign geometry_before_row_start_o = 1'b0;
`endif

	// Top strips run to strip bottom; later strips stop at visible world end.
	always @* begin
		gy_ext_t = {{2{gy_i[15]}}, gy_i};
		height_ext_t = $signed({2'b00, visual_height_i});
		end_y_t = gy_ext_t + height_ext_t;
		strip_y_t = $signed({10'd0, strip_i, 3'b000});
		strip_end_t = strip_y_t + 18'sd8;
		height_positive_t = !timing_height_i[16] &&
			(timing_height_i != 17'sd0) &&
			(visual_height_i != 16'd0);
		reaches_bottom_t = height_positive_t && (end_y_t > 18'sd216);

		fixed_cost_t = 10'd0;
		if (COMPOSED_TIMING_CREDIT_ENABLE != 0) begin
			if (strip_i < 5'd28) begin
				fixed_cost_t = COMPOSED_BASE_TICKS;
				if (first_visit_i) begin
					fixed_cost_t = fixed_cost_t +
						COMPOSED_FIRST_REMAINDER;
					if (reaches_bottom_t) begin
						fixed_cost_t = fixed_cost_t -
							COMPOSED_BOTTOM_ADJUST;
					end
				end
			end
		end else if (first_visit_i) begin
			fixed_cost_t = reaches_bottom_t ?
				FIXED_WITH_BOTTOM_RESERVE : FIXED_TICKS;
		end

		strip_cost_t = 6'd0;
		rows_t = 4'd0;
		row_screen_start_t = strip_y_t[8:0];
		row_start_t = strip_y_t;
		row_end_t = strip_y_t;
		row_count_wide_t = 18'sd0;
		contains_top_t = 1'b0;
		contains_bottom_t = 1'b0;

		if ((strip_i < 5'd28) && height_positive_t &&
			(end_y_t > strip_y_t)) begin
			if (gy_ext_t >= strip_end_t) begin
				strip_cost_t = (strip_i == 5'd27) ? 6'd4 : 6'd5;
			end else begin
				contains_top_t = gy_ext_t >= strip_y_t;
				contains_bottom_t = end_y_t <= strip_end_t;
				if (contains_top_t) begin
					strip_cost_t = 6'd12;
				end else if (contains_bottom_t) begin
					strip_cost_t = 6'd13;
				end else begin
					strip_cost_t = 6'd16;
				end
				if ((strip_i == 5'd0) && !contains_top_t) begin
					strip_cost_t = strip_cost_t +
						(contains_bottom_t ? 6'd6 : 6'd4);
				end

				row_start_t = contains_top_t ? gy_ext_t : strip_y_t;
				if (!contains_top_t && (end_y_t < strip_end_t)) begin
					row_end_t = end_y_t;
				end else begin
					row_end_t = strip_end_t;
				end
				row_count_wide_t = row_end_t - row_start_t;
				if (row_count_wide_t > 18'sd8) begin
					rows_t = 4'd8;
				end else if (row_count_wide_t > 18'sd0) begin
					rows_t = row_count_wide_t[3:0];
				end
				row_screen_start_t = row_start_t[8:0];
			end
		end

`ifndef SYNTHESIS
		// Simulation-only comparison against measured raw-H timing.
		timing_height_ext_t =
			{{1{timing_height_i[16]}}, timing_height_i};
		timing_end_y_t = gy_ext_t + timing_height_ext_t;
		timing_reference_strip_cost_t = 6'd0;
		timing_reference_rows_t = 4'd0;
		timing_row_start_t = strip_y_t;
		timing_row_end_t = strip_y_t;
		timing_row_count_wide_t = 18'sd0;
		timing_contains_top_t = 1'b0;
		timing_contains_bottom_t = 1'b0;
		extent_conflict_t = height_positive_t &&
			(timing_height_i != $signed({1'b0, visual_height_i}));

		if ((strip_i < 5'd28) && height_positive_t &&
			(timing_end_y_t > strip_y_t)) begin
			if (gy_ext_t >= strip_end_t) begin
				timing_reference_strip_cost_t =
					(strip_i == 5'd27) ? 6'd4 : 6'd5;
			end else begin
				timing_contains_top_t = gy_ext_t >= strip_y_t;
				timing_contains_bottom_t =
					timing_end_y_t <= strip_end_t;
				if (timing_contains_top_t) begin
					timing_reference_strip_cost_t = 6'd12;
				end else if (timing_contains_bottom_t) begin
					timing_reference_strip_cost_t = 6'd13;
				end else begin
					timing_reference_strip_cost_t = 6'd16;
				end
				if ((strip_i == 5'd0) &&
					!timing_contains_top_t) begin
					timing_reference_strip_cost_t =
						timing_reference_strip_cost_t +
						(timing_contains_bottom_t ? 6'd6 : 6'd4);
				end

				timing_row_start_t = timing_contains_top_t ?
					gy_ext_t : strip_y_t;
				if (!timing_contains_top_t &&
					(timing_end_y_t < strip_end_t)) begin
					timing_row_end_t = timing_end_y_t;
				end else begin
					timing_row_end_t = strip_end_t;
				end
				timing_row_count_wide_t =
					timing_row_end_t - timing_row_start_t;
				if (timing_row_count_wide_t > 18'sd8) begin
					timing_reference_rows_t = 4'd8;
				end else if (timing_row_count_wide_t > 18'sd0) begin
					timing_reference_rows_t =
						timing_row_count_wide_t[3:0];
				end
			end
		end

		if (rows_t > timing_reference_rows_t) begin
			visual_only_rows_t = rows_t - timing_reference_rows_t;
		end else begin
			visual_only_rows_t = 4'd0;
		end
`endif
	end

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			state_ticks_remaining_q <= 10'd0;
			world_q <= 5'd0;
			strip_q <= 5'd0;
			gy_q <= 16'sd0;
			my_q <= 13'sd0;
			row_screen_start_q <= 9'd0;
			row_count_q <= 4'd0;
			row_ordinal_q <= 4'd0;
			strip_cost_q <= 6'd0;
			row_start_accepted_q <= 1'b0;
			geometry_accepted_q <= 1'b0;
			prime_accepted_q <= 1'b0;
			tile_accepted_q <= 1'b0;
			row_tile_start_q <= 15'sd0;
			row_tile_count_q <= 16'd0;
			tile_ordinal_q <= 16'd0;
			done_o <= 1'b0;
			aborted_o <= 1'b0;
`ifndef SYNTHESIS
			diag_timing_reference_strip_ticks_o <= 8'd0;
			diag_timing_reference_rows_o <= 4'd0;
			diag_visual_only_rows_o <= 4'd0;
			diag_extent_conflict_o <= 1'b0;
			diag_elapsed_ticks_o <= 32'd0;
			diag_fixed_ticks_o <= 16'd0;
			diag_strip_ticks_o <= 8'd0;
			diag_row_setup_ticks_o <= 32'd0;
			diag_tile_ticks_o <= 32'd0;
			diag_stall_ticks_o <= 32'd0;
			diag_row_start_accept_count_o <= 16'd0;
			diag_geometry_accept_count_o <= 16'd0;
			diag_prime_accept_count_o <= 16'd0;
			diag_tile_accept_count_o <= 32'd0;
			diag_rows_in_strip_o <= 4'd0;
			diag_bottom_reserve_o <= 4'd0;
			invalid_height_o <= 1'b0;
			invalid_strip_o <= 1'b0;
			invalid_geometry_o <= 1'b0;
			tile_index_overflow_o <= 1'b0;
			geometry_before_row_start_o <= 1'b0;
`endif
		end else if (abort_i) begin
			state_q <= STATE_IDLE;
			state_ticks_remaining_q <= 10'd0;
			row_start_accepted_q <= 1'b0;
			geometry_accepted_q <= 1'b0;
			prime_accepted_q <= 1'b0;
			tile_accepted_q <= 1'b0;
			row_tile_count_q <= 16'd0;
			tile_ordinal_q <= 16'd0;
			done_o <= 1'b0;
			aborted_o <= 1'b1;
		end else if (ce_i) begin
			done_o <= 1'b0;
`ifndef SYNTHESIS
			if ((state_q == STATE_ROW_SETUP) &&
				row_geometry_valid_i && !row_start_accepted_q &&
				!row_start_fire_w) begin
				geometry_before_row_start_o <= 1'b1;
			end
`endif
			case (state_q)
				STATE_IDLE: begin
					state_ticks_remaining_q <= 10'd0;
					row_start_accepted_q <= 1'b0;
					geometry_accepted_q <= 1'b0;
					prime_accepted_q <= 1'b0;
					tile_accepted_q <= 1'b0;
					if (start_valid_i && start_ready_o) begin
						world_q <= world_i;
						strip_q <= strip_i;
						gy_q <= gy_i;
						my_q <= my_i;
						row_screen_start_q <= row_screen_start_t;
						row_count_q <= rows_t;
						row_ordinal_q <= 4'd0;
						strip_cost_q <= strip_cost_t;
						row_tile_start_q <= 15'sd0;
						row_tile_count_q <= 16'd0;
						tile_ordinal_q <= 16'd0;
						aborted_o <= 1'b0;
`ifndef SYNTHESIS
						diag_timing_reference_strip_ticks_o <=
							{2'd0, timing_reference_strip_cost_t};
						diag_timing_reference_rows_o <=
							timing_reference_rows_t;
						diag_visual_only_rows_o <= visual_only_rows_t;
						diag_extent_conflict_o <= extent_conflict_t;
						diag_elapsed_ticks_o <= 32'd0;
						diag_fixed_ticks_o <= 16'd0;
						diag_strip_ticks_o <= 8'd0;
						diag_row_setup_ticks_o <= 32'd0;
						diag_tile_ticks_o <= 32'd0;
						diag_stall_ticks_o <= 32'd0;
						diag_row_start_accept_count_o <= 16'd0;
						diag_geometry_accept_count_o <= 16'd0;
						diag_prime_accept_count_o <= 16'd0;
						diag_tile_accept_count_o <= 32'd0;
						diag_rows_in_strip_o <= rows_t;
						diag_bottom_reserve_o <=
							(first_visit_i && reaches_bottom_t) ? 4'd9 : 4'd0;
						invalid_height_o <= !height_positive_t;
						invalid_strip_o <= strip_i >= 5'd28;
						invalid_geometry_o <= 1'b0;
						tile_index_overflow_o <= 1'b0;
						geometry_before_row_start_o <= 1'b0;
`endif
						if (fixed_cost_t != 10'd0) begin
							state_q <= STATE_FIXED;
							state_ticks_remaining_q <= fixed_cost_t;
						end else if (strip_cost_t != 6'd0) begin
							state_q <= STATE_STRIP;
							state_ticks_remaining_q <= {4'd0, strip_cost_t};
						end else begin
							state_q <= STATE_IDLE;
							done_o <= 1'b1;
						end
					end
				end

				STATE_FIXED: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_fixed_ticks_o <= diag_fixed_ticks_o + 16'd1;
`endif
					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (strip_cost_q != 6'd0) begin
						state_q <= STATE_STRIP;
						state_ticks_remaining_q <= {4'd0, strip_cost_q};
					end else begin
						state_q <= STATE_IDLE;
						state_ticks_remaining_q <= 10'd0;
						done_o <= 1'b1;
					end
				end

				STATE_STRIP: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_strip_ticks_o <= diag_strip_ticks_o + 8'd1;
`endif
					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (row_count_q != 4'd0) begin
						state_q <= STATE_ROW_SETUP;
						state_ticks_remaining_q <= ROW_SETUP_TICKS;
						row_start_accepted_q <= 1'b0;
						geometry_accepted_q <= 1'b0;
						prime_accepted_q <= 1'b0;
					end else begin
						state_q <= STATE_IDLE;
						state_ticks_remaining_q <= 10'd0;
						done_o <= 1'b1;
					end
				end

				STATE_ROW_SETUP: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_row_setup_ticks_o <=
						diag_row_setup_ticks_o + 32'd1;
					if ((state_ticks_remaining_q == 10'd1) &&
						!(row_start_complete_w && geometry_complete_w &&
						  prime_complete_w)) begin
						diag_stall_ticks_o <= diag_stall_ticks_o + 32'd1;
					end
`endif
					if (row_start_fire_w) begin
						row_start_accepted_q <= 1'b1;
`ifndef SYNTHESIS
						diag_row_start_accept_count_o <=
							diag_row_start_accept_count_o + 16'd1;
`endif
					end
					if (geometry_fire_w) begin
						geometry_accepted_q <= 1'b1;
						row_tile_start_q <= row_geometry_tile_start_i;
						row_tile_count_q <=
							row_geometry_tile_count_i[15:0];
`ifndef SYNTHESIS
						diag_geometry_accept_count_o <=
							diag_geometry_accept_count_o + 16'd1;
						if (row_geometry_tile_count_i[15] ||
							(row_geometry_tile_count_i == 16'sd0)) begin
							invalid_geometry_o <= 1'b1;
						end
`endif
					end
					if (prime_fire_w) begin
						prime_accepted_q <= 1'b1;
`ifndef SYNTHESIS
						diag_prime_accept_count_o <=
							diag_prime_accept_count_o + 16'd1;
`endif
					end

					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (row_start_complete_w &&
						geometry_complete_w && prime_complete_w) begin
						row_start_accepted_q <= 1'b0;
						geometry_accepted_q <= 1'b0;
						prime_accepted_q <= 1'b0;
						tile_ordinal_q <= 16'd0;
						if (completed_geometry_usable_w) begin
							row_tile_start_q <= completed_tile_start_w;
							row_tile_count_q <= completed_tile_count_w;
							state_q <= STATE_TILE;
							state_ticks_remaining_q <= TILE_TICKS;
							tile_accepted_q <= 1'b0;
						end else if (!row_is_last_w) begin
							row_ordinal_q <= row_ordinal_q + 4'd1;
							state_q <= STATE_ROW_SETUP;
							state_ticks_remaining_q <= ROW_SETUP_TICKS;
						end else if (downstream_idle_i) begin
							state_q <= STATE_IDLE;
							state_ticks_remaining_q <= 10'd0;
							done_o <= 1'b1;
						end else begin
							state_q <= STATE_DRAIN;
							state_ticks_remaining_q <= 10'd0;
						end
					end
				end

				STATE_TILE: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_tile_ticks_o <= diag_tile_ticks_o + 32'd1;
					if ((state_ticks_remaining_q == 10'd1) && !tile_complete_w) begin
						diag_stall_ticks_o <= diag_stall_ticks_o + 32'd1;
					end
`endif
					if (tile_fire_w) begin
						tile_accepted_q <= 1'b1;
`ifndef SYNTHESIS
						diag_tile_accept_count_o <=
							diag_tile_accept_count_o + 32'd1;
						if (current_tile_index_overflow_w) begin
							tile_index_overflow_o <= 1'b1;
						end
`endif
					end
					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (tile_complete_w) begin
						tile_accepted_q <= 1'b0;
						if (!tile_is_last_w) begin
							tile_ordinal_q <= tile_ordinal_q + 16'd1;
							state_ticks_remaining_q <= TILE_TICKS;
						end else if (!row_is_last_w) begin
							row_ordinal_q <= row_ordinal_q + 4'd1;
							tile_ordinal_q <= 16'd0;
							state_q <= STATE_ROW_SETUP;
							state_ticks_remaining_q <= ROW_SETUP_TICKS;
							row_start_accepted_q <= 1'b0;
							geometry_accepted_q <= 1'b0;
							prime_accepted_q <= 1'b0;
						end else if (downstream_idle_i) begin
							state_q <= STATE_IDLE;
							state_ticks_remaining_q <= 10'd0;
							done_o <= 1'b1;
						end else begin
							state_q <= STATE_DRAIN;
							state_ticks_remaining_q <= 10'd0;
						end
					end
				end

				STATE_DRAIN: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					// Count every downstream drain edge after natural work ends.
					diag_stall_ticks_o <= diag_stall_ticks_o + 32'd1;
`endif
					if (downstream_idle_i) begin
						state_q <= STATE_IDLE;
						done_o <= 1'b1;
					end
				end

				default: begin
					state_q <= STATE_IDLE;
					state_ticks_remaining_q <= 10'd0;
					row_start_accepted_q <= 1'b0;
					geometry_accepted_q <= 1'b0;
					prime_accepted_q <= 1'b0;
					tile_accepted_q <= 1'b0;
				end
			endcase
		end
	end

endmodule

`timescale 1ns/1ps

// H-bias active-row pipeline.
//
// Convert a row start into PARAM reads, stereo geometry, tile fetches, and row
// tokens. Tile zero is primed during setup; each later token launches the next
// tile to keep the measured four-CE cadence.
//
// PARAM is H-bias-specific; CELL and character work use the shared backend.
// Accepting one token may present the next tile on the same CE.

module vip_xp_hbias_row_pipeline
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,
	input  wire [2:0]           parallax_scale_i,

	// Background settings captured at row start.
	input  wire signed [15:0]   gy_i,
	input  wire [15:0]          param_base_i,
	input  wire signed [12:0]   mx_i,
	input  wire signed [14:0]   mp_i,
	input  wire [12:0]          semantic_width_i,
	input  wire signed [9:0]    gx_i,
	input  wire signed [9:0]    gp_i,
	input  wire                 left_on_i,
	input  wire                 right_on_i,
	input  wire [3:0]           maps_wide_i,
	input  wire [3:0]           maps_high_i,
	input  wire [3:0]           effective_map_columns_i,
	input  wire [3:0]           bgmap_base_rounded_i,
	input  wire                 over_i,
	input  wire [15:0]          overplane_i,
	input  wire [31:0]          gplt_active_i,

	// Held row-start request.
	input  wire                 scheduler_row_start_valid_i,
	output wire                 scheduler_row_start_ready_o,
	input  wire [4:0]           scheduler_row_start_world_i,
	input  wire [4:0]           scheduler_row_start_strip_i,
	input  wire                 scheduler_row_start_first_in_strip_i,
	input  wire [8:0]           scheduler_row_start_screen_y_i,
	input  wire [15:0]          scheduler_row_start_local_y_i,
	input  wire signed [17:0]   scheduler_row_start_source_y_i,

	// Held row geometry response.
	output wire                 scheduler_row_geometry_valid_o,
	input  wire                 scheduler_row_geometry_ready_i,
	output wire signed [14:0]   scheduler_row_geometry_tile_start_o,
	output wire signed [15:0]   scheduler_row_geometry_tile_count_o,

	// Held first-tile prime completion.
	output wire                 scheduler_row_prime_valid_o,
	input  wire                 scheduler_row_prime_ready_i,

	// Held tile; ready means its matching row token transferred.
	input  wire                 scheduler_tile_valid_i,
	output wire                 scheduler_tile_ready_o,
	input  wire [4:0]           scheduler_tile_world_i,
	input  wire [4:0]           scheduler_tile_strip_i,
	input  wire [8:0]           scheduler_tile_screen_y_i,
	input  wire [15:0]          scheduler_tile_local_y_i,
	input  wire signed [17:0]   scheduler_tile_source_y_i,
	input  wire [15:0]          scheduler_tile_ordinal_i,
	input  wire [15:0]          scheduler_tile_count_i,
	input  wire signed [14:0]   scheduler_tile_index_i,
	input  wire signed [17:0]   scheduler_tile_source_x_i,
	input  wire                 scheduler_tile_uses_prime_i,
	input  wire                 scheduler_tile_last_in_row_i,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire                 scheduler_tile_last_in_strip_i,
	/* verilator lint_on UNUSEDSIGNAL */

	// PARAM DRAM client.
	output wire                 param_dram_req_o,
	output wire [15:0]          param_dram_addr_o,
	input  wire                 param_dram_accept_i,
	input  wire                 param_dram_resp_valid_i,
	input  wire [15:0]          param_dram_resp_data_i,
	input  wire                 param_dram_cleanup_busy_i,
	input  wire                 param_dram_stale_discard_i,

	// Shared backend uses the row-start settings.
	output wire [3:0]           bg_maps_wide_o,
	output wire [3:0]           bg_maps_high_o,
	output wire [3:0]           bg_effective_map_columns_o,
	output wire [3:0]           bg_bgmap_base_rounded_o,
	output wire                 bg_over_o,
	output wire [15:0]          bg_overplane_o,
	output wire                 bg_left_on_o,
	output wire                 bg_right_on_o,
	output wire signed [17:0]   bg_left_source_start_o,
	output wire signed [17:0]   bg_right_source_start_o,
	output wire signed [17:0]   bg_left_destination_start_o,
	output wire signed [17:0]   bg_right_destination_start_o,
	output wire [12:0]          bg_semantic_width_o,
	output wire [31:0]          bg_gplt_active_o,

	output wire                 bg_tile_row_valid_o,
	input  wire                 bg_tile_row_ready_i,
	output wire [0:0]           bg_tile_row_load_o,
	output wire [8:0]           bg_tile_row_screen_y_o,
	output wire signed [16:0]   bg_tile_row_source_y_o,
	output wire                 bg_tile_valid_o,
	input  wire                 bg_tile_ready_i,
	output wire [0:0]           bg_tile_load_o,
	output wire [12:0]          bg_tile_ordinal_o,
	output wire signed [15:0]   bg_tile_x_o,
	output wire                 bg_row_valid_o,
	input  wire                 bg_row_ready_i,
	output wire [0:0]           bg_row_load_o,
	output wire [12:0]          bg_row_tile_ordinal_o,
	output wire [2:0]           bg_row_ordinal_o,
	output wire [2:0]           bg_row_source_index_o,
	output wire [8:0]           bg_row_screen_y_o,
	output wire signed [16:0]   bg_row_source_y_o,
	output wire                 bg_result_permit_o,

	// Marks the CE that moves a fetch result into blend.
	input  wire                 bg_raw_result_valid_i,
	input  wire                 bg_raw_result_accept_i,
	input  wire [1:0]           bg_raw_result_owner_i,
	input  wire [0:0]           bg_raw_result_load_i,
	input  wire [12:0]          bg_raw_result_tile_ordinal_i,
	input  wire [2:0]           bg_raw_result_row_ordinal_i,
	input  wire signed [15:0]   bg_raw_result_tile_x_i,
	input  wire [8:0]           bg_raw_result_screen_y_i,
	input  wire signed [16:0]   bg_raw_result_source_y_i,
	input  wire [2:0]           bg_raw_result_source_index_i,
	input  wire [8:0]           bg_raw_result_tile_row_screen_y_i,
	input  wire signed [16:0]   bg_raw_result_tile_row_source_y_i,
	input  wire                 bg_raw_result_overplane_selected_i,
	input  wire                 bg_raw_result_strict_overplane_i,

	// Held blend token and source tag.
	input  wire                 bg_token_valid_i,
	output wire                 bg_token_ready_o,
	input  wire                 bg_token_accept_i,
	input  wire [2:0]           bg_token_row_i,
	input  wire signed [15:0]   bg_token_left_base_x_i,
	input  wire                 bg_token_left_enable_i,
	input  wire [7:0]           bg_token_left_active_i,
	input  wire [7:0]           bg_token_left_opaque_i,
	input  wire [15:0]          bg_token_left_values_i,
	input  wire signed [15:0]   bg_token_right_base_x_i,
	input  wire                 bg_token_right_enable_i,
	input  wire [7:0]           bg_token_right_active_i,
	input  wire [7:0]           bg_token_right_opaque_i,
	input  wire [15:0]          bg_token_right_values_i,
	input  wire [1:0]           bg_token_owner_i,
	input  wire [0:0]           bg_token_load_i,
	input  wire [12:0]          bg_token_tile_ordinal_i,
	input  wire [2:0]           bg_token_row_ordinal_i,
	input  wire signed [15:0]   bg_token_tile_x_i,
	input  wire [8:0]           bg_token_screen_y_i,
	input  wire signed [16:0]   bg_token_source_y_i,
	input  wire [2:0]           bg_token_source_index_i,
	input  wire [8:0]           bg_token_tile_row_screen_y_i,
	input  wire signed [16:0]   bg_token_tile_row_source_y_i,
	input  wire                 bg_token_overplane_selected_i,
	input  wire                 bg_token_strict_overplane_i,

	// Context ownership and physical status from the H-bias controller.
	input  wire                 bg_context_accept_i,
	input  wire                 bg_context_owner_valid_i,
	input  wire [1:0]           bg_active_context_owner_i,
	input  wire                 bg_busy_i,
	input  wire                 bg_fetch_busy_i,
	input  wire                 bg_cleanup_busy_i,
	input  wire                 bg_dram_read_pending_i,
	input  wire                 bg_vrm_read_pending_i,
	input  wire                 bg_cell_accept_i,
	input  wire                 bg_vrm_accept_i,
	input  wire                 bg_unexpected_dram_response_i,
	input  wire                 bg_unexpected_vrm_response_i,
	input  wire                 bg_response_capture_overflow_i,
	input  wire                 bg_scheduler_tag_mismatch_i,
	input  wire                 bg_concurrent_work_error_i,
	input  wire                 bg_strict_overplane_seen_i,
	input  wire                 bg_map_index_overflow_seen_i,

	// Registered stereo row token with an internal ordinal tag.
	output wire                 row_producer_valid_o,
	input  wire                 row_producer_ready_i,
	output wire [15:0]          row_producer_tile_ordinal_o,
	output wire [2:0]           row_producer_row_o,
	output wire signed [15:0]   row_producer_left_base_x_o,
	output wire                 row_producer_left_enable_o,
	output wire [7:0]           row_producer_left_active_o,
	output wire [7:0]           row_producer_left_opaque_o,
	output wire [15:0]          row_producer_left_values_o,
	output wire signed [15:0]   row_producer_right_base_x_o,
	output wire                 row_producer_right_enable_o,
	output wire [7:0]           row_producer_right_active_o,
	output wire [7:0]           row_producer_right_opaque_o,
	output wire [15:0]          row_producer_right_values_o,
	input  wire                 row_producer_done_i,

	// Cleanup, active ownership, and protocol diagnostics.
	output wire                 busy_o,
	output wire                 cleanup_busy_o,
	output wire                 downstream_idle_o,
	output wire                 row_context_valid_o,
	output wire                 geometry_context_valid_o,
	output wire [15:0]          active_tile_ordinal_o,
	output wire signed [17:0]   active_tile_source_x_o,
	output wire [1:0]           producer_outstanding_o,
	output wire                 param_busy_o,
	output wire                 geometry_busy_o,
	output wire                 fetch_busy_o,
	output wire                 fetch_cleanup_busy_o,
	output wire                 param_read_pending_o,
	output wire                 cell_dram_read_pending_o,
	output wire                 cell_vrm_read_pending_o,
	output wire                 blend_pending_o,
	output wire                 source_conflict_o,
	output wire                 component_error_o,
	output reg                  row_context_mismatch_o,
	output reg                  geometry_unsupported_o,
	output reg                  scheduler_tile_tag_mismatch_o,
	output reg                  ordinal_overflow_o,
	output reg                  coordinate_overflow_o,
	output reg                  producer_overflow_o,
	output reg                  producer_underflow_o,
`ifndef SYNTHESIS
	output reg  [31:0]          diag_row_start_accept_count_o,
	output reg  [31:0]          diag_parameter_accept_count_o,
	output reg  [31:0]          diag_geometry_accept_count_o,
	output reg  [31:0]          diag_prime_accept_count_o,
	output reg  [31:0]          diag_cell_accept_count_o,
	output reg  [31:0]          diag_vrm_accept_count_o,
	output reg  [31:0]          diag_fetch_result_accept_count_o,
	output reg  [31:0]          diag_producer_accept_count_o,
	output reg  [31:0]          diag_producer_done_count_o
`else
	output wire [31:0]          diag_row_start_accept_count_o,
	output wire [31:0]          diag_parameter_accept_count_o,
	output wire [31:0]          diag_geometry_accept_count_o,
	output wire [31:0]          diag_prime_accept_count_o,
	output wire [31:0]          diag_cell_accept_count_o,
	output wire [31:0]          diag_vrm_accept_count_o,
	output wire [31:0]          diag_fetch_result_accept_count_o,
	output wire [31:0]          diag_producer_accept_count_o,
	output wire [31:0]          diag_producer_done_count_o
`endif
);

	localparam [3:0]
		STATE_IDLE          = 4'd0,
		STATE_PARAMETER     = 4'd1,
		STATE_GEOMETRY      = 4'd2,
		STATE_FETCH_CONTEXT = 4'd3,
		STATE_FETCH_TILE    = 4'd4,
		STATE_FETCH_ROW     = 4'd5,
		// WAIT_TOKEN and WAIT_DONE are parking states: no case arm
		// matches them, no output is qualified on them, and the row
		// retire path is what leaves them.
		STATE_WAIT_TOKEN    = 4'd6,
		STATE_WAIT_DONE     = 4'd7,
		STATE_EMPTY_PRIME   = 4'd8;
	localparam [1:0] OWNER_HBIAS = 2'd2;

	reg [3:0] state_q;
	reg row_context_valid_q;
	reg geometry_context_valid_q;
	reg row_load_q;

	reg [4:0] row_world_q;
	reg [4:0] row_strip_q;
	reg [8:0] row_screen_y_q;
	reg [15:0] row_local_y_q;
	reg signed [17:0] row_source_y_q;

	reg signed [12:0] mx_q;
	reg signed [14:0] mp_q;
	reg [12:0] semantic_width_q;
	reg signed [9:0] gx_q;
	reg signed [9:0] gp_q;
	reg left_on_q;
	reg right_on_q;
	reg [3:0] maps_wide_q;
	reg [3:0] maps_high_q;
	reg [3:0] effective_map_columns_q;
	reg [3:0] bgmap_base_rounded_q;
	reg over_q;
	reg [15:0] overplane_q;
	reg [31:0] gplt_active_q;

	reg signed [17:0] left_source_start_q;
	reg signed [17:0] right_source_start_q;
	reg signed [17:0] left_destination_start_q;
	reg signed [17:0] right_destination_start_q;
	reg [15:0] geometry_tile_count_q;

	reg [15:0] work_tile_ordinal_q;
	reg signed [17:0] work_tile_source_x_q;
	reg raw_metadata_valid_q;
	reg raw_overplane_selected_q;
	reg raw_strict_overplane_q;
	reg prime_pending_q;
	reg final_token_accepted_q;
	reg [1:0] producer_outstanding_q;

	wire param_row_ready_w;
	wire param_result_valid_w;
	wire param_result_ready_w;
	/* verilator lint_off UNUSEDSIGNAL */
	wire [4:0] param_result_world_w;
	wire [4:0] param_result_strip_w;
	/* verilator lint_on UNUSEDSIGNAL */
	wire [8:0] param_result_screen_y_w;
	wire [15:0] param_result_local_row_w;
	/* verilator lint_off UNUSEDSIGNAL */
	wire signed [17:0] param_result_hofst_left_w;
	wire signed [17:0] param_result_hofst_right_w;
	wire signed [18:0] param_result_hofst_sum_w =
		{param_result_hofst_left_w[17], param_result_hofst_left_w} +
		{param_result_hofst_right_w[17], param_result_hofst_right_w};
	wire signed [17:0] param_result_hofst_center_w =
		param_result_hofst_sum_w[18:1];
	wire signed [17:0] param_result_hofst_left_delta_w =
		param_result_hofst_left_w - param_result_hofst_center_w;
	wire signed [17:0] param_result_hofst_right_delta_w =
		param_result_hofst_right_w - param_result_hofst_center_w;
	wire signed [17:0] param_result_hofst_left_delta_scaled_w;
	wire signed [17:0] param_result_hofst_right_delta_scaled_w;
	wire signed [17:0] param_result_hofst_left_scaled_w =
		param_result_hofst_center_w +
		param_result_hofst_left_delta_scaled_w;
	wire signed [17:0] param_result_hofst_right_scaled_w =
		param_result_hofst_center_w +
		param_result_hofst_right_delta_scaled_w;
	/* verilator lint_on UNUSEDSIGNAL */
	wire param_result_source_conflict_w;
	wire param_cleanup_busy_w;
	wire param_source_conflict_seen_w;
	wire param_unexpected_response_w;
	wire param_capture_overflow_w;
	wire param_owner_mismatch_w;

	vip_stereo_scale_signed #(.WIDTH(18)) u_hofst_left_scale
	(
		.value_i(param_result_hofst_left_delta_w),
		.scale_i(parallax_scale_i),
		.value_o(param_result_hofst_left_delta_scaled_w)
	);

	vip_stereo_scale_signed #(.WIDTH(18)) u_hofst_right_scale
	(
		.value_i(param_result_hofst_right_delta_w),
		.scale_i(parallax_scale_i),
		.value_o(param_result_hofst_right_delta_scaled_w)
	);

	wire geometry_input_ready_w;
	wire geometry_output_valid_w;
	wire geometry_output_ready_w;
	wire signed [17:0] geometry_left_source_start_w;
	wire signed [17:0] geometry_right_source_start_w;
	wire signed [17:0] geometry_left_destination_start_w;
	wire signed [17:0] geometry_right_destination_start_w;
	wire signed [14:0] geometry_tile_floor_w;
	wire signed [15:0] geometry_tile_count_w;
	wire signed [17:0] geometry_first_tile_source_x_w;
	wire geometry_malformed_w;

	wire blend_output_ready_w;

	wire row_start_fire_w = ce_i && scheduler_row_start_valid_i &&
		scheduler_row_start_ready_o;
	wire parameter_fire_w = ce_i && param_result_valid_w &&
		param_result_ready_w;
	wire geometry_fire_w = ce_i && geometry_output_valid_w &&
		geometry_output_ready_w;
	wire geometry_supported_w = !geometry_malformed_w &&
		!geometry_tile_count_w[15] &&
		(geometry_tile_count_w != 16'sd0) &&
		(geometry_tile_count_w <= 16'sd8192);
	wire geometry_first_x_fits_w =
		geometry_first_tile_source_x_w[17:15] ==
		{3{geometry_first_tile_source_x_w[15]}};
	wire geometry_usable_w = geometry_supported_w &&
		geometry_first_x_fits_w;
	wire bg_context_hbias_w = bg_context_owner_valid_i &&
		(bg_active_context_owner_i == OWNER_HBIAS);
	wire bg_relevant_w = row_context_valid_q || bg_context_hbias_w;
	wire bg_token_relevant_w = bg_token_valid_i &&
		(row_context_valid_q || (bg_token_owner_i == OWNER_HBIAS));
	wire bg_fetch_busy_relevant_w = bg_relevant_w && bg_fetch_busy_i;
	wire bg_busy_relevant_w = bg_relevant_w && bg_busy_i;
	wire bg_cleanup_relevant_w = bg_relevant_w && bg_cleanup_busy_i;

	wire raw_result_tag_matches_w =
		(bg_raw_result_owner_i == OWNER_HBIAS) &&
		(bg_raw_result_load_i == row_load_q) &&
		(bg_raw_result_tile_ordinal_i == work_tile_ordinal_q[12:0]) &&
		(work_tile_ordinal_q[15:13] == 3'd0) &&
		(bg_raw_result_row_ordinal_i == 3'd0) &&
		(bg_raw_result_tile_x_i == work_tile_source_x_q[15:0]) &&
		(bg_raw_result_screen_y_i == row_screen_y_q) &&
		(bg_raw_result_source_y_i == row_source_y_q[16:0]) &&
		(bg_raw_result_source_index_i == row_source_y_q[2:0]) &&
		(bg_raw_result_tile_row_screen_y_i == row_screen_y_q) &&
		(bg_raw_result_tile_row_source_y_i == row_source_y_q[16:0]);
	wire token_tag_matches_work_w = raw_metadata_valid_q &&
		(bg_token_owner_i == OWNER_HBIAS) &&
		(bg_token_load_i == row_load_q) &&
		(bg_token_tile_ordinal_i == work_tile_ordinal_q[12:0]) &&
		(work_tile_ordinal_q[15:13] == 3'd0) &&
		(bg_token_row_ordinal_i == 3'd0) &&
		(bg_token_tile_x_i == work_tile_source_x_q[15:0]) &&
		(bg_token_screen_y_i == row_screen_y_q) &&
		(bg_token_source_y_i == row_source_y_q[16:0]) &&
		(bg_token_source_index_i == row_source_y_q[2:0]) &&
		(bg_token_tile_row_screen_y_i == row_screen_y_q) &&
		(bg_token_tile_row_source_y_i == row_source_y_q[16:0]) &&
		(bg_token_overplane_selected_i == raw_overplane_selected_q) &&
		(bg_token_strict_overplane_i == raw_strict_overplane_q);

	wire empty_prime_w = state_q == STATE_EMPTY_PRIME;
	wire prime_from_fetch_w = (state_q == STATE_FETCH_ROW) &&
		(work_tile_ordinal_q == 16'd0) &&
		bg_raw_result_accept_i && raw_result_tag_matches_w;
	wire prime_fire_w = ce_i && scheduler_row_prime_valid_o &&
		scheduler_row_prime_ready_i;

	wire blend_tag_matches_scheduler_w = token_tag_matches_work_w &&
		({3'd0, bg_token_tile_ordinal_i} ==
		 scheduler_tile_ordinal_i) &&
		({{2{bg_token_tile_x_i[15]}}, bg_token_tile_x_i} ==
		 scheduler_tile_source_x_i);
	wire scheduler_context_matches_w =
		(scheduler_tile_world_i == row_world_q) &&
		(scheduler_tile_strip_i == row_strip_q) &&
		(scheduler_tile_screen_y_i == row_screen_y_q) &&
		(scheduler_tile_local_y_i == row_local_y_q) &&
		(scheduler_tile_source_y_i == row_source_y_q) &&
		(scheduler_tile_count_i == geometry_tile_count_q) &&
		(scheduler_tile_index_i == scheduler_tile_source_x_i[17:3]) &&
		(scheduler_tile_uses_prime_i ==
		 (scheduler_tile_ordinal_i == 16'd0));
	wire producer_offer_w = bg_token_valid_i &&
		blend_tag_matches_scheduler_w && scheduler_context_matches_w &&
		scheduler_tile_valid_i && !reset_i && !abort_i;
	wire producer_accept_w = ce_i && producer_offer_w &&
		row_producer_ready_i;
	wire producer_done_w = ce_i && row_producer_done_i &&
		!reset_i && !abort_i;

	wire [16:0] next_tile_ordinal_w =
		{1'b0, scheduler_tile_ordinal_i} + 17'd1;
	wire signed [18:0] next_tile_source_x_w =
		{{1{scheduler_tile_source_x_i[17]}},
		 scheduler_tile_source_x_i} + 19'sd8;
	wire launch_next_tile_w = producer_accept_w &&
		!scheduler_tile_last_in_row_i;
	wire fetch_tile_valid_w = (state_q == STATE_FETCH_TILE) ||
		launch_next_tile_w;
	wire [12:0] fetch_tile_ordinal_w = launch_next_tile_w ?
		next_tile_ordinal_w[12:0] : work_tile_ordinal_q[12:0];
	wire signed [15:0] fetch_tile_source_x_w = launch_next_tile_w ?
		next_tile_source_x_w[15:0] : work_tile_source_x_q[15:0];

	wire fetch_result_accept_w = bg_raw_result_accept_i &&
		raw_result_tag_matches_w;
	wire blend_input_fire_w = fetch_result_accept_w;
	wire expected_context_accept_w = ce_i && bg_tile_row_valid_o &&
		bg_tile_row_ready_i;

	// Idle only when token ownership reaches zero without replacement.
	wire producer_count_zero_after_w =
		(!producer_accept_w && !producer_done_w &&
		 (producer_outstanding_q == 2'd0)) ||
		(!producer_accept_w && producer_done_w &&
		 (producer_outstanding_q == 2'd1));
	wire final_token_seen_after_w = final_token_accepted_q ||
		(producer_accept_w && scheduler_tile_last_in_row_i);
	wire blend_empty_after_w = !bg_token_valid_i ||
		producer_accept_w;
	wire row_retire_w = ce_i && row_context_valid_q &&
		final_token_seen_after_w && producer_count_zero_after_w &&
		blend_empty_after_w && !fetch_busy_o &&
		!fetch_cleanup_busy_o && !param_busy_o &&
		!geometry_busy_o;

	assign scheduler_row_start_ready_o = param_row_ready_w &&
		(state_q == STATE_IDLE) && !row_context_valid_q &&
		!cleanup_busy_o && (producer_outstanding_q == 2'd0) &&
		!bg_token_valid_i;

	assign scheduler_row_geometry_valid_o = geometry_output_valid_w &&
		(state_q == STATE_GEOMETRY) && row_context_valid_q;
	assign scheduler_row_geometry_tile_start_o = geometry_tile_floor_w;
	assign scheduler_row_geometry_tile_count_o = geometry_usable_w ?
		geometry_tile_count_w : 16'sd0;
	assign geometry_output_ready_w = scheduler_row_geometry_ready_i &&
		(state_q == STATE_GEOMETRY) && row_context_valid_q;

	assign scheduler_row_prime_valid_o = !reset_i && !abort_i &&
		(empty_prime_w || prime_pending_q || prime_from_fetch_w);

	assign row_producer_valid_o = producer_offer_w;
	assign scheduler_tile_ready_o = producer_offer_w &&
		row_producer_ready_i;
	assign blend_output_ready_w = scheduler_tile_valid_i &&
		blend_tag_matches_scheduler_w && scheduler_context_matches_w &&
		row_producer_ready_i;
	assign bg_token_ready_o = blend_output_ready_w;
	assign row_producer_tile_ordinal_o =
		{3'd0, bg_token_tile_ordinal_i};
	assign row_producer_row_o = bg_token_row_i;
	assign row_producer_left_base_x_o = bg_token_left_base_x_i;
	assign row_producer_left_enable_o = bg_token_left_enable_i;
	assign row_producer_left_active_o = bg_token_left_active_i;
	assign row_producer_left_opaque_o = bg_token_left_opaque_i;
	assign row_producer_left_values_o = bg_token_left_values_i;
	assign row_producer_right_base_x_o = bg_token_right_base_x_i;
	assign row_producer_right_enable_o = bg_token_right_enable_i;
	assign row_producer_right_active_o = bg_token_right_active_i;
	assign row_producer_right_opaque_o = bg_token_right_opaque_i;
	assign row_producer_right_values_o = bg_token_right_values_i;

	assign bg_maps_wide_o = maps_wide_q;
	assign bg_maps_high_o = maps_high_q;
	assign bg_effective_map_columns_o = effective_map_columns_q;
	assign bg_bgmap_base_rounded_o = bgmap_base_rounded_q;
	assign bg_over_o = over_q;
	assign bg_overplane_o = overplane_q;
	assign bg_left_on_o = left_on_q;
	assign bg_right_on_o = right_on_q;
	assign bg_left_source_start_o = left_source_start_q;
	assign bg_right_source_start_o = right_source_start_q;
	assign bg_left_destination_start_o = left_destination_start_q;
	assign bg_right_destination_start_o = right_destination_start_q;
	assign bg_semantic_width_o = semantic_width_q;
	assign bg_gplt_active_o = gplt_active_q;
	assign bg_tile_row_valid_o = state_q == STATE_FETCH_CONTEXT;
	assign bg_tile_row_load_o = row_load_q;
	assign bg_tile_row_screen_y_o = row_screen_y_q;
	assign bg_tile_row_source_y_o = row_source_y_q[16:0];
	assign bg_tile_valid_o = fetch_tile_valid_w;
	assign bg_tile_load_o = row_load_q;
	assign bg_tile_ordinal_o = fetch_tile_ordinal_w;
	assign bg_tile_x_o = fetch_tile_source_x_w;
	assign bg_row_valid_o = state_q == STATE_FETCH_ROW;
	assign bg_row_load_o = row_load_q;
	assign bg_row_tile_ordinal_o = work_tile_ordinal_q[12:0];
	assign bg_row_ordinal_o = 3'd0;
	assign bg_row_source_index_o = row_source_y_q[2:0];
	assign bg_row_screen_y_o = row_screen_y_q;
	assign bg_row_source_y_o = row_source_y_q[16:0];
	assign bg_result_permit_o = (state_q == STATE_FETCH_ROW) &&
		bg_raw_result_valid_i && raw_result_tag_matches_w;

	assign row_context_valid_o = row_context_valid_q;
	assign geometry_context_valid_o = geometry_context_valid_q;
	assign active_tile_ordinal_o = work_tile_ordinal_q;
	assign active_tile_source_x_o = work_tile_source_x_q;
	assign producer_outstanding_o = producer_outstanding_q;
	assign blend_pending_o = bg_token_relevant_w;
	assign source_conflict_o = param_result_source_conflict_w ||
		param_source_conflict_seen_w;
	assign fetch_busy_o = bg_fetch_busy_relevant_w;
	assign fetch_cleanup_busy_o = bg_cleanup_relevant_w;
	assign cell_dram_read_pending_o = bg_context_hbias_w &&
		bg_dram_read_pending_i;
	assign cell_vrm_read_pending_o = bg_context_hbias_w &&
		bg_vrm_read_pending_i;
	assign busy_o = row_context_valid_q || param_busy_o ||
		geometry_busy_o || bg_busy_relevant_w || bg_token_relevant_w ||
		(producer_outstanding_q != 2'd0);
	assign cleanup_busy_o = param_cleanup_busy_w ||
		fetch_cleanup_busy_o || param_dram_cleanup_busy_i;
	assign downstream_idle_o = !reset_i && !abort_i &&
		(!row_context_valid_q || row_retire_w) &&
		!param_busy_o && !geometry_busy_o && !fetch_busy_o &&
		!fetch_cleanup_busy_o && blend_empty_after_w &&
		producer_count_zero_after_w && !cleanup_busy_o;
	assign component_error_o = param_unexpected_response_w ||
		param_capture_overflow_w || param_owner_mismatch_w ||
		(bg_relevant_w && (bg_unexpected_dram_response_i ||
		 bg_unexpected_vrm_response_i ||
		 bg_response_capture_overflow_i ||
		 bg_scheduler_tag_mismatch_i ||
		 bg_concurrent_work_error_i ||
		 bg_strict_overplane_seen_i ||
		 bg_map_index_overflow_seen_i));

	assign param_result_ready_w = (state_q == STATE_PARAMETER) &&
		row_context_valid_q && geometry_input_ready_w;

`ifdef SYNTHESIS
	assign diag_row_start_accept_count_o = 32'd0;
	assign diag_parameter_accept_count_o = 32'd0;
	assign diag_geometry_accept_count_o = 32'd0;
	assign diag_prime_accept_count_o = 32'd0;
	assign diag_cell_accept_count_o = 32'd0;
	assign diag_vrm_accept_count_o = 32'd0;
	assign diag_fetch_result_accept_count_o = 32'd0;
	assign diag_producer_accept_count_o = 32'd0;
	assign diag_producer_done_count_o = 32'd0;
`endif

	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_hbias_param_streamer u_param_streamer
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.row_valid_i(scheduler_row_start_valid_i &&
			scheduler_row_start_ready_o),
		.row_ready_o(param_row_ready_w),
		.row_world_i(scheduler_row_start_world_i),
		.row_strip_i(scheduler_row_start_strip_i),
		.row_first_in_strip_i(
			scheduler_row_start_first_in_strip_i),
		.row_screen_y_i(scheduler_row_start_screen_y_i),
		.gy_i(gy_i),
		.param_base_i(param_base_i),
		.dram_req_o(param_dram_req_o),
		.dram_addr_o(param_dram_addr_o),
		.dram_accept_i(param_dram_accept_i),
		.dram_resp_valid_i(param_dram_resp_valid_i),
		.dram_resp_data_i(param_dram_resp_data_i),
		.dram_router_cleanup_busy_i(param_dram_cleanup_busy_i),
		.dram_router_stale_discard_i(param_dram_stale_discard_i),
		.row_result_valid_o(param_result_valid_w),
		.row_result_ready_i(param_result_ready_w),
		.row_result_world_o(param_result_world_w),
		.row_result_strip_o(param_result_strip_w),
		.row_result_screen_y_o(param_result_screen_y_w),
		.row_result_local_row_o(param_result_local_row_w),
		.row_result_hofst_left_o(param_result_hofst_left_w),
		.row_result_hofst_right_o(param_result_hofst_right_w),
		.row_result_raw_left_o(),
		.row_result_raw_right_o(),
		.row_result_odd_alias_o(),
		.row_result_source_conflict_o(
			param_result_source_conflict_w),
		.busy_o(param_busy_o),
		.cleanup_busy_o(param_cleanup_busy_w),
		.read_pending_o(param_read_pending_o),
		.response_capture_valid_o(),
		.dram_request_owner_o(),
		.dram_pending_owner_o(),
		.active_local_row_o(),
		.active_left_index_o(),
		.active_right_index_o(),
		.active_odd_alias_o(),
		.active_address_wrapped_o(),
		.request_accepted_o(),
		.response_retired_o(),
		.stale_response_discarded_o(),
		.source_conflict_seen_o(param_source_conflict_seen_w),
		.invalid_local_row_seen_o(),
		.h00_reference_protocol_error_o(),
		.accept_without_request_o(),
		.unexpected_response_o(param_unexpected_response_w),
		.response_capture_overflow_o(param_capture_overflow_w),
		.pending_owner_mismatch_o(param_owner_mismatch_w)
	);

	vip_xp_hbias_row_geometry u_row_geometry
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.input_valid_i(param_result_valid_w &&
			(state_q == STATE_PARAMETER)),
		.input_ready_o(geometry_input_ready_w),
		.mx_i(mx_q),
		.mp_i(mp_q),
		.hofst_left_i(param_result_hofst_left_scaled_w[12:0]),
		.hofst_right_i(param_result_hofst_right_scaled_w[12:0]),
		.semantic_width_i(semantic_width_q),
		.gx_i(gx_q),
		.gp_i(gp_q),
		.output_valid_o(geometry_output_valid_w),
		.output_ready_i(geometry_output_ready_w),
		.left_source_start_o(geometry_left_source_start_w),
		.right_source_start_o(geometry_right_source_start_w),
		.left_destination_start_o(
			geometry_left_destination_start_w),
		.right_destination_start_o(
			geometry_right_destination_start_w),
		.union_low_o(),
		.union_high_exclusive_o(),
		.union_tile_floor_o(geometry_tile_floor_w),
		.union_tile_ceil_exclusive_o(),
		.union_tile_count_o(geometry_tile_count_w),
		.left_tile_mapping_bias_o(),
		.right_tile_mapping_bias_o(),
		.first_tile_source_x_o(geometry_first_tile_source_x_w),
		.first_tile_left_destination_base_o(),
		.first_tile_right_destination_base_o(),
		.malformed_o(geometry_malformed_w),
		.busy_o(geometry_busy_o)
	);

	/* verilator lint_on PINCONNECTEMPTY */

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			row_context_valid_q <= 1'b0;
			geometry_context_valid_q <= 1'b0;
			row_load_q <= 1'b0;
			row_world_q <= 5'd0;
			row_strip_q <= 5'd0;
			row_screen_y_q <= 9'd0;
			row_local_y_q <= 16'd0;
			row_source_y_q <= 18'sd0;
			mx_q <= 13'sd0;
			mp_q <= 15'sd0;
			semantic_width_q <= 13'd0;
			gx_q <= 10'sd0;
			gp_q <= 10'sd0;
			left_on_q <= 1'b0;
			right_on_q <= 1'b0;
			maps_wide_q <= 4'd1;
			maps_high_q <= 4'd1;
			effective_map_columns_q <= 4'd1;
			bgmap_base_rounded_q <= 4'd0;
			over_q <= 1'b0;
			overplane_q <= 16'd0;
			gplt_active_q <= 32'd0;
			left_source_start_q <= 18'sd0;
			right_source_start_q <= 18'sd0;
			left_destination_start_q <= 18'sd0;
			right_destination_start_q <= 18'sd0;
			geometry_tile_count_q <= 16'd0;
			work_tile_ordinal_q <= 16'd0;
			work_tile_source_x_q <= 18'sd0;
			raw_metadata_valid_q <= 1'b0;
			raw_overplane_selected_q <= 1'b0;
			raw_strict_overplane_q <= 1'b0;
			prime_pending_q <= 1'b0;
			final_token_accepted_q <= 1'b0;
			producer_outstanding_q <= 2'd0;
			row_context_mismatch_o <= 1'b0;
			geometry_unsupported_o <= 1'b0;
			scheduler_tile_tag_mismatch_o <= 1'b0;
			ordinal_overflow_o <= 1'b0;
			coordinate_overflow_o <= 1'b0;
			producer_overflow_o <= 1'b0;
			producer_underflow_o <= 1'b0;
`ifndef SYNTHESIS
			diag_row_start_accept_count_o <= 32'd0;
			diag_parameter_accept_count_o <= 32'd0;
			diag_geometry_accept_count_o <= 32'd0;
			diag_prime_accept_count_o <= 32'd0;
			diag_cell_accept_count_o <= 32'd0;
			diag_vrm_accept_count_o <= 32'd0;
			diag_fetch_result_accept_count_o <= 32'd0;
			diag_producer_accept_count_o <= 32'd0;
			diag_producer_done_count_o <= 32'd0;
`endif
		end else if (abort_i) begin
			state_q <= STATE_IDLE;
			row_context_valid_q <= 1'b0;
			geometry_context_valid_q <= 1'b0;
			raw_metadata_valid_q <= 1'b0;
			prime_pending_q <= 1'b0;
			final_token_accepted_q <= 1'b0;
			producer_outstanding_q <= 2'd0;
		end else if (ce_i) begin
			if (row_start_fire_w) begin
				state_q <= STATE_PARAMETER;
				row_context_valid_q <= 1'b1;
				geometry_context_valid_q <= 1'b0;
				row_load_q <= ~row_load_q;
				row_world_q <= scheduler_row_start_world_i;
				row_strip_q <= scheduler_row_start_strip_i;
				row_screen_y_q <= scheduler_row_start_screen_y_i;
				row_local_y_q <= scheduler_row_start_local_y_i;
				row_source_y_q <= scheduler_row_start_source_y_i;
				mx_q <= mx_i;
				mp_q <= mp_i;
				semantic_width_q <= semantic_width_i;
				gx_q <= gx_i;
				gp_q <= gp_i;
				left_on_q <= left_on_i;
				right_on_q <= right_on_i;
				maps_wide_q <= maps_wide_i;
				maps_high_q <= maps_high_i;
				effective_map_columns_q <=
					effective_map_columns_i;
				bgmap_base_rounded_q <= bgmap_base_rounded_i;
				over_q <= over_i;
				overplane_q <= overplane_i;
				gplt_active_q <= gplt_active_i;
				prime_pending_q <= 1'b0;
				final_token_accepted_q <= 1'b0;
				raw_metadata_valid_q <= 1'b0;
				if (scheduler_row_start_source_y_i[17:16] !=
					{2{scheduler_row_start_source_y_i[15]}}) begin
					coordinate_overflow_o <= 1'b1;
				end
`ifndef SYNTHESIS
				diag_row_start_accept_count_o <=
					diag_row_start_accept_count_o + 32'd1;
`endif
			end

			if (parameter_fire_w) begin
				state_q <= STATE_GEOMETRY;
				if (
`ifndef SYNTHESIS
					(param_result_world_w != row_world_q) ||
					(param_result_strip_w != row_strip_q) ||
`endif
					(param_result_screen_y_w != row_screen_y_q) ||
					(param_result_local_row_w != row_local_y_q)) begin
					row_context_mismatch_o <= 1'b1;
				end
`ifndef SYNTHESIS
				diag_parameter_accept_count_o <=
					diag_parameter_accept_count_o + 32'd1;
`endif
			end

			if (geometry_fire_w) begin
				geometry_context_valid_q <= geometry_usable_w;
				left_source_start_q <= geometry_left_source_start_w;
				right_source_start_q <= geometry_right_source_start_w;
				left_destination_start_q <=
					geometry_left_destination_start_w;
				right_destination_start_q <=
					geometry_right_destination_start_w;
				geometry_tile_count_q <= geometry_usable_w ?
					geometry_tile_count_w[15:0] : 16'd0;
				work_tile_ordinal_q <= 16'd0;
				work_tile_source_x_q <=
					geometry_first_tile_source_x_w;
				if (geometry_usable_w) begin
					state_q <= STATE_FETCH_CONTEXT;
				end else begin
					state_q <= STATE_EMPTY_PRIME;
					geometry_unsupported_o <= 1'b1;
				end
				if (!geometry_first_x_fits_w) begin
					coordinate_overflow_o <= 1'b1;
				end
`ifndef SYNTHESIS
				diag_geometry_accept_count_o <=
					diag_geometry_accept_count_o + 32'd1;
`endif
			end

			if ((state_q == STATE_FETCH_CONTEXT) &&
				bg_tile_row_ready_i) begin
				state_q <= STATE_FETCH_TILE;
			end

			if ((state_q == STATE_FETCH_TILE) && bg_tile_ready_i) begin
				state_q <= STATE_FETCH_ROW;
			end

			if ((state_q == STATE_FETCH_ROW) && bg_row_ready_i) begin
				state_q <= STATE_WAIT_TOKEN;
			end

			if (prime_fire_w) begin
				prime_pending_q <= 1'b0;
`ifndef SYNTHESIS
				diag_prime_accept_count_o <=
					diag_prime_accept_count_o + 32'd1;
`endif
				if (empty_prime_w) begin
					state_q <= STATE_IDLE;
					row_context_valid_q <= 1'b0;
					geometry_context_valid_q <= 1'b0;
				end
			end
			if (blend_input_fire_w &&
				(work_tile_ordinal_q == 16'd0) && !prime_fire_w) begin
				prime_pending_q <= 1'b1;
			end

			if (blend_input_fire_w) begin
				raw_metadata_valid_q <= 1'b1;
				raw_overplane_selected_q <=
					bg_raw_result_overplane_selected_i;
				raw_strict_overplane_q <=
					bg_raw_result_strict_overplane_i;
			end else if (producer_accept_w) begin
				raw_metadata_valid_q <= 1'b0;
			end

			if (producer_accept_w) begin
				if (scheduler_tile_last_in_row_i) begin
					state_q <= STATE_WAIT_DONE;
					final_token_accepted_q <= 1'b1;
				end else begin
					state_q <= STATE_FETCH_TILE;
					work_tile_ordinal_q <=
						next_tile_ordinal_w[15:0];
					work_tile_source_x_q <=
						next_tile_source_x_w[17:0];
					if (|next_tile_ordinal_w[16:13]) begin
						ordinal_overflow_o <= 1'b1;
					end
					if (next_tile_source_x_w[18:15] !=
						{4{next_tile_source_x_w[15]}}) begin
						coordinate_overflow_o <= 1'b1;
					end
				end
`ifndef SYNTHESIS
				diag_producer_accept_count_o <=
					diag_producer_accept_count_o + 32'd1;
`endif
			end

			if (scheduler_tile_valid_i && bg_token_valid_i &&
				(!blend_tag_matches_scheduler_w ||
				 !scheduler_context_matches_w)) begin
				scheduler_tile_tag_mismatch_o <= 1'b1;
			end

			if (bg_relevant_w && bg_raw_result_valid_i &&
				!raw_result_tag_matches_w) begin
				scheduler_tile_tag_mismatch_o <= 1'b1;
			end
			if (row_context_valid_q &&
				(expected_context_accept_w != bg_context_accept_i)) begin
				scheduler_tile_tag_mismatch_o <= 1'b1;
			end
			// The backend's token accept must mirror our own accept.
			if ((row_context_valid_q ||
				 (bg_token_owner_i == OWNER_HBIAS)) &&
				(producer_accept_w != bg_token_accept_i)) begin
				scheduler_tile_tag_mismatch_o <= 1'b1;
			end
			if (row_context_valid_q && bg_context_owner_valid_i &&
				(bg_active_context_owner_i != OWNER_HBIAS)) begin
				scheduler_tile_tag_mismatch_o <= 1'b1;
			end

			if (bg_cell_accept_i && bg_relevant_w) begin
`ifndef SYNTHESIS
				diag_cell_accept_count_o <=
					diag_cell_accept_count_o + 32'd1;
`endif
			end
			if (bg_vrm_accept_i && bg_relevant_w) begin
`ifndef SYNTHESIS
				diag_vrm_accept_count_o <=
					diag_vrm_accept_count_o + 32'd1;
`endif
			end
			if (fetch_result_accept_w) begin
`ifndef SYNTHESIS
				diag_fetch_result_accept_count_o <=
					diag_fetch_result_accept_count_o + 32'd1;
`endif
			end

			case ({producer_accept_w, producer_done_w})
				2'b10: begin
					if (producer_outstanding_q == 2'd3) begin
						producer_overflow_o <= 1'b1;
					end else begin
						producer_outstanding_q <=
							producer_outstanding_q + 2'd1;
					end
				end
				2'b01: begin
					if (producer_outstanding_q == 2'd0) begin
						producer_underflow_o <= 1'b1;
					end else begin
						producer_outstanding_q <=
							producer_outstanding_q - 2'd1;
					end
				end
				2'b11: begin
					if (producer_outstanding_q == 2'd0) begin
						// Keep a new token when done has no older owner.
						producer_underflow_o <= 1'b1;
						producer_outstanding_q <= 2'd1;
					end
				end
				default: begin
				end
			endcase

			if (producer_done_w) begin
`ifndef SYNTHESIS
				diag_producer_done_count_o <=
					diag_producer_done_count_o + 32'd1;
`endif
			end

			if (row_retire_w) begin
				state_q <= STATE_IDLE;
				row_context_valid_q <= 1'b0;
				geometry_context_valid_q <= 1'b0;
				prime_pending_q <= 1'b0;
				final_token_accepted_q <= 1'b0;
				raw_metadata_valid_q <= 1'b0;
			end
		end
	end

endmodule

`timescale 1ns/1ps

// H-bias row-parameter streamer.
//
// local_row is screen_y-GY. Param Base is a DRAM halfword index, with two words
// per row and 16-bit wrap. Silicon unknown: use STS's provisional OR-one rule
// for the right word; an odd left index therefore supplies both eyes.
//
// Hold DRAM requests and result tags until accepted. Capture raw responses
// during CE pauses. Abort drops offers and drains accepted reads.

module vip_xp_hbias_param_streamer
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	// Held row command. World and strip are trace tags only.
	input  wire                 row_valid_i,
	output wire                 row_ready_o,
`ifdef SYNTHESIS
	/* verilator lint_off UNUSEDSIGNAL */
`endif
	input  wire [4:0]           row_world_i,
	input  wire [4:0]           row_strip_i,
`ifdef SYNTHESIS
	/* verilator lint_on UNUSEDSIGNAL */
`endif
	input  wire                 row_first_in_strip_i,
	input  wire [8:0]           row_screen_y_i,
	input  wire signed [15:0]   gy_i,
	input  wire [15:0]          param_base_i,

	// PARAM client of the shared DRAM mux.
	output wire                 dram_req_o,
	output wire [15:0]          dram_addr_o,
	input  wire                 dram_accept_i,
	input  wire                 dram_resp_valid_i,
`ifdef SYNTHESIS
	/* verilator lint_off UNUSEDSIGNAL */
`endif
	input  wire [15:0]          dram_resp_data_i,
`ifdef SYNTHESIS
	/* verilator lint_on UNUSEDSIGNAL */
`endif
	input  wire                 dram_router_cleanup_busy_i,
	input  wire                 dram_router_stale_discard_i,

	// Held stereo row parameters.
	output wire                 row_result_valid_o,
	input  wire                 row_result_ready_i,
	output wire [4:0]           row_result_world_o,
	output wire [4:0]           row_result_strip_o,
	output wire [8:0]           row_result_screen_y_o,
	output wire [15:0]          row_result_local_row_o,
	output wire signed [17:0]   row_result_hofst_left_o,
	output wire signed [17:0]   row_result_hofst_right_o,
	output wire [15:0]          row_result_raw_left_o,
	output wire [15:0]          row_result_raw_right_o,
	output wire                 row_result_odd_alias_o,
	output wire                 row_result_source_conflict_o,

	// Request, ownership, address, cleanup, and source diagnostics.
	output wire                 busy_o,
	output wire                 cleanup_busy_o,
	output wire                 read_pending_o,
	output wire                 response_capture_valid_o,
	output wire [1:0]           dram_request_owner_o,
	output wire [1:0]           dram_pending_owner_o,
	output wire [15:0]          active_local_row_o,
	output wire [15:0]          active_left_index_o,
	output wire [15:0]          active_right_index_o,
	output wire                 active_odd_alias_o,
	output wire                 active_address_wrapped_o,
	output wire                 request_accepted_o,
	output wire                 response_retired_o,
	output wire                 stale_response_discarded_o,
	output wire                 source_conflict_seen_o,
	output wire                 invalid_local_row_seen_o,
	output wire                 h00_reference_protocol_error_o,
	output wire                 accept_without_request_o,
	output wire                 unexpected_response_o,
	output wire                 response_capture_overflow_o,
	output wire                 pending_owner_mismatch_o
);

	localparam [2:0]
		STATE_IDLE       = 3'd0,
		STATE_READ_LEFT  = 3'd1,
		STATE_READ_RIGHT = 3'd2,
		STATE_RESULT     = 3'd3,
		STATE_DRAIN      = 3'd4;

	localparam [1:0]
		OWNER_NONE        = 2'd0,
		OWNER_PARAM_LEFT  = 2'd1,
		OWNER_PARAM_RIGHT = 2'd2;

	reg [2:0] state_q;

`ifndef SYNTHESIS
	reg [4:0] row_world_q;
	reg [4:0] row_strip_q;
`endif
	reg       row_first_in_strip_q;
	reg [8:0] row_screen_y_q;
	reg [15:0] row_local_row_q;
	reg [15:0] left_index_q;
	reg [15:0] right_index_q;
	reg        odd_alias_q;
`ifndef SYNTHESIS
	reg        address_wrapped_q;
`endif

	reg                 pending_q;
	reg                 pending_stale_q;
	reg [1:0]           pending_owner_q;
	reg                 response_capture_valid_q;
`ifndef SYNTHESIS
	reg [15:0]          response_capture_data_q;
`else
	reg [12:0]          response_capture_data_q;
`endif

	reg signed [17:0]   left_offset_q;
	reg signed [17:0]   right_offset_q;
`ifndef SYNTHESIS
	reg [15:0]          raw_left_q;
	reg [15:0]          raw_right_q;
`endif
	reg                  result_source_conflict_q;

	// Keep the H00 timing comparison visible without affecting pixels.
	reg                  h00_reference_valid_q;
	reg signed [17:0]    h00_reference_left_q;
	reg signed [17:0]    h00_reference_right_q;
	reg                  source_conflict_seen_q;

`ifndef SYNTHESIS
	reg request_accepted_q;
	reg response_retired_q;
	reg stale_response_discarded_q;
	reg invalid_local_row_seen_q;
	reg h00_reference_protocol_error_q;
	reg accept_without_request_q;
	reg unexpected_response_q;
	reg response_capture_overflow_q;
	reg pending_owner_mismatch_q;
`endif

	wire [15:0] local_row_wrapped_w =
		{7'd0, row_screen_y_i} - gy_i;
`ifndef SYNTHESIS
	wire signed [16:0] local_row_signed_w =
		$signed({8'd0, row_screen_y_i}) -
		$signed({gy_i[15], gy_i});
`endif
	// Select bits 14:0 before shifting to make the 16-bit wrap explicit.
	wire [15:0] local_row_twice_wrapped_w =
		{local_row_wrapped_w[14:0], 1'b0};
	wire [15:0] calculated_left_index_w =
		param_base_i + local_row_twice_wrapped_w;
`ifndef SYNTHESIS
	wire [17:0] left_index_full_sum_w =
		{2'b00, param_base_i} +
		{1'b0, local_row_wrapped_w, 1'b0};
	wire calculated_address_wrapped_w =
		(local_row_signed_w[15:0] == local_row_wrapped_w) &&
		(left_index_full_sum_w[15:0] == calculated_left_index_w) &&
		|left_index_full_sum_w[17:16];
`endif
	wire [15:0] calculated_right_index_w =
		calculated_left_index_w | 16'h0001;
`ifndef SYNTHESIS
	wire invalid_local_row_w = local_row_signed_w[16];
`endif

	wire request_left_w = state_q == STATE_READ_LEFT;
	wire request_right_w = state_q == STATE_READ_RIGHT;
	wire request_active_w = request_left_w || request_right_w;
	wire [1:0] request_owner_w = request_right_w ?
		OWNER_PARAM_RIGHT : OWNER_PARAM_LEFT;

	wire response_available_w = response_capture_valid_q ||
		dram_resp_valid_i;
	wire [12:0] response_low_w = response_capture_valid_q ?
		response_capture_data_q[12:0] : dram_resp_data_i[12:0];
	wire signed [17:0] response_offset_w =
		{{5{response_low_w[12]}}, response_low_w};
`ifndef SYNTHESIS
	wire [15:0] response_raw_w = response_capture_valid_q ?
		response_capture_data_q : dram_resp_data_i;
`endif
	wire stale_active_w = pending_q &&
		(pending_stale_q || abort_i);
	wire live_response_fire_w = ce_i && pending_q &&
		!pending_stale_q && !abort_i && response_available_w;
	wire stale_response_fire_w = ce_i && stale_active_w &&
		response_available_w;
	wire request_accept_fire_w = ce_i && dram_req_o &&
		dram_accept_i;
	wire result_fire_w = ce_i && row_result_valid_o &&
		row_result_ready_i;

	wire pair_complete_w = live_response_fire_w &&
		((pending_owner_q == OWNER_PARAM_RIGHT) || odd_alias_q);
	wire signed [17:0] completed_left_offset_w =
		(pending_owner_q == OWNER_PARAM_RIGHT) ?
		left_offset_q : response_offset_w;
	wire signed [17:0] completed_right_offset_w =
		response_offset_w;
	wire h00_compare_w = pair_complete_w &&
		!row_first_in_strip_q && h00_reference_valid_q;
	wire h00_conflict_w = h00_compare_w &&
		((completed_left_offset_w != h00_reference_left_q) ||
		 (completed_right_offset_w != h00_reference_right_q));

	assign row_ready_o = ce_i && !reset_i && !abort_i &&
		(state_q == STATE_IDLE) && !pending_q &&
		!response_capture_valid_q && !dram_router_cleanup_busy_i;

	assign dram_req_o = !reset_i && !abort_i && request_active_w &&
		!pending_q && !dram_router_cleanup_busy_i;
	assign dram_addr_o = request_right_w ? right_index_q : left_index_q;

	assign row_result_valid_o = !reset_i && !abort_i &&
		(state_q == STATE_RESULT);
`ifndef SYNTHESIS
	assign row_result_world_o = row_world_q;
	assign row_result_strip_o = row_strip_q;
`else
	assign row_result_world_o = 5'd0;
	assign row_result_strip_o = 5'd0;
`endif
	assign row_result_screen_y_o = row_screen_y_q;
	assign row_result_local_row_o = row_local_row_q;
	assign row_result_hofst_left_o = left_offset_q;
	assign row_result_hofst_right_o = right_offset_q;
`ifndef SYNTHESIS
	assign row_result_raw_left_o = raw_left_q;
	assign row_result_raw_right_o = raw_right_q;
`else
	assign row_result_raw_left_o = 16'd0;
	assign row_result_raw_right_o = 16'd0;
`endif
	assign row_result_odd_alias_o = odd_alias_q;
	assign row_result_source_conflict_o = result_source_conflict_q;

	assign busy_o = (state_q != STATE_IDLE) || pending_q ||
		response_capture_valid_q || dram_router_cleanup_busy_i;
	assign cleanup_busy_o = dram_router_cleanup_busy_i ||
		(state_q == STATE_DRAIN) || stale_active_w;
	assign read_pending_o = pending_q;
	assign response_capture_valid_o = response_capture_valid_q;
	assign dram_request_owner_o = dram_req_o ?
		request_owner_w : OWNER_NONE;
	assign dram_pending_owner_o = pending_q ?
		pending_owner_q : OWNER_NONE;
	assign active_local_row_o = row_local_row_q;
	assign active_left_index_o = left_index_q;
	assign active_right_index_o = right_index_q;
	assign active_odd_alias_o = odd_alias_q;
`ifndef SYNTHESIS
	assign active_address_wrapped_o = address_wrapped_q;
	assign request_accepted_o = request_accepted_q;
	assign response_retired_o = response_retired_q;
	assign stale_response_discarded_o = stale_response_discarded_q;
	assign invalid_local_row_seen_o = invalid_local_row_seen_q;
	assign h00_reference_protocol_error_o =
		h00_reference_protocol_error_q;
	assign accept_without_request_o = accept_without_request_q;
	assign unexpected_response_o = unexpected_response_q;
	assign response_capture_overflow_o = response_capture_overflow_q;
	assign pending_owner_mismatch_o = pending_owner_mismatch_q;
`else
	assign active_address_wrapped_o = 1'b0;
	assign request_accepted_o = 1'b0;
	assign response_retired_o = 1'b0;
	assign stale_response_discarded_o = 1'b0;
	assign invalid_local_row_seen_o = 1'b0;
	assign h00_reference_protocol_error_o = 1'b0;
	assign accept_without_request_o = 1'b0;
	assign unexpected_response_o = 1'b0;
	assign response_capture_overflow_o = 1'b0;
	assign pending_owner_mismatch_o = 1'b0;
`endif
	assign source_conflict_seen_o = source_conflict_seen_q;

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
`ifndef SYNTHESIS
			row_world_q <= 5'd0;
			row_strip_q <= 5'd0;
`endif
			row_first_in_strip_q <= 1'b0;
			row_screen_y_q <= 9'd0;
			row_local_row_q <= 16'd0;
			left_index_q <= 16'd0;
			right_index_q <= 16'd0;
			odd_alias_q <= 1'b0;
`ifndef SYNTHESIS
			address_wrapped_q <= 1'b0;
`endif
			pending_q <= 1'b0;
			pending_stale_q <= 1'b0;
			pending_owner_q <= OWNER_NONE;
			response_capture_valid_q <= 1'b0;
`ifndef SYNTHESIS
			response_capture_data_q <= 16'd0;
`else
			response_capture_data_q <= 13'd0;
`endif
			left_offset_q <= 18'sd0;
			right_offset_q <= 18'sd0;
`ifndef SYNTHESIS
			raw_left_q <= 16'd0;
			raw_right_q <= 16'd0;
`endif
			result_source_conflict_q <= 1'b0;
			h00_reference_valid_q <= 1'b0;
			h00_reference_left_q <= 18'sd0;
			h00_reference_right_q <= 18'sd0;
			source_conflict_seen_q <= 1'b0;
`ifndef SYNTHESIS
			request_accepted_q <= 1'b0;
			response_retired_q <= 1'b0;
			stale_response_discarded_q <= 1'b0;
			invalid_local_row_seen_q <= 1'b0;
			h00_reference_protocol_error_q <= 1'b0;
			accept_without_request_q <= 1'b0;
			unexpected_response_q <= 1'b0;
			response_capture_overflow_q <= 1'b0;
			pending_owner_mismatch_q <= 1'b0;
`endif
		end else begin
`ifndef SYNTHESIS
			request_accepted_q <= 1'b0;
			response_retired_q <= 1'b0;
			stale_response_discarded_q <= 1'b0;
`endif

			// Retire local PARAM ownership on the raw stale-discard pulse.
			if (dram_router_stale_discard_i) begin
`ifndef SYNTHESIS
				if (!pending_q) begin
					unexpected_response_q <= 1'b1;
				end
`endif
				pending_q <= 1'b0;
				pending_stale_q <= 1'b0;
				pending_owner_q <= OWNER_NONE;
				response_capture_valid_q <= 1'b0;
				state_q <= STATE_IDLE;
`ifndef SYNTHESIS
				stale_response_discarded_q <= 1'b1;
`endif
			end

			// Save raw responses that CE cannot consume immediately.
			if (dram_resp_valid_i && !dram_router_stale_discard_i) begin
`ifndef SYNTHESIS
				if (!pending_q) begin
					unexpected_response_q <= 1'b1;
				end else if (response_capture_valid_q) begin
					response_capture_overflow_q <= 1'b1;
				end
`endif
				if (pending_q && !response_capture_valid_q &&
					!live_response_fire_w &&
					!stale_response_fire_w) begin
					response_capture_valid_q <= 1'b1;
`ifndef SYNTHESIS
					response_capture_data_q <= dram_resp_data_i;
`else
					response_capture_data_q <= dram_resp_data_i[12:0];
`endif
				end
			end

			// Raw abort drops row state and drains accepted reads.
			if (abort_i) begin
				result_source_conflict_q <= 1'b0;
				h00_reference_valid_q <= 1'b0;
				source_conflict_seen_q <= 1'b0;
				if (!dram_router_stale_discard_i) begin
					if (pending_q) begin
						pending_stale_q <= 1'b1;
						state_q <= STATE_DRAIN;
					end else begin
						state_q <= STATE_IDLE;
					end
				end
			end

			if (ce_i) begin
`ifndef SYNTHESIS
				if (dram_accept_i && !dram_req_o) begin
					accept_without_request_q <= 1'b1;
				end
`endif

				if (stale_response_fire_w) begin
					pending_q <= 1'b0;
					pending_stale_q <= 1'b0;
					pending_owner_q <= OWNER_NONE;
					response_capture_valid_q <= 1'b0;
					state_q <= STATE_IDLE;
`ifndef SYNTHESIS
					stale_response_discarded_q <= 1'b1;
`endif
				end else if (live_response_fire_w) begin
`ifndef SYNTHESIS
					if (((pending_owner_q == OWNER_PARAM_LEFT) &&
						(state_q != STATE_READ_LEFT)) ||
						((pending_owner_q == OWNER_PARAM_RIGHT) &&
						(state_q != STATE_READ_RIGHT)) ||
						(pending_owner_q == OWNER_NONE)) begin
						pending_owner_mismatch_q <= 1'b1;
					end
`endif
					pending_q <= 1'b0;
					pending_stale_q <= 1'b0;
					pending_owner_q <= OWNER_NONE;
					response_capture_valid_q <= 1'b0;
`ifndef SYNTHESIS
					response_retired_q <= 1'b1;
`endif

					if (pending_owner_q == OWNER_PARAM_LEFT) begin
						left_offset_q <= response_offset_w;
`ifndef SYNTHESIS
						raw_left_q <= response_raw_w;
`endif
						if (odd_alias_q) begin
							right_offset_q <= response_offset_w;
`ifndef SYNTHESIS
							raw_right_q <= response_raw_w;
`endif
							state_q <= STATE_RESULT;
						end else begin
							state_q <= STATE_READ_RIGHT;
						end
					end else if (pending_owner_q ==
						OWNER_PARAM_RIGHT) begin
						right_offset_q <= response_offset_w;
`ifndef SYNTHESIS
						raw_right_q <= response_raw_w;
`endif
						state_q <= STATE_RESULT;
					end

					if (pair_complete_w) begin
						result_source_conflict_q <= h00_conflict_w;
						if (row_first_in_strip_q ||
							!h00_reference_valid_q) begin
`ifndef SYNTHESIS
							if (!row_first_in_strip_q &&
								!h00_reference_valid_q) begin
								h00_reference_protocol_error_q <=
									1'b1;
							end
`endif
							h00_reference_valid_q <= 1'b1;
							h00_reference_left_q <=
								completed_left_offset_w;
							h00_reference_right_q <=
								completed_right_offset_w;
						end else if (h00_conflict_w) begin
							source_conflict_seen_q <= 1'b1;
						end
					end
				end

				if (!abort_i && request_accept_fire_w) begin
					pending_q <= 1'b1;
					pending_stale_q <= 1'b0;
					pending_owner_q <= request_owner_w;
`ifndef SYNTHESIS
					request_accepted_q <= 1'b1;
`endif
				end

				if (!abort_i && row_valid_i && row_ready_o) begin
`ifndef SYNTHESIS
					row_world_q <= row_world_i;
					row_strip_q <= row_strip_i;
`endif
					row_first_in_strip_q <=
						row_first_in_strip_i;
					row_screen_y_q <= row_screen_y_i;
					row_local_row_q <= local_row_wrapped_w;
					left_index_q <= calculated_left_index_w;
					right_index_q <= calculated_right_index_w;
					odd_alias_q <= calculated_left_index_w[0];
`ifndef SYNTHESIS
					address_wrapped_q <= calculated_address_wrapped_w;
`endif
					left_offset_q <= 18'sd0;
					right_offset_q <= 18'sd0;
`ifndef SYNTHESIS
					raw_left_q <= 16'd0;
					raw_right_q <= 16'd0;
`endif
					result_source_conflict_q <= 1'b0;
					state_q <= STATE_READ_LEFT;
`ifndef SYNTHESIS
					if (invalid_local_row_w) begin
						invalid_local_row_seen_q <= 1'b1;
					end
`endif
				end

				if (!abort_i && result_fire_w) begin
					state_q <= STATE_IDLE;
					result_source_conflict_q <= 1'b0;
				end
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Registered H-bias stereo row geometry.
//
// One row context carries both eyes. The source equations are:
//
// left  = MX - MP + HOFSTL
// right = MX + MP + HOFSTR
//
// Charge the half-open union of both eye intervals. Tile bounds use signed floor
// and ceiling by eight. Mapping bias converts source X to each destination X.
//
// Pipeline source math, min/max, alignment, and count. Hold one context until
// accepted; raw abort drops it immediately.

module vip_xp_hbias_row_geometry
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	input  wire                 input_valid_i,
	output wire                 input_ready_o,
	input  wire signed [12:0]   mx_i,
	input  wire signed [14:0]   mp_i,
	input  wire signed [12:0]   hofst_left_i,
	input  wire signed [12:0]   hofst_right_i,
	input  wire [12:0]          semantic_width_i,
	input  wire signed [9:0]    gx_i,
	input  wire signed [9:0]    gp_i,

	output wire                 output_valid_o,
	input  wire                 output_ready_i,
	output reg  signed [17:0]   left_source_start_o,
	output reg  signed [17:0]   right_source_start_o,
	output reg  signed [17:0]   left_destination_start_o,
	output reg  signed [17:0]   right_destination_start_o,
	output reg  signed [17:0]   union_low_o,
	output reg  signed [17:0]   union_high_exclusive_o,
	output reg  signed [14:0]   union_tile_floor_o,
	output reg  signed [14:0]   union_tile_ceil_exclusive_o,
	output reg  signed [15:0]   union_tile_count_o,
	output reg  signed [17:0]   left_tile_mapping_bias_o,
	output reg  signed [17:0]   right_tile_mapping_bias_o,
	output reg  signed [17:0]   first_tile_source_x_o,
	output reg  signed [17:0]   first_tile_left_destination_base_o,
	output reg  signed [17:0]   first_tile_right_destination_base_o,
	output reg                  malformed_o,
	output wire                 busy_o
);

	localparam [2:0]
		STATE_IDLE     = 3'd0,
		STATE_BASE     = 3'd1,
		STATE_OFFSET   = 3'd2,
		STATE_UNION    = 3'd3,
		STATE_ENDPOINT = 3'd4,
		STATE_TILE     = 3'd5,
		STATE_RESULT   = 3'd6,
		STATE_OUTPUT   = 3'd7;

	reg [2:0] state_q;

	reg signed [12:0] mx_q;
	reg signed [14:0] mp_q;
	reg signed [12:0] hofst_left_q;
	reg signed [12:0] hofst_right_q;
	reg [12:0] semantic_width_q;
	reg signed [9:0] gx_q;
	reg signed [9:0] gp_q;
	reg width_malformed_q;

	reg signed [17:0] left_source_base_q;
	reg signed [17:0] right_source_base_q;
	reg signed [17:0] left_source_q;
	reg signed [17:0] right_source_q;
	reg signed [17:0] left_destination_q;
	reg signed [17:0] right_destination_q;
	reg signed [17:0] union_low_q;
	reg signed [17:0] union_max_start_q;
	reg signed [17:0] union_high_q;
	reg signed [17:0] left_mapping_bias_q;
	reg signed [17:0] right_mapping_bias_q;
	reg signed [14:0] union_tile_low_q;
	reg signed [14:0] union_tile_high_q;

	wire signed [17:0] mx_extended_w =
		{{5{mx_q[12]}}, mx_q};
	wire signed [17:0] mp_extended_w =
		{{3{mp_q[14]}}, mp_q};
	wire signed [17:0] hofst_left_extended_w =
		{{5{hofst_left_q[12]}}, hofst_left_q};
	wire signed [17:0] hofst_right_extended_w =
		{{5{hofst_right_q[12]}}, hofst_right_q};
	wire signed [17:0] gx_extended_w =
		{{8{gx_q[9]}}, gx_q};
	wire signed [17:0] gp_extended_w =
		{{8{gp_q[9]}}, gp_q};
	wire signed [17:0] width_extended_w =
		$signed({5'b00000, semantic_width_q});

	wire signed [14:0] union_low_floor_tile_w =
		union_low_q[17:3];
	wire signed [14:0] union_high_floor_tile_w =
		union_high_q[17:3];
	wire union_high_has_fraction_w = |union_high_q[2:0];
	wire signed [14:0] union_high_ceil_tile_w =
		union_high_floor_tile_w +
		$signed({14'b00000000000000, union_high_has_fraction_w});
	wire signed [15:0] union_tile_delta_w =
		{union_tile_high_q[14], union_tile_high_q} -
		{union_tile_low_q[14], union_tile_low_q};
	wire signed [17:0] first_tile_source_x_w =
		{union_tile_low_q, 3'b000};

	wire input_fire_w = input_valid_i && input_ready_o;
	wire output_fire_w = output_valid_o && output_ready_i && ce_i;

	assign input_ready_o = ce_i && !reset_i && !abort_i &&
		(state_q == STATE_IDLE);
	assign output_valid_o = !reset_i && !abort_i &&
		(state_q == STATE_OUTPUT);
	assign busy_o = state_q != STATE_IDLE;

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			mx_q <= 13'sd0;
			mp_q <= 15'sd0;
			hofst_left_q <= 13'sd0;
			hofst_right_q <= 13'sd0;
			semantic_width_q <= 13'd0;
			gx_q <= 10'sd0;
			gp_q <= 10'sd0;
			width_malformed_q <= 1'b0;
			left_source_base_q <= 18'sd0;
			right_source_base_q <= 18'sd0;
			left_source_q <= 18'sd0;
			right_source_q <= 18'sd0;
			left_destination_q <= 18'sd0;
			right_destination_q <= 18'sd0;
			union_low_q <= 18'sd0;
			union_max_start_q <= 18'sd0;
			union_high_q <= 18'sd0;
			left_mapping_bias_q <= 18'sd0;
			right_mapping_bias_q <= 18'sd0;
			union_tile_low_q <= 15'sd0;
			union_tile_high_q <= 15'sd0;
			left_source_start_o <= 18'sd0;
			right_source_start_o <= 18'sd0;
			left_destination_start_o <= 18'sd0;
			right_destination_start_o <= 18'sd0;
			union_low_o <= 18'sd0;
			union_high_exclusive_o <= 18'sd0;
			union_tile_floor_o <= 15'sd0;
			union_tile_ceil_exclusive_o <= 15'sd0;
			union_tile_count_o <= 16'sd0;
			left_tile_mapping_bias_o <= 18'sd0;
			right_tile_mapping_bias_o <= 18'sd0;
			first_tile_source_x_o <= 18'sd0;
			first_tile_left_destination_base_o <= 18'sd0;
			first_tile_right_destination_base_o <= 18'sd0;
			malformed_o <= 1'b0;
		end else if (abort_i) begin
			state_q <= STATE_IDLE;
		end else if (ce_i) begin
			case (state_q)
				STATE_IDLE: begin
					if (input_fire_w) begin
						mx_q <= mx_i;
						mp_q <= mp_i;
						hofst_left_q <= hofst_left_i;
						hofst_right_q <= hofst_right_i;
						semantic_width_q <= semantic_width_i;
						gx_q <= gx_i;
						gp_q <= gp_i;
						width_malformed_q <=
							(semantic_width_i == 13'd0) ||
							(semantic_width_i > 13'd4096);
						state_q <= STATE_BASE;
					end
				end

				STATE_BASE: begin
					left_source_base_q <= mx_extended_w -
						mp_extended_w;
					right_source_base_q <= mx_extended_w +
						mp_extended_w;
					left_destination_q <= gx_extended_w -
						gp_extended_w;
					right_destination_q <= gx_extended_w +
						gp_extended_w;
					state_q <= STATE_OFFSET;
				end

				STATE_OFFSET: begin
					left_source_q <= left_source_base_q +
						hofst_left_extended_w;
					right_source_q <= right_source_base_q +
						hofst_right_extended_w;
					state_q <= STATE_UNION;
				end

				STATE_UNION: begin
					if (left_source_q <= right_source_q) begin
						union_low_q <= left_source_q;
						union_max_start_q <= right_source_q;
					end else begin
						union_low_q <= right_source_q;
						union_max_start_q <= left_source_q;
					end
					left_mapping_bias_q <= left_destination_q -
						left_source_q;
					right_mapping_bias_q <= right_destination_q -
						right_source_q;
					state_q <= STATE_ENDPOINT;
				end

				STATE_ENDPOINT: begin
					union_high_q <= union_max_start_q +
						width_extended_w;
					state_q <= STATE_TILE;
				end

				STATE_TILE: begin
					union_tile_low_q <= union_low_floor_tile_w;
					union_tile_high_q <= union_high_ceil_tile_w;
					state_q <= STATE_RESULT;
				end

				STATE_RESULT: begin
					left_source_start_o <= left_source_q;
					right_source_start_o <= right_source_q;
					left_destination_start_o <=
						left_destination_q;
					right_destination_start_o <=
						right_destination_q;
					union_low_o <= union_low_q;
					union_high_exclusive_o <= union_high_q;
					union_tile_floor_o <= union_tile_low_q;
					union_tile_ceil_exclusive_o <=
						union_tile_high_q;
					union_tile_count_o <= union_tile_delta_w;
					left_tile_mapping_bias_o <=
						left_mapping_bias_q;
					right_tile_mapping_bias_o <=
						right_mapping_bias_q;
					first_tile_source_x_o <=
						first_tile_source_x_w;
					first_tile_left_destination_base_o <=
						first_tile_source_x_w +
						left_mapping_bias_q;
					first_tile_right_destination_base_o <=
						first_tile_source_x_w +
						right_mapping_bias_q;
					malformed_o <= width_malformed_q ||
						union_tile_delta_w[15] ||
						(union_high_q < union_low_q);
					state_q <= STATE_OUTPUT;
				end

				// STATE_OUTPUT: hold the result until it is taken.
				default: begin
					if (output_fire_w) begin
						state_q <= STATE_IDLE;
					end
				end
			endcase
		end
	end

endmodule

`timescale 1ns/1ps

// Held Affine descriptor adapter.
//
// Capture shared descriptor fields and add Affine width, height, and policy
// checks. Descriptor MX, MP, and MY are kept for snapshots, not source position.
// The registered snapshot outputs are bench observability only: both RTL
// instantiation sites leave them open and consume just the live_* view,
// the record handshake, and the sticky policy flags.

module vip_xp_affine_decode
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	input  wire                 descriptor_valid_i,
	output wire                 descriptor_ready_o,
	output wire                 descriptor_accept_o,
	input  wire [255:0]         descriptor_i,
	input  wire [31:0]          gplt_active_i,

	output wire                 record_valid_o,
	input  wire                 record_ready_i,
	output reg  [255:0]         descriptor_raw_o,
	output reg  [31:0]          gplt_active_o,
	output reg  [15:0]          word0_o,
	output reg                  lon_o,
	output reg                  ron_o,
	output reg  [1:0]           kind_o,
	output reg                  kind_valid_o,
	output reg  [1:0]           scx_o,
	output reg  [1:0]           scy_o,
	output reg                  over_o,
	output reg                  end_o,
	output reg                  dummy_o,
	output reg  [3:0]           bgmap_base_raw_o,

	output reg  signed [9:0]    gx_o,
	output reg  signed [9:0]    gp_o,
	output reg  signed [15:0]   gy_o,
	output reg  [15:0]          ignored_mx_raw_o,
	output reg  [15:0]          ignored_mp_raw_o,
	output reg  [15:0]          ignored_my_raw_o,
	output reg  [15:0]          raw_w_o,
	output reg  [15:0]          raw_h_o,
	output reg  [15:0]          param_base_o,
	output reg  [15:0]          overplane_o,

	output reg  [10:0]          semantic_width_o,
	output reg  signed [16:0]   semantic_height_o,
	output reg  signed [17:0]   visual_start_y_o,
	output reg  signed [17:0]   visual_end_y_exclusive_o,

	output reg  [3:0]           maps_wide_o,
	output reg  [3:0]           maps_high_o,
	output reg  [3:0]           effective_map_count_o,
	output reg  [3:0]           effective_map_columns_o,
	output reg  [3:0]           bgmap_base_rounded_o,

	output reg                  descriptor_kind_mismatch_o,
	output reg                  raw_w_upper_nonzero_o,
	output reg                  raw_w_documented_range_high_o,
	output reg                  raw_h_negative_o,
	output reg                  raw_h_documented_range_high_o,
	output reg                  strict_overplane_high_o,
	output reg                  param_base_unaligned_o,
	output reg                  malformed_descriptor_o,
	output reg                  strict_policy_violation_o,
	output reg                  work_behavior_unresolved_o,

	// Same-edge Affine decode for command acceptance.
	output wire                 live_lon_o,
	output wire                 live_ron_o,
	output wire                 live_over_o,
	output wire signed [9:0]    live_gx_o,
	output wire signed [9:0]    live_gp_o,
	output wire signed [15:0]   live_gy_o,
	output wire [15:0]          live_param_base_o,
	output wire [15:0]          live_overplane_o,
	output wire [10:0]          live_semantic_width_o,
	output wire signed [16:0]   live_semantic_height_o,
	output wire [3:0]           live_maps_wide_o,
	output wire [3:0]           live_maps_high_o,
	output wire [3:0]           live_effective_map_columns_o,
	output wire [3:0]           live_bgmap_base_rounded_o,
	output wire                 live_descriptor_kind_mismatch_o,
	output wire                 live_raw_w_upper_nonzero_o,
	output wire                 live_raw_w_documented_range_high_o,
	output wire                 live_raw_h_negative_o,
	output wire                 live_raw_h_documented_range_high_o,
	output wire                 live_strict_overplane_high_o,
	output wire                 live_param_base_unaligned_o,
	output wire                 live_malformed_descriptor_o,
	output wire                 live_strict_policy_violation_o,
	output wire                 live_work_behavior_unresolved_o
);

	reg record_valid_q;

	wire [255:0] common_descriptor_raw_w;
	wire [15:0] common_word0_w;
	wire common_lon_w;
	wire common_ron_w;
	wire [1:0] common_kind_w;
	wire [1:0] common_scx_w;
	wire [1:0] common_scy_w;
	wire common_over_w;
	wire common_end_w;
	wire common_dummy_w;
	wire [3:0] common_bgmap_base_raw_w;
	wire signed [9:0] common_gx_w;
	wire signed [9:0] common_gp_w;
	wire signed [15:0] common_gy_w;
	wire [15:0] common_raw_w_w;
	wire [15:0] common_raw_h_w;
	wire [15:0] common_param_base_w;
	wire [15:0] common_overplane_w;
	wire [3:0] common_maps_wide_w;
	wire [3:0] common_maps_high_w;
	wire [3:0] common_effective_map_count_w;
	wire [3:0] common_effective_map_columns_w;
	wire [3:0] common_bgmap_base_rounded_w;
	wire common_strict_overplane_high_w;

	wire [10:0] affine_semantic_width_w =
		{1'b0, common_raw_w_w[9:0]} + 11'd1;
	wire signed [16:0] affine_semantic_height_w =
		$signed({common_raw_h_w[15], common_raw_h_w}) + 17'sd1;
	wire signed [17:0] affine_visual_start_y_w =
		{{2{common_gy_w[15]}}, common_gy_w};
	wire signed [17:0] affine_visual_end_y_exclusive_w =
		affine_visual_start_y_w +
		{{1{affine_semantic_height_w[16]}},
			affine_semantic_height_w};

	wire descriptor_kind_mismatch_w = common_kind_w != 2'd2;
	wire raw_w_upper_nonzero_w = |common_raw_w_w[15:10];
	wire raw_w_documented_range_high_w =
		common_raw_w_w[9:0] > 10'd383;
	wire raw_h_negative_w = common_raw_h_w[15];
	wire raw_h_documented_range_high_w = !common_raw_h_w[15] &&
		(common_raw_h_w[14:0] > 15'd223);
	// Param Base is a halfword index; eight halfwords make one Affine row.
	wire param_base_unaligned_w = |common_param_base_w[2:0];
	wire malformed_descriptor_w = raw_w_upper_nonzero_w ||
		raw_w_documented_range_high_w || raw_h_negative_w ||
		raw_h_documented_range_high_w;
	// OVER is a full 16-bit map character address; flag but allow high values.
	wire strict_policy_violation_w = descriptor_kind_mismatch_w ||
		param_base_unaligned_w;

	wire record_fire_w = ce_i && record_valid_o && record_ready_i;

	assign live_lon_o = common_lon_w;
	assign live_ron_o = common_ron_w;
	assign live_over_o = common_over_w;
	assign live_gx_o = common_gx_w;
	assign live_gp_o = common_gp_w;
	assign live_gy_o = common_gy_w;
	assign live_param_base_o = common_param_base_w;
	assign live_overplane_o = common_overplane_w;
	assign live_semantic_width_o = affine_semantic_width_w;
	assign live_semantic_height_o = affine_semantic_height_w;
	assign live_maps_wide_o = common_maps_wide_w;
	assign live_maps_high_o = common_maps_high_w;
	assign live_effective_map_columns_o =
		common_effective_map_columns_w;
	assign live_bgmap_base_rounded_o = common_bgmap_base_rounded_w;
	assign live_descriptor_kind_mismatch_o =
		descriptor_kind_mismatch_w;
	assign live_raw_w_upper_nonzero_o = raw_w_upper_nonzero_w;
	assign live_raw_w_documented_range_high_o =
		raw_w_documented_range_high_w;
	assign live_raw_h_negative_o = raw_h_negative_w;
	assign live_raw_h_documented_range_high_o =
		raw_h_documented_range_high_w;
	assign live_strict_overplane_high_o =
		common_strict_overplane_high_w;
	assign live_param_base_unaligned_o = param_base_unaligned_w;
	assign live_malformed_descriptor_o = malformed_descriptor_w;
	assign live_strict_policy_violation_o = strict_policy_violation_w;
	// Silicon unknown: work words 5-7 and unaligned tables are uncharacterized.
	assign live_work_behavior_unresolved_o = 1'b1;

	assign descriptor_ready_o = ce_i && !reset_i && !abort_i &&
		(!record_valid_q || record_ready_i);
	assign descriptor_accept_o = descriptor_valid_i &&
		descriptor_ready_o;
	assign record_valid_o = !reset_i && !abort_i && record_valid_q;

	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_bg_descriptor_decode u_common_decode
	(
		.descriptor_i(descriptor_i),
		.descriptor_raw_o(common_descriptor_raw_w),
		.word0_o(common_word0_w),
		.lon_o(common_lon_w),
		.ron_o(common_ron_w),
		.kind_o(common_kind_w),
		.scx_o(common_scx_w),
		.scy_o(common_scy_w),
		.over_o(common_over_w),
		.end_o(common_end_w),
		.dummy_o(common_dummy_w),
		.bgmap_base_raw_o(common_bgmap_base_raw_w),
		.gx_o(common_gx_w),
		.gp_o(common_gp_w),
		.gy_o(common_gy_w),
		.mx_o(),
		.mp_o(),
		.my_o(),
		.raw_w_o(common_raw_w_w),
		.raw_h_o(common_raw_h_w),
		.param_base_o(common_param_base_w),
		.overplane_o(common_overplane_w),
		.semantic_width_o(),
		.semantic_height_o(),
		.visual_height_o(),
		.timing_height_o(),
		.visual_end_y_exclusive_o(),
		.timing_end_y_exclusive_o(),
		.maps_wide_o(common_maps_wide_w),
		.maps_high_o(common_maps_high_w),
		.effective_map_count_o(common_effective_map_count_w),
		.effective_map_columns_o(common_effective_map_columns_w),
		.bgmap_base_rounded_o(common_bgmap_base_rounded_w),
		.raw_h_timing_conflict_o(),
		.strict_overplane_high_o(common_strict_overplane_high_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	always @(posedge clk_i) begin
		if (reset_i) begin
			record_valid_q <= 1'b0;
			descriptor_raw_o <= 256'd0;
			gplt_active_o <= 32'd0;
			word0_o <= 16'd0;
			lon_o <= 1'b0;
			ron_o <= 1'b0;
			kind_o <= 2'd0;
			kind_valid_o <= 1'b0;
			scx_o <= 2'd0;
			scy_o <= 2'd0;
			over_o <= 1'b0;
			end_o <= 1'b0;
			dummy_o <= 1'b1;
			bgmap_base_raw_o <= 4'd0;
			gx_o <= 10'sd0;
			gp_o <= 10'sd0;
			gy_o <= 16'sd0;
			ignored_mx_raw_o <= 16'd0;
			ignored_mp_raw_o <= 16'd0;
			ignored_my_raw_o <= 16'd0;
			raw_w_o <= 16'd0;
			raw_h_o <= 16'd0;
			param_base_o <= 16'd0;
			overplane_o <= 16'd0;
			semantic_width_o <= 11'd0;
			semantic_height_o <= 17'sd0;
			visual_start_y_o <= 18'sd0;
			visual_end_y_exclusive_o <= 18'sd0;
			maps_wide_o <= 4'd1;
			maps_high_o <= 4'd1;
			effective_map_count_o <= 4'd1;
			effective_map_columns_o <= 4'd1;
			bgmap_base_rounded_o <= 4'd0;
			descriptor_kind_mismatch_o <= 1'b0;
			raw_w_upper_nonzero_o <= 1'b0;
			raw_w_documented_range_high_o <= 1'b0;
			raw_h_negative_o <= 1'b0;
			raw_h_documented_range_high_o <= 1'b0;
			strict_overplane_high_o <= 1'b0;
			param_base_unaligned_o <= 1'b0;
			malformed_descriptor_o <= 1'b0;
			strict_policy_violation_o <= 1'b0;
			work_behavior_unresolved_o <= 1'b0;
		end else if (abort_i) begin
			record_valid_q <= 1'b0;
		end else if (ce_i) begin
			if (descriptor_accept_o) begin
				record_valid_q <= 1'b1;
				descriptor_raw_o <= common_descriptor_raw_w;
				gplt_active_o <= gplt_active_i;
				word0_o <= common_word0_w;
				lon_o <= common_lon_w;
				ron_o <= common_ron_w;
				kind_o <= common_kind_w;
				kind_valid_o <= !descriptor_kind_mismatch_w;
				scx_o <= common_scx_w;
				scy_o <= common_scy_w;
				over_o <= common_over_w;
				end_o <= common_end_w;
				dummy_o <= common_dummy_w;
				bgmap_base_raw_o <= common_bgmap_base_raw_w;
				gx_o <= common_gx_w;
				gp_o <= common_gp_w;
				gy_o <= common_gy_w;
				ignored_mx_raw_o <=
					common_descriptor_raw_w[64 +: 16];
				ignored_mp_raw_o <=
					common_descriptor_raw_w[80 +: 16];
				ignored_my_raw_o <=
					common_descriptor_raw_w[96 +: 16];
				raw_w_o <= common_raw_w_w;
				raw_h_o <= common_raw_h_w;
				param_base_o <= common_param_base_w;
				overplane_o <= common_overplane_w;
				semantic_width_o <= affine_semantic_width_w;
				semantic_height_o <= affine_semantic_height_w;
				visual_start_y_o <= affine_visual_start_y_w;
				visual_end_y_exclusive_o <=
					affine_visual_end_y_exclusive_w;
				maps_wide_o <= common_maps_wide_w;
				maps_high_o <= common_maps_high_w;
				effective_map_count_o <=
					common_effective_map_count_w;
				effective_map_columns_o <=
					common_effective_map_columns_w;
				bgmap_base_rounded_o <=
					common_bgmap_base_rounded_w;
				descriptor_kind_mismatch_o <=
					descriptor_kind_mismatch_w;
				raw_w_upper_nonzero_o <= raw_w_upper_nonzero_w;
				raw_w_documented_range_high_o <=
					raw_w_documented_range_high_w;
				raw_h_negative_o <= raw_h_negative_w;
				raw_h_documented_range_high_o <=
					raw_h_documented_range_high_w;
				strict_overplane_high_o <=
					common_strict_overplane_high_w;
				param_base_unaligned_o <= param_base_unaligned_w;
				malformed_descriptor_o <= malformed_descriptor_w;
				strict_policy_violation_o <=
					strict_policy_violation_w;
				// A01 does not model the three unknown work-word writes.
				work_behavior_unresolved_o <= 1'b1;
			end else if (record_fire_w) begin
				record_valid_q <= 1'b0;
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Affine-world front end.
//
// Owns scheduling, aligned parameters, MP DDA, stereo sampling, and four-pixel
// packing. Character decode and row storage are shared. PARAM has fresh-offer
// priority over CELL on the DRAM port.
//
// Row setup completes after the left CELL prime. A pixel completes only when
// its sample, packer, and needed row-store commit all accept.

module vip_xp_affine_frontend
#(
	parameter integer COMPOSED_TIMING_CREDIT_ENABLE = 0,
	parameter integer GENERATION_WIDTH = 8
)
(
	input  wire                        clk_i,
	input  wire                        reset_i,
	input  wire                        ce_i,
	input  wire                        abort_i,

	// Affine strip command. Policy rejects complete without starting the scheduler.
	input  wire                        start_valid_i,
	output wire                        start_ready_o,
	output wire                        start_accept_o,
	input  wire                        strict_policy_violation_i,
	input  wire [2:0]                  parallax_scale_i,
	input  wire [4:0]                  world_i,
	input  wire [4:0]                  strip_i,
	input  wire                        first_visit_i,
	input  wire signed [15:0]          gy_i,
	input  wire [10:0]                 semantic_width_i,
	input  wire signed [16:0]          semantic_height_i,
	input  wire [15:0]                 param_base_i,
	input  wire signed [15:0]          gx_i,
	input  wire signed [15:0]          gp_i,
	input  wire                        left_on_i,
	input  wire                        right_on_i,
	input  wire [3:0]                  maps_wide_i,
	input  wire [3:0]                  maps_high_i,
	input  wire [3:0]                  effective_map_columns_i,
	input  wire [3:0]                  bgmap_base_rounded_i,
	input  wire                        over_i,
	input  wire [15:0]                 overplane_i,
	input  wire [31:0]                 gplt_active_i,

	// Held query and result for the shared background-address block.
	output wire signed [16:0]          address_source_x_o,
	output wire signed [16:0]          address_source_y_o,
	output wire [3:0]                  address_maps_wide_o,
	output wire [3:0]                  address_maps_high_o,
	output wire [3:0]                  address_effective_map_columns_o,
	output wire [3:0]                  address_bgmap_base_rounded_o,
	output wire                        address_over_o,
	output wire [15:0]                 address_overplane_o,
	output wire [15:0]                 address_cell_o,
	output wire [2:0]                  address_cell_source_row_o,
	input  wire [15:0]                 addressed_dram_cell_addr_i,
	input  wire                        addressed_overplane_selected_i,
	input  wire                        addressed_strict_overplane_i,
	input  wire                        addressed_map_index_overflow_i,
	input  wire [15:0]                 addressed_vrm_character_row_addr_i,
	input  wire [1:0]                  addressed_palette_i,
	input  wire                        addressed_hflip_i,
	input  wire                        addressed_vflip_i,

	output wire                        busy_o,
	output wire                        done_o,
	output reg                         reject_pulse_o,
	output reg                         abort_done_pulse_o,
	output reg                         invalid_width_reject_o,
	output reg                         unaligned_param_reject_o,
	output reg                         strict_policy_reject_o,
	output wire                        nonzero_mp_fault_o,
	output wire                        nonzero_mp_policy_seen_o,
	output reg                         raw_abort_seen_o,
	output wire                        local_abort_active_o,

	// Shared DRAM owner; PARAM has fresh-offer priority over CELL.
	output wire                        dram_abort_o,
	output wire                        dram_req_o,
	output wire [15:0]                 dram_addr_o,
	input  wire                        dram_accept_i,
	input  wire                        dram_resp_valid_i,
	input  wire [15:0]                 dram_resp_data_i,
	input  wire                        dram_cleanup_busy_i,
	input  wire                        dram_stale_discard_i,

	// Character-row VRM client.
	output wire                        char_vrm_abort_o,
	output wire                        char_vrm_req_o,
	output wire [15:0]                 char_vrm_addr_o,
	input  wire                        char_vrm_accept_i,
	input  wire                        char_vrm_resp_valid_i,
	input  wire [15:0]                 char_vrm_resp_data_i,
	input  wire                        char_vrm_cleanup_busy_i,
	input  wire                        char_vrm_stale_discard_i,

	// Shared character and GPLT decoder interface.
	output wire [15:0]                 decode_character_row_o,
	output wire [1:0]                  decode_palette_o,
	output wire                        decode_hflip_o,
	output wire [2:0]                  decode_source_x_index_o,
	output wire [31:0]                 decode_gplt_active_o,
	input  wire [1:0]                  decoded_raw_pixel_i,
	input  wire                        decoded_raw_nonzero_i,
	input  wire [1:0]                  decoded_mapped_pixel_i,

	// Affine row-store prepare and commit interface.
	output wire                        row_store_abort_o,
	output wire                        affine_prepare_valid_o,
	input  wire                        affine_prepare_ready_i,
	output wire                        affine_prepare_accept_o,
	output wire [2:0]                  affine_prepare_row_o,
	output wire signed [15:0]          affine_prepare_left_base_x_o,
	output wire                        affine_prepare_left_enable_o,
	output wire signed [15:0]          affine_prepare_right_base_x_o,
	output wire                        affine_prepare_right_enable_o,
	output wire                        affine_commit_valid_o,
	input  wire                        affine_commit_ready_i,
	output wire                        affine_commit_accept_o,
	output wire [3:0]                  affine_commit_left_active_o,
	output wire [3:0]                  affine_commit_left_opaque_o,
	output wire [7:0]                  affine_commit_left_values_o,
	output wire [3:0]                  affine_commit_right_active_o,
	output wire [3:0]                  affine_commit_right_opaque_o,
	output wire [7:0]                  affine_commit_right_values_o,
	input  wire                        affine_store_quiescent_i,

	// CE-qualified integration diagnostics.
	output wire [2:0]                  scheduler_state_o,
	output wire [9:0]                  scheduler_ticks_remaining_o,
	output wire [9:0]                  scheduler_pixel_ordinal_o,
	output wire                        scheduler_pixel_accept_o,
	output wire [3:0]                  sample_state_o,
	output wire                        sample_prime_complete_o,
	output wire                        sample_result_accept_o,
	output wire                        packer_prepare_accept_o,
	output wire                        packer_commit_accept_o,
	output wire                        actual_downstream_idle_o,
	output wire                        final_will_be_idle_o,
	output wire                        cleanup_interlock_o,
	output wire                        param_dram_selected_o,
	output wire                        dram_mux_held_offer_o,
	output wire                        dram_mux_read_pending_o,
	output wire [31:0]                 scheduler_elapsed_ticks_o,
	output wire [31:0]                 scheduler_row_setup_ticks_o,
	output wire [31:0]                 scheduler_pixel_ticks_o,
	output wire [31:0]                 scheduler_stall_ticks_o,
	output wire [15:0]                 scheduler_row_start_count_o,
	output wire [15:0]                 scheduler_row_context_count_o,
	output wire [31:0]                 scheduler_pixel_count_o,
	output wire                        sample_strict_overplane_seen_o,
	output wire                        sample_map_index_overflow_seen_o,
	output wire                        protocol_error_o
);

	localparam [2:0]
		SCHED_STATE_ROW_SETUP = 3'd3,
		SCHED_STATE_PIXEL     = 3'd4;
	localparam [3:0]
		SAMPLE_STAGE0 = 4'd3;

	reg command_active_q;
	reg cleanup_interlock_q;
	reg done_pulse_q;

	reg [15:0] param_base_q;
	reg signed [15:0] gx_q;
	reg signed [15:0] gp_q;
	reg left_on_q;
	reg right_on_q;
	reg [3:0] maps_wide_q;
	reg [3:0] maps_high_q;
	reg [3:0] effective_map_columns_q;
	reg [3:0] bgmap_base_rounded_q;
	reg over_q;
	reg [15:0] overplane_q;
	reg [31:0] gplt_active_q;
	reg [10:0] semantic_width_q;

	wire known_width_legal_w =
		(semantic_width_i >= 11'd1) &&
		(semantic_width_i <= 11'd1024);
	wire known_alignment_legal_w = param_base_i[2:0] == 3'd0;
	wire admission_legal_w = known_width_legal_w &&
		known_alignment_legal_w && !strict_policy_violation_i;

	wire scheduler_start_ready_w;
	wire scheduler_busy_w;
	wire scheduler_done_w;
	wire scheduler_row_start_valid_w;
	wire scheduler_row_start_ready_w;
	wire [4:0] scheduler_row_world_w;
	wire [4:0] scheduler_row_strip_w;
	wire [8:0] scheduler_row_screen_y_w;
	wire [15:0] scheduler_row_local_y_w;
	wire scheduler_row_context_ready_w;
	wire scheduler_pixel_valid_w;
	wire scheduler_pixel_ready_w;
	wire [4:0] scheduler_pixel_world_w;
	wire [4:0] scheduler_pixel_strip_w;
	wire [8:0] scheduler_pixel_screen_y_w;
	wire [15:0] scheduler_pixel_local_y_w;
	wire [9:0] scheduler_pixel_group_start_w;
	wire [2:0] scheduler_pixel_group_slot_w;
	wire scheduler_pixel_last_in_row_w;
	wire scheduler_pixel_last_in_strip_w;
	wire scheduler_downstream_idle_w;

	wire row_context_valid_w;
	wire row_context_accept_window_w;
	wire row_pixel_valid_w;
	wire row_pixel_ready_w;
	wire [4:0] row_pixel_world_w;
	wire [4:0] row_pixel_strip_w;
	wire [8:0] row_pixel_screen_y_w;
	wire [15:0] row_pixel_local_y_w;
	wire [9:0] row_pixel_ordinal_w;
	wire row_pixel_last_w;
	wire signed [16:0] row_left_source_x_w;
	wire signed [16:0] row_left_source_y_w;
	wire signed [16:0] row_right_source_x_w;
	wire signed [16:0] row_right_source_y_w;
	wire row_pipeline_busy_w;
	wire row_pipeline_cleanup_busy_w;
	wire row_pipeline_downstream_idle_w;
	wire row_param_read_pending_w;
	wire row_protocol_error_w;

	wire param_dram_req_w;
	wire [15:0] param_dram_addr_w;
	wire param_dram_accept_w;
	wire param_dram_resp_valid_w;
	wire [15:0] param_dram_resp_data_w;
	wire param_dram_cleanup_busy_w;
	wire param_dram_stale_discard_w;

	wire sample_dram_req_w;
	wire [15:0] sample_dram_addr_w;
	wire sample_dram_accept_w;
	wire sample_dram_resp_valid_w;
	wire [15:0] sample_dram_resp_data_w;
	wire sample_dram_cleanup_busy_w;
	wire sample_dram_stale_discard_w;
	wire sample_char_vrm_req_w;
	wire [15:0] sample_char_vrm_addr_w;
	wire sample_char_vrm_accept_w;
	wire sample_context_valid_w;
	wire sample_context_ready_w;
	wire sample_result_valid_w;
	wire sample_result_ready_w;
	wire sample_result_accept_w;
	wire [9:0] sample_result_tag_w;
	wire sample_result_last_w;
	wire sample_result_left_raw_nonzero_w;
	wire sample_result_right_raw_nonzero_w;
	wire [1:0] sample_result_left_mapped_w;
	wire [1:0] sample_result_right_mapped_w;
	wire sample_prime_complete_w;
	wire sample_quiescent_w;
	wire sample_cleanup_busy_w;
	wire sample_next_context_valid_w;
	wire sample_dram_pending_w;
	wire sample_vrm_pending_w;
	wire sample_dram_capture_valid_w;
	wire sample_vrm_capture_valid_w;
	wire sample_protocol_error_w;
	wire sample_unexpected_dram_response_w;
	wire sample_unexpected_vrm_response_w;
	wire sample_response_capture_overflow_w;
	wire sample_pending_owner_mismatch_w;
	wire sample_accept_without_request_w;
	wire sample_static_context_mismatch_w;
	wire sample_tag_sequence_error_w;

	wire packer_prepare_valid_w;
	wire packer_prepare_accept_w;
	wire packer_input_valid_w;
	wire packer_input_ready_w;
	wire packer_input_accept_w;
	wire packer_half_commit_valid_w;
	wire packer_half_commit_accept_w;
	wire packer_prepared_valid_w;
	wire packer_quiescent_w;
	wire packer_protocol_error_w;
	wire packer_prepare_alignment_error_w;
	wire packer_result_without_prepare_w;
	wire packer_ordinal_sequence_error_w;
	wire packer_ownership_mismatch_w;

	wire dram_mux_held_offer_w;
	wire dram_mux_read_pending_w;
	wire dram_mux_pending_internal_w;
	wire dram_mux_accept_error_w;
	wire dram_mux_retire_error_w;
	wire dram_mux_overlap_error_w;

	wire aggregate_resources_idle_w;
	wire command_cleanup_complete_w;
	wire scheduler_legal_complete_w = command_active_q &&
		scheduler_done_w && actual_downstream_idle_o &&
		!cleanup_interlock_q;

	// Admit only when routers, row-store half, and abort cleanup are idle.
	assign start_ready_o = scheduler_start_ready_w && !done_o &&
		!command_active_q && !cleanup_interlock_q &&
		aggregate_resources_idle_w;
	assign start_accept_o = start_valid_i && start_ready_o;

	assign done_o = done_pulse_q || scheduler_legal_complete_w;
	assign busy_o = (command_active_q && !scheduler_legal_complete_w) ||
		cleanup_interlock_q || scheduler_busy_w;
	// Accepted MP values do not cause a local fault.
	assign local_abort_active_o = 1'b0;
	assign nonzero_mp_fault_o = 1'b0;
	assign cleanup_interlock_o = cleanup_interlock_q;

	// Accept DDA setup near the end of the 80-CE row window, then prime pixel zero.
	assign row_context_accept_window_w =
		(scheduler_state_o == SCHED_STATE_ROW_SETUP) &&
		(scheduler_ticks_remaining_o <= 10'd3);

	wire initial_sample_window_w =
		(scheduler_state_o == SCHED_STATE_ROW_SETUP) &&
		(scheduler_ticks_remaining_o <= 10'd2) &&
		(row_pixel_ordinal_w == 10'd0);
	wire lookahead_sample_window_w =
		(scheduler_state_o == SCHED_STATE_PIXEL) &&
		(scheduler_ticks_remaining_o == 10'd4) &&
		!scheduler_pixel_last_in_row_w &&
		({1'b0, row_pixel_ordinal_w} ==
		 ({1'b0, scheduler_pixel_ordinal_o} + 11'd1));
	wire row_scheduler_tags_match_w =
		(row_pixel_world_w == scheduler_pixel_world_w) &&
		(row_pixel_strip_w == scheduler_pixel_strip_w) &&
		(row_pixel_screen_y_w == scheduler_pixel_screen_y_w) &&
		(row_pixel_local_y_w == scheduler_pixel_local_y_w);
	wire sample_window_open_w =
		initial_sample_window_w || lookahead_sample_window_w;
	assign sample_context_valid_w = row_pixel_valid_w &&
		row_scheduler_tags_match_w && sample_window_open_w;
	assign row_pixel_ready_w = sample_context_ready_w &&
		row_scheduler_tags_match_w && sample_window_open_w;

	// Begin row-store prepare at state zero and hold it until accepted.
	assign packer_prepare_valid_w = scheduler_pixel_valid_w &&
		((scheduler_pixel_group_slot_w == 3'd0) ||
		 (scheduler_pixel_group_slot_w == 3'd4)) &&
		(sample_state_o == SAMPLE_STAGE0);
	// Do not start CELL or character reads before row-store prepare accepts.
	wire sample_stage0_transport_release_w =
		(sample_state_o != SAMPLE_STAGE0) || packer_prepared_valid_w ||
		packer_prepare_accept_w;
	assign char_vrm_req_o = sample_char_vrm_req_w &&
		sample_stage0_transport_release_w;
	assign char_vrm_addr_o = sample_char_vrm_addr_w;
	assign sample_char_vrm_accept_w = char_vrm_accept_i &&
		sample_stage0_transport_release_w;

	wire result_tag_match_w = scheduler_pixel_valid_w &&
		(sample_result_tag_w == scheduler_pixel_ordinal_o) &&
		(sample_result_last_w == scheduler_pixel_last_in_row_w);
	assign packer_input_valid_w = sample_result_valid_w &&
		result_tag_match_w;
	assign sample_result_ready_w = packer_input_ready_w &&
		result_tag_match_w;
	// The pixel retires exactly when the packer takes the sample.
	assign scheduler_pixel_ready_w = packer_input_valid_w &&
		packer_input_ready_w;
	assign scheduler_pixel_accept_o = ce_i &&
		scheduler_pixel_valid_w && scheduler_pixel_ready_w;

	// Final-row lookahead requires the matching sample and store commit to accept.
	wire final_transition_accept_w = scheduler_pixel_accept_o &&
		sample_result_accept_w && packer_input_accept_w &&
		packer_half_commit_accept_w && scheduler_pixel_last_in_strip_w &&
		sample_result_last_w;
	wire final_other_owners_idle_w =
		!row_pipeline_cleanup_busy_w && !row_param_read_pending_w &&
		!sample_cleanup_busy_w &&
		!sample_next_context_valid_w && !sample_dram_pending_w &&
		!sample_dram_capture_valid_w &&
		!dram_mux_held_offer_w && !dram_mux_read_pending_w &&
		!dram_cleanup_busy_i && !char_vrm_cleanup_busy_i;
	assign final_will_be_idle_o = final_transition_accept_w &&
		final_other_owners_idle_w && sample_vrm_pending_w &&
		(sample_result_valid_w || sample_vrm_capture_valid_w) &&
		packer_half_commit_valid_w && affine_commit_ready_i;

	assign actual_downstream_idle_o = row_pipeline_downstream_idle_w &&
		!row_pipeline_cleanup_busy_w && sample_quiescent_w &&
		packer_quiescent_w && affine_store_quiescent_i &&
		!dram_mux_held_offer_w && !dram_mux_read_pending_w &&
		!dram_cleanup_busy_i && !char_vrm_cleanup_busy_i;
	assign scheduler_downstream_idle_w = actual_downstream_idle_o ||
		final_will_be_idle_o;
	assign aggregate_resources_idle_w = actual_downstream_idle_o &&
		!row_pipeline_busy_w;
	// Clear cleanup while abort stays high once all registered owners drain.
	assign command_cleanup_complete_w = aggregate_resources_idle_w &&
		!scheduler_busy_w;

	assign row_store_abort_o = abort_i;
	assign char_vrm_abort_o = abort_i;

	assign sample_prime_complete_o = sample_prime_complete_w;
	assign sample_result_accept_o = sample_result_accept_w;
	assign packer_prepare_accept_o = packer_prepare_accept_w;
	assign packer_commit_accept_o = packer_half_commit_accept_w;
	assign dram_mux_held_offer_o = dram_mux_held_offer_w;
	assign dram_mux_read_pending_o = dram_mux_read_pending_w;
	assign param_dram_selected_o = param_dram_req_w ||
		(dram_mux_read_pending_w && dram_mux_pending_internal_w);

	assign protocol_error_o = row_protocol_error_w ||
		sample_protocol_error_w || packer_protocol_error_w ||
		dram_mux_accept_error_w || dram_mux_retire_error_w ||
		dram_mux_overlap_error_w ||
		(sample_result_valid_w && !result_tag_match_w);

	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_affine_scheduler #(
		.COMPOSED_TIMING_CREDIT_ENABLE(COMPOSED_TIMING_CREDIT_ENABLE)
	) u_scheduler (
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		// Start the child only for a legal accepted command.
		.start_valid_i(start_accept_o && admission_legal_w),
		.start_ready_o(scheduler_start_ready_w),
		.world_i(world_i),
		.strip_i(strip_i),
		.first_visit_i(first_visit_i),
		.gy_i(gy_i),
		.semantic_width_i(semantic_width_i),
		.semantic_height_i(semantic_height_i),
		.busy_o(scheduler_busy_w),
		.done_o(scheduler_done_w),
		.aborted_o(),
		.row_start_valid_o(scheduler_row_start_valid_w),
		.row_start_ready_i(scheduler_row_start_ready_w),
		.row_start_world_o(scheduler_row_world_w),
		.row_start_strip_o(scheduler_row_strip_w),
		.row_start_first_in_strip_o(),
		.row_start_screen_y_o(scheduler_row_screen_y_w),
		.row_start_local_y_o(scheduler_row_local_y_w),
		.row_context_valid_i(sample_prime_complete_w &&
			scheduler_row_context_ready_w),
		.row_context_ready_o(scheduler_row_context_ready_w),
		.pixel_valid_o(scheduler_pixel_valid_w),
		.pixel_ready_i(scheduler_pixel_ready_w),
		.pixel_world_o(scheduler_pixel_world_w),
		.pixel_strip_o(scheduler_pixel_strip_w),
		.pixel_screen_y_o(scheduler_pixel_screen_y_w),
		.pixel_local_y_o(scheduler_pixel_local_y_w),
		.pixel_ordinal_o(scheduler_pixel_ordinal_o),
		.pixel_group_start_o(scheduler_pixel_group_start_w),
		.pixel_group_slot_o(scheduler_pixel_group_slot_w),
		.pixel_last_in_group_o(),
		.pixel_last_in_row_o(scheduler_pixel_last_in_row_w),
		.pixel_last_in_strip_o(scheduler_pixel_last_in_strip_w),
		.downstream_idle_i(scheduler_downstream_idle_w),
		.state_o(scheduler_state_o),
		.state_ticks_remaining_o(scheduler_ticks_remaining_o),
		.diag_elapsed_ticks_o(scheduler_elapsed_ticks_o),
		.diag_fixed_ticks_o(),
		.diag_strip_ticks_o(),
		.diag_row_setup_ticks_o(scheduler_row_setup_ticks_o),
		.diag_pixel_ticks_o(scheduler_pixel_ticks_o),
		.diag_stall_ticks_o(scheduler_stall_ticks_o),
		.diag_row_start_accept_count_o(scheduler_row_start_count_o),
		.diag_row_context_accept_count_o(scheduler_row_context_count_o),
		.diag_pixel_accept_count_o(scheduler_pixel_count_o),
		.diag_rows_in_strip_o(),
		.diag_bottom_reserve_o(),
		.invalid_height_o(),
		.undocumented_width_o(),
		.invalid_strip_o(),
		.context_before_row_start_o()
	);

	vip_xp_affine_row_pipeline u_row_pipeline
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.parallax_scale_i(parallax_scale_i),
		.row_valid_i(scheduler_row_start_valid_w),
		.row_ready_o(scheduler_row_start_ready_w),
		.row_world_i(scheduler_row_world_w),
		.row_strip_i(scheduler_row_strip_w),
		.row_screen_y_i(scheduler_row_screen_y_w),
		.row_local_y_i(scheduler_row_local_y_w),
		.param_base_i(param_base_q),
		.semantic_width_i(semantic_width_q),
		.param_dram_req_o(param_dram_req_w),
		.param_dram_addr_o(param_dram_addr_w),
		.param_dram_accept_i(param_dram_accept_w),
		.param_dram_resp_valid_i(param_dram_resp_valid_w),
		.param_dram_resp_data_i(param_dram_resp_data_w),
		.param_dram_cleanup_busy_i(param_dram_cleanup_busy_w),
		.param_dram_stale_discard_i(param_dram_stale_discard_w),
		.row_context_valid_o(row_context_valid_w),
		.row_context_ready_i(row_context_accept_window_w &&
			row_context_valid_w),
		.pixel_valid_o(row_pixel_valid_w),
		.pixel_ready_i(row_pixel_ready_w),
		.pixel_retire_o(),
		.pixel_world_o(row_pixel_world_w),
		.pixel_strip_o(row_pixel_strip_w),
		.pixel_screen_y_o(row_pixel_screen_y_w),
		.pixel_local_y_o(row_pixel_local_y_w),
		.pixel_ordinal_o(row_pixel_ordinal_w),
		.pixel_last_o(row_pixel_last_w),
		.left_x_accumulator_o(),
		.left_y_accumulator_o(),
		.right_x_accumulator_o(),
		.right_y_accumulator_o(),
		.left_source_x_o(row_left_source_x_w),
		.left_source_y_o(row_left_source_y_w),
		.right_source_x_o(row_right_source_x_w),
		.right_source_y_o(row_right_source_y_w),
		.left_source_x_pixel_o(),
		.left_source_y_pixel_o(),
		.right_source_x_pixel_o(),
		.right_source_y_pixel_o(),
		.left_source_x_fraction_o(),
		.left_source_y_fraction_o(),
		.right_source_x_fraction_o(),
		.right_source_y_fraction_o(),
		.busy_o(row_pipeline_busy_w),
		.cleanup_busy_o(row_pipeline_cleanup_busy_w),
		.downstream_idle_o(row_pipeline_downstream_idle_w),
		.param_read_pending_o(row_param_read_pending_w),
		.dda_busy_o(),
		.dda_row_done_o(),
		.active_element_base_o(),
		.active_mx_o(),
		.active_mp_o(),
		.active_my_o(),
		.active_dx_o(),
		.active_dy_o(),
		.work_behavior_unresolved_o(),
		.unaligned_policy_blocked_o(),
		.nonzero_mp_policy_blocked_o(),
		.undocumented_width_blocked_o(),
		.unaligned_policy_seen_o(),
		.nonzero_mp_policy_seen_o(nonzero_mp_policy_seen_o),
		.undocumented_width_seen_o(),
		.current_coordinate_range_valid_o(),
		.coordinate_range_error_o(),
		.accumulator_overflow_error_o(),
		.protocol_error_o(row_protocol_error_w)
	);

	vip_xp_read_subclient_mux u_dram_subclient_mux
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.global_abort_i(abort_i),
		.external_abort_i(1'b0),
		.internal_req_i(param_dram_req_w),
		.internal_addr_i(param_dram_addr_w),
		.internal_accept_o(param_dram_accept_w),
		.internal_resp_valid_o(param_dram_resp_valid_w),
		.internal_resp_data_o(param_dram_resp_data_w),
		.internal_cleanup_busy_o(param_dram_cleanup_busy_w),
		.internal_stale_discarded_o(param_dram_stale_discard_w),
		.external_req_i(sample_dram_req_w &&
			sample_stage0_transport_release_w),
		.external_addr_i(sample_dram_addr_w),
		.external_accept_o(sample_dram_accept_w),
		.external_resp_valid_o(sample_dram_resp_valid_w),
		.external_resp_data_o(sample_dram_resp_data_w),
		.external_cleanup_busy_o(sample_dram_cleanup_busy_w),
		.external_stale_discarded_o(sample_dram_stale_discard_w),
		.aggregate_abort_o(dram_abort_o),
		.aggregate_req_o(dram_req_o),
		.aggregate_addr_o(dram_addr_o),
		.aggregate_accept_i(dram_accept_i),
		.aggregate_resp_valid_i(dram_resp_valid_i),
		.aggregate_resp_data_i(dram_resp_data_i),
		.aggregate_cleanup_busy_i(dram_cleanup_busy_i),
		.aggregate_stale_discarded_i(dram_stale_discard_i),
		.held_offer_o(dram_mux_held_offer_w),
		.held_owner_internal_o(),
		.read_pending_o(dram_mux_read_pending_w),
		.pending_owner_internal_o(dram_mux_pending_internal_w),
		.accept_without_offer_o(dram_mux_accept_error_w),
		.retire_without_pending_o(dram_mux_retire_error_w),
		.outstanding_overlap_o(dram_mux_overlap_error_w)
	);

	vip_xp_affine_sample_pipeline #(
		.GENERATION_WIDTH(GENERATION_WIDTH),
		.EXTERNAL_ADDRESS_SEAM(1)
	) u_sample_pipeline (
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.sample_valid_i(sample_context_valid_w),
		.sample_ready_o(sample_context_ready_w),
		.sample_accept_o(),
		.sample_tag_i(row_pixel_ordinal_w),
		.sample_last_i(row_pixel_last_w),
		.left_source_x_i(row_left_source_x_w),
		.left_source_y_i(row_left_source_y_w),
		.right_source_x_i(row_right_source_x_w),
		.right_source_y_i(row_right_source_y_w),
		.maps_wide_i(maps_wide_q),
		.maps_high_i(maps_high_q),
		.effective_map_columns_i(effective_map_columns_q),
		.bgmap_base_rounded_i(bgmap_base_rounded_q),
		.over_i(over_q),
		.overplane_i(overplane_q),
		.gplt_active_i(gplt_active_q),
		.address_source_x_o(address_source_x_o),
		.address_source_y_o(address_source_y_o),
		.address_maps_wide_o(address_maps_wide_o),
		.address_maps_high_o(address_maps_high_o),
		.address_effective_map_columns_o(
			address_effective_map_columns_o),
		.address_bgmap_base_rounded_o(
			address_bgmap_base_rounded_o),
		.address_over_o(address_over_o),
		.address_overplane_o(address_overplane_o),
		.address_cell_o(address_cell_o),
		.address_cell_source_row_o(address_cell_source_row_o),
		.addressed_dram_cell_addr_i(addressed_dram_cell_addr_i),
		.addressed_overplane_selected_i(
			addressed_overplane_selected_i),
		.addressed_strict_overplane_i(addressed_strict_overplane_i),
		.addressed_map_index_overflow_i(
			addressed_map_index_overflow_i),
		.addressed_vrm_character_row_addr_i(
			addressed_vrm_character_row_addr_i),
		.addressed_palette_i(addressed_palette_i),
		.addressed_hflip_i(addressed_hflip_i),
		.addressed_vflip_i(addressed_vflip_i),
		.decode_character_row_o(decode_character_row_o),
		.decode_palette_o(decode_palette_o),
		.decode_hflip_o(decode_hflip_o),
		.decode_source_x_index_o(decode_source_x_index_o),
		.decode_gplt_active_o(decode_gplt_active_o),
		.decoded_raw_pixel_i(decoded_raw_pixel_i),
		.decoded_raw_nonzero_i(decoded_raw_nonzero_i),
		.decoded_mapped_pixel_i(decoded_mapped_pixel_i),
		.dram_req_o(sample_dram_req_w),
		.dram_addr_o(sample_dram_addr_w),
		.dram_accept_i(sample_dram_accept_w),
		.dram_resp_valid_i(sample_dram_resp_valid_w),
		.dram_resp_data_i(sample_dram_resp_data_w),
		.dram_router_cleanup_busy_i(sample_dram_cleanup_busy_w),
		.dram_router_stale_discard_i(sample_dram_stale_discard_w),
		.vrm_req_o(sample_char_vrm_req_w),
		.vrm_addr_o(sample_char_vrm_addr_w),
		.vrm_accept_i(sample_char_vrm_accept_w),
		.vrm_resp_valid_i(char_vrm_resp_valid_i),
		.vrm_resp_data_i(char_vrm_resp_data_i),
		.vrm_router_cleanup_busy_i(char_vrm_cleanup_busy_i),
		.vrm_router_stale_discard_i(char_vrm_stale_discard_i),
		.result_valid_o(sample_result_valid_w),
		.result_ready_i(sample_result_ready_w),
		.result_accept_o(sample_result_accept_w),
		.result_tag_o(sample_result_tag_w),
		.result_last_o(sample_result_last_w),
		.result_left_cell_o(),
		.result_right_cell_o(),
		.result_left_character_row_o(),
		.result_right_character_row_o(),
		.result_left_palette_o(),
		.result_right_palette_o(),
		.result_left_hflip_o(),
		.result_right_hflip_o(),
		.result_left_vflip_o(),
		.result_right_vflip_o(),
		.result_left_overplane_selected_o(),
		.result_right_overplane_selected_o(),
		.result_left_raw_pixel_o(),
		.result_right_raw_pixel_o(),
		.result_left_raw_nonzero_o(sample_result_left_raw_nonzero_w),
		.result_right_raw_nonzero_o(sample_result_right_raw_nonzero_w),
		.result_left_mapped_pixel_o(sample_result_left_mapped_w),
		.result_right_mapped_pixel_o(sample_result_right_mapped_w),
		.prime_accept_o(),
		.prime_complete_o(sample_prime_complete_w),
		.pixel_window_active_o(),
		.state_o(sample_state_o),
		.busy_o(),
		.cleanup_busy_o(sample_cleanup_busy_w),
		.quiescent_o(sample_quiescent_w),
		.next_context_valid_o(sample_next_context_valid_w),
		.dram_read_pending_o(sample_dram_pending_w),
		.vrm_read_pending_o(sample_vrm_pending_w),
		.dram_response_capture_valid_o(sample_dram_capture_valid_w),
		.vrm_response_capture_valid_o(sample_vrm_capture_valid_w),
		.dram_request_owner_o(),
		.dram_pending_owner_o(),
		.vrm_request_owner_o(),
		.vrm_pending_owner_o(),
		.active_generation_o(),
		.dram_pending_generation_o(),
		.vrm_pending_generation_o(),
		.dram_stale_response_discarded_o(),
		.vrm_stale_response_discarded_o(),
		.unexpected_dram_response_o(sample_unexpected_dram_response_w),
		.unexpected_vrm_response_o(sample_unexpected_vrm_response_w),
		.response_capture_overflow_o(sample_response_capture_overflow_w),
		.pending_owner_mismatch_o(sample_pending_owner_mismatch_w),
		.accept_without_request_o(sample_accept_without_request_w),
		.static_context_mismatch_o(sample_static_context_mismatch_w),
		.sample_tag_sequence_error_o(sample_tag_sequence_error_w),
		.strict_overplane_seen_o(sample_strict_overplane_seen_o),
		.map_index_overflow_seen_o(sample_map_index_overflow_seen_o)
	);

	// Combine sample-pipeline errors into one flag.
	assign sample_protocol_error_w =
		sample_unexpected_dram_response_w ||
		sample_unexpected_vrm_response_w ||
		sample_response_capture_overflow_w ||
		sample_pending_owner_mismatch_w ||
		sample_accept_without_request_w ||
		sample_static_context_mismatch_w ||
		sample_tag_sequence_error_w;

	vip_xp_affine_pixel_packer u_pixel_packer
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.prepare_valid_i(packer_prepare_valid_w),
		.prepare_ready_o(),
		.prepare_accept_o(packer_prepare_accept_w),
		.prepare_world_i(scheduler_pixel_world_w),
		.prepare_strip_i(scheduler_pixel_strip_w),
		.prepare_screen_y_i(scheduler_pixel_screen_y_w),
		.prepare_local_y_i(scheduler_pixel_local_y_w),
		.prepare_group_start_i(scheduler_pixel_group_start_w),
		.prepare_half_start_i(scheduler_pixel_ordinal_o),
		.prepare_gx_i(gx_q),
		.prepare_gp_i(gp_q),
		.prepare_left_on_i(left_on_q),
		.prepare_right_on_i(right_on_q),
		.half_context_valid_o(affine_prepare_valid_o),
		.half_context_ready_i(affine_prepare_ready_i),
		.half_context_accept_o(affine_prepare_accept_o),
		.half_context_world_o(),
		.half_context_strip_o(),
		.half_context_screen_y_o(),
		.half_context_local_y_o(),
		.half_context_group_start_o(),
		.half_context_start_o(),
		.half_context_second_o(),
		.half_context_row_o(affine_prepare_row_o),
		.half_context_left_base_x_o(affine_prepare_left_base_x_o),
		.half_context_left_enable_o(affine_prepare_left_enable_o),
		.half_context_right_base_x_o(affine_prepare_right_base_x_o),
		.half_context_right_enable_o(affine_prepare_right_enable_o),
		.input_valid_i(packer_input_valid_w),
		.input_ready_o(packer_input_ready_w),
		.input_accept_o(packer_input_accept_w),
		.input_world_i(scheduler_pixel_world_w),
		.input_strip_i(scheduler_pixel_strip_w),
		.input_screen_y_i(scheduler_pixel_screen_y_w),
		.input_local_y_i(scheduler_pixel_local_y_w),
		.input_ordinal_i(scheduler_pixel_ordinal_o),
		.input_group_start_i(scheduler_pixel_group_start_w),
		.input_last_i(sample_result_last_w),
		.input_left_raw_nonzero_i(sample_result_left_raw_nonzero_w),
		.input_left_mapped_i(sample_result_left_mapped_w),
		.input_right_raw_nonzero_i(sample_result_right_raw_nonzero_w),
		.input_right_mapped_i(sample_result_right_mapped_w),
		.half_commit_valid_o(packer_half_commit_valid_w),
		.half_commit_ready_i(affine_commit_ready_i),
		.half_commit_accept_o(packer_half_commit_accept_w),
		.half_commit_world_o(),
		.half_commit_strip_o(),
		.half_commit_screen_y_o(),
		.half_commit_local_y_o(),
		.half_commit_group_start_o(),
		.half_commit_start_o(),
		.half_commit_second_o(),
		.half_commit_last_o(),
		.half_commit_row_o(),
		.half_commit_left_enable_o(),
		.half_commit_left_active_o(affine_commit_left_active_o),
		.half_commit_left_opaque_o(affine_commit_left_opaque_o),
		.half_commit_left_values_o(affine_commit_left_values_o),
		.half_commit_right_enable_o(),
		.half_commit_right_active_o(affine_commit_right_active_o),
		.half_commit_right_opaque_o(affine_commit_right_opaque_o),
		.half_commit_right_values_o(affine_commit_right_values_o),
		.prepared_valid_o(packer_prepared_valid_w),
		.next_slot_o(),
		.busy_o(),
		.quiescent_o(packer_quiescent_w),
		.diag_prepare_accept_count_o(),
		.diag_input_accept_count_o(),
		.diag_commit_accept_count_o(),
		.prepare_alignment_error_o(packer_prepare_alignment_error_w),
		.result_without_prepare_o(packer_result_without_prepare_w),
		.ordinal_sequence_error_o(packer_ordinal_sequence_error_w),
		.ownership_mismatch_o(packer_ownership_mismatch_w)
	);

	assign affine_commit_valid_o = packer_half_commit_valid_w;
	assign affine_commit_accept_o = packer_half_commit_accept_w;
	assign packer_protocol_error_w =
		packer_prepare_alignment_error_w ||
		packer_result_without_prepare_w ||
		packer_ordinal_sequence_error_w ||
		packer_ownership_mismatch_w;
	/* verilator lint_on PINCONNECTEMPTY */

	// Keep abort cleanup until accepted memory owners retire.
	always @(posedge clk_i) begin
		if (reset_i) begin
			command_active_q <= 1'b0;
			cleanup_interlock_q <= 1'b0;
			param_base_q <= 16'd0;
			gx_q <= 16'sd0;
			gp_q <= 16'sd0;
			left_on_q <= 1'b0;
			right_on_q <= 1'b0;
			maps_wide_q <= 4'd1;
			maps_high_q <= 4'd1;
			effective_map_columns_q <= 4'd1;
			bgmap_base_rounded_q <= 4'd0;
			over_q <= 1'b0;
			overplane_q <= 16'd0;
			gplt_active_q <= 32'd0;
			semantic_width_q <= 11'd0;
			done_pulse_q <= 1'b0;
			reject_pulse_o <= 1'b0;
			abort_done_pulse_o <= 1'b0;
			invalid_width_reject_o <= 1'b0;
			unaligned_param_reject_o <= 1'b0;
			strict_policy_reject_o <= 1'b0;
			raw_abort_seen_o <= 1'b0;
		end else begin
			if (abort_i && (command_active_q || scheduler_busy_w ||
				cleanup_interlock_q)) begin
				cleanup_interlock_q <= 1'b1;
				raw_abort_seen_o <= 1'b1;
			end

			if (ce_i) begin
				done_pulse_q <= 1'b0;
				reject_pulse_o <= 1'b0;
				abort_done_pulse_o <= 1'b0;

				if (start_accept_o) begin
					invalid_width_reject_o <= !known_width_legal_w;
					unaligned_param_reject_o <=
						!known_alignment_legal_w;
					strict_policy_reject_o <=
						strict_policy_violation_i;
					raw_abort_seen_o <= 1'b0;
					if (admission_legal_w) begin
						command_active_q <= 1'b1;
						param_base_q <= param_base_i;
						gx_q <= gx_i;
						gp_q <= gp_i;
						left_on_q <= left_on_i;
						right_on_q <= right_on_i;
						maps_wide_q <= maps_wide_i;
						maps_high_q <= maps_high_i;
						effective_map_columns_q <=
							effective_map_columns_i;
						bgmap_base_rounded_q <=
							bgmap_base_rounded_i;
						over_q <= over_i;
						overplane_q <= overplane_i;
						gplt_active_q <= gplt_active_i;
						semantic_width_q <= semantic_width_i;
					end else begin
						reject_pulse_o <= 1'b1;
						done_pulse_q <= 1'b1;
					end
				end

				if (scheduler_done_w && command_active_q &&
					!cleanup_interlock_q) begin
					command_active_q <= 1'b0;
				end

				// Retire active-row work on the scheduler's final edge.
				if (final_will_be_idle_o && command_active_q &&
					!cleanup_interlock_q) begin
					command_active_q <= 1'b0;
					done_pulse_q <= 1'b1;
				end

				if (cleanup_interlock_q &&
					command_cleanup_complete_w) begin
					cleanup_interlock_q <= 1'b0;
					command_active_q <= 1'b0;
					done_pulse_q <= 1'b1;
					abort_done_pulse_o <= 1'b1;
				end
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Affine-world strip scheduler.
//
// One command visits one strip. The shipped core uses composed timing
// (COMPOSED_TIMING_CREDIT_ENABLE = 1): 23 command CE per visit, plus 21 CE
// first and nine CE later. Each row setup costs 80 CE and each output pixel
// costs four CE. Late work extends its interval.
//
// The non-composed path (parameter = 0, bench-only) charges the full 908 CE
// fixed cost on the first visit instead.
//
// Vertical work is the exact screen intersection. Width is W+1 from 1 to 1024
// and always starts at configured ordinal zero.
//
// Subtract the measured 12-CE bottom adjustment from the first visit on any
// strip whose world reaches the bottom of the screen.

module vip_xp_affine_scheduler
#(
	parameter integer COMPOSED_TIMING_CREDIT_ENABLE = 0
)
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	input  wire                 start_valid_i,
	output wire                 start_ready_o,
	input  wire [4:0]           world_i,
	input  wire [4:0]           strip_i,
	input  wire                 first_visit_i,
	input  wire signed [15:0]   gy_i,
	input  wire [10:0]          semantic_width_i,
	input  wire signed [16:0]   semantic_height_i,

	output wire                 busy_o,
	output reg                  done_o,
	output reg                  aborted_o,

	// Start parameter and DDA setup for the real row; setup still lasts at least 80 CE.
	output wire                 row_start_valid_o,
	input  wire                 row_start_ready_i,
	output wire [4:0]           row_start_world_o,
	output wire [4:0]           row_start_strip_o,
	output wire                 row_start_first_in_strip_o,
	output wire [8:0]           row_start_screen_y_o,
	output wire [15:0]          row_start_local_y_o,
	input  wire                 row_context_valid_i,
	output wire                 row_context_ready_o,

	// One held request per output pixel, with a four-CE minimum.
	output wire                 pixel_valid_o,
	input  wire                 pixel_ready_i,
	output wire [4:0]           pixel_world_o,
	output wire [4:0]           pixel_strip_o,
	output wire [8:0]           pixel_screen_y_o,
	output wire [15:0]          pixel_local_y_o,
	output wire [9:0]           pixel_ordinal_o,
	output wire [9:0]           pixel_group_start_o,
	output wire [2:0]           pixel_group_slot_o,
	output wire                 pixel_last_in_group_o,
	output wire                 pixel_last_in_row_o,
	output wire                 pixel_last_in_strip_o,

	// Finish only after parameter, sample, packer, and row-store work drain.
	input  wire                 downstream_idle_i,

	output wire [2:0]           state_o,
	output wire [9:0]           state_ticks_remaining_o,
`ifndef SYNTHESIS
	output reg  [31:0]          diag_elapsed_ticks_o,
	output reg  [15:0]          diag_fixed_ticks_o,
	output reg  [7:0]           diag_strip_ticks_o,
	output reg  [31:0]          diag_row_setup_ticks_o,
	output reg  [31:0]          diag_pixel_ticks_o,
	output reg  [31:0]          diag_stall_ticks_o,
	output reg  [15:0]          diag_row_start_accept_count_o,
	output reg  [15:0]          diag_row_context_accept_count_o,
	output reg  [31:0]          diag_pixel_accept_count_o,
	output reg  [3:0]           diag_rows_in_strip_o,
	output reg  [3:0]           diag_bottom_reserve_o,
	output reg                  invalid_height_o,
	output reg                  undocumented_width_o,
	output reg                  invalid_strip_o,
	output reg                  context_before_row_start_o
`else
	output wire [31:0]          diag_elapsed_ticks_o,
	output wire [15:0]          diag_fixed_ticks_o,
	output wire [7:0]           diag_strip_ticks_o,
	output wire [31:0]          diag_row_setup_ticks_o,
	output wire [31:0]          diag_pixel_ticks_o,
	output wire [31:0]          diag_stall_ticks_o,
	output wire [15:0]          diag_row_start_accept_count_o,
	output wire [15:0]          diag_row_context_accept_count_o,
	output wire [31:0]          diag_pixel_accept_count_o,
	output wire [3:0]           diag_rows_in_strip_o,
	output wire [3:0]           diag_bottom_reserve_o,
	output wire                 invalid_height_o,
	output wire                 undocumented_width_o,
	output wire                 invalid_strip_o,
	output wire                 context_before_row_start_o
`endif
);

	localparam [2:0]
		STATE_IDLE      = 3'd0,
		STATE_FIXED     = 3'd1,
		STATE_STRIP     = 3'd2,
		STATE_ROW_SETUP = 3'd3,
		STATE_PIXEL     = 3'd4,
		STATE_DRAIN     = 3'd5;

	localparam [9:0]
		FIXED_TICKS                 = 10'd908,
		FIXED_WITH_BOTTOM_RESERVE   = 10'd896,
		ROW_SETUP_TICKS             = 10'd80,
		PIXEL_TICKS                 = 10'd4,
		COMPOSED_BASE_TICKS         = 10'd9,
		COMPOSED_FIRST_REMAINDER    = 10'd12,
		COMPOSED_BOTTOM_ADJUST      = 10'd12;

	reg [2:0] state_q;
	reg [9:0] state_ticks_remaining_q;
	reg [4:0] world_q;
	reg [4:0] strip_q;
	reg signed [15:0] gy_q;
	reg [10:0] semantic_width_q;
	reg [8:0] row_screen_start_q;
	reg [3:0] row_count_q;
	reg [3:0] row_ordinal_q;
	reg [9:0] pixel_ordinal_q;
	reg [5:0] strip_cost_q;
	reg row_start_accepted_q;
	reg row_context_accepted_q;
	reg pixel_accepted_q;
	reg abort_cleanup_pending_q;

	reg [9:0] fixed_cost_t;
	reg [5:0] strip_cost_t;
	reg [3:0] rows_t;
	reg [8:0] row_screen_start_t;
	reg signed [17:0] gy_ext_t;
	reg signed [17:0] height_ext_t;
	reg signed [17:0] end_y_t;
	reg signed [17:0] strip_y_t;
	reg signed [17:0] strip_end_t;
	reg signed [17:0] row_start_t;
	reg signed [17:0] row_end_t;
	reg signed [17:0] row_count_wide_t;
	reg height_positive_t;
	reg reaches_bottom_t;
	reg contains_top_t;

	/* verilator lint_off UNUSEDSIGNAL */
	wire [9:0] current_screen_y_extended_w =
		{1'b0, row_screen_start_q} + {6'd0, row_ordinal_q};
	/* verilator lint_on UNUSEDSIGNAL */
	wire [8:0] current_screen_y_w =
		current_screen_y_extended_w[8:0];
	/* verilator lint_off UNUSEDSIGNAL */
	wire signed [16:0] current_local_y_extended_w =
		$signed({8'd0, current_screen_y_w}) -
		$signed({gy_q[15], gy_q});
	/* verilator lint_on UNUSEDSIGNAL */
	wire [15:0] current_local_y_w =
		current_local_y_extended_w[15:0];

	wire row_start_fire_w = ce_i && row_start_valid_o &&
		row_start_ready_i;
	wire row_context_fire_w = ce_i && row_context_valid_i &&
		row_context_ready_o;
	wire pixel_fire_w = ce_i && pixel_valid_o && pixel_ready_i;
	wire row_start_complete_w = row_start_accepted_q ||
		row_start_fire_w;
	wire row_context_complete_w = row_context_accepted_q ||
		row_context_fire_w;
	wire pixel_complete_w = pixel_accepted_q || pixel_fire_w;
	wire [10:0] next_pixel_ordinal_w =
		{1'b0, pixel_ordinal_q} + 11'd1;
	wire pixel_is_last_w = next_pixel_ordinal_w >= semantic_width_q;
	wire row_is_last_w = ({1'b0, row_ordinal_q} + 5'd1) >=
		{1'b0, row_count_q};

	// Abort drops offers and blocks restart until accepted downstream work drains.
	assign start_ready_o = ce_i && !reset_i && !abort_i && !done_o &&
		!abort_cleanup_pending_q && (state_q == STATE_IDLE);
	// Keep busy high after abort until downstream ownership drains.
	assign busy_o = (state_q != STATE_IDLE) || abort_cleanup_pending_q;
	assign state_o = state_q;
	assign state_ticks_remaining_o = state_ticks_remaining_q;

	assign row_start_valid_o = !reset_i && !abort_i &&
		(state_q == STATE_ROW_SETUP) && !row_start_accepted_q;
	assign row_start_world_o = world_q;
	assign row_start_strip_o = strip_q;
	assign row_start_first_in_strip_o = row_ordinal_q == 4'd0;
	assign row_start_screen_y_o = current_screen_y_w;
	assign row_start_local_y_o = current_local_y_w;
	assign row_context_ready_o = ce_i && !reset_i && !abort_i &&
		(state_q == STATE_ROW_SETUP) && !row_context_accepted_q &&
		(row_start_accepted_q || row_start_fire_w);

	assign pixel_valid_o = !reset_i && !abort_i &&
		(state_q == STATE_PIXEL) && !pixel_accepted_q;
	assign pixel_world_o = world_q;
	assign pixel_strip_o = strip_q;
	assign pixel_screen_y_o = current_screen_y_w;
	assign pixel_local_y_o = current_local_y_w;
	assign pixel_ordinal_o = pixel_ordinal_q;
	assign pixel_group_start_o = {pixel_ordinal_q[9:3], 3'b000};
	assign pixel_group_slot_o = pixel_ordinal_q[2:0];
	assign pixel_last_in_group_o = (pixel_ordinal_q[2:0] == 3'd7) ||
		pixel_is_last_w;
	assign pixel_last_in_row_o = pixel_is_last_w;
	assign pixel_last_in_strip_o = pixel_is_last_w && row_is_last_w;

`ifdef SYNTHESIS
	assign diag_elapsed_ticks_o = 32'd0;
	assign diag_fixed_ticks_o = 16'd0;
	assign diag_strip_ticks_o = 8'd0;
	assign diag_row_setup_ticks_o = 32'd0;
	assign diag_pixel_ticks_o = 32'd0;
	assign diag_stall_ticks_o = 32'd0;
	assign diag_row_start_accept_count_o = 16'd0;
	assign diag_row_context_accept_count_o = 16'd0;
	assign diag_pixel_accept_count_o = 32'd0;
	assign diag_rows_in_strip_o = 4'd0;
	assign diag_bottom_reserve_o = 4'd0;
	assign invalid_height_o = 1'b0;
	assign undocumented_width_o = 1'b0;
	assign invalid_strip_o = 1'b0;
	assign context_before_row_start_o = 1'b0;
`endif

	// First-visit fixed time includes the bottom-strip adjustment.
	always @* begin
		gy_ext_t = {{2{gy_i[15]}}, gy_i};
		height_ext_t = {{1{semantic_height_i[16]}}, semantic_height_i};
		end_y_t = gy_ext_t + height_ext_t;
		strip_y_t = $signed({10'd0, strip_i, 3'b000});
		strip_end_t = strip_y_t + 18'sd8;
		height_positive_t = !semantic_height_i[16] &&
			(semantic_height_i != 17'sd0);
		reaches_bottom_t = height_positive_t && (end_y_t > 18'sd216);

		fixed_cost_t = 10'd0;
		if (COMPOSED_TIMING_CREDIT_ENABLE != 0) begin
			if (strip_i < 5'd28) begin
				fixed_cost_t = COMPOSED_BASE_TICKS;
				if (first_visit_i) begin
					fixed_cost_t = fixed_cost_t +
						COMPOSED_FIRST_REMAINDER;
					if (reaches_bottom_t) begin
						fixed_cost_t = fixed_cost_t -
							COMPOSED_BOTTOM_ADJUST;
					end
				end
			end
		end else if (first_visit_i) begin
			fixed_cost_t = reaches_bottom_t ?
				FIXED_WITH_BOTTOM_RESERVE : FIXED_TICKS;
		end

		strip_cost_t = 6'd0;
		rows_t = 4'd0;
		row_screen_start_t = strip_y_t[8:0];
		row_start_t = strip_y_t;
		row_end_t = strip_y_t;
		row_count_wide_t = 18'sd0;
		contains_top_t = 1'b0;

		if ((strip_i < 5'd28) && height_positive_t &&
			(end_y_t > strip_y_t)) begin
			if (gy_ext_t >= strip_end_t) begin
				strip_cost_t = (strip_i == 5'd27) ? 6'd7 : 6'd5;
			end else begin
				contains_top_t = gy_ext_t >= strip_y_t;
				strip_cost_t = contains_top_t ? 6'd13 : 6'd14;
				if ((strip_i == 5'd0) && !contains_top_t) begin
					strip_cost_t = strip_cost_t + 6'd5;
				end
				if ((strip_i == 5'd27) && (end_y_t > 18'sd224)) begin
					strip_cost_t = strip_cost_t + 6'd3;
				end

				row_start_t = contains_top_t ? gy_ext_t : strip_y_t;
				row_end_t = (end_y_t < strip_end_t) ?
					end_y_t : strip_end_t;
				row_count_wide_t = row_end_t - row_start_t;
				if (row_count_wide_t > 18'sd8) begin
					rows_t = 4'd8;
				end else if (row_count_wide_t > 18'sd0) begin
					rows_t = row_count_wide_t[3:0];
				end
				row_screen_start_t = row_start_t[8:0];
			end
		end
	end

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			state_ticks_remaining_q <= 10'd0;
			world_q <= 5'd0;
			strip_q <= 5'd0;
			gy_q <= 16'sd0;
			semantic_width_q <= 11'd0;
			row_screen_start_q <= 9'd0;
			row_count_q <= 4'd0;
			row_ordinal_q <= 4'd0;
			pixel_ordinal_q <= 10'd0;
			strip_cost_q <= 6'd0;
			row_start_accepted_q <= 1'b0;
			row_context_accepted_q <= 1'b0;
			pixel_accepted_q <= 1'b0;
			abort_cleanup_pending_q <= 1'b0;
			done_o <= 1'b0;
			aborted_o <= 1'b0;
`ifndef SYNTHESIS
			diag_elapsed_ticks_o <= 32'd0;
			diag_fixed_ticks_o <= 16'd0;
			diag_strip_ticks_o <= 8'd0;
			diag_row_setup_ticks_o <= 32'd0;
			diag_pixel_ticks_o <= 32'd0;
			diag_stall_ticks_o <= 32'd0;
			diag_row_start_accept_count_o <= 16'd0;
			diag_row_context_accept_count_o <= 16'd0;
			diag_pixel_accept_count_o <= 32'd0;
			diag_rows_in_strip_o <= 4'd0;
			diag_bottom_reserve_o <= 4'd0;
			invalid_height_o <= 1'b0;
			undocumented_width_o <= 1'b0;
			invalid_strip_o <= 1'b0;
			context_before_row_start_o <= 1'b0;
`endif
		end else if (abort_i) begin
			state_q <= STATE_IDLE;
			state_ticks_remaining_q <= 10'd0;
			row_start_accepted_q <= 1'b0;
			row_context_accepted_q <= 1'b0;
			pixel_accepted_q <= 1'b0;
			// Do not create Affine cleanup for work owned by another renderer.
			abort_cleanup_pending_q <= !downstream_idle_i &&
				(abort_cleanup_pending_q || (state_q != STATE_IDLE));
			pixel_ordinal_q <= 10'd0;
			done_o <= 1'b0;
			aborted_o <= 1'b1;
		end else if (ce_i) begin
			done_o <= 1'b0;
			if (abort_cleanup_pending_q && downstream_idle_i)
				abort_cleanup_pending_q <= 1'b0;
`ifndef SYNTHESIS
			if ((state_q == STATE_ROW_SETUP) && row_context_valid_i &&
				!row_start_accepted_q && !row_start_fire_w) begin
				context_before_row_start_o <= 1'b1;
			end
`endif
			case (state_q)
				STATE_IDLE: begin
					state_ticks_remaining_q <= 10'd0;
					row_start_accepted_q <= 1'b0;
					row_context_accepted_q <= 1'b0;
					pixel_accepted_q <= 1'b0;
					if (start_valid_i && start_ready_o) begin
						world_q <= world_i;
						strip_q <= strip_i;
						gy_q <= gy_i;
						semantic_width_q <= semantic_width_i;
						row_screen_start_q <= row_screen_start_t;
						row_count_q <= rows_t;
						row_ordinal_q <= 4'd0;
						pixel_ordinal_q <= 10'd0;
						strip_cost_q <= strip_cost_t;
						aborted_o <= 1'b0;
`ifndef SYNTHESIS
						diag_elapsed_ticks_o <= 32'd0;
						diag_fixed_ticks_o <= 16'd0;
						diag_strip_ticks_o <= 8'd0;
						diag_row_setup_ticks_o <= 32'd0;
						diag_pixel_ticks_o <= 32'd0;
						diag_stall_ticks_o <= 32'd0;
						diag_row_start_accept_count_o <= 16'd0;
						diag_row_context_accept_count_o <= 16'd0;
						diag_pixel_accept_count_o <= 32'd0;
						diag_rows_in_strip_o <= rows_t;
						diag_bottom_reserve_o <=
							(first_visit_i && reaches_bottom_t) ? 4'd12 : 4'd0;
						invalid_height_o <= !height_positive_t;
						undocumented_width_o <=
							(semantic_width_i == 11'd0) ||
							(semantic_width_i > 11'd1024);
						invalid_strip_o <= strip_i >= 5'd28;
						context_before_row_start_o <= 1'b0;
`endif
						if (fixed_cost_t != 10'd0) begin
							state_q <= STATE_FIXED;
							state_ticks_remaining_q <= fixed_cost_t;
						end else if (strip_cost_t != 6'd0) begin
							state_q <= STATE_STRIP;
							state_ticks_remaining_q <= {4'd0, strip_cost_t};
						end else begin
							state_q <= STATE_IDLE;
							done_o <= 1'b1;
						end
					end
				end

				STATE_FIXED: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_fixed_ticks_o <= diag_fixed_ticks_o + 16'd1;
`endif
					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (strip_cost_q != 6'd0) begin
						state_q <= STATE_STRIP;
						state_ticks_remaining_q <= {4'd0, strip_cost_q};
					end else begin
						state_q <= STATE_IDLE;
						state_ticks_remaining_q <= 10'd0;
						done_o <= 1'b1;
					end
				end

				STATE_STRIP: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_strip_ticks_o <= diag_strip_ticks_o + 8'd1;
`endif
					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (row_count_q != 4'd0) begin
						state_q <= STATE_ROW_SETUP;
						state_ticks_remaining_q <= ROW_SETUP_TICKS;
						row_start_accepted_q <= 1'b0;
						row_context_accepted_q <= 1'b0;
					end else begin
						state_q <= STATE_IDLE;
						state_ticks_remaining_q <= 10'd0;
						done_o <= 1'b1;
					end
				end

				STATE_ROW_SETUP: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_row_setup_ticks_o <=
						diag_row_setup_ticks_o + 32'd1;
					if ((state_ticks_remaining_q == 10'd1) &&
						!(row_start_complete_w && row_context_complete_w)) begin
						diag_stall_ticks_o <= diag_stall_ticks_o + 32'd1;
					end
`endif
					if (row_start_fire_w) begin
						row_start_accepted_q <= 1'b1;
`ifndef SYNTHESIS
						diag_row_start_accept_count_o <=
							diag_row_start_accept_count_o + 16'd1;
`endif
					end
					if (row_context_fire_w) begin
						row_context_accepted_q <= 1'b1;
`ifndef SYNTHESIS
						diag_row_context_accept_count_o <=
							diag_row_context_accept_count_o + 16'd1;
`endif
					end

					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (row_start_complete_w &&
						row_context_complete_w) begin
						row_start_accepted_q <= 1'b0;
						row_context_accepted_q <= 1'b0;
						pixel_ordinal_q <= 10'd0;
						pixel_accepted_q <= 1'b0;
						if (semantic_width_q != 11'd0) begin
							state_q <= STATE_PIXEL;
							state_ticks_remaining_q <= PIXEL_TICKS;
						end else if (!row_is_last_w) begin
							row_ordinal_q <= row_ordinal_q + 4'd1;
							state_ticks_remaining_q <= ROW_SETUP_TICKS;
						end else if (downstream_idle_i) begin
							state_q <= STATE_IDLE;
							state_ticks_remaining_q <= 10'd0;
							done_o <= 1'b1;
						end else begin
							state_q <= STATE_DRAIN;
							state_ticks_remaining_q <= 10'd0;
						end
					end
				end

				STATE_PIXEL: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_pixel_ticks_o <= diag_pixel_ticks_o + 32'd1;
					if ((state_ticks_remaining_q == 10'd1) && !pixel_complete_w) begin
						diag_stall_ticks_o <= diag_stall_ticks_o + 32'd1;
					end
`endif
					if (pixel_fire_w) begin
						pixel_accepted_q <= 1'b1;
`ifndef SYNTHESIS
						diag_pixel_accept_count_o <=
							diag_pixel_accept_count_o + 32'd1;
`endif
					end
					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (pixel_complete_w) begin
						pixel_accepted_q <= 1'b0;
						if (!pixel_is_last_w) begin
							pixel_ordinal_q <= pixel_ordinal_q + 10'd1;
							state_ticks_remaining_q <= PIXEL_TICKS;
						end else if (!row_is_last_w) begin
							row_ordinal_q <= row_ordinal_q + 4'd1;
							pixel_ordinal_q <= 10'd0;
							state_q <= STATE_ROW_SETUP;
							state_ticks_remaining_q <= ROW_SETUP_TICKS;
							row_start_accepted_q <= 1'b0;
							row_context_accepted_q <= 1'b0;
						end else if (downstream_idle_i) begin
							state_q <= STATE_IDLE;
							state_ticks_remaining_q <= 10'd0;
							done_o <= 1'b1;
						end else begin
							state_q <= STATE_DRAIN;
							state_ticks_remaining_q <= 10'd0;
						end
					end
				end

				STATE_DRAIN: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_stall_ticks_o <= diag_stall_ticks_o + 32'd1;
`endif
					if (downstream_idle_i) begin
						state_q <= STATE_IDLE;
						done_o <= 1'b1;
					end
				end

				default: begin
					state_q <= STATE_IDLE;
					state_ticks_remaining_q <= 10'd0;
					row_start_accepted_q <= 1'b0;
					row_context_accepted_q <= 1'b0;
					pixel_accepted_q <= 1'b0;
				end
			endcase
		end
	end

endmodule

`timescale 1ns/1ps

// Affine row setup pipeline.
//
// Read five aligned parameters, seed the DDA, and hold row tags while pixels
// retire. Reads and DDA setup fit in the scheduler's 80-CE row window.
//
// A01 blocks unaligned tables and unknown work writes. Nonzero MP uses the
// measured selected-eye rule. Reject widths outside 1..1024.

module vip_xp_affine_row_pipeline
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,
	input  wire [2:0]           parallax_scale_i,

	input  wire                 row_valid_i,
	output wire                 row_ready_o,
	input  wire [4:0]           row_world_i,
	input  wire [4:0]           row_strip_i,
	input  wire [8:0]           row_screen_y_i,
	input  wire [15:0]          row_local_y_i,
	input  wire [15:0]          param_base_i,
	input  wire [10:0]          semantic_width_i,

	output wire                 param_dram_req_o,
	output wire [15:0]          param_dram_addr_o,
	input  wire                 param_dram_accept_i,
	input  wire                 param_dram_resp_valid_i,
	input  wire [15:0]          param_dram_resp_data_i,
	input  wire                 param_dram_cleanup_busy_i,
	input  wire                 param_dram_stale_discard_i,

	// Held row setup completion.
	output wire                 row_context_valid_o,
	input  wire                 row_context_ready_i,

	// One held DDA coordinate per output pixel.
	output wire                 pixel_valid_o,
	input  wire                 pixel_ready_i,
	output wire                 pixel_retire_o,
	output wire [4:0]           pixel_world_o,
	output wire [4:0]           pixel_strip_o,
	output wire [8:0]           pixel_screen_y_o,
	output wire [15:0]          pixel_local_y_o,
	output wire [9:0]           pixel_ordinal_o,
	output wire                 pixel_last_o,
	output wire signed [25:0]   left_x_accumulator_o,
	output wire signed [25:0]   left_y_accumulator_o,
	output wire signed [25:0]   right_x_accumulator_o,
	output wire signed [25:0]   right_y_accumulator_o,
	output wire signed [16:0]   left_source_x_o,
	output wire signed [16:0]   left_source_y_o,
	output wire signed [16:0]   right_source_x_o,
	output wire signed [16:0]   right_source_y_o,
	output wire [2:0]           left_source_x_pixel_o,
	output wire [2:0]           left_source_y_pixel_o,
	output wire [2:0]           right_source_x_pixel_o,
	output wire [2:0]           right_source_y_pixel_o,
	output wire [8:0]           left_source_x_fraction_o,
	output wire [8:0]           left_source_y_fraction_o,
	output wire [8:0]           right_source_x_fraction_o,
	output wire [8:0]           right_source_y_fraction_o,

	output wire                 busy_o,
	output wire                 cleanup_busy_o,
	output wire                 downstream_idle_o,
	output wire                 param_read_pending_o,
	output wire                 dda_busy_o,
	output wire                 dda_row_done_o,
	output wire [15:0]          active_element_base_o,
	output wire [15:0]          active_mx_o,
	output wire [15:0]          active_mp_o,
	output wire [15:0]          active_my_o,
	output wire [15:0]          active_dx_o,
	output wire [15:0]          active_dy_o,
	output wire                 work_behavior_unresolved_o,
	output wire                 unaligned_policy_blocked_o,
	output wire                 nonzero_mp_policy_blocked_o,
	output wire                 undocumented_width_blocked_o,
	output reg                  unaligned_policy_seen_o,
	output reg                  nonzero_mp_policy_seen_o,
	output reg                  undocumented_width_seen_o,
	output wire                 current_coordinate_range_valid_o,
	output wire                 coordinate_range_error_o,
	output wire                 accumulator_overflow_error_o,
	output reg                  protocol_error_o
);

	reg active_q;
	reg row_context_accepted_q;
	reg unaligned_blocked_q;
	reg [4:0] row_world_q;
	reg [4:0] row_strip_q;
	reg [8:0] row_screen_y_q;
	reg [15:0] row_local_y_q;
	reg [10:0] semantic_width_q;

	wire streamer_row_ready_w;
	wire streamer_row_result_valid_w;
	wire streamer_row_result_ready_w;
	wire [4:0] streamer_result_world_w;
	wire [4:0] streamer_result_strip_w;
	wire [8:0] streamer_result_screen_y_w;
	wire [15:0] streamer_result_local_y_w;
	wire [15:0] streamer_result_element_base_w;
	wire [15:0] streamer_result_mx_w;
	wire [15:0] streamer_result_mp_w;
	wire signed [15:0] streamer_result_mp_scaled_w;
	wire [15:0] streamer_result_my_w;
	wire [15:0] streamer_result_dx_w;
	wire [15:0] streamer_result_dy_w;
	wire streamer_busy_w;
	wire streamer_cleanup_busy_w;
	wire streamer_read_pending_w;
	wire streamer_row_rejected_unaligned_w;
	wire streamer_accept_without_request_w;
	wire streamer_unexpected_response_w;
	wire streamer_response_capture_overflow_w;
	wire streamer_pending_owner_mismatch_w;

	vip_stereo_scale_signed #(.WIDTH(16)) u_affine_mp_scale
	(
		.value_i(streamer_result_mp_w),
		.scale_i(parallax_scale_i),
		.value_o(streamer_result_mp_scaled_w)
	);

	wire dda_setup_ready_w;
	wire dda_pixel_valid_w;
	wire dda_pixel_ready_w;
	wire dda_quiescent_w;
	wire dda_nonzero_mp_unresolved_w;
	wire dda_nonzero_mp_seen_w;

	wire row_accept_w = ce_i && row_valid_i && row_ready_o;
	wire row_context_accept_w = ce_i && row_context_valid_o &&
		row_context_ready_i;
	wire legal_width_w = (semantic_width_q >= 11'd1) &&
		(semantic_width_q <= 11'd1024);
	wire streamer_tags_match_w =
		(streamer_result_world_w == row_world_q) &&
		(streamer_result_strip_w == row_strip_q) &&
		(streamer_result_screen_y_w == row_screen_y_q) &&
		(streamer_result_local_y_w == row_local_y_q);
	wire dda_setup_valid_w = streamer_row_result_valid_w &&
		legal_width_w && streamer_tags_match_w;

	assign row_ready_o = streamer_row_ready_w && !active_q &&
		dda_quiescent_w;
	assign streamer_row_result_ready_w = dda_setup_ready_w &&
		legal_width_w && streamer_tags_match_w;

	assign row_context_valid_o = !reset_i && !abort_i && active_q &&
		dda_pixel_valid_w && !row_context_accepted_q;
	assign dda_pixel_ready_w = pixel_ready_i &&
		row_context_accepted_q;
	assign pixel_valid_o = !reset_i && !abort_i && active_q &&
		row_context_accepted_q && dda_pixel_valid_w;
	assign pixel_retire_o = ce_i && pixel_valid_o && pixel_ready_i;
	assign pixel_world_o = row_world_q;
	assign pixel_strip_o = row_strip_q;
	assign pixel_screen_y_o = row_screen_y_q;
	assign pixel_local_y_o = row_local_y_q;

	assign busy_o = active_q || streamer_busy_w || dda_busy_o;
	assign cleanup_busy_o = streamer_cleanup_busy_w;
	assign downstream_idle_o = !active_q && !streamer_busy_w &&
		dda_quiescent_w;
	assign param_read_pending_o = streamer_read_pending_w;
	assign active_element_base_o = streamer_result_element_base_w;
	assign active_mx_o = streamer_result_mx_w;
	assign active_mp_o = streamer_result_mp_w;
	assign active_my_o = streamer_result_my_w;
	assign active_dx_o = streamer_result_dx_w;
	assign active_dy_o = streamer_result_dy_w;
	// Silicon unknown: Affine work-word writes are not known, so keep this flagged.
	assign work_behavior_unresolved_o = 1'b1;
	assign unaligned_policy_blocked_o = active_q &&
		unaligned_blocked_q;
	// Nonzero MP is allowed.
	assign nonzero_mp_policy_blocked_o = 1'b0;
	assign undocumented_width_blocked_o = active_q &&
		!legal_width_w;

	vip_xp_affine_param_work_streamer u_param_streamer
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.row_valid_i(row_valid_i && !active_q && dda_quiescent_w),
		.row_ready_o(streamer_row_ready_w),
		.row_world_i(row_world_i),
		.row_strip_i(row_strip_i),
		.row_screen_y_i(row_screen_y_i),
		.row_local_row_i(row_local_y_i),
		.param_base_i(param_base_i),
		.dram_req_o(param_dram_req_o),
		.dram_addr_o(param_dram_addr_o),
		.dram_accept_i(param_dram_accept_i),
		.dram_resp_valid_i(param_dram_resp_valid_i),
		.dram_resp_data_i(param_dram_resp_data_i),
		.dram_router_cleanup_busy_i(param_dram_cleanup_busy_i),
		.dram_router_stale_discard_i(param_dram_stale_discard_i),
		.dram_write_o(),
		.dram_wdata_o(),
		.dram_byte_enable_o(),
		.work_behavior_unresolved_o(),
		.work_writes_disabled_o(),
		.row_result_valid_o(streamer_row_result_valid_w),
		.row_result_ready_i(streamer_row_result_ready_w),
		.row_result_world_o(streamer_result_world_w),
		.row_result_strip_o(streamer_result_strip_w),
		.row_result_screen_y_o(streamer_result_screen_y_w),
		.row_result_local_row_o(streamer_result_local_y_w),
		.row_result_element_base_o(streamer_result_element_base_w),
		.row_result_mx_o(streamer_result_mx_w),
		.row_result_mp_o(streamer_result_mp_w),
		.row_result_my_o(streamer_result_my_w),
		.row_result_dx_o(streamer_result_dx_w),
		.row_result_dy_o(streamer_result_dy_w),
		.busy_o(streamer_busy_w),
		.cleanup_busy_o(streamer_cleanup_busy_w),
		.read_pending_o(streamer_read_pending_w),
		.response_capture_valid_o(),
		.dram_request_owner_o(),
		.dram_pending_owner_o(),
		.active_element_base_o(),
		.active_field_index_o(),
		.active_field_address_o(),
		.active_address_wrapped_o(),
		.row_param_aligned_o(),
		.row_rejected_unaligned_o(streamer_row_rejected_unaligned_w),
		.unaligned_param_seen_o(),
		.request_accepted_o(),
		.response_retired_o(),
		.stale_response_discarded_o(),
		.accept_without_request_o(streamer_accept_without_request_w),
		.unexpected_response_o(streamer_unexpected_response_w),
		.response_capture_overflow_o(streamer_response_capture_overflow_w),
		.pending_owner_mismatch_o(streamer_pending_owner_mismatch_w)
	);

	vip_xp_affine_dda u_dda
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.setup_valid_i(dda_setup_valid_w),
		.setup_ready_o(dda_setup_ready_w),
		.setup_accept_o(),
		.row_mx_i($signed(streamer_result_mx_w)),
		.row_mp_i(streamer_result_mp_scaled_w),
		.row_my_i($signed(streamer_result_my_w)),
		.row_dx_i($signed(streamer_result_dx_w)),
		.row_dy_i($signed(streamer_result_dy_w)),
		.configured_pixel_count_i(semantic_width_q),
		.pixel_valid_o(dda_pixel_valid_w),
		.pixel_ready_i(dda_pixel_ready_w),
		.pixel_retire_o(),
		.pixel_ordinal_o(pixel_ordinal_o),
		.pixel_last_o(pixel_last_o),
		.left_x_accumulator_o(left_x_accumulator_o),
		.left_y_accumulator_o(left_y_accumulator_o),
		.right_x_accumulator_o(right_x_accumulator_o),
		.right_y_accumulator_o(right_y_accumulator_o),
		.left_source_x_o(left_source_x_o),
		.left_source_y_o(left_source_y_o),
		.right_source_x_o(right_source_x_o),
		.right_source_y_o(right_source_y_o),
		.left_source_x_pixel_o(left_source_x_pixel_o),
		.left_source_y_pixel_o(left_source_y_pixel_o),
		.right_source_x_pixel_o(right_source_x_pixel_o),
		.right_source_y_pixel_o(right_source_y_pixel_o),
		.left_source_x_fraction_o(left_source_x_fraction_o),
		.left_source_y_fraction_o(left_source_y_fraction_o),
		.right_source_x_fraction_o(right_source_x_fraction_o),
		.right_source_y_fraction_o(right_source_y_fraction_o),
		.current_coordinate_range_valid_o(
			current_coordinate_range_valid_o),
		.coordinate_range_error_o(coordinate_range_error_o),
		.accumulator_overflow_error_o(accumulator_overflow_error_o),
		.nonzero_mp_policy_unresolved_o(dda_nonzero_mp_unresolved_w),
		.nonzero_mp_policy_seen_o(dda_nonzero_mp_seen_w),
		// The scheduler admits only legal widths (dda_setup_valid_w
		// requires legal_width_w), so the invalid-width flags stay low.
		/* verilator lint_off PINCONNECTEMPTY */
		.configured_width_invalid_o(),
		.configured_width_invalid_seen_o(),
		/* verilator lint_on PINCONNECTEMPTY */
		.row_done_o(dda_row_done_o),
		.busy_o(dda_busy_o),
		.quiescent_o(dda_quiescent_w)
	);

	always @(posedge clk_i) begin
		if (reset_i) begin
			active_q <= 1'b0;
			row_context_accepted_q <= 1'b0;
			unaligned_blocked_q <= 1'b0;
			row_world_q <= 5'd0;
			row_strip_q <= 5'd0;
			row_screen_y_q <= 9'd0;
			row_local_y_q <= 16'd0;
			semantic_width_q <= 11'd0;
			unaligned_policy_seen_o <= 1'b0;
			nonzero_mp_policy_seen_o <= 1'b0;
			undocumented_width_seen_o <= 1'b0;
			protocol_error_o <= 1'b0;
		end else if (abort_i) begin
			active_q <= 1'b0;
			row_context_accepted_q <= 1'b0;
			unaligned_blocked_q <= 1'b0;
		end else if (ce_i) begin
			if (row_accept_w) begin
				active_q <= 1'b1;
				row_context_accepted_q <= 1'b0;
				unaligned_blocked_q <= 1'b0;
				row_world_q <= row_world_i;
				row_strip_q <= row_strip_i;
				row_screen_y_q <= row_screen_y_i;
				row_local_y_q <= row_local_y_i;
				semantic_width_q <= semantic_width_i;
				if ((semantic_width_i == 11'd0) ||
					(semantic_width_i > 11'd1024)) begin
					undocumented_width_seen_o <= 1'b1;
				end
			end
			if (row_context_accept_w) begin
				row_context_accepted_q <= 1'b1;
			end
			// Clear row ownership with the final accepted DDA pixel.
			if (pixel_retire_o && pixel_last_o) begin
				active_q <= 1'b0;
				row_context_accepted_q <= 1'b0;
				unaligned_blocked_q <= 1'b0;
			end
			if (streamer_row_rejected_unaligned_w) begin
				unaligned_blocked_q <= 1'b1;
				unaligned_policy_seen_o <= 1'b1;
			end
			if (dda_nonzero_mp_unresolved_w || dda_nonzero_mp_seen_w) begin
				nonzero_mp_policy_seen_o <= 1'b1;
			end
			if (streamer_accept_without_request_w ||
				streamer_unexpected_response_w ||
				streamer_response_capture_overflow_w ||
				streamer_pending_owner_mismatch_w ||
				(streamer_row_result_valid_w &&
				 !streamer_tags_match_w)) begin
				protocol_error_o <= 1'b1;
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Affine parameter row streamer.
//
// Compute wrapped ParamBase+(local_row<<3), then read MX, MP, MY, DX, and DY.
// Field addresses use STS's provisional element_base OR field_index rule.
//
// Capture responses during CE pauses. Abort drops offers and drains accepted reads.
//
// A01 is uncharacterized. Reject unaligned tables and do not access work words 5-7.

module vip_xp_affine_param_work_streamer
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	// Held Affine row context.
	input  wire                 row_valid_i,
	output wire                 row_ready_o,
	input  wire [4:0]           row_world_i,
	input  wire [4:0]           row_strip_i,
	input  wire [8:0]           row_screen_y_i,
	input  wire [15:0]          row_local_row_i,
	input  wire [15:0]          param_base_i,

	// Parameter client of the shared DRAM mux.
	output wire                 dram_req_o,
	output wire [15:0]          dram_addr_o,
	input  wire                 dram_accept_i,
	input  wire                 dram_resp_valid_i,
	input  wire [15:0]          dram_resp_data_i,
	input  wire                 dram_router_cleanup_busy_i,
	input  wire                 dram_router_stale_discard_i,

	// Reserved, inactive A01 work-write interface.
	output wire                 dram_write_o,
	output wire [15:0]          dram_wdata_o,
	output wire [1:0]           dram_byte_enable_o,
	output wire                 work_behavior_unresolved_o,
	output wire                 work_writes_disabled_o,

	// Held completed parameter row.
	output wire                 row_result_valid_o,
	input  wire                 row_result_ready_i,
	output wire [4:0]           row_result_world_o,
	output wire [4:0]           row_result_strip_o,
	output wire [8:0]           row_result_screen_y_o,
	output wire [15:0]          row_result_local_row_o,
	output wire [15:0]          row_result_element_base_o,
	output wire [15:0]          row_result_mx_o,
	output wire [15:0]          row_result_mp_o,
	output wire [15:0]          row_result_my_o,
	output wire [15:0]          row_result_dx_o,
	output wire [15:0]          row_result_dy_o,

	// Ownership, cleanup, address, and policy diagnostics.
	output wire                 busy_o,
	output wire                 cleanup_busy_o,
	output wire                 read_pending_o,
	output wire                 response_capture_valid_o,
	output wire [2:0]           dram_request_owner_o,
	output wire [2:0]           dram_pending_owner_o,
	output wire [15:0]          active_element_base_o,
	output wire [2:0]           active_field_index_o,
	output wire [15:0]          active_field_address_o,
	output wire                 active_address_wrapped_o,
	output wire                 row_param_aligned_o,
	output wire                 row_rejected_unaligned_o,
	output wire                 unaligned_param_seen_o,
	output wire                 request_accepted_o,
	output wire                 response_retired_o,
	output wire                 stale_response_discarded_o,
	output wire                 accept_without_request_o,
	output wire                 unexpected_response_o,
	output wire                 response_capture_overflow_o,
	output wire                 pending_owner_mismatch_o
);

	localparam [1:0]
		STATE_IDLE   = 2'd0,
		STATE_READ   = 2'd1,
		STATE_RESULT = 2'd2,
		STATE_DRAIN  = 2'd3;

	localparam [2:0]
		OWNER_NONE = 3'd0,
		OWNER_MX   = 3'd1,
		OWNER_MP   = 3'd2,
		OWNER_MY   = 3'd3,
		OWNER_DX   = 3'd4,
		OWNER_DY   = 3'd5;

	reg [1:0] state_q;

	reg [4:0] row_world_q;
	reg [4:0] row_strip_q;
	reg [8:0] row_screen_y_q;
	reg [15:0] row_local_row_q;
	reg [15:0] element_base_q;
	reg [2:0] field_index_q;
	reg address_wrapped_q;

	reg pending_q;
	reg pending_stale_q;
	reg [2:0] pending_owner_q;
	reg response_capture_valid_q;
	reg [15:0] response_capture_data_q;

	reg [15:0] mx_q;
	reg [15:0] mp_q;
	reg [15:0] my_q;
	reg [15:0] dx_q;
	reg [15:0] dy_q;

	reg row_rejected_unaligned_q;
	reg unaligned_param_seen_q;

`ifndef SYNTHESIS
	reg request_accepted_q;
	reg response_retired_q;
	reg stale_response_discarded_q;
	reg accept_without_request_q;
	reg unexpected_response_q;
	reg response_capture_overflow_q;
	reg pending_owner_mismatch_q;
`endif

	// Use bits 12:0 before shifting to make the 16-bit row stride wrap explicit.
	wire [15:0] row_stride_wrapped_w =
		{row_local_row_i[12:0], 3'b000};
	wire [16:0] element_base_sum_w =
		{1'b0, param_base_i} + {1'b0, row_stride_wrapped_w};
	wire [15:0] calculated_element_base_w =
		element_base_sum_w[15:0];
	wire calculated_address_wrapped_w =
		(|row_local_row_i[15:13]) || element_base_sum_w[16];
	wire row_param_aligned_w = param_base_i[2:0] == 3'b000;

	wire request_active_w = state_q == STATE_READ;
	wire [2:0] request_owner_w = field_index_q + 3'd1;
	wire [15:0] field_address_w =
		element_base_q | {13'd0, field_index_q};

	wire response_available_w = response_capture_valid_q ||
		dram_resp_valid_i;
	wire [15:0] response_data_w = response_capture_valid_q ?
		response_capture_data_q : dram_resp_data_i;
	wire stale_active_w = pending_q &&
		(pending_stale_q || abort_i);
	wire live_response_fire_w = ce_i && pending_q &&
		!pending_stale_q && !abort_i && response_available_w;
	wire stale_response_fire_w = ce_i && stale_active_w &&
		response_available_w;
	wire request_accept_fire_w = ce_i && dram_req_o &&
		dram_accept_i;
	wire row_accept_fire_w = ce_i && row_valid_i && row_ready_o;
	wire result_fire_w = ce_i && row_result_valid_o &&
		row_result_ready_i;

	assign row_ready_o = ce_i && !reset_i && !abort_i &&
		(state_q == STATE_IDLE) && !pending_q &&
		!response_capture_valid_q && !dram_router_cleanup_busy_i;

	assign dram_req_o = !reset_i && !abort_i && request_active_w &&
		!pending_q && !dram_router_cleanup_busy_i;
	assign dram_addr_o = field_address_w;

	// Silicon unknown: do not issue guessed Affine work writes.
	assign dram_write_o = 1'b0;
	assign dram_wdata_o = 16'd0;
	assign dram_byte_enable_o = 2'b00;
	assign work_behavior_unresolved_o = 1'b1;
	assign work_writes_disabled_o = 1'b1;

	assign row_result_valid_o = !reset_i && !abort_i &&
		(state_q == STATE_RESULT);
	assign row_result_world_o = row_world_q;
	assign row_result_strip_o = row_strip_q;
	assign row_result_screen_y_o = row_screen_y_q;
	assign row_result_local_row_o = row_local_row_q;
	assign row_result_element_base_o = element_base_q;
	assign row_result_mx_o = mx_q;
	assign row_result_mp_o = mp_q;
	assign row_result_my_o = my_q;
	assign row_result_dx_o = dx_q;
	assign row_result_dy_o = dy_q;

	assign busy_o = (state_q != STATE_IDLE) || pending_q ||
		response_capture_valid_q || dram_router_cleanup_busy_i;
	assign cleanup_busy_o = dram_router_cleanup_busy_i ||
		(state_q == STATE_DRAIN) || stale_active_w;
	assign read_pending_o = pending_q;
	assign response_capture_valid_o = response_capture_valid_q;
	assign dram_request_owner_o = dram_req_o ?
		request_owner_w : OWNER_NONE;
	assign dram_pending_owner_o = pending_q ?
		pending_owner_q : OWNER_NONE;
	assign active_element_base_o = element_base_q;
	assign active_field_index_o = field_index_q;
	assign active_field_address_o = field_address_w;
	assign active_address_wrapped_o = address_wrapped_q;
	assign row_param_aligned_o = row_param_aligned_w;
	assign row_rejected_unaligned_o = row_rejected_unaligned_q;
	assign unaligned_param_seen_o = unaligned_param_seen_q;
`ifndef SYNTHESIS
	assign request_accepted_o = request_accepted_q;
	assign response_retired_o = response_retired_q;
	assign stale_response_discarded_o = stale_response_discarded_q;
	assign accept_without_request_o = accept_without_request_q;
	assign unexpected_response_o = unexpected_response_q;
	assign response_capture_overflow_o = response_capture_overflow_q;
	assign pending_owner_mismatch_o = pending_owner_mismatch_q;
`else
	assign request_accepted_o = 1'b0;
	assign response_retired_o = 1'b0;
	assign stale_response_discarded_o = 1'b0;
	assign accept_without_request_o = 1'b0;
	assign unexpected_response_o = 1'b0;
	assign response_capture_overflow_o = 1'b0;
	assign pending_owner_mismatch_o = 1'b0;
`endif

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			row_world_q <= 5'd0;
			row_strip_q <= 5'd0;
			row_screen_y_q <= 9'd0;
			row_local_row_q <= 16'd0;
			element_base_q <= 16'd0;
			field_index_q <= 3'd0;
			address_wrapped_q <= 1'b0;
			pending_q <= 1'b0;
			pending_stale_q <= 1'b0;
			pending_owner_q <= OWNER_NONE;
			response_capture_valid_q <= 1'b0;
			response_capture_data_q <= 16'd0;
			mx_q <= 16'd0;
			mp_q <= 16'd0;
			my_q <= 16'd0;
			dx_q <= 16'd0;
			dy_q <= 16'd0;
			row_rejected_unaligned_q <= 1'b0;
			unaligned_param_seen_q <= 1'b0;
`ifndef SYNTHESIS
			request_accepted_q <= 1'b0;
			response_retired_q <= 1'b0;
			stale_response_discarded_q <= 1'b0;
			accept_without_request_q <= 1'b0;
			unexpected_response_q <= 1'b0;
			response_capture_overflow_q <= 1'b0;
			pending_owner_mismatch_q <= 1'b0;
`endif
		end else begin
			row_rejected_unaligned_q <= 1'b0;
`ifndef SYNTHESIS
			request_accepted_q <= 1'b0;
			response_retired_q <= 1'b0;
			stale_response_discarded_q <= 1'b0;
`endif

			// Retire local ownership on the raw stale-discard pulse.
			if (dram_router_stale_discard_i) begin
`ifndef SYNTHESIS
				if (!pending_q) begin
					unexpected_response_q <= 1'b1;
				end
`endif
				pending_q <= 1'b0;
				pending_stale_q <= 1'b0;
				pending_owner_q <= OWNER_NONE;
				response_capture_valid_q <= 1'b0;
				state_q <= STATE_IDLE;
`ifndef SYNTHESIS
				stale_response_discarded_q <= 1'b1;
`endif
			end

			// Save raw responses that CE cannot consume immediately.
			if (dram_resp_valid_i && !dram_router_stale_discard_i) begin
`ifndef SYNTHESIS
				if (!pending_q) begin
					unexpected_response_q <= 1'b1;
				end else if (response_capture_valid_q) begin
					response_capture_overflow_q <= 1'b1;
				end
`endif
				if (pending_q && !response_capture_valid_q &&
					!live_response_fire_w &&
					!stale_response_fire_w) begin
					response_capture_valid_q <= 1'b1;
					response_capture_data_q <= dram_resp_data_i;
				end
			end

			// Raw abort keeps only state needed to drain an accepted read.
			if (abort_i) begin
				mx_q <= 16'd0;
				mp_q <= 16'd0;
				my_q <= 16'd0;
				dx_q <= 16'd0;
				dy_q <= 16'd0;
				if (!dram_router_stale_discard_i) begin
					if (pending_q) begin
						pending_stale_q <= 1'b1;
						state_q <= STATE_DRAIN;
					end else begin
						state_q <= STATE_IDLE;
					end
				end
			end

			if (ce_i) begin
`ifndef SYNTHESIS
				if (dram_accept_i && !dram_req_o) begin
					accept_without_request_q <= 1'b1;
				end
`endif

				if (stale_response_fire_w) begin
					pending_q <= 1'b0;
					pending_stale_q <= 1'b0;
					pending_owner_q <= OWNER_NONE;
					response_capture_valid_q <= 1'b0;
					state_q <= STATE_IDLE;
`ifndef SYNTHESIS
					stale_response_discarded_q <= 1'b1;
`endif
				end else if (live_response_fire_w) begin
`ifndef SYNTHESIS
					if ((pending_owner_q != request_owner_w) ||
						(state_q != STATE_READ) ||
						(pending_owner_q == OWNER_NONE)) begin
						pending_owner_mismatch_q <= 1'b1;
					end
`endif
					pending_q <= 1'b0;
					pending_stale_q <= 1'b0;
					pending_owner_q <= OWNER_NONE;
					response_capture_valid_q <= 1'b0;
`ifndef SYNTHESIS
					response_retired_q <= 1'b1;
`endif

					case (pending_owner_q)
						OWNER_MX: begin
							mx_q <= response_data_w;
							field_index_q <= 3'd1;
						end
						OWNER_MP: begin
							mp_q <= response_data_w;
							field_index_q <= 3'd2;
						end
						OWNER_MY: begin
							my_q <= response_data_w;
							field_index_q <= 3'd3;
						end
						OWNER_DX: begin
							dx_q <= response_data_w;
							field_index_q <= 3'd4;
						end
						OWNER_DY: begin
							dy_q <= response_data_w;
							state_q <= STATE_RESULT;
						end
						default: begin
							state_q <= STATE_DRAIN;
						end
					endcase
				end

				if (!abort_i && request_accept_fire_w) begin
					pending_q <= 1'b1;
					pending_stale_q <= 1'b0;
					pending_owner_q <= request_owner_w;
`ifndef SYNTHESIS
					request_accepted_q <= 1'b1;
`endif
				end

				if (!abort_i && row_accept_fire_w) begin
					if (row_param_aligned_w) begin
						row_world_q <= row_world_i;
						row_strip_q <= row_strip_i;
						row_screen_y_q <= row_screen_y_i;
						row_local_row_q <= row_local_row_i;
						element_base_q <=
							calculated_element_base_w;
						field_index_q <= 3'd0;
						address_wrapped_q <=
							calculated_address_wrapped_w;
						mx_q <= 16'd0;
						mp_q <= 16'd0;
						my_q <= 16'd0;
						dx_q <= 16'd0;
						dy_q <= 16'd0;
						state_q <= STATE_READ;
					end else begin
						row_rejected_unaligned_q <= 1'b1;
						unaligned_param_seen_q <= 1'b1;
					end
				end

				if (!abort_i && result_fire_w) begin
					state_q <= STATE_IDLE;
				end
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Registered Affine seed and DDA.
//
// Shift signed Q13.3 MX/MY into Q7.9. Four 26-bit accumulators add DX/DY once
// per retired pixel.
//
// MP sign selects which eye receives abs(MP)*DX/DY. A 16-step shift/add avoids
// a wide multiplier. This matches Sacred and the Virtual Bowling capture.
//
// Hold pixel output until ready. CE pauses progress; raw abort drops context.

module vip_xp_affine_dda
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	input  wire                 setup_valid_i,
	output wire                 setup_ready_o,
	output wire                 setup_accept_o,
	input  wire signed [15:0]   row_mx_i,
	input  wire signed [15:0]   row_mp_i,
	input  wire signed [15:0]   row_my_i,
	input  wire signed [15:0]   row_dx_i,
	input  wire signed [15:0]   row_dy_i,
	input  wire [10:0]          configured_pixel_count_i,

	output wire                 pixel_valid_o,
	input  wire                 pixel_ready_i,
	output wire                 pixel_retire_o,
	output wire [9:0]           pixel_ordinal_o,
	output wire                 pixel_last_o,

	output reg  signed [25:0]   left_x_accumulator_o,
	output reg  signed [25:0]   left_y_accumulator_o,
	output reg  signed [25:0]   right_x_accumulator_o,
	output reg  signed [25:0]   right_y_accumulator_o,

	output wire signed [16:0]   left_source_x_o,
	output wire signed [16:0]   left_source_y_o,
	output wire signed [16:0]   right_source_x_o,
	output wire signed [16:0]   right_source_y_o,
	output wire [2:0]           left_source_x_pixel_o,
	output wire [2:0]           left_source_y_pixel_o,
	output wire [2:0]           right_source_x_pixel_o,
	output wire [2:0]           right_source_y_pixel_o,
	output wire [8:0]           left_source_x_fraction_o,
	output wire [8:0]           left_source_y_fraction_o,
	output wire [8:0]           right_source_x_fraction_o,
	output wire [8:0]           right_source_y_fraction_o,

	output wire                 current_coordinate_range_valid_o,
	output reg                  coordinate_range_error_o,
	output reg                  accumulator_overflow_error_o,
	output wire                 nonzero_mp_policy_unresolved_o,
	output reg                  nonzero_mp_policy_seen_o,
	output wire                 configured_width_invalid_o,
	output reg                  configured_width_invalid_seen_o,
	output wire                 row_done_o,
	output wire                 busy_o,
	output wire                 quiescent_o
);

	localparam [2:0]
		STATE_IDLE    = 3'd0,
		STATE_CONVERT = 3'd1,
		STATE_MP_STEP = 3'd2,
		STATE_SEED    = 3'd3,
		STATE_ACTIVE  = 3'd4;

	reg [2:0] state_q;
	reg signed [15:0] row_mx_q;
	reg signed [15:0] row_mp_q;
	reg signed [15:0] row_my_q;
	reg signed [15:0] row_dx_q;
	reg signed [15:0] row_dy_q;
	reg [10:0] configured_pixel_count_q;
	reg [9:0] pixel_ordinal_q;
	reg signed [25:0] mx_seed_q;
	reg signed [25:0] my_seed_q;
	reg signed [25:0] dx_q;
	reg signed [25:0] dy_q;
	reg [15:0] mp_magnitude_q;
	reg [3:0] mp_step_q;
	reg signed [31:0] mp_x_accumulator_q;
	reg signed [31:0] mp_y_accumulator_q;
	reg signed [31:0] mp_x_term_q;
	reg signed [31:0] mp_y_term_q;
	reg row_done_q;

	wire setup_width_valid_w =
		(configured_pixel_count_i >= 11'd1) &&
		(configured_pixel_count_i <= 11'd1024);
	wire setup_mp_zero_w = row_mp_i == 16'sd0;

	assign setup_ready_o = ce_i && !reset_i && !abort_i &&
		(state_q == STATE_IDLE) && setup_width_valid_w;
	assign setup_accept_o = setup_valid_i && setup_ready_o;
	// This pulse reports nonzero MP; it does not block setup.
	assign nonzero_mp_policy_unresolved_o = setup_valid_i &&
		!setup_mp_zero_w;
	assign configured_width_invalid_o = setup_valid_i &&
		!setup_width_valid_w;

	assign pixel_valid_o = !reset_i && !abort_i &&
		(state_q == STATE_ACTIVE);
	assign pixel_retire_o = ce_i && pixel_valid_o && pixel_ready_i;
	assign pixel_ordinal_o = pixel_ordinal_q;
	assign pixel_last_o = pixel_valid_o &&
		({1'b0, pixel_ordinal_q} ==
		 (configured_pixel_count_q - 11'd1));
	assign row_done_o = !reset_i && !abort_i && row_done_q;
	assign busy_o = state_q != STATE_IDLE;
	assign quiescent_o = state_q == STATE_IDLE;

	// Use unsigned MP magnitude so -32768 remains exact.
	wire [15:0] row_mp_magnitude_w = row_mp_q[15] ?
		((~row_mp_q) + 16'd1) : row_mp_q;
	wire signed [31:0] row_dx_extended_w =
		$signed({{16{row_dx_q[15]}}, row_dx_q});
	wire signed [31:0] row_dy_extended_w =
		$signed({{16{row_dy_q[15]}}, row_dy_q});

	// Widen the seed add before explicit narrowing.
	wire signed [32:0] selected_x_seed_sum_w =
		$signed({{7{mx_seed_q[25]}}, mx_seed_q}) +
		$signed({mp_x_accumulator_q[31], mp_x_accumulator_q});
	wire signed [32:0] selected_y_seed_sum_w =
		$signed({{7{my_seed_q[25]}}, my_seed_q}) +
		$signed({mp_y_accumulator_q[31], mp_y_accumulator_q});
	wire signed [25:0] selected_x_seed_w = selected_x_seed_sum_w[25:0];
	wire signed [25:0] selected_y_seed_w = selected_y_seed_sum_w[25:0];
	wire selected_x_seed_fits_w =
		selected_x_seed_sum_w[32:26] ==
		{7{selected_x_seed_sum_w[25]}};
	wire selected_y_seed_fits_w =
		selected_y_seed_sum_w[32:26] ==
		{7{selected_y_seed_sum_w[25]}};
	wire selected_x_seed_range_valid_w = selected_x_seed_fits_w &&
		(selected_x_seed_w[25:22] == {4{selected_x_seed_w[21]}});
	wire selected_y_seed_range_valid_w = selected_y_seed_fits_w &&
		(selected_y_seed_w[25:22] == {4{selected_y_seed_w[21]}});

	// Coordinates are signed Q7.9; the address stage uses the signed integer part.
	wire left_x_range_valid_w =
		left_x_accumulator_o[25:22] ==
		{4{left_x_accumulator_o[21]}};
	wire left_y_range_valid_w =
		left_y_accumulator_o[25:22] ==
		{4{left_y_accumulator_o[21]}};
	wire right_x_range_valid_w =
		right_x_accumulator_o[25:22] ==
		{4{right_x_accumulator_o[21]}};
	wire right_y_range_valid_w =
		right_y_accumulator_o[25:22] ==
		{4{right_y_accumulator_o[21]}};

	assign current_coordinate_range_valid_o = pixel_valid_o &&
		left_x_range_valid_w && left_y_range_valid_w &&
		right_x_range_valid_w && right_y_range_valid_w;

	assign left_source_x_o = $signed(
		{{4{left_x_accumulator_o[21]}},
		 left_x_accumulator_o[21:9]});
	assign left_source_y_o = $signed(
		{{4{left_y_accumulator_o[21]}},
		 left_y_accumulator_o[21:9]});
	assign right_source_x_o = $signed(
		{{4{right_x_accumulator_o[21]}},
		 right_x_accumulator_o[21:9]});
	assign right_source_y_o = $signed(
		{{4{right_y_accumulator_o[21]}},
		 right_y_accumulator_o[21:9]});

	assign left_source_x_pixel_o = left_x_accumulator_o[11:9];
	assign left_source_y_pixel_o = left_y_accumulator_o[11:9];
	assign right_source_x_pixel_o = right_x_accumulator_o[11:9];
	assign right_source_y_pixel_o = right_y_accumulator_o[11:9];
	assign left_source_x_fraction_o = left_x_accumulator_o[8:0];
	assign left_source_y_fraction_o = left_y_accumulator_o[8:0];
	assign right_source_x_fraction_o = right_x_accumulator_o[8:0];
	assign right_source_y_fraction_o = right_y_accumulator_o[8:0];

	// Widen each DDA add by one bit and flag overflow before narrowing.
	wire signed [26:0] left_x_sum_w =
		{left_x_accumulator_o[25], left_x_accumulator_o} +
		{dx_q[25], dx_q};
	wire signed [26:0] left_y_sum_w =
		{left_y_accumulator_o[25], left_y_accumulator_o} +
		{dy_q[25], dy_q};
	wire signed [26:0] right_x_sum_w =
		{right_x_accumulator_o[25], right_x_accumulator_o} +
		{dx_q[25], dx_q};
	wire signed [26:0] right_y_sum_w =
		{right_y_accumulator_o[25], right_y_accumulator_o} +
		{dy_q[25], dy_q};
	wire signed [25:0] left_x_next_w = left_x_sum_w[25:0];
	wire signed [25:0] left_y_next_w = left_y_sum_w[25:0];
	wire signed [25:0] right_x_next_w = right_x_sum_w[25:0];
	wire signed [25:0] right_y_next_w = right_y_sum_w[25:0];
	wire recurrence_overflow_w =
		(left_x_sum_w[26] != left_x_sum_w[25]) ||
		(left_y_sum_w[26] != left_y_sum_w[25]) ||
		(right_x_sum_w[26] != right_x_sum_w[25]) ||
		(right_y_sum_w[26] != right_y_sum_w[25]);
	wire next_coordinate_range_valid_w =
		(left_x_next_w[25:22] == {4{left_x_next_w[21]}}) &&
		(left_y_next_w[25:22] == {4{left_y_next_w[21]}}) &&
		(right_x_next_w[25:22] == {4{right_x_next_w[21]}}) &&
		(right_y_next_w[25:22] == {4{right_y_next_w[21]}});
	wire base_seed_coordinate_range_valid_w =
		(mx_seed_q[25:22] == {4{mx_seed_q[21]}}) &&
		(my_seed_q[25:22] == {4{my_seed_q[21]}});
	wire seed_coordinate_range_valid_w =
		base_seed_coordinate_range_valid_w &&
		selected_x_seed_range_valid_w &&
		selected_y_seed_range_valid_w;

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			row_mx_q <= 16'sd0;
			row_mp_q <= 16'sd0;
			row_my_q <= 16'sd0;
			row_dx_q <= 16'sd0;
			row_dy_q <= 16'sd0;
			configured_pixel_count_q <= 11'd0;
			pixel_ordinal_q <= 10'd0;
			mx_seed_q <= 26'sd0;
			my_seed_q <= 26'sd0;
			dx_q <= 26'sd0;
			dy_q <= 26'sd0;
			mp_magnitude_q <= 16'd0;
			mp_step_q <= 4'd0;
			mp_x_accumulator_q <= 32'sd0;
			mp_y_accumulator_q <= 32'sd0;
			mp_x_term_q <= 32'sd0;
			mp_y_term_q <= 32'sd0;
			left_x_accumulator_o <= 26'sd0;
			left_y_accumulator_o <= 26'sd0;
			right_x_accumulator_o <= 26'sd0;
			right_y_accumulator_o <= 26'sd0;
			row_done_q <= 1'b0;
			coordinate_range_error_o <= 1'b0;
			accumulator_overflow_error_o <= 1'b0;
			nonzero_mp_policy_seen_o <= 1'b0;
			configured_width_invalid_seen_o <= 1'b0;
		end else if (abort_i) begin
			state_q <= STATE_IDLE;
			row_mx_q <= 16'sd0;
			row_mp_q <= 16'sd0;
			row_my_q <= 16'sd0;
			row_dx_q <= 16'sd0;
			row_dy_q <= 16'sd0;
			configured_pixel_count_q <= 11'd0;
			pixel_ordinal_q <= 10'd0;
			mx_seed_q <= 26'sd0;
			my_seed_q <= 26'sd0;
			dx_q <= 26'sd0;
			dy_q <= 26'sd0;
			mp_magnitude_q <= 16'd0;
			mp_step_q <= 4'd0;
			mp_x_accumulator_q <= 32'sd0;
			mp_y_accumulator_q <= 32'sd0;
			mp_x_term_q <= 32'sd0;
			mp_y_term_q <= 32'sd0;
			left_x_accumulator_o <= 26'sd0;
			left_y_accumulator_o <= 26'sd0;
			right_x_accumulator_o <= 26'sd0;
			right_y_accumulator_o <= 26'sd0;
			row_done_q <= 1'b0;
		end else if (ce_i) begin
			row_done_q <= 1'b0;
			case (state_q)
				STATE_IDLE: begin
					if (setup_valid_i && !setup_mp_zero_w)
						nonzero_mp_policy_seen_o <= 1'b1;
					if (setup_valid_i && !setup_width_valid_w)
						configured_width_invalid_seen_o <= 1'b1;
					if (setup_accept_o) begin
						row_mx_q <= row_mx_i;
						row_mp_q <= row_mp_i;
						row_my_q <= row_my_i;
						row_dx_q <= row_dx_i;
						row_dy_q <= row_dy_i;
						configured_pixel_count_q <=
							configured_pixel_count_i;
						state_q <= STATE_CONVERT;
					end
				end

				STATE_CONVERT: begin
					// Concatenate to sign-extend and shift into 26 bits.
					mx_seed_q <= $signed(
						{{4{row_mx_q[15]}}, row_mx_q, 6'b000000});
					my_seed_q <= $signed(
						{{4{row_my_q[15]}}, row_my_q, 6'b000000});
					dx_q <= $signed({{10{row_dx_q[15]}}, row_dx_q});
					dy_q <= $signed({{10{row_dy_q[15]}}, row_dy_q});
					mp_magnitude_q <= row_mp_magnitude_w;
					mp_step_q <= 4'd0;
					mp_x_accumulator_q <= 32'sd0;
					mp_y_accumulator_q <= 32'sd0;
					mp_x_term_q <= row_dx_extended_w;
					mp_y_term_q <= row_dy_extended_w;
					if (row_mp_q == 16'sd0)
						state_q <= STATE_SEED;
					else
						state_q <= STATE_MP_STEP;
				end

				STATE_MP_STEP: begin
					if (mp_magnitude_q[0]) begin
						mp_x_accumulator_q <=
							mp_x_accumulator_q + mp_x_term_q;
						mp_y_accumulator_q <=
							mp_y_accumulator_q + mp_y_term_q;
					end
					mp_magnitude_q <= {1'b0, mp_magnitude_q[15:1]};
					mp_x_term_q <= mp_x_term_q <<< 1;
					mp_y_term_q <= mp_y_term_q <<< 1;
					if (mp_step_q == 4'd15) begin
						state_q <= STATE_SEED;
					end else begin
						mp_step_q <= mp_step_q + 4'd1;
					end
				end

				STATE_SEED: begin
					left_x_accumulator_o <= row_mp_q[15] ?
						selected_x_seed_w : mx_seed_q;
					left_y_accumulator_o <= row_mp_q[15] ?
						selected_y_seed_w : my_seed_q;
					right_x_accumulator_o <= row_mp_q[15] ?
						mx_seed_q : selected_x_seed_w;
					right_y_accumulator_o <= row_mp_q[15] ?
						my_seed_q : selected_y_seed_w;
					pixel_ordinal_q <= 10'd0;
					if (!seed_coordinate_range_valid_w)
						coordinate_range_error_o <= 1'b1;
					if (!selected_x_seed_fits_w ||
						!selected_y_seed_fits_w)
						accumulator_overflow_error_o <= 1'b1;
					state_q <= STATE_ACTIVE;
				end

				STATE_ACTIVE: begin
					if (pixel_retire_o) begin
						left_x_accumulator_o <= left_x_next_w;
						left_y_accumulator_o <= left_y_next_w;
						right_x_accumulator_o <= right_x_next_w;
						right_y_accumulator_o <= right_y_next_w;
						if (!current_coordinate_range_valid_o ||
							(!pixel_last_o &&
							 !next_coordinate_range_valid_w)) begin
							coordinate_range_error_o <= 1'b1;
						end
						if (recurrence_overflow_w)
							accumulator_overflow_error_o <= 1'b1;
						if (pixel_last_o) begin
							row_done_q <= 1'b1;
							state_q <= STATE_IDLE;
						end else begin
							pixel_ordinal_q <= pixel_ordinal_q + 10'd1;
						end
					end
				end

				default: begin
					state_q <= STATE_IDLE;
				end
			endcase
		end
	end

endmodule

`timescale 1ns/1ps

// Two-eye Affine sample transport.
//
// The first left-eye CELL read is an explicit two-CE row-setup prime. Once
// that registered cell is available, each configured pixel owns four logical
// CE slots:
//
//   state 0: accept left CHAR and right CELL reads
//   state 1: retire both responses through registered context
//   state 2: accept right CHAR and the next pixel's left CELL read
//   state 3: retire both responses and accept one stereo result
//
// The last pixel skips the next left CELL read, giving exactly 4W CE after the
// prime. One address stage forms the next CELL and current character addresses.

module vip_xp_affine_sample_pipeline
#(
	parameter integer GENERATION_WIDTH = 8,
	// Shared mode uses the single background-address block without another stage.
	parameter integer EXTERNAL_ADDRESS_SEAM = 0
)
(
	input  wire                        clk_i,
	input  wire                        reset_i,
	input  wire                        ce_i,
	input  wire                        abort_i,

	// Held DDA pixel. The first primes the row; later pixels use one next slot.
	input  wire                        sample_valid_i,
	output wire                        sample_ready_o,
	output wire                        sample_accept_o,
	input  wire [9:0]                  sample_tag_i,
	input  wire                        sample_last_i,
	input  wire signed [16:0]          left_source_x_i,
	input  wire signed [16:0]          left_source_y_i,
	input  wire signed [16:0]          right_source_x_i,
	input  wire signed [16:0]          right_source_y_i,

	// Capture row settings with the prime context.
	input  wire [3:0]                  maps_wide_i,
	input  wire [3:0]                  maps_high_i,
	input  wire [3:0]                  effective_map_columns_i,
	input  wire [3:0]                  bgmap_base_rounded_i,
	input  wire                        over_i,
	input  wire [15:0]                 overplane_i,
	input  wire [31:0]                 gplt_active_i,

	// Held query to the shared background-address block.
	output wire signed [16:0]          address_source_x_o,
	output wire signed [16:0]          address_source_y_o,
	output wire [3:0]                  address_maps_wide_o,
	output wire [3:0]                  address_maps_high_o,
	output wire [3:0]                  address_effective_map_columns_o,
	output wire [3:0]                  address_bgmap_base_rounded_o,
	output wire                        address_over_o,
	output wire [15:0]                 address_overplane_o,
	output wire [15:0]                 address_cell_o,
	output wire [2:0]                  address_cell_source_row_o,
	// Same-cycle shared address result.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [15:0]                 addressed_dram_cell_addr_i,
	input  wire                        addressed_overplane_selected_i,
	input  wire                        addressed_strict_overplane_i,
	input  wire                        addressed_map_index_overflow_i,
	input  wire [15:0]                 addressed_vrm_character_row_addr_i,
	input  wire [1:0]                  addressed_palette_i,
	input  wire                        addressed_hflip_i,
	input  wire                        addressed_vflip_i,
	/* verilator lint_on UNUSEDSIGNAL */

	// Held left or right character context for the shared decoder.
	output wire [15:0]                 decode_character_row_o,
	output wire [1:0]                  decode_palette_o,
	output wire                        decode_hflip_o,
	output wire [2:0]                  decode_source_x_index_o,
	output wire [31:0]                 decode_gplt_active_o,
	input  wire [1:0]                  decoded_raw_pixel_i,
	input  wire                        decoded_raw_nonzero_i,
	input  wire [1:0]                  decoded_mapped_pixel_i,

	// CELL DRAM client.
	output wire                        dram_req_o,
	output wire [15:0]                 dram_addr_o,
	input  wire                        dram_accept_i,
	input  wire                        dram_resp_valid_i,
	input  wire [15:0]                 dram_resp_data_i,
	input  wire                        dram_router_cleanup_busy_i,
	input  wire                        dram_router_stale_discard_i,

	// Character-row VRM client.
	output wire                        vrm_req_o,
	output wire [15:0]                 vrm_addr_o,
	input  wire                        vrm_accept_i,
	input  wire                        vrm_resp_valid_i,
	input  wire [15:0]                 vrm_resp_data_i,
	input  wire                        vrm_router_cleanup_busy_i,
	input  wire                        vrm_router_stale_discard_i,

	// Hold stereo results until accepted, including through CE pauses.
	output wire                        result_valid_o,
	input  wire                        result_ready_i,
	output wire                        result_accept_o,
	output wire [9:0]                  result_tag_o,
	output wire                        result_last_o,
	output wire [15:0]                 result_left_cell_o,
	output wire [15:0]                 result_right_cell_o,
	output wire [15:0]                 result_left_character_row_o,
	output wire [15:0]                 result_right_character_row_o,
	output wire [1:0]                  result_left_palette_o,
	output wire [1:0]                  result_right_palette_o,
	output wire                        result_left_hflip_o,
	output wire                        result_right_hflip_o,
	output wire                        result_left_vflip_o,
	output wire                        result_right_vflip_o,
	output wire                        result_left_overplane_selected_o,
	output wire                        result_right_overplane_selected_o,
	output wire [1:0]                  result_left_raw_pixel_o,
	output wire [1:0]                  result_right_raw_pixel_o,
	output wire                        result_left_raw_nonzero_o,
	output wire                        result_right_raw_nonzero_o,
	output wire [1:0]                  result_left_mapped_pixel_o,
	output wire [1:0]                  result_right_mapped_pixel_o,

	// Timing, ownership, epoch, cleanup, and structural diagnostics.
	output wire                        prime_accept_o,
	output wire                        prime_complete_o,
	output wire                        pixel_window_active_o,
	output wire [3:0]                  state_o,
	output wire                        busy_o,
	output wire                        cleanup_busy_o,
	output wire                        quiescent_o,
	output wire                        next_context_valid_o,
	output wire                        dram_read_pending_o,
	output wire                        vrm_read_pending_o,
	output wire                        dram_response_capture_valid_o,
	output wire                        vrm_response_capture_valid_o,
	output wire [2:0]                  dram_request_owner_o,
	output wire [2:0]                  dram_pending_owner_o,
	output wire [2:0]                  vrm_request_owner_o,
	output wire [2:0]                  vrm_pending_owner_o,
	output wire [GENERATION_WIDTH-1:0] active_generation_o,
	output wire [GENERATION_WIDTH-1:0] dram_pending_generation_o,
	output wire [GENERATION_WIDTH-1:0] vrm_pending_generation_o,
	output reg                         dram_stale_response_discarded_o,
	output reg                         vrm_stale_response_discarded_o,
	output reg                         unexpected_dram_response_o,
	output reg                         unexpected_vrm_response_o,
	output reg                         response_capture_overflow_o,
	output reg                         pending_owner_mismatch_o,
	output reg                         accept_without_request_o,
	output reg                         static_context_mismatch_o,
	output reg                         sample_tag_sequence_error_o,
	output reg                         strict_overplane_seen_o,
	output reg                         map_index_overflow_seen_o
);

	localparam [3:0]
		STATE_IDLE          = 4'd0,
		STATE_PRIME_REQUEST = 4'd1,
		STATE_PRIME_WAIT    = 4'd2,
		STATE_STAGE0        = 4'd3,
		STATE_STAGE1        = 4'd4,
		STATE_STAGE2        = 4'd5,
		STATE_STAGE3        = 4'd6,
		STATE_DRAIN         = 4'd7;

	localparam [2:0]
		DRAM_OWNER_NONE      = 3'd0,
		DRAM_OWNER_PRIME_L   = 3'd1,
		DRAM_OWNER_RIGHT     = 3'd2,
		DRAM_OWNER_NEXT_L    = 3'd3;

	localparam [2:0]
		VRM_OWNER_NONE       = 3'd0,
		VRM_OWNER_LEFT_CHAR  = 3'd1,
		VRM_OWNER_RIGHT_CHAR = 3'd2;

	reg [3:0] state_q;

	reg current_valid_q;
	reg [9:0] current_tag_q;
	reg current_last_q;
	reg signed [16:0] current_left_x_q;
	reg signed [16:0] current_left_y_q;
	reg signed [16:0] current_right_x_q;
	reg signed [16:0] current_right_y_q;

	reg next_valid_q;
	reg [9:0] next_tag_q;
	reg next_last_q;
	reg signed [16:0] next_left_x_q;
	reg signed [16:0] next_left_y_q;
	reg signed [16:0] next_right_x_q;
	reg signed [16:0] next_right_y_q;

	reg [3:0] maps_wide_q;
	reg [3:0] maps_high_q;
	reg [3:0] effective_map_columns_q;
	reg [3:0] bgmap_base_rounded_q;
	reg over_q;
	reg [15:0] overplane_q;
	reg [31:0] gplt_active_q;

	reg [15:0] left_cell_q;
	reg [15:0] right_cell_q;
	reg [15:0] left_character_row_q;
	reg [1:0] left_palette_q;
	reg [1:0] right_palette_q;
	reg left_hflip_q;
	reg right_hflip_q;
	reg left_vflip_q;
	reg right_vflip_q;
	reg left_overplane_selected_q;
	reg right_overplane_selected_q;
	reg next_left_overplane_selected_q;
	reg [1:0] left_raw_pixel_q;
	reg left_raw_nonzero_q;
	reg [1:0] left_mapped_pixel_q;

	reg dram_pending_q;
	reg dram_pending_stale_q;
	reg [2:0] dram_pending_owner_q;
	reg [GENERATION_WIDTH-1:0] dram_pending_generation_q;
	reg dram_capture_valid_q;
	reg [15:0] dram_capture_data_q;

	reg vrm_pending_q;
	reg vrm_pending_stale_q;
	reg [2:0] vrm_pending_owner_q;
	reg [GENERATION_WIDTH-1:0] vrm_pending_generation_q;
	reg vrm_capture_valid_q;
	reg [15:0] vrm_capture_data_q;

	reg [GENERATION_WIDTH-1:0] active_generation_q;

	wire router_cleanup_busy_w = dram_router_cleanup_busy_i ||
		vrm_router_cleanup_busy_i;
	wire local_cleanup_busy_w = dram_pending_stale_q ||
		vrm_pending_stale_q || (state_q == STATE_DRAIN);

	wire idle_accept_window_w = (state_q == STATE_IDLE) &&
		!current_valid_q && !next_valid_q && !dram_pending_q &&
		!vrm_pending_q && !dram_capture_valid_q &&
		!vrm_capture_valid_q && !router_cleanup_busy_w;
	wire next_accept_window_w = current_valid_q && !current_last_q &&
		!next_valid_q && ((state_q == STATE_STAGE0) ||
		(state_q == STATE_STAGE1) || (state_q == STATE_STAGE2));

	assign sample_ready_o = ce_i && !reset_i && !abort_i &&
		(idle_accept_window_w || next_accept_window_w);
	assign sample_accept_o = sample_valid_i && sample_ready_o;
	assign prime_accept_o = sample_accept_o &&
		(state_q == STATE_IDLE);

	// One address stage serves CELL from coordinates and CHAR from registered CELL data.
	wire address_uses_live_prime_w = state_q == STATE_IDLE;
	wire address_uses_current_prime_w =
		state_q == STATE_PRIME_REQUEST;
	wire address_uses_right_w = state_q == STATE_STAGE0;
	wire address_uses_next_left_w = state_q == STATE_STAGE2;

	wire [15:0] address_dram_cell_w;
	wire address_overplane_selected_w;
	wire address_strict_overplane_w;
	wire address_map_index_overflow_w;
	wire [15:0] address_vrm_character_row_w;
	wire [1:0] address_palette_w;
	wire address_hflip_w;
	wire address_vflip_w;

	assign address_source_x_o =
		address_uses_live_prime_w ? left_source_x_i :
		address_uses_current_prime_w ? current_left_x_q :
		address_uses_right_w ? current_right_x_q :
		address_uses_next_left_w ?
			(current_last_q ? current_left_x_q : next_left_x_q) :
		current_left_x_q;
	assign address_source_y_o =
		address_uses_live_prime_w ? left_source_y_i :
		address_uses_current_prime_w ? current_left_y_q :
		address_uses_right_w ? current_right_y_q :
		address_uses_next_left_w ?
			(current_last_q ? current_left_y_q : next_left_y_q) :
		current_left_y_q;
	assign address_maps_wide_o = address_uses_live_prime_w ?
		maps_wide_i : maps_wide_q;
	assign address_maps_high_o = address_uses_live_prime_w ?
		maps_high_i : maps_high_q;
	assign address_effective_map_columns_o =
		address_uses_live_prime_w ? effective_map_columns_i :
		effective_map_columns_q;
	assign address_bgmap_base_rounded_o = address_uses_live_prime_w ?
		bgmap_base_rounded_i : bgmap_base_rounded_q;
	assign address_over_o = address_uses_live_prime_w ? over_i : over_q;
	assign address_overplane_o = address_uses_live_prime_w ?
		overplane_i : overplane_q;
	assign address_cell_o = address_uses_right_w ?
		left_cell_q : address_uses_next_left_w ? right_cell_q : 16'd0;
	assign address_cell_source_row_o = address_uses_right_w ?
		current_left_y_q[2:0] : current_right_y_q[2:0];

	generate
		if (EXTERNAL_ADDRESS_SEAM == 0) begin : g_local_address
			/* verilator lint_off PINCONNECTEMPTY */
			vip_xp_bg_address u_bg_address
			(
				.source_x_i(address_source_x_o),
				.source_y_i(address_source_y_o),
				.maps_wide_i(address_maps_wide_o),
				.maps_high_i(address_maps_high_o),
				.effective_map_columns_i(
					address_effective_map_columns_o),
				.bgmap_base_rounded_i(
					address_bgmap_base_rounded_o),
				.over_i(address_over_o),
				.overplane_i(address_overplane_o),
				.dram_cell_addr_o(address_dram_cell_w),
				.overplane_selected_o(
					address_overplane_selected_w),
				.strict_overplane_range_o(
					address_strict_overplane_w),
				.wrapped_source_x_o(),
				.wrapped_source_y_o(),
				.source_x_low_o(),
				.source_y_low_o(),
				.map_x_o(),
				.map_y_o(),
				.effective_map_x_o(),
				.map_index_o(),
				.map_index_overflow_o(
					address_map_index_overflow_w),
				.cell_x_o(),
				.cell_y_o(),
				.cell_i(address_cell_o),
				.cell_source_row_i(address_cell_source_row_o),
				.vrm_character_row_addr_o(
					address_vrm_character_row_w),
				.character_o(),
				.character_row_o(),
				.palette_o(address_palette_w),
				.hflip_o(address_hflip_w),
				.vflip_o(address_vflip_w)
			);
			/* verilator lint_on PINCONNECTEMPTY */
		end else begin : g_external_address
			assign address_dram_cell_w = addressed_dram_cell_addr_i;
			assign address_overplane_selected_w =
				addressed_overplane_selected_i;
			assign address_strict_overplane_w =
				addressed_strict_overplane_i;
			assign address_map_index_overflow_w =
				addressed_map_index_overflow_i;
			assign address_vrm_character_row_w =
				addressed_vrm_character_row_addr_i;
			assign address_palette_w = addressed_palette_i;
			assign address_hflip_w = addressed_hflip_i;
			assign address_vflip_w = addressed_vflip_i;
		end
	endgenerate

	wire prime_request_w = ((state_q == STATE_IDLE) && sample_valid_i &&
		idle_accept_window_w) || (state_q == STATE_PRIME_REQUEST);
	wire stage0_request_w = (state_q == STATE_STAGE0) &&
		current_valid_q;
	wire stage2_context_ready_w = current_last_q || next_valid_q;
	wire stage2_request_w = (state_q == STATE_STAGE2) &&
		current_valid_q && stage2_context_ready_w;

	wire [2:0] dram_request_owner_w = prime_request_w ?
		DRAM_OWNER_PRIME_L : stage0_request_w ?
		DRAM_OWNER_RIGHT : stage2_request_w && !current_last_q ?
		DRAM_OWNER_NEXT_L : DRAM_OWNER_NONE;
	wire [2:0] vrm_request_owner_w = stage0_request_w ?
		VRM_OWNER_LEFT_CHAR : stage2_request_w ?
		VRM_OWNER_RIGHT_CHAR : VRM_OWNER_NONE;

	assign dram_req_o = !reset_i && !abort_i &&
		!router_cleanup_busy_w && !dram_pending_q &&
		(dram_request_owner_w != DRAM_OWNER_NONE);
	assign dram_addr_o = address_dram_cell_w;
	assign vrm_req_o = !reset_i && !abort_i &&
		!router_cleanup_busy_w && !vrm_pending_q &&
		(vrm_request_owner_w != VRM_OWNER_NONE);
	assign vrm_addr_o = address_vrm_character_row_w;

	wire dram_accept_fire_w = ce_i && dram_req_o && dram_accept_i;
	wire vrm_accept_fire_w = ce_i && vrm_req_o && vrm_accept_i;

	wire [15:0] dram_response_data_w = dram_capture_valid_q ?
		dram_capture_data_q : dram_resp_data_i;
	wire [15:0] vrm_response_data_w = vrm_capture_valid_q ?
		vrm_capture_data_q : vrm_resp_data_i;
	wire dram_response_available_w = dram_capture_valid_q ||
		dram_resp_valid_i;
	wire vrm_response_available_w = vrm_capture_valid_q ||
		vrm_resp_valid_i;

	wire dram_generation_live_w =
		dram_pending_generation_q == active_generation_q;
	wire vrm_generation_live_w =
		vrm_pending_generation_q == active_generation_q;
	wire dram_live_available_w = dram_pending_q &&
		!dram_pending_stale_q && !abort_i && dram_generation_live_w &&
		dram_response_available_w;
	wire vrm_live_available_w = vrm_pending_q &&
		!vrm_pending_stale_q && !abort_i && vrm_generation_live_w &&
		vrm_response_available_w;

	wire prime_response_fire_w = ce_i &&
		(state_q == STATE_PRIME_WAIT) && dram_live_available_w &&
		(dram_pending_owner_q == DRAM_OWNER_PRIME_L);
	wire stage1_responses_ready_w =
		(state_q == STATE_STAGE1) && dram_live_available_w &&
		vrm_live_available_w &&
		(dram_pending_owner_q == DRAM_OWNER_RIGHT) &&
		(vrm_pending_owner_q == VRM_OWNER_LEFT_CHAR);
	wire stage1_response_fire_w = ce_i && stage1_responses_ready_w;
	wire stage3_responses_ready_w =
		(state_q == STATE_STAGE3) && vrm_live_available_w &&
		(vrm_pending_owner_q == VRM_OWNER_RIGHT_CHAR) &&
		(current_last_q || (dram_live_available_w &&
			(dram_pending_owner_q == DRAM_OWNER_NEXT_L)));

	assign result_valid_o = !reset_i && !abort_i &&
		stage3_responses_ready_w;
	assign result_accept_o = ce_i && result_valid_o && result_ready_i;
	assign prime_complete_o = prime_response_fire_w;

	wire dram_live_consume_w = prime_response_fire_w ||
		stage1_response_fire_w ||
		(result_accept_o && !current_last_q);
	wire vrm_live_consume_w = stage1_response_fire_w || result_accept_o;
	wire dram_stale_response_fire_w = ce_i && dram_pending_q &&
		(dram_pending_stale_q || abort_i) &&
		dram_response_available_w;
	wire vrm_stale_response_fire_w = ce_i && vrm_pending_q &&
		(vrm_pending_stale_q || abort_i) &&
		vrm_response_available_w;

	// Time-multiplex one character decoder between left state 1 and right state 3.
	wire decode_left_w = state_q == STATE_STAGE1;
	assign decode_character_row_o = vrm_response_data_w;
	assign decode_palette_o = decode_left_w ?
		left_palette_q : right_palette_q;
	assign decode_hflip_o = decode_left_w ?
		left_hflip_q : right_hflip_q;
	assign decode_source_x_index_o = decode_left_w ?
		current_left_x_q[2:0] : current_right_x_q[2:0];
	assign decode_gplt_active_o = gplt_active_q;

	assign result_tag_o = current_tag_q;
	assign result_last_o = current_last_q;
	assign result_left_cell_o = left_cell_q;
	assign result_right_cell_o = right_cell_q;
	assign result_left_character_row_o = left_character_row_q;
	assign result_right_character_row_o = vrm_response_data_w;
	assign result_left_palette_o = left_palette_q;
	assign result_right_palette_o = right_palette_q;
	assign result_left_hflip_o = left_hflip_q;
	assign result_right_hflip_o = right_hflip_q;
	assign result_left_vflip_o = left_vflip_q;
	assign result_right_vflip_o = right_vflip_q;
	assign result_left_overplane_selected_o =
		left_overplane_selected_q;
	assign result_right_overplane_selected_o =
		right_overplane_selected_q;
	assign result_left_raw_pixel_o = left_raw_pixel_q;
	assign result_right_raw_pixel_o = decoded_raw_pixel_i;
	assign result_left_raw_nonzero_o = left_raw_nonzero_q;
	assign result_right_raw_nonzero_o = decoded_raw_nonzero_i;
	assign result_left_mapped_pixel_o = left_mapped_pixel_q;
	assign result_right_mapped_pixel_o = decoded_mapped_pixel_i;

	assign pixel_window_active_o = (state_q == STATE_STAGE0) ||
		(state_q == STATE_STAGE1) || (state_q == STATE_STAGE2) ||
		(state_q == STATE_STAGE3);
	assign state_o = state_q;
	assign busy_o = (state_q != STATE_IDLE) || current_valid_q ||
		next_valid_q || dram_pending_q || vrm_pending_q ||
		dram_capture_valid_q || vrm_capture_valid_q ||
		router_cleanup_busy_w;
	assign cleanup_busy_o = router_cleanup_busy_w || local_cleanup_busy_w;
	assign quiescent_o = (state_q == STATE_IDLE) && !current_valid_q &&
		!next_valid_q && !dram_pending_q && !vrm_pending_q &&
		!dram_capture_valid_q && !vrm_capture_valid_q &&
		!router_cleanup_busy_w;
	assign next_context_valid_o = next_valid_q;
	assign dram_read_pending_o = dram_pending_q;
	assign vrm_read_pending_o = vrm_pending_q;
	assign dram_response_capture_valid_o = dram_capture_valid_q;
	assign vrm_response_capture_valid_o = vrm_capture_valid_q;
	assign dram_request_owner_o = dram_req_o ?
		dram_request_owner_w : DRAM_OWNER_NONE;
	assign dram_pending_owner_o = dram_pending_q ?
		dram_pending_owner_q : DRAM_OWNER_NONE;
	assign vrm_request_owner_o = vrm_req_o ?
		vrm_request_owner_w : VRM_OWNER_NONE;
	assign vrm_pending_owner_o = vrm_pending_q ?
		vrm_pending_owner_q : VRM_OWNER_NONE;
	assign active_generation_o = active_generation_q;
	assign dram_pending_generation_o = dram_pending_generation_q;
	assign vrm_pending_generation_o = vrm_pending_generation_q;

	wire stage0_requests_complete_w =
		(dram_pending_q || dram_accept_fire_w) &&
		(vrm_pending_q || vrm_accept_fire_w);
	wire stage2_requests_complete_w =
		(current_last_q || dram_pending_q || dram_accept_fire_w) &&
		(vrm_pending_q || vrm_accept_fire_w);
	wire [GENERATION_WIDTH-1:0] next_generation_w =
		active_generation_q +
		{{(GENERATION_WIDTH-1){1'b0}}, 1'b1};

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			current_valid_q <= 1'b0;
			current_tag_q <= 10'd0;
			current_last_q <= 1'b0;
			current_left_x_q <= 17'sd0;
			current_left_y_q <= 17'sd0;
			current_right_x_q <= 17'sd0;
			current_right_y_q <= 17'sd0;
			next_valid_q <= 1'b0;
			next_tag_q <= 10'd0;
			next_last_q <= 1'b0;
			next_left_x_q <= 17'sd0;
			next_left_y_q <= 17'sd0;
			next_right_x_q <= 17'sd0;
			next_right_y_q <= 17'sd0;
			maps_wide_q <= 4'd1;
			maps_high_q <= 4'd1;
			effective_map_columns_q <= 4'd1;
			bgmap_base_rounded_q <= 4'd0;
			over_q <= 1'b0;
			overplane_q <= 16'd0;
			gplt_active_q <= 32'd0;
			left_cell_q <= 16'd0;
			right_cell_q <= 16'd0;
			left_character_row_q <= 16'd0;
			left_palette_q <= 2'd0;
			right_palette_q <= 2'd0;
			left_hflip_q <= 1'b0;
			right_hflip_q <= 1'b0;
			left_vflip_q <= 1'b0;
			right_vflip_q <= 1'b0;
			left_overplane_selected_q <= 1'b0;
			right_overplane_selected_q <= 1'b0;
			next_left_overplane_selected_q <= 1'b0;
			left_raw_pixel_q <= 2'd0;
			left_raw_nonzero_q <= 1'b0;
			left_mapped_pixel_q <= 2'd0;
			dram_pending_q <= 1'b0;
			dram_pending_stale_q <= 1'b0;
			dram_pending_owner_q <= DRAM_OWNER_NONE;
			dram_pending_generation_q <=
				{GENERATION_WIDTH{1'b0}};
			dram_capture_valid_q <= 1'b0;
			dram_capture_data_q <= 16'd0;
			vrm_pending_q <= 1'b0;
			vrm_pending_stale_q <= 1'b0;
			vrm_pending_owner_q <= VRM_OWNER_NONE;
			vrm_pending_generation_q <=
				{GENERATION_WIDTH{1'b0}};
			vrm_capture_valid_q <= 1'b0;
			vrm_capture_data_q <= 16'd0;
			active_generation_q <= {GENERATION_WIDTH{1'b0}};
			dram_stale_response_discarded_o <= 1'b0;
			vrm_stale_response_discarded_o <= 1'b0;
			unexpected_dram_response_o <= 1'b0;
			unexpected_vrm_response_o <= 1'b0;
			response_capture_overflow_o <= 1'b0;
			pending_owner_mismatch_o <= 1'b0;
			accept_without_request_o <= 1'b0;
			static_context_mismatch_o <= 1'b0;
			sample_tag_sequence_error_o <= 1'b0;
			strict_overplane_seen_o <= 1'b0;
			map_index_overflow_seen_o <= 1'b0;
		end else begin
			dram_stale_response_discarded_o <= 1'b0;
			vrm_stale_response_discarded_o <= 1'b0;

			if (dram_router_stale_discard_i) begin
				if (!dram_pending_q) begin
					unexpected_dram_response_o <= 1'b1;
				end
				dram_pending_q <= 1'b0;
				dram_pending_stale_q <= 1'b0;
				dram_pending_owner_q <= DRAM_OWNER_NONE;
				dram_capture_valid_q <= 1'b0;
				dram_stale_response_discarded_o <= 1'b1;
			end
			if (vrm_router_stale_discard_i) begin
				if (!vrm_pending_q) begin
					unexpected_vrm_response_o <= 1'b1;
				end
				vrm_pending_q <= 1'b0;
				vrm_pending_stale_q <= 1'b0;
				vrm_pending_owner_q <= VRM_OWNER_NONE;
				vrm_capture_valid_q <= 1'b0;
				vrm_stale_response_discarded_o <= 1'b1;
			end

			// Save raw responses until their state can consume them.
			if (dram_resp_valid_i && !dram_router_stale_discard_i) begin
				if (!dram_pending_q) begin
					unexpected_dram_response_o <= 1'b1;
				end else if (dram_capture_valid_q) begin
					response_capture_overflow_o <= 1'b1;
				end else if (!dram_live_consume_w &&
					!dram_stale_response_fire_w) begin
					dram_capture_valid_q <= 1'b1;
					dram_capture_data_q <= dram_resp_data_i;
				end
			end
			if (vrm_resp_valid_i && !vrm_router_stale_discard_i) begin
				if (!vrm_pending_q) begin
					unexpected_vrm_response_o <= 1'b1;
				end else if (vrm_capture_valid_q) begin
					response_capture_overflow_o <= 1'b1;
				end else if (!vrm_live_consume_w &&
					!vrm_stale_response_fire_w) begin
					vrm_capture_valid_q <= 1'b1;
					vrm_capture_data_q <= vrm_resp_data_i;
				end
			end

			// Raw abort drops offers and keeps accepted owners only for cleanup.
			if (abort_i) begin
				current_valid_q <= 1'b0;
				next_valid_q <= 1'b0;
				if (dram_pending_q) begin
					dram_pending_stale_q <= 1'b1;
				end
				if (vrm_pending_q) begin
					vrm_pending_stale_q <= 1'b1;
				end
				state_q <= (dram_pending_q || vrm_pending_q) ?
					STATE_DRAIN : STATE_IDLE;
			end

			if (ce_i) begin
				if (dram_accept_i && !dram_req_o) begin
					accept_without_request_o <= 1'b1;
				end
				if (vrm_accept_i && !vrm_req_o) begin
					accept_without_request_o <= 1'b1;
				end

				if (dram_stale_response_fire_w) begin
					dram_pending_q <= 1'b0;
					dram_pending_stale_q <= 1'b0;
					dram_pending_owner_q <= DRAM_OWNER_NONE;
					dram_capture_valid_q <= 1'b0;
					dram_stale_response_discarded_o <= 1'b1;
				end
				if (vrm_stale_response_fire_w) begin
					vrm_pending_q <= 1'b0;
					vrm_pending_stale_q <= 1'b0;
					vrm_pending_owner_q <= VRM_OWNER_NONE;
					vrm_capture_valid_q <= 1'b0;
					vrm_stale_response_discarded_o <= 1'b1;
				end

				if (!abort_i) begin
					if (sample_accept_o) begin
						if (state_q == STATE_IDLE) begin
							current_valid_q <= 1'b1;
							current_tag_q <= sample_tag_i;
							current_last_q <= sample_last_i;
							current_left_x_q <= left_source_x_i;
							current_left_y_q <= left_source_y_i;
							current_right_x_q <= right_source_x_i;
							current_right_y_q <= right_source_y_i;
							maps_wide_q <= maps_wide_i;
							maps_high_q <= maps_high_i;
							effective_map_columns_q <=
								effective_map_columns_i;
							bgmap_base_rounded_q <=
								bgmap_base_rounded_i;
							over_q <= over_i;
							overplane_q <= overplane_i;
							gplt_active_q <= gplt_active_i;
							active_generation_q <= next_generation_w;
							left_overplane_selected_q <=
								address_overplane_selected_w;
							if (address_strict_overplane_w) begin
								strict_overplane_seen_o <= 1'b1;
							end
							if (address_map_index_overflow_w) begin
								map_index_overflow_seen_o <= 1'b1;
							end
							if (dram_accept_fire_w) begin
								dram_pending_q <= 1'b1;
								dram_pending_stale_q <= 1'b0;
								dram_pending_owner_q <=
									DRAM_OWNER_PRIME_L;
								dram_pending_generation_q <=
									next_generation_w;
								state_q <= STATE_PRIME_WAIT;
							end else begin
								state_q <= STATE_PRIME_REQUEST;
							end
						end else begin
							next_valid_q <= 1'b1;
							next_tag_q <= sample_tag_i;
							next_last_q <= sample_last_i;
							next_left_x_q <= left_source_x_i;
							next_left_y_q <= left_source_y_i;
							next_right_x_q <= right_source_x_i;
							next_right_y_q <= right_source_y_i;
							if (sample_tag_i !=
								(current_tag_q + 10'd1)) begin
								sample_tag_sequence_error_o <= 1'b1;
							end
							if ((maps_wide_i != maps_wide_q) ||
								(maps_high_i != maps_high_q) ||
								(effective_map_columns_i !=
									effective_map_columns_q) ||
								(bgmap_base_rounded_i !=
									bgmap_base_rounded_q) ||
								(over_i != over_q) ||
								(overplane_i != overplane_q) ||
								(gplt_active_i != gplt_active_q)) begin
								static_context_mismatch_o <= 1'b1;
							end
						end
					end

					case (state_q)
						STATE_PRIME_REQUEST: begin
							if (dram_accept_fire_w) begin
								dram_pending_q <= 1'b1;
								dram_pending_stale_q <= 1'b0;
								dram_pending_owner_q <=
									DRAM_OWNER_PRIME_L;
								dram_pending_generation_q <=
									active_generation_q;
								state_q <= STATE_PRIME_WAIT;
							end
						end

						STATE_PRIME_WAIT: begin
							if (prime_response_fire_w) begin
								dram_pending_q <= 1'b0;
								dram_pending_owner_q <=
									DRAM_OWNER_NONE;
								dram_capture_valid_q <= 1'b0;
								left_cell_q <= dram_response_data_w;
								state_q <= STATE_STAGE0;
							end else if (dram_live_available_w &&
								(dram_pending_owner_q !=
									DRAM_OWNER_PRIME_L)) begin
								pending_owner_mismatch_o <= 1'b1;
							end
						end

						STATE_STAGE0: begin
							if (dram_accept_fire_w) begin
								dram_pending_q <= 1'b1;
								dram_pending_stale_q <= 1'b0;
								dram_pending_owner_q <=
									DRAM_OWNER_RIGHT;
								dram_pending_generation_q <=
									active_generation_q;
								right_overplane_selected_q <=
									address_overplane_selected_w;
								if (address_strict_overplane_w) begin
									strict_overplane_seen_o <= 1'b1;
								end
								if (address_map_index_overflow_w) begin
									map_index_overflow_seen_o <= 1'b1;
								end
							end
							if (vrm_accept_fire_w) begin
								vrm_pending_q <= 1'b1;
								vrm_pending_stale_q <= 1'b0;
								vrm_pending_owner_q <=
									VRM_OWNER_LEFT_CHAR;
								vrm_pending_generation_q <=
									active_generation_q;
								left_palette_q <= address_palette_w;
								left_hflip_q <= address_hflip_w;
								left_vflip_q <= address_vflip_w;
							end
							if (stage0_requests_complete_w) begin
								state_q <= STATE_STAGE1;
							end
						end

						STATE_STAGE1: begin
							if (stage1_response_fire_w) begin
								dram_pending_q <= 1'b0;
								dram_pending_owner_q <=
									DRAM_OWNER_NONE;
								dram_capture_valid_q <= 1'b0;
								vrm_pending_q <= 1'b0;
								vrm_pending_owner_q <=
									VRM_OWNER_NONE;
								vrm_capture_valid_q <= 1'b0;
								right_cell_q <= dram_response_data_w;
								left_character_row_q <=
									vrm_response_data_w;
								left_raw_pixel_q <= decoded_raw_pixel_i;
								left_raw_nonzero_q <=
									decoded_raw_nonzero_i;
								left_mapped_pixel_q <=
									decoded_mapped_pixel_i;
								state_q <= STATE_STAGE2;
							end else if ((dram_live_available_w &&
								(dram_pending_owner_q !=
									DRAM_OWNER_RIGHT)) ||
								(vrm_live_available_w &&
								(vrm_pending_owner_q !=
									VRM_OWNER_LEFT_CHAR))) begin
								pending_owner_mismatch_o <= 1'b1;
							end
						end

						STATE_STAGE2: begin
							if (dram_accept_fire_w) begin
								dram_pending_q <= 1'b1;
								dram_pending_stale_q <= 1'b0;
								dram_pending_owner_q <=
									DRAM_OWNER_NEXT_L;
								dram_pending_generation_q <=
									active_generation_q;
								next_left_overplane_selected_q <=
									address_overplane_selected_w;
								if (address_strict_overplane_w) begin
									strict_overplane_seen_o <= 1'b1;
								end
								if (address_map_index_overflow_w) begin
									map_index_overflow_seen_o <= 1'b1;
								end
							end
							if (vrm_accept_fire_w) begin
								vrm_pending_q <= 1'b1;
								vrm_pending_stale_q <= 1'b0;
								vrm_pending_owner_q <=
									VRM_OWNER_RIGHT_CHAR;
								vrm_pending_generation_q <=
									active_generation_q;
								right_palette_q <= address_palette_w;
								right_hflip_q <= address_hflip_w;
								right_vflip_q <= address_vflip_w;
							end
							if (stage2_requests_complete_w) begin
								state_q <= STATE_STAGE3;
							end
						end

						STATE_STAGE3: begin
							if (result_accept_o) begin
								vrm_pending_q <= 1'b0;
								vrm_pending_owner_q <=
									VRM_OWNER_NONE;
								vrm_capture_valid_q <= 1'b0;
								if (current_last_q) begin
									current_valid_q <= 1'b0;
									next_valid_q <= 1'b0;
									state_q <= STATE_IDLE;
								end else begin
									dram_pending_q <= 1'b0;
									dram_pending_owner_q <=
										DRAM_OWNER_NONE;
									dram_capture_valid_q <= 1'b0;
									current_tag_q <= next_tag_q;
									current_last_q <= next_last_q;
									current_left_x_q <= next_left_x_q;
									current_left_y_q <= next_left_y_q;
									current_right_x_q <= next_right_x_q;
									current_right_y_q <= next_right_y_q;
									left_cell_q <= dram_response_data_w;
									left_overplane_selected_q <=
										next_left_overplane_selected_q;
									next_valid_q <= 1'b0;
									state_q <= STATE_STAGE0;
								end
							end else if ((vrm_live_available_w &&
								(vrm_pending_owner_q !=
									VRM_OWNER_RIGHT_CHAR)) ||
								(!current_last_q &&
								dram_live_available_w &&
								(dram_pending_owner_q !=
									DRAM_OWNER_NEXT_L))) begin
								pending_owner_mismatch_o <= 1'b1;
							end
						end

						STATE_DRAIN: begin
							if (!dram_pending_q && !vrm_pending_q &&
								!dram_capture_valid_q &&
								!vrm_capture_valid_q &&
								!router_cleanup_busy_w) begin
								state_q <= STATE_IDLE;
							end
						end

						default: begin
						end
					endcase
				end
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Streaming four-pixel Affine packer.
//
// Prepare row storage at slots 0 and 4. Commit at slot 3, slot 7, or row end,
// including the current sample so no packer tail remains.
//
// Results wait for prepare. Clipping controls active masks, eye enables control
// each eye, and raw zero controls transparency.

module vip_xp_affine_pixel_packer
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	// Prepare at four-pixel half starts; group starts are eight-pixel aligned.
	input  wire                 prepare_valid_i,
	output wire                 prepare_ready_o,
	output wire                 prepare_accept_o,
	input  wire [4:0]           prepare_world_i,
	input  wire [4:0]           prepare_strip_i,
	input  wire [8:0]           prepare_screen_y_i,
	input  wire [15:0]          prepare_local_y_i,
	input  wire [9:0]           prepare_group_start_i,
	input  wire [9:0]           prepare_half_start_i,
	input  wire signed [15:0]   prepare_gx_i,
	input  wire signed [15:0]   prepare_gp_i,
	input  wire                 prepare_left_on_i,
	input  wire                 prepare_right_on_i,

	// Held row-store prepare context.
	output wire                 half_context_valid_o,
	input  wire                 half_context_ready_i,
	output wire                 half_context_accept_o,
	output wire [4:0]           half_context_world_o,
	output wire [4:0]           half_context_strip_o,
	output wire [8:0]           half_context_screen_y_o,
	output wire [15:0]          half_context_local_y_o,
	output wire [9:0]           half_context_group_start_o,
	output wire [9:0]           half_context_start_o,
	output wire                 half_context_second_o,
	output wire [2:0]           half_context_row_o,
	output wire signed [15:0]   half_context_left_base_x_o,
	output wire                 half_context_left_enable_o,
	output wire signed [15:0]   half_context_right_base_x_o,
	output wire                 half_context_right_enable_o,

	// Held stereo result tagged to its prepare owner.
	input  wire                 input_valid_i,
	output wire                 input_ready_o,
	output wire                 input_accept_o,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [4:0]           input_world_i,
	input  wire [4:0]           input_strip_i,
	input  wire [8:0]           input_screen_y_i,
	input  wire [15:0]          input_local_y_i,
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire [9:0]           input_ordinal_i,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [9:0]           input_group_start_i,
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire                 input_last_i,
	input  wire                 input_left_raw_nonzero_i,
	input  wire [1:0]           input_left_mapped_i,
	input  wire                 input_right_raw_nonzero_i,
	input  wire [1:0]           input_right_mapped_i,

	// Commit at slot 3, slot 7, or partial row end with the current sample.
	output wire                 half_commit_valid_o,
	input  wire                 half_commit_ready_i,
	output wire                 half_commit_accept_o,
	output wire [4:0]           half_commit_world_o,
	output wire [4:0]           half_commit_strip_o,
	output wire [8:0]           half_commit_screen_y_o,
	output wire [15:0]          half_commit_local_y_o,
	output wire [9:0]           half_commit_group_start_o,
	output wire [9:0]           half_commit_start_o,
	output wire                 half_commit_second_o,
	output wire                 half_commit_last_o,
	output wire [2:0]           half_commit_row_o,
	output wire                 half_commit_left_enable_o,
	output wire [3:0]           half_commit_left_active_o,
	output wire [3:0]           half_commit_left_opaque_o,
	output wire [7:0]           half_commit_left_values_o,
	output wire                 half_commit_right_enable_o,
	output wire [3:0]           half_commit_right_active_o,
	output wire [3:0]           half_commit_right_opaque_o,
	output wire [7:0]           half_commit_right_values_o,

	output wire                 prepared_valid_o,
	output wire [1:0]           next_slot_o,
	output wire                 busy_o,
	output wire                 quiescent_o,
`ifndef SYNTHESIS
	output reg  [31:0]          diag_prepare_accept_count_o,
	output reg  [31:0]          diag_input_accept_count_o,
	output reg  [31:0]          diag_commit_accept_count_o,
	output reg                  prepare_alignment_error_o,
	output reg                  result_without_prepare_o,
	output reg                  ordinal_sequence_error_o,
	output reg                  ownership_mismatch_o
`else
	output wire [31:0]          diag_prepare_accept_count_o,
	output wire [31:0]          diag_input_accept_count_o,
	output wire [31:0]          diag_commit_accept_count_o,
	output wire                 prepare_alignment_error_o,
	output wire                 result_without_prepare_o,
	output wire                 ordinal_sequence_error_o,
	output wire                 ownership_mismatch_o
`endif
);

	reg prepared_valid_q;
	reg [4:0] prepared_world_q;
	reg [4:0] prepared_strip_q;
	reg [8:0] prepared_screen_y_q;
	reg [15:0] prepared_local_y_q;
	reg [9:0] prepared_group_start_q;
	reg [9:0] prepared_half_start_q;
	reg signed [15:0] prepared_gx_q;
	reg signed [15:0] prepared_gp_q;
	reg prepared_left_on_q;
	reg prepared_right_on_q;
	reg [2:0] accepted_sample_count_q;
	reg [3:0] build_left_active_q;
	reg [3:0] build_left_opaque_q;
	reg [7:0] build_left_values_q;
	reg [3:0] build_right_active_q;
	reg [3:0] build_right_opaque_q;
	reg [7:0] build_right_values_q;

	function automatic [3:0] set_flag_fn;
		input [3:0] flags_v;
		input [1:0] slot_v;
		input value_v;
		reg [3:0] slot_mask_t;
		begin
			slot_mask_t = 4'b0001 << slot_v;
			set_flag_fn = (flags_v & ~slot_mask_t) |
				(value_v ? slot_mask_t : 4'd0);
		end
	endfunction

	function automatic [7:0] set_value_fn;
		input [7:0] values_v;
		input [1:0] slot_v;
		input [1:0] value_v;
		reg [7:0] value_mask_t;
		reg [2:0] value_shift_t;
		begin
			value_shift_t = {slot_v, 1'b0};
			value_mask_t = 8'h03 << value_shift_t;
			set_value_fn = (values_v & ~value_mask_t) |
				({6'd0, value_v} << value_shift_t);
		end
	endfunction

	// Set half ownership when row-store prepare accepts.
	assign half_context_valid_o = !reset_i && !abort_i &&
		!prepared_valid_q && prepare_valid_i;
	assign prepare_ready_o = ce_i && !reset_i && !abort_i &&
		!prepared_valid_q && half_context_ready_i;
	assign prepare_accept_o = prepare_valid_i && prepare_ready_o;
	assign half_context_accept_o = ce_i && half_context_valid_o &&
		half_context_ready_i;

	wire signed [17:0] prepare_gx_extended_w =
		{{2{prepare_gx_i[15]}}, prepare_gx_i};
	wire signed [17:0] prepare_gp_extended_w =
		{{2{prepare_gp_i[15]}}, prepare_gp_i};
	wire signed [17:0] prepare_half_start_extended_w =
		$signed({8'd0, prepare_half_start_i});
	// GP shifts destination X only: left GX-GP+i, right GX+GP+i.
	/* verilator lint_off UNUSEDSIGNAL */
	wire signed [17:0] context_left_base_w =
		prepare_gx_extended_w - prepare_gp_extended_w +
		prepare_half_start_extended_w;
	wire signed [17:0] context_right_base_w =
		prepare_gx_extended_w + prepare_gp_extended_w +
		prepare_half_start_extended_w;
	/* verilator lint_on UNUSEDSIGNAL */

	assign half_context_world_o = prepare_world_i;
	assign half_context_strip_o = prepare_strip_i;
	assign half_context_screen_y_o = prepare_screen_y_i;
	assign half_context_local_y_o = prepare_local_y_i;
	assign half_context_group_start_o = prepare_group_start_i;
	assign half_context_start_o = prepare_half_start_i;
	assign half_context_second_o = prepare_half_start_i[2];
	assign half_context_row_o = prepare_screen_y_i[2:0];
	assign half_context_left_base_x_o = context_left_base_w[15:0];
	assign half_context_left_enable_o = prepare_left_on_i;
	assign half_context_right_base_x_o = context_right_base_w[15:0];
	assign half_context_right_enable_o = prepare_right_on_i;

	wire [1:0] input_half_slot_w = input_ordinal_i[1:0];
	wire input_commit_needed_w =
		(input_half_slot_w == 2'd3) || input_last_i;
`ifndef SYNTHESIS
	wire [10:0] expected_ordinal_w =
		{1'b0, prepared_half_start_q} +
		{8'd0, accepted_sample_count_q};
`endif

	assign input_ready_o = ce_i && !reset_i && !abort_i &&
		prepared_valid_q &&
		(!input_commit_needed_w || half_commit_ready_i);
	assign input_accept_o = input_valid_i && input_ready_o;
	assign half_commit_valid_o = !reset_i && !abort_i &&
		prepared_valid_q && input_valid_i && input_commit_needed_w;
	assign half_commit_accept_o = ce_i && half_commit_valid_o &&
		half_commit_ready_i;

	wire signed [17:0] prepared_gx_extended_w =
		{{2{prepared_gx_q[15]}}, prepared_gx_q};
	wire signed [17:0] prepared_gp_extended_w =
		{{2{prepared_gp_q[15]}}, prepared_gp_q};
	wire signed [17:0] input_ordinal_extended_w =
		$signed({8'd0, input_ordinal_i});
	wire signed [17:0] left_destination_w =
		prepared_gx_extended_w - prepared_gp_extended_w +
		input_ordinal_extended_w;
	wire signed [17:0] right_destination_w =
		prepared_gx_extended_w + prepared_gp_extended_w +
		input_ordinal_extended_w;
	wire input_left_active_w =
		(left_destination_w >= 18'sd0) &&
		(left_destination_w < 18'sd384);
	wire input_right_active_w =
		(right_destination_w >= 18'sd0) &&
		(right_destination_w < 18'sd384);

	wire [3:0] next_left_active_w = set_flag_fn(
		build_left_active_q, input_half_slot_w, input_left_active_w);
	wire [3:0] next_left_opaque_w = set_flag_fn(
		build_left_opaque_q, input_half_slot_w,
		input_left_raw_nonzero_i);
	wire [7:0] next_left_values_w = set_value_fn(
		build_left_values_q, input_half_slot_w,
		input_left_mapped_i);
	wire [3:0] next_right_active_w = set_flag_fn(
		build_right_active_q, input_half_slot_w,
		input_right_active_w);
	wire [3:0] next_right_opaque_w = set_flag_fn(
		build_right_opaque_q, input_half_slot_w,
		input_right_raw_nonzero_i);
	wire [7:0] next_right_values_w = set_value_fn(
		build_right_values_q, input_half_slot_w,
		input_right_mapped_i);

	assign half_commit_world_o = prepared_world_q;
	assign half_commit_strip_o = prepared_strip_q;
	assign half_commit_screen_y_o = prepared_screen_y_q;
	assign half_commit_local_y_o = prepared_local_y_q;
	assign half_commit_group_start_o = prepared_group_start_q;
	assign half_commit_start_o = prepared_half_start_q;
	assign half_commit_second_o = prepared_half_start_q[2];
	assign half_commit_last_o = input_last_i;
	assign half_commit_row_o = prepared_screen_y_q[2:0];
	assign half_commit_left_enable_o = prepared_left_on_q;
	assign half_commit_left_active_o = next_left_active_w;
	assign half_commit_left_opaque_o = next_left_opaque_w;
	assign half_commit_left_values_o = next_left_values_w;
	assign half_commit_right_enable_o = prepared_right_on_q;
	assign half_commit_right_active_o = next_right_active_w;
	assign half_commit_right_opaque_o = next_right_opaque_w;
	assign half_commit_right_values_o = next_right_values_w;

	assign prepared_valid_o = prepared_valid_q;
	assign next_slot_o = accepted_sample_count_q[1:0];
	assign busy_o = prepared_valid_q;
	assign quiescent_o = !prepared_valid_q;

`ifdef SYNTHESIS
	assign diag_prepare_accept_count_o = 32'd0;
	assign diag_input_accept_count_o = 32'd0;
	assign diag_commit_accept_count_o = 32'd0;
	assign prepare_alignment_error_o = 1'b0;
	assign result_without_prepare_o = 1'b0;
	assign ordinal_sequence_error_o = 1'b0;
	assign ownership_mismatch_o = 1'b0;
`endif

	always @(posedge clk_i) begin
		if (reset_i) begin
			prepared_valid_q <= 1'b0;
			prepared_world_q <= 5'd0;
			prepared_strip_q <= 5'd0;
			prepared_screen_y_q <= 9'd0;
			prepared_local_y_q <= 16'd0;
			prepared_group_start_q <= 10'd0;
			prepared_half_start_q <= 10'd0;
			prepared_gx_q <= 16'sd0;
			prepared_gp_q <= 16'sd0;
			prepared_left_on_q <= 1'b0;
			prepared_right_on_q <= 1'b0;
			accepted_sample_count_q <= 3'd0;
			build_left_active_q <= 4'd0;
			build_left_opaque_q <= 4'd0;
			build_left_values_q <= 8'd0;
			build_right_active_q <= 4'd0;
			build_right_opaque_q <= 4'd0;
			build_right_values_q <= 8'd0;
`ifndef SYNTHESIS
			diag_prepare_accept_count_o <= 32'd0;
			diag_input_accept_count_o <= 32'd0;
			diag_commit_accept_count_o <= 32'd0;
			prepare_alignment_error_o <= 1'b0;
			result_without_prepare_o <= 1'b0;
			ordinal_sequence_error_o <= 1'b0;
			ownership_mismatch_o <= 1'b0;
`endif
		end else if (abort_i) begin
			prepared_valid_q <= 1'b0;
			accepted_sample_count_q <= 3'd0;
			build_left_active_q <= 4'd0;
			build_left_opaque_q <= 4'd0;
			build_left_values_q <= 8'd0;
			build_right_active_q <= 4'd0;
			build_right_opaque_q <= 4'd0;
			build_right_values_q <= 8'd0;
		end else if (ce_i) begin
			if (prepare_accept_o) begin
				prepared_valid_q <= 1'b1;
				prepared_world_q <= prepare_world_i;
				prepared_strip_q <= prepare_strip_i;
				prepared_screen_y_q <= prepare_screen_y_i;
				prepared_local_y_q <= prepare_local_y_i;
				prepared_group_start_q <= prepare_group_start_i;
				prepared_half_start_q <= prepare_half_start_i;
				prepared_gx_q <= prepare_gx_i;
				prepared_gp_q <= prepare_gp_i;
				prepared_left_on_q <= prepare_left_on_i;
				prepared_right_on_q <= prepare_right_on_i;
				accepted_sample_count_q <= 3'd0;
				build_left_active_q <= 4'd0;
				build_left_opaque_q <= 4'd0;
				build_left_values_q <= 8'd0;
				build_right_active_q <= 4'd0;
				build_right_opaque_q <= 4'd0;
				build_right_values_q <= 8'd0;
`ifndef SYNTHESIS
				diag_prepare_accept_count_o <=
					diag_prepare_accept_count_o + 32'd1;
				if ((prepare_half_start_i[1:0] != 2'd0) ||
					(prepare_group_start_i[2:0] != 3'd0) ||
					(prepare_group_start_i !=
					 {prepare_half_start_i[9:3], 3'b000})) begin
					prepare_alignment_error_o <= 1'b1;
				end
`endif
			end

			if (input_accept_o) begin
`ifndef SYNTHESIS
				diag_input_accept_count_o <=
					diag_input_accept_count_o + 32'd1;
				if (!prepared_valid_q) begin
					result_without_prepare_o <= 1'b1;
				end
				if ({1'b0, input_ordinal_i} !=
					expected_ordinal_w) begin
					ordinal_sequence_error_o <= 1'b1;
				end
				if ((input_world_i != prepared_world_q) ||
					(input_strip_i != prepared_strip_q) ||
					(input_screen_y_i != prepared_screen_y_q) ||
					(input_local_y_i != prepared_local_y_q) ||
					(input_group_start_i !=
					 prepared_group_start_q)) begin
					ownership_mismatch_o <= 1'b1;
				end
`endif

				if (input_commit_needed_w) begin
					prepared_valid_q <= 1'b0;
					accepted_sample_count_q <= 3'd0;
					build_left_active_q <= 4'd0;
					build_left_opaque_q <= 4'd0;
					build_left_values_q <= 8'd0;
					build_right_active_q <= 4'd0;
					build_right_opaque_q <= 4'd0;
					build_right_values_q <= 8'd0;
				end else begin
					accepted_sample_count_q <=
						accepted_sample_count_q + 3'd1;
					build_left_active_q <= next_left_active_w;
					build_left_opaque_q <= next_left_opaque_w;
					build_left_values_q <= next_left_values_w;
					build_right_active_q <= next_right_active_w;
					build_right_opaque_q <= next_right_opaque_w;
					build_right_values_q <= next_right_values_w;
				end
			end

`ifndef SYNTHESIS
			if (input_valid_i && !prepared_valid_q &&
				!prepare_accept_o) begin
				result_without_prepare_o <= 1'b1;
			end
			if (half_commit_accept_o) begin
				diag_commit_accept_count_o <=
					diag_commit_accept_count_o + 32'd1;
			end
`endif
		end
	end

endmodule

/* verilator lint_on DECLFILENAME */
