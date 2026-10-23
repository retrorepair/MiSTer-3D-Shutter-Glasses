// Copyright (c) 2026 Jamie Blanks

`timescale 1ns/1ps
/* verilator lint_off DECLFILENAME */

// Normal, H-bias, Affine, and Object renderers sharing one background pipeline.
// Kinds 0..3 select those modes in order. Accepted reads keep their owner.

module vip_render_subsystem
#(
	parameter integer COMPOSED_TIMING_CREDIT_ENABLE = 0
)
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire [2:0]           parallax_scale_i,

	input  wire                 engine_cmd_valid_i,
	output wire                 engine_cmd_ready_o,
	input  wire [1:0]           engine_cmd_kind_i,
	input  wire [4:0]           engine_cmd_strip_i,
	input  wire [4:0]           engine_cmd_world_i,
	input  wire [255:0]         engine_cmd_descriptor_i,
	input  wire                 engine_cmd_first_visit_i,
	output wire                 engine_done_o,
	input  wire                 engine_abort_i,
	input  wire [31:0]          gplt_active_i,
	input  wire [39:0]          spt_active_i,
	input  wire [31:0]          jplt_active_i,

	// Shared VIP DRAM read channel.
	output wire                 aggregate_dram_abort_o,
	output wire                 aggregate_dram_req_o,
	output wire [15:0]          aggregate_dram_addr_o,
	input  wire                 aggregate_dram_accept_i,
	input  wire                 aggregate_dram_resp_valid_i,
	input  wire [15:0]          aggregate_dram_resp_data_i,
	input  wire                 aggregate_dram_cleanup_busy_i,
	input  wire                 aggregate_dram_stale_discard_i,

	// Shared character-row VRM channel.
	output wire                 aggregate_vrm_abort_o,
	output wire                 aggregate_vrm_req_o,
	output wire [15:0]          aggregate_vrm_addr_o,
	input  wire                 aggregate_vrm_accept_i,
	input  wire                 aggregate_vrm_resp_valid_i,
	input  wire [15:0]          aggregate_vrm_resp_data_i,
	input  wire                 aggregate_vrm_cleanup_busy_i,
	input  wire                 aggregate_vrm_stale_discard_i,

	// Normal and H-bias row token.
	output wire                 row_producer_valid_o,
	input  wire                 row_producer_ready_i,
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

	// Affine row-store input and raw XPRST abort.
	output wire                 affine_abort_o,
	output wire                 affine_prepare_valid_o,
	input  wire                 affine_prepare_ready_i,
	output wire                 affine_prepare_accept_o,
	output wire [2:0]           affine_prepare_row_o,
	output wire signed [15:0]   affine_prepare_left_base_x_o,
	output wire                 affine_prepare_left_enable_o,
	output wire signed [15:0]   affine_prepare_right_base_x_o,
	output wire                 affine_prepare_right_enable_o,
	output wire                 affine_commit_valid_o,
	input  wire                 affine_commit_ready_i,
	output wire                 affine_commit_accept_o,
	output wire [3:0]           affine_commit_left_active_o,
	output wire [3:0]           affine_commit_left_opaque_o,
	output wire [7:0]           affine_commit_left_values_o,
	output wire [3:0]           affine_commit_right_active_o,
	output wire [3:0]           affine_commit_right_opaque_o,
	output wire [7:0]           affine_commit_right_values_o,
	input  wire                 affine_store_quiescent_i,

	// Active command and completion state.
	output wire                 command_active_o,
	output wire [1:0]           command_kind_o,
	output wire [4:0]           command_strip_o,
	output wire [4:0]           command_world_o,
	output wire [255:0]         command_descriptor_o,
	output wire                 command_first_visit_o,
	output wire [31:0]          command_gplt_o,
	output wire                 completion_pending_o,
	output wire                 global_quiescent_o,
	output wire                 normal_child_done_o,
	output wire                 hbias_child_done_o,
	output wire                 affine_child_done_o,
	output wire                 object_child_done_o,
	output wire                 engine_cleanup_busy_o,

	// The remaining outputs below are simulation observability; vip_core
	// leaves them unconnected and only the standalone benches read them.

	// Child renderer progress.
	output wire                 normal_active_o,
	output wire                 normal_quiescent_o,
	output wire [3:0]           normal_scheduler_state_o,
	output wire [31:0]          normal_scheduler_elapsed_ticks_o,
	output wire [31:0]          normal_scheduler_tile_accept_count_o,
	output wire [31:0]          normal_scheduler_row_accept_count_o,
	output wire [1:0]           normal_producer_outstanding_o,
	output wire                 hbias_active_o,
	output wire                 hbias_quiescent_o,
	output wire [2:0]           hbias_scheduler_state_o,
	output wire [31:0]          hbias_scheduler_elapsed_ticks_o,
	output wire [15:0]          hbias_scheduler_row_accept_count_o,
	output wire [31:0]          hbias_scheduler_tile_accept_count_o,
	output wire [1:0]           hbias_producer_outstanding_o,

	// Affine progress and trace signals.
	output wire                 affine_active_o,
	output wire                 affine_reject_pulse_o,
	output wire                 affine_abort_done_pulse_o,
	output wire                 affine_invalid_width_reject_o,
	output wire                 affine_unaligned_param_reject_o,
	output wire                 affine_strict_policy_reject_o,
	output wire                 affine_descriptor_accept_o,
	output wire                 affine_descriptor_record_valid_o,
	output wire                 affine_descriptor_kind_mismatch_o,
	output wire                 affine_raw_w_upper_nonzero_o,
	output wire                 affine_raw_w_documented_range_high_o,
	output wire                 affine_raw_h_negative_o,
	output wire                 affine_raw_h_documented_range_high_o,
	output wire                 affine_strict_overplane_qualification_o,
	output wire                 affine_param_base_unaligned_o,
	output wire                 affine_malformed_descriptor_o,
	output wire                 affine_strict_policy_violation_o,
	output wire                 affine_work_behavior_unresolved_o,
	output wire                 affine_nonzero_mp_fault_o,
	output wire                 affine_nonzero_mp_policy_seen_o,
	output wire                 affine_raw_abort_seen_o,
	output wire                 affine_local_abort_active_o,
	output wire [2:0]           affine_scheduler_state_o,
	output wire [9:0]           affine_scheduler_ticks_remaining_o,
	output wire [9:0]           affine_scheduler_pixel_ordinal_o,
	output wire                 affine_scheduler_pixel_accept_o,
	output wire [3:0]           affine_sample_state_o,
	output wire                 affine_sample_prime_complete_o,
	output wire                 affine_sample_result_accept_o,
	output wire                 affine_packer_prepare_accept_o,
	output wire                 affine_packer_commit_accept_o,
	output wire                 affine_downstream_idle_o,
	output wire                 affine_final_will_be_idle_o,
	output wire                 affine_cleanup_interlock_o,
	output wire                 affine_param_dram_selected_o,
	output wire [31:0]          affine_scheduler_elapsed_ticks_o,
	output wire [31:0]          affine_scheduler_row_setup_ticks_o,
	output wire [31:0]          affine_scheduler_pixel_ticks_o,
	output wire [31:0]          affine_scheduler_stall_ticks_o,
	output wire [15:0]          affine_scheduler_row_start_count_o,
	output wire [15:0]          affine_scheduler_row_context_count_o,
	output wire [31:0]          affine_scheduler_pixel_count_o,
	output wire                 affine_sample_strict_overplane_seen_o,
	output wire                 affine_sample_map_index_overflow_seen_o,

	// Active owner: 0 none, 1 Normal, 2 H-bias, 3 Affine, 4 Object.
	output wire [2:0]           dram_accepted_owner_o,
	output wire                 dram_offer_held_o,
	output wire [2:0]           dram_held_owner_o,
	output wire                 dram_read_pending_o,
	output wire [2:0]           dram_pending_owner_o,
	output wire [2:0]           vrm_accepted_owner_o,
	output wire                 vrm_offer_held_o,
	output wire [2:0]           vrm_held_owner_o,
	output wire                 vrm_read_pending_o,
	output wire [2:0]           vrm_pending_owner_o,
	output wire [1:0]           hbias_dram_accepted_owner_o,
	output wire                 hbias_dram_offer_held_o,
	output wire [1:0]           hbias_dram_held_owner_o,
	output wire                 hbias_dram_read_pending_o,
	output wire [1:0]           hbias_dram_pending_owner_o,

	// Ordinary row tokens use a two-entry owner FIFO.
	output wire [1:0]           row_owner_count_o,
	output wire [1:0]           row_owner_head_o,
	output wire [1:0]           row_owner_tail_o,
	output wire                 row_offer_held_o,
	output wire [1:0]           row_offer_owner_o,
	output wire                 normal_row_done_o,
	output wire                 hbias_row_done_o,
	output wire                 object_row_done_o,

	// Object progress and ownership.
	output wire                 object_active_o,
	output wire [3:0]           object_epoch_o,
	output wire [1:0]           object_group_o,
	output wire [5:0]           object_ordinal_o,
	output wire                 object_penalty_class_o,
	output wire [2:0]           object_scheduler_state_o,
	output wire [10:0]          object_scheduler_ticks_remaining_o,
	output wire [31:0]          object_scheduler_elapsed_ticks_o,
	output wire [15:0]          object_scheduler_fixed_ticks_o,
	output wire [31:0]          object_scheduler_probe_ticks_o,
	output wire [31:0]          object_scheduler_active_setup_ticks_o,
	output wire [31:0]          object_scheduler_continuation_ticks_o,
	output wire [31:0]          object_scheduler_row_ticks_o,
	output wire [31:0]          object_scheduler_underflow_ticks_o,
	output wire [31:0]          object_scheduler_transport_stall_ticks_o,
	output wire                 object_oam_pending_o,
	output wire                 object_char_pending_o,
	output wire                 object_decode_pending_o,
	output wire                 object_decode_accept_o,
	output wire                 object_transport_idle_o,
	output wire                 object_oam_stale_retire_o,
	output wire                 object_char_stale_retire_o,
	output wire [31:0]          object_oam_read_accept_count_o,
	output wire [31:0]          object_char_context_accept_count_o,
	output wire [31:0]          object_char_read_accept_count_o,
	output wire [31:0]          object_token_accept_count_o,
	output wire [31:0]          object_token_done_count_o,
	output wire                 object_group_overrun_o,
	output wire                 object_underflow_unresolved_o,
	output wire                 object_jy_behavior_unresolved_o,
	output wire                 object_ignored_oam_bits_nonzero_o,
	output wire                 object_error_o,

	// Composition diagnostics.
	output wire                 normal_error_o,
	output wire                 hbias_error_o,
	output wire                 affine_error_o,
	output wire                 normal_height_conflict_o,
	output wire                 hbias_strict_overplane_qualification_o,
	output wire                 hbias_raw_height_conflict_o,
	output wire                 hbias_source_conflict_o,
	output wire                 dram_protocol_error_o,
	output wire                 vrm_protocol_error_o,
	output wire                 row_protocol_error_o,
	output wire                 object_decode_mode_conflict_o,
	output wire                 external_decode_mode_conflict_o,
	output wire                 external_address_mode_conflict_o,
	output reg                  unexpected_completion_o,
	output reg                  engine_request_overlap_o,
	output wire                 protocol_error_o
);

	localparam [1:0]
		OWNER_NONE   = 2'd0,
		OWNER_NORMAL = 2'd1,
		OWNER_HBIAS  = 2'd2,
		OWNER_AFFINE = 2'd3;
	localparam [2:0]
		MODE_NONE   = 3'd0,
		MODE_NORMAL = 3'd1,
		MODE_HBIAS  = 3'd2,
		MODE_AFFINE = 3'd3,
		MODE_OBJECT = 3'd4;
	localparam [1:0]
		DRAM_OWNER_PARAM = 2'd1,
		DRAM_OWNER_CELL  = 2'd2;

	reg command_active_q;
	reg [1:0] command_kind_q;
	reg [4:0] command_strip_q;
	reg [4:0] command_world_q;
	reg [255:0] command_descriptor_q;
	reg command_first_visit_q;
	reg [31:0] command_gplt_q;
	reg [2:0] command_parallax_scale_q;
	reg completion_pending_q;

	wire signed [9:0] engine_cmd_gp_w =
		engine_cmd_descriptor_i[41:32];
	wire signed [14:0] engine_cmd_mp_w =
		engine_cmd_descriptor_i[94:80];
	wire signed [9:0] engine_cmd_scaled_gp_w;
	wire signed [14:0] engine_cmd_scaled_mp_w;
	reg [255:0] engine_cmd_scaled_descriptor_t;

	vip_stereo_scale_signed #(.WIDTH(10)) u_world_gp_scale
	(
		.value_i(engine_cmd_gp_w),
		.scale_i(parallax_scale_i),
		.value_o(engine_cmd_scaled_gp_w)
	);

	vip_stereo_scale_signed #(.WIDTH(15)) u_world_mp_scale
	(
		.value_i(engine_cmd_mp_w),
		.scale_i(parallax_scale_i),
		.value_o(engine_cmd_scaled_mp_w)
	);

	always @* begin
		engine_cmd_scaled_descriptor_t = engine_cmd_descriptor_i;
		engine_cmd_scaled_descriptor_t[41:32] =
			engine_cmd_scaled_gp_w;
		engine_cmd_scaled_descriptor_t[94:80] =
			engine_cmd_scaled_mp_w;
	end

	// Normal command and backend state.
	wire normal_cmd_valid_w;
	wire normal_cmd_ready_w;
	wire normal_done_w;
	wire normal_external_valid_w;
	wire normal_external_ready_w;
	wire [1:0] normal_external_kind_w;
	wire [4:0] normal_external_strip_w;
	wire [4:0] normal_external_world_w;
	wire [255:0] normal_external_descriptor_w;
	wire normal_external_first_visit_w;
	wire normal_external_done_w;
	wire normal_command_accept_w;
	wire [3:0] normal_bg_maps_wide_w;
	wire [3:0] normal_bg_maps_high_w;
	wire [3:0] normal_bg_effective_columns_w;
	wire [3:0] normal_bg_base_rounded_w;
	wire normal_bg_over_w;
	wire [15:0] normal_bg_overplane_w;
	wire normal_bg_left_on_w;
	wire normal_bg_right_on_w;
	wire signed [17:0] normal_bg_left_source_w;
	wire signed [17:0] normal_bg_right_source_w;
	wire signed [17:0] normal_bg_left_destination_w;
	wire signed [17:0] normal_bg_right_destination_w;
	wire [12:0] normal_bg_width_w;
	wire [31:0] normal_bg_gplt_w;
	wire normal_bg_result_permit_w;
	wire normal_bg_tile_row_valid_w;
	wire normal_bg_tile_row_ready_w;
	wire [0:0] normal_bg_tile_row_load_w;
	wire [8:0] normal_bg_tile_row_screen_y_w;
	wire signed [16:0] normal_bg_tile_row_source_y_w;
	wire normal_bg_tile_valid_w;
	wire normal_bg_tile_ready_w;
	wire [0:0] normal_bg_tile_load_w;
	wire [12:0] normal_bg_tile_ordinal_w;
	wire signed [15:0] normal_bg_tile_x_w;
	wire normal_bg_row_valid_w;
	wire normal_bg_row_ready_w;
	wire [0:0] normal_bg_row_load_w;
	wire [12:0] normal_bg_row_tile_ordinal_w;
	wire [2:0] normal_bg_row_ordinal_w;
	wire [2:0] normal_bg_row_source_index_w;
	wire [8:0] normal_bg_row_screen_y_w;
	wire signed [16:0] normal_bg_row_source_y_w;

	// H-bias command, PARAM reads, and row state.
	wire hbias_cmd_valid_w;
	wire hbias_cmd_ready_w;
	wire hbias_done_w;
	wire hbias_command_accept_w;
	wire hbias_scheduler_busy_w;
	wire hbias_pipeline_busy_w;
	wire hbias_pipeline_cleanup_busy_w;
	wire hbias_pipeline_downstream_idle_w;
	wire hbias_param_read_pending_w;
	wire hbias_param_req_w;
	wire [15:0] hbias_param_addr_w;
	wire hbias_param_accept_w;
	wire hbias_param_resp_valid_w;
	wire [15:0] hbias_param_resp_data_w;
	wire hbias_param_cleanup_busy_w;
	wire hbias_param_stale_discard_w;
	wire hbias_bg_rearm_w;
	wire hbias_bg_token_ready_w;
	wire hbias_bg_result_permit_w;
	wire [3:0] hbias_bg_maps_wide_w;
	wire [3:0] hbias_bg_maps_high_w;
	wire [3:0] hbias_bg_effective_columns_w;
	wire [3:0] hbias_bg_base_rounded_w;
	wire hbias_bg_over_w;
	wire [15:0] hbias_bg_overplane_w;
	wire hbias_bg_left_on_w;
	wire hbias_bg_right_on_w;
	wire signed [17:0] hbias_bg_left_source_w;
	wire signed [17:0] hbias_bg_right_source_w;
	wire signed [17:0] hbias_bg_left_destination_w;
	wire signed [17:0] hbias_bg_right_destination_w;
	wire [12:0] hbias_bg_width_w;
	wire [31:0] hbias_bg_gplt_w;
	wire hbias_bg_tile_row_valid_w;
	wire hbias_bg_tile_row_ready_w;
	wire [0:0] hbias_bg_tile_row_load_w;
	wire [8:0] hbias_bg_tile_row_screen_y_w;
	wire signed [16:0] hbias_bg_tile_row_source_y_w;
	wire hbias_bg_tile_valid_w;
	wire hbias_bg_tile_ready_w;
	wire [0:0] hbias_bg_tile_load_w;
	wire [12:0] hbias_bg_tile_ordinal_w;
	wire signed [15:0] hbias_bg_tile_x_w;
	wire hbias_bg_row_valid_w;
	wire hbias_bg_row_ready_w;
	wire [0:0] hbias_bg_row_load_w;
	wire [12:0] hbias_bg_row_tile_ordinal_w;
	wire [2:0] hbias_bg_row_ordinal_w;
	wire [2:0] hbias_bg_row_source_index_w;
	wire [8:0] hbias_bg_row_screen_y_w;
	wire signed [16:0] hbias_bg_row_source_y_w;
	wire hbias_row_valid_w;
	wire hbias_row_ready_w;
	wire [2:0] hbias_row_row_w;
	wire signed [15:0] hbias_row_left_base_x_w;
	wire hbias_row_left_enable_w;
	wire [7:0] hbias_row_left_active_w;
	wire [7:0] hbias_row_left_opaque_w;
	wire [15:0] hbias_row_left_values_w;
	wire signed [15:0] hbias_row_right_base_x_w;
	wire hbias_row_right_enable_w;
	wire [7:0] hbias_row_right_active_w;
	wire [7:0] hbias_row_right_opaque_w;
	wire [15:0] hbias_row_right_values_w;
	wire normal_row_ready_w;

	// Affine command and frontend state.
	wire affine_start_valid_w;
	wire affine_start_ready_w;
	wire affine_start_accept_w;
	wire affine_busy_w;
	wire affine_done_w;
	wire affine_dram_abort_w;
	wire affine_dram_req_w;
	wire [15:0] affine_dram_addr_w;
	wire affine_dram_accept_w;
	wire affine_dram_resp_valid_w;
	wire [15:0] affine_dram_resp_data_w;
	wire affine_dram_cleanup_busy_w;
	wire affine_dram_stale_discard_w;
	wire affine_vrm_abort_w;
	wire affine_vrm_req_w;
	wire [15:0] affine_vrm_addr_w;
	wire affine_vrm_accept_w;
	wire affine_vrm_resp_valid_w;
	wire [15:0] affine_vrm_resp_data_w;
	wire affine_vrm_cleanup_busy_w;
	wire affine_vrm_stale_discard_w;
	wire signed [16:0] affine_address_source_x_w;
	wire signed [16:0] affine_address_source_y_w;
	wire [3:0] affine_address_maps_wide_w;
	wire [3:0] affine_address_maps_high_w;
	wire [3:0] affine_address_effective_columns_w;
	wire [3:0] affine_address_base_rounded_w;
	wire affine_address_over_w;
	wire [15:0] affine_address_overplane_w;
	wire [15:0] affine_address_cell_w;
	wire [2:0] affine_address_cell_row_w;
	wire [15:0] affine_addressed_dram_cell_addr_w;
	wire affine_addressed_overplane_selected_w;
	wire affine_addressed_strict_overplane_w;
	wire affine_addressed_map_overflow_w;
	wire [15:0] affine_addressed_vrm_char_addr_w;
	wire [1:0] affine_addressed_palette_w;
	wire affine_addressed_hflip_w;
	wire affine_addressed_vflip_w;
	wire [15:0] affine_decode_character_row_w;
	wire [1:0] affine_decode_palette_w;
	wire affine_decode_hflip_w;
	wire [2:0] affine_decode_source_x_w;
	wire [31:0] affine_decode_gplt_w;
	wire [1:0] affine_decoded_raw_pixel_w;
	wire affine_decoded_raw_nonzero_w;
	wire [1:0] affine_decoded_mapped_pixel_w;
	wire affine_frontend_protocol_error_w;

	// The Affine adapter owns descriptor decoding and holds accepted results.
	wire affine_descriptor_left_on_w;
	wire affine_descriptor_right_on_w;
	wire affine_descriptor_over_w;
	wire signed [9:0] affine_descriptor_gx_w;
	wire signed [9:0] affine_descriptor_gp_w;
	wire signed [15:0] affine_descriptor_gy_w;
	wire [15:0] affine_descriptor_param_base_w;
	wire [15:0] affine_descriptor_overplane_w;
	wire [10:0] affine_descriptor_width_w;
	wire signed [16:0] affine_descriptor_height_w;
	wire [3:0] affine_descriptor_maps_wide_w;
	wire [3:0] affine_descriptor_maps_high_w;
	wire [3:0] affine_descriptor_effective_columns_w;
	wire [3:0] affine_descriptor_base_rounded_w;
	wire affine_descriptor_strict_policy_w;

	// Shared backend result and token state.
	wire backend_tile_row_ready_w;
	wire backend_tile_ready_w;
	wire backend_row_ready_w;
	wire backend_raw_valid_w;
	wire backend_raw_accept_w;
	wire [1:0] backend_raw_owner_w;
	wire [0:0] backend_raw_load_w;
	wire [12:0] backend_raw_tile_ordinal_w;
	wire [2:0] backend_raw_row_ordinal_w;
	wire signed [15:0] backend_raw_tile_x_w;
	wire [8:0] backend_raw_screen_y_w;
	wire signed [16:0] backend_raw_source_y_w;
	wire [2:0] backend_raw_source_index_w;
	wire [8:0] backend_raw_context_screen_y_w;
	wire signed [16:0] backend_raw_context_source_y_w;
	wire backend_raw_overplane_selected_w;
	wire backend_raw_strict_overplane_w;
	wire backend_token_valid_w;
	wire backend_token_ready_w;
	wire backend_token_accept_w;
	wire [2:0] backend_token_row_w;
	wire signed [15:0] backend_token_left_base_x_w;
	wire backend_token_left_enable_w;
	wire [7:0] backend_token_left_active_w;
	wire [7:0] backend_token_left_opaque_w;
	wire [15:0] backend_token_left_values_w;
	wire signed [15:0] backend_token_right_base_x_w;
	wire backend_token_right_enable_w;
	wire [7:0] backend_token_right_active_w;
	wire [7:0] backend_token_right_opaque_w;
	wire [15:0] backend_token_right_values_w;
	wire [1:0] backend_token_owner_w;
	wire [0:0] backend_token_load_w;
	wire [12:0] backend_token_tile_ordinal_w;
	wire [2:0] backend_token_row_ordinal_w;
	wire signed [15:0] backend_token_tile_x_w;
	wire [8:0] backend_token_screen_y_w;
	wire signed [16:0] backend_token_source_y_w;
	wire [2:0] backend_token_source_index_w;
	wire [8:0] backend_token_context_screen_y_w;
	wire signed [16:0] backend_token_context_source_y_w;
	wire backend_token_overplane_selected_w;
	wire backend_token_strict_overplane_w;
	wire backend_context_accept_w;
	wire backend_context_owner_valid_w;
	wire [1:0] backend_context_owner_w;
	wire backend_busy_w;
	wire backend_fetch_busy_w;
	wire backend_cleanup_busy_w;
	wire backend_dram_pending_w;
	wire backend_vrm_pending_w;
	wire backend_cell_req_w;
	wire [15:0] backend_cell_addr_w;
	wire backend_cell_accept_w;
	wire backend_cell_resp_valid_w;
	wire [15:0] backend_cell_resp_data_w;
	wire backend_cell_cleanup_busy_w;
	wire backend_cell_stale_discard_w;
	wire backend_vrm_req_w;
	wire [15:0] backend_vrm_addr_w;
	wire backend_vrm_accept_w;
	wire backend_vrm_resp_valid_w;
	wire [15:0] backend_vrm_resp_data_w;
	wire backend_vrm_cleanup_busy_w;
	wire backend_vrm_stale_discard_w;
	wire backend_unexpected_dram_w;
	wire backend_unexpected_vrm_w;
	wire backend_capture_overflow_w;
	wire backend_tag_mismatch_w;
	wire backend_concurrent_work_w;
	wire backend_strict_overplane_seen_w;
	wire backend_map_overflow_seen_w;
	wire backend_rearm_ready_w;
	wire backend_rearm_accept_w;
	wire backend_rearm_rejected_w;

	// Nested memory owner state.
	wire local_dram_req_w;
	wire [15:0] local_dram_addr_w;
	wire local_dram_accept_w;
	wire local_dram_resp_valid_w;
	wire [15:0] local_dram_resp_data_w;
	wire local_dram_cleanup_busy_w;
	wire local_dram_stale_discard_w;
	wire dram_mode_held_w;
	wire dram_mode_held_internal_w;
	wire dram_mode_pending_w;
	wire dram_mode_pending_internal_w;
	wire dram_mode_accept_error_w;
	wire dram_mode_retire_error_w;
	wire dram_mode_overlap_error_w;
	wire dram_inner_accept_error_w;
	wire dram_inner_retire_error_w;
	wire dram_inner_overlap_error_w;
	wire vrm_mode_held_w;
	wire vrm_mode_held_internal_w;
	wire vrm_mode_pending_w;
	wire vrm_mode_pending_internal_w;
	wire vrm_mode_accept_error_w;
	wire vrm_mode_retire_error_w;
	wire vrm_mode_overlap_error_w;

	// Outer muxes join Affine memory traffic with Object OAM and character reads.
	wire shared_dram_abort_w;
	wire shared_dram_req_w;
	wire [15:0] shared_dram_addr_w;
	wire shared_dram_accept_w;
	wire shared_dram_resp_valid_w;
	wire [15:0] shared_dram_resp_data_w;
	wire shared_dram_cleanup_busy_w;
	wire shared_dram_stale_discard_w;
	wire shared_vrm_abort_w;
	wire shared_vrm_req_w;
	wire [15:0] shared_vrm_addr_w;
	wire shared_vrm_accept_w;
	wire shared_vrm_resp_valid_w;
	wire [15:0] shared_vrm_resp_data_w;
	wire shared_vrm_cleanup_busy_w;
	wire shared_vrm_stale_discard_w;
	wire dram_outer_held_w;
	wire dram_outer_held_internal_w;
	wire dram_outer_pending_w;
	wire dram_outer_pending_internal_w;
	wire dram_outer_accept_error_w;
	wire dram_outer_retire_error_w;
	wire dram_outer_overlap_error_w;
	wire vrm_outer_held_w;
	wire vrm_outer_held_internal_w;
	wire vrm_outer_pending_w;
	wire vrm_outer_pending_internal_w;
	wire vrm_outer_accept_error_w;
	wire vrm_outer_retire_error_w;
	wire vrm_outer_overlap_error_w;

	// Strip-local Object command and four-bit epoch.
	reg [3:0] object_epoch_counter_q;
	reg [3:0] command_object_epoch_q;
	reg [1:0] command_object_group_q;
	reg [5:0] command_object_ordinal_q;
	reg command_object_penalty_q;
	reg object_backend_rearm_pending_q;
	wire tracker_preview_valid_w;
	wire [4:0] tracker_preview_strip_w;
	wire [1:0] tracker_preview_group_w;
	wire [5:0] tracker_preview_ordinal_w;
	wire tracker_preview_penalty_w;
	wire [31:0] tracker_preview_jplt_w;
	wire [9:0] tracker_preview_end_w;
	wire [9:0] tracker_preview_start_w;
	wire [10:0] tracker_preview_count_w;
	wire tracker_context_valid_w;
	wire [4:0] tracker_context_strip_w;
	wire [1:0] tracker_context_group_w;
	wire [5:0] tracker_context_ordinal_w;
	wire tracker_context_penalty_w;
	wire [31:0] tracker_context_jplt_w;
	wire [9:0] tracker_context_end_w;
	wire [9:0] tracker_context_start_w;
	wire [10:0] tracker_context_count_w;
	wire tracker_context_overrun_w;

	// Object command and completion.
	wire object_start_valid_w;
	wire object_start_ready_w;
	wire object_start_accept_w;
	wire object_busy_w;
	wire object_done_w;
	wire object_cleanup_busy_w;
	wire object_quiescent_w;
	wire object_command_active_w;
	wire object_transport_idle_w;
	wire object_completion_will_idle_w;
	wire [3:0] object_selected_epoch_w;
	wire [4:0] object_selected_strip_w;
	wire [1:0] object_selected_group_w;
	wire [5:0] object_selected_ordinal_w;
	wire object_selected_penalty_w;
	wire [31:0] object_selected_jplt_w;
	wire [9:0] object_selected_first_index_w;
	wire [9:0] object_selected_final_index_w;
	wire [10:0] object_selected_entry_count_w;

	// Object OAM and character clients.
	wire object_oam_req_w;
	wire [15:0] object_oam_addr_w;
	wire object_oam_accept_w;
	wire object_oam_resp_valid_w;
	wire [15:0] object_oam_resp_data_w;
	wire object_oam_cleanup_busy_w;
	wire object_oam_stale_discard_w;
	wire object_oam_stale_retire_w;
	wire object_char_req_w;
	wire [15:0] object_char_addr_w;
	wire object_char_accept_w;
	wire object_char_resp_valid_w;
	wire [15:0] object_char_resp_data_w;
	wire object_char_cleanup_busy_w;
	wire object_char_stale_discard_w;
	wire object_char_stale_retire_w;

	// Object query to the shared character decoder.
	wire object_decode_query_valid_w;
	wire object_decode_grant_w;
	wire object_decode_conflict_w;
	wire object_decode_accept_w;
	wire [15:0] object_decode_character_row_w;
	wire [1:0] object_decode_palette_w;
	wire object_decode_hflip_w;
	wire [31:0] object_decode_jplt_w;
	wire [7:0] shared_decoded_raw_nonzero_w;
	wire [15:0] shared_decoded_mapped_pixels_w;

	// Object row token.
	wire object_token_valid_w;
	wire object_token_ready_w;
	wire [2:0] object_token_row_w;
	wire signed [15:0] object_token_left_base_w;
	wire object_token_left_enable_w;
	wire [7:0] object_token_left_active_w;
	wire [7:0] object_token_left_opaque_w;
	wire [15:0] object_token_left_values_w;
	wire signed [15:0] object_token_right_base_w;
	wire object_token_right_enable_w;
	wire [7:0] object_token_right_active_w;
	wire [7:0] object_token_right_opaque_w;
	wire [15:0] object_token_right_values_w;

	// Object engine diagnostics.
	wire [15:0] object_scheduler_fixed_ticks_w;
	wire [31:0] object_scheduler_probe_ticks_w;
	wire [31:0] object_scheduler_active_setup_ticks_w;
	wire [31:0] object_scheduler_continuation_ticks_w;
	wire [31:0] object_scheduler_row_ticks_w;
	wire [31:0] object_scheduler_underflow_ticks_w;
	wire [31:0] object_oam_accept_count_w;
	wire [31:0] object_char_context_accept_count_w;
	wire [31:0] object_char_read_accept_count_w;
	wire [31:0] object_token_accept_count_w;
	wire [31:0] object_token_done_count_w;
	wire object_engine_protocol_error_w;
	reg object_start_mismatch_q;

	// Controller and FIFO diagnostics.
	wire normal_descriptor_mismatch_w;
	wire normal_height_conflict_w;
	wire normal_producer_overflow_w;
	wire normal_producer_underflow_w;
	wire hbias_command_kind_mismatch_w;
	wire hbias_descriptor_kind_mismatch_w;
	wire hbias_strict_overplane_high_w;
	wire hbias_raw_height_conflict_w;
	wire hbias_source_conflict_w;
	wire hbias_geometry_error_w;
	wire hbias_protocol_error_w;
	wire row_owner_overflow_w;
	wire row_owner_underflow_w;
	wire row_simultaneous_offer_w;
	wire row_owner_protocol_error_w;
	reg normal_fetch_error_q;
	reg hbias_fetch_error_q;
	reg affine_fetch_error_q;
	reg object_fetch_error_q;
	reg unowned_fetch_error_q;

	// Selected Normal, H-bias, or Object controller state.
	wire selected_hbias_w = command_kind_q == 2'd1;
	wire selected_ordinary_work_w = command_active_q &&
		((command_kind_q == 2'd0) || (command_kind_q == 2'd1));
	wire [1:0] selected_bg_owner_w = selected_ordinary_work_w ?
		(selected_hbias_w ? OWNER_HBIAS : OWNER_NORMAL) : OWNER_NONE;
	wire [3:0] selected_bg_maps_wide_w = selected_hbias_w ?
		hbias_bg_maps_wide_w : normal_bg_maps_wide_w;
	wire [3:0] selected_bg_maps_high_w = selected_hbias_w ?
		hbias_bg_maps_high_w : normal_bg_maps_high_w;
	wire [3:0] selected_bg_effective_columns_w = selected_hbias_w ?
		hbias_bg_effective_columns_w : normal_bg_effective_columns_w;
	wire [3:0] selected_bg_base_rounded_w = selected_hbias_w ?
		hbias_bg_base_rounded_w : normal_bg_base_rounded_w;
	wire selected_bg_over_w = selected_hbias_w ?
		hbias_bg_over_w : normal_bg_over_w;
	wire [15:0] selected_bg_overplane_w = selected_hbias_w ?
		hbias_bg_overplane_w : normal_bg_overplane_w;
	wire selected_bg_left_on_w = selected_hbias_w ?
		hbias_bg_left_on_w : normal_bg_left_on_w;
	wire selected_bg_right_on_w = selected_hbias_w ?
		hbias_bg_right_on_w : normal_bg_right_on_w;
	wire signed [17:0] selected_bg_left_source_w = selected_hbias_w ?
		hbias_bg_left_source_w : normal_bg_left_source_w;
	wire signed [17:0] selected_bg_right_source_w = selected_hbias_w ?
		hbias_bg_right_source_w : normal_bg_right_source_w;
	wire signed [17:0] selected_bg_left_destination_w =
		selected_hbias_w ? hbias_bg_left_destination_w :
		normal_bg_left_destination_w;
	wire signed [17:0] selected_bg_right_destination_w =
		selected_hbias_w ? hbias_bg_right_destination_w :
		normal_bg_right_destination_w;
	wire [12:0] selected_bg_width_w = selected_hbias_w ?
		hbias_bg_width_w : normal_bg_width_w;
	wire [31:0] selected_bg_gplt_w = selected_hbias_w ?
		hbias_bg_gplt_w : normal_bg_gplt_w;
	wire selected_bg_tile_row_valid_w = selected_ordinary_work_w &&
		(selected_hbias_w ? hbias_bg_tile_row_valid_w :
		 normal_bg_tile_row_valid_w);
	wire [0:0] selected_bg_tile_row_load_w = selected_hbias_w ?
		hbias_bg_tile_row_load_w : normal_bg_tile_row_load_w;
	wire [8:0] selected_bg_tile_row_screen_y_w = selected_hbias_w ?
		hbias_bg_tile_row_screen_y_w : normal_bg_tile_row_screen_y_w;
	wire signed [16:0] selected_bg_tile_row_source_y_w =
		selected_hbias_w ? hbias_bg_tile_row_source_y_w :
		normal_bg_tile_row_source_y_w;
	wire selected_bg_tile_valid_w = selected_ordinary_work_w &&
		(selected_hbias_w ? hbias_bg_tile_valid_w :
		 normal_bg_tile_valid_w);
	wire [0:0] selected_bg_tile_load_w = selected_hbias_w ?
		hbias_bg_tile_load_w : normal_bg_tile_load_w;
	wire [12:0] selected_bg_tile_ordinal_w = selected_hbias_w ?
		hbias_bg_tile_ordinal_w : normal_bg_tile_ordinal_w;
	wire signed [15:0] selected_bg_tile_x_w = selected_hbias_w ?
		hbias_bg_tile_x_w : normal_bg_tile_x_w;
	wire selected_bg_row_valid_w = selected_ordinary_work_w &&
		(selected_hbias_w ? hbias_bg_row_valid_w : normal_bg_row_valid_w);
	wire [0:0] selected_bg_row_load_w = selected_hbias_w ?
		hbias_bg_row_load_w : normal_bg_row_load_w;
	wire [12:0] selected_bg_row_tile_ordinal_w = selected_hbias_w ?
		hbias_bg_row_tile_ordinal_w : normal_bg_row_tile_ordinal_w;
	wire [2:0] selected_bg_row_ordinal_w = selected_hbias_w ?
		hbias_bg_row_ordinal_w : normal_bg_row_ordinal_w;
	wire [2:0] selected_bg_row_source_index_w = selected_hbias_w ?
		hbias_bg_row_source_index_w : normal_bg_row_source_index_w;
	wire [8:0] selected_bg_row_screen_y_w = selected_hbias_w ?
		hbias_bg_row_screen_y_w : normal_bg_row_screen_y_w;
	wire signed [16:0] selected_bg_row_source_y_w = selected_hbias_w ?
		hbias_bg_row_source_y_w : normal_bg_row_source_y_w;
	wire selected_bg_result_permit_w = selected_ordinary_work_w &&
		(selected_hbias_w ? hbias_bg_result_permit_w :
		 normal_bg_result_permit_w);

	// Keep Affine ownership after abort until accepted work drains.
	wire affine_mode_owned_w = (command_kind_q == 2'd2) &&
		(command_active_q || affine_busy_w ||
		 (dram_mode_held_w && !dram_mode_held_internal_w) ||
		 (dram_mode_pending_w && !dram_mode_pending_internal_w) ||
		 (vrm_mode_held_w && !vrm_mode_held_internal_w) ||
		 (vrm_mode_pending_w && !vrm_mode_pending_internal_w));

	// Use the held Object context, or pass a new one through an empty slot.
	assign object_selected_epoch_w = tracker_context_valid_w ?
		command_object_epoch_q : object_epoch_counter_q;
	assign object_selected_strip_w = tracker_context_valid_w ?
		tracker_context_strip_w : tracker_preview_strip_w;
	assign object_selected_group_w = tracker_context_valid_w ?
		tracker_context_group_w : tracker_preview_group_w;
	assign object_selected_ordinal_w = tracker_context_valid_w ?
		tracker_context_ordinal_w : tracker_preview_ordinal_w;
	assign object_selected_penalty_w = tracker_context_valid_w ?
		tracker_context_penalty_w : tracker_preview_penalty_w;
	assign object_selected_jplt_w = tracker_context_valid_w ?
		tracker_context_jplt_w : tracker_preview_jplt_w;
	assign object_selected_first_index_w = tracker_context_valid_w ?
		tracker_context_end_w : tracker_preview_end_w;
	assign object_selected_final_index_w = tracker_context_valid_w ?
		tracker_context_start_w : tracker_preview_start_w;
	assign object_selected_entry_count_w = tracker_context_valid_w ?
		tracker_context_count_w : tracker_preview_count_w;

	// Completion waits for child and outer memory ownership to drain.
	wire backend_controller_work_w = selected_bg_tile_row_valid_w ||
		selected_bg_tile_valid_w || selected_bg_row_valid_w;
	wire backend_context_normal_w = backend_context_owner_valid_w &&
		(backend_context_owner_w == OWNER_NORMAL);
	wire backend_token_normal_w = backend_token_valid_w &&
		(backend_token_owner_w == OWNER_NORMAL);
	wire backend_reset_independent_busy_w = backend_controller_work_w ||
		backend_dram_pending_w || backend_vrm_pending_w ||
		backend_cleanup_busy_w;
	wire ordinary_row_quiescent_w = !row_producer_valid_o &&
		!row_offer_held_o && (row_owner_count_o == 2'd0);
	wire dram_quiescent_w = !aggregate_dram_req_o &&
		!dram_outer_held_w && !dram_outer_pending_w &&
		!dram_mode_held_w && !dram_mode_pending_w &&
		!hbias_dram_offer_held_o && !hbias_dram_read_pending_o &&
		!aggregate_dram_cleanup_busy_i &&
		!aggregate_dram_resp_valid_i &&
		!aggregate_dram_stale_discard_i;
	wire vrm_quiescent_w = !aggregate_vrm_req_o &&
		!vrm_outer_held_w && !vrm_outer_pending_w &&
		!vrm_mode_held_w && !vrm_mode_pending_w &&
		!backend_vrm_pending_w && !aggregate_vrm_cleanup_busy_i &&
		!aggregate_vrm_resp_valid_i &&
		!aggregate_vrm_stale_discard_i;
	wire admission_dram_quiescent_w = !dram_outer_held_w &&
		!dram_outer_pending_w && !dram_mode_held_w &&
		!dram_mode_pending_w && !hbias_dram_offer_held_o &&
		!hbias_dram_read_pending_o && !aggregate_dram_cleanup_busy_i &&
		!aggregate_dram_resp_valid_i &&
		!aggregate_dram_stale_discard_i;
	wire admission_vrm_quiescent_w = !vrm_outer_held_w &&
		!vrm_outer_pending_w && !vrm_mode_held_w &&
		!vrm_mode_pending_w && !backend_vrm_pending_w &&
		!aggregate_vrm_cleanup_busy_i &&
		!aggregate_vrm_resp_valid_i &&
		!aggregate_vrm_stale_discard_i;
	wire hbias_logical_quiescent_w = !hbias_active_o &&
		!hbias_scheduler_busy_w && !hbias_pipeline_busy_w &&
		!hbias_pipeline_cleanup_busy_w &&
		hbias_pipeline_downstream_idle_w &&
		!hbias_param_read_pending_w && !hbias_param_req_w &&
		(hbias_producer_outstanding_o == 2'd0) && !hbias_row_valid_w;
	wire hbias_admission_quiescent_w = !hbias_active_o &&
		!hbias_scheduler_busy_w && !hbias_param_read_pending_w &&
		!hbias_param_req_w &&
		(hbias_producer_outstanding_o == 2'd0) && !hbias_row_valid_w;
	wire affine_logical_quiescent_w = !affine_busy_w &&
		!affine_prepare_valid_o && !affine_commit_valid_o &&
		affine_store_quiescent_i;
	wire object_logical_quiescent_w = object_quiescent_w &&
		!object_busy_w && !object_command_active_w &&
		!tracker_context_valid_w;
	wire admission_backend_quiescent_w = !backend_token_valid_w &&
		!backend_cleanup_busy_w &&
		!backend_controller_work_w &&
		!object_backend_rearm_pending_q;
	wire admission_quiescent_w = normal_quiescent_o &&
		hbias_admission_quiescent_w && affine_logical_quiescent_w &&
		object_logical_quiescent_w &&
		admission_backend_quiescent_w && admission_dram_quiescent_w &&
		admission_vrm_quiescent_w && ordinary_row_quiescent_w;
	wire global_quiescent_w = normal_quiescent_o &&
		hbias_logical_quiescent_w && affine_logical_quiescent_w &&
		object_logical_quiescent_w &&
		!backend_busy_w && !backend_cleanup_busy_w &&
		!object_backend_rearm_pending_q &&
		dram_quiescent_w && vrm_quiescent_w &&
		ordinary_row_quiescent_w;
	wire command_admit_w = !reset_i && !engine_abort_i &&
		!command_active_q && !completion_pending_q &&
		admission_quiescent_w;

	wire command_fire_w = ce_i && engine_cmd_valid_i &&
		engine_cmd_ready_o;
	wire selected_external_child_done_w =
		(command_kind_q == 2'd1) ? hbias_done_w :
		((command_kind_q == 2'd2) ? affine_done_w : object_done_w);
	wire selected_child_done_w = (command_kind_q == 2'd0) ?
		normal_done_w : selected_external_child_done_w;
	wire completion_seen_w = completion_pending_q ||
		(command_active_q && selected_child_done_w);
	wire external_completion_seen_w = completion_pending_q ||
		(command_active_q && selected_external_child_done_w);
	wire normal_completion_quiescent_w = normal_quiescent_o ||
		(command_active_q && (command_kind_q == 2'd0) && normal_done_w);
	wire hbias_completion_quiescent_w = hbias_logical_quiescent_w ||
		(command_active_q && (command_kind_q == 2'd1) && hbias_done_w);
	wire affine_completion_quiescent_w = affine_logical_quiescent_w ||
		(command_active_q && (command_kind_q == 2'd2) && affine_done_w &&
		 !affine_prepare_valid_o && !affine_commit_valid_o &&
		 affine_store_quiescent_i);
	wire object_completion_quiescent_w = object_logical_quiescent_w ||
		(command_active_q && (command_kind_q == 2'd3) && object_done_w &&
		 object_completion_will_idle_w);
	wire completion_quiescent_w = normal_completion_quiescent_w &&
		hbias_completion_quiescent_w && affine_completion_quiescent_w &&
		object_completion_quiescent_w &&
		!backend_busy_w && !backend_cleanup_busy_w &&
		!object_backend_rearm_pending_q &&
		dram_quiescent_w && vrm_quiescent_w && ordinary_row_quiescent_w;
	wire external_completion_quiescent_w = normal_quiescent_o &&
		hbias_completion_quiescent_w && affine_completion_quiescent_w &&
		object_completion_quiescent_w &&
		!backend_busy_w && !backend_cleanup_busy_w &&
		!object_backend_rearm_pending_q &&
		dram_quiescent_w && vrm_quiescent_w && ordinary_row_quiescent_w;

	assign normal_cmd_valid_w = engine_cmd_valid_i && command_admit_w &&
		((engine_cmd_kind_i != 2'd0) || backend_rearm_ready_w);
	assign engine_cmd_ready_o = command_admit_w && normal_cmd_ready_w;
	assign engine_done_o = !reset_i && !engine_abort_i &&
		command_active_q && completion_seen_w && completion_quiescent_w;

	assign hbias_cmd_valid_w = normal_external_valid_w &&
		(normal_external_kind_w == 2'd1);
	assign affine_start_valid_w = normal_external_valid_w &&
		(normal_external_kind_w == 2'd2) && backend_rearm_ready_w;
	assign object_start_valid_w = backend_rearm_ready_w &&
		(tracker_context_valid_w ||
		(normal_external_valid_w &&
		 (normal_external_kind_w == 2'd3) &&
		 tracker_preview_valid_w));
	assign normal_external_ready_w =
		(normal_external_kind_w == 2'd1) ? hbias_cmd_ready_w :
		((normal_external_kind_w == 2'd2) ? affine_start_ready_w :
		 ((normal_external_kind_w == 2'd3) ?
		  (object_start_ready_w && backend_rearm_ready_w &&
		   !tracker_context_valid_w) : 1'b0));
	assign normal_external_done_w = !reset_i && !engine_abort_i &&
		command_active_q && (command_kind_q != 2'd0) &&
		external_completion_seen_w && external_completion_quiescent_w;

	assign command_active_o = command_active_q;
	assign command_kind_o = command_kind_q;
	assign command_strip_o = command_strip_q;
	assign command_world_o = command_world_q;
	assign command_descriptor_o = command_descriptor_q;
	assign command_first_visit_o = command_first_visit_q;
	assign command_gplt_o = command_gplt_q;
	assign completion_pending_o = completion_pending_q;
	assign global_quiescent_o = global_quiescent_w;
	assign normal_child_done_o = normal_done_w;
	assign hbias_child_done_o = hbias_done_w;
	assign affine_child_done_o = affine_done_w;
	assign object_child_done_o = object_done_w;
	assign affine_active_o = affine_busy_w;
	assign object_active_o = object_busy_w;

	assign normal_bg_tile_row_ready_w = !selected_hbias_w &&
		backend_tile_row_ready_w;
	assign normal_bg_tile_ready_w = !selected_hbias_w &&
		backend_tile_ready_w;
	assign normal_bg_row_ready_w = !selected_hbias_w &&
		backend_row_ready_w;
	assign hbias_bg_tile_row_ready_w = selected_hbias_w &&
		backend_tile_row_ready_w;
	assign hbias_bg_tile_ready_w = selected_hbias_w &&
		backend_tile_ready_w;
	assign hbias_bg_row_ready_w = selected_hbias_w &&
		backend_row_ready_w;
	assign backend_token_ready_w =
		(backend_token_owner_w == OWNER_NORMAL) ? normal_row_ready_w :
		((backend_token_owner_w == OWNER_HBIAS) ?
		 hbias_bg_token_ready_w : 1'b0);

	// MODE view of the retained backend context owner, shared by the
	// owner-report chains below.
	wire [2:0] backend_context_mode_w =
		(backend_context_owner_w == OWNER_NORMAL) ? MODE_NORMAL :
		((backend_context_owner_w == OWNER_HBIAS) ? MODE_HBIAS : MODE_NONE);

	// Report the retained owner, not the live command selector.
	assign dram_accepted_owner_o = object_oam_accept_w ? MODE_OBJECT :
		(affine_dram_accept_w ? MODE_AFFINE :
		 ((hbias_dram_accepted_owner_o == DRAM_OWNER_PARAM) ? MODE_HBIAS :
		  ((hbias_dram_accepted_owner_o == DRAM_OWNER_CELL) ?
		   backend_context_mode_w : MODE_NONE)));
	assign dram_offer_held_o = dram_outer_held_w;
	assign dram_held_owner_o = !dram_outer_held_w ? MODE_NONE :
		(!dram_outer_held_internal_w ? MODE_OBJECT :
		 (!dram_mode_held_w ? MODE_NONE :
		  (!dram_mode_held_internal_w ? MODE_AFFINE :
		   ((hbias_dram_held_owner_o == DRAM_OWNER_PARAM) ? MODE_HBIAS :
		    ((hbias_dram_held_owner_o == DRAM_OWNER_CELL) ?
		     backend_context_mode_w : MODE_NONE)))));
	assign dram_read_pending_o = dram_outer_pending_w;
	assign dram_pending_owner_o = !dram_outer_pending_w ? MODE_NONE :
		(!dram_outer_pending_internal_w ? MODE_OBJECT :
		 (!dram_mode_pending_w ? MODE_NONE :
		  (!dram_mode_pending_internal_w ? MODE_AFFINE :
		   ((hbias_dram_pending_owner_o == DRAM_OWNER_PARAM) ? MODE_HBIAS :
		    ((hbias_dram_pending_owner_o == DRAM_OWNER_CELL) ?
		     backend_context_mode_w : MODE_NONE)))));
	assign vrm_accepted_owner_o = object_char_accept_w ? MODE_OBJECT :
		(affine_vrm_accept_w ? MODE_AFFINE :
		 (backend_vrm_accept_w ? backend_context_mode_w : MODE_NONE));
	assign vrm_offer_held_o = vrm_outer_held_w;
	assign vrm_held_owner_o = !vrm_outer_held_w ? MODE_NONE :
		(!vrm_outer_held_internal_w ? MODE_OBJECT :
		 (!vrm_mode_held_w ? MODE_NONE :
		  (vrm_mode_held_internal_w ?
		   backend_context_mode_w : MODE_AFFINE)));
	assign vrm_read_pending_o = vrm_outer_pending_w;
	assign vrm_pending_owner_o = !vrm_outer_pending_w ? MODE_NONE :
		(!vrm_outer_pending_internal_w ? MODE_OBJECT :
		 (!vrm_mode_pending_w ? MODE_NONE :
		  (vrm_mode_pending_internal_w ?
		   backend_context_mode_w : MODE_AFFINE)));

	// Cleanup uses only registered pending and busy state.
	assign engine_cleanup_busy_o = backend_cleanup_busy_w ||
		hbias_pipeline_cleanup_busy_w || affine_cleanup_interlock_o ||
		object_cleanup_busy_w || object_backend_rearm_pending_q ||
		dram_outer_held_w || dram_outer_pending_w ||
		vrm_outer_held_w || vrm_outer_pending_w || dram_mode_held_w ||
		dram_mode_pending_w || vrm_mode_held_w || vrm_mode_pending_w ||
		hbias_dram_offer_held_o || hbias_dram_read_pending_o ||
		backend_dram_pending_w || backend_vrm_pending_w ||
		(row_owner_count_o != 2'd0) || row_offer_held_o;

	assign object_epoch_o = command_object_epoch_q;
	assign object_group_o = command_object_group_q;
	assign object_ordinal_o = command_object_ordinal_q;
	assign object_penalty_class_o = command_object_penalty_q;
	assign object_oam_pending_o = dram_outer_pending_w &&
		!dram_outer_pending_internal_w;
	assign object_char_pending_o = vrm_outer_pending_w &&
		!vrm_outer_pending_internal_w;
	assign object_decode_pending_o = object_decode_query_valid_w;
	assign object_decode_accept_o = object_decode_accept_w;
	assign object_transport_idle_o = object_transport_idle_w;
	assign object_oam_stale_retire_o = object_oam_stale_retire_w;
	assign object_char_stale_retire_o = object_char_stale_retire_w;
	assign object_scheduler_fixed_ticks_o = object_scheduler_fixed_ticks_w;
	assign object_scheduler_probe_ticks_o = object_scheduler_probe_ticks_w;
	assign object_scheduler_active_setup_ticks_o =
		object_scheduler_active_setup_ticks_w;
	assign object_scheduler_continuation_ticks_o =
		object_scheduler_continuation_ticks_w;
	assign object_scheduler_row_ticks_o = object_scheduler_row_ticks_w;
	assign object_scheduler_underflow_ticks_o =
		object_scheduler_underflow_ticks_w;
	assign object_oam_read_accept_count_o = object_oam_accept_count_w;
	assign object_char_context_accept_count_o =
		object_char_context_accept_count_w;
	assign object_char_read_accept_count_o = object_char_read_accept_count_w;
	assign object_token_accept_count_o = object_token_accept_count_w;
	assign object_token_done_count_o = object_token_done_count_w;
	assign object_group_overrun_o = tracker_context_overrun_w;
	assign object_decode_mode_conflict_o = object_decode_conflict_w ||
		(object_decode_query_valid_w && external_decode_mode_conflict_o);
	assign object_error_o = object_engine_protocol_error_w ||
		tracker_context_overrun_w || object_start_mismatch_q ||
		object_decode_mode_conflict_o || object_fetch_error_q;

	assign normal_error_o = normal_descriptor_mismatch_w ||
		normal_producer_overflow_w || normal_producer_underflow_w ||
		normal_fetch_error_q;
	assign hbias_error_o = hbias_command_kind_mismatch_w ||
		hbias_descriptor_kind_mismatch_w || hbias_geometry_error_w ||
		hbias_protocol_error_w || hbias_fetch_error_q;
	assign affine_error_o = affine_frontend_protocol_error_w ||
		affine_fetch_error_q ||
		(external_decode_mode_conflict_o && affine_mode_owned_w) ||
		external_address_mode_conflict_o;
	assign normal_height_conflict_o = normal_height_conflict_w;
	assign hbias_strict_overplane_qualification_o =
		hbias_strict_overplane_high_w;
	assign hbias_raw_height_conflict_o = hbias_raw_height_conflict_w;
	assign hbias_source_conflict_o = hbias_source_conflict_w;
	assign dram_protocol_error_o = dram_outer_accept_error_w ||
		dram_outer_retire_error_w || dram_outer_overlap_error_w ||
		dram_mode_accept_error_w ||
		dram_mode_retire_error_w || dram_mode_overlap_error_w ||
		dram_inner_accept_error_w || dram_inner_retire_error_w ||
		dram_inner_overlap_error_w;
	assign vrm_protocol_error_o = vrm_outer_accept_error_w ||
		vrm_outer_retire_error_w || vrm_outer_overlap_error_w ||
		vrm_mode_accept_error_w ||
		vrm_mode_retire_error_w || vrm_mode_overlap_error_w;
	assign row_protocol_error_o = row_owner_overflow_w ||
		row_owner_underflow_w || row_simultaneous_offer_w ||
		row_owner_protocol_error_w;
	assign protocol_error_o = normal_error_o || hbias_error_o ||
		affine_error_o || object_error_o || dram_protocol_error_o ||
		vrm_protocol_error_o || row_protocol_error_o ||
		unexpected_completion_o || engine_request_overlap_o ||
		unowned_fetch_error_q;

	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_normal_controller
	#(
		.COMPOSED_TIMING_CREDIT_ENABLE(
			COMPOSED_TIMING_CREDIT_ENABLE)
	)
	u_normal_controller
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.engine_cmd_valid_i(normal_cmd_valid_w),
		.engine_cmd_ready_o(normal_cmd_ready_w),
		.engine_cmd_kind_i(engine_cmd_kind_i),
		.engine_cmd_strip_i(engine_cmd_strip_i),
		.engine_cmd_world_i(engine_cmd_world_i),
		.engine_cmd_descriptor_i(engine_cmd_scaled_descriptor_t),
		.engine_cmd_first_visit_i(engine_cmd_first_visit_i),
		.engine_done_o(normal_done_w),
		.engine_abort_i(engine_abort_i),
		.gplt_active_i(gplt_active_i),
		.external_cmd_valid_o(normal_external_valid_w),
		.external_cmd_ready_i(normal_external_ready_w),
		.external_cmd_kind_o(normal_external_kind_w),
		.external_cmd_strip_o(normal_external_strip_w),
		.external_cmd_world_o(normal_external_world_w),
		.external_cmd_descriptor_o(normal_external_descriptor_w),
		.external_cmd_first_visit_o(normal_external_first_visit_w),
		.external_done_i(normal_external_done_w),
		.backend_maps_wide_o(normal_bg_maps_wide_w),
		.backend_maps_high_o(normal_bg_maps_high_w),
		.backend_effective_map_columns_o(
			normal_bg_effective_columns_w),
		.backend_bgmap_base_rounded_o(normal_bg_base_rounded_w),
		.backend_over_o(normal_bg_over_w),
		.backend_overplane_o(normal_bg_overplane_w),
		.backend_left_on_o(normal_bg_left_on_w),
		.backend_right_on_o(normal_bg_right_on_w),
		.backend_left_source_start_o(normal_bg_left_source_w),
		.backend_right_source_start_o(normal_bg_right_source_w),
		.backend_left_destination_start_o(
			normal_bg_left_destination_w),
		.backend_right_destination_start_o(
			normal_bg_right_destination_w),
		.backend_semantic_width_o(normal_bg_width_w),
		.backend_gplt_active_o(normal_bg_gplt_w),
		.backend_result_permit_o(normal_bg_result_permit_w),
		.backend_tile_row_valid_o(normal_bg_tile_row_valid_w),
		.backend_tile_row_ready_i(normal_bg_tile_row_ready_w),
		.backend_tile_row_load_o(normal_bg_tile_row_load_w),
		.backend_tile_row_screen_y_o(normal_bg_tile_row_screen_y_w),
		.backend_tile_row_source_y_o(normal_bg_tile_row_source_y_w),
		.backend_tile_valid_o(normal_bg_tile_valid_w),
		.backend_tile_ready_i(normal_bg_tile_ready_w),
		.backend_tile_load_o(normal_bg_tile_load_w),
		.backend_tile_ordinal_o(normal_bg_tile_ordinal_w),
		.backend_tile_x_o(normal_bg_tile_x_w),
		.backend_row_valid_o(normal_bg_row_valid_w),
		.backend_row_ready_i(normal_bg_row_ready_w),
		.backend_row_load_o(normal_bg_row_load_w),
		.backend_row_tile_ordinal_o(normal_bg_row_tile_ordinal_w),
		.backend_row_ordinal_o(normal_bg_row_ordinal_w),
		.backend_row_source_index_o(normal_bg_row_source_index_w),
		.backend_row_screen_y_o(normal_bg_row_screen_y_w),
		.backend_row_source_y_o(normal_bg_row_source_y_w),
		.backend_fetch_busy_i(backend_context_normal_w &&
			backend_reset_independent_busy_w),
		.backend_cleanup_busy_i(backend_context_normal_w &&
			backend_cleanup_busy_w),
		.backend_token_valid_i(backend_token_normal_w),
		.backend_token_accept_i(backend_token_accept_w &&
			(backend_token_owner_w == OWNER_NORMAL)),
		.row_producer_done_i(normal_row_done_o),
		.normal_command_accept_o(normal_command_accept_w),
		.normal_active_o(normal_active_o),
		.normal_quiescent_o(normal_quiescent_o),
		.scheduler_state_o(normal_scheduler_state_o),
		.scheduler_elapsed_ticks_o(normal_scheduler_elapsed_ticks_o),
		.scheduler_tile_accept_count_o(
			normal_scheduler_tile_accept_count_o),
		.scheduler_row_accept_count_o(
			normal_scheduler_row_accept_count_o),
		.producer_outstanding_o(normal_producer_outstanding_o),
		.descriptor_kind_mismatch_o(normal_descriptor_mismatch_w),
		.minimum_height_timing_conflict_o(normal_height_conflict_w),
		.producer_overflow_o(normal_producer_overflow_w),
		.producer_underflow_o(normal_producer_underflow_w)
	);

	vip_xp_hbias_engine
	#(
		.COMPOSED_TIMING_CREDIT_ENABLE(
			COMPOSED_TIMING_CREDIT_ENABLE)
	)
	u_hbias_engine
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.engine_cmd_valid_i(hbias_cmd_valid_w),
		.engine_cmd_ready_o(hbias_cmd_ready_w),
		.engine_cmd_kind_i(normal_external_kind_w),
		.engine_cmd_strip_i(normal_external_strip_w),
		.engine_cmd_world_i(normal_external_world_w),
		.engine_cmd_descriptor_i(normal_external_descriptor_w),
		.engine_cmd_first_visit_i(normal_external_first_visit_w),
		.engine_done_o(hbias_done_w),
		.engine_abort_i(engine_abort_i),
		.parallax_scale_i(command_parallax_scale_q),
		.gplt_active_i(gplt_active_i),
		.param_dram_req_o(hbias_param_req_w),
		.param_dram_addr_o(hbias_param_addr_w),
		.param_dram_accept_i(hbias_param_accept_w),
		.param_dram_resp_valid_i(hbias_param_resp_valid_w),
		.param_dram_resp_data_i(hbias_param_resp_data_w),
		.param_dram_cleanup_busy_i(hbias_param_cleanup_busy_w),
		.param_dram_stale_discard_i(hbias_param_stale_discard_w),
		.bg_diagnostic_rearm_o(hbias_bg_rearm_w),
		.bg_diagnostic_rearm_ready_i(backend_rearm_ready_w),
		.bg_diagnostic_rearm_accept_i(backend_rearm_accept_w),
		.bg_diagnostic_rearm_rejected_i(backend_rearm_rejected_w),
		.bg_maps_wide_o(hbias_bg_maps_wide_w),
		.bg_maps_high_o(hbias_bg_maps_high_w),
		.bg_effective_map_columns_o(hbias_bg_effective_columns_w),
		.bg_bgmap_base_rounded_o(hbias_bg_base_rounded_w),
		.bg_over_o(hbias_bg_over_w),
		.bg_overplane_o(hbias_bg_overplane_w),
		.bg_left_on_o(hbias_bg_left_on_w),
		.bg_right_on_o(hbias_bg_right_on_w),
		.bg_left_source_start_o(hbias_bg_left_source_w),
		.bg_right_source_start_o(hbias_bg_right_source_w),
		.bg_left_destination_start_o(hbias_bg_left_destination_w),
		.bg_right_destination_start_o(hbias_bg_right_destination_w),
		.bg_semantic_width_o(hbias_bg_width_w),
		.bg_gplt_active_o(hbias_bg_gplt_w),
		.bg_tile_row_valid_o(hbias_bg_tile_row_valid_w),
		.bg_tile_row_ready_i(hbias_bg_tile_row_ready_w),
		.bg_tile_row_load_o(hbias_bg_tile_row_load_w),
		.bg_tile_row_screen_y_o(hbias_bg_tile_row_screen_y_w),
		.bg_tile_row_source_y_o(hbias_bg_tile_row_source_y_w),
		.bg_tile_valid_o(hbias_bg_tile_valid_w),
		.bg_tile_ready_i(hbias_bg_tile_ready_w),
		.bg_tile_load_o(hbias_bg_tile_load_w),
		.bg_tile_ordinal_o(hbias_bg_tile_ordinal_w),
		.bg_tile_x_o(hbias_bg_tile_x_w),
		.bg_row_valid_o(hbias_bg_row_valid_w),
		.bg_row_ready_i(hbias_bg_row_ready_w),
		.bg_row_load_o(hbias_bg_row_load_w),
		.bg_row_tile_ordinal_o(hbias_bg_row_tile_ordinal_w),
		.bg_row_ordinal_o(hbias_bg_row_ordinal_w),
		.bg_row_source_index_o(hbias_bg_row_source_index_w),
		.bg_row_screen_y_o(hbias_bg_row_screen_y_w),
		.bg_row_source_y_o(hbias_bg_row_source_y_w),
		.bg_result_permit_o(hbias_bg_result_permit_w),
		.bg_raw_result_valid_i(backend_raw_valid_w),
		.bg_raw_result_accept_i(backend_raw_accept_w),
		.bg_raw_result_owner_i(backend_raw_owner_w),
		.bg_raw_result_load_i(backend_raw_load_w),
		.bg_raw_result_tile_ordinal_i(backend_raw_tile_ordinal_w),
		.bg_raw_result_row_ordinal_i(backend_raw_row_ordinal_w),
		.bg_raw_result_tile_x_i(backend_raw_tile_x_w),
		.bg_raw_result_screen_y_i(backend_raw_screen_y_w),
		.bg_raw_result_source_y_i(backend_raw_source_y_w),
		.bg_raw_result_source_index_i(backend_raw_source_index_w),
		.bg_raw_result_tile_row_screen_y_i(
			backend_raw_context_screen_y_w),
		.bg_raw_result_tile_row_source_y_i(
			backend_raw_context_source_y_w),
		.bg_raw_result_overplane_selected_i(
			backend_raw_overplane_selected_w),
		.bg_raw_result_strict_overplane_i(
			backend_raw_strict_overplane_w),
		.bg_token_valid_i(backend_token_valid_w),
		.bg_token_ready_o(hbias_bg_token_ready_w),
		.bg_token_accept_i(backend_token_accept_w),
		.bg_token_row_i(backend_token_row_w),
		.bg_token_left_base_x_i(backend_token_left_base_x_w),
		.bg_token_left_enable_i(backend_token_left_enable_w),
		.bg_token_left_active_i(backend_token_left_active_w),
		.bg_token_left_opaque_i(backend_token_left_opaque_w),
		.bg_token_left_values_i(backend_token_left_values_w),
		.bg_token_right_base_x_i(backend_token_right_base_x_w),
		.bg_token_right_enable_i(backend_token_right_enable_w),
		.bg_token_right_active_i(backend_token_right_active_w),
		.bg_token_right_opaque_i(backend_token_right_opaque_w),
		.bg_token_right_values_i(backend_token_right_values_w),
		.bg_token_owner_i(backend_token_owner_w),
		.bg_token_load_i(backend_token_load_w),
		.bg_token_tile_ordinal_i(backend_token_tile_ordinal_w),
		.bg_token_row_ordinal_i(backend_token_row_ordinal_w),
		.bg_token_tile_x_i(backend_token_tile_x_w),
		.bg_token_screen_y_i(backend_token_screen_y_w),
		.bg_token_source_y_i(backend_token_source_y_w),
		.bg_token_source_index_i(backend_token_source_index_w),
		.bg_token_tile_row_screen_y_i(
			backend_token_context_screen_y_w),
		.bg_token_tile_row_source_y_i(
			backend_token_context_source_y_w),
		.bg_token_overplane_selected_i(
			backend_token_overplane_selected_w),
		.bg_token_strict_overplane_i(backend_token_strict_overplane_w),
		.bg_context_accept_i(backend_context_accept_w),
		.bg_context_owner_valid_i(backend_context_owner_valid_w),
		.bg_active_context_owner_i(backend_context_owner_w),
		.bg_busy_i(backend_busy_w),
		.bg_fetch_busy_i(backend_fetch_busy_w),
		.bg_cleanup_busy_i(backend_cleanup_busy_w),
		.bg_dram_read_pending_i(backend_dram_pending_w),
		.bg_vrm_read_pending_i(backend_vrm_pending_w),
		.bg_cell_accept_i(backend_cell_accept_w),
		.bg_vrm_accept_i(backend_vrm_accept_w),
		.bg_unexpected_dram_response_i(backend_unexpected_dram_w),
		.bg_unexpected_vrm_response_i(backend_unexpected_vrm_w),
		.bg_response_capture_overflow_i(backend_capture_overflow_w),
		.bg_scheduler_tag_mismatch_i(backend_tag_mismatch_w),
		.bg_concurrent_work_error_i(backend_concurrent_work_w),
		.bg_strict_overplane_seen_i(backend_strict_overplane_seen_w),
		.bg_map_index_overflow_seen_i(backend_map_overflow_seen_w),
		.row_producer_valid_o(hbias_row_valid_w),
		.row_producer_ready_i(hbias_row_ready_w),
		.row_producer_tile_ordinal_o(),
		.row_producer_row_o(hbias_row_row_w),
		.row_producer_left_base_x_o(hbias_row_left_base_x_w),
		.row_producer_left_enable_o(hbias_row_left_enable_w),
		.row_producer_left_active_o(hbias_row_left_active_w),
		.row_producer_left_opaque_o(hbias_row_left_opaque_w),
		.row_producer_left_values_o(hbias_row_left_values_w),
		.row_producer_right_base_x_o(hbias_row_right_base_x_w),
		.row_producer_right_enable_o(hbias_row_right_enable_w),
		.row_producer_right_active_o(hbias_row_right_active_w),
		.row_producer_right_opaque_o(hbias_row_right_opaque_w),
		.row_producer_right_values_o(hbias_row_right_values_w),
		.row_producer_done_i(hbias_row_done_o),
		.hbias_active_o(hbias_active_o),
		.hbias_quiescent_o(hbias_quiescent_o),
		.command_accept_o(hbias_command_accept_w),
		.active_visual_height_o(),
		.active_timing_height_o(),
		.scheduler_busy_o(hbias_scheduler_busy_w),
		.scheduler_done_pulse_o(),
		.scheduler_aborted_o(),
		.scheduler_state_o(hbias_scheduler_state_o),
		.scheduler_ticks_remaining_o(),
		.scheduler_elapsed_ticks_o(hbias_scheduler_elapsed_ticks_o),
		.scheduler_row_accept_count_o(
			hbias_scheduler_row_accept_count_o),
		.scheduler_tile_accept_count_o(
			hbias_scheduler_tile_accept_count_o),
		.scheduler_rows_in_strip_o(),
		.timing_reference_strip_ticks_o(),
		.timing_reference_rows_o(),
		.visual_only_rows_o(),
		.extent_conflict_o(),
		.pipeline_busy_o(hbias_pipeline_busy_w),
		.pipeline_cleanup_busy_o(hbias_pipeline_cleanup_busy_w),
		.pipeline_downstream_idle_o(hbias_pipeline_downstream_idle_w),
		.producer_outstanding_o(hbias_producer_outstanding_o),
		.param_read_pending_o(hbias_param_read_pending_w),
		.cell_dram_read_pending_o(),
		.cell_vrm_read_pending_o(),
		.command_kind_mismatch_o(hbias_command_kind_mismatch_w),
		.descriptor_kind_mismatch_o(hbias_descriptor_kind_mismatch_w),
		.strict_overplane_high_o(hbias_strict_overplane_high_w),
		.raw_h_timing_conflict_o(hbias_raw_height_conflict_w),
		.source_conflict_o(hbias_source_conflict_w),
		.geometry_error_o(hbias_geometry_error_w),
		.protocol_error_o(hbias_protocol_error_w),
		.diag_command_accept_count_o(),
		.diag_command_done_count_o()
	);

	// Reset Object group state on every accepted root command.
	vip_xp_obj_group_tracker u_object_group_tracker
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(engine_abort_i),
		.root_accept_i(command_fire_w),
		.root_strip_i(engine_cmd_strip_i),
		.root_kind_i(engine_cmd_kind_i),
		.root_dummy_i(1'b0),
		.spt_active_i(spt_active_i),
		.jplt_active_i(jplt_active_i),
		.preview_valid_o(tracker_preview_valid_w),
		.preview_strip_o(tracker_preview_strip_w),
		.preview_group_o(tracker_preview_group_w),
		.preview_ordinal_o(tracker_preview_ordinal_w),
		.preview_penalty_class_o(tracker_preview_penalty_w),
		.preview_spt_o(),
		.preview_jplt_o(tracker_preview_jplt_w),
		.preview_inclusive_end_o(tracker_preview_end_w),
		.preview_inclusive_start_o(tracker_preview_start_w),
		.preview_entry_count_o(tracker_preview_count_w),
		.preview_full_range_o(),
		.context_valid_o(tracker_context_valid_w),
		.context_ready_i(object_start_accept_w),
		.context_strip_o(tracker_context_strip_w),
		.context_group_o(tracker_context_group_w),
		.context_ordinal_o(tracker_context_ordinal_w),
		.context_penalty_class_o(tracker_context_penalty_w),
		.context_spt_o(),
		.context_jplt_o(tracker_context_jplt_w),
		.context_inclusive_end_o(tracker_context_end_w),
		.context_inclusive_start_o(tracker_context_start_w),
		.context_entry_count_o(tracker_context_count_w),
		.context_full_range_o(),
		.context_overrun_o(tracker_context_overrun_w)
	);

	// Object work starts on the accepted kind-three command edge.
	vip_xp_obj_engine
	#(
		.COMPOSED_TIMING_CREDIT_ENABLE(
			COMPOSED_TIMING_CREDIT_ENABLE)
	)
	u_object_engine
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(engine_abort_i),
		.start_valid_i(object_start_valid_w),
		.start_ready_o(object_start_ready_w),
		.start_accept_o(object_start_accept_w),
		.world_i(tracker_context_valid_w ? command_world_q :
			normal_external_world_w),
		.strip_i(object_selected_strip_w),
		.first_visit_i(tracker_context_valid_w ?
			command_first_visit_q : normal_external_first_visit_w),
		.epoch_i(object_selected_epoch_w),
		.first_index_i(object_selected_first_index_w),
		.final_index_i(object_selected_final_index_w),
		.entry_count_i(object_selected_entry_count_w),
		.penalty_i(object_selected_penalty_w),
		.parallax_scale_i(command_parallax_scale_q),
		.jplt_active_i(object_selected_jplt_w),
		.busy_o(object_busy_w),
		.done_o(object_done_w),
		// Completion is always taken; the parent's completion_pending
		// register provides any holding the coordinator needs.
		.done_ready_i(1'b1),
		.cleanup_busy_o(object_cleanup_busy_w),
		.quiescent_o(object_quiescent_w),
		.command_active_o(object_command_active_w),
		.transport_idle_o(object_transport_idle_w),
		.completion_will_idle_o(object_completion_will_idle_w),
		.oam_dram_req_o(object_oam_req_w),
		.oam_dram_addr_o(object_oam_addr_w),
		.oam_dram_accept_i(object_oam_accept_w),
		.oam_dram_resp_valid_i(object_oam_resp_valid_w),
		.oam_dram_resp_data_i(object_oam_resp_data_w),
		.oam_router_cleanup_busy_i(object_oam_cleanup_busy_w),
		.oam_router_stale_discard_i(object_oam_stale_discard_w),
		.oam_stale_retire_o(object_oam_stale_retire_w),
		.char_vrm_req_o(object_char_req_w),
		// Object never writes VRAM; the write flag is tied low inside.
		.char_vrm_write_o(),
		.char_vrm_addr_o(object_char_addr_w),
		.char_vrm_accept_i(object_char_accept_w),
		.char_vrm_resp_valid_i(object_char_resp_valid_w),
		.char_vrm_resp_data_i(object_char_resp_data_w),
		.char_router_cleanup_busy_i(object_char_cleanup_busy_w),
		.char_router_stale_discard_i(object_char_stale_discard_w),
		.char_stale_retire_o(object_char_stale_retire_w),
		.decode_query_valid_o(object_decode_query_valid_w),
		.decode_query_ready_o(),
		.decode_grant_i(object_decode_grant_w),
		.decode_conflict_i(object_decode_conflict_w),
		.decode_accept_o(object_decode_accept_w),
		.decode_character_row_o(object_decode_character_row_w),
		.decode_palette_o(object_decode_palette_w),
		.decode_hflip_o(object_decode_hflip_w),
		.decode_jplt_active_o(object_decode_jplt_w),
		.decoded_raw_nonzero_i(shared_decoded_raw_nonzero_w),
		.decoded_mapped_pixels_i(shared_decoded_mapped_pixels_w),
		.token_valid_o(object_token_valid_w),
		.token_ready_i(object_token_ready_w),
		.token_accept_o(),
		.token_done_i(object_row_done_o),
		.token_epoch_o(),
		.token_object_index_o(),
		.token_screen_y_o(),
		.token_source_row_o(),
		.token_row_o(object_token_row_w),
		.token_left_base_x_o(object_token_left_base_w),
		.token_left_enable_o(object_token_left_enable_w),
		.token_left_active_o(object_token_left_active_w),
		.token_left_opaque_o(object_token_left_opaque_w),
		.token_left_values_o(object_token_left_values_w),
		.token_right_base_x_o(object_token_right_base_w),
		.token_right_enable_o(object_token_right_enable_w),
		.token_right_active_o(object_token_right_active_w),
		.token_right_opaque_o(object_token_right_opaque_w),
		.token_right_values_o(object_token_right_values_w),
		.token_character_effective_row_o(),
		.token_character_row_addr_o(),
		.scheduler_state_o(object_scheduler_state_o),
		.scheduler_ticks_remaining_o(
			object_scheduler_ticks_remaining_o),
		.scheduler_elapsed_ticks_o(object_scheduler_elapsed_ticks_o),
		.scheduler_fixed_ticks_o(object_scheduler_fixed_ticks_w),
		.scheduler_probe_ticks_o(object_scheduler_probe_ticks_w),
		.scheduler_active_setup_ticks_o(
			object_scheduler_active_setup_ticks_w),
		.scheduler_continuation_ticks_o(
			object_scheduler_continuation_ticks_w),
		.scheduler_row_ticks_o(object_scheduler_row_ticks_w),
		.scheduler_underflow_ticks_o(
			object_scheduler_underflow_ticks_w),
		.scheduler_transport_stall_ticks_o(
			object_scheduler_transport_stall_ticks_o),
		.diag_oam_read_accept_count_o(object_oam_accept_count_w),
		.diag_char_context_accept_count_o(
			object_char_context_accept_count_w),
		.diag_char_read_accept_count_o(object_char_read_accept_count_w),
		.diag_token_accept_count_o(object_token_accept_count_w),
		.diag_token_done_count_o(object_token_done_count_w),
		.underflow_unresolved_o(object_underflow_unresolved_o),
		.jy_unresolved_o(object_jy_behavior_unresolved_o),
		.ignored_oam_bits_nonzero_o(
			object_ignored_oam_bits_nonzero_o),
		.class_tag_error_o(),
		.record_tag_error_o(),
		.char_tag_error_o(),
		.row_tag_error_o(),
		.token_owner_overflow_o(),
		.token_owner_underflow_o(),
		.outer_stale_error_o(),
		.protocol_error_o(object_engine_protocol_error_w)
	);

	assign object_decode_grant_w = object_decode_query_valid_w &&
		!affine_mode_owned_w && !backend_raw_valid_w;
	assign object_decode_conflict_w = object_decode_query_valid_w &&
		(affine_mode_owned_w || backend_raw_valid_w);

	// Capture Affine diagnostics on the root command edge.
	vip_xp_affine_decode u_affine_descriptor_decode
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(engine_abort_i),
		.descriptor_valid_i(command_fire_w &&
			(engine_cmd_kind_i == 2'd2)),
		.descriptor_ready_o(),
		.descriptor_accept_o(affine_descriptor_accept_o),
		.descriptor_i(normal_external_descriptor_w),
		.gplt_active_i(gplt_active_i),
		.record_valid_o(affine_descriptor_record_valid_o),
		.record_ready_i(engine_done_o),
		.descriptor_raw_o(),
		.gplt_active_o(),
		.word0_o(),
		.lon_o(),
		.ron_o(),
		.kind_o(),
		.kind_valid_o(),
		.scx_o(),
		.scy_o(),
		.over_o(),
		.end_o(),
		.dummy_o(),
		.bgmap_base_raw_o(),
		.gx_o(),
		.gp_o(),
		.gy_o(),
		.ignored_mx_raw_o(),
		.ignored_mp_raw_o(),
		.ignored_my_raw_o(),
		.raw_w_o(),
		.raw_h_o(),
		.param_base_o(),
		.overplane_o(),
		.semantic_width_o(),
		.semantic_height_o(),
		.visual_start_y_o(),
		.visual_end_y_exclusive_o(),
		.maps_wide_o(),
		.maps_high_o(),
		.effective_map_count_o(),
		.effective_map_columns_o(),
		.bgmap_base_rounded_o(),
		.descriptor_kind_mismatch_o(
			affine_descriptor_kind_mismatch_o),
		.raw_w_upper_nonzero_o(affine_raw_w_upper_nonzero_o),
		.raw_w_documented_range_high_o(
			affine_raw_w_documented_range_high_o),
		.raw_h_negative_o(affine_raw_h_negative_o),
		.raw_h_documented_range_high_o(
			affine_raw_h_documented_range_high_o),
		.strict_overplane_high_o(
			affine_strict_overplane_qualification_o),
		.param_base_unaligned_o(affine_param_base_unaligned_o),
		.malformed_descriptor_o(affine_malformed_descriptor_o),
		.strict_policy_violation_o(
			affine_strict_policy_violation_o),
		.work_behavior_unresolved_o(
			affine_work_behavior_unresolved_o),
		.live_lon_o(affine_descriptor_left_on_w),
		.live_ron_o(affine_descriptor_right_on_w),
		.live_over_o(affine_descriptor_over_w),
		.live_gx_o(affine_descriptor_gx_w),
		.live_gp_o(affine_descriptor_gp_w),
		.live_gy_o(affine_descriptor_gy_w),
		.live_param_base_o(affine_descriptor_param_base_w),
		.live_overplane_o(affine_descriptor_overplane_w),
		.live_semantic_width_o(affine_descriptor_width_w),
		.live_semantic_height_o(affine_descriptor_height_w),
		.live_maps_wide_o(affine_descriptor_maps_wide_w),
		.live_maps_high_o(affine_descriptor_maps_high_w),
		.live_effective_map_columns_o(
			affine_descriptor_effective_columns_w),
		.live_bgmap_base_rounded_o(
			affine_descriptor_base_rounded_w),
		.live_descriptor_kind_mismatch_o(),
		.live_raw_w_upper_nonzero_o(),
		.live_raw_w_documented_range_high_o(),
		.live_raw_h_negative_o(),
		.live_raw_h_documented_range_high_o(),
		.live_strict_overplane_high_o(),
		.live_param_base_unaligned_o(),
		.live_malformed_descriptor_o(),
		.live_strict_policy_violation_o(
			affine_descriptor_strict_policy_w),
		.live_work_behavior_unresolved_o()
	);

	vip_xp_affine_frontend
	#(
		.COMPOSED_TIMING_CREDIT_ENABLE(
			COMPOSED_TIMING_CREDIT_ENABLE)
	)
	u_affine_frontend
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(engine_abort_i),
		.start_valid_i(affine_start_valid_w),
		.start_ready_o(affine_start_ready_w),
		.start_accept_o(affine_start_accept_w),
		.strict_policy_violation_i(
			affine_descriptor_strict_policy_w),
		.parallax_scale_i(command_parallax_scale_q),
		.world_i(normal_external_world_w),
		.strip_i(normal_external_strip_w),
		.first_visit_i(normal_external_first_visit_w),
		.gy_i(affine_descriptor_gy_w),
		.semantic_width_i(affine_descriptor_width_w),
		.semantic_height_i(affine_descriptor_height_w),
		.param_base_i(affine_descriptor_param_base_w),
		.gx_i({{6{affine_descriptor_gx_w[9]}},
			affine_descriptor_gx_w}),
		.gp_i({{6{affine_descriptor_gp_w[9]}},
			affine_descriptor_gp_w}),
		.left_on_i(affine_descriptor_left_on_w),
		.right_on_i(affine_descriptor_right_on_w),
		.maps_wide_i(affine_descriptor_maps_wide_w),
		.maps_high_i(affine_descriptor_maps_high_w),
		.effective_map_columns_i(
			affine_descriptor_effective_columns_w),
		.bgmap_base_rounded_i(affine_descriptor_base_rounded_w),
		.over_i(affine_descriptor_over_w),
		.overplane_i(affine_descriptor_overplane_w),
		.gplt_active_i(gplt_active_i),
		.address_source_x_o(affine_address_source_x_w),
		.address_source_y_o(affine_address_source_y_w),
		.address_maps_wide_o(affine_address_maps_wide_w),
		.address_maps_high_o(affine_address_maps_high_w),
		.address_effective_map_columns_o(
			affine_address_effective_columns_w),
		.address_bgmap_base_rounded_o(
			affine_address_base_rounded_w),
		.address_over_o(affine_address_over_w),
		.address_overplane_o(affine_address_overplane_w),
		.address_cell_o(affine_address_cell_w),
		.address_cell_source_row_o(affine_address_cell_row_w),
		.addressed_dram_cell_addr_i(
			affine_addressed_dram_cell_addr_w),
		.addressed_overplane_selected_i(
			affine_addressed_overplane_selected_w),
		.addressed_strict_overplane_i(
			affine_addressed_strict_overplane_w),
		.addressed_map_index_overflow_i(
			affine_addressed_map_overflow_w),
		.addressed_vrm_character_row_addr_i(
			affine_addressed_vrm_char_addr_w),
		.addressed_palette_i(affine_addressed_palette_w),
		.addressed_hflip_i(affine_addressed_hflip_w),
		.addressed_vflip_i(affine_addressed_vflip_w),
		.busy_o(affine_busy_w),
		.done_o(affine_done_w),
		.reject_pulse_o(affine_reject_pulse_o),
		.abort_done_pulse_o(affine_abort_done_pulse_o),
		.invalid_width_reject_o(affine_invalid_width_reject_o),
		.unaligned_param_reject_o(affine_unaligned_param_reject_o),
		.strict_policy_reject_o(affine_strict_policy_reject_o),
		.nonzero_mp_fault_o(affine_nonzero_mp_fault_o),
		.nonzero_mp_policy_seen_o(affine_nonzero_mp_policy_seen_o),
		.raw_abort_seen_o(affine_raw_abort_seen_o),
		.local_abort_active_o(affine_local_abort_active_o),
		.dram_abort_o(affine_dram_abort_w),
		.dram_req_o(affine_dram_req_w),
		.dram_addr_o(affine_dram_addr_w),
		.dram_accept_i(affine_dram_accept_w),
		.dram_resp_valid_i(affine_dram_resp_valid_w),
		.dram_resp_data_i(affine_dram_resp_data_w),
		.dram_cleanup_busy_i(affine_dram_cleanup_busy_w),
		.dram_stale_discard_i(affine_dram_stale_discard_w),
		.char_vrm_abort_o(affine_vrm_abort_w),
		.char_vrm_req_o(affine_vrm_req_w),
		.char_vrm_addr_o(affine_vrm_addr_w),
		.char_vrm_accept_i(affine_vrm_accept_w),
		.char_vrm_resp_valid_i(affine_vrm_resp_valid_w),
		.char_vrm_resp_data_i(affine_vrm_resp_data_w),
		.char_vrm_cleanup_busy_i(affine_vrm_cleanup_busy_w),
		.char_vrm_stale_discard_i(affine_vrm_stale_discard_w),
		.decode_character_row_o(affine_decode_character_row_w),
		.decode_palette_o(affine_decode_palette_w),
		.decode_hflip_o(affine_decode_hflip_w),
		.decode_source_x_index_o(affine_decode_source_x_w),
		.decode_gplt_active_o(affine_decode_gplt_w),
		.decoded_raw_pixel_i(affine_decoded_raw_pixel_w),
		.decoded_raw_nonzero_i(affine_decoded_raw_nonzero_w),
		.decoded_mapped_pixel_i(affine_decoded_mapped_pixel_w),
		.row_store_abort_o(affine_abort_o),
		.affine_prepare_valid_o(affine_prepare_valid_o),
		.affine_prepare_ready_i(affine_prepare_ready_i),
		.affine_prepare_accept_o(affine_prepare_accept_o),
		.affine_prepare_row_o(affine_prepare_row_o),
		.affine_prepare_left_base_x_o(affine_prepare_left_base_x_o),
		.affine_prepare_left_enable_o(affine_prepare_left_enable_o),
		.affine_prepare_right_base_x_o(affine_prepare_right_base_x_o),
		.affine_prepare_right_enable_o(affine_prepare_right_enable_o),
		.affine_commit_valid_o(affine_commit_valid_o),
		.affine_commit_ready_i(affine_commit_ready_i),
		.affine_commit_accept_o(affine_commit_accept_o),
		.affine_commit_left_active_o(affine_commit_left_active_o),
		.affine_commit_left_opaque_o(affine_commit_left_opaque_o),
		.affine_commit_left_values_o(affine_commit_left_values_o),
		.affine_commit_right_active_o(affine_commit_right_active_o),
		.affine_commit_right_opaque_o(affine_commit_right_opaque_o),
		.affine_commit_right_values_o(affine_commit_right_values_o),
		.affine_store_quiescent_i(affine_store_quiescent_i),
		.scheduler_state_o(affine_scheduler_state_o),
		.scheduler_ticks_remaining_o(
			affine_scheduler_ticks_remaining_o),
		.scheduler_pixel_ordinal_o(affine_scheduler_pixel_ordinal_o),
		.scheduler_pixel_accept_o(affine_scheduler_pixel_accept_o),
		.sample_state_o(affine_sample_state_o),
		.sample_prime_complete_o(affine_sample_prime_complete_o),
		.sample_result_accept_o(affine_sample_result_accept_o),
		.packer_prepare_accept_o(affine_packer_prepare_accept_o),
		.packer_commit_accept_o(affine_packer_commit_accept_o),
		.actual_downstream_idle_o(affine_downstream_idle_o),
		.final_will_be_idle_o(affine_final_will_be_idle_o),
		.cleanup_interlock_o(affine_cleanup_interlock_o),
		.param_dram_selected_o(affine_param_dram_selected_o),
		.dram_mux_held_offer_o(),
		.dram_mux_read_pending_o(),
		.scheduler_elapsed_ticks_o(affine_scheduler_elapsed_ticks_o),
		.scheduler_row_setup_ticks_o(
			affine_scheduler_row_setup_ticks_o),
		.scheduler_pixel_ticks_o(affine_scheduler_pixel_ticks_o),
		.scheduler_stall_ticks_o(affine_scheduler_stall_ticks_o),
		.scheduler_row_start_count_o(
			affine_scheduler_row_start_count_o),
		.scheduler_row_context_count_o(
			affine_scheduler_row_context_count_o),
		.scheduler_pixel_count_o(affine_scheduler_pixel_count_o),
		.sample_strict_overplane_seen_o(
			affine_sample_strict_overplane_seen_o),
		.sample_map_index_overflow_seen_o(
			affine_sample_map_index_overflow_seen_o),
		.protocol_error_o(affine_frontend_protocol_error_w)
	);

	vip_xp_bg_shared_backend
	#(
		.EXTERNAL_DECODE_SEAM(1),
		.EXTERNAL_ADDRESS_SEAM(1)
	)
	u_shared_backend
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(engine_abort_i),
		.diagnostic_rearm_i(normal_command_accept_w ||
			hbias_bg_rearm_w || affine_start_accept_w ||
			object_backend_rearm_pending_q),
		.diagnostic_rearm_ready_o(backend_rearm_ready_w),
		.diagnostic_rearm_accept_o(backend_rearm_accept_w),
		.diagnostic_rearm_rejected_o(backend_rearm_rejected_w),
		.controller_owner_i(selected_bg_owner_w),
		.maps_wide_i(selected_bg_maps_wide_w),
		.maps_high_i(selected_bg_maps_high_w),
		.effective_map_columns_i(selected_bg_effective_columns_w),
		.bgmap_base_rounded_i(selected_bg_base_rounded_w),
		.over_i(selected_bg_over_w),
		.overplane_i(selected_bg_overplane_w),
		.left_on_i(selected_bg_left_on_w),
		.right_on_i(selected_bg_right_on_w),
		.left_source_start_i(selected_bg_left_source_w),
		.right_source_start_i(selected_bg_right_source_w),
		.left_destination_start_i(selected_bg_left_destination_w),
		.right_destination_start_i(selected_bg_right_destination_w),
		.semantic_width_i(selected_bg_width_w),
		.gplt_active_i(selected_bg_gplt_w),
		.external_decode_select_i(affine_mode_owned_w ||
			object_decode_query_valid_w),
		.external_decode_character_row_i(affine_mode_owned_w ?
			affine_decode_character_row_w :
			object_decode_character_row_w),
		.external_decode_palette_i(affine_mode_owned_w ?
			affine_decode_palette_w : object_decode_palette_w),
		.external_decode_hflip_i(affine_mode_owned_w ?
			affine_decode_hflip_w : object_decode_hflip_w),
		.external_decode_source_x_index_i(affine_mode_owned_w ?
			affine_decode_source_x_w : 3'd0),
		.external_decode_gplt_active_i(affine_mode_owned_w ?
			affine_decode_gplt_w : object_decode_jplt_w),
		.external_decoded_raw_pixel_o(affine_decoded_raw_pixel_w),
		.external_decoded_raw_nonzero_o(
			affine_decoded_raw_nonzero_w),
		.external_decoded_mapped_pixel_o(
			affine_decoded_mapped_pixel_w),
		.external_decoded_raw_pixels_o(),
		.external_decoded_raw_nonzero_vector_o(
			shared_decoded_raw_nonzero_w),
		.external_decoded_mapped_pixels_o(
			shared_decoded_mapped_pixels_w),
		.external_decode_mode_conflict_o(
			external_decode_mode_conflict_o),
		.external_address_select_i(affine_mode_owned_w),
		.external_address_source_x_i(affine_address_source_x_w),
		.external_address_source_y_i(affine_address_source_y_w),
		.external_address_maps_wide_i(affine_address_maps_wide_w),
		.external_address_maps_high_i(affine_address_maps_high_w),
		.external_address_effective_map_columns_i(
			affine_address_effective_columns_w),
		.external_address_bgmap_base_rounded_i(
			affine_address_base_rounded_w),
		.external_address_over_i(affine_address_over_w),
		.external_address_overplane_i(affine_address_overplane_w),
		.external_address_cell_i(affine_address_cell_w),
		.external_address_cell_source_row_i(affine_address_cell_row_w),
		.external_addressed_dram_cell_addr_o(
			affine_addressed_dram_cell_addr_w),
		.external_addressed_overplane_selected_o(
			affine_addressed_overplane_selected_w),
		.external_addressed_strict_overplane_o(
			affine_addressed_strict_overplane_w),
		.external_addressed_map_index_overflow_o(
			affine_addressed_map_overflow_w),
		.external_addressed_vrm_character_row_addr_o(
			affine_addressed_vrm_char_addr_w),
		.external_addressed_palette_o(affine_addressed_palette_w),
		.external_addressed_hflip_o(affine_addressed_hflip_w),
		.external_addressed_vflip_o(affine_addressed_vflip_w),
		.external_address_mode_conflict_o(
			external_address_mode_conflict_o),
		.tile_row_valid_i(selected_bg_tile_row_valid_w),
		.tile_row_ready_o(backend_tile_row_ready_w),
		.tile_row_load_i(selected_bg_tile_row_load_w),
		.tile_row_screen_y_i(selected_bg_tile_row_screen_y_w),
		.tile_row_source_y_i(selected_bg_tile_row_source_y_w),
		.tile_valid_i(selected_bg_tile_valid_w),
		.tile_ready_o(backend_tile_ready_w),
		.tile_load_i(selected_bg_tile_load_w),
		.tile_ordinal_i(selected_bg_tile_ordinal_w),
		.tile_x_i(selected_bg_tile_x_w),
		.row_valid_i(selected_bg_row_valid_w),
		.row_ready_o(backend_row_ready_w),
		.row_load_i(selected_bg_row_load_w),
		.row_tile_ordinal_i(selected_bg_row_tile_ordinal_w),
		.row_ordinal_i(selected_bg_row_ordinal_w),
		.row_source_index_i(selected_bg_row_source_index_w),
		.row_screen_y_i(selected_bg_row_screen_y_w),
		.row_source_y_i(selected_bg_row_source_y_w),
		.result_permit_i(selected_bg_result_permit_w),
		.dram_req_o(backend_cell_req_w),
		.dram_addr_o(backend_cell_addr_w),
		.dram_accept_i(backend_cell_accept_w),
		.dram_resp_valid_i(backend_cell_resp_valid_w),
		.dram_resp_data_i(backend_cell_resp_data_w),
		.dram_router_cleanup_busy_i(backend_cell_cleanup_busy_w),
		.dram_router_stale_discard_i(backend_cell_stale_discard_w),
		.vrm_req_o(backend_vrm_req_w),
		.vrm_addr_o(backend_vrm_addr_w),
		.vrm_accept_i(backend_vrm_accept_w),
		.vrm_resp_valid_i(backend_vrm_resp_valid_w),
		.vrm_resp_data_i(backend_vrm_resp_data_w),
		.vrm_router_cleanup_busy_i(backend_vrm_cleanup_busy_w),
		.vrm_router_stale_discard_i(backend_vrm_stale_discard_w),
		.raw_result_valid_o(backend_raw_valid_w),
		.raw_result_accept_o(backend_raw_accept_w),
		.raw_result_owner_o(backend_raw_owner_w),
		.raw_result_load_o(backend_raw_load_w),
		.raw_result_tile_ordinal_o(backend_raw_tile_ordinal_w),
		.raw_result_row_ordinal_o(backend_raw_row_ordinal_w),
		.raw_result_tile_x_o(backend_raw_tile_x_w),
		.raw_result_screen_y_o(backend_raw_screen_y_w),
		.raw_result_source_y_o(backend_raw_source_y_w),
		.raw_result_source_index_o(backend_raw_source_index_w),
		.raw_result_tile_row_screen_y_o(
			backend_raw_context_screen_y_w),
		.raw_result_tile_row_source_y_o(
			backend_raw_context_source_y_w),
		.raw_result_cell_o(),
		.raw_result_character_row_o(),
		.raw_result_palette_o(),
		.raw_result_hflip_o(),
		.raw_result_vflip_o(),
		.raw_result_overplane_selected_o(
			backend_raw_overplane_selected_w),
		.raw_result_strict_overplane_o(backend_raw_strict_overplane_w),
		.token_valid_o(backend_token_valid_w),
		.token_ready_i(backend_token_ready_w),
		.token_accept_o(backend_token_accept_w),
		.token_row_o(backend_token_row_w),
		.token_left_base_x_o(backend_token_left_base_x_w),
		.token_left_enable_o(backend_token_left_enable_w),
		.token_left_active_o(backend_token_left_active_w),
		.token_left_opaque_o(backend_token_left_opaque_w),
		.token_left_values_o(backend_token_left_values_w),
		.token_right_base_x_o(backend_token_right_base_x_w),
		.token_right_enable_o(backend_token_right_enable_w),
		.token_right_active_o(backend_token_right_active_w),
		.token_right_opaque_o(backend_token_right_opaque_w),
		.token_right_values_o(backend_token_right_values_w),
		.token_owner_o(backend_token_owner_w),
		.token_load_o(backend_token_load_w),
		.token_tile_ordinal_o(backend_token_tile_ordinal_w),
		.token_row_ordinal_o(backend_token_row_ordinal_w),
		.token_tile_x_o(backend_token_tile_x_w),
		.token_screen_y_o(backend_token_screen_y_w),
		.token_source_y_o(backend_token_source_y_w),
		.token_source_index_o(backend_token_source_index_w),
		.token_tile_row_screen_y_o(backend_token_context_screen_y_w),
		.token_tile_row_source_y_o(backend_token_context_source_y_w),
		.token_overplane_selected_o(backend_token_overplane_selected_w),
		.token_strict_overplane_o(backend_token_strict_overplane_w),
		.context_accept_o(backend_context_accept_w),
		.context_owner_valid_o(backend_context_owner_valid_w),
		.active_context_owner_o(backend_context_owner_w),
		.busy_o(backend_busy_w),
		.fetch_busy_o(backend_fetch_busy_w),
		.cleanup_busy_o(backend_cleanup_busy_w),
		.dram_read_pending_o(backend_dram_pending_w),
		.vrm_read_pending_o(backend_vrm_pending_w),
		.dram_stale_response_discarded_o(),
		.vrm_stale_response_discarded_o(),
		.unexpected_dram_response_o(backend_unexpected_dram_w),
		.unexpected_vrm_response_o(backend_unexpected_vrm_w),
		.response_capture_overflow_o(backend_capture_overflow_w),
		.scheduler_tag_mismatch_o(backend_tag_mismatch_w),
		.concurrent_work_error_o(backend_concurrent_work_w),
		.strict_overplane_seen_o(backend_strict_overplane_seen_w),
		.map_index_overflow_seen_o(backend_map_overflow_seen_w),
		.diag_blend_input_accept_count_o(),
		.diag_token_accept_count_o()
	);

	// Normal and H-bias share the inner PARAM/CELL mux.
	vip_xp_hbias_dram_mux u_hbias_dram_mux
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(engine_abort_i),
		.param_req_i(hbias_param_req_w),
		.param_addr_i(hbias_param_addr_w),
		.param_accept_o(hbias_param_accept_w),
		.param_resp_valid_o(hbias_param_resp_valid_w),
		.param_resp_data_o(hbias_param_resp_data_w),
		.param_cleanup_busy_o(hbias_param_cleanup_busy_w),
		.param_stale_discarded_o(hbias_param_stale_discard_w),
		.cell_req_i(backend_cell_req_w),
		.cell_addr_i(backend_cell_addr_w),
		.cell_accept_o(backend_cell_accept_w),
		.cell_resp_valid_o(backend_cell_resp_valid_w),
		.cell_resp_data_o(backend_cell_resp_data_w),
		.cell_cleanup_busy_o(backend_cell_cleanup_busy_w),
		.cell_stale_discarded_o(backend_cell_stale_discard_w),
		.aggregate_abort_o(),
		.aggregate_req_o(local_dram_req_w),
		.aggregate_addr_o(local_dram_addr_w),
		.aggregate_accept_i(local_dram_accept_w),
		.aggregate_resp_valid_i(local_dram_resp_valid_w),
		.aggregate_resp_data_i(local_dram_resp_data_w),
		.aggregate_cleanup_busy_i(local_dram_cleanup_busy_w),
		.aggregate_stale_discarded_i(local_dram_stale_discard_w),
		.accepted_owner_o(hbias_dram_accepted_owner_o),
		.held_offer_o(hbias_dram_offer_held_o),
		.held_owner_o(hbias_dram_held_owner_o),
		.read_pending_o(hbias_dram_read_pending_o),
		.pending_owner_o(hbias_dram_pending_owner_o),
		.accept_without_offer_o(dram_inner_accept_error_w),
		.retire_without_pending_o(dram_inner_retire_error_w),
		.outstanding_overlap_o(dram_inner_overlap_error_w)
	);

	vip_xp_read_subclient_mux u_mode_dram_mux
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.global_abort_i(engine_abort_i),
		.external_abort_i(affine_dram_abort_w),
		.internal_req_i(local_dram_req_w),
		.internal_addr_i(local_dram_addr_w),
		.internal_accept_o(local_dram_accept_w),
		.internal_resp_valid_o(local_dram_resp_valid_w),
		.internal_resp_data_o(local_dram_resp_data_w),
		.internal_cleanup_busy_o(local_dram_cleanup_busy_w),
		.internal_stale_discarded_o(local_dram_stale_discard_w),
		.external_req_i(affine_dram_req_w),
		.external_addr_i(affine_dram_addr_w),
		.external_accept_o(affine_dram_accept_w),
		.external_resp_valid_o(affine_dram_resp_valid_w),
		.external_resp_data_o(affine_dram_resp_data_w),
		.external_cleanup_busy_o(affine_dram_cleanup_busy_w),
		.external_stale_discarded_o(affine_dram_stale_discard_w),
		.aggregate_abort_o(shared_dram_abort_w),
		.aggregate_req_o(shared_dram_req_w),
		.aggregate_addr_o(shared_dram_addr_w),
		.aggregate_accept_i(shared_dram_accept_w),
		.aggregate_resp_valid_i(shared_dram_resp_valid_w),
		.aggregate_resp_data_i(shared_dram_resp_data_w),
		.aggregate_cleanup_busy_i(shared_dram_cleanup_busy_w),
		.aggregate_stale_discarded_i(shared_dram_stale_discard_w),
		.held_offer_o(dram_mode_held_w),
		.held_owner_internal_o(dram_mode_held_internal_w),
		.read_pending_o(dram_mode_pending_w),
		.pending_owner_internal_o(dram_mode_pending_internal_w),
		.accept_without_offer_o(dram_mode_accept_error_w),
		.retire_without_pending_o(dram_mode_retire_error_w),
		.outstanding_overlap_o(dram_mode_overlap_error_w)
	);

	// Retain character-read ownership through response.
	vip_xp_read_subclient_mux u_mode_vrm_mux
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.global_abort_i(engine_abort_i),
		.external_abort_i(affine_vrm_abort_w),
		.internal_req_i(backend_vrm_req_w),
		.internal_addr_i(backend_vrm_addr_w),
		.internal_accept_o(backend_vrm_accept_w),
		.internal_resp_valid_o(backend_vrm_resp_valid_w),
		.internal_resp_data_o(backend_vrm_resp_data_w),
		.internal_cleanup_busy_o(backend_vrm_cleanup_busy_w),
		.internal_stale_discarded_o(backend_vrm_stale_discard_w),
		.external_req_i(affine_vrm_req_w),
		.external_addr_i(affine_vrm_addr_w),
		.external_accept_o(affine_vrm_accept_w),
		.external_resp_valid_o(affine_vrm_resp_valid_w),
		.external_resp_data_o(affine_vrm_resp_data_w),
		.external_cleanup_busy_o(affine_vrm_cleanup_busy_w),
		.external_stale_discarded_o(affine_vrm_stale_discard_w),
		.aggregate_abort_o(shared_vrm_abort_w),
		.aggregate_req_o(shared_vrm_req_w),
		.aggregate_addr_o(shared_vrm_addr_w),
		.aggregate_accept_i(shared_vrm_accept_w),
		.aggregate_resp_valid_i(shared_vrm_resp_valid_w),
		.aggregate_resp_data_i(shared_vrm_resp_data_w),
		.aggregate_cleanup_busy_i(shared_vrm_cleanup_busy_w),
		.aggregate_stale_discarded_i(shared_vrm_stale_discard_w),
		.held_offer_o(vrm_mode_held_w),
		.held_owner_internal_o(vrm_mode_held_internal_w),
		.read_pending_o(vrm_mode_pending_w),
		.pending_owner_internal_o(vrm_mode_pending_internal_w),
		.accept_without_offer_o(vrm_mode_accept_error_w),
		.retire_without_pending_o(vrm_mode_retire_error_w),
		.outstanding_overlap_o(vrm_mode_overlap_error_w)
	);

	// Outer DRAM arbitration joins background/Affine with Object OAM.
	vip_xp_read_subclient_mux u_object_dram_mux
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.global_abort_i(engine_abort_i || shared_dram_abort_w),
		.external_abort_i(engine_abort_i),
		.internal_req_i(shared_dram_req_w),
		.internal_addr_i(shared_dram_addr_w),
		.internal_accept_o(shared_dram_accept_w),
		.internal_resp_valid_o(shared_dram_resp_valid_w),
		.internal_resp_data_o(shared_dram_resp_data_w),
		.internal_cleanup_busy_o(shared_dram_cleanup_busy_w),
		.internal_stale_discarded_o(shared_dram_stale_discard_w),
		.external_req_i(object_oam_req_w),
		.external_addr_i(object_oam_addr_w),
		.external_accept_o(object_oam_accept_w),
		.external_resp_valid_o(object_oam_resp_valid_w),
		.external_resp_data_o(object_oam_resp_data_w),
		.external_cleanup_busy_o(object_oam_cleanup_busy_w),
		.external_stale_discarded_o(object_oam_stale_discard_w),
		.aggregate_abort_o(aggregate_dram_abort_o),
		.aggregate_req_o(aggregate_dram_req_o),
		.aggregate_addr_o(aggregate_dram_addr_o),
		.aggregate_accept_i(aggregate_dram_accept_i),
		.aggregate_resp_valid_i(aggregate_dram_resp_valid_i),
		.aggregate_resp_data_i(aggregate_dram_resp_data_i),
		.aggregate_cleanup_busy_i(aggregate_dram_cleanup_busy_i),
		.aggregate_stale_discarded_i(aggregate_dram_stale_discard_i),
		.held_offer_o(dram_outer_held_w),
		.held_owner_internal_o(dram_outer_held_internal_w),
		.read_pending_o(dram_outer_pending_w),
		.pending_owner_internal_o(dram_outer_pending_internal_w),
		.accept_without_offer_o(dram_outer_accept_error_w),
		.retire_without_pending_o(dram_outer_retire_error_w),
		.outstanding_overlap_o(dram_outer_overlap_error_w)
	);

	// Background/Affine has fresh-offer priority over Object character reads.
	vip_xp_read_subclient_mux u_object_vrm_mux
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.global_abort_i(engine_abort_i || shared_vrm_abort_w),
		.external_abort_i(engine_abort_i),
		.internal_req_i(shared_vrm_req_w),
		.internal_addr_i(shared_vrm_addr_w),
		.internal_accept_o(shared_vrm_accept_w),
		.internal_resp_valid_o(shared_vrm_resp_valid_w),
		.internal_resp_data_o(shared_vrm_resp_data_w),
		.internal_cleanup_busy_o(shared_vrm_cleanup_busy_w),
		.internal_stale_discarded_o(shared_vrm_stale_discard_w),
		.external_req_i(object_char_req_w),
		.external_addr_i(object_char_addr_w),
		.external_accept_o(object_char_accept_w),
		.external_resp_valid_o(object_char_resp_valid_w),
		.external_resp_data_o(object_char_resp_data_w),
		.external_cleanup_busy_o(object_char_cleanup_busy_w),
		.external_stale_discarded_o(object_char_stale_discard_w),
		.aggregate_abort_o(aggregate_vrm_abort_o),
		.aggregate_req_o(aggregate_vrm_req_o),
		.aggregate_addr_o(aggregate_vrm_addr_o),
		.aggregate_accept_i(aggregate_vrm_accept_i),
		.aggregate_resp_valid_i(aggregate_vrm_resp_valid_i),
		.aggregate_resp_data_i(aggregate_vrm_resp_data_i),
		.aggregate_cleanup_busy_i(aggregate_vrm_cleanup_busy_i),
		.aggregate_stale_discarded_i(aggregate_vrm_stale_discard_i),
		.held_offer_o(vrm_outer_held_w),
		.held_owner_internal_o(vrm_outer_held_internal_w),
		.read_pending_o(vrm_outer_pending_w),
		.pending_owner_internal_o(vrm_outer_pending_internal_w),
		.accept_without_offer_o(vrm_outer_accept_error_w),
		.retire_without_pending_o(vrm_outer_retire_error_w),
		.outstanding_overlap_o(vrm_outer_overlap_error_w)
	);

	vip_xp_row_owner_mux u_row_owner_fifo
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(engine_abort_i),
		.normal_valid_i(backend_token_normal_w),
		.normal_ready_o(normal_row_ready_w),
		.normal_done_o(normal_row_done_o),
		.normal_row_i(backend_token_row_w),
		.normal_left_base_x_i(backend_token_left_base_x_w),
		.normal_left_enable_i(backend_token_left_enable_w),
		.normal_left_active_i(backend_token_left_active_w),
		.normal_left_opaque_i(backend_token_left_opaque_w),
		.normal_left_values_i(backend_token_left_values_w),
		.normal_right_base_x_i(backend_token_right_base_x_w),
		.normal_right_enable_i(backend_token_right_enable_w),
		.normal_right_active_i(backend_token_right_active_w),
		.normal_right_opaque_i(backend_token_right_opaque_w),
		.normal_right_values_i(backend_token_right_values_w),
		.hbias_valid_i(hbias_row_valid_w),
		.hbias_ready_o(hbias_row_ready_w),
		.hbias_done_o(hbias_row_done_o),
		.hbias_row_i(hbias_row_row_w),
		.hbias_left_base_x_i(hbias_row_left_base_x_w),
		.hbias_left_enable_i(hbias_row_left_enable_w),
		.hbias_left_active_i(hbias_row_left_active_w),
		.hbias_left_opaque_i(hbias_row_left_opaque_w),
		.hbias_left_values_i(hbias_row_left_values_w),
		.hbias_right_base_x_i(hbias_row_right_base_x_w),
		.hbias_right_enable_i(hbias_row_right_enable_w),
		.hbias_right_active_i(hbias_row_right_active_w),
		.hbias_right_opaque_i(hbias_row_right_opaque_w),
		.hbias_right_values_i(hbias_row_right_values_w),
		.object_valid_i(object_token_valid_w),
		.object_ready_o(object_token_ready_w),
		.object_done_o(object_row_done_o),
		.object_row_i(object_token_row_w),
		.object_left_base_x_i(object_token_left_base_w),
		.object_left_enable_i(object_token_left_enable_w),
		.object_left_active_i(object_token_left_active_w),
		.object_left_opaque_i(object_token_left_opaque_w),
		.object_left_values_i(object_token_left_values_w),
		.object_right_base_x_i(object_token_right_base_w),
		.object_right_enable_i(object_token_right_enable_w),
		.object_right_active_i(object_token_right_active_w),
		.object_right_opaque_i(object_token_right_opaque_w),
		.object_right_values_i(object_token_right_values_w),
		.producer_valid_o(row_producer_valid_o),
		.producer_ready_i(row_producer_ready_i),
		.producer_done_i(row_producer_done_i),
		.producer_row_o(row_producer_row_o),
		.producer_left_base_x_o(row_producer_left_base_x_o),
		.producer_left_enable_o(row_producer_left_enable_o),
		.producer_left_active_o(row_producer_left_active_o),
		.producer_left_opaque_o(row_producer_left_opaque_o),
		.producer_left_values_o(row_producer_left_values_o),
		.producer_right_base_x_o(row_producer_right_base_x_o),
		.producer_right_enable_o(row_producer_right_enable_o),
		.producer_right_active_o(row_producer_right_active_o),
		.producer_right_opaque_o(row_producer_right_opaque_o),
		.producer_right_values_o(row_producer_right_values_o),
		.owner_count_o(row_owner_count_o),
		.owner_head_pointer_o(),
		.owner_tail_pointer_o(),
		.owner_head_o(row_owner_head_o),
		.owner_tail_o(row_owner_tail_o),
		.offer_held_o(row_offer_held_o),
		.offer_owner_o(row_offer_owner_o),
		.owner_overflow_o(row_owner_overflow_w),
		.owner_underflow_o(row_owner_underflow_w),
		.simultaneous_offer_o(row_simultaneous_offer_w),
		.owner_protocol_error_o(row_owner_protocol_error_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	// Raw abort hides the command while accepted memory work drains.
	always @(posedge clk_i) begin
		if (reset_i) begin
			command_active_q <= 1'b0;
			command_kind_q <= 2'd0;
			command_strip_q <= 5'd0;
			command_world_q <= 5'd0;
			command_descriptor_q <= 256'd0;
			command_first_visit_q <= 1'b0;
			command_gplt_q <= 32'd0;
			command_parallax_scale_q <= 3'd0;
			object_epoch_counter_q <= 4'd0;
			command_object_epoch_q <= 4'd0;
			command_object_group_q <= 2'd3;
			command_object_ordinal_q <= 6'd0;
			command_object_penalty_q <= 1'b0;
			object_backend_rearm_pending_q <= 1'b0;
			completion_pending_q <= 1'b0;
			unexpected_completion_o <= 1'b0;
			engine_request_overlap_o <= 1'b0;
			object_start_mismatch_q <= 1'b0;
		end else begin
			if (engine_abort_i) begin
				command_active_q <= 1'b0;
				completion_pending_q <= 1'b0;
				object_backend_rearm_pending_q <= 1'b0;
			end

			if (ce_i) begin
				if (!engine_abort_i) begin
					if (object_start_accept_w) begin
						object_backend_rearm_pending_q <= 1'b1;
					end else if (backend_rearm_accept_w) begin
						object_backend_rearm_pending_q <= 1'b0;
					end
					if (command_fire_w) begin
						command_active_q <= 1'b1;
						command_kind_q <= engine_cmd_kind_i;
						command_strip_q <= engine_cmd_strip_i;
						command_world_q <= engine_cmd_world_i;
						command_descriptor_q <=
							engine_cmd_descriptor_i;
						command_first_visit_q <=
							engine_cmd_first_visit_i;
						command_gplt_q <= gplt_active_i;
						command_parallax_scale_q <=
							parallax_scale_i;
						if (engine_cmd_kind_i == 2'd3) begin
							command_object_epoch_q <=
								object_selected_epoch_w;
							command_object_group_q <=
								object_selected_group_w;
							command_object_ordinal_q <=
								object_selected_ordinal_w;
							command_object_penalty_q <=
								object_selected_penalty_w;
							object_epoch_counter_q <=
								object_epoch_counter_q + 4'd1;
						end
						completion_pending_q <=
							((engine_cmd_kind_i == 2'd2) &&
							 affine_done_w) ||
							((engine_cmd_kind_i == 2'd3) &&
							 object_done_w);
					end else if (engine_done_o) begin
						command_active_q <= 1'b0;
						completion_pending_q <= 1'b0;
					end else if (command_active_q &&
						selected_child_done_w) begin
						completion_pending_q <= 1'b1;
					end
				end

				if (hbias_done_w &&
					(!command_active_q ||
					 (command_kind_q != 2'd1))) begin
					unexpected_completion_o <= 1'b1;
				end
				if (affine_done_w && !affine_abort_done_pulse_o &&
					!((command_active_q && command_kind_q == 2'd2) ||
					  (command_fire_w && engine_cmd_kind_i == 2'd2))) begin
					unexpected_completion_o <= 1'b1;
				end
				if (object_done_w &&
					!((command_active_q && command_kind_q == 2'd3) ||
					  (command_fire_w && engine_cmd_kind_i == 2'd3))) begin
					unexpected_completion_o <= 1'b1;
				end

				if ((normal_active_o && hbias_active_o) ||
					(normal_active_o && affine_busy_w) ||
					(normal_active_o && object_busy_w) ||
					(hbias_active_o && affine_busy_w) ||
					(hbias_active_o && object_busy_w) ||
					(affine_busy_w && object_busy_w) ||
					(normal_bg_tile_row_valid_w &&
					 hbias_bg_tile_row_valid_w) ||
					(normal_bg_tile_valid_w && hbias_bg_tile_valid_w) ||
					(normal_bg_row_valid_w && hbias_bg_row_valid_w) ||
					(affine_mode_owned_w && backend_controller_work_w)) begin
					engine_request_overlap_o <= 1'b1;
				end
				if (hbias_command_accept_w !=
					(command_fire_w && engine_cmd_kind_i == 2'd1)) begin
					engine_request_overlap_o <= 1'b1;
				end
				if (affine_start_accept_w !=
					(command_fire_w && engine_cmd_kind_i == 2'd2)) begin
					engine_request_overlap_o <= 1'b1;
				end
				if (affine_descriptor_accept_o !=
					(command_fire_w && engine_cmd_kind_i == 2'd2)) begin
					engine_request_overlap_o <= 1'b1;
				end
				if (object_start_accept_w !=
					(command_fire_w && engine_cmd_kind_i == 2'd3)) begin
					object_start_mismatch_q <= 1'b1;
				end
			end
		end
	end

	// Attribute backend diagnostics to the retained context owner.
	wire backend_protocol_error_w = backend_unexpected_dram_w ||
		backend_unexpected_vrm_w || backend_capture_overflow_w ||
		backend_tag_mismatch_w || backend_concurrent_work_w;
	wire [1:0] backend_diagnostic_owner_w =
		backend_context_owner_valid_w ? backend_context_owner_w :
		(command_kind_q == 2'd0 ? OWNER_NORMAL :
		 (command_kind_q == 2'd1 ? OWNER_HBIAS :
		  (command_kind_q == 2'd2 ? OWNER_AFFINE : OWNER_NONE)));

	always @(posedge clk_i) begin
		if (reset_i) begin
			normal_fetch_error_q <= 1'b0;
			hbias_fetch_error_q <= 1'b0;
			affine_fetch_error_q <= 1'b0;
			object_fetch_error_q <= 1'b0;
			unowned_fetch_error_q <= 1'b0;
		end else if (ce_i) begin
			// Overplane and extended-map flags do not mark transport failure.
			if (backend_protocol_error_w) begin
				case (backend_diagnostic_owner_w)
					OWNER_NORMAL:
						normal_fetch_error_q <= 1'b1;
					OWNER_HBIAS:
						hbias_fetch_error_q <= 1'b1;
					OWNER_AFFINE:
						affine_fetch_error_q <= 1'b1;
					default:
						unowned_fetch_error_q <= 1'b1;
				endcase
			end
			if (backend_rearm_rejected_w) begin
				if (normal_command_accept_w ||
					(command_active_q && command_kind_q == 2'd0)) begin
					normal_fetch_error_q <= 1'b1;
				end else if (hbias_active_o || hbias_bg_rearm_w) begin
					hbias_fetch_error_q <= 1'b1;
				end else if (affine_busy_w || affine_start_accept_w) begin
					affine_fetch_error_q <= 1'b1;
				end else if (object_busy_w || object_start_accept_w) begin
					object_fetch_error_q <= 1'b1;
				end else begin
					unowned_fetch_error_q <= 1'b1;
				end
			end
		end
	end

`ifndef SYNTHESIS
	// Trace protocol failure on its first edge.
	always @(posedge clk_i) begin
		if (!reset_i && ce_i &&
			(backend_protocol_error_w || backend_rearm_rejected_w)) begin
			$display("VIP_BACKEND_ERROR owner=%0d unexpected_dram=%0d unexpected_vrm=%0d capture_overflow=%0d tag_mismatch=%0d concurrent=%0d strict_overplane=%0d map_overflow=%0d rearm_rejected=%0d command_active=%0d command_kind=%0d normal_active=%0d producer_outstanding=%0d",
				backend_diagnostic_owner_w,
				backend_unexpected_dram_w,
				backend_unexpected_vrm_w,
				backend_capture_overflow_w,
				backend_tag_mismatch_w,
				backend_concurrent_work_w,
				backend_strict_overplane_seen_w,
				backend_map_overflow_seen_w,
				backend_rearm_rejected_w,
				command_active_q,
				command_kind_q,
				normal_active_o,
				normal_producer_outstanding_o);
		end
	end
`endif

endmodule

// Shared background, memory arbitration, and Object rendering.

`timescale 1ns/1ps

// Read-only two-client mux for one renderer memory port.
//
// Internal requests have fresh-offer priority. A stalled offer keeps its owner
// and address. One read may be active, with same-edge response replacement.

module vip_xp_read_subclient_mux
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire        global_abort_i,
	input  wire        external_abort_i,

	input  wire        internal_req_i,
	input  wire [15:0] internal_addr_i,
	output wire        internal_accept_o,
	output wire        internal_resp_valid_o,
	output wire [15:0] internal_resp_data_o,
	output wire        internal_cleanup_busy_o,
	output wire        internal_stale_discarded_o,

	input  wire        external_req_i,
	input  wire [15:0] external_addr_i,
	output wire        external_accept_o,
	output wire        external_resp_valid_o,
	output wire [15:0] external_resp_data_o,
	output wire        external_cleanup_busy_o,
	output wire        external_stale_discarded_o,

	output wire        aggregate_abort_o,
	output wire        aggregate_req_o,
	output wire [15:0] aggregate_addr_o,
	input  wire        aggregate_accept_i,
	input  wire        aggregate_resp_valid_i,
	input  wire [15:0] aggregate_resp_data_i,
	input  wire        aggregate_cleanup_busy_i,
	input  wire        aggregate_stale_discarded_i,

	output wire        held_offer_o,
	output wire        held_owner_internal_o,
	output wire        read_pending_o,
	output wire        pending_owner_internal_o,
	output reg         accept_without_offer_o,
	output reg         retire_without_pending_o,
	output reg         outstanding_overlap_o
);

	reg        held_offer_q;
	reg        held_owner_internal_q;
	reg [15:0] held_addr_q;
	reg        read_pending_q;
	reg        pending_owner_internal_q;

	wire aggregate_retire_w = aggregate_resp_valid_i ||
		aggregate_stale_discarded_i;
	wire offer_window_w = !read_pending_q || aggregate_retire_w;
	wire live_external_req_w = external_req_i && !external_abort_i;
	wire live_req_w = internal_req_i || live_external_req_w;
	wire [15:0] live_addr_w = internal_req_i ?
		internal_addr_i : external_addr_i;
	wire selected_offer_w = held_offer_q ||
		(offer_window_w && live_req_w);
	wire selected_owner_internal_w = held_offer_q ?
		held_owner_internal_q : internal_req_i;
	wire [15:0] selected_addr_w = held_offer_q ?
		held_addr_q : live_addr_w;

	// Forward selective abort only when the external client owns router state.
	wire external_owned_context_w =
		(held_offer_q && !held_owner_internal_q) ||
		(read_pending_q && !pending_owner_internal_q);
	wire selected_external_aborted_w = external_abort_i &&
		selected_offer_w && !selected_owner_internal_w;
	wire response_external_aborted_w = external_abort_i &&
		read_pending_q && !pending_owner_internal_q;

	assign aggregate_abort_o = !reset_i &&
		(global_abort_i ||
		 (external_abort_i && external_owned_context_w));
	assign aggregate_req_o = !reset_i && !aggregate_abort_o &&
		selected_offer_w && !selected_external_aborted_w;
	assign aggregate_addr_o = selected_addr_w;

	assign internal_accept_o = ce_i && aggregate_accept_i &&
		aggregate_req_o && selected_owner_internal_w;
	assign external_accept_o = ce_i && aggregate_accept_i &&
		aggregate_req_o && !selected_owner_internal_w;

	assign internal_resp_valid_o = ce_i && !reset_i && !global_abort_i &&
		aggregate_resp_valid_i && read_pending_q &&
		pending_owner_internal_q;
	assign external_resp_valid_o = ce_i && !reset_i && !global_abort_i &&
		!response_external_aborted_w && aggregate_resp_valid_i &&
		read_pending_q && !pending_owner_internal_q;
	assign internal_resp_data_o = internal_resp_valid_o ?
		aggregate_resp_data_i : 16'd0;
	assign external_resp_data_o = external_resp_valid_o ?
		aggregate_resp_data_i : 16'd0;

	assign internal_cleanup_busy_o = aggregate_cleanup_busy_i &&
		read_pending_q && pending_owner_internal_q;
	assign external_cleanup_busy_o = aggregate_cleanup_busy_i &&
		read_pending_q && !pending_owner_internal_q;
	assign internal_stale_discarded_o = aggregate_stale_discarded_i &&
		read_pending_q && pending_owner_internal_q;
	assign external_stale_discarded_o = aggregate_stale_discarded_i &&
		read_pending_q && !pending_owner_internal_q;

	assign held_offer_o = held_offer_q;
	assign held_owner_internal_o = held_owner_internal_q;
	assign read_pending_o = read_pending_q;
	assign pending_owner_internal_o = pending_owner_internal_q;

	always @(posedge clk_i) begin
		if (reset_i) begin
			held_offer_q <= 1'b0;
			held_owner_internal_q <= 1'b0;
			held_addr_q <= 16'd0;
			read_pending_q <= 1'b0;
			pending_owner_internal_q <= 1'b0;
			accept_without_offer_o <= 1'b0;
			retire_without_pending_o <= 1'b0;
			outstanding_overlap_o <= 1'b0;
		end else begin
			// Raw abort drops offers; accepted reads keep their tag until drained.
			if (global_abort_i ||
				(external_abort_i && held_offer_q &&
				 !held_owner_internal_q)) begin
				held_offer_q <= 1'b0;
			end
			// Retire stale ownership on the raw discard pulse.
			if (aggregate_stale_discarded_i) begin
				if (!read_pending_q) begin
					retire_without_pending_o <= 1'b1;
				end
				read_pending_q <= 1'b0;
			end

			if (ce_i) begin
				if (aggregate_resp_valid_i &&
					aggregate_stale_discarded_i) begin
					outstanding_overlap_o <= 1'b1;
				end
				if (aggregate_resp_valid_i) begin
					if (!read_pending_q) begin
						retire_without_pending_o <= 1'b1;
					end
					read_pending_q <= 1'b0;
				end

				if (aggregate_accept_i) begin
					if (!aggregate_req_o) begin
						accept_without_offer_o <= 1'b1;
					end else begin
						if (read_pending_q && !aggregate_retire_w) begin
							outstanding_overlap_o <= 1'b1;
						end
						read_pending_q <= 1'b1;
						pending_owner_internal_q <=
							selected_owner_internal_w;
						held_offer_q <= 1'b0;
					end
				end else if (!held_offer_q && aggregate_req_o) begin
					held_offer_q <= 1'b1;
					held_owner_internal_q <=
						selected_owner_internal_w;
					held_addr_q <= selected_addr_w;
				end
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Three-client row-token mux.
//
// Owners are 0 none, 1 Normal, 2 H-bias, 3 Object. Fresh priority follows that
// order. Two owner slots cover same-edge token replacement.

module vip_xp_row_owner_mux
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	input  wire                 normal_valid_i,
	output wire                 normal_ready_o,
	output wire                 normal_done_o,
	input  wire [2:0]           normal_row_i,
	input  wire signed [15:0]   normal_left_base_x_i,
	input  wire                 normal_left_enable_i,
	input  wire [7:0]           normal_left_active_i,
	input  wire [7:0]           normal_left_opaque_i,
	input  wire [15:0]          normal_left_values_i,
	input  wire signed [15:0]   normal_right_base_x_i,
	input  wire                 normal_right_enable_i,
	input  wire [7:0]           normal_right_active_i,
	input  wire [7:0]           normal_right_opaque_i,
	input  wire [15:0]          normal_right_values_i,

	input  wire                 hbias_valid_i,
	output wire                 hbias_ready_o,
	output wire                 hbias_done_o,
	input  wire [2:0]           hbias_row_i,
	input  wire signed [15:0]   hbias_left_base_x_i,
	input  wire                 hbias_left_enable_i,
	input  wire [7:0]           hbias_left_active_i,
	input  wire [7:0]           hbias_left_opaque_i,
	input  wire [15:0]          hbias_left_values_i,
	input  wire signed [15:0]   hbias_right_base_x_i,
	input  wire                 hbias_right_enable_i,
	input  wire [7:0]           hbias_right_active_i,
	input  wire [7:0]           hbias_right_opaque_i,
	input  wire [15:0]          hbias_right_values_i,

	input  wire                 object_valid_i,
	output wire                 object_ready_o,
	output wire                 object_done_o,
	input  wire [2:0]           object_row_i,
	input  wire signed [15:0]   object_left_base_x_i,
	input  wire                 object_left_enable_i,
	input  wire [7:0]           object_left_active_i,
	input  wire [7:0]           object_left_opaque_i,
	input  wire [15:0]          object_left_values_i,
	input  wire signed [15:0]   object_right_base_x_i,
	input  wire                 object_right_enable_i,
	input  wire [7:0]           object_right_active_i,
	input  wire [7:0]           object_right_opaque_i,
	input  wire [15:0]          object_right_values_i,

	output wire                 producer_valid_o,
	input  wire                 producer_ready_i,
	input  wire                 producer_done_i,
	output wire [2:0]           producer_row_o,
	output wire signed [15:0]   producer_left_base_x_o,
	output wire                 producer_left_enable_o,
	output wire [7:0]           producer_left_active_o,
	output wire [7:0]           producer_left_opaque_o,
	output wire [15:0]          producer_left_values_o,
	output wire signed [15:0]   producer_right_base_x_o,
	output wire                 producer_right_enable_o,
	output wire [7:0]           producer_right_active_o,
	output wire [7:0]           producer_right_opaque_o,
	output wire [15:0]          producer_right_values_o,

	output wire [1:0]           owner_count_o,
	output wire                 owner_head_pointer_o,
	output wire                 owner_tail_pointer_o,
	output wire [1:0]           owner_head_o,
	output wire [1:0]           owner_tail_o,
	output wire                 offer_held_o,
	output wire [1:0]           offer_owner_o,
	output reg                  owner_overflow_o,
	output reg                  owner_underflow_o,
	output reg                  simultaneous_offer_o,
	output reg                  owner_protocol_error_o
);

	localparam [1:0]
		OWNER_NONE   = 2'd0,
		OWNER_NORMAL = 2'd1,
		OWNER_HBIAS  = 2'd2,
		OWNER_OBJECT = 2'd3;

	reg offer_held_q;
	reg [1:0] offer_owner_q;
	reg [100:0] offer_payload_q;

	reg [1:0] owner_count_q;
	reg owner_head_pointer_q;
	reg owner_tail_pointer_q;
	reg [1:0] owner_slot0_q;
	reg [1:0] owner_slot1_q;

	wire [100:0] normal_payload_w = {
		normal_row_i,
		normal_left_base_x_i, normal_left_enable_i,
		normal_left_active_i, normal_left_opaque_i,
		normal_left_values_i,
		normal_right_base_x_i, normal_right_enable_i,
		normal_right_active_i, normal_right_opaque_i,
		normal_right_values_i
	};
	wire [100:0] hbias_payload_w = {
		hbias_row_i,
		hbias_left_base_x_i, hbias_left_enable_i,
		hbias_left_active_i, hbias_left_opaque_i,
		hbias_left_values_i,
		hbias_right_base_x_i, hbias_right_enable_i,
		hbias_right_active_i, hbias_right_opaque_i,
		hbias_right_values_i
	};
	wire [100:0] object_payload_w = {
		object_row_i,
		object_left_base_x_i, object_left_enable_i,
		object_left_active_i, object_left_opaque_i,
		object_left_values_i,
		object_right_base_x_i, object_right_enable_i,
		object_right_active_i, object_right_opaque_i,
		object_right_values_i
	};

	wire live_valid_w = normal_valid_i || hbias_valid_i || object_valid_i;
	wire [1:0] live_owner_w = normal_valid_i ? OWNER_NORMAL :
		(hbias_valid_i ? OWNER_HBIAS :
		 (object_valid_i ? OWNER_OBJECT : OWNER_NONE));
	wire [100:0] live_payload_w = normal_valid_i ? normal_payload_w :
		(hbias_valid_i ? hbias_payload_w :
		 (object_valid_i ? object_payload_w : normal_payload_w));
	wire simultaneous_live_offer_w =
		(normal_valid_i && hbias_valid_i) ||
		(normal_valid_i && object_valid_i) ||
		(hbias_valid_i && object_valid_i);

	wire selected_valid_w = offer_held_q || live_valid_w;
	wire [1:0] selected_owner_w = offer_held_q ?
		offer_owner_q : live_owner_w;
	wire [100:0] selected_payload_w = offer_held_q ?
		offer_payload_q : live_payload_w;

	wire owner_empty_w = owner_count_q == 2'd0;
	wire owner_full_w = owner_count_q == 2'd2;
	wire [1:0] owner_head_w = owner_head_pointer_q ?
		owner_slot1_q : owner_slot0_q;
	wire owner_tail_element_pointer_w = owner_full_w ?
		~owner_head_pointer_q : owner_head_pointer_q;
	wire [1:0] owner_tail_w = owner_tail_element_pointer_w ?
		owner_slot1_q : owner_slot0_q;
	wire owner_retire_w = ce_i && !reset_i && !abort_i &&
		producer_done_i && !owner_empty_w;
	wire owner_slot_available_w = !owner_full_w || owner_retire_w;

	assign producer_valid_o = !reset_i && !abort_i &&
		owner_slot_available_w && selected_valid_w;
	wire producer_accept_w = ce_i && producer_valid_o &&
		producer_ready_i;

	assign normal_ready_o = producer_accept_w &&
		(selected_owner_w == OWNER_NORMAL);
	assign hbias_ready_o = producer_accept_w &&
		(selected_owner_w == OWNER_HBIAS);
	assign object_ready_o = producer_accept_w &&
		(selected_owner_w == OWNER_OBJECT);

	assign normal_done_o = owner_retire_w &&
		(owner_head_w == OWNER_NORMAL);
	assign hbias_done_o = owner_retire_w &&
		(owner_head_w == OWNER_HBIAS);
	assign object_done_o = owner_retire_w &&
		(owner_head_w == OWNER_OBJECT);

	assign {
		producer_row_o,
		producer_left_base_x_o, producer_left_enable_o,
		producer_left_active_o, producer_left_opaque_o,
		producer_left_values_o,
		producer_right_base_x_o, producer_right_enable_o,
		producer_right_active_o, producer_right_opaque_o,
		producer_right_values_o
	} = selected_payload_w;

	assign owner_count_o = owner_count_q;
	assign owner_head_pointer_o = owner_head_pointer_q;
	assign owner_tail_pointer_o = owner_tail_pointer_q;
	assign owner_head_o = owner_empty_w ? OWNER_NONE : owner_head_w;
	assign owner_tail_o = owner_empty_w ? OWNER_NONE : owner_tail_w;
	assign offer_held_o = offer_held_q;
	assign offer_owner_o = offer_held_q ? offer_owner_q : OWNER_NONE;

	always @(posedge clk_i) begin
		if (reset_i) begin
			offer_held_q <= 1'b0;
			offer_owner_q <= OWNER_NONE;
			offer_payload_q <= 101'd0;
			owner_count_q <= 2'd0;
			owner_head_pointer_q <= 1'b0;
			owner_tail_pointer_q <= 1'b0;
			owner_slot0_q <= OWNER_NONE;
			owner_slot1_q <= OWNER_NONE;
			owner_overflow_o <= 1'b0;
			owner_underflow_o <= 1'b0;
			simultaneous_offer_o <= 1'b0;
			owner_protocol_error_o <= 1'b0;
		end else if (abort_i) begin
			offer_held_q <= 1'b0;
			offer_owner_q <= OWNER_NONE;
			offer_payload_q <= 101'd0;
			owner_count_q <= 2'd0;
			owner_head_pointer_q <= 1'b0;
			owner_tail_pointer_q <= 1'b0;
			owner_slot0_q <= OWNER_NONE;
			owner_slot1_q <= OWNER_NONE;
		end else if (ce_i) begin
			if (!offer_held_q && simultaneous_live_offer_w) begin
				simultaneous_offer_o <= 1'b1;
			end

			if (producer_done_i && owner_empty_w) begin
				owner_underflow_o <= 1'b1;
			end
			if (producer_accept_w && owner_full_w && !owner_retire_w) begin
				owner_overflow_o <= 1'b1;
			end
			if ((producer_accept_w &&
				(selected_owner_w == OWNER_NONE)) ||
				(owner_retire_w && (owner_head_w == OWNER_NONE)) ||
				(owner_count_q > 2'd2)) begin
				owner_protocol_error_o <= 1'b1;
			end

			if (offer_held_q) begin
				if (producer_accept_w) begin
					offer_held_q <= 1'b0;
					offer_owner_q <= OWNER_NONE;
				end
			end else if (live_valid_w && !producer_accept_w) begin
				offer_held_q <= 1'b1;
				offer_owner_q <= live_owner_w;
				offer_payload_q <= live_payload_w;
			end

			if (producer_accept_w) begin
				if (owner_tail_pointer_q) begin
					owner_slot1_q <= selected_owner_w;
				end else begin
					owner_slot0_q <= selected_owner_w;
				end
				owner_tail_pointer_q <= ~owner_tail_pointer_q;
			end
			if (owner_retire_w) begin
				owner_head_pointer_q <= ~owner_head_pointer_q;
			end

			case ({producer_accept_w, owner_retire_w})
				2'b10: owner_count_q <= owner_count_q + 2'd1;
				2'b01: owner_count_q <= owner_count_q - 2'd1;
				default: owner_count_q <= owner_count_q;
			endcase
		end
	end

endmodule

`timescale 1ns/1ps

// H-bias PARAM/CELL DRAM arbitration.
//
// PARAM has fresh-offer priority. Hold stalled offers and accepted read owners.

module vip_xp_hbias_dram_mux
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire        abort_i,

	input  wire        param_req_i,
	input  wire [15:0] param_addr_i,
	output wire        param_accept_o,
	output wire        param_resp_valid_o,
	output wire [15:0] param_resp_data_o,
	output wire        param_cleanup_busy_o,
	output wire        param_stale_discarded_o,

	input  wire        cell_req_i,
	input  wire [15:0] cell_addr_i,
	output wire        cell_accept_o,
	output wire        cell_resp_valid_o,
	output wire [15:0] cell_resp_data_o,
	output wire        cell_cleanup_busy_o,
	output wire        cell_stale_discarded_o,

	output wire        aggregate_abort_o,
	output wire        aggregate_req_o,
	output wire [15:0] aggregate_addr_o,
	input  wire        aggregate_accept_i,
	input  wire        aggregate_resp_valid_i,
	input  wire [15:0] aggregate_resp_data_i,
	input  wire        aggregate_cleanup_busy_i,
	input  wire        aggregate_stale_discarded_i,

	output wire [1:0]  accepted_owner_o,
	output wire        held_offer_o,
	output wire [1:0]  held_owner_o,
	output wire        read_pending_o,
	output wire [1:0]  pending_owner_o,
	output wire        accept_without_offer_o,
	output wire        retire_without_pending_o,
	output wire        outstanding_overlap_o
);

	localparam [1:0]
		OWNER_NONE  = 2'd0,
		OWNER_PARAM = 2'd1,
		OWNER_CELL  = 2'd2;

	wire held_owner_param_w;
	wire pending_owner_param_w;

	assign accepted_owner_o = param_accept_o ? OWNER_PARAM :
		(cell_accept_o ? OWNER_CELL : OWNER_NONE);
	assign held_owner_o = held_offer_o ?
		(held_owner_param_w ? OWNER_PARAM : OWNER_CELL) : OWNER_NONE;
	assign pending_owner_o = read_pending_o ?
		(pending_owner_param_w ? OWNER_PARAM : OWNER_CELL) : OWNER_NONE;

	vip_xp_read_subclient_mux u_param_cell_mux
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.global_abort_i(abort_i),
		.external_abort_i(1'b0),
		.internal_req_i(param_req_i),
		.internal_addr_i(param_addr_i),
		.internal_accept_o(param_accept_o),
		.internal_resp_valid_o(param_resp_valid_o),
		.internal_resp_data_o(param_resp_data_o),
		.internal_cleanup_busy_o(param_cleanup_busy_o),
		.internal_stale_discarded_o(param_stale_discarded_o),
		.external_req_i(cell_req_i),
		.external_addr_i(cell_addr_i),
		.external_accept_o(cell_accept_o),
		.external_resp_valid_o(cell_resp_valid_o),
		.external_resp_data_o(cell_resp_data_o),
		.external_cleanup_busy_o(cell_cleanup_busy_o),
		.external_stale_discarded_o(cell_stale_discarded_o),
		.aggregate_abort_o(aggregate_abort_o),
		.aggregate_req_o(aggregate_req_o),
		.aggregate_addr_o(aggregate_addr_o),
		.aggregate_accept_i(aggregate_accept_i),
		.aggregate_resp_valid_i(aggregate_resp_valid_i),
		.aggregate_resp_data_i(aggregate_resp_data_i),
		.aggregate_cleanup_busy_i(aggregate_cleanup_busy_i),
		.aggregate_stale_discarded_i(aggregate_stale_discarded_i),
		.held_offer_o(held_offer_o),
		.held_owner_internal_o(held_owner_param_w),
		.read_pending_o(read_pending_o),
		.pending_owner_internal_o(pending_owner_param_w),
		.accept_without_offer_o(accept_without_offer_o),
		.retire_without_pending_o(retire_without_pending_o),
		.outstanding_overlap_o(outstanding_overlap_o)
	);

endmodule

`timescale 1ns/1ps

// Normal-world timing and traversal controller.
//
// The controller holds draw state and schedules work through the shared fetch
// and blend backend.

module vip_xp_normal_controller
#(
	parameter integer COMPOSED_TIMING_CREDIT_ENABLE = 0
)
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,

	// Draw command.
	input  wire                 engine_cmd_valid_i,
	output wire                 engine_cmd_ready_o,
	input  wire [1:0]           engine_cmd_kind_i,
	input  wire [4:0]           engine_cmd_strip_i,
	input  wire [4:0]           engine_cmd_world_i,
	input  wire [255:0]         engine_cmd_descriptor_i,
	input  wire                 engine_cmd_first_visit_i,
	output wire                 engine_done_o,
	input  wire                 engine_abort_i,
	input  wire [31:0]          gplt_active_i,

	// Other renderer kinds pass through one held interface.
	output wire                 external_cmd_valid_o,
	input  wire                 external_cmd_ready_i,
	output wire [1:0]           external_cmd_kind_o,
	output wire [4:0]           external_cmd_strip_o,
	output wire [4:0]           external_cmd_world_o,
	output wire [255:0]         external_cmd_descriptor_o,
	output wire                 external_cmd_first_visit_o,
	input  wire                 external_done_i,

	// Background settings held for the command.
	output wire [3:0]           backend_maps_wide_o,
	output wire [3:0]           backend_maps_high_o,
	output wire [3:0]           backend_effective_map_columns_o,
	output wire [3:0]           backend_bgmap_base_rounded_o,
	output wire                 backend_over_o,
	output wire [15:0]          backend_overplane_o,
	output wire                 backend_left_on_o,
	output wire                 backend_right_on_o,
	output wire signed [17:0]   backend_left_source_start_o,
	output wire signed [17:0]   backend_right_source_start_o,
	output wire signed [17:0]   backend_left_destination_start_o,
	output wire signed [17:0]   backend_right_destination_start_o,
	output wire [12:0]          backend_semantic_width_o,
	output wire [31:0]          backend_gplt_active_o,
	output wire                 backend_result_permit_o,

	// Held fetch-work interface.
	output wire                 backend_tile_row_valid_o,
	input  wire                 backend_tile_row_ready_i,
	output wire [0:0]           backend_tile_row_load_o,
	output wire [8:0]           backend_tile_row_screen_y_o,
	output wire signed [16:0]   backend_tile_row_source_y_o,

	output wire                 backend_tile_valid_o,
	input  wire                 backend_tile_ready_i,
	output wire [0:0]           backend_tile_load_o,
	output wire [12:0]          backend_tile_ordinal_o,
	output wire signed [15:0]   backend_tile_x_o,

	output wire                 backend_row_valid_o,
	input  wire                 backend_row_ready_i,
	output wire [0:0]           backend_row_load_o,
	output wire [12:0]          backend_row_tile_ordinal_o,
	output wire [2:0]           backend_row_ordinal_o,
	output wire [2:0]           backend_row_source_index_o,
	output wire [8:0]           backend_row_screen_y_o,
	output wire signed [16:0]   backend_row_source_y_o,

	// Physical ownership and row retirement.
	input  wire                 backend_fetch_busy_i,
	input  wire                 backend_cleanup_busy_i,
	input  wire                 backend_token_valid_i,
	input  wire                 backend_token_accept_i,
	input  wire                 row_producer_done_i,

	// Progress and controller-owned diagnostics.
	output wire                 normal_command_accept_o,
	output wire                 normal_active_o,
	output wire                 normal_quiescent_o,
	output wire [3:0]           scheduler_state_o,
	output wire [31:0]          scheduler_elapsed_ticks_o,
	output wire [31:0]          scheduler_tile_accept_count_o,
	output wire [31:0]          scheduler_row_accept_count_o,
	output wire [1:0]           producer_outstanding_o,
	output reg                  descriptor_kind_mismatch_o,
	output reg                  minimum_height_timing_conflict_o,
	output reg                  producer_overflow_o,
	output reg                  producer_underflow_o
);

	reg normal_active_q;
	reg scheduler_complete_q;
	reg external_active_q;
	reg [1:0] producer_outstanding_q;

	reg left_on_q;
	reg right_on_q;
	reg signed [9:0] gx_q;
	reg signed [9:0] gp_q;
	reg signed [12:0] mx_q;
	reg signed [14:0] mp_q;
	reg [12:0] semantic_width_q;
	reg [3:0] maps_wide_q;
	reg [3:0] maps_high_q;
	reg [3:0] effective_map_columns_q;
	reg [3:0] bgmap_base_rounded_q;
	reg over_q;
	reg [15:0] overplane_q;
	reg [31:0] gplt_active_q;

	wire descriptor_left_on_w;
	wire descriptor_right_on_w;
	wire [1:0] descriptor_kind_w;
	wire descriptor_over_w;
	wire signed [9:0] descriptor_gx_w;
	wire signed [9:0] descriptor_gp_w;
	wire signed [15:0] descriptor_gy_w;
	wire signed [12:0] descriptor_mx_w;
	wire signed [14:0] descriptor_mp_w;
	wire signed [12:0] descriptor_my_w;
	wire [12:0] descriptor_semantic_width_w;
	wire signed [16:0] descriptor_semantic_height_w;
	wire [15:0] descriptor_visual_height_w;
	wire [15:0] descriptor_overplane_w;
	wire [3:0] descriptor_maps_wide_w;
	wire [3:0] descriptor_maps_high_w;
	wire [3:0] descriptor_effective_map_columns_w;
	wire [3:0] descriptor_bgmap_base_rounded_w;
	wire signed [13:0] descriptor_tile_start_w;
	wire [13:0] descriptor_tile_count_w;
	wire signed [16:0] scheduler_visual_height_w =
		$signed({1'b0, descriptor_visual_height_w});
	wire minimum_height_timing_conflict_w =
		descriptor_semantic_height_w != scheduler_visual_height_w;

	wire scheduler_start_ready_w;
	wire scheduler_done_w;
	wire normal_selected_w = engine_cmd_kind_i == 2'd0;
	wire all_engines_idle_w = !normal_active_q && !external_active_q;
	wire producer_accept_w = ce_i && backend_token_accept_i;
	wire producer_done_w = ce_i && row_producer_done_i;
	wire normal_command_quiescent_w = !backend_fetch_busy_i &&
		!backend_cleanup_busy_i && !backend_token_valid_i &&
		(producer_outstanding_q == 2'd0);
	// A zero-work strip may finish on its command edge if the backend is empty.
	wire normal_complete_w = normal_active_q &&
		(scheduler_complete_q || scheduler_done_w) &&
		normal_command_quiescent_w;
	wire normal_start_valid_w = engine_cmd_valid_i &&
		normal_selected_w && all_engines_idle_w &&
		normal_command_quiescent_w;
	wire normal_command_fire_w = normal_start_valid_w &&
		scheduler_start_ready_w;
	wire external_command_fire_w = external_cmd_valid_o &&
		external_cmd_ready_i && ce_i;

	wire signed [17:0] gx_extended_w = {{8{gx_q[9]}}, gx_q};
	wire signed [17:0] gp_extended_w = {{8{gp_q[9]}}, gp_q};
	wire signed [17:0] mx_extended_w = {{5{mx_q[12]}}, mx_q};
	wire signed [17:0] mp_extended_w = {{3{mp_q[14]}}, mp_q};

	assign engine_cmd_ready_o = ce_i && !reset_i && !engine_abort_i &&
		all_engines_idle_w && normal_command_quiescent_w &&
		(normal_selected_w ? scheduler_start_ready_w :
		 external_cmd_ready_i);
	assign engine_done_o = !reset_i && !engine_abort_i &&
		(normal_complete_w ||
		 (external_active_q && external_done_i));

	assign external_cmd_valid_o = !reset_i && !engine_abort_i &&
		engine_cmd_valid_i && !normal_selected_w && all_engines_idle_w &&
		normal_command_quiescent_w;
	assign external_cmd_kind_o = engine_cmd_kind_i;
	assign external_cmd_strip_o = engine_cmd_strip_i;
	assign external_cmd_world_o = engine_cmd_world_i;
	assign external_cmd_descriptor_o = engine_cmd_descriptor_i;
	assign external_cmd_first_visit_o = engine_cmd_first_visit_i;

	assign backend_maps_wide_o = maps_wide_q;
	assign backend_maps_high_o = maps_high_q;
	assign backend_effective_map_columns_o = effective_map_columns_q;
	assign backend_bgmap_base_rounded_o = bgmap_base_rounded_q;
	assign backend_over_o = over_q;
	assign backend_overplane_o = overplane_q;
	assign backend_left_on_o = left_on_q;
	assign backend_right_on_o = right_on_q;
	assign backend_left_source_start_o = mx_extended_w - mp_extended_w;
	assign backend_right_source_start_o = mx_extended_w + mp_extended_w;
	assign backend_left_destination_start_o = gx_extended_w - gp_extended_w;
	assign backend_right_destination_start_o = gx_extended_w + gp_extended_w;
	assign backend_semantic_width_o = semantic_width_q;
	assign backend_gplt_active_o = gplt_active_q;
	assign backend_result_permit_o = 1'b1;

	assign normal_command_accept_o = normal_command_fire_w;
	assign normal_active_o = normal_active_q;
	assign normal_quiescent_o = !normal_active_q &&
		normal_command_quiescent_w;
	assign producer_outstanding_o = producer_outstanding_q;

	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_normal_decode u_normal_decode
	(
		.descriptor_i(engine_cmd_descriptor_i),
		.word0_o(),
		.lon_o(descriptor_left_on_w),
		.ron_o(descriptor_right_on_w),
		.kind_o(descriptor_kind_w),
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
		.semantic_width_o(descriptor_semantic_width_w),
		.semantic_height_o(descriptor_semantic_height_w),
		.visual_height_o(descriptor_visual_height_w),
		.overplane_o(descriptor_overplane_w),
		.maps_wide_o(descriptor_maps_wide_w),
		.maps_high_o(descriptor_maps_high_w),
		.effective_map_count_o(),
		.effective_map_columns_o(
			descriptor_effective_map_columns_w),
		.bgmap_base_rounded_o(descriptor_bgmap_base_rounded_w),
		.mp_abs_o(),
		.union_start_o(),
		.union_end_o(),
		.union_start_tile_o(descriptor_tile_start_w),
		.union_end_tile_exclusive_o(),
		.union_tile_count_o(descriptor_tile_count_w)
	);

	vip_xp_normal_scheduler
	#(
		.COMPOSED_TIMING_CREDIT_ENABLE(
			COMPOSED_TIMING_CREDIT_ENABLE)
	)
	u_normal_scheduler
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(engine_abort_i),
		.start_valid_i(normal_start_valid_w),
		.start_ready_o(scheduler_start_ready_w),
		.strip_i(engine_cmd_strip_i),
		.first_visit_i(engine_cmd_first_visit_i),
		.gy_i(descriptor_gy_w),
		.my_i(descriptor_my_w),
		.timing_height_i(scheduler_visual_height_w),
		.tile_start_i(descriptor_tile_start_w),
		.tile_count_i(descriptor_tile_count_w),
		.busy_o(),
		.done_o(scheduler_done_w),
		.aborted_o(),
		.tile_row_valid_o(backend_tile_row_valid_o),
		.tile_row_ready_i(backend_tile_row_ready_i),
		.tile_row_load_o(backend_tile_row_load_o),
		.tile_row_screen_y_o(backend_tile_row_screen_y_o),
		.tile_row_source_y_o(backend_tile_row_source_y_o),
		.tile_valid_o(backend_tile_valid_o),
		.tile_ready_i(backend_tile_ready_i),
		.tile_load_o(backend_tile_load_o),
		.tile_ordinal_o(backend_tile_ordinal_o),
		.tile_x_o(backend_tile_x_o),
		.row_valid_o(backend_row_valid_o),
		.row_ready_i(backend_row_ready_i),
		.row_load_o(backend_row_load_o),
		.row_tile_ordinal_o(backend_row_tile_ordinal_o),
		.row_ordinal_o(backend_row_ordinal_o),
		.row_source_index_o(backend_row_source_index_o),
		.row_screen_y_o(backend_row_screen_y_o),
		.row_source_y_o(backend_row_source_y_o),
		.state_o(scheduler_state_o),
		.state_ticks_remaining_o(),
		.diag_elapsed_ticks_o(scheduler_elapsed_ticks_o),
		.diag_base_ticks_o(),
		.diag_strip_ticks_o(),
		.diag_tile_row_ticks_o(),
		.diag_tile_ticks_o(),
		.diag_row_ticks_o(),
		.diag_tile_row_accept_count_o(),
		.diag_tile_accept_count_o(scheduler_tile_accept_count_o),
		.diag_row_accept_count_o(scheduler_row_accept_count_o),
		.diag_rows_per_tile_o(),
		.diag_tile_row_count_o(),
		.diag_bottom_adjust_o(),
		.diag_interface_seam_credit_o(),
		.diag_terminal_drain_credit_o(),
		.invalid_height_o(),
		.invalid_strip_o(),
		.invalid_tile_count_o()
	);
	/* verilator lint_on PINCONNECTEMPTY */

	always @(posedge clk_i) begin
		if (reset_i) begin
			normal_active_q <= 1'b0;
			scheduler_complete_q <= 1'b0;
			external_active_q <= 1'b0;
			producer_outstanding_q <= 2'd0;
			left_on_q <= 1'b0;
			right_on_q <= 1'b0;
			gx_q <= 10'sd0;
			gp_q <= 10'sd0;
			mx_q <= 13'sd0;
			mp_q <= 15'sd0;
			semantic_width_q <= 13'd0;
			maps_wide_q <= 4'd1;
			maps_high_q <= 4'd1;
			effective_map_columns_q <= 4'd1;
			bgmap_base_rounded_q <= 4'd0;
			over_q <= 1'b0;
			overplane_q <= 16'd0;
			gplt_active_q <= 32'd0;
			descriptor_kind_mismatch_o <= 1'b0;
			minimum_height_timing_conflict_o <= 1'b0;
			producer_overflow_o <= 1'b0;
			producer_underflow_o <= 1'b0;
		end else if (engine_abort_i) begin
			normal_active_q <= 1'b0;
			scheduler_complete_q <= 1'b0;
			external_active_q <= 1'b0;
			producer_outstanding_q <= 2'd0;
		end else if (ce_i) begin
			if (normal_command_fire_w) begin
				normal_active_q <= 1'b1;
				scheduler_complete_q <= 1'b0;
				left_on_q <= descriptor_left_on_w;
				right_on_q <= descriptor_right_on_w;
				gx_q <= descriptor_gx_w;
				gp_q <= descriptor_gp_w;
				mx_q <= descriptor_mx_w;
				mp_q <= descriptor_mp_w;
				semantic_width_q <= descriptor_semantic_width_w;
				maps_wide_q <= descriptor_maps_wide_w;
				maps_high_q <= descriptor_maps_high_w;
				effective_map_columns_q <=
					descriptor_effective_map_columns_w;
				bgmap_base_rounded_q <=
					descriptor_bgmap_base_rounded_w;
				over_q <= descriptor_over_w;
				overplane_q <= descriptor_overplane_w;
				gplt_active_q <= gplt_active_i;
				if (descriptor_kind_w != 2'd0) begin
					descriptor_kind_mismatch_o <= 1'b1;
				end
				// Silicon unknown: use STS's eight-row pixels but measured H+1 timing.
				if (minimum_height_timing_conflict_w) begin
					minimum_height_timing_conflict_o <= 1'b1;
				end
			end else if (normal_complete_w) begin
				normal_active_q <= 1'b0;
				scheduler_complete_q <= 1'b0;
			end else if (normal_active_q && scheduler_done_w) begin
				scheduler_complete_q <= 1'b1;
			end

			if (external_command_fire_w) begin
				external_active_q <= 1'b1;
			end else if (external_active_q && external_done_i) begin
				external_active_q <= 1'b0;
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
				default: begin
				end
			endcase
		end
	end

endmodule

`timescale 1ns/1ps

// Normal-world descriptor decoder.
//
// Descriptor word zero is in bits 15:0. The horizontal pixel interval is
// [union_start_o, union_end_o); the corresponding tile interval is
// [union_start_tile_o, union_end_tile_exclusive_o).

module vip_xp_normal_decode
(
	input  wire [255:0] descriptor_i,

	output wire [15:0] word0_o,
	output wire        lon_o,
	output wire        ron_o,
	output wire [1:0]  kind_o,
	output wire [1:0]  scx_o,
	output wire [1:0]  scy_o,
	output wire        over_o,
	output wire        end_o,
	output wire        dummy_o,
	output wire [3:0]  bgmap_base_raw_o,

	output wire signed [9:0]  gx_o,
	output wire signed [9:0]  gp_o,
	output wire signed [15:0] gy_o,
	output wire signed [12:0] mx_o,
	output wire signed [14:0] mp_o,
	output wire signed [12:0] my_o,
	output wire [15:0] raw_w_o,
	output wire [15:0] raw_h_o,

	output wire [12:0]        semantic_width_o,
	output wire signed [16:0] semantic_height_o,
	output wire [15:0]        visual_height_o,
	output wire [15:0]        overplane_o,

	output wire [3:0] maps_wide_o,
	output wire [3:0] maps_high_o,
	output wire [3:0] effective_map_count_o,
	output wire [3:0] effective_map_columns_o,
	output wire [3:0] bgmap_base_rounded_o,

	output wire [14:0]        mp_abs_o,
	output wire signed [16:0] union_start_o,
	output wire signed [16:0] union_end_o,
	output wire signed [13:0] union_start_tile_o,
	output wire signed [13:0] union_end_tile_exclusive_o,
	output wire [13:0]        union_tile_count_o
);

	wire signed [16:0] mx_extended_w =
		{{4{mx_o[12]}}, mx_o};
	wire signed [16:0] mp_abs_extended_w =
		$signed({2'b00, mp_abs_o});
	wire signed [16:0] width_extended_w =
		$signed({4'b0000, semantic_width_o});
	wire signed [13:0] union_end_floor_tile_w = union_end_o[16:3];
	wire union_end_has_fraction_w = |union_end_o[2:0];
	wire signed [14:0] union_tile_delta_w =
		{{1{union_end_tile_exclusive_o[13]}},
			union_end_tile_exclusive_o} -
		{{1{union_start_tile_o[13]}}, union_start_tile_o};

	// Add the Normal-only union around the shared descriptor decoder.
	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_bg_descriptor_decode u_common_decode
	(
		.descriptor_i(descriptor_i),
		.descriptor_raw_o(),
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
		.param_base_o(),
		.overplane_o(overplane_o),
		.semantic_width_o(semantic_width_o),
		.semantic_height_o(semantic_height_o),
		.visual_height_o(visual_height_o),
		.timing_height_o(),
		.visual_end_y_exclusive_o(),
		.timing_end_y_exclusive_o(),
		.maps_wide_o(maps_wide_o),
		.maps_high_o(maps_high_o),
		.effective_map_count_o(effective_map_count_o),
		.effective_map_columns_o(effective_map_columns_o),
		.bgmap_base_rounded_o(bgmap_base_rounded_o),
		.raw_h_timing_conflict_o(),
		.strict_overplane_high_o()
	);
	/* verilator lint_on PINCONNECTEMPTY */

	// Fifteen-bit negate keeps abs(-16384) as 15'h4000.
	assign mp_abs_o = mp_o[14] ?
		((~mp_o) + 15'd1) : mp_o;

	assign union_start_o = mx_extended_w - mp_abs_extended_w;
	assign union_end_o = mx_extended_w + mp_abs_extended_w +
		width_extended_w;
	// Bits 16:3 give signed floor-by-eight; the end uses ceiling division.
	assign union_start_tile_o = union_start_o[16:3];
	assign union_end_tile_exclusive_o = union_end_floor_tile_w +
		{13'd0, union_end_has_fraction_w};
	assign union_tile_count_o = union_tile_delta_w[14] ?
		14'd0 : union_tile_delta_w[13:0];

endmodule

`timescale 1ns/1ps

// Normal-world strip scheduler.
//
// This block owns timing and traversal. Other stages handle memory and pixels.
//
// The natural timing costs come from the physical-hardware timing model:
//   - 880 ticks once, on first_visit_i;
//   - 12/13/16 active-strip setup and measured strip quirks;
//   - 91 ticks for each source tile-row load;
//   - 2 ticks for each tile in a load;
//   - 2 ticks for each participating character row in a tile.
//
// Composed mode accounts for 23 command ticks per strip, spreads the remaining
// fixed work as 20 then 8 ticks, and reserves four final blend/store ticks.
//
// Subtract the measured nine-tick bottom-strip adjustment from first-visit work.

module vip_xp_normal_scheduler
#(
	parameter integer COMPOSED_TIMING_CREDIT_ENABLE = 0
)
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	// Hold command geometry until accepted.
	input  wire                 start_valid_i,
	output wire                 start_ready_o,
	input  wire [4:0]           strip_i,
	input  wire                 first_visit_i,
	input  wire signed [15:0]   gy_i,
	input  wire signed [12:0]   my_i,
	input  wire signed [16:0]   timing_height_i,
	// Signed source tile, converted to pixels when emitted.
	input  wire signed [13:0]   tile_start_i,
	input  wire [13:0]          tile_count_i,

	output wire                 busy_o,
	output reg                  done_o,
	output reg                  aborted_o,

	// One held tile-row request per 91-tick interval.
	output wire                 tile_row_valid_o,
	input  wire                 tile_row_ready_i,
	output wire [0:0]           tile_row_load_o,
	output wire [8:0]           tile_row_screen_y_o,
	output wire signed [16:0]   tile_row_source_y_o,

	// One source-tile request with a two-tick minimum.
	output wire                 tile_valid_o,
	input  wire                 tile_ready_i,
	output wire [0:0]           tile_load_o,
	output wire [12:0]          tile_ordinal_o,
	output wire signed [15:0]   tile_x_o,

	// One row request with a two-tick minimum. Order is load, tile, then rows.
	output wire                 row_valid_o,
	input  wire                 row_ready_i,
	output wire [0:0]           row_load_o,
	output wire [12:0]          row_tile_ordinal_o,
	output wire [2:0]           row_ordinal_o,
	output wire [2:0]           row_source_index_o,
	output wire [8:0]           row_screen_y_o,
	output wire signed [16:0]   row_source_y_o,

	// Observable scheduler state and focused-slice diagnostics.
	output wire [3:0]           state_o,
	output wire [9:0]           state_ticks_remaining_o,
`ifndef SYNTHESIS
	output reg  [31:0]          diag_elapsed_ticks_o,
	output reg  [15:0]          diag_base_ticks_o,
	output reg  [7:0]           diag_strip_ticks_o,
	output reg  [31:0]          diag_tile_row_ticks_o,
	output reg  [31:0]          diag_tile_ticks_o,
	output reg  [31:0]          diag_row_ticks_o,
	output reg  [1:0]           diag_tile_row_accept_count_o,
	output reg  [31:0]          diag_tile_accept_count_o,
	output reg  [31:0]          diag_row_accept_count_o,
	output reg  [3:0]           diag_rows_per_tile_o,
	output reg  [1:0]           diag_tile_row_count_o,
	output reg  [3:0]           diag_bottom_adjust_o,
	output reg  [5:0]           diag_interface_seam_credit_o,
	output reg  [2:0]           diag_terminal_drain_credit_o,
	output reg                  invalid_height_o,
	output reg                  invalid_strip_o,
	output reg                  invalid_tile_count_o
`else
	output wire [31:0]          diag_elapsed_ticks_o,
	output wire [15:0]          diag_base_ticks_o,
	output wire [7:0]           diag_strip_ticks_o,
	output wire [31:0]          diag_tile_row_ticks_o,
	output wire [31:0]          diag_tile_ticks_o,
	output wire [31:0]          diag_row_ticks_o,
	output wire [1:0]           diag_tile_row_accept_count_o,
	output wire [31:0]          diag_tile_accept_count_o,
	output wire [31:0]          diag_row_accept_count_o,
	output wire [3:0]           diag_rows_per_tile_o,
	output wire [1:0]           diag_tile_row_count_o,
	output wire [3:0]           diag_bottom_adjust_o,
	output wire [5:0]           diag_interface_seam_credit_o,
	output wire [2:0]           diag_terminal_drain_credit_o,
	output wire                 invalid_height_o,
	output wire                 invalid_strip_o,
	output wire                 invalid_tile_count_o
`endif
);

	localparam [3:0]
		STATE_IDLE     = 4'd0,
		STATE_BASE     = 4'd1,
		STATE_STRIP    = 4'd2,
		STATE_TILE_ROW = 4'd3,
		STATE_TILE     = 4'd4,
		STATE_ROW      = 4'd5;

	localparam [9:0]
		BASE_TICKS              = 10'd880,
		BASE_WITH_BOTTOM_ADJUST = 10'd871,
		TILE_ROW_TICKS          = 10'd91,
		TILE_ROW_COMPOSED_TICKS = 10'd87,
		TILE_TICKS              = 10'd2,
		ROW_TICKS               = 10'd2;
	localparam [9:0]
		COMPOSED_BASE_TICKS       = 10'd8,
		COMPOSED_FIRST_REMAINDER  = 10'd12,
		COMPOSED_BOTTOM_ADJUST    = 10'd9;
	localparam [13:0] MAX_TILE_COUNT = 14'd4608;

	reg [3:0] state_q;
	reg [9:0] state_ticks_remaining_q;
	reg       work_accepted_q;

	reg signed [15:0] gy_q;
	reg signed [12:0] my_q;
	reg signed [13:0] tile_start_q;
	reg [13:0] tile_count_q;
	reg [1:0] load_count_q;
	reg [0:0] load_index_q;
	reg [3:0] load0_rows_q;
	reg [3:0] load1_rows_q;
	reg [8:0] load0_screen_start_q;
	reg [8:0] load1_screen_start_q;
	reg [12:0] tile_ordinal_q;
	reg [2:0] row_ordinal_q;
	reg [5:0] strip_cost_q;
	reg       terminal_drain_credit_q;

	reg [9:0] base_cost_t;
	reg [5:0] strip_cost_t;
	reg       contains_top_t;
	reg       contains_bottom_t;
	reg [3:0] rows_t;
	reg [1:0] loads_t;
	reg [3:0] load0_rows_t;
	reg [3:0] load1_rows_t;
	reg [8:0] load0_screen_start_t;
	reg [8:0] load1_screen_start_t;
	reg signed [17:0] gy_ext_t;
	reg signed [17:0] height_ext_t;
	reg signed [17:0] end_y_t;
	reg signed [17:0] strip_y_t;
	reg signed [17:0] strip_end_t;
	reg signed [17:0] active_start_t;
	reg signed [17:0] split_y_t;
	reg signed [17:0] rows_wide_t;
	reg signed [17:0] split_rows_t;
	reg [2:0] vertical_offset_t;
	reg       height_positive_t;
	reg       reaches_bottom_t;
	reg       second_load_t;

	wire [3:0] current_load_rows_w = load_index_q ?
		load1_rows_q : load0_rows_q;
	wire [8:0] current_load_screen_start_w = load_index_q ?
		load1_screen_start_q : load0_screen_start_q;
	wire [8:0] current_screen_y_w = current_load_screen_start_w +
		{6'd0, row_ordinal_q};
	wire signed [16:0] current_source_y_w =
		{{4{my_q[12]}}, my_q} + $signed({8'd0, current_screen_y_w}) -
		{{1{gy_q[15]}}, gy_q};
	/* verilator lint_off UNUSEDSIGNAL */
	wire signed [16:0] load_source_y_w =
		{{4{my_q[12]}}, my_q} +
		$signed({8'd0, current_load_screen_start_w}) -
		{{1{gy_q[15]}}, gy_q};
	/* verilator lint_on UNUSEDSIGNAL */
	wire signed [16:0] tile_row_source_y_w =
		{load_source_y_w[16:3], 3'b000};
	wire signed [14:0] current_tile_index_w =
		{{1{tile_start_q[13]}}, tile_start_q} +
		$signed({2'b00, tile_ordinal_q});
	// Keep carry while converting the 13-bit tile position to pixel X.
	/* verilator lint_off UNUSEDSIGNAL */
	wire signed [17:0] tile_x_extended_w =
		{current_tile_index_w, 3'b000};
	/* verilator lint_on UNUSEDSIGNAL */
	wire signed [15:0] tile_x_w = tile_x_extended_w[15:0];

	wire tile_row_fire_w = ce_i && tile_row_valid_o &&
		tile_row_ready_i;
	wire tile_fire_w = ce_i && tile_valid_o && tile_ready_i;
	wire row_fire_w = ce_i && row_valid_o && row_ready_i;

	assign start_ready_o = ce_i && !abort_i && !done_o &&
		(state_q == STATE_IDLE);
	assign busy_o = state_q != STATE_IDLE;
	assign state_o = state_q;
	assign state_ticks_remaining_o = state_ticks_remaining_q;

`ifdef SYNTHESIS
	assign diag_elapsed_ticks_o = 32'd0;
	assign diag_base_ticks_o = 16'd0;
	assign diag_strip_ticks_o = 8'd0;
	assign diag_tile_row_ticks_o = 32'd0;
	assign diag_tile_ticks_o = 32'd0;
	assign diag_row_ticks_o = 32'd0;
	assign diag_tile_row_accept_count_o = 2'd0;
	assign diag_tile_accept_count_o = 32'd0;
	assign diag_row_accept_count_o = 32'd0;
	assign diag_rows_per_tile_o = 4'd0;
	assign diag_tile_row_count_o = 2'd0;
	assign diag_bottom_adjust_o = 4'd0;
	assign diag_interface_seam_credit_o = 6'd0;
	assign diag_terminal_drain_credit_o = 3'd0;
	assign invalid_height_o = 1'b0;
	assign invalid_strip_o = 1'b0;
	assign invalid_tile_count_o = 1'b0;
`endif

	assign tile_row_valid_o = (state_q == STATE_TILE_ROW) &&
		!work_accepted_q;
	assign tile_row_load_o = load_index_q;
	assign tile_row_screen_y_o = current_load_screen_start_w;
	assign tile_row_source_y_o = tile_row_source_y_w;

	assign tile_valid_o = (state_q == STATE_TILE) &&
		!work_accepted_q;
	assign tile_load_o = load_index_q;
	assign tile_ordinal_o = tile_ordinal_q;
	assign tile_x_o = tile_x_w;

	assign row_valid_o = (state_q == STATE_ROW) &&
		!work_accepted_q;
	assign row_load_o = load_index_q;
	assign row_tile_ordinal_o = tile_ordinal_q;
	assign row_ordinal_o = row_ordinal_q;
	assign row_source_index_o = current_source_y_w[2:0];
	assign row_screen_y_o = current_screen_y_w;
	assign row_source_y_o = current_source_y_w;

	// Natural mode charges 880 ticks once. Composed mode charges only its share.
	always @* begin
		gy_ext_t = {{2{gy_i[15]}}, gy_i};
		height_ext_t = {{1{timing_height_i[16]}}, timing_height_i};
		end_y_t = gy_ext_t + height_ext_t;
		strip_y_t = $signed({10'd0, strip_i, 3'b000});
		strip_end_t = strip_y_t + 18'sd8;
		height_positive_t = !timing_height_i[16] &&
			(timing_height_i != 17'sd0);
		reaches_bottom_t = height_positive_t && (end_y_t > 18'sd216);

		base_cost_t = 10'd0;
		if (COMPOSED_TIMING_CREDIT_ENABLE != 0) begin
			if (strip_i < 5'd28) begin
				base_cost_t = COMPOSED_BASE_TICKS;
				if (first_visit_i) begin
					base_cost_t = base_cost_t +
						COMPOSED_FIRST_REMAINDER;
					if (reaches_bottom_t) begin
						base_cost_t = base_cost_t -
							COMPOSED_BOTTOM_ADJUST;
					end
				end
			end
		end else if (first_visit_i) begin
			base_cost_t = reaches_bottom_t ?
				BASE_WITH_BOTTOM_ADJUST : BASE_TICKS;
		end

		strip_cost_t = 6'd0;
		contains_top_t = 1'b0;
		contains_bottom_t = 1'b0;
		rows_t = 4'd0;
		loads_t = 2'd0;
		load0_rows_t = 4'd0;
		load1_rows_t = 4'd0;
		load0_screen_start_t = strip_y_t[8:0];
		load1_screen_start_t = strip_y_t[8:0];
		active_start_t = strip_y_t;
		split_y_t = strip_y_t;
		rows_wide_t = 18'sd0;
		split_rows_t = 18'sd0;
		vertical_offset_t = gy_i[2:0] - my_i[2:0];
		second_load_t = 1'b0;

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

				active_start_t = contains_top_t ? gy_ext_t : strip_y_t;
				if ((end_y_t < strip_end_t) && !contains_top_t) begin
					rows_t = {1'b0, end_y_t[2:0]};
				end else begin
					rows_wide_t = strip_end_t - gy_ext_t;
					if (rows_wide_t > 18'sd8) begin
						rows_t = 4'd8;
					end else begin
						rows_t = rows_wide_t[3:0];
					end
				end

				split_y_t = strip_y_t +
					$signed({15'd0, vertical_offset_t});
				second_load_t = (vertical_offset_t != 3'd0) &&
					(!contains_top_t || (gy_ext_t < split_y_t)) &&
					(!contains_bottom_t || contains_top_t ||
					 (end_y_t > split_y_t));
				loads_t = second_load_t ? 2'd2 : 2'd1;

				load0_screen_start_t = active_start_t[8:0];
				if (second_load_t) begin
					split_rows_t = split_y_t - active_start_t;
					if (split_rows_t < 18'sd0) begin
						load0_rows_t = 4'd0;
					end else if (split_rows_t > $signed({14'd0, rows_t})) begin
						load0_rows_t = rows_t;
					end else begin
						load0_rows_t = split_rows_t[3:0];
					end
					load1_rows_t = rows_t - load0_rows_t;
					load1_screen_start_t = split_y_t[8:0];
				end else begin
					load0_rows_t = rows_t;
					load1_rows_t = 4'd0;
					load1_screen_start_t = active_start_t[8:0];
				end
			end
		end
	end

	// A zero or oversized tile count degrades to an empty strip visit.
	wire tile_count_valid_w = (tile_count_i != 14'd0) &&
		(tile_count_i <= MAX_TILE_COUNT);

	// Retire the strip visit.
	task finish_strip_task;
		begin
			state_q <= STATE_IDLE;
			state_ticks_remaining_q <= 10'd0;
			done_o <= 1'b1;
		end
	endtask

	// Charge the next tile-row load and enter its window.
	task enter_next_tile_row_task;
		begin
			load_index_q <= load_index_q + 1'd1;
			state_q <= STATE_TILE_ROW;
			state_ticks_remaining_q <=
				terminal_drain_credit_q ?
				TILE_ROW_COMPOSED_TICKS : TILE_ROW_TICKS;
		end
	endtask

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			state_ticks_remaining_q <= 10'd0;
			work_accepted_q <= 1'b0;
			gy_q <= 16'sd0;
			my_q <= 13'sd0;
			tile_start_q <= 14'sd0;
			tile_count_q <= 14'd0;
			load_count_q <= 2'd0;
			load_index_q <= 1'd0;
			load0_rows_q <= 4'd0;
			load1_rows_q <= 4'd0;
			load0_screen_start_q <= 9'd0;
			load1_screen_start_q <= 9'd0;
			tile_ordinal_q <= 13'd0;
			row_ordinal_q <= 3'd0;
			strip_cost_q <= 6'd0;
			terminal_drain_credit_q <= 1'b0;
			done_o <= 1'b0;
			aborted_o <= 1'b0;
`ifndef SYNTHESIS
			diag_elapsed_ticks_o <= 32'd0;
			diag_base_ticks_o <= 16'd0;
			diag_strip_ticks_o <= 8'd0;
			diag_tile_row_ticks_o <= 32'd0;
			diag_tile_ticks_o <= 32'd0;
			diag_row_ticks_o <= 32'd0;
			diag_tile_row_accept_count_o <= 2'd0;
			diag_tile_accept_count_o <= 32'd0;
			diag_row_accept_count_o <= 32'd0;
			diag_rows_per_tile_o <= 4'd0;
			diag_tile_row_count_o <= 2'd0;
			diag_bottom_adjust_o <= 4'd0;
			diag_interface_seam_credit_o <= 6'd0;
			diag_terminal_drain_credit_o <= 3'd0;
			invalid_height_o <= 1'b0;
			invalid_strip_o <= 1'b0;
			invalid_tile_count_o <= 1'b0;
`endif
		end else if (abort_i) begin
			state_q <= STATE_IDLE;
			state_ticks_remaining_q <= 10'd0;
			work_accepted_q <= 1'b0;
			terminal_drain_credit_q <= 1'b0;
			done_o <= 1'b0;
			aborted_o <= 1'b1;
		end else if (ce_i) begin
			done_o <= 1'b0;
			case (state_q)
				STATE_IDLE: begin
					state_ticks_remaining_q <= 10'd0;
					work_accepted_q <= 1'b0;
					if (start_valid_i && start_ready_o) begin
						gy_q <= gy_i;
						my_q <= my_i;
						tile_start_q <= tile_start_i;
						tile_count_q <= tile_count_valid_w ?
							tile_count_i : 14'd0;
						load_count_q <= tile_count_valid_w ?
							loads_t : 2'd0;
						load_index_q <= 1'd0;
						load0_rows_q <= load0_rows_t;
						load1_rows_q <= load1_rows_t;
						load0_screen_start_q <= load0_screen_start_t;
						load1_screen_start_q <= load1_screen_start_t;
						tile_ordinal_q <= 13'd0;
						row_ordinal_q <= 3'd0;
						strip_cost_q <= strip_cost_t;
						terminal_drain_credit_q <=
							(COMPOSED_TIMING_CREDIT_ENABLE != 0) &&
							tile_count_valid_w &&
							(loads_t != 2'd0) && (rows_t != 4'd0);
						aborted_o <= 1'b0;
`ifndef SYNTHESIS
						diag_elapsed_ticks_o <= 32'd0;
						diag_base_ticks_o <= 16'd0;
						diag_strip_ticks_o <= 8'd0;
						diag_tile_row_ticks_o <= 32'd0;
						diag_tile_ticks_o <= 32'd0;
						diag_row_ticks_o <= 32'd0;
						diag_tile_row_accept_count_o <= 2'd0;
						diag_tile_accept_count_o <= 32'd0;
						diag_row_accept_count_o <= 32'd0;
						diag_rows_per_tile_o <= rows_t;
						diag_tile_row_count_o <=
							tile_count_valid_w ? loads_t : 2'd0;
						diag_bottom_adjust_o <=
							(first_visit_i && reaches_bottom_t) ? 4'd9 : 4'd0;
						diag_interface_seam_credit_o <=
							((COMPOSED_TIMING_CREDIT_ENABLE != 0) &&
							 (strip_i < 5'd28)) ? 6'd23 : 6'd0;
						diag_terminal_drain_credit_o <=
							((COMPOSED_TIMING_CREDIT_ENABLE != 0) &&
							 tile_count_valid_w &&
							 (loads_t != 2'd0) && (rows_t != 4'd0)) ?
							3'd4 : 3'd0;
						invalid_height_o <= !height_positive_t;
						invalid_strip_o <= strip_i >= 5'd28;
						invalid_tile_count_o <= !tile_count_valid_w;
`endif
						if (base_cost_t != 10'd0) begin
							state_q <= STATE_BASE;
							state_ticks_remaining_q <= base_cost_t;
						end else if (strip_cost_t != 6'd0) begin
							state_q <= STATE_STRIP;
							state_ticks_remaining_q <= {4'd0, strip_cost_t};
						end else begin
							state_q <= STATE_IDLE;
							done_o <= 1'b1;
						end
					end
				end

				STATE_BASE: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_base_ticks_o <= diag_base_ticks_o + 16'd1;
`endif
					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (strip_cost_q != 6'd0) begin
						state_q <= STATE_STRIP;
						state_ticks_remaining_q <= {4'd0, strip_cost_q};
					end else begin
						finish_strip_task;
					end
				end

				STATE_STRIP: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_strip_ticks_o <= diag_strip_ticks_o + 8'd1;
`endif
					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (load_count_q != 2'd0) begin
						state_q <= STATE_TILE_ROW;
						state_ticks_remaining_q <=
							terminal_drain_credit_q &&
							(load_count_q == 2'd1) ?
							TILE_ROW_COMPOSED_TICKS : TILE_ROW_TICKS;
						work_accepted_q <= 1'b0;
					end else begin
						finish_strip_task;
					end
				end

				STATE_TILE_ROW: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_tile_row_ticks_o <= diag_tile_row_ticks_o + 32'd1;
`endif
					if (tile_row_fire_w) begin
						work_accepted_q <= 1'b1;
`ifndef SYNTHESIS
						diag_tile_row_accept_count_o <=
							diag_tile_row_accept_count_o + 2'd1;
`endif
					end
					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (work_accepted_q || tile_row_fire_w) begin
						work_accepted_q <= 1'b0;
						if (tile_count_q != 14'd0) begin
							state_q <= STATE_TILE;
							state_ticks_remaining_q <= TILE_TICKS;
							tile_ordinal_q <= 13'd0;
						end else if ({1'b0, load_index_q} + 2'd1 <
							load_count_q) begin
							enter_next_tile_row_task;
						end else begin
							finish_strip_task;
						end
					end
				end

				STATE_TILE: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_tile_ticks_o <= diag_tile_ticks_o + 32'd1;
`endif
					if (tile_fire_w) begin
						work_accepted_q <= 1'b1;
`ifndef SYNTHESIS
						diag_tile_accept_count_o <=
							diag_tile_accept_count_o + 32'd1;
`endif
					end
					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (work_accepted_q || tile_fire_w) begin
						work_accepted_q <= 1'b0;
						if (current_load_rows_w != 4'd0) begin
							state_q <= STATE_ROW;
							state_ticks_remaining_q <= ROW_TICKS;
							row_ordinal_q <= 3'd0;
						end else if ({1'b0, tile_ordinal_q} + 14'd1 <
							tile_count_q) begin
							tile_ordinal_q <= tile_ordinal_q + 13'd1;
							state_q <= STATE_TILE;
							state_ticks_remaining_q <= TILE_TICKS;
						end else if ({1'b0, load_index_q} + 2'd1 <
							load_count_q) begin
							tile_ordinal_q <= 13'd0;
							enter_next_tile_row_task;
						end else begin
							finish_strip_task;
						end
					end
				end

				STATE_ROW: begin
`ifndef SYNTHESIS
					diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
					diag_row_ticks_o <= diag_row_ticks_o + 32'd1;
`endif
					if (row_fire_w) begin
						work_accepted_q <= 1'b1;
`ifndef SYNTHESIS
						diag_row_accept_count_o <=
							diag_row_accept_count_o + 32'd1;
`endif
					end
					if (state_ticks_remaining_q > 10'd1) begin
						state_ticks_remaining_q <= state_ticks_remaining_q - 10'd1;
					end else if (work_accepted_q || row_fire_w) begin
						work_accepted_q <= 1'b0;
						if ({1'b0, row_ordinal_q} + 4'd1 <
							current_load_rows_w) begin
							row_ordinal_q <= row_ordinal_q + 3'd1;
							state_q <= STATE_ROW;
							state_ticks_remaining_q <= ROW_TICKS;
						end else if ({1'b0, tile_ordinal_q} + 14'd1 <
							tile_count_q) begin
							tile_ordinal_q <= tile_ordinal_q + 13'd1;
							row_ordinal_q <= 3'd0;
							state_q <= STATE_TILE;
							state_ticks_remaining_q <= TILE_TICKS;
						end else if ({1'b0, load_index_q} + 2'd1 <
							load_count_q) begin
							tile_ordinal_q <= 13'd0;
							row_ordinal_q <= 3'd0;
							enter_next_tile_row_task;
						end else begin
							finish_strip_task;
						end
					end
				end

				default: begin
					state_q <= STATE_IDLE;
					state_ticks_remaining_q <= 10'd0;
					work_accepted_q <= 1'b0;
				end
			endcase
		end
	end

endmodule

`timescale 1ns/1ps

// Shared background-world descriptor decoder.
//
// Decodes fields shared by Normal and H-bias. Mode-specific geometry stays outside.

module vip_xp_bg_descriptor_decode
(
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

	output reg  [3:0] maps_wide_o,
	output reg  [3:0] maps_high_o,
	output reg  [3:0] effective_map_count_o,
	output reg  [3:0] effective_map_columns_o,
	output reg  [3:0] bgmap_base_rounded_o,

	output wire raw_h_timing_conflict_o,
	output wire strict_overplane_high_o
);

	wire [12:0] width_plus_one_w =
		{1'b0, raw_w_o[11:0]} + 13'd1;
	wire signed [16:0] height_extended_w =
		{raw_h_o[15], raw_h_o};
	wire signed [17:0] gy_extended_w =
		{{2{gy_o[15]}}, gy_o};
	wire signed [17:0] visual_height_extended_w =
		$signed({2'b00, visual_height_o});
	wire signed [17:0] timing_height_extended_w =
		{timing_height_o[16], timing_height_o};

	assign descriptor_raw_o = descriptor_i;
	assign word0_o = descriptor_i[0 +: 16];
	assign lon_o = word0_o[15];
	assign ron_o = word0_o[14];
	assign kind_o = word0_o[13:12];
	assign scx_o = word0_o[11:10];
	assign scy_o = word0_o[9:8];
	assign over_o = word0_o[7];
	assign end_o = word0_o[6];
	assign dummy_o = (word0_o[15:14] == 2'b00);
	assign bgmap_base_raw_o = word0_o[3:0];

	assign gx_o = descriptor_i[16 +: 10];
	assign gp_o = descriptor_i[32 +: 10];
	assign gy_o = descriptor_i[48 +: 16];
	assign mx_o = descriptor_i[64 +: 13];
	assign mp_o = descriptor_i[80 +: 15];
	assign my_o = descriptor_i[96 +: 13];
	assign raw_w_o = descriptor_i[112 +: 16];
	assign raw_h_o = descriptor_i[128 +: 16];
	assign param_base_o = descriptor_i[144 +: 16];
	assign overplane_o = descriptor_i[160 +: 16];

	// W is a signed 13-bit inclusive maximum.
	assign semantic_width_o = raw_w_o[12] ?
		13'd0 : width_plus_one_w;
	assign semantic_height_o = height_extended_w + 17'sd1;
	assign visual_height_o = (semantic_height_o < 17'sd8) ?
		16'd8 : semantic_height_o[15:0];

	// Timing uses signed H+1, separate from the visible height minimum.
	assign timing_height_o = semantic_height_o;
	assign visual_end_y_exclusive_o = gy_extended_w +
		visual_height_extended_w;
	assign timing_end_y_exclusive_o = gy_extended_w +
		timing_height_extended_w;

	// Silicon unknown: H=0..6 draws eight rows but times as H+1.
	assign raw_h_timing_conflict_o = !raw_h_o[15] &&
		(raw_h_o[14:0] <= 15'd6);
	assign strict_overplane_high_o = over_o &&
		(overplane_o[15:13] == 3'b111);

	// Map dimensions are powers of two; this table avoids multiply and divide.
	always @* begin
		case (scx_o)
			2'd0: maps_wide_o = 4'd1;
			2'd1: maps_wide_o = 4'd2;
			2'd2: maps_wide_o = 4'd4;
			default: maps_wide_o = 4'd8;
		endcase

		case (scy_o)
			2'd0: maps_high_o = 4'd1;
			2'd1: maps_high_o = 4'd2;
			2'd2: maps_high_o = 4'd4;
			default: maps_high_o = 4'd8;
		endcase

		case ({scx_o, scy_o})
			4'b0000: begin
				effective_map_count_o = 4'd1;
				effective_map_columns_o = 4'd1;
			end
			4'b0001: begin
				effective_map_count_o = 4'd2;
				effective_map_columns_o = 4'd1;
			end
			4'b0010: begin
				effective_map_count_o = 4'd4;
				effective_map_columns_o = 4'd1;
			end
			4'b0011: begin
				effective_map_count_o = 4'd8;
				effective_map_columns_o = 4'd1;
			end
			4'b0100: begin
				effective_map_count_o = 4'd2;
				effective_map_columns_o = 4'd2;
			end
			4'b0101: begin
				effective_map_count_o = 4'd4;
				effective_map_columns_o = 4'd2;
			end
			4'b0110: begin
				effective_map_count_o = 4'd8;
				effective_map_columns_o = 4'd2;
			end
			4'b0111: begin
				effective_map_count_o = 4'd8;
				effective_map_columns_o = 4'd1;
			end
			4'b1000: begin
				effective_map_count_o = 4'd4;
				effective_map_columns_o = 4'd4;
			end
			4'b1001: begin
				effective_map_count_o = 4'd8;
				effective_map_columns_o = 4'd4;
			end
			4'b1010: begin
				effective_map_count_o = 4'd8;
				effective_map_columns_o = 4'd2;
			end
			4'b1011: begin
				effective_map_count_o = 4'd8;
				effective_map_columns_o = 4'd1;
			end
			4'b1100: begin
				effective_map_count_o = 4'd8;
				effective_map_columns_o = 4'd8;
			end
			4'b1101: begin
				effective_map_count_o = 4'd8;
				effective_map_columns_o = 4'd4;
			end
			4'b1110: begin
				effective_map_count_o = 4'd8;
				effective_map_columns_o = 4'd2;
			end
			default: begin
				effective_map_count_o = 4'd8;
				effective_map_columns_o = 4'd1;
			end
		endcase

		case (effective_map_count_o)
			4'd1: bgmap_base_rounded_o = bgmap_base_raw_o;
			4'd2: bgmap_base_rounded_o =
				{bgmap_base_raw_o[3:1], 1'b0};
			4'd4: bgmap_base_rounded_o =
				{bgmap_base_raw_o[3:2], 2'b00};
			default: bgmap_base_rounded_o =
				{bgmap_base_raw_o[3], 3'b000};
		endcase
	end

endmodule

`timescale 1ns/1ps

// Shared background fetch and blend backend.
//
// The selected controller supplies tile-row, tile, and row work. Capture map,
// owner, and blend geometry when the context is accepted.
//
// Fetch feeds blend directly. Tags are registered beside the blend data, with
// same-edge output replacement.

module vip_xp_bg_shared_backend
#(
	// Enable external decode only in the shared Affine hierarchy.
	parameter integer EXTERNAL_DECODE_SEAM = 0,
	// Enable external address queries only in the shared hierarchy.
	parameter integer EXTERNAL_ADDRESS_SEAM = 0
)
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,
	// Rearm diagnostics only while the backend is empty.
	input  wire                 diagnostic_rearm_i,
	output wire                 diagnostic_rearm_ready_o,
	output wire                 diagnostic_rearm_accept_o,
	output reg                  diagnostic_rearm_rejected_o,

	// Selected owner and draw settings.
	input  wire [1:0]           controller_owner_i,
	input  wire [3:0]           maps_wide_i,
	input  wire [3:0]           maps_high_i,
	input  wire [3:0]           effective_map_columns_i,
	input  wire [3:0]           bgmap_base_rounded_i,
	input  wire                 over_i,
	input  wire [15:0]          overplane_i,
	input  wire                 left_on_i,
	input  wire                 right_on_i,
	input  wire signed [17:0]   left_source_start_i,
	input  wire signed [17:0]   right_source_start_i,
	input  wire signed [17:0]   left_destination_start_i,
	input  wire signed [17:0]   right_destination_start_i,
	input  wire [12:0]          semantic_width_i,
	input  wire [31:0]          gplt_active_i,

	// Optional Affine query to the shared character decoder. Tile work has priority.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire                 external_decode_select_i,
	input  wire [15:0]          external_decode_character_row_i,
	input  wire [1:0]           external_decode_palette_i,
	input  wire                 external_decode_hflip_i,
	input  wire [2:0]           external_decode_source_x_index_i,
	input  wire [31:0]          external_decode_gplt_active_i,
	/* verilator lint_on UNUSEDSIGNAL */
	output wire [1:0]           external_decoded_raw_pixel_o,
	output wire                 external_decoded_raw_nonzero_o,
	output wire [1:0]           external_decoded_mapped_pixel_o,
	output wire [15:0]          external_decoded_raw_pixels_o,
	output wire [7:0]           external_decoded_raw_nonzero_vector_o,
	output wire [15:0]          external_decoded_mapped_pixels_o,
	output wire                 external_decode_mode_conflict_o,

	// Optional Affine address query. Normal/H-bias fetch has priority.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire                 external_address_select_i,
	input  wire signed [16:0]   external_address_source_x_i,
	input  wire signed [16:0]   external_address_source_y_i,
	input  wire [3:0]           external_address_maps_wide_i,
	input  wire [3:0]           external_address_maps_high_i,
	input  wire [3:0]           external_address_effective_map_columns_i,
	input  wire [3:0]           external_address_bgmap_base_rounded_i,
	input  wire                 external_address_over_i,
	input  wire [15:0]          external_address_overplane_i,
	input  wire [15:0]          external_address_cell_i,
	input  wire [2:0]           external_address_cell_source_row_i,
	/* verilator lint_on UNUSEDSIGNAL */
	output wire [15:0]          external_addressed_dram_cell_addr_o,
	output wire                 external_addressed_overplane_selected_o,
	output wire                 external_addressed_strict_overplane_o,
	output wire                 external_addressed_map_index_overflow_o,
	output wire [15:0]          external_addressed_vrm_character_row_addr_o,
	output wire [1:0]           external_addressed_palette_o,
	output wire                 external_addressed_hflip_o,
	output wire                 external_addressed_vflip_o,
	output wire                 external_address_mode_conflict_o,

	// Fetch work from the selected controller.
	input  wire                 tile_row_valid_i,
	output wire                 tile_row_ready_o,
	input  wire [0:0]           tile_row_load_i,
	input  wire [8:0]           tile_row_screen_y_i,
	input  wire signed [16:0]   tile_row_source_y_i,

	input  wire                 tile_valid_i,
	output wire                 tile_ready_o,
	input  wire [0:0]           tile_load_i,
	input  wire [12:0]          tile_ordinal_i,
	input  wire signed [15:0]   tile_x_i,

	input  wire                 row_valid_i,
	output wire                 row_ready_o,
	input  wire [0:0]           row_load_i,
	input  wire [12:0]          row_tile_ordinal_i,
	input  wire [2:0]           row_ordinal_i,
	input  wire [2:0]           row_source_index_i,
	input  wire [8:0]           row_screen_y_i,
	input  wire signed [16:0]   row_source_y_i,
	// Combinational permission for the current ordinal and X tag.
	input  wire                 result_permit_i,

	// Shared CELL DRAM interface.
	output wire                 dram_req_o,
	output wire [15:0]          dram_addr_o,
	input  wire                 dram_accept_i,
	input  wire                 dram_resp_valid_i,
	input  wire [15:0]          dram_resp_data_i,
	input  wire                 dram_router_cleanup_busy_i,
	input  wire                 dram_router_stale_discard_i,

	// Shared character-row VRM interface.
	output wire                 vrm_req_o,
	output wire [15:0]          vrm_addr_o,
	input  wire                 vrm_accept_i,
	input  wire                 vrm_resp_valid_i,
	input  wire [15:0]          vrm_resp_data_i,
	input  wire                 vrm_router_cleanup_busy_i,
	input  wire                 vrm_router_stale_discard_i,

	// raw_result_accept_o marks the edge that loads the blend register.
	output wire                 raw_result_valid_o,
	output wire                 raw_result_accept_o,
	output wire [1:0]           raw_result_owner_o,
	output wire [0:0]           raw_result_load_o,
	output wire [12:0]          raw_result_tile_ordinal_o,
	output wire [2:0]           raw_result_row_ordinal_o,
	output wire signed [15:0]   raw_result_tile_x_o,
	output wire [8:0]           raw_result_screen_y_o,
	output wire signed [16:0]   raw_result_source_y_o,
	output wire [2:0]           raw_result_source_index_o,
	output wire [8:0]           raw_result_tile_row_screen_y_o,
	output wire signed [16:0]   raw_result_tile_row_source_y_o,
	output wire [15:0]          raw_result_cell_o,
	output wire [15:0]          raw_result_character_row_o,
	output wire [1:0]           raw_result_palette_o,
	output wire                 raw_result_hflip_o,
	output wire                 raw_result_vflip_o,
	output wire                 raw_result_overplane_selected_o,
	output wire                 raw_result_strict_overplane_o,

	// Held row token and source tag.
	output wire                 token_valid_o,
	input  wire                 token_ready_i,
	output wire                 token_accept_o,
	output wire [2:0]           token_row_o,
	output wire signed [15:0]   token_left_base_x_o,
	output wire                 token_left_enable_o,
	output wire [7:0]           token_left_active_o,
	output wire [7:0]           token_left_opaque_o,
	output wire [15:0]          token_left_values_o,
	output wire signed [15:0]   token_right_base_x_o,
	output wire                 token_right_enable_o,
	output wire [7:0]           token_right_active_o,
	output wire [7:0]           token_right_opaque_o,
	output wire [15:0]          token_right_values_o,
	output wire [1:0]           token_owner_o,
	output wire [0:0]           token_load_o,
	output wire [12:0]          token_tile_ordinal_o,
	output wire [2:0]           token_row_ordinal_o,
	output wire signed [15:0]   token_tile_x_o,
	output wire [8:0]           token_screen_y_o,
	output wire signed [16:0]   token_source_y_o,
	output wire [2:0]           token_source_index_o,
	output wire [8:0]           token_tile_row_screen_y_o,
	output wire signed [16:0]   token_tile_row_source_y_o,
	output wire                 token_overplane_selected_o,
	output wire                 token_strict_overplane_o,

	// Context, ownership, cleanup, and unchanged fetch diagnostics.
	output wire                 context_accept_o,
	output wire                 context_owner_valid_o,
	output wire [1:0]           active_context_owner_o,
	output wire                 busy_o,
	output wire                 fetch_busy_o,
	output wire                 cleanup_busy_o,
	output wire                 dram_read_pending_o,
	output wire                 vrm_read_pending_o,
	output wire                 dram_stale_response_discarded_o,
	output wire                 vrm_stale_response_discarded_o,
	output wire                 unexpected_dram_response_o,
	output wire                 unexpected_vrm_response_o,
	output wire                 response_capture_overflow_o,
	output wire                 scheduler_tag_mismatch_o,
	output wire                 concurrent_work_error_o,
	output wire                 strict_overplane_seen_o,
	output wire                 map_index_overflow_seen_o,
	output wire [31:0]          diag_blend_input_accept_count_o,
	output wire [31:0]          diag_token_accept_count_o
);

	reg context_owner_valid_q;
	reg [1:0] context_owner_q;
	reg left_on_q;
	reg right_on_q;
	reg signed [17:0] left_source_start_q;
	reg signed [17:0] right_source_start_q;
	reg signed [17:0] left_destination_start_q;
	reg signed [17:0] right_destination_start_q;
	reg [12:0] semantic_width_q;
	reg [31:0] gplt_active_q;

	// Tag stored beside the blend register.
	reg [1:0] token_owner_q;
	reg [0:0] token_load_q;
	reg [12:0] token_tile_ordinal_q;
	reg [2:0] token_row_ordinal_q;
	reg signed [15:0] token_tile_x_q;
	reg [8:0] token_screen_y_q;
	reg signed [16:0] token_source_y_q;
	reg [2:0] token_source_index_q;
	reg [8:0] token_tile_row_screen_y_q;
	reg signed [16:0] token_tile_row_source_y_q;
	reg token_overplane_selected_q;
	reg token_strict_overplane_q;
	reg token_occupied_q;

	wire fetch_result_valid_w;
	wire fetch_result_ready_w;
	wire [0:0] fetch_result_load_w;
	wire [12:0] fetch_result_tile_ordinal_w;
	wire [2:0] fetch_result_row_ordinal_w;
	wire signed [15:0] fetch_result_tile_x_w;
	wire [8:0] fetch_result_screen_y_w;
	wire signed [16:0] fetch_result_source_y_w;
	wire [2:0] fetch_result_source_index_w;
	wire [8:0] fetch_result_tile_row_screen_y_w;
	wire signed [16:0] fetch_result_tile_row_source_y_w;
	wire [15:0] fetch_result_cell_w;
	wire [15:0] fetch_result_character_row_w;
	wire [1:0] fetch_result_palette_w;
	wire fetch_result_hflip_w;
	wire fetch_result_vflip_w;
	wire fetch_result_overplane_selected_w;
	wire fetch_result_strict_overplane_w;
	wire fetch_busy_w;
	wire fetch_cleanup_busy_w;
	wire blend_input_ready_w;
	wire blend_output_valid_w;
	wire [15:0] decoded_raw_pixels_w;
	wire [7:0] decoded_raw_nonzero_w;
	wire [15:0] decoded_mapped_pixels_w;

	// Fetch address-query context for CELL and character reads.
	wire signed [16:0] fetch_address_source_x_w;
	wire signed [16:0] fetch_address_source_y_w;
	wire [3:0] fetch_address_maps_wide_w;
	wire [3:0] fetch_address_maps_high_w;
	wire [3:0] fetch_address_effective_map_columns_w;
	wire [3:0] fetch_address_bgmap_base_rounded_w;
	wire fetch_address_over_w;
	wire [15:0] fetch_address_overplane_w;
	wire [15:0] fetch_address_cell_w;
	wire [2:0] fetch_address_cell_source_row_w;

	wire external_address_enabled_w = EXTERNAL_ADDRESS_SEAM != 0;
	// Selection depends only on offers, ownership, and cleanup state.
	wire fetch_address_owner_active_w = tile_valid_i || row_valid_i ||
		dram_read_pending_o || vrm_read_pending_o ||
		dram_router_cleanup_busy_i || vrm_router_cleanup_busy_i;
	wire external_address_selected_w = external_address_enabled_w &&
		external_address_select_i && !fetch_address_owner_active_w;
	wire signed [16:0] selected_address_source_x_w =
		external_address_selected_w ? external_address_source_x_i :
		fetch_address_source_x_w;
	wire signed [16:0] selected_address_source_y_w =
		external_address_selected_w ? external_address_source_y_i :
		fetch_address_source_y_w;
	wire [3:0] selected_address_maps_wide_w =
		external_address_selected_w ? external_address_maps_wide_i :
		fetch_address_maps_wide_w;
	wire [3:0] selected_address_maps_high_w =
		external_address_selected_w ? external_address_maps_high_i :
		fetch_address_maps_high_w;
	wire [3:0] selected_address_effective_map_columns_w =
		external_address_selected_w ?
		external_address_effective_map_columns_i :
		fetch_address_effective_map_columns_w;
	wire [3:0] selected_address_bgmap_base_rounded_w =
		external_address_selected_w ?
		external_address_bgmap_base_rounded_i :
		fetch_address_bgmap_base_rounded_w;
	wire selected_address_over_w = external_address_selected_w ?
		external_address_over_i : fetch_address_over_w;
	wire [15:0] selected_address_overplane_w =
		external_address_selected_w ? external_address_overplane_i :
		fetch_address_overplane_w;
	wire [15:0] selected_address_cell_w = external_address_selected_w ?
		external_address_cell_i : fetch_address_cell_w;
	wire [2:0] selected_address_cell_source_row_w =
		external_address_selected_w ?
		external_address_cell_source_row_i :
		fetch_address_cell_source_row_w;
	wire [15:0] addressed_dram_cell_addr_w;
	wire addressed_overplane_selected_w;
	wire addressed_strict_overplane_w;
	wire addressed_map_index_overflow_w;
	wire [15:0] addressed_vrm_character_row_addr_w;
	wire [1:0] addressed_palette_w;
	wire addressed_hflip_w;
	wire addressed_vflip_w;

	wire external_decode_enabled_w = EXTERNAL_DECODE_SEAM != 0;
	// A held tile result has decode priority over the external owner.
	wire external_decode_selected_w = external_decode_enabled_w &&
		external_decode_select_i && !fetch_result_valid_w;
	wire [15:0] decode_character_row_w = external_decode_selected_w ?
		external_decode_character_row_i : fetch_result_character_row_w;
	wire [1:0] decode_palette_w = external_decode_selected_w ?
		external_decode_palette_i : fetch_result_palette_w;
	wire decode_hflip_w = external_decode_selected_w ?
		external_decode_hflip_i : fetch_result_hflip_w;
	wire [2:0] decode_source_x_index_w = external_decode_selected_w ?
		external_decode_source_x_index_i : 3'd0;
	wire [31:0] decode_gplt_active_w = external_decode_selected_w ?
		external_decode_gplt_active_i : gplt_active_q;
	// Rearm uses request and ownership state directly to avoid a reset/busy loop.
	wire rearm_fetch_quiescent_w = !tile_row_valid_i && !tile_valid_i &&
		!row_valid_i && !dram_read_pending_o && !vrm_read_pending_o &&
		!dram_router_cleanup_busy_i && !vrm_router_cleanup_busy_i;
	wire rearm_quiescent_w = rearm_fetch_quiescent_w &&
		!fetch_cleanup_busy_w && !token_occupied_q;

	assign diagnostic_rearm_ready_o = ce_i && !reset_i && !abort_i &&
		rearm_quiescent_w;
	assign diagnostic_rearm_accept_o = diagnostic_rearm_i &&
		diagnostic_rearm_ready_o;
	// Fetch owns sticky errors; blend counters are trace-only.
	wire fetch_reset_w = reset_i || diagnostic_rearm_accept_o;

	assign context_accept_o = ce_i && tile_row_valid_i &&
		tile_row_ready_o;
	assign context_owner_valid_o = context_owner_valid_q;
	assign active_context_owner_o = context_owner_q;

	// H-bias prime sees raw result acceptance on the same edge.
	assign fetch_result_ready_w = blend_input_ready_w && result_permit_i;
	assign raw_result_valid_o = fetch_result_valid_w;
	assign raw_result_accept_o = ce_i && fetch_result_valid_w &&
		result_permit_i && blend_input_ready_w;
	assign raw_result_owner_o = context_owner_q;
	assign raw_result_load_o = fetch_result_load_w;
	assign raw_result_tile_ordinal_o = fetch_result_tile_ordinal_w;
	assign raw_result_row_ordinal_o = fetch_result_row_ordinal_w;
	assign raw_result_tile_x_o = fetch_result_tile_x_w;
	assign raw_result_screen_y_o = fetch_result_screen_y_w;
	assign raw_result_source_y_o = fetch_result_source_y_w;
	assign raw_result_source_index_o = fetch_result_source_index_w;
	assign raw_result_tile_row_screen_y_o =
		fetch_result_tile_row_screen_y_w;
	assign raw_result_tile_row_source_y_o =
		fetch_result_tile_row_source_y_w;
	assign raw_result_cell_o = fetch_result_cell_w;
	assign raw_result_character_row_o = fetch_result_character_row_w;
	assign raw_result_palette_o = fetch_result_palette_w;
	assign raw_result_hflip_o = fetch_result_hflip_w;
	assign raw_result_vflip_o = fetch_result_vflip_w;
	assign raw_result_overplane_selected_o =
		fetch_result_overplane_selected_w;
	assign raw_result_strict_overplane_o =
		fetch_result_strict_overplane_w;

	assign token_valid_o = blend_output_valid_w;
	assign token_accept_o = ce_i && token_valid_o && token_ready_i;
	assign token_owner_o = token_owner_q;
	assign token_load_o = token_load_q;
	assign token_tile_ordinal_o = token_tile_ordinal_q;
	assign token_row_ordinal_o = token_row_ordinal_q;
	assign token_tile_x_o = token_tile_x_q;
	assign token_screen_y_o = token_screen_y_q;
	assign token_source_y_o = token_source_y_q;
	assign token_source_index_o = token_source_index_q;
	assign token_tile_row_screen_y_o = token_tile_row_screen_y_q;
	assign token_tile_row_source_y_o = token_tile_row_source_y_q;
	assign token_overplane_selected_o = token_overplane_selected_q;
	assign token_strict_overplane_o = token_strict_overplane_q;

	assign busy_o = fetch_busy_w || blend_output_valid_w;
	assign fetch_busy_o = fetch_busy_w;
	assign cleanup_busy_o = fetch_cleanup_busy_w;
	assign external_decode_mode_conflict_o =
		external_decode_enabled_w && external_decode_select_i &&
		(fetch_busy_w || blend_output_valid_w);
	assign external_addressed_dram_cell_addr_o =
		addressed_dram_cell_addr_w;
	assign external_addressed_overplane_selected_o =
		addressed_overplane_selected_w;
	assign external_addressed_strict_overplane_o =
		addressed_strict_overplane_w;
	assign external_addressed_map_index_overflow_o =
		addressed_map_index_overflow_w;
	assign external_addressed_vrm_character_row_addr_o =
		addressed_vrm_character_row_addr_w;
	assign external_addressed_palette_o = addressed_palette_w;
	assign external_addressed_hflip_o = addressed_hflip_w;
	assign external_addressed_vflip_o = addressed_vflip_w;
	assign external_address_mode_conflict_o =
		external_address_enabled_w && external_address_select_i &&
		fetch_address_owner_active_w;

	// One address stage serves fetch or Affine, with fetch priority.
	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_bg_address u_bg_address
	(
		.source_x_i(selected_address_source_x_w),
		.source_y_i(selected_address_source_y_w),
		.maps_wide_i(selected_address_maps_wide_w),
		.maps_high_i(selected_address_maps_high_w),
		.effective_map_columns_i(
			selected_address_effective_map_columns_w),
		.bgmap_base_rounded_i(selected_address_bgmap_base_rounded_w),
		.over_i(selected_address_over_w),
		.overplane_i(selected_address_overplane_w),
		.dram_cell_addr_o(addressed_dram_cell_addr_w),
		.overplane_selected_o(addressed_overplane_selected_w),
		.strict_overplane_range_o(addressed_strict_overplane_w),
		.wrapped_source_x_o(),
		.wrapped_source_y_o(),
		.source_x_low_o(),
		.source_y_low_o(),
		.map_x_o(),
		.map_y_o(),
		.effective_map_x_o(),
		.map_index_o(),
		.map_index_overflow_o(addressed_map_index_overflow_w),
		.cell_x_o(),
		.cell_y_o(),
		.cell_i(selected_address_cell_w),
		.cell_source_row_i(selected_address_cell_source_row_w),
		.vrm_character_row_addr_o(addressed_vrm_character_row_addr_w),
		.character_o(),
		.character_row_o(),
		.palette_o(addressed_palette_w),
		.hflip_o(addressed_hflip_w),
		.vflip_o(addressed_vflip_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_bg_fetch
	#(
		.EXTERNAL_ADDRESS_SEAM(1)
	)
	u_bg_fetch
	(
		.clk_i(clk_i),
		.reset_i(fetch_reset_w),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.maps_wide_i(maps_wide_i),
		.maps_high_i(maps_high_i),
		.effective_map_columns_i(effective_map_columns_i),
		.bgmap_base_rounded_i(bgmap_base_rounded_i),
		.over_i(over_i),
		.overplane_i(overplane_i),
		.address_source_x_o(fetch_address_source_x_w),
		.address_source_y_o(fetch_address_source_y_w),
		.address_maps_wide_o(fetch_address_maps_wide_w),
		.address_maps_high_o(fetch_address_maps_high_w),
		.address_effective_map_columns_o(
			fetch_address_effective_map_columns_w),
		.address_bgmap_base_rounded_o(
			fetch_address_bgmap_base_rounded_w),
		.address_over_o(fetch_address_over_w),
		.address_overplane_o(fetch_address_overplane_w),
		.address_cell_o(fetch_address_cell_w),
		.address_cell_source_row_o(
			fetch_address_cell_source_row_w),
		.addressed_dram_cell_addr_i(addressed_dram_cell_addr_w),
		.addressed_overplane_selected_i(
			addressed_overplane_selected_w),
		.addressed_strict_overplane_i(addressed_strict_overplane_w),
		.addressed_map_index_overflow_i(
			addressed_map_index_overflow_w),
		.addressed_vrm_character_row_addr_i(
			addressed_vrm_character_row_addr_w),
		.addressed_palette_i(addressed_palette_w),
		.addressed_hflip_i(addressed_hflip_w),
		.addressed_vflip_i(addressed_vflip_w),
		.tile_row_valid_i(tile_row_valid_i),
		.tile_row_ready_o(tile_row_ready_o),
		.tile_row_load_i(tile_row_load_i),
		.tile_row_screen_y_i(tile_row_screen_y_i),
		.tile_row_source_y_i(tile_row_source_y_i),
		.tile_valid_i(tile_valid_i),
		.tile_ready_o(tile_ready_o),
		.tile_load_i(tile_load_i),
		.tile_ordinal_i(tile_ordinal_i),
		.tile_x_i(tile_x_i),
		.row_valid_i(row_valid_i),
		.row_ready_o(row_ready_o),
		.row_load_i(row_load_i),
		.row_tile_ordinal_i(row_tile_ordinal_i),
		.row_ordinal_i(row_ordinal_i),
		.row_source_index_i(row_source_index_i),
		.row_screen_y_i(row_screen_y_i),
		.row_source_y_i(row_source_y_i),
		.dram_req_o(dram_req_o),
		.dram_addr_o(dram_addr_o),
		.dram_accept_i(dram_accept_i),
		.dram_resp_valid_i(dram_resp_valid_i),
		.dram_resp_data_i(dram_resp_data_i),
		.dram_router_cleanup_busy_i(dram_router_cleanup_busy_i),
		.dram_router_stale_discard_i(dram_router_stale_discard_i),
		.vrm_req_o(vrm_req_o),
		.vrm_addr_o(vrm_addr_o),
		.vrm_accept_i(vrm_accept_i),
		.vrm_resp_valid_i(vrm_resp_valid_i),
		.vrm_resp_data_i(vrm_resp_data_i),
		.vrm_router_cleanup_busy_i(vrm_router_cleanup_busy_i),
		.vrm_router_stale_discard_i(vrm_router_stale_discard_i),
		.row_result_valid_o(fetch_result_valid_w),
		.row_result_ready_i(fetch_result_ready_w),
		.row_result_load_o(fetch_result_load_w),
		.row_result_tile_ordinal_o(fetch_result_tile_ordinal_w),
		.row_result_row_ordinal_o(fetch_result_row_ordinal_w),
		.row_result_tile_x_o(fetch_result_tile_x_w),
		.row_result_screen_y_o(fetch_result_screen_y_w),
		.row_result_source_y_o(fetch_result_source_y_w),
		.row_result_source_index_o(fetch_result_source_index_w),
		.row_result_tile_row_screen_y_o(
			fetch_result_tile_row_screen_y_w),
		.row_result_tile_row_source_y_o(
			fetch_result_tile_row_source_y_w),
		.row_result_cell_o(fetch_result_cell_w),
		.row_result_character_row_o(fetch_result_character_row_w),
		.row_result_palette_o(fetch_result_palette_w),
		.row_result_hflip_o(fetch_result_hflip_w),
		.row_result_vflip_o(fetch_result_vflip_w),
		.row_result_overplane_selected_o(
			fetch_result_overplane_selected_w),
		.row_result_strict_overplane_o(
			fetch_result_strict_overplane_w),
		.busy_o(fetch_busy_w),
		.cleanup_busy_o(fetch_cleanup_busy_w),
		.dram_read_pending_o(dram_read_pending_o),
		.vrm_read_pending_o(vrm_read_pending_o),
		.dram_stale_response_discarded_o(
			dram_stale_response_discarded_o),
		.vrm_stale_response_discarded_o(
			vrm_stale_response_discarded_o),
		.unexpected_dram_response_o(unexpected_dram_response_o),
		.unexpected_vrm_response_o(unexpected_vrm_response_o),
		.response_capture_overflow_o(response_capture_overflow_o),
		.scheduler_tag_mismatch_o(scheduler_tag_mismatch_o),
		.concurrent_work_error_o(concurrent_work_error_o),
		.strict_overplane_seen_o(strict_overplane_seen_o),
		.map_index_overflow_seen_o(map_index_overflow_seen_o)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	// One combinational character decoder serves the selected renderer.
	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_bg_character_decode u_bg_character_decode
	(
		.character_row_i(decode_character_row_w),
		.palette_i(decode_palette_w),
		.hflip_i(decode_hflip_w),
		.selected_index_i(decode_source_x_index_w),
		.gplt_active_i(decode_gplt_active_w),
		.raw_pixels_o(decoded_raw_pixels_w),
		.raw_nonzero_o(decoded_raw_nonzero_w),
		.mapped_pixels_o(decoded_mapped_pixels_w),
		.selected_raw_pixel_o(external_decoded_raw_pixel_o),
		.selected_raw_nonzero_o(external_decoded_raw_nonzero_o),
		.selected_mapped_pixel_o(external_decoded_mapped_pixel_o)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	assign external_decoded_raw_pixels_o = decoded_raw_pixels_w;
	assign external_decoded_raw_nonzero_vector_o =
		decoded_raw_nonzero_w;
	assign external_decoded_mapped_pixels_o = decoded_mapped_pixels_w;

	vip_xp_bg_row_blend_core u_bg_row_blend_core
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.input_valid_i(fetch_result_valid_w && result_permit_i),
		.input_ready_o(blend_input_ready_w),
		.tile_x_i({{2{fetch_result_tile_x_w[15]}},
			fetch_result_tile_x_w}),
		.screen_y_i(fetch_result_screen_y_w),
		.decoded_raw_nonzero_i(decoded_raw_nonzero_w),
		.decoded_mapped_pixels_i(decoded_mapped_pixels_w),
		.left_on_i(left_on_q),
		.right_on_i(right_on_q),
		.left_source_start_i(left_source_start_q),
		.right_source_start_i(right_source_start_q),
		.left_destination_start_i(left_destination_start_q),
		.right_destination_start_i(right_destination_start_q),
		.semantic_width_i(semantic_width_q),
		.output_valid_o(blend_output_valid_w),
		.output_ready_i(token_ready_i),
		.output_row_o(token_row_o),
		.output_left_base_x_o(token_left_base_x_o),
		.output_right_base_x_o(token_right_base_x_o),
		.output_left_enable_o(token_left_enable_o),
		.output_right_enable_o(token_right_enable_o),
		.output_left_active_o(token_left_active_o),
		.output_right_active_o(token_right_active_o),
		.output_left_opaque_o(token_left_opaque_o),
		.output_right_opaque_o(token_right_opaque_o),
		.output_left_values_o(token_left_values_o),
		.output_right_values_o(token_right_values_o),
		.diag_input_accept_count_o(diag_blend_input_accept_count_o),
		.diag_output_accept_count_o(diag_token_accept_count_o)
	);

	always @(posedge clk_i) begin
		if (reset_i || diagnostic_rearm_accept_o) begin
			context_owner_valid_q <= 1'b0;
			context_owner_q <= 2'd0;
			left_on_q <= 1'b0;
			right_on_q <= 1'b0;
			left_source_start_q <= 18'sd0;
			right_source_start_q <= 18'sd0;
			left_destination_start_q <= 18'sd0;
			right_destination_start_q <= 18'sd0;
			semantic_width_q <= 13'd0;
			gplt_active_q <= 32'd0;
			token_owner_q <= 2'd0;
			token_load_q <= 1'd0;
			token_tile_ordinal_q <= 13'd0;
			token_row_ordinal_q <= 3'd0;
			token_tile_x_q <= 16'sd0;
			token_screen_y_q <= 9'd0;
			token_source_y_q <= 17'sd0;
			token_source_index_q <= 3'd0;
			token_tile_row_screen_y_q <= 9'd0;
			token_tile_row_source_y_q <= 17'sd0;
			token_overplane_selected_q <= 1'b0;
			token_strict_overplane_q <= 1'b0;
			token_occupied_q <= 1'b0;
			diagnostic_rearm_rejected_o <= 1'b0;
		end else if (abort_i) begin
			token_occupied_q <= 1'b0;
		end else if (ce_i) begin
			if (diagnostic_rearm_i && !diagnostic_rearm_ready_o) begin
				diagnostic_rearm_rejected_o <= 1'b1;
			end
			if (context_accept_o) begin
				context_owner_valid_q <= 1'b1;
				context_owner_q <= controller_owner_i;
				left_on_q <= left_on_i;
				right_on_q <= right_on_i;
				left_source_start_q <= left_source_start_i;
				right_source_start_q <= right_source_start_i;
				left_destination_start_q <=
					left_destination_start_i;
				right_destination_start_q <=
					right_destination_start_i;
				semantic_width_q <= semantic_width_i;
				gplt_active_q <= gplt_active_i;
			end

			if (raw_result_accept_o) begin
				token_occupied_q <= 1'b1;
				token_owner_q <= context_owner_q;
				token_load_q <= fetch_result_load_w;
				token_tile_ordinal_q <= fetch_result_tile_ordinal_w;
				token_row_ordinal_q <= fetch_result_row_ordinal_w;
				token_tile_x_q <= fetch_result_tile_x_w;
				token_screen_y_q <= fetch_result_screen_y_w;
				token_source_y_q <= fetch_result_source_y_w;
				token_source_index_q <= fetch_result_source_index_w;
				token_tile_row_screen_y_q <=
					fetch_result_tile_row_screen_y_w;
				token_tile_row_source_y_q <=
					fetch_result_tile_row_source_y_w;
				token_overplane_selected_q <=
					fetch_result_overplane_selected_w;
				token_strict_overplane_q <=
					fetch_result_strict_overplane_w;
			end else if (token_accept_o) begin
				token_occupied_q <= 1'b0;
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Normal and H-bias cell and character-row address logic.
//
// Source coordinates wrap to power-of-two map bounds when OVER is clear.
//
// CELL uses a DRAM halfword address. Character address concatenation preserves
// gaps between the four banks without multiplication.

module vip_xp_bg_address
(
	input  wire signed [16:0] source_x_i,
	input  wire signed [16:0] source_y_i,
	input  wire        [3:0]  maps_wide_i,
	input  wire        [3:0]  maps_high_i,
	input  wire        [3:0]  effective_map_columns_i,
	input  wire        [3:0]  bgmap_base_rounded_i,
	input  wire               over_i,
	input  wire        [15:0] overplane_i,

	output wire        [15:0] dram_cell_addr_o,
	output wire               overplane_selected_o,
	output wire               strict_overplane_range_o,
	output wire        [11:0] wrapped_source_x_o,
	output wire        [11:0] wrapped_source_y_o,
	output wire        [2:0]  source_x_low_o,
	output wire        [2:0]  source_y_low_o,
	output wire        [2:0]  map_x_o,
	output wire        [2:0]  map_y_o,
	output wire        [2:0]  effective_map_x_o,
	output wire        [3:0]  map_index_o,
	output wire               map_index_overflow_o,
	output wire        [5:0]  cell_x_o,
	output wire        [5:0]  cell_y_o,

	/* verilator lint_off UNUSEDSIGNAL */
	input  wire        [15:0] cell_i,
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire        [2:0]  cell_source_row_i,
	output wire        [15:0] vrm_character_row_addr_o,
	output wire        [10:0] character_o,
	output wire        [2:0]  character_row_o,
	output wire        [1:0]  palette_o,
	output wire               hflip_o,
	output wire               vflip_o
);

	reg        source_x_out_of_bounds_t;
	reg        source_y_out_of_bounds_t;
	reg [11:0] wrapped_source_x_t;
	reg [11:0] wrapped_source_y_t;
	reg [2:0]  effective_map_x_t;
	reg [5:0]  map_row_offset_t;

	wire [2:0] map_x_w = wrapped_source_x_t[11:9];
	wire [2:0] map_y_w = wrapped_source_y_t[11:9];
	wire [5:0] map_column_offset_w = {3'd0, effective_map_x_t};
	wire [6:0] map_index_extended_w =
		{3'd0, bgmap_base_rounded_i} +
		{1'b0, map_row_offset_t} +
		{1'b0, map_column_offset_w};
	wire [3:0] map_index_w = map_index_extended_w[3:0];
	wire [5:0] cell_x_w = wrapped_source_x_t[8:3];
	wire [5:0] cell_y_w = wrapped_source_y_t[8:3];
	wire [15:0] mapped_cell_addr_w =
		{map_index_w, cell_y_w, cell_x_w};
	wire [2:0] character_row_w = cell_i[12] ?
		(~cell_source_row_i) : cell_source_row_i;

	always @* begin
		case (maps_wide_i)
			4'd1: begin
				source_x_out_of_bounds_t = source_x_i[16] ||
					(|source_x_i[15:9]);
				wrapped_source_x_t = {3'd0, source_x_i[8:0]};
			end
			4'd2: begin
				source_x_out_of_bounds_t = source_x_i[16] ||
					(|source_x_i[15:10]);
				wrapped_source_x_t = {2'd0, source_x_i[9:0]};
			end
			4'd4: begin
				source_x_out_of_bounds_t = source_x_i[16] ||
					(|source_x_i[15:11]);
				wrapped_source_x_t = {1'b0, source_x_i[10:0]};
			end
			default: begin
				source_x_out_of_bounds_t = source_x_i[16] ||
					(|source_x_i[15:12]);
				wrapped_source_x_t = source_x_i[11:0];
			end
		endcase

		case (maps_high_i)
			4'd1: begin
				source_y_out_of_bounds_t = source_y_i[16] ||
					(|source_y_i[15:9]);
				wrapped_source_y_t = {3'd0, source_y_i[8:0]};
			end
			4'd2: begin
				source_y_out_of_bounds_t = source_y_i[16] ||
					(|source_y_i[15:10]);
				wrapped_source_y_t = {2'd0, source_y_i[9:0]};
			end
			4'd4: begin
				source_y_out_of_bounds_t = source_y_i[16] ||
					(|source_y_i[15:11]);
				wrapped_source_y_t = {1'b0, source_y_i[10:0]};
			end
			default: begin
				source_y_out_of_bounds_t = source_y_i[16] ||
					(|source_y_i[15:12]);
				wrapped_source_y_t = source_y_i[11:0];
			end
		endcase

		case (effective_map_columns_i)
			4'd1: begin
				effective_map_x_t = 3'd0;
				map_row_offset_t = {3'd0, map_y_w};
			end
			4'd2: begin
				effective_map_x_t = {2'd0, map_x_w[0]};
				map_row_offset_t = {2'd0, map_y_w, 1'b0};
			end
			4'd4: begin
				effective_map_x_t = {1'b0, map_x_w[1:0]};
				map_row_offset_t = {1'b0, map_y_w, 2'b00};
			end
			default: begin
				effective_map_x_t = map_x_w;
				map_row_offset_t = {map_y_w, 3'b000};
			end
		endcase
	end

	assign overplane_selected_o = over_i &&
		(source_x_out_of_bounds_t || source_y_out_of_bounds_t);
	assign strict_overplane_range_o = overplane_selected_o &&
		(overplane_i[15:13] == 3'b111);
	assign dram_cell_addr_o = overplane_selected_o ?
		overplane_i : mapped_cell_addr_w;

	assign wrapped_source_x_o = wrapped_source_x_t;
	assign wrapped_source_y_o = wrapped_source_y_t;
	assign source_x_low_o = source_x_i[2:0];
	assign source_y_low_o = source_y_i[2:0];
	assign map_x_o = map_x_w;
	assign map_y_o = map_y_w;
	assign effective_map_x_o = effective_map_x_t;
	assign map_index_o = map_index_w;
	assign map_index_overflow_o = |map_index_extended_w[6:4];
	assign cell_x_o = cell_x_w;
	assign cell_y_o = cell_y_w;

	assign character_o = cell_i[10:0];
	assign character_row_o = character_row_w;
	assign palette_o = cell_i[15:14];
	assign hflip_o = cell_i[13];
	assign vflip_o = cell_i[12];
	// VRM character-row address; vip_xp_obj_char_pipeline and
	// vip_xp_obj_row_token build the same shape from JCA.
	assign vrm_character_row_addr_o = {
		cell_i[10:9], 2'b11, cell_i[8:0], character_row_w
	};

endmodule

`timescale 1ns/1ps

// Held background cell and character-row fetch pipeline.
//
// Hold scheduler requests until ready. Each tile reads one CELL, and each row
// reads one character word. Raw-clock capture preserves responses during CE
// pauses; abort drops offers and drains accepted reads.

module vip_xp_bg_fetch
#(
	// Shared mode supplies addresses from the single background-address block.
	parameter integer EXTERNAL_ADDRESS_SEAM = 0
)
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	// Background settings captured at tile-row load.
	input  wire [3:0]           maps_wide_i,
	input  wire [3:0]           maps_high_i,
	input  wire [3:0]           effective_map_columns_i,
	input  wire [3:0]           bgmap_base_rounded_i,
	input  wire                 over_i,
	input  wire [15:0]          overplane_i,

	// Held query to the shared background-address block.
	output wire signed [16:0]   address_source_x_o,
	output wire signed [16:0]   address_source_y_o,
	output wire [3:0]           address_maps_wide_o,
	output wire [3:0]           address_maps_high_o,
	output wire [3:0]           address_effective_map_columns_o,
	output wire [3:0]           address_bgmap_base_rounded_o,
	output wire                 address_over_o,
	output wire [15:0]          address_overplane_o,
	output wire [15:0]          address_cell_o,
	output wire [2:0]           address_cell_source_row_o,
	// Same-cycle shared address result.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [15:0]          addressed_dram_cell_addr_i,
	input  wire                 addressed_overplane_selected_i,
	input  wire                 addressed_strict_overplane_i,
	input  wire                 addressed_map_index_overflow_i,
	input  wire [15:0]          addressed_vrm_character_row_addr_i,
	input  wire [1:0]           addressed_palette_i,
	input  wire                 addressed_hflip_i,
	input  wire                 addressed_vflip_i,
	/* verilator lint_on UNUSEDSIGNAL */

	// Held tile-row context.
	input  wire                 tile_row_valid_i,
	output wire                 tile_row_ready_o,
	input  wire [0:0]           tile_row_load_i,
	input  wire [8:0]           tile_row_screen_y_i,
	input  wire signed [16:0]   tile_row_source_y_i,

	// Tile request; ready means its CELL response was captured.
	input  wire                 tile_valid_i,
	output wire                 tile_ready_o,
	input  wire [0:0]           tile_load_i,
	input  wire [12:0]          tile_ordinal_i,
	input  wire signed [15:0]   tile_x_i,

	// Row request; ready means the row result was accepted.
	input  wire                 row_valid_i,
	output wire                 row_ready_o,
	input  wire [0:0]           row_load_i,
	input  wire [12:0]          row_tile_ordinal_i,
	input  wire [2:0]           row_ordinal_i,
	input  wire [2:0]           row_source_index_i,
	input  wire [8:0]           row_screen_y_i,
	input  wire signed [16:0]   row_source_y_i,

	// Background DRAM client.
	output wire                 dram_req_o,
	output wire [15:0]          dram_addr_o,
	input  wire                 dram_accept_i,
	input  wire                 dram_resp_valid_i,
	input  wire [15:0]          dram_resp_data_i,
	input  wire                 dram_router_cleanup_busy_i,
	input  wire                 dram_router_stale_discard_i,

	// Background VRM client.
	output wire                 vrm_req_o,
	output wire [15:0]          vrm_addr_o,
	input  wire                 vrm_accept_i,
	input  wire                 vrm_resp_valid_i,
	input  wire [15:0]          vrm_resp_data_i,
	input  wire                 vrm_router_cleanup_busy_i,
	input  wire                 vrm_router_stale_discard_i,

	// Hold row results until accepted.
	output wire                 row_result_valid_o,
	input  wire                 row_result_ready_i,
	output wire [0:0]           row_result_load_o,
	output wire [12:0]          row_result_tile_ordinal_o,
	output wire [2:0]           row_result_row_ordinal_o,
	output wire signed [15:0]   row_result_tile_x_o,
	output wire [8:0]           row_result_screen_y_o,
	output wire signed [16:0]   row_result_source_y_o,
	output wire [2:0]           row_result_source_index_o,
	output wire [8:0]           row_result_tile_row_screen_y_o,
	output wire signed [16:0]   row_result_tile_row_source_y_o,
	output wire [15:0]          row_result_cell_o,
	output wire [15:0]          row_result_character_row_o,
	output wire [1:0]           row_result_palette_o,
	output wire                 row_result_hflip_o,
	output wire                 row_result_vflip_o,
	output wire                 row_result_overplane_selected_o,
	output wire                 row_result_strict_overplane_o,

	// Ownership and protocol diagnostics.
	output wire                 busy_o,
	output wire                 cleanup_busy_o,
	output wire                 dram_read_pending_o,
	output wire                 vrm_read_pending_o,
	output reg                  dram_stale_response_discarded_o,
	output reg                  vrm_stale_response_discarded_o,
	output reg                  unexpected_dram_response_o,
	output reg                  unexpected_vrm_response_o,
	output reg                  response_capture_overflow_o,
	output reg                  scheduler_tag_mismatch_o,
	output reg                  concurrent_work_error_o,
	output reg                  strict_overplane_seen_o,
	output reg                  map_index_overflow_seen_o
);

	reg                 tile_row_context_valid_q;
	reg [0:0]           tile_row_load_q;
	reg [8:0]           tile_row_screen_y_q;
	reg signed [16:0]   tile_row_source_y_q;
	reg [3:0]           maps_wide_q;
	reg [3:0]           maps_high_q;
	reg [3:0]           effective_map_columns_q;
	reg [3:0]           bgmap_base_rounded_q;
	reg                 over_q;
	reg [15:0]          overplane_q;

	reg                 dram_pending_q;
	reg                 dram_stale_q;
	reg                 dram_capture_valid_q;
	reg [15:0]          dram_capture_data_q;
	reg [0:0]           dram_tile_load_q;
	reg [12:0]          dram_tile_ordinal_q;
	reg signed [15:0]   dram_tile_x_q;
	reg                 dram_overplane_selected_q;
	reg                 dram_strict_overplane_q;

	reg                 cell_valid_q;
	reg [15:0]          cell_q;
	reg [0:0]           cell_load_q;
	reg [12:0]          cell_tile_ordinal_q;
	reg signed [15:0]   cell_tile_x_q;
	reg                 cell_overplane_selected_q;
	reg                 cell_strict_overplane_q;

	reg                 vrm_pending_q;
	reg                 vrm_stale_q;
	reg                 vrm_capture_valid_q;
	reg [15:0]          vrm_capture_data_q;
	reg [0:0]           vrm_row_load_q;
	reg [12:0]          vrm_row_tile_ordinal_q;
	reg [2:0]           vrm_row_ordinal_q;
	reg signed [15:0]   vrm_row_tile_x_q;
	reg [8:0]           vrm_row_screen_y_q;
	reg signed [16:0]   vrm_row_source_y_q;
	reg [2:0]           vrm_row_source_index_q;
	reg [8:0]           vrm_tile_row_screen_y_q;
	reg signed [16:0]   vrm_tile_row_source_y_q;
	reg [15:0]          vrm_row_cell_q;
	reg [1:0]           vrm_row_palette_q;
	reg                 vrm_row_hflip_q;
	reg                 vrm_row_vflip_q;
	reg                 vrm_row_overplane_selected_q;
	reg                 vrm_row_strict_overplane_q;

	wire signed [16:0] address_source_x_w =
		{{1{tile_x_i[15]}}, tile_x_i};
	wire [15:0] address_dram_cell_w;
	wire        address_overplane_selected_w;
	wire        address_strict_overplane_w;
	wire        address_map_index_overflow_w;
	wire [15:0] address_vrm_character_row_w;
	wire [1:0]  address_palette_w;
	wire        address_hflip_w;
	wire        address_vflip_w;

	assign address_source_x_o = address_source_x_w;
	assign address_source_y_o = tile_row_source_y_q;
	assign address_maps_wide_o = maps_wide_q;
	assign address_maps_high_o = maps_high_q;
	assign address_effective_map_columns_o =
		effective_map_columns_q;
	assign address_bgmap_base_rounded_o = bgmap_base_rounded_q;
	assign address_over_o = over_q;
	assign address_overplane_o = overplane_q;
	assign address_cell_o = cell_q;
	assign address_cell_source_row_o = row_source_index_i;

	wire tile_context_match_w = tile_row_context_valid_q &&
		(tile_load_i == tile_row_load_q);
	wire cell_context_match_w = cell_valid_q &&
		(row_load_i == cell_load_q) &&
		(row_tile_ordinal_i == cell_tile_ordinal_q);
	wire dram_response_tag_match_w = tile_valid_i &&
		(tile_load_i == dram_tile_load_q) &&
		(tile_ordinal_i == dram_tile_ordinal_q) &&
		(tile_x_i == dram_tile_x_q);
	wire vrm_response_tag_match_w = row_valid_i &&
		(row_load_i == vrm_row_load_q) &&
		(row_tile_ordinal_i == vrm_row_tile_ordinal_q) &&
		(row_ordinal_i == vrm_row_ordinal_q) &&
		(row_source_index_i == vrm_row_source_index_q) &&
		(row_screen_y_i == vrm_row_screen_y_q) &&
		(row_source_y_i == vrm_row_source_y_q);

	wire dram_response_available_w = dram_capture_valid_q ||
		dram_resp_valid_i;
	wire [15:0] dram_response_data_w = dram_capture_valid_q ?
		dram_capture_data_q : dram_resp_data_i;
	wire vrm_response_available_w = vrm_capture_valid_q ||
		vrm_resp_valid_i;
	wire [15:0] vrm_response_data_w = vrm_capture_valid_q ?
		vrm_capture_data_q : vrm_resp_data_i;

	wire dram_stale_active_w = dram_pending_q &&
		(dram_stale_q || abort_i);
	wire vrm_stale_active_w = vrm_pending_q &&
		(vrm_stale_q || abort_i);
	wire dram_stale_drain_w = ce_i && dram_stale_active_w &&
		dram_response_available_w;
	wire vrm_stale_drain_w = ce_i && vrm_stale_active_w &&
		vrm_response_available_w;
	wire dram_live_retire_w = ce_i && !abort_i && dram_pending_q &&
		!dram_stale_q && dram_response_available_w &&
		dram_response_tag_match_w;
	wire vrm_live_result_w = !abort_i && vrm_pending_q &&
		!vrm_stale_q && vrm_response_available_w &&
		vrm_response_tag_match_w;
	wire row_result_fire_w = ce_i && vrm_live_result_w &&
		row_result_ready_i;

	wire router_cleanup_busy_w = dram_router_cleanup_busy_i ||
		vrm_router_cleanup_busy_i;
	wire dram_offer_w = !reset_i && !abort_i && !router_cleanup_busy_w &&
		tile_valid_i && tile_context_match_w &&
		!dram_pending_q && !vrm_pending_q;
	wire vrm_offer_w = !reset_i && !abort_i && row_valid_i &&
		!router_cleanup_busy_w && cell_context_match_w &&
		!dram_pending_q && !vrm_pending_q && !dram_offer_w;
	wire dram_accept_fire_w = ce_i && dram_offer_w && dram_accept_i;
	wire vrm_accept_fire_w = ce_i && vrm_offer_w && vrm_accept_i;
	wire tile_row_fire_w = tile_row_valid_i && tile_row_ready_o;

	assign tile_row_ready_o = ce_i && !reset_i && !abort_i &&
		!router_cleanup_busy_w && !dram_pending_q && !vrm_pending_q &&
		!tile_valid_i && !row_valid_i;
	assign tile_ready_o = dram_live_retire_w;
	assign row_ready_o = row_result_fire_w;

	assign dram_req_o = dram_offer_w;
	assign dram_addr_o = address_dram_cell_w;
	assign vrm_req_o = vrm_offer_w;
	assign vrm_addr_o = address_vrm_character_row_w;

	assign row_result_valid_o = vrm_live_result_w;
	assign row_result_load_o = vrm_row_load_q;
	assign row_result_tile_ordinal_o = vrm_row_tile_ordinal_q;
	assign row_result_row_ordinal_o = vrm_row_ordinal_q;
	assign row_result_tile_x_o = vrm_row_tile_x_q;
	assign row_result_screen_y_o = vrm_row_screen_y_q;
	assign row_result_source_y_o = vrm_row_source_y_q;
	assign row_result_source_index_o = vrm_row_source_index_q;
	assign row_result_tile_row_screen_y_o = vrm_tile_row_screen_y_q;
	assign row_result_tile_row_source_y_o = vrm_tile_row_source_y_q;
	assign row_result_cell_o = vrm_row_cell_q;
	assign row_result_character_row_o = vrm_response_data_w;
	assign row_result_palette_o = vrm_row_palette_q;
	assign row_result_hflip_o = vrm_row_hflip_q;
	assign row_result_vflip_o = vrm_row_vflip_q;
	assign row_result_overplane_selected_o =
		vrm_row_overplane_selected_q;
	assign row_result_strict_overplane_o = vrm_row_strict_overplane_q;

	assign busy_o = router_cleanup_busy_w || dram_pending_q || vrm_pending_q ||
		dram_req_o || vrm_req_o;
	assign cleanup_busy_o = router_cleanup_busy_w ||
		dram_stale_active_w || vrm_stale_active_w;
	assign dram_read_pending_o = dram_pending_q;
	assign vrm_read_pending_o = vrm_pending_q;

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

	always @(posedge clk_i) begin
		if (reset_i) begin
			tile_row_context_valid_q <= 1'b0;
			tile_row_load_q <= 1'd0;
			tile_row_screen_y_q <= 9'd0;
			tile_row_source_y_q <= 17'sd0;
			maps_wide_q <= 4'd1;
			maps_high_q <= 4'd1;
			effective_map_columns_q <= 4'd1;
			bgmap_base_rounded_q <= 4'd0;
			over_q <= 1'b0;
			overplane_q <= 16'd0;
			dram_pending_q <= 1'b0;
			dram_stale_q <= 1'b0;
			dram_capture_valid_q <= 1'b0;
			dram_capture_data_q <= 16'd0;
			dram_tile_load_q <= 1'd0;
			dram_tile_ordinal_q <= 13'd0;
			dram_tile_x_q <= 16'sd0;
			dram_overplane_selected_q <= 1'b0;
			dram_strict_overplane_q <= 1'b0;
			cell_valid_q <= 1'b0;
			cell_q <= 16'd0;
			cell_load_q <= 1'd0;
			cell_tile_ordinal_q <= 13'd0;
			cell_tile_x_q <= 16'sd0;
			cell_overplane_selected_q <= 1'b0;
			cell_strict_overplane_q <= 1'b0;
			vrm_pending_q <= 1'b0;
			vrm_stale_q <= 1'b0;
			vrm_capture_valid_q <= 1'b0;
			vrm_capture_data_q <= 16'd0;
			vrm_row_load_q <= 1'd0;
			vrm_row_tile_ordinal_q <= 13'd0;
			vrm_row_ordinal_q <= 3'd0;
			vrm_row_tile_x_q <= 16'sd0;
			vrm_row_screen_y_q <= 9'd0;
			vrm_row_source_y_q <= 17'sd0;
			vrm_row_source_index_q <= 3'd0;
			vrm_tile_row_screen_y_q <= 9'd0;
			vrm_tile_row_source_y_q <= 17'sd0;
			vrm_row_cell_q <= 16'd0;
			vrm_row_palette_q <= 2'd0;
			vrm_row_hflip_q <= 1'b0;
			vrm_row_vflip_q <= 1'b0;
			vrm_row_overplane_selected_q <= 1'b0;
			vrm_row_strict_overplane_q <= 1'b0;
			dram_stale_response_discarded_o <= 1'b0;
			vrm_stale_response_discarded_o <= 1'b0;
			unexpected_dram_response_o <= 1'b0;
			unexpected_vrm_response_o <= 1'b0;
			response_capture_overflow_o <= 1'b0;
			scheduler_tag_mismatch_o <= 1'b0;
			concurrent_work_error_o <= 1'b0;
			strict_overplane_seen_o <= 1'b0;
			map_index_overflow_seen_o <= 1'b0;
		end else begin
			dram_stale_response_discarded_o <= 1'b0;
			vrm_stale_response_discarded_o <= 1'b0;

			// A stale discard retires the matching local read owner.
			if (dram_router_stale_discard_i) begin
				dram_pending_q <= 1'b0;
				dram_stale_q <= 1'b0;
				dram_capture_valid_q <= 1'b0;
				dram_stale_response_discarded_o <= 1'b1;
			end
			if (vrm_router_stale_discard_i) begin
				vrm_pending_q <= 1'b0;
				vrm_stale_q <= 1'b0;
				vrm_capture_valid_q <= 1'b0;
				vrm_stale_response_discarded_o <= 1'b1;
			end

			if (tile_row_valid_i && (tile_valid_i || row_valid_i)) begin
				concurrent_work_error_o <= 1'b1;
			end
			if (tile_valid_i && row_valid_i) begin
				concurrent_work_error_o <= 1'b1;
			end
			if (tile_valid_i && !tile_context_match_w) begin
				scheduler_tag_mismatch_o <= 1'b1;
			end
			if (row_valid_i && !cell_context_match_w) begin
				scheduler_tag_mismatch_o <= 1'b1;
			end
			if (dram_pending_q && dram_response_available_w &&
				!dram_stale_active_w && !dram_response_tag_match_w) begin
				scheduler_tag_mismatch_o <= 1'b1;
			end
			if (vrm_pending_q && vrm_response_available_w &&
				!vrm_stale_active_w && !vrm_response_tag_match_w) begin
				scheduler_tag_mismatch_o <= 1'b1;
			end

			// Capture one-clock responses that CE cannot consume immediately.
			if (dram_resp_valid_i) begin
				if (!dram_pending_q) begin
					unexpected_dram_response_o <= 1'b1;
				end else if (dram_capture_valid_q) begin
					response_capture_overflow_o <= 1'b1;
				end else if (!dram_live_retire_w &&
					!dram_stale_drain_w) begin
					dram_capture_valid_q <= 1'b1;
					dram_capture_data_q <= dram_resp_data_i;
				end
			end
			if (vrm_resp_valid_i) begin
				if (!vrm_pending_q) begin
					unexpected_vrm_response_o <= 1'b1;
				end else if (vrm_capture_valid_q) begin
					response_capture_overflow_o <= 1'b1;
				end else if (!row_result_fire_w &&
					!vrm_stale_drain_w) begin
					vrm_capture_valid_q <= 1'b1;
					vrm_capture_data_q <= vrm_resp_data_i;
				end
			end

			// Raw abort drops context but keeps tags needed to drain reads.
			if (abort_i) begin
				tile_row_context_valid_q <= 1'b0;
				cell_valid_q <= 1'b0;
				if (dram_pending_q) begin
					dram_stale_q <= 1'b1;
				end
				if (vrm_pending_q) begin
					vrm_stale_q <= 1'b1;
				end
			end

			if (ce_i) begin
				if (dram_stale_drain_w) begin
					dram_pending_q <= 1'b0;
					dram_stale_q <= 1'b0;
					dram_capture_valid_q <= 1'b0;
					dram_stale_response_discarded_o <= 1'b1;
				end else if (dram_live_retire_w) begin
					dram_pending_q <= 1'b0;
					dram_stale_q <= 1'b0;
					dram_capture_valid_q <= 1'b0;
					cell_valid_q <= 1'b1;
					cell_q <= dram_response_data_w;
					cell_load_q <= dram_tile_load_q;
					cell_tile_ordinal_q <= dram_tile_ordinal_q;
					cell_tile_x_q <= dram_tile_x_q;
					cell_overplane_selected_q <=
						dram_overplane_selected_q;
					cell_strict_overplane_q <=
						dram_strict_overplane_q;
				end

				if (vrm_stale_drain_w) begin
					vrm_pending_q <= 1'b0;
					vrm_stale_q <= 1'b0;
					vrm_capture_valid_q <= 1'b0;
					vrm_stale_response_discarded_o <= 1'b1;
				end else if (row_result_fire_w) begin
					vrm_pending_q <= 1'b0;
					vrm_stale_q <= 1'b0;
					vrm_capture_valid_q <= 1'b0;
				end

				if (!abort_i) begin
					if (tile_row_fire_w) begin
						tile_row_context_valid_q <= 1'b1;
						tile_row_load_q <= tile_row_load_i;
						tile_row_screen_y_q <= tile_row_screen_y_i;
						tile_row_source_y_q <= tile_row_source_y_i;
						maps_wide_q <= maps_wide_i;
						maps_high_q <= maps_high_i;
						effective_map_columns_q <=
							effective_map_columns_i;
						bgmap_base_rounded_q <=
							bgmap_base_rounded_i;
						over_q <= over_i;
						overplane_q <= overplane_i;
					end

					if (dram_accept_fire_w) begin
						dram_pending_q <= 1'b1;
						dram_stale_q <= 1'b0;
						dram_tile_load_q <= tile_load_i;
						dram_tile_ordinal_q <= tile_ordinal_i;
						dram_tile_x_q <= tile_x_i;
						dram_overplane_selected_q <=
							address_overplane_selected_w;
						dram_strict_overplane_q <=
							address_strict_overplane_w;
						cell_valid_q <= 1'b0;
						if (address_strict_overplane_w) begin
							strict_overplane_seen_o <= 1'b1;
						end
						if (address_map_index_overflow_w) begin
							map_index_overflow_seen_o <= 1'b1;
						end
					end

					if (vrm_accept_fire_w) begin
						vrm_pending_q <= 1'b1;
						vrm_stale_q <= 1'b0;
						vrm_row_load_q <= row_load_i;
						vrm_row_tile_ordinal_q <=
							row_tile_ordinal_i;
						vrm_row_ordinal_q <= row_ordinal_i;
						vrm_row_tile_x_q <= cell_tile_x_q;
						vrm_row_screen_y_q <= row_screen_y_i;
						vrm_row_source_y_q <= row_source_y_i;
						vrm_row_source_index_q <=
							row_source_index_i;
						vrm_tile_row_screen_y_q <=
							tile_row_screen_y_q;
						vrm_tile_row_source_y_q <=
							tile_row_source_y_q;
						vrm_row_cell_q <= cell_q;
						vrm_row_palette_q <= address_palette_w;
						vrm_row_hflip_q <= address_hflip_w;
						vrm_row_vflip_q <= address_vflip_w;
						vrm_row_overplane_selected_q <=
							cell_overplane_selected_q;
						vrm_row_strict_overplane_q <=
							cell_strict_overplane_q;
					end
				end
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Shared combinational character and GPLT decoder.
//
// Decode eight pixels in parallel, apply HFLIP and GPLT, and keep raw zero
// transparent. Normal, H-bias, Affine, and Object share this logic.

module vip_xp_bg_character_decode
(
	input  wire [15:0] character_row_i,
	input  wire [1:0]  palette_i,
	input  wire        hflip_i,
	input  wire [2:0]  selected_index_i,
	// Raw zero is transparent, so GPLT entry zero is unused.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [31:0] gplt_active_i,
	/* verilator lint_on UNUSEDSIGNAL */

	output reg  [15:0] raw_pixels_o,
	output reg  [7:0]  raw_nonzero_o,
	output reg  [15:0] mapped_pixels_o,
	output reg  [1:0]  selected_raw_pixel_o,
	output reg         selected_raw_nonzero_o,
	output reg  [1:0]  selected_mapped_pixel_o
);

	reg [5:0] palette_nonzero_data_t;
	reg [1:0] raw_pixel_t;
	integer pixel_t;

	always @* begin
		case (palette_i)
			2'd0: palette_nonzero_data_t = gplt_active_i[7:2];
			2'd1: palette_nonzero_data_t = gplt_active_i[15:10];
			2'd2: palette_nonzero_data_t = gplt_active_i[23:18];
			default: palette_nonzero_data_t = gplt_active_i[31:26];
		endcase

		if (hflip_i) begin
			raw_pixels_o = {
				character_row_i[1:0],
				character_row_i[3:2],
				character_row_i[5:4],
				character_row_i[7:6],
				character_row_i[9:8],
				character_row_i[11:10],
				character_row_i[13:12],
				character_row_i[15:14]
			};
		end else begin
			raw_pixels_o = character_row_i;
		end

		raw_nonzero_o = 8'd0;
		mapped_pixels_o = 16'd0;
		raw_pixel_t = 2'd0;
		for (pixel_t = 0; pixel_t < 8; pixel_t = pixel_t + 1) begin
			raw_pixel_t =
				raw_pixels_o[{pixel_t[2:0], 1'b0} +: 2];
			raw_nonzero_o[pixel_t] = raw_pixel_t != 2'd0;
			case (raw_pixel_t)
				2'd0: mapped_pixels_o[
					{pixel_t[2:0], 1'b0} +: 2] = 2'd0;
				2'd1: mapped_pixels_o[
					{pixel_t[2:0], 1'b0} +: 2] =
					palette_nonzero_data_t[1:0];
				2'd2: mapped_pixels_o[
					{pixel_t[2:0], 1'b0} +: 2] =
					palette_nonzero_data_t[3:2];
				default: mapped_pixels_o[
					{pixel_t[2:0], 1'b0} +: 2] =
					palette_nonzero_data_t[5:4];
			endcase
		end
	end

	always @* begin
		selected_raw_pixel_o = 2'd0;
		selected_raw_nonzero_o = 1'b0;
		selected_mapped_pixel_o = 2'd0;
		case (selected_index_i)
			3'd0: begin
				selected_raw_pixel_o = raw_pixels_o[1:0];
				selected_raw_nonzero_o = raw_nonzero_o[0];
				selected_mapped_pixel_o = mapped_pixels_o[1:0];
			end
			3'd1: begin
				selected_raw_pixel_o = raw_pixels_o[3:2];
				selected_raw_nonzero_o = raw_nonzero_o[1];
				selected_mapped_pixel_o = mapped_pixels_o[3:2];
			end
			3'd2: begin
				selected_raw_pixel_o = raw_pixels_o[5:4];
				selected_raw_nonzero_o = raw_nonzero_o[2];
				selected_mapped_pixel_o = mapped_pixels_o[5:4];
			end
			3'd3: begin
				selected_raw_pixel_o = raw_pixels_o[7:6];
				selected_raw_nonzero_o = raw_nonzero_o[3];
				selected_mapped_pixel_o = mapped_pixels_o[7:6];
			end
			3'd4: begin
				selected_raw_pixel_o = raw_pixels_o[9:8];
				selected_raw_nonzero_o = raw_nonzero_o[4];
				selected_mapped_pixel_o = mapped_pixels_o[9:8];
			end
			3'd5: begin
				selected_raw_pixel_o = raw_pixels_o[11:10];
				selected_raw_nonzero_o = raw_nonzero_o[5];
				selected_mapped_pixel_o = mapped_pixels_o[11:10];
			end
			3'd6: begin
				selected_raw_pixel_o = raw_pixels_o[13:12];
				selected_raw_nonzero_o = raw_nonzero_o[6];
				selected_mapped_pixel_o = mapped_pixels_o[13:12];
			end
			default: begin
				selected_raw_pixel_o = raw_pixels_o[15:14];
				selected_raw_nonzero_o = raw_nonzero_o[7];
				selected_mapped_pixel_o = mapped_pixels_o[15:14];
			end
		endcase
	end

endmodule

`timescale 1ns/1ps

// Registered background row blend.
//
// Blend one decoded eight-pixel row into both eyes. Active masks clip the
// destination; opaque masks handle transparent source pixels.

module vip_xp_bg_row_blend_core
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	input  wire                 input_valid_i,
	output wire                 input_ready_o,
	input  wire signed [17:0]   tile_x_i,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [8:0]           screen_y_i,
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire [7:0]           decoded_raw_nonzero_i,
	input  wire [15:0]          decoded_mapped_pixels_i,

	input  wire                 left_on_i,
	input  wire                 right_on_i,
	input  wire signed [17:0]   left_source_start_i,
	input  wire signed [17:0]   right_source_start_i,
	input  wire signed [17:0]   left_destination_start_i,
	input  wire signed [17:0]   right_destination_start_i,
	input  wire [12:0]          semantic_width_i,

	output wire                 output_valid_o,
	input  wire                 output_ready_i,
	output reg  [2:0]           output_row_o,
	output reg  signed [15:0]   output_left_base_x_o,
	output reg  signed [15:0]   output_right_base_x_o,
	output reg                  output_left_enable_o,
	output reg                  output_right_enable_o,
	output reg  [7:0]           output_left_active_o,
	output reg  [7:0]           output_right_active_o,
	output reg  [7:0]           output_left_opaque_o,
	output reg  [7:0]           output_right_opaque_o,
	output reg  [15:0]          output_left_values_o,
	output reg  [15:0]          output_right_values_o,

`ifndef SYNTHESIS
	output reg  [31:0]          diag_input_accept_count_o,
	output reg  [31:0]          diag_output_accept_count_o
`else
	output wire [31:0]          diag_input_accept_count_o,
	output wire [31:0]          diag_output_accept_count_o
`endif
);

	reg output_valid_q;

	reg signed [17:0] width_ext_t;
	reg signed [17:0] left_source_end_t;
	reg signed [17:0] right_source_end_t;
	reg signed [17:0] left_base_t;
	reg signed [17:0] right_base_t;
	reg signed [17:0] source_pixel_t;
	reg signed [17:0] left_destination_pixel_t;
	reg signed [17:0] right_destination_pixel_t;
	reg [7:0] left_active_t;
	reg [7:0] right_active_t;
	integer pixel_t;

	wire input_fire_w = ce_i && input_valid_i && input_ready_o;
	wire output_fire_w = ce_i && output_valid_o && output_ready_i;

	assign input_ready_o = ce_i && !reset_i && !abort_i &&
		(!output_valid_q || output_ready_i);
	// Abort removes valid immediately and clears the token on the raw edge.
	assign output_valid_o = output_valid_q && !reset_i && !abort_i;

`ifdef SYNTHESIS
	assign diag_input_accept_count_o = 32'd0;
	assign diag_output_accept_count_o = 32'd0;
`endif

	// Any active destination base lies from -7 through 383 and fits in 16 bits.
	always @* begin
		width_ext_t = $signed({5'd0, semantic_width_i});
		left_source_end_t = left_source_start_i + width_ext_t;
		right_source_end_t = right_source_start_i + width_ext_t;
		left_base_t = left_destination_start_i + tile_x_i -
			left_source_start_i;
		right_base_t = right_destination_start_i + tile_x_i -
			right_source_start_i;

		left_active_t = 8'd0;
		right_active_t = 8'd0;

		for (pixel_t = 0; pixel_t < 8; pixel_t = pixel_t + 1) begin
			source_pixel_t = tile_x_i +
				$signed({15'd0, pixel_t[2:0]});
			left_destination_pixel_t = left_base_t +
				$signed({15'd0, pixel_t[2:0]});
			right_destination_pixel_t = right_base_t +
				$signed({15'd0, pixel_t[2:0]});

			left_active_t[pixel_t] =
				(source_pixel_t >= left_source_start_i) &&
				(source_pixel_t < left_source_end_t) &&
				(left_destination_pixel_t >= 18'sd0) &&
				(left_destination_pixel_t < 18'sd384);
			right_active_t[pixel_t] =
				(source_pixel_t >= right_source_start_i) &&
				(source_pixel_t < right_source_end_t) &&
				(right_destination_pixel_t >= 18'sd0) &&
				(right_destination_pixel_t < 18'sd384);
		end
	end

	always @(posedge clk_i) begin
		if (reset_i) begin
			output_valid_q <= 1'b0;
			output_row_o <= 3'd0;
			output_left_base_x_o <= 16'sd0;
			output_right_base_x_o <= 16'sd0;
			output_left_enable_o <= 1'b0;
			output_right_enable_o <= 1'b0;
			output_left_active_o <= 8'd0;
			output_right_active_o <= 8'd0;
			output_left_opaque_o <= 8'd0;
			output_right_opaque_o <= 8'd0;
			output_left_values_o <= 16'd0;
			output_right_values_o <= 16'd0;
`ifndef SYNTHESIS
			diag_input_accept_count_o <= 32'd0;
			diag_output_accept_count_o <= 32'd0;
`endif
		end else if (abort_i) begin
			output_valid_q <= 1'b0;
		end else if (ce_i) begin
			if (input_fire_w) begin
				output_valid_q <= 1'b1;
				output_row_o <= screen_y_i[2:0];
				output_left_base_x_o <= left_base_t[15:0];
				output_right_base_x_o <= right_base_t[15:0];
				output_left_enable_o <= left_on_i;
				output_right_enable_o <= right_on_i;
				output_left_active_o <= left_active_t;
				output_right_active_o <= right_active_t;
				output_left_opaque_o <= decoded_raw_nonzero_i;
				output_right_opaque_o <= decoded_raw_nonzero_i;
				output_left_values_o <= decoded_mapped_pixels_i;
				output_right_values_o <= decoded_mapped_pixels_i;
`ifndef SYNTHESIS
				diag_input_accept_count_o <=
					diag_input_accept_count_o + 32'd1;
`endif
			end else if (output_fire_w) begin
				output_valid_q <= 1'b0;
			end

			if (output_fire_w) begin
`ifndef SYNTHESIS
				diag_output_accept_count_o <=
					diag_output_accept_count_o + 32'd1;
`endif
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Strip-local Object group and control snapshot.
//
// Reset the ordinal each strip. Each accepted, non-dummy Object command uses one group.
//
// Silicon unknown: mid-draw write visibility is unmeasured. Snapshot SPT and
// JPLT at command acceptance; OAM and character data remain live reads.

module vip_xp_obj_group_tracker
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	input  wire                 root_accept_i,
	input  wire [4:0]           root_strip_i,
	input  wire [1:0]           root_kind_i,
	input  wire                 root_dummy_i,
	input  wire [39:0]          spt_active_i,
	input  wire [31:0]          jplt_active_i,

	// An empty context slot passes a new command through on the same edge.
	output wire                 preview_valid_o,
	output wire [4:0]           preview_strip_o,
	output wire [1:0]           preview_group_o,
	output wire [5:0]           preview_ordinal_o,
	output wire                 preview_penalty_class_o,
	output wire [39:0]          preview_spt_o,
	output wire [31:0]          preview_jplt_o,
	output wire [9:0]           preview_inclusive_end_o,
	output wire [9:0]           preview_inclusive_start_o,
	output wire [10:0]          preview_entry_count_o,
	output wire                 preview_full_range_o,

	output wire                 context_valid_o,
	input  wire                 context_ready_i,
	output reg  [4:0]           context_strip_o,
	output reg  [1:0]           context_group_o,
	output reg  [5:0]           context_ordinal_o,
	output reg                  context_penalty_class_o,
	output reg  [39:0]          context_spt_o,
	output reg  [31:0]          context_jplt_o,
	output reg  [9:0]           context_inclusive_end_o,
	output reg  [9:0]           context_inclusive_start_o,
	output reg  [10:0]          context_entry_count_o,
	output reg                  context_full_range_o,

	output reg                  context_overrun_o
);

	reg context_valid_q;
	reg strip_valid_q;
	reg [4:0] strip_q;
	reg [1:0] next_group_q;
	reg [5:0] next_ordinal_q;

	wire root_is_active_object_w =
		(root_kind_i == 2'd3) && !root_dummy_i;
	wire context_slot_available_w =
		!context_valid_q || context_ready_i;
	wire strip_change_w = !strip_valid_q ||
		(root_strip_i != strip_q);
	wire [1:0] selected_group_w = strip_change_w ?
		2'd3 : next_group_q;
	wire [5:0] selected_ordinal_w = strip_change_w ?
		6'd0 : next_ordinal_q;
	wire selected_penalty_class_w =
		(selected_ordinal_w != 6'd0) &&
		(selected_ordinal_w[1:0] == 2'b00);

	wire [9:0] spt0_w = spt_active_i[9:0];
	wire [9:0] spt1_w = spt_active_i[19:10];
	wire [9:0] spt2_w = spt_active_i[29:20];
	wire [9:0] spt3_w = spt_active_i[39:30];

	// Ten-bit addition wraps 1023 to zero.
	wire [9:0] spt0_plus_one_w = spt0_w + 10'd1;
	wire [9:0] spt1_plus_one_w = spt1_w + 10'd1;
	wire [9:0] spt2_plus_one_w = spt2_w + 10'd1;

	wire [9:0] selected_end_w =
		(selected_group_w == 2'd3) ? spt3_w :
		((selected_group_w == 2'd2) ? spt2_w :
		 ((selected_group_w == 2'd1) ? spt1_w : spt0_w));
	wire [9:0] selected_start_w =
		(selected_group_w == 2'd3) ? spt2_plus_one_w :
		((selected_group_w == 2'd2) ? spt1_plus_one_w :
		 ((selected_group_w == 2'd1) ? spt0_plus_one_w :
		  10'd0));

	// Ten-bit subtraction gives cyclic inclusive distances from 1 to 1024.
	wire [9:0] selected_span_w =
		selected_end_w - selected_start_w;
	wire [10:0] selected_entry_count_w =
		{1'b0, selected_span_w} + 11'd1;
	wire selected_full_range_w = selected_entry_count_w[10];

	wire [1:0] group_after_accept_w =
		(selected_group_w == 2'd3) ? 2'd2 :
		((selected_group_w == 2'd2) ? 2'd1 :
		 ((selected_group_w == 2'd1) ? 2'd0 : 2'd3));
	wire [5:0] ordinal_after_accept_w =
		selected_ordinal_w + 6'd1;

	assign preview_valid_o = !reset_i && !abort_i &&
		!context_valid_q && root_is_active_object_w;
	assign preview_strip_o = root_strip_i;
	assign preview_group_o = selected_group_w;
	assign preview_ordinal_o = selected_ordinal_w;
	assign preview_penalty_class_o = selected_penalty_class_w;
	assign preview_spt_o = spt_active_i;
	assign preview_jplt_o = jplt_active_i;
	assign preview_inclusive_end_o = selected_end_w;
	assign preview_inclusive_start_o = selected_start_w;
	assign preview_entry_count_o = selected_entry_count_w;
	assign preview_full_range_o = selected_full_range_w;

	assign context_valid_o = !reset_i && !abort_i && context_valid_q;

	always @(posedge clk_i) begin
		if (reset_i) begin
			context_valid_q <= 1'b0;
			strip_valid_q <= 1'b0;
			strip_q <= 5'd0;
			next_group_q <= 2'd3;
			next_ordinal_q <= 6'd0;
			context_strip_o <= 5'd0;
			context_group_o <= 2'd3;
			context_ordinal_o <= 6'd0;
			context_penalty_class_o <= 1'b0;
			context_spt_o <= 40'd0;
			context_jplt_o <= 32'd0;
			context_inclusive_end_o <= 10'd0;
			context_inclusive_start_o <= 10'd0;
			context_entry_count_o <= 11'd0;
			context_full_range_o <= 1'b0;
			context_overrun_o <= 1'b0;
		end else if (abort_i) begin
			context_valid_q <= 1'b0;
			strip_valid_q <= 1'b0;
			strip_q <= 5'd0;
			next_group_q <= 2'd3;
			next_ordinal_q <= 6'd0;
			context_overrun_o <= 1'b0;
		end else if (ce_i) begin
			if (context_valid_q && context_ready_i) begin
				context_valid_q <= 1'b0;
			end

			if (root_accept_i) begin
				if (root_is_active_object_w &&
					context_slot_available_w) begin
					// Pass through an empty slot, or replace a context consumed this edge.
					context_valid_q <= context_valid_q ||
						!context_ready_i;
					context_strip_o <= root_strip_i;
					context_group_o <= selected_group_w;
					context_ordinal_o <= selected_ordinal_w;
					context_penalty_class_o <=
						selected_penalty_class_w;
					context_spt_o <= spt_active_i;
					context_jplt_o <= jplt_active_i;
					context_inclusive_end_o <= selected_end_w;
					context_inclusive_start_o <=
						selected_start_w;
					context_entry_count_o <=
						selected_entry_count_w;
					context_full_range_o <=
						selected_full_range_w;

					strip_valid_q <= 1'b1;
					strip_q <= root_strip_i;
					next_group_q <= group_after_accept_w;
					next_ordinal_q <= ordinal_after_accept_w;
				end else if (root_is_active_object_w) begin
					context_overrun_o <= 1'b1;
				end else if (strip_change_w) begin
					strip_valid_q <= 1'b1;
					strip_q <= root_strip_i;
					next_group_q <= 2'd3;
					next_ordinal_q <= 6'd0;
				end
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Object group and strip renderer.
//
// The scheduler owns timing. The walker reads OAM, launches character work, and
// retires row tokens through the shared store and decoder.

module vip_xp_obj_engine
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
	output wire                 start_accept_o,
	input  wire [4:0]           world_i,
	input  wire [4:0]           strip_i,
	input  wire                 first_visit_i,
	input  wire [3:0]           epoch_i,
	input  wire [9:0]           first_index_i,
	input  wire [9:0]           final_index_i,
	input  wire [10:0]          entry_count_i,
	input  wire                 penalty_i,
	input  wire [2:0]           parallax_scale_i,
	input  wire [31:0]          jplt_active_i,

	output wire                 busy_o,
	output wire                 done_o,
	input  wire                 done_ready_i,
	output wire                 cleanup_busy_o,
	output wire                 quiescent_o,
	output wire                 command_active_o,
	output wire                 transport_idle_o,
	output wire                 completion_will_idle_o,
	output wire                 underflow_unresolved_o,
	output reg                  jy_unresolved_o,
	output reg                  ignored_oam_bits_nonzero_o,

	output wire                 oam_dram_req_o,
	output wire [15:0]          oam_dram_addr_o,
	input  wire                 oam_dram_accept_i,
	input  wire                 oam_dram_resp_valid_i,
	input  wire [15:0]          oam_dram_resp_data_i,
	input  wire                 oam_router_cleanup_busy_i,
	input  wire                 oam_router_stale_discard_i,
	output wire                 oam_stale_retire_o,

	output wire                 char_vrm_req_o,
	output wire                 char_vrm_write_o,
	output wire [15:0]          char_vrm_addr_o,
	input  wire                 char_vrm_accept_i,
	input  wire                 char_vrm_resp_valid_i,
	input  wire [15:0]          char_vrm_resp_data_i,
	input  wire                 char_router_cleanup_busy_i,
	input  wire                 char_router_stale_discard_i,
	output wire                 char_stale_retire_o,

	output wire                 decode_query_valid_o,
	output wire                 decode_query_ready_o,
	input  wire                 decode_grant_i,
	input  wire                 decode_conflict_i,
	output wire                 decode_accept_o,
	output wire [15:0]          decode_character_row_o,
	output wire [1:0]           decode_palette_o,
	output wire                 decode_hflip_o,
	output wire [31:0]          decode_jplt_active_o,
	input  wire [7:0]           decoded_raw_nonzero_i,
	input  wire [15:0]          decoded_mapped_pixels_i,

	output wire                 token_valid_o,
	input  wire                 token_ready_i,
	output wire                 token_accept_o,
	input  wire                 token_done_i,
	output wire [3:0]           token_epoch_o,
	output wire [9:0]           token_object_index_o,
	output wire [8:0]           token_screen_y_o,
	output wire [2:0]           token_source_row_o,
	output wire [2:0]           token_row_o,
	output wire signed [15:0]   token_left_base_x_o,
	output wire                 token_left_enable_o,
	output wire [7:0]           token_left_active_o,
	output wire [7:0]           token_left_opaque_o,
	output wire [15:0]          token_left_values_o,
	output wire signed [15:0]   token_right_base_x_o,
	output wire                 token_right_enable_o,
	output wire [7:0]           token_right_active_o,
	output wire [7:0]           token_right_opaque_o,
	output wire [15:0]          token_right_values_o,
	output wire [2:0]           token_character_effective_row_o,
	output wire [15:0]          token_character_row_addr_o,

	output wire [2:0]           scheduler_state_o,
	output wire [10:0]          scheduler_ticks_remaining_o,
	output wire [31:0]          scheduler_elapsed_ticks_o,
	output wire [15:0]          scheduler_fixed_ticks_o,
	output wire [31:0]          scheduler_probe_ticks_o,
	output wire [31:0]          scheduler_active_setup_ticks_o,
	output wire [31:0]          scheduler_continuation_ticks_o,
	output wire [31:0]          scheduler_row_ticks_o,
	output wire [31:0]          scheduler_underflow_ticks_o,
	output wire [31:0]          scheduler_transport_stall_ticks_o,
	output wire [31:0]          diag_oam_read_accept_count_o,
	output wire [31:0]          diag_char_context_accept_count_o,
	output wire [31:0]          diag_char_read_accept_count_o,
	output wire [31:0]          diag_token_accept_count_o,
	output wire [31:0]          diag_token_done_count_o,
	output reg                  class_tag_error_o,
	output reg                  record_tag_error_o,
	output reg                  char_tag_error_o,
	output reg                  row_tag_error_o,
	output reg                  token_owner_overflow_o,
	output reg                  token_owner_underflow_o,
	output reg                  outer_stale_error_o,
	output wire                 protocol_error_o
);

	// Mirrors of the vip_xp_obj_scheduler state encoding, used to observe
	// its scheduler_state_o; the two lists must stay in step.
	localparam [2:0]
		STATE_ACTIVE_SETUP = 3'd4,
		STATE_CONTINUATION = 3'd5;

	reg command_active_q;
	reg [4:0] command_strip_q;
	reg [3:0] command_epoch_q;
	reg [9:0] command_final_index_q;
	reg [31:0] command_jplt_q;
	reg [9:0] expected_class_index_q;

	reg active_class_valid_q;
	reg [9:0] active_index_q;
	reg [4:0] active_strip_q;
	reg [3:0] active_epoch_q;
	reg active_final_q;
	reg active_continuation_q;
	reg [3:0] active_visible_rows_q;
	reg [8:0] active_first_screen_y_q;
	reg [2:0] active_first_source_row_q;
	reg detail_started_q;
	reg first_token_issued_q;

	// Hold Object walk geometry until all rows enter the character pipeline.
	reg record_sidecar_valid_q;
	reg [9:0] record_index_q;
	reg [3:0] record_epoch_q;
	reg [3:0] record_visible_rows_q;
	reg [8:0] record_first_screen_y_q;
	reg [2:0] record_first_source_row_q;
	reg [3:0] context_ordinal_q;

	// Two owner slots match the row mux replacement depth. Tag order is
	// {epoch,index,screen_y,source_row,row}.
	reg [28:0] token_owner_slot0_q;
	reg [28:0] token_owner_slot1_q;
	reg token_owner_presented0_q;
	reg token_owner_presented1_q;
	reg token_owner_head_q;
	reg token_owner_tail_q;
	reg [1:0] token_owner_count_q;

	wire scheduler_start_ready_w;
	wire scheduler_start_valid_w;
	wire scheduler_busy_w;
	wire scheduler_done_w;
	wire scheduler_cleanup_busy_w;
	wire scheduler_underflow_unresolved_w;
	wire scheduler_class_ready_w;
	wire scheduler_active_setup_valid_w;
	wire scheduler_active_setup_ready_w;
	wire scheduler_row_valid_w;
	wire scheduler_row_ready_w;
	wire [3:0] scheduler_row_ordinal_w;
	wire scheduler_row_last_w;
	wire scheduler_row_final_w;
	wire scheduler_invalid_classification_w;
	wire scheduler_object_ordinal_overflow_w;

	wire walker_start_ready_w;
	wire walker_start_valid_w;
	wire walker_class_valid_w;
	wire walker_class_ready_w;
	wire [9:0] walker_class_index_w;
	wire [4:0] walker_class_strip_w;
	wire [3:0] walker_class_epoch_w;
	wire walker_class_final_w;
	wire walker_class_appears_w;
	wire walker_class_continuation_w;
	wire [3:0] walker_class_visible_rows_w;
	wire [8:0] walker_class_first_screen_y_w;
	wire [2:0] walker_class_first_source_row_w;
	wire walker_class_unresolved_jy_w;
	wire walker_detail_start_valid_w;
	wire walker_detail_start_accept_w;
	wire walker_record_valid_w;
	wire walker_record_ready_w;
	wire [63:0] walker_record_data_w;
	wire signed [9:0] walker_record_jp_w = walker_record_data_w[25:16];
	wire signed [9:0] walker_record_jp_scaled_w;
	wire [63:0] walker_record_scaled_data_w =
		{walker_record_data_w[63:26], walker_record_jp_scaled_w,
		 walker_record_data_w[15:0]};
	wire [9:0] walker_record_index_w;
	wire [4:0] walker_record_strip_w;
	wire [3:0] walker_record_epoch_w;
	wire walker_record_final_w;
	wire walker_record_continuation_w;
	wire [3:0] walker_record_visible_rows_w;
	wire [8:0] walker_record_first_screen_y_w;
	wire [2:0] walker_record_first_source_row_w;
	wire walker_record_unresolved_jy_w;
	wire walker_busy_w;
	wire walker_cleanup_busy_w;
	wire walker_terminal_will_idle_w;
	wire walker_transport_pending_w;
	wire walker_stale_discard_w;

	vip_stereo_scale_signed #(.WIDTH(10)) u_object_jp_scale
	(
		.value_i(walker_record_jp_w),
		.scale_i(parallax_scale_i),
		.value_o(walker_record_jp_scaled_w)
	);
	wire walker_protocol_error_w;

	wire decoder_descriptor_ready_w;
	wire decoder_descriptor_accept_w;
	wire decoder_record_valid_w;
	wire decoder_record_ready_w;
	wire decoder_jlon_w;
	wire decoder_jron_w;
	wire [1:0] decoder_jplt_select_w;
	wire decoder_hflip_w;
	wire decoder_vflip_w;
	wire [10:0] decoder_jca_w;
	wire signed [11:0] decoder_left_base_w;
	wire signed [11:0] decoder_right_base_w;
	wire decoder_jy_unresolved_w;
	wire decoder_ignored_bits_w;

	wire char_context_valid_w;
	wire char_context_accept_w;
	wire char_token_valid_w;
	wire char_token_ready_w;
	wire char_token_accept_w;
	wire [3:0] char_token_epoch_w;
	wire [9:0] char_token_index_w;
	wire [8:0] char_token_screen_y_w;
	wire [2:0] char_token_source_row_w;
	wire [2:0] char_token_row_w;
	wire signed [15:0] char_token_left_base_w;
	wire char_token_left_enable_w;
	wire [7:0] char_token_left_active_w;
	wire [7:0] char_token_left_opaque_w;
	wire [15:0] char_token_left_values_w;
	wire signed [15:0] char_token_right_base_w;
	wire char_token_right_enable_w;
	wire [7:0] char_token_right_active_w;
	wire [7:0] char_token_right_opaque_w;
	wire [15:0] char_token_right_values_w;
	wire [2:0] char_character_effective_row_w;
	wire [15:0] char_character_row_addr_w;
	wire char_busy_w;
	wire char_cleanup_busy_w;
	wire char_read_pending_w;
	wire char_stale_discard_w;
	wire char_accept_without_request_w;
	wire char_unowned_response_w;
	wire char_response_capture_overflow_w;
	wire char_pending_owner_overlap_w;
	wire char_decode_conflict_w;

	wire class_tag_match_w = command_active_q &&
		(walker_class_index_w == expected_class_index_q) &&
		(walker_class_strip_w == command_strip_q) &&
		(walker_class_epoch_w == command_epoch_q) &&
		(walker_class_final_w ==
		 (expected_class_index_q == command_final_index_q));
	wire class_fire_w = ce_i && walker_class_valid_w &&
		walker_class_ready_w;

	wire record_tag_match_w = active_class_valid_q &&
		(walker_record_index_w == active_index_q) &&
		(walker_record_strip_w == active_strip_q) &&
		(walker_record_epoch_w == active_epoch_q) &&
		(walker_record_final_w == active_final_q) &&
		(walker_record_continuation_w == active_continuation_q) &&
		(walker_record_visible_rows_w == active_visible_rows_q) &&
		(walker_record_first_screen_y_w == active_first_screen_y_q) &&
		(walker_record_first_source_row_w ==
		 active_first_source_row_q);

	wire [9:0] context_screen_sum_w =
		{1'b0, record_first_screen_y_q} + {6'd0, context_ordinal_q};
	wire [3:0] context_source_sum_w =
		{1'b0, record_first_source_row_q} + context_ordinal_q;
	wire context_last_w =
		({1'b0, context_ordinal_q} + 5'd1) >=
		{1'b0, record_visible_rows_q};

	wire [4:0] current_row_ordinal_w =
		{1'b0, scheduler_row_ordinal_w};
	wire [9:0] current_screen_sum_w =
		{1'b0, active_first_screen_y_q} +
		{5'd0, current_row_ordinal_w};
	wire [4:0] current_source_sum_w =
		{2'd0, active_first_source_row_q} + current_row_ordinal_w;
	wire [4:0] next_row_ordinal_w = current_row_ordinal_w + 5'd1;
	wire [9:0] next_screen_sum_w =
		{1'b0, active_first_screen_y_q} +
		{5'd0, next_row_ordinal_w};
	wire [4:0] next_source_sum_w =
		{2'd0, active_first_source_row_q} + next_row_ordinal_w;

	wire [28:0] current_expected_tag_w = {
		active_epoch_q,
		active_index_q,
		current_screen_sum_w[8:0],
		current_source_sum_w[2:0],
		current_screen_sum_w[2:0]
	};
	wire [28:0] next_expected_tag_w = {
		active_epoch_q,
		active_index_q,
		next_screen_sum_w[8:0],
		next_source_sum_w[2:0],
		next_screen_sum_w[2:0]
	};
	wire [28:0] first_expected_tag_w = {
		active_epoch_q,
		active_index_q,
		active_first_screen_y_q,
		active_first_source_row_q,
		active_first_screen_y_q[2:0]
	};
	wire [28:0] char_token_tag_w = {
		char_token_epoch_w,
		char_token_index_w,
		char_token_screen_y_w,
		char_token_source_row_w,
		char_token_row_w
	};
	wire [28:0] token_owner_head_tag_w = token_owner_head_q ?
		token_owner_slot1_q : token_owner_slot0_q;
	wire token_owner_head_presented_w = token_owner_head_q ?
		token_owner_presented1_q : token_owner_presented0_q;
	wire token_owner_empty_w = token_owner_count_q == 2'd0;
	wire token_owner_full_w = token_owner_count_q == 2'd2;
	wire row_head_match_w = !token_owner_empty_w &&
		!current_screen_sum_w[9] &&
		(current_source_sum_w[4:3] == 2'd0) &&
		(token_owner_head_tag_w == current_expected_tag_w);
	wire first_char_tag_match_w = active_class_valid_q &&
		(char_token_tag_w == first_expected_tag_w);
	wire current_char_tag_match_w = active_class_valid_q &&
		(char_token_tag_w == current_expected_tag_w);
	wire next_char_tag_match_w = active_class_valid_q &&
		!next_screen_sum_w[9] &&
		(next_source_sum_w[4:3] == 2'd0) &&
		(char_token_tag_w == next_expected_tag_w);

	wire [9:0] char_screen_offset_w =
		{1'b0, char_token_screen_y_w} -
		{1'b0, active_first_screen_y_q};
	wire [3:0] char_source_offset_w =
		{1'b0, char_token_source_row_w} -
		{1'b0, active_first_source_row_q};
	wire char_tag_in_active_range_w = active_class_valid_q &&
		(char_token_epoch_w == active_epoch_q) &&
		(char_token_index_w == active_index_q) &&
		(char_token_screen_y_w >= active_first_screen_y_q) &&
		(char_token_source_row_w >= active_first_source_row_q) &&
		(char_screen_offset_w[9:4] == 6'd0) &&
		(char_screen_offset_w[3:0] == char_source_offset_w) &&
		(char_screen_offset_w[3:0] < active_visible_rows_q) &&
		(char_token_row_w == char_token_screen_y_w[2:0]);

	// Advance row timing only for a matching token completion.
	wire token_owner_pop_w = ce_i && !reset_i && !abort_i &&
		token_done_i && !token_owner_empty_w;
	wire qualified_row_done_w = token_owner_pop_w &&
		scheduler_row_valid_w && row_head_match_w &&
		token_owner_head_presented_w;
	wire observe_row_head_w = ce_i && scheduler_row_valid_w &&
		row_head_match_w;
	wire token_owner_slot_available_w = !token_owner_full_w ||
		token_owner_pop_w;

	wire setup_release_w =
		(scheduler_state_o == STATE_ACTIVE_SETUP) &&
		!active_continuation_q &&
		(scheduler_ticks_remaining_o <= 11'd2) &&
		!first_token_issued_q && token_owner_empty_w &&
		first_char_tag_match_w;
	wire continuation_release_w =
		(scheduler_state_o == STATE_CONTINUATION) &&
		(scheduler_ticks_remaining_o <= 11'd2) &&
		!first_token_issued_q && token_owner_empty_w &&
		first_char_tag_match_w;
	wire late_current_release_w = scheduler_row_valid_w &&
		token_owner_empty_w && current_char_tag_match_w;
	wire replacement_release_w = scheduler_row_valid_w &&
		(scheduler_ticks_remaining_o == 11'd2) &&
		row_head_match_w && !scheduler_row_last_w &&
		next_char_tag_match_w;
	wire token_release_w = !reset_i && !abort_i &&
		token_owner_slot_available_w && char_token_valid_w &&
		(setup_release_w || continuation_release_w ||
		 late_current_release_w || replacement_release_w);

	wire first_token_primed_w = char_token_valid_w &&
		first_char_tag_match_w;
	assign scheduler_active_setup_ready_w =
		active_class_valid_q && detail_started_q &&
		(active_continuation_q ? first_token_primed_w :
		 first_token_issued_q);
	assign scheduler_row_ready_w = qualified_row_done_w;

	assign walker_class_ready_w = scheduler_class_ready_w &&
		class_tag_match_w;
	assign walker_detail_start_valid_w =
		scheduler_active_setup_valid_w && active_class_valid_q &&
		!detail_started_q;
	assign walker_record_ready_w = decoder_descriptor_ready_w &&
		record_tag_match_w && !record_sidecar_valid_q;

	assign char_context_valid_w = decoder_record_valid_w &&
		record_sidecar_valid_q &&
		(context_ordinal_q < record_visible_rows_q) &&
		!context_source_sum_w[3] && !context_screen_sum_w[9];
	assign decoder_record_ready_w = char_context_accept_w &&
		context_last_w;

	assign token_valid_o = char_token_valid_w && token_release_w;
	assign char_token_ready_w = token_release_w && token_ready_i;
	assign token_accept_o = char_token_accept_w;
	assign token_epoch_o = char_token_epoch_w;
	assign token_object_index_o = char_token_index_w;
	assign token_screen_y_o = char_token_screen_y_w;
	assign token_source_row_o = char_token_source_row_w;
	assign token_row_o = char_token_row_w;
	assign token_left_base_x_o = char_token_left_base_w;
	assign token_left_enable_o = char_token_left_enable_w;
	assign token_left_active_o = char_token_left_active_w;
	assign token_left_opaque_o = char_token_left_opaque_w;
	assign token_left_values_o = char_token_left_values_w;
	assign token_right_base_x_o = char_token_right_base_w;
	assign token_right_enable_o = char_token_right_enable_w;
	assign token_right_active_o = char_token_right_active_w;
	assign token_right_opaque_o = char_token_right_opaque_w;
	assign token_right_values_o = char_token_right_values_w;
	assign token_character_effective_row_o =
		char_character_effective_row_w;
	assign token_character_row_addr_o = char_character_row_addr_w;

	// Route stale cleanup only to the leaf that owns the accepted read.
	wire oam_outer_stale_inject_w = oam_router_stale_discard_i &&
		walker_transport_pending_w;
	wire char_outer_stale_inject_w = char_router_stale_discard_i &&
		char_read_pending_w;
	wire oam_effective_resp_valid_w = oam_dram_resp_valid_i ||
		oam_outer_stale_inject_w;
	wire char_effective_resp_valid_w = char_vrm_resp_valid_i ||
		char_outer_stale_inject_w;
	wire [15:0] oam_effective_resp_data_w = oam_dram_resp_valid_i ?
		oam_dram_resp_data_i : 16'd0;
	wire [15:0] char_effective_resp_data_w = char_vrm_resp_valid_i ?
		char_vrm_resp_data_i : 16'd0;
	assign oam_stale_retire_o = walker_stale_discard_w;
	assign char_stale_retire_o = char_stale_discard_w;

	wire decoder_idle_w = !decoder_record_valid_w &&
		!record_sidecar_valid_q;
	wire outer_cleanup_idle_w = !oam_router_cleanup_busy_i &&
		!char_router_cleanup_busy_i;
	// Compute Object idle from retained state, even while abort hides public status.
	wire walker_state_idle_w = !walker_busy_w;
	wire char_state_idle_w = !char_busy_w;
	wire actual_transport_idle_w = walker_state_idle_w &&
		char_state_idle_w && decoder_idle_w && token_owner_empty_w &&
		outer_cleanup_idle_w;
	wire predictive_owner_idle_w = token_owner_empty_w ||
		((token_owner_count_q == 2'd1) && qualified_row_done_w);
	wire predictive_transport_idle_w =
		(walker_state_idle_w || walker_terminal_will_idle_w) &&
		char_state_idle_w && decoder_idle_w && predictive_owner_idle_w &&
		outer_cleanup_idle_w;

	assign scheduler_start_valid_w = start_valid_i &&
		walker_start_ready_w && actual_transport_idle_w;
	assign walker_start_valid_w = start_valid_i &&
		scheduler_start_ready_w && actual_transport_idle_w;
	assign start_ready_o = scheduler_start_ready_w &&
		walker_start_ready_w && actual_transport_idle_w;
	assign start_accept_o = start_valid_i && start_ready_o;

	assign busy_o = scheduler_busy_w || walker_busy_w || char_busy_w ||
		decoder_record_valid_w || record_sidecar_valid_q ||
		!token_owner_empty_w || oam_router_cleanup_busy_i ||
		char_router_cleanup_busy_i;
	assign done_o = scheduler_done_w;
	assign cleanup_busy_o = scheduler_cleanup_busy_w ||
		walker_cleanup_busy_w || char_cleanup_busy_w ||
		oam_router_cleanup_busy_i || char_router_cleanup_busy_i;
	assign quiescent_o = !reset_i && !abort_i && !busy_o &&
		!command_active_q;
	assign command_active_o = command_active_q;
	assign transport_idle_o = actual_transport_idle_w;
	assign underflow_unresolved_o = scheduler_underflow_unresolved_w;

	wire terminal_invisible_fire_w = class_fire_w &&
		walker_class_final_w && !walker_class_appears_w &&
		predictive_transport_idle_w;
	wire terminal_row_fire_w = qualified_row_done_w &&
		scheduler_row_last_w && scheduler_row_final_w &&
		predictive_transport_idle_w;
	assign completion_will_idle_o =
		(scheduler_done_w && actual_transport_idle_w) ||
		terminal_invisible_fire_w || terminal_row_fire_w;

	assign char_vrm_write_o = 1'b0;

	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_obj_scheduler
	#(
		.COMPOSED_TIMING_CREDIT_ENABLE(
			COMPOSED_TIMING_CREDIT_ENABLE)
	)
	u_scheduler
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.start_valid_i(scheduler_start_valid_w),
		.start_ready_o(scheduler_start_ready_w),
		.world_i(world_i),
		.strip_i(strip_i),
		.first_visit_i(first_visit_i),
		.has_objects_i(entry_count_i != 11'd0),
		.underflow_i(penalty_i),
		.busy_o(scheduler_busy_w),
		.done_o(scheduler_done_w),
		.done_ready_i(done_ready_i),
		.aborted_o(),
		.cleanup_busy_o(scheduler_cleanup_busy_w),
		.underflow_unresolved_o(scheduler_underflow_unresolved_w),
		.object_class_valid_i(walker_class_valid_w && class_tag_match_w),
		.object_class_ready_o(scheduler_class_ready_w),
		.object_class_final_i(walker_class_final_w),
		.object_class_appears_i(walker_class_appears_w),
		.object_class_continuation_i(walker_class_continuation_w),
		.object_class_visible_rows_i(walker_class_visible_rows_w),
		.object_world_o(),
		.object_strip_o(),
		.object_ordinal_o(),
		.active_setup_valid_o(scheduler_active_setup_valid_w),
		.active_setup_ready_i(scheduler_active_setup_ready_w),
		.active_setup_final_object_o(),
		.active_setup_continuation_o(),
		.active_setup_visible_rows_o(),
		.row_valid_o(scheduler_row_valid_w),
		.row_ready_i(scheduler_row_ready_w),
		.row_ordinal_o(scheduler_row_ordinal_w),
		.row_last_in_object_o(scheduler_row_last_w),
		.row_final_object_o(scheduler_row_final_w),
		.transport_idle_i(predictive_transport_idle_w),
		.state_o(scheduler_state_o),
		.state_ticks_remaining_o(scheduler_ticks_remaining_o),
		.diag_elapsed_ticks_o(scheduler_elapsed_ticks_o),
		.diag_fixed_ticks_o(scheduler_fixed_ticks_o),
		.diag_probe_ticks_o(scheduler_probe_ticks_o),
		.diag_active_setup_ticks_o(scheduler_active_setup_ticks_o),
		.diag_continuation_ticks_o(scheduler_continuation_ticks_o),
		.diag_row_ticks_o(scheduler_row_ticks_o),
		.diag_underflow_ticks_o(scheduler_underflow_ticks_o),
		.diag_transport_stall_ticks_o(
			scheduler_transport_stall_ticks_o),
		.diag_object_accept_count_o(),
		.diag_active_setup_accept_count_o(),
		.diag_row_accept_count_o(),
		.diag_object_complete_count_o(),
		.diag_interface_seam_credit_o(),
		.invalid_strip_o(),
		.invalid_classification_o(scheduler_invalid_classification_w),
		.object_ordinal_overflow_o(
			scheduler_object_ordinal_overflow_w)
	);

	vip_xp_obj_oam_walker u_oam_walker
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.start_valid_i(walker_start_valid_w),
		.start_ready_o(walker_start_ready_w),
		.start_accept_o(),
		.start_strip_i(strip_i),
		.start_epoch_i(epoch_i),
		.start_first_index_i(first_index_i),
		.start_final_index_i(final_index_i),
		.start_entry_count_i(entry_count_i),
		.dram_req_o(oam_dram_req_o),
		.dram_addr_o(oam_dram_addr_o),
		.dram_accept_i(oam_dram_accept_i),
		.dram_resp_valid_i(oam_effective_resp_valid_w),
		.dram_resp_data_i(oam_effective_resp_data_w),
		.class_valid_o(walker_class_valid_w),
		.class_ready_i(walker_class_ready_w),
		.class_object_index_o(walker_class_index_w),
		.class_strip_o(walker_class_strip_w),
		.class_epoch_o(walker_class_epoch_w),
		.class_final_o(walker_class_final_w),
		.class_appears_o(walker_class_appears_w),
		.class_continuation_o(walker_class_continuation_w),
		.class_visible_rows_o(walker_class_visible_rows_w),
		.class_first_screen_y_o(walker_class_first_screen_y_w),
		.class_first_source_row_o(walker_class_first_source_row_w),
		.class_raw_jy_o(),
		.class_word2_o(),
		.class_unresolved_jy_o(walker_class_unresolved_jy_w),
		.class_invalid_strip_o(),
		.detail_start_valid_i(walker_detail_start_valid_w),
		.detail_start_ready_o(),
		.detail_start_accept_o(walker_detail_start_accept_w),
		.detail_start_index_i(active_index_q),
		.detail_start_epoch_i(active_epoch_q),
		.record_valid_o(walker_record_valid_w),
		.record_ready_i(walker_record_ready_w),
		.record_data_o(walker_record_data_w),
		.record_object_index_o(walker_record_index_w),
		.record_strip_o(walker_record_strip_w),
		.record_epoch_o(walker_record_epoch_w),
		.record_final_o(walker_record_final_w),
		.record_continuation_o(walker_record_continuation_w),
		.record_visible_rows_o(walker_record_visible_rows_w),
		.record_first_screen_y_o(walker_record_first_screen_y_w),
		.record_first_source_row_o(walker_record_first_source_row_w),
		.record_raw_jy_o(),
		.record_unresolved_jy_o(walker_record_unresolved_jy_w),
		.busy_o(walker_busy_w),
		.cleanup_busy_o(walker_cleanup_busy_w),
		.quiescent_o(),
		.terminal_will_idle_o(walker_terminal_will_idle_w),
		.transport_offer_valid_o(),
		.transport_pending_o(walker_transport_pending_w),
		.transport_response_capture_valid_o(),
		.stale_response_discarded_o(walker_stale_discard_w),
		.invalid_context_o(),
		.context_count_mismatch_o(),
		.stream_tag_error_o(),
		.class_alignment_error_o(),
		.detail_start_tag_mismatch_o(),
		.detail_sequence_error_o(),
		.transport_protocol_error_o(),
		.protocol_error_o(walker_protocol_error_w)
	);

	vip_xp_obj_decode u_field_decode
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.descriptor_valid_i(walker_record_valid_w &&
			record_tag_match_w && !record_sidecar_valid_q),
		.descriptor_ready_o(decoder_descriptor_ready_w),
		.descriptor_accept_o(decoder_descriptor_accept_w),
		.descriptor_i(walker_record_scaled_data_w),
		.record_valid_o(decoder_record_valid_w),
		.record_ready_i(decoder_record_ready_w),
		.jx_o(),
		.jp_o(),
		.jy_raw_o(),
		.jlon_o(decoder_jlon_w),
		.jron_o(decoder_jron_w),
		.jplt_select_o(decoder_jplt_select_w),
		.hflip_o(decoder_hflip_w),
		.vflip_o(decoder_vflip_w),
		.jca_o(decoder_jca_w),
		.left_base_o(decoder_left_base_w),
		.right_base_o(decoder_right_base_w),
		.jy_unresolved_o(decoder_jy_unresolved_w),
		.ignored_bits_nonzero_o(decoder_ignored_bits_w)
	);

	vip_xp_obj_char_pipeline u_char_pipeline
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.context_valid_i(char_context_valid_w),
		.context_ready_o(),
		.context_accept_o(char_context_accept_w),
		.context_epoch_i(record_epoch_q),
		.context_object_index_i(record_index_q),
		.context_screen_y_i(context_screen_sum_w[8:0]),
		.context_source_row_i(context_source_sum_w[2:0]),
		.context_jca_i(decoder_jca_w),
		.context_vflip_i(decoder_vflip_w),
		.context_hflip_i(decoder_hflip_w),
		.context_jplt_select_i(decoder_jplt_select_w),
		.context_jplt_active_i(command_jplt_q),
		.context_left_base_i(decoder_left_base_w),
		.context_right_base_i(decoder_right_base_w),
		.context_jlon_i(decoder_jlon_w),
		.context_jron_i(decoder_jron_w),
		.vrm_req_o(char_vrm_req_o),
		.vrm_write_o(),
		.vrm_addr_o(char_vrm_addr_o),
		.vrm_accept_i(char_vrm_accept_i),
		.vrm_resp_valid_i(char_effective_resp_valid_w),
		.vrm_resp_data_i(char_effective_resp_data_w),
		.decode_query_valid_o(decode_query_valid_o),
		.decode_query_ready_o(decode_query_ready_o),
		.decode_grant_i(decode_grant_i),
		.decode_conflict_i(decode_conflict_i),
		.decode_accept_o(decode_accept_o),
		.decode_character_row_o(decode_character_row_o),
		.decode_palette_o(decode_palette_o),
		.decode_hflip_o(decode_hflip_o),
		.decode_jplt_active_o(decode_jplt_active_o),
		.decoded_raw_nonzero_i(decoded_raw_nonzero_i),
		.decoded_mapped_pixels_i(decoded_mapped_pixels_i),
		.token_valid_o(char_token_valid_w),
		.token_ready_i(char_token_ready_w),
		.token_accept_o(char_token_accept_w),
		.token_epoch_o(char_token_epoch_w),
		.token_object_index_o(char_token_index_w),
		.token_screen_y_o(char_token_screen_y_w),
		.token_source_row_o(char_token_source_row_w),
		.token_row_o(char_token_row_w),
		.token_left_base_x_o(char_token_left_base_w),
		.token_left_enable_o(char_token_left_enable_w),
		.token_left_active_o(char_token_left_active_w),
		.token_left_opaque_o(char_token_left_opaque_w),
		.token_left_values_o(char_token_left_values_w),
		.token_right_base_x_o(char_token_right_base_w),
		.token_right_enable_o(char_token_right_enable_w),
		.token_right_active_o(char_token_right_active_w),
		.token_right_opaque_o(char_token_right_opaque_w),
		.token_right_values_o(char_token_right_values_w),
		.character_effective_row_o(char_character_effective_row_w),
		.character_row_addr_o(char_character_row_addr_w),
		.busy_o(char_busy_w),
		.cleanup_busy_o(char_cleanup_busy_w),
		.quiescent_o(),
		.offer_valid_o(),
		.read_pending_o(char_read_pending_w),
		.response_capture_valid_o(),
		.decode_pending_o(),
		.row_token_busy_o(),
		.stale_response_discarded_o(char_stale_discard_w),
		.accept_without_request_o(char_accept_without_request_w),
		.unowned_response_o(char_unowned_response_w),
		.response_capture_overflow_o(
			char_response_capture_overflow_w),
		.pending_owner_overlap_o(char_pending_owner_overlap_w),
		.decode_conflict_o(char_decode_conflict_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

`ifndef SYNTHESIS
	reg [31:0] diag_oam_read_accept_count_q;
	reg [31:0] diag_char_context_accept_count_q;
	reg [31:0] diag_char_read_accept_count_q;
	reg [31:0] diag_token_accept_count_q;
	reg [31:0] diag_token_done_count_q;

	assign diag_oam_read_accept_count_o = diag_oam_read_accept_count_q;
	assign diag_char_context_accept_count_o =
		diag_char_context_accept_count_q;
	assign diag_char_read_accept_count_o = diag_char_read_accept_count_q;
	assign diag_token_accept_count_o = diag_token_accept_count_q;
	assign diag_token_done_count_o = diag_token_done_count_q;
`else
	assign diag_oam_read_accept_count_o = 32'd0;
	assign diag_char_context_accept_count_o = 32'd0;
	assign diag_char_read_accept_count_o = 32'd0;
	assign diag_token_accept_count_o = 32'd0;
	assign diag_token_done_count_o = 32'd0;
`endif

	assign protocol_error_o = class_tag_error_o ||
		record_tag_error_o || char_tag_error_o || row_tag_error_o ||
		token_owner_overflow_o || token_owner_underflow_o ||
		outer_stale_error_o || walker_protocol_error_w ||
		char_accept_without_request_w || char_unowned_response_w ||
		char_response_capture_overflow_w ||
		char_pending_owner_overlap_w || char_decode_conflict_w ||
		scheduler_invalid_classification_w ||
		scheduler_object_ordinal_overflow_w;

	always @(posedge clk_i) begin
		if (reset_i) begin
			command_active_q <= 1'b0;
			command_strip_q <= 5'd0;
			command_epoch_q <= 4'd0;
			command_final_index_q <= 10'd0;
			command_jplt_q <= 32'd0;
			expected_class_index_q <= 10'd0;
			active_class_valid_q <= 1'b0;
			active_index_q <= 10'd0;
			active_strip_q <= 5'd0;
			active_epoch_q <= 4'd0;
			active_final_q <= 1'b0;
			active_continuation_q <= 1'b0;
			active_visible_rows_q <= 4'd0;
			active_first_screen_y_q <= 9'd0;
			active_first_source_row_q <= 3'd0;
			detail_started_q <= 1'b0;
			first_token_issued_q <= 1'b0;
			record_sidecar_valid_q <= 1'b0;
			record_index_q <= 10'd0;
			record_epoch_q <= 4'd0;
			record_visible_rows_q <= 4'd0;
			record_first_screen_y_q <= 9'd0;
			record_first_source_row_q <= 3'd0;
			context_ordinal_q <= 4'd0;
			token_owner_slot0_q <= 29'd0;
			token_owner_slot1_q <= 29'd0;
			token_owner_presented0_q <= 1'b0;
			token_owner_presented1_q <= 1'b0;
			token_owner_head_q <= 1'b0;
			token_owner_tail_q <= 1'b0;
			token_owner_count_q <= 2'd0;
			jy_unresolved_o <= 1'b0;
			ignored_oam_bits_nonzero_o <= 1'b0;
			class_tag_error_o <= 1'b0;
			record_tag_error_o <= 1'b0;
			char_tag_error_o <= 1'b0;
			row_tag_error_o <= 1'b0;
			token_owner_overflow_o <= 1'b0;
			token_owner_underflow_o <= 1'b0;
			outer_stale_error_o <= 1'b0;
`ifndef SYNTHESIS
			diag_oam_read_accept_count_q <= 32'd0;
			diag_char_context_accept_count_q <= 32'd0;
			diag_char_read_accept_count_q <= 32'd0;
			diag_token_accept_count_q <= 32'd0;
			diag_token_done_count_q <= 32'd0;
`endif
		end else if (abort_i) begin
			command_active_q <= 1'b0;
			active_class_valid_q <= 1'b0;
			detail_started_q <= 1'b0;
			first_token_issued_q <= 1'b0;
			record_sidecar_valid_q <= 1'b0;
			context_ordinal_q <= 4'd0;
			token_owner_slot0_q <= 29'd0;
			token_owner_slot1_q <= 29'd0;
			token_owner_presented0_q <= 1'b0;
			token_owner_presented1_q <= 1'b0;
			token_owner_head_q <= 1'b0;
			token_owner_tail_q <= 1'b0;
			token_owner_count_q <= 2'd0;
			jy_unresolved_o <= 1'b0;
			ignored_oam_bits_nonzero_o <= 1'b0;
		end else begin
			// Check stale-retirement ownership on the raw clock.
			if (oam_router_stale_discard_i &&
				!walker_transport_pending_w)
				outer_stale_error_o <= 1'b1;
			if (char_router_stale_discard_i &&
				!char_read_pending_w)
				outer_stale_error_o <= 1'b1;
			if ((oam_router_stale_discard_i &&
				oam_dram_resp_valid_i) ||
				(char_router_stale_discard_i && char_vrm_resp_valid_i))
				outer_stale_error_o <= 1'b1;

			if (ce_i) begin
				if (scheduler_done_w && done_ready_i &&
					!start_accept_o) begin
					command_active_q <= 1'b0;
				end

				if (start_accept_o) begin
					command_active_q <= 1'b1;
					command_strip_q <= strip_i;
					command_epoch_q <= epoch_i;
					command_final_index_q <= final_index_i;
					command_jplt_q <= jplt_active_i;
					expected_class_index_q <= first_index_i;
					active_class_valid_q <= 1'b0;
					detail_started_q <= 1'b0;
					first_token_issued_q <= 1'b0;
					record_sidecar_valid_q <= 1'b0;
					context_ordinal_q <= 4'd0;
					jy_unresolved_o <= 1'b0;
					ignored_oam_bits_nonzero_o <= 1'b0;
					class_tag_error_o <= 1'b0;
					record_tag_error_o <= 1'b0;
					char_tag_error_o <= 1'b0;
					row_tag_error_o <= 1'b0;
					token_owner_overflow_o <= 1'b0;
					token_owner_underflow_o <= 1'b0;
					outer_stale_error_o <= 1'b0;
				end

				if (walker_class_valid_w && !class_tag_match_w)
					class_tag_error_o <= 1'b1;

				if (class_fire_w) begin
					if (walker_class_unresolved_jy_w)
						jy_unresolved_o <= 1'b1;
					if (walker_class_final_w) begin
						expected_class_index_q <=
							expected_class_index_q;
					end else begin
						expected_class_index_q <=
							expected_class_index_q - 10'd1;
					end
					if (walker_class_appears_w) begin
						active_class_valid_q <= 1'b1;
						active_index_q <= walker_class_index_w;
						active_strip_q <= walker_class_strip_w;
						active_epoch_q <= walker_class_epoch_w;
						active_final_q <= walker_class_final_w;
						active_continuation_q <=
							walker_class_continuation_w;
						active_visible_rows_q <=
							walker_class_visible_rows_w;
						active_first_screen_y_q <=
							walker_class_first_screen_y_w;
						active_first_source_row_q <=
							walker_class_first_source_row_w;
						detail_started_q <= 1'b0;
						first_token_issued_q <= 1'b0;
					end else begin
						active_class_valid_q <= 1'b0;
					end
				end

				if (walker_detail_start_accept_w)
					detail_started_q <= 1'b1;

				if (walker_record_valid_w && !record_tag_match_w)
					record_tag_error_o <= 1'b1;

				if (decoder_descriptor_accept_w) begin
					record_sidecar_valid_q <= 1'b1;
					record_index_q <= walker_record_index_w;
					record_epoch_q <= walker_record_epoch_w;
					record_visible_rows_q <=
						walker_record_visible_rows_w;
					record_first_screen_y_q <=
						walker_record_first_screen_y_w;
					record_first_source_row_q <=
						walker_record_first_source_row_w;
					context_ordinal_q <= 4'd0;
					if (walker_record_unresolved_jy_w)
						jy_unresolved_o <= 1'b1;
				end

				if (decoder_record_valid_w && decoder_ignored_bits_w)
					ignored_oam_bits_nonzero_o <= 1'b1;
				if (decoder_record_valid_w && decoder_jy_unresolved_w)
					jy_unresolved_o <= 1'b1;

				if (char_context_accept_w) begin
					if (context_last_w) begin
						record_sidecar_valid_q <= 1'b0;
						context_ordinal_q <= 4'd0;
					end else begin
						context_ordinal_q <= context_ordinal_q + 4'd1;
					end
				end

				if (decoder_record_valid_w &&
					context_source_sum_w[3]) begin
					char_tag_error_o <= 1'b1;
				end
				if (char_token_valid_w && !char_tag_in_active_range_w)
					char_tag_error_o <= 1'b1;

				if (char_token_accept_w && first_char_tag_match_w)
					first_token_issued_q <= 1'b1;

				if (token_done_i && token_owner_empty_w)
					token_owner_underflow_o <= 1'b1;
				if (char_token_accept_w && token_owner_full_w &&
					!token_owner_pop_w) begin
					token_owner_overflow_o <= 1'b1;
				end
				if (token_owner_pop_w &&
					(!scheduler_row_valid_w || !row_head_match_w ||
					 !token_owner_head_presented_w)) begin
					row_tag_error_o <= 1'b1;
				end

				if (observe_row_head_w) begin
					if (token_owner_head_q)
						token_owner_presented1_q <= 1'b1;
					else
						token_owner_presented0_q <= 1'b1;
				end

				if (char_token_accept_w) begin
					if (token_owner_tail_q) begin
						token_owner_slot1_q <= char_token_tag_w;
						token_owner_presented1_q <=
							token_owner_empty_w &&
							scheduler_row_valid_w &&
							current_char_tag_match_w;
					end else begin
						token_owner_slot0_q <= char_token_tag_w;
						token_owner_presented0_q <=
							token_owner_empty_w &&
							scheduler_row_valid_w &&
							current_char_tag_match_w;
					end
					token_owner_tail_q <= ~token_owner_tail_q;
				end
				if (token_owner_pop_w)
					token_owner_head_q <= ~token_owner_head_q;

				case ({char_token_accept_w, token_owner_pop_w})
					2'b10: token_owner_count_q <=
						token_owner_count_q + 2'd1;
					2'b01: token_owner_count_q <=
						token_owner_count_q - 2'd1;
					default: token_owner_count_q <= token_owner_count_q;
				endcase

`ifndef SYNTHESIS
				if (start_accept_o) begin
					diag_oam_read_accept_count_q <= 32'd0;
					diag_char_context_accept_count_q <= 32'd0;
					diag_char_read_accept_count_q <= 32'd0;
					diag_token_accept_count_q <= 32'd0;
					diag_token_done_count_q <= 32'd0;
				end else begin
					if (oam_dram_req_o && oam_dram_accept_i)
						diag_oam_read_accept_count_q <=
							diag_oam_read_accept_count_q + 32'd1;
					if (char_context_accept_w)
						diag_char_context_accept_count_q <=
							diag_char_context_accept_count_q + 32'd1;
					if (char_vrm_req_o && char_vrm_accept_i)
						diag_char_read_accept_count_q <=
							diag_char_read_accept_count_q + 32'd1;
					if (char_token_accept_w)
						diag_token_accept_count_q <=
							diag_token_accept_count_q + 32'd1;
					if (token_owner_pop_w)
						diag_token_done_count_q <=
							diag_token_done_count_q + 32'd1;
				end
`endif
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Object-world strip scheduler.
//
// One command visits one strip of an active Object world. Timing stages are:
//   - 27 + first_visit_i fixed CE in standalone mode;
//   - 4 + first_visit_i fixed CE in composed mode;
//   - an optional provisional 1,032-CE underflow state;
//   - one probe CE for every selected Object;
//   - 42 setup CE for every Object appearing on this strip;
//   - five continuation CE when the Object top is not on this strip; and
//   - two CE for every visible Object row.
//
// Late work extends only its own timing interval and raises the transport-stall count.
//
// Hold completion until ready and allow same-edge replacement. Abort drops new
// offers and waits for accepted transport to drain before restart.

module vip_xp_obj_scheduler
#(
	parameter integer COMPOSED_TIMING_CREDIT_ENABLE = 0
)
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	// Held strip command. has_objects_i also supports the zero-object timing test.
	input  wire                 start_valid_i,
	output wire                 start_ready_o,
	input  wire [4:0]           world_i,
	input  wire [4:0]           strip_i,
	input  wire                 first_visit_i,
	input  wire                 has_objects_i,
	input  wire                 underflow_i,

	output wire                 busy_o,
	output wire                 done_o,
	input  wire                 done_ready_i,
	output reg                  aborted_o,
	output wire                 cleanup_busy_o,
	output reg                  underflow_unresolved_o,

	// Ordered Object classifications from the Y-first OAM walker.
	input  wire                 object_class_valid_i,
	output wire                 object_class_ready_o,
	input  wire                 object_class_final_i,
	input  wire                 object_class_appears_i,
	input  wire                 object_class_continuation_i,
	input  wire [3:0]           object_class_visible_rows_i,
	output wire [4:0]           object_world_o,
	output wire [4:0]           object_strip_o,
	output wire [9:0]           object_ordinal_o,

	// One detail request per visible Object; early acceptance does not shorten setup.
	output wire                 active_setup_valid_o,
	input  wire                 active_setup_ready_i,
	output wire                 active_setup_final_object_o,
	output wire                 active_setup_continuation_o,
	output wire [3:0]           active_setup_visible_rows_o,

	// One request per visible row; early acceptance does not shorten its interval.
	output wire                 row_valid_o,
	input  wire                 row_ready_i,
	output wire [3:0]           row_ordinal_o,
	output wire                 row_last_in_object_o,
	output wire                 row_final_object_o,

	// Accepted OAM, character, and row ownership.
	input  wire                 transport_idle_i,

	output wire [2:0]           state_o,
	output wire [10:0]          state_ticks_remaining_o,
`ifndef SYNTHESIS
	output reg  [31:0]          diag_elapsed_ticks_o,
	output reg  [15:0]          diag_fixed_ticks_o,
	output reg  [31:0]          diag_probe_ticks_o,
	output reg  [31:0]          diag_active_setup_ticks_o,
	output reg  [31:0]          diag_continuation_ticks_o,
	output reg  [31:0]          diag_row_ticks_o,
	output reg  [31:0]          diag_underflow_ticks_o,
	output reg  [31:0]          diag_transport_stall_ticks_o,
	output reg  [10:0]          diag_object_accept_count_o,
	output reg  [10:0]          diag_active_setup_accept_count_o,
	output reg  [31:0]          diag_row_accept_count_o,
	output reg  [10:0]          diag_object_complete_count_o,
	output reg  [5:0]           diag_interface_seam_credit_o,
	output reg                  invalid_strip_o,
	output reg                  invalid_classification_o,
	output reg                  object_ordinal_overflow_o
`else
	output wire [31:0]          diag_elapsed_ticks_o,
	output wire [15:0]          diag_fixed_ticks_o,
	output wire [31:0]          diag_probe_ticks_o,
	output wire [31:0]          diag_active_setup_ticks_o,
	output wire [31:0]          diag_continuation_ticks_o,
	output wire [31:0]          diag_row_ticks_o,
	output wire [31:0]          diag_underflow_ticks_o,
	output wire [31:0]          diag_transport_stall_ticks_o,
	output wire [10:0]          diag_object_accept_count_o,
	output wire [10:0]          diag_active_setup_accept_count_o,
	output wire [31:0]          diag_row_accept_count_o,
	output wire [10:0]          diag_object_complete_count_o,
	output wire [5:0]           diag_interface_seam_credit_o,
	output wire                 invalid_strip_o,
	output wire                 invalid_classification_o,
	output wire                 object_ordinal_overflow_o
`endif
);

	// vip_xp_obj_engine mirrors ACTIVE_SETUP and CONTINUATION to watch
	// scheduler_state_o; keep the encodings in step.
	localparam [2:0]
		STATE_IDLE         = 3'd0,
		STATE_FIXED        = 3'd1,
		STATE_UNDERFLOW    = 3'd2,
		STATE_PROBE        = 3'd3,
		STATE_ACTIVE_SETUP = 3'd4,
		STATE_CONTINUATION = 3'd5,
		STATE_ROW          = 3'd6;

	localparam [10:0]
		NATURAL_FIXED_TICKS   = 11'd27,
		COMPOSED_FIXED_TICKS  = 11'd4,
		// Silicon unknown: use 1,032 underflow cycles per strip to match the
		// measured 28,896-cycle total.
		UNDERFLOW_TICKS       = 11'd1032,
		PROBE_TICKS           = 11'd1,
		ACTIVE_SETUP_TICKS    = 11'd42,
		CONTINUATION_TICKS    = 11'd5,
		ROW_TICKS             = 11'd2;

	reg [2:0] state_q;
	reg [10:0] state_ticks_remaining_q;
	reg done_q;
	reg abort_cleanup_pending_q;
	reg retire_pending_q;

	reg [4:0] world_q;
	reg [4:0] strip_q;
	reg has_objects_q;
	reg underflow_q;
	reg [9:0] object_ordinal_q;

	reg class_accepted_q;
	reg class_final_q;
	reg class_appears_q;
	reg class_continuation_q;
	reg [3:0] class_visible_rows_q;
	reg active_setup_accepted_q;
	reg row_accepted_q;
	reg [3:0] row_ordinal_q;

	wire start_fire_w = ce_i && start_valid_i && start_ready_o;
	wire class_fire_w = ce_i && object_class_valid_i &&
		object_class_ready_o;
	wire active_setup_fire_w = ce_i && active_setup_valid_o &&
		active_setup_ready_i;
	wire row_fire_w = ce_i && row_valid_o && row_ready_i;

	wire class_complete_w = class_accepted_q || class_fire_w;
	wire class_completed_final_w = class_fire_w ?
		object_class_final_i : class_final_q;
	wire class_completed_appears_w = class_fire_w ?
		object_class_appears_i : class_appears_q;
	wire class_completed_continuation_w = class_fire_w ?
		object_class_continuation_i : class_continuation_q;
	wire [3:0] class_completed_visible_rows_w = class_fire_w ?
		object_class_visible_rows_i : class_visible_rows_q;
	wire active_setup_complete_w = active_setup_accepted_q ||
		active_setup_fire_w;
	wire row_complete_w = row_accepted_q || row_fire_w;
	wire row_is_last_w = ({1'b0, row_ordinal_q} + 5'd1) >=
		{1'b0, class_visible_rows_q};

	wire [10:0] fixed_ticks_w =
		(COMPOSED_TIMING_CREDIT_ENABLE != 0) ?
		(COMPOSED_FIXED_TICKS + {10'd0, first_visit_i}) :
		(NATURAL_FIXED_TICKS + {10'd0, first_visit_i});

	assign start_ready_o = ce_i && !reset_i && !abort_i &&
		!abort_cleanup_pending_q && transport_idle_i &&
		(state_q == STATE_IDLE) && (!done_q || done_ready_i);
	assign busy_o = (state_q != STATE_IDLE) || done_q ||
		abort_cleanup_pending_q;
	assign done_o = done_q && !reset_i && !abort_i;
	assign cleanup_busy_o = abort_cleanup_pending_q;

	assign object_class_ready_o = ce_i && !reset_i && !abort_i &&
		!retire_pending_q && (state_q == STATE_PROBE) &&
		!class_accepted_q;
	assign object_world_o = world_q;
	assign object_strip_o = strip_q;
	assign object_ordinal_o = object_ordinal_q;

	assign active_setup_valid_o = !reset_i && !abort_i &&
		!retire_pending_q && (state_q == STATE_ACTIVE_SETUP) &&
		!active_setup_accepted_q;
	assign active_setup_final_object_o = class_final_q;
	assign active_setup_continuation_o = class_continuation_q;
	assign active_setup_visible_rows_o = class_visible_rows_q;

	assign row_valid_o = !reset_i && !abort_i && !retire_pending_q &&
		(state_q == STATE_ROW) && !row_accepted_q;
	assign row_ordinal_o = row_ordinal_q;
	assign row_last_in_object_o = row_is_last_w;
	assign row_final_object_o = class_final_q;

	assign state_o = state_q;
	assign state_ticks_remaining_o = state_ticks_remaining_q;

`ifdef SYNTHESIS
	assign diag_elapsed_ticks_o = 32'd0;
	assign diag_fixed_ticks_o = 16'd0;
	assign diag_probe_ticks_o = 32'd0;
	assign diag_active_setup_ticks_o = 32'd0;
	assign diag_continuation_ticks_o = 32'd0;
	assign diag_row_ticks_o = 32'd0;
	assign diag_underflow_ticks_o = 32'd0;
	assign diag_transport_stall_ticks_o = 32'd0;
	assign diag_object_accept_count_o = 11'd0;
	assign diag_active_setup_accept_count_o = 11'd0;
	assign diag_row_accept_count_o = 32'd0;
	assign diag_object_complete_count_o = 11'd0;
	assign diag_interface_seam_credit_o = 6'd0;
	assign invalid_strip_o = 1'b0;
	assign invalid_classification_o = 1'b0;
	assign object_ordinal_overflow_o = 1'b0;
`endif

	// Retire the finished object: end the pass on the final object, else
	// step the ordinal (saturating at 1023) and probe the next one.
	task complete_object_task;
		input final_object;
		begin
`ifndef SYNTHESIS
			diag_object_complete_count_o <=
				diag_object_complete_count_o + 11'd1;
`endif
			if (final_object) begin
				state_ticks_remaining_q <= 11'd0;
				if (transport_idle_i) begin
					state_q <= STATE_IDLE;
					done_q <= 1'b1;
				end else begin
					retire_pending_q <= 1'b1;
				end
			end else begin
`ifndef SYNTHESIS
				if (object_ordinal_q == 10'd1023)
					object_ordinal_overflow_o <= 1'b1;
`endif
				if (object_ordinal_q != 10'd1023)
					object_ordinal_q <= object_ordinal_q + 10'd1;
				state_q <= STATE_PROBE;
				state_ticks_remaining_q <= PROBE_TICKS;
				class_accepted_q <= 1'b0;
			end
		end
	endtask

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			state_ticks_remaining_q <= 11'd0;
			done_q <= 1'b0;
			abort_cleanup_pending_q <= 1'b0;
			retire_pending_q <= 1'b0;
			world_q <= 5'd0;
			strip_q <= 5'd0;
			has_objects_q <= 1'b0;
			underflow_q <= 1'b0;
			object_ordinal_q <= 10'd0;
			class_accepted_q <= 1'b0;
			class_final_q <= 1'b0;
			class_appears_q <= 1'b0;
			class_continuation_q <= 1'b0;
			class_visible_rows_q <= 4'd0;
			active_setup_accepted_q <= 1'b0;
			row_accepted_q <= 1'b0;
			row_ordinal_q <= 4'd0;
			aborted_o <= 1'b0;
			underflow_unresolved_o <= 1'b0;
`ifndef SYNTHESIS
			diag_elapsed_ticks_o <= 32'd0;
			diag_fixed_ticks_o <= 16'd0;
			diag_probe_ticks_o <= 32'd0;
			diag_active_setup_ticks_o <= 32'd0;
			diag_continuation_ticks_o <= 32'd0;
			diag_row_ticks_o <= 32'd0;
			diag_underflow_ticks_o <= 32'd0;
			diag_transport_stall_ticks_o <= 32'd0;
			diag_object_accept_count_o <= 11'd0;
			diag_active_setup_accept_count_o <= 11'd0;
			diag_row_accept_count_o <= 32'd0;
			diag_object_complete_count_o <= 11'd0;
			diag_interface_seam_credit_o <= 6'd0;
			invalid_strip_o <= 1'b0;
			invalid_classification_o <= 1'b0;
			object_ordinal_overflow_o <= 1'b0;
`endif
		end else if (abort_i) begin
			state_q <= STATE_IDLE;
			state_ticks_remaining_q <= 11'd0;
			done_q <= 1'b0;
			abort_cleanup_pending_q <= !transport_idle_i;
			retire_pending_q <= 1'b0;
			has_objects_q <= 1'b0;
			underflow_q <= 1'b0;
			object_ordinal_q <= 10'd0;
			class_accepted_q <= 1'b0;
			active_setup_accepted_q <= 1'b0;
			row_accepted_q <= 1'b0;
			row_ordinal_q <= 4'd0;
			aborted_o <= 1'b1;
			underflow_unresolved_o <= 1'b0;
		end else if (ce_i) begin
			if (abort_cleanup_pending_q && transport_idle_i)
				abort_cleanup_pending_q <= 1'b0;

			if (retire_pending_q) begin
`ifndef SYNTHESIS
				diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
				diag_transport_stall_ticks_o <=
					diag_transport_stall_ticks_o + 32'd1;
`endif
				if (transport_idle_i) begin
					state_q <= STATE_IDLE;
					state_ticks_remaining_q <= 11'd0;
					retire_pending_q <= 1'b0;
					done_q <= 1'b1;
				end
			end else begin
				case (state_q)
					STATE_IDLE: begin
						state_ticks_remaining_q <= 11'd0;
						class_accepted_q <= 1'b0;
						active_setup_accepted_q <= 1'b0;
						row_accepted_q <= 1'b0;
						if (done_q && done_ready_i)
							done_q <= 1'b0;
						if (start_fire_w) begin
							state_q <= STATE_FIXED;
							state_ticks_remaining_q <= fixed_ticks_w;
							done_q <= 1'b0;
							world_q <= world_i;
							strip_q <= strip_i;
							has_objects_q <= has_objects_i;
							underflow_q <= underflow_i;
							object_ordinal_q <= 10'd0;
							class_final_q <= 1'b0;
							class_appears_q <= 1'b0;
							class_continuation_q <= 1'b0;
							class_visible_rows_q <= 4'd0;
							row_ordinal_q <= 4'd0;
							aborted_o <= 1'b0;
							underflow_unresolved_o <= underflow_i;
`ifndef SYNTHESIS
							diag_elapsed_ticks_o <= 32'd0;
							diag_fixed_ticks_o <= 16'd0;
							diag_probe_ticks_o <= 32'd0;
							diag_active_setup_ticks_o <= 32'd0;
							diag_continuation_ticks_o <= 32'd0;
							diag_row_ticks_o <= 32'd0;
							diag_underflow_ticks_o <= 32'd0;
							diag_transport_stall_ticks_o <= 32'd0;
							diag_object_accept_count_o <= 11'd0;
							diag_active_setup_accept_count_o <= 11'd0;
							diag_row_accept_count_o <= 32'd0;
							diag_object_complete_count_o <= 11'd0;
							diag_interface_seam_credit_o <=
								(COMPOSED_TIMING_CREDIT_ENABLE != 0) ?
								6'd23 : 6'd0;
							invalid_strip_o <= strip_i >= 5'd28;
							invalid_classification_o <= 1'b0;
							object_ordinal_overflow_o <= 1'b0;
`endif
						end
					end

					STATE_FIXED: begin
`ifndef SYNTHESIS
						diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
						if (state_ticks_remaining_q != 11'd0)
							diag_fixed_ticks_o <= diag_fixed_ticks_o + 16'd1;
						else
							diag_transport_stall_ticks_o <=
								diag_transport_stall_ticks_o + 32'd1;
`endif
						if (state_ticks_remaining_q > 11'd1) begin
							state_ticks_remaining_q <= state_ticks_remaining_q - 11'd1;
						end else if (state_ticks_remaining_q == 11'd1) begin
							if (underflow_q) begin
								state_q <= STATE_UNDERFLOW;
								state_ticks_remaining_q <= UNDERFLOW_TICKS;
							end else if (has_objects_q) begin
								state_q <= STATE_PROBE;
								state_ticks_remaining_q <= PROBE_TICKS;
								class_accepted_q <= 1'b0;
							end else if (transport_idle_i) begin
								state_q <= STATE_IDLE;
								state_ticks_remaining_q <= 11'd0;
								done_q <= 1'b1;
							end else begin
								state_ticks_remaining_q <= 11'd0;
								retire_pending_q <= 1'b1;
							end
						end
					end

					STATE_UNDERFLOW: begin
`ifndef SYNTHESIS
						diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
						diag_underflow_ticks_o <=
							diag_underflow_ticks_o + 32'd1;
`endif
						if (state_ticks_remaining_q > 11'd1) begin
							state_ticks_remaining_q <= state_ticks_remaining_q - 11'd1;
						end else if (has_objects_q) begin
							state_q <= STATE_PROBE;
							state_ticks_remaining_q <= PROBE_TICKS;
							class_accepted_q <= 1'b0;
						end else if (transport_idle_i) begin
							state_q <= STATE_IDLE;
							state_ticks_remaining_q <= 11'd0;
							done_q <= 1'b1;
						end else begin
							state_ticks_remaining_q <= 11'd0;
							retire_pending_q <= 1'b1;
						end
					end

					STATE_PROBE: begin
`ifndef SYNTHESIS
						diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
						if (state_ticks_remaining_q != 11'd0)
							diag_probe_ticks_o <= diag_probe_ticks_o + 32'd1;
						else
							diag_transport_stall_ticks_o <=
								diag_transport_stall_ticks_o + 32'd1;
`endif
						if (class_fire_w) begin
							class_accepted_q <= 1'b1;
							class_final_q <= object_class_final_i;
							class_appears_q <= object_class_appears_i;
							class_continuation_q <=
								object_class_continuation_i;
							class_visible_rows_q <=
								object_class_visible_rows_i;
`ifndef SYNTHESIS
							diag_object_accept_count_o <=
								diag_object_accept_count_o + 11'd1;
							if ((object_class_visible_rows_i > 4'd8) ||
								(object_class_appears_i &&
								 (object_class_visible_rows_i == 4'd0)) ||
								(!object_class_appears_i &&
								 (object_class_continuation_i ||
								  (object_class_visible_rows_i != 4'd0)))) begin
								invalid_classification_o <= 1'b1;
							end
`endif
						end

						if (state_ticks_remaining_q > 11'd1) begin
							state_ticks_remaining_q <= state_ticks_remaining_q - 11'd1;
						end else if (class_complete_w) begin
							class_accepted_q <= 1'b0;
							if (class_completed_appears_w) begin
								class_final_q <= class_completed_final_w;
								class_appears_q <= 1'b1;
								class_continuation_q <=
									class_completed_continuation_w;
								class_visible_rows_q <=
									class_completed_visible_rows_w;
								active_setup_accepted_q <= 1'b0;
								state_q <= STATE_ACTIVE_SETUP;
								state_ticks_remaining_q <= ACTIVE_SETUP_TICKS;
							end else begin
								complete_object_task(
									class_completed_final_w);
							end
						end else if (state_ticks_remaining_q == 11'd1) begin
							state_ticks_remaining_q <= 11'd0;
						end
					end

					STATE_ACTIVE_SETUP: begin
`ifndef SYNTHESIS
						diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
						if (state_ticks_remaining_q != 11'd0)
							diag_active_setup_ticks_o <=
								diag_active_setup_ticks_o + 32'd1;
						else
							diag_transport_stall_ticks_o <=
								diag_transport_stall_ticks_o + 32'd1;
`endif
						if (active_setup_fire_w) begin
							active_setup_accepted_q <= 1'b1;
`ifndef SYNTHESIS
							diag_active_setup_accept_count_o <=
								diag_active_setup_accept_count_o + 11'd1;
`endif
						end
						if (state_ticks_remaining_q > 11'd1) begin
							state_ticks_remaining_q <= state_ticks_remaining_q - 11'd1;
						end else if (active_setup_complete_w) begin
							active_setup_accepted_q <= 1'b0;
							if (class_continuation_q) begin
								state_q <= STATE_CONTINUATION;
								state_ticks_remaining_q <= CONTINUATION_TICKS;
							end else if (class_visible_rows_q != 4'd0) begin
								state_q <= STATE_ROW;
								state_ticks_remaining_q <= ROW_TICKS;
								row_ordinal_q <= 4'd0;
								row_accepted_q <= 1'b0;
							end else begin
								complete_object_task(class_final_q);
							end
						end else if (state_ticks_remaining_q == 11'd1) begin
							state_ticks_remaining_q <= 11'd0;
						end
					end

					STATE_CONTINUATION: begin
`ifndef SYNTHESIS
						diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
						diag_continuation_ticks_o <=
							diag_continuation_ticks_o + 32'd1;
`endif
						if (state_ticks_remaining_q > 11'd1) begin
							state_ticks_remaining_q <= state_ticks_remaining_q - 11'd1;
						end else if (class_visible_rows_q != 4'd0) begin
							state_q <= STATE_ROW;
							state_ticks_remaining_q <= ROW_TICKS;
							row_ordinal_q <= 4'd0;
							row_accepted_q <= 1'b0;
						end else begin
							complete_object_task(class_final_q);
						end
					end

					STATE_ROW: begin
`ifndef SYNTHESIS
						diag_elapsed_ticks_o <= diag_elapsed_ticks_o + 32'd1;
						if (state_ticks_remaining_q != 11'd0)
							diag_row_ticks_o <= diag_row_ticks_o + 32'd1;
						else
							diag_transport_stall_ticks_o <=
								diag_transport_stall_ticks_o + 32'd1;
`endif
						if (row_fire_w) begin
							row_accepted_q <= 1'b1;
`ifndef SYNTHESIS
							diag_row_accept_count_o <=
								diag_row_accept_count_o + 32'd1;
`endif
						end
						if (state_ticks_remaining_q > 11'd1) begin
							state_ticks_remaining_q <= state_ticks_remaining_q - 11'd1;
						end else if (row_complete_w) begin
							row_accepted_q <= 1'b0;
							if (!row_is_last_w) begin
								row_ordinal_q <= row_ordinal_q + 4'd1;
								state_ticks_remaining_q <= ROW_TICKS;
							end else begin
								complete_object_task(class_final_q);
							end
						end else if (state_ticks_remaining_q == 11'd1) begin
							state_ticks_remaining_q <= 11'd0;
						end
					end

					default: begin
						state_q <= STATE_IDLE;
						state_ticks_remaining_q <= 11'd0;
						done_q <= 1'b0;
						retire_pending_q <= 1'b0;
						class_accepted_q <= 1'b0;
						active_setup_accepted_q <= 1'b0;
						row_accepted_q <= 1'b0;
					end
				endcase
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Y-first Object-group walker.
//
// Scan word two in descending cyclic order. Visible entries hold their geometry
// until detail starts, then words zero, one, and three complete the Object record.

module vip_xp_obj_oam_walker
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	input  wire                 start_valid_i,
	output wire                 start_ready_o,
	output wire                 start_accept_o,
	input  wire [4:0]           start_strip_i,
	input  wire [3:0]           start_epoch_i,
	input  wire [9:0]           start_first_index_i,
	input  wire [9:0]           start_final_index_i,
	input  wire [10:0]          start_entry_count_i,

	output wire                 dram_req_o,
	output wire [15:0]          dram_addr_o,
	input  wire                 dram_accept_i,
	input  wire                 dram_resp_valid_i,
	input  wire [15:0]          dram_resp_data_i,

	output wire                 class_valid_o,
	input  wire                 class_ready_i,
	output wire [9:0]           class_object_index_o,
	output wire [4:0]           class_strip_o,
	output wire [3:0]           class_epoch_o,
	output wire                 class_final_o,
	output wire                 class_appears_o,
	output wire                 class_continuation_o,
	output wire [3:0]           class_visible_rows_o,
	output wire [8:0]           class_first_screen_y_o,
	output wire [2:0]           class_first_source_row_o,
	output wire [7:0]           class_raw_jy_o,
	output wire [15:0]          class_word2_o,
	output wire                 class_unresolved_jy_o,
	output wire                 class_invalid_strip_o,

	input  wire                 detail_start_valid_i,
	output wire                 detail_start_ready_o,
	output wire                 detail_start_accept_o,
	input  wire [9:0]           detail_start_index_i,
	input  wire [3:0]           detail_start_epoch_i,

	output wire                 record_valid_o,
	input  wire                 record_ready_i,
	output wire [63:0]          record_data_o,
	output wire [9:0]           record_object_index_o,
	output wire [4:0]           record_strip_o,
	output wire [3:0]           record_epoch_o,
	output wire                 record_final_o,
	output wire                 record_continuation_o,
	output wire [3:0]           record_visible_rows_o,
	output wire [8:0]           record_first_screen_y_o,
	output wire [2:0]           record_first_source_row_o,
	output wire [7:0]           record_raw_jy_o,
	output wire                 record_unresolved_jy_o,

	output wire                 busy_o,
	output wire                 cleanup_busy_o,
	output wire                 quiescent_o,
	output wire                 terminal_will_idle_o,
	output wire                 transport_offer_valid_o,
	output wire                 transport_pending_o,
	output wire                 transport_response_capture_valid_o,
	output wire                 stale_response_discarded_o,

	output reg                  invalid_context_o,
	output reg                  context_count_mismatch_o,
	output reg                  stream_tag_error_o,
	output reg                  class_alignment_error_o,
	output reg                  detail_start_tag_mismatch_o,
	output reg                  detail_sequence_error_o,
	output reg                  transport_protocol_error_o,
	output reg                  protocol_error_o
);

	reg context_active_q;
	reg [4:0] context_strip_q;
	reg [3:0] context_epoch_q;
	reg [9:0] context_final_index_q;
	reg [9:0] scan_issue_index_q;
	reg [10:0] scan_issue_remaining_q;
	reg final_class_retired_q;
	reg abort_cleanup_q;

	reg word_offer_valid_q;
	reg [16:0] word_offer_tag_q;

	reg class_mirror_valid_q;
	reg [15:0] class_mirror_word2_q;
	reg [16:0] class_mirror_tag_q;

	// Four registers cover the bounded scan skid path without private OAM storage.
	reg [2:0] scan_fifo_count_q;
	reg [1:0] scan_fifo_head_q;
	reg [1:0] scan_fifo_tail_q;
	reg [2:0] scan_prefetch_count_q;
	reg [15:0] scan_fifo_data0_q;
	reg [15:0] scan_fifo_data1_q;
	reg [15:0] scan_fifo_data2_q;
	reg [15:0] scan_fifo_data3_q;
	reg [16:0] scan_fifo_tag0_q;
	reg [16:0] scan_fifo_tag1_q;
	reg [16:0] scan_fifo_tag2_q;
	reg [16:0] scan_fifo_tag3_q;

	reg active_valid_q;
	reg [9:0] active_index_q;
	reg [4:0] active_strip_q;
	reg [3:0] active_epoch_q;
	reg active_final_q;
	reg active_continuation_q;
	reg [3:0] active_visible_rows_q;
	reg [8:0] active_first_screen_y_q;
	reg [2:0] active_first_source_row_q;
	reg [7:0] active_raw_jy_q;
	reg [15:0] active_word2_q;
	reg active_unresolved_jy_q;

	reg detail_started_q;
	reg [1:0] detail_next_field_q;
	reg [2:0] detail_loaded_count_q;
	reg detail_word0_valid_q;
	reg detail_word1_valid_q;
	reg detail_word3_valid_q;
	reg [15:0] detail_word0_q;
	reg [15:0] detail_word1_q;
	reg [15:0] detail_word3_q;

	reg record_valid_q;
	reg [63:0] record_data_q;
	reg [9:0] record_object_index_q;
	reg [4:0] record_strip_q;
	reg [3:0] record_epoch_q;
	reg record_final_q;
	reg record_continuation_q;
	reg [3:0] record_visible_rows_q;
	reg [8:0] record_first_screen_y_q;
	reg [2:0] record_first_source_row_q;
	reg [7:0] record_raw_jy_q;
	reg record_unresolved_jy_q;

	wire [9:0] start_span_w =
		start_first_index_i - start_final_index_i;
	wire [10:0] start_expected_count_w =
		{1'b0, start_span_w} + 11'd1;
	wire start_count_valid_w =
		(start_entry_count_i != 11'd0) &&
		(start_entry_count_i <= 11'd1024);

	wire streamer_word_accept_w;
	wire streamer_result_valid_w;
	wire streamer_result_ready_w;
	wire [15:0] streamer_result_data_w;
	wire [16:0] streamer_result_tag_w;
	wire streamer_busy_w;
	wire streamer_cleanup_busy_w;
	wire streamer_offer_valid_w;
	wire streamer_pending_w;
	wire streamer_response_capture_valid_w;
	wire streamer_stale_discard_w;
	wire streamer_accept_without_request_w;
	wire streamer_unowned_response_w;
	wire streamer_capture_overflow_w;
	wire streamer_pending_overlap_w;

	wire classifier_input_valid_w;
	wire classifier_input_accept_w;
	wire classifier_result_valid_w;
	wire classifier_result_ready_w;
	wire [9:0] classifier_index_w;
	wire [4:0] classifier_strip_w;
	wire [7:0] classifier_raw_jy_w;
	wire classifier_final_w;
	wire [3:0] classifier_epoch_w;
	wire classifier_appears_w;
	wire classifier_continuation_w;
	wire [3:0] classifier_visible_rows_w;
	wire [8:0] classifier_first_screen_y_w;
	wire [2:0] classifier_first_source_row_w;
	wire classifier_unresolved_jy_w;
	wire classifier_invalid_strip_w;

	wire record_fire_w = ce_i && record_valid_o && record_ready_i;
	wire active_slot_available_w = !active_valid_q || record_fire_w;
	wire class_payload_aligned_w = class_mirror_valid_q &&
		(class_mirror_tag_q[16:13] == classifier_epoch_w) &&
		(class_mirror_tag_q[12:3] == classifier_index_w) &&
		(class_mirror_tag_q[2:0] == 3'b101) &&
		(class_mirror_word2_q[7:0] == classifier_raw_jy_w);
	wire class_accept_w = ce_i && class_valid_o && class_ready_i;
	wire class_retire_allowed_w = class_mirror_valid_q &&
		class_payload_aligned_w &&
		(!classifier_appears_w || active_slot_available_w);

	assign class_valid_o = !reset_i && !abort_i &&
		classifier_result_valid_w && class_retire_allowed_w;
	assign classifier_result_ready_w = !class_mirror_valid_q ? 1'b1 :
		(class_ready_i && class_retire_allowed_w);

	assign class_object_index_o = classifier_index_w;
	assign class_strip_o = classifier_strip_w;
	assign class_epoch_o = classifier_epoch_w;
	assign class_final_o = classifier_final_w;
	assign class_appears_o = classifier_appears_w;
	assign class_continuation_o = classifier_continuation_w;
	assign class_visible_rows_o = classifier_visible_rows_w;
	assign class_first_screen_y_o = classifier_first_screen_y_w;
	assign class_first_source_row_o = classifier_first_source_row_w;
	assign class_raw_jy_o = classifier_raw_jy_w;
	assign class_word2_o = class_mirror_word2_q;
	assign class_unresolved_jy_o = classifier_unresolved_jy_w;
	assign class_invalid_strip_o = classifier_invalid_strip_w;

	assign detail_start_ready_o = ce_i && !reset_i && !abort_i &&
		!cleanup_busy_o && active_valid_q && !detail_started_q &&
		!record_valid_q;
	assign detail_start_accept_o = detail_start_valid_i &&
		detail_start_ready_o;

	wire effective_detail_started_w =
		detail_started_q || detail_start_accept_o;
	wire [2:0] effective_detail_loaded_count_w =
		detail_start_accept_o ? 3'd0 : detail_loaded_count_q;
	wire [1:0] effective_detail_next_field_w =
		detail_start_accept_o ? 2'd0 : detail_next_field_q;
	wire detail_candidate_valid_w = effective_detail_started_w &&
		(effective_detail_loaded_count_w < 3'd3);
	wire [16:0] detail_candidate_tag_w = {
		active_epoch_q,
		active_index_q,
		effective_detail_next_field_w,
		1'b0
	};

	wire appearing_class_owns_oam_w = classifier_result_valid_w &&
		classifier_appears_w;
	wire active_class_owns_oam_w = appearing_class_owns_oam_w ||
		active_valid_q;
	wire scan_prefetch_slot_available_w =
		(scan_prefetch_count_q < 3'd4) || classifier_input_accept_w;
	wire scan_candidate_valid_w = context_active_q &&
		(scan_issue_remaining_q != 11'd0) &&
		!active_class_owns_oam_w && scan_prefetch_slot_available_w;
	wire [16:0] scan_candidate_tag_w = {
		context_epoch_q,
		scan_issue_index_q,
		2'd2,
		1'b1
	};
	wire selected_candidate_valid_w = detail_candidate_valid_w ||
		scan_candidate_valid_w;
	wire [16:0] selected_candidate_tag_w =
		detail_candidate_valid_w ? detail_candidate_tag_w :
		scan_candidate_tag_w;

	wire word_offer_fire_w = ce_i && streamer_word_accept_w;
	wire word_offer_slot_available_w = !word_offer_valid_q ||
		word_offer_fire_w;
	wire word_offer_load_w = ce_i && !reset_i && !abort_i &&
		!cleanup_busy_o && word_offer_slot_available_w &&
		selected_candidate_valid_w;
	wire scan_prefetch_push_w = word_offer_load_w &&
		!detail_candidate_valid_w;
	wire scan_prefetch_pop_w = classifier_input_accept_w;
	wire [9:0] scan_issue_index_after_w =
		scan_issue_index_q - 10'd1;
	wire [10:0] scan_issue_remaining_after_w =
		scan_issue_remaining_q - 11'd1;
	wire [2:0] detail_loaded_count_after_w =
		effective_detail_loaded_count_w + 3'd1;
	wire [1:0] detail_field_after_w =
		(effective_detail_next_field_w == 2'd0) ? 2'd1 : 2'd3;

	wire [3:0] stream_result_epoch_w =
		streamer_result_tag_w[16:13];
	wire [9:0] stream_result_index_w =
		streamer_result_tag_w[12:3];
	wire [1:0] stream_result_field_w =
		streamer_result_tag_w[2:1];
	wire stream_result_scan_w = streamer_result_tag_w[0];
	wire stream_result_context_match_w = context_active_q &&
		(stream_result_epoch_w == context_epoch_q);
	wire stream_result_scan_shape_w = stream_result_scan_w &&
		(stream_result_field_w == 2'd2);
	wire stream_result_detail_shape_w = !stream_result_scan_w &&
		((stream_result_field_w == 2'd0) ||
		 (stream_result_field_w == 2'd1) ||
		 (stream_result_field_w == 2'd3));
	wire valid_scan_result_w = stream_result_context_match_w &&
		stream_result_scan_shape_w;
	wire valid_detail_result_w = stream_result_context_match_w &&
		active_valid_q && stream_result_detail_shape_w &&
		(stream_result_epoch_w == active_epoch_q) &&
		(stream_result_index_w == active_index_q);

	wire scan_fifo_empty_w = scan_fifo_count_q == 3'd0;
	wire scan_fifo_full_w = scan_fifo_count_q == 3'd4;
	wire [15:0] scan_fifo_head_data_w =
		(scan_fifo_head_q == 2'd0) ? scan_fifo_data0_q :
		((scan_fifo_head_q == 2'd1) ? scan_fifo_data1_q :
		 ((scan_fifo_head_q == 2'd2) ? scan_fifo_data2_q :
		  scan_fifo_data3_q));
	wire [16:0] scan_fifo_head_tag_w =
		(scan_fifo_head_q == 2'd0) ? scan_fifo_tag0_q :
		((scan_fifo_head_q == 2'd1) ? scan_fifo_tag1_q :
		 ((scan_fifo_head_q == 2'd2) ? scan_fifo_tag2_q :
		  scan_fifo_tag3_q));
	wire direct_scan_available_w = streamer_result_valid_w &&
		valid_scan_result_w;
	wire scan_source_valid_w = !scan_fifo_empty_w ||
		direct_scan_available_w;
	wire [15:0] scan_source_data_w = scan_fifo_empty_w ?
		streamer_result_data_w : scan_fifo_head_data_w;
	wire [16:0] scan_source_tag_w = scan_fifo_empty_w ?
		streamer_result_tag_w : scan_fifo_head_tag_w;

	wire class_mirror_slot_available_w = !class_mirror_valid_q ||
		class_accept_w;
	assign classifier_input_valid_w = scan_source_valid_w &&
		class_mirror_slot_available_w;
	wire scan_fifo_pop_w = !scan_fifo_empty_w &&
		classifier_input_accept_w;
	wire scan_fifo_capture_ready_w = !scan_fifo_full_w ||
		scan_fifo_pop_w;
	assign streamer_result_ready_w = !reset_i && !abort_i &&
		streamer_result_valid_w &&
		(!valid_scan_result_w || scan_fifo_capture_ready_w);
	wire streamer_result_fire_w = ce_i && streamer_result_valid_w &&
		streamer_result_ready_w;
	wire direct_scan_fire_w = scan_fifo_empty_w &&
		classifier_input_accept_w && streamer_result_fire_w &&
		valid_scan_result_w;
	wire scan_fifo_push_w = streamer_result_fire_w &&
		valid_scan_result_w && !direct_scan_fire_w;
	wire detail_result_fire_w = streamer_result_fire_w &&
		valid_detail_result_w;

	wire detail_words_complete_w = detail_word0_valid_q &&
		detail_word1_valid_q && detail_word3_valid_q;
	wire terminal_class_fire_w = class_accept_w &&
		classifier_final_w && !classifier_appears_w &&
		(!active_valid_q || record_fire_w) && scan_fifo_empty_w &&
		(scan_prefetch_count_q == 3'd0);
	wire terminal_record_fire_w = record_fire_w &&
		(final_class_retired_q ||
		 (class_accept_w && classifier_final_w)) &&
		!(class_accept_w && classifier_appears_w) && scan_fifo_empty_w &&
		(scan_prefetch_count_q == 3'd0);
	wire context_drained_w = context_active_q &&
		final_class_retired_q &&
		(scan_issue_remaining_q == 11'd0) &&
		!word_offer_valid_q && !streamer_busy_w && scan_fifo_empty_w &&
		(scan_prefetch_count_q == 3'd0) &&
		!classifier_result_valid_w && !class_mirror_valid_q &&
		!active_valid_q && !record_valid_q;
	wire local_cleanup_drained_w = !context_active_q &&
		!word_offer_valid_q && !streamer_busy_w && scan_fifo_empty_w &&
		(scan_prefetch_count_q == 3'd0) &&
		!classifier_result_valid_w && !class_mirror_valid_q &&
		!active_valid_q && !record_valid_q;

	assign start_ready_o = ce_i && !reset_i && !abort_i &&
		!cleanup_busy_o && !context_active_q &&
		!word_offer_valid_q && !streamer_busy_w && scan_fifo_empty_w &&
		(scan_prefetch_count_q == 3'd0) &&
		!classifier_result_valid_w && !class_mirror_valid_q &&
		!active_valid_q && !record_valid_q;
	assign start_accept_o = start_valid_i && start_ready_o;

	assign record_valid_o = !reset_i && !abort_i && record_valid_q;
	assign record_data_o = record_data_q;
	assign record_object_index_o = record_object_index_q;
	assign record_strip_o = record_strip_q;
	assign record_epoch_o = record_epoch_q;
	assign record_final_o = record_final_q;
	assign record_continuation_o = record_continuation_q;
	assign record_visible_rows_o = record_visible_rows_q;
	assign record_first_screen_y_o = record_first_screen_y_q;
	assign record_first_source_row_o = record_first_source_row_q;
	assign record_raw_jy_o = record_raw_jy_q;
	assign record_unresolved_jy_o = record_unresolved_jy_q;

	// Exclude abort_cleanup_q from walker ownership to avoid a self-held interlock.
	wire local_owner_busy_w = context_active_q || word_offer_valid_q ||
		streamer_busy_w || classifier_result_valid_w ||
		!scan_fifo_empty_w || class_mirror_valid_q || active_valid_q ||
		record_valid_q || (scan_prefetch_count_q != 3'd0);
	assign cleanup_busy_o = abort_cleanup_q ||
		streamer_cleanup_busy_w;
	assign busy_o = local_owner_busy_w || cleanup_busy_o;
	assign quiescent_o = !reset_i && !abort_i && !busy_o &&
		!cleanup_busy_o;
	assign terminal_will_idle_o = !reset_i && !abort_i &&
		(terminal_class_fire_w || terminal_record_fire_w);
	assign transport_offer_valid_o = streamer_offer_valid_w ||
		word_offer_valid_q;
	assign transport_pending_o = streamer_pending_w;
	assign transport_response_capture_valid_o =
		streamer_response_capture_valid_w;
	assign stale_response_discarded_o = streamer_stale_discard_w;

	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_obj_oam_streamer u_streamer
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.word_valid_i(word_offer_valid_q),
		.word_ready_o(),
		.word_accept_o(streamer_word_accept_w),
		.word_tag_i(word_offer_tag_q),
		.dram_req_o(dram_req_o),
		.dram_addr_o(dram_addr_o),
		.dram_accept_i(dram_accept_i),
		.dram_resp_valid_i(dram_resp_valid_i),
		.dram_resp_data_i(dram_resp_data_i),
		.result_valid_o(streamer_result_valid_w),
		.result_ready_i(streamer_result_ready_w),
		.result_data_o(streamer_result_data_w),
		.result_tag_o(streamer_result_tag_w),
		.busy_o(streamer_busy_w),
		.cleanup_busy_o(streamer_cleanup_busy_w),
		.offer_valid_o(streamer_offer_valid_w),
		.read_pending_o(streamer_pending_w),
		.response_capture_valid_o(
			streamer_response_capture_valid_w),
		.stale_response_discarded_o(streamer_stale_discard_w),
		.accept_without_request_o(
			streamer_accept_without_request_w),
		.unowned_response_o(streamer_unowned_response_w),
		.response_capture_overflow_o(
			streamer_capture_overflow_w),
		.pending_owner_overlap_o(streamer_pending_overlap_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	vip_xp_obj_vertical_classify u_vertical_classify
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.classify_valid_i(classifier_input_valid_w),
		.classify_ready_o(),
		.classify_accept_o(classifier_input_accept_w),
		.object_index_i(scan_source_tag_w[12:3]),
		.strip_i(context_strip_q),
		.raw_jy_i(scan_source_data_w[7:0]),
		.final_i(scan_source_tag_w[12:3] == context_final_index_q),
		.epoch_i(scan_source_tag_w[16:13]),
		.result_valid_o(classifier_result_valid_w),
		.result_ready_i(classifier_result_ready_w),
		.object_index_o(classifier_index_w),
		.strip_o(classifier_strip_w),
		.raw_jy_o(classifier_raw_jy_w),
		.final_o(classifier_final_w),
		.epoch_o(classifier_epoch_w),
		.appears_o(classifier_appears_w),
		.continuation_o(classifier_continuation_w),
		.visible_rows_o(classifier_visible_rows_w),
		.first_screen_y_o(classifier_first_screen_y_w),
		.first_source_row_o(classifier_first_source_row_w),
		.unresolved_jy_o(classifier_unresolved_jy_w),
		.invalid_strip_o(classifier_invalid_strip_w)
	);

	always @(posedge clk_i) begin
		if (reset_i) begin
			context_active_q <= 1'b0;
			context_strip_q <= 5'd0;
			context_epoch_q <= 4'd0;
			context_final_index_q <= 10'd0;
			scan_issue_index_q <= 10'd0;
			scan_issue_remaining_q <= 11'd0;
			final_class_retired_q <= 1'b0;
			abort_cleanup_q <= 1'b0;
			word_offer_valid_q <= 1'b0;
			word_offer_tag_q <= 17'd0;
			class_mirror_valid_q <= 1'b0;
			class_mirror_word2_q <= 16'd0;
			class_mirror_tag_q <= 17'd0;
			scan_fifo_count_q <= 3'd0;
			scan_fifo_head_q <= 2'd0;
			scan_fifo_tail_q <= 2'd0;
			scan_prefetch_count_q <= 3'd0;
			scan_fifo_data0_q <= 16'd0;
			scan_fifo_data1_q <= 16'd0;
			scan_fifo_data2_q <= 16'd0;
			scan_fifo_data3_q <= 16'd0;
			scan_fifo_tag0_q <= 17'd0;
			scan_fifo_tag1_q <= 17'd0;
			scan_fifo_tag2_q <= 17'd0;
			scan_fifo_tag3_q <= 17'd0;
			active_valid_q <= 1'b0;
			active_index_q <= 10'd0;
			active_strip_q <= 5'd0;
			active_epoch_q <= 4'd0;
			active_final_q <= 1'b0;
			active_continuation_q <= 1'b0;
			active_visible_rows_q <= 4'd0;
			active_first_screen_y_q <= 9'd0;
			active_first_source_row_q <= 3'd0;
			active_raw_jy_q <= 8'd0;
			active_word2_q <= 16'd0;
			active_unresolved_jy_q <= 1'b0;
			detail_started_q <= 1'b0;
			detail_next_field_q <= 2'd0;
			detail_loaded_count_q <= 3'd0;
			detail_word0_valid_q <= 1'b0;
			detail_word1_valid_q <= 1'b0;
			detail_word3_valid_q <= 1'b0;
			detail_word0_q <= 16'd0;
			detail_word1_q <= 16'd0;
			detail_word3_q <= 16'd0;
			record_valid_q <= 1'b0;
			record_data_q <= 64'd0;
			record_object_index_q <= 10'd0;
			record_strip_q <= 5'd0;
			record_epoch_q <= 4'd0;
			record_final_q <= 1'b0;
			record_continuation_q <= 1'b0;
			record_visible_rows_q <= 4'd0;
			record_first_screen_y_q <= 9'd0;
			record_first_source_row_q <= 3'd0;
			record_raw_jy_q <= 8'd0;
			record_unresolved_jy_q <= 1'b0;
			invalid_context_o <= 1'b0;
			context_count_mismatch_o <= 1'b0;
			stream_tag_error_o <= 1'b0;
			class_alignment_error_o <= 1'b0;
			detail_start_tag_mismatch_o <= 1'b0;
			detail_sequence_error_o <= 1'b0;
			transport_protocol_error_o <= 1'b0;
			protocol_error_o <= 1'b0;
		end else begin
			if (abort_i) begin
				// While abort is held, wait only for real accepted ownership to drain.
				abort_cleanup_q <= local_owner_busy_w;
				context_active_q <= 1'b0;
				scan_issue_remaining_q <= 11'd0;
				final_class_retired_q <= 1'b0;
				word_offer_valid_q <= 1'b0;
				class_mirror_valid_q <= 1'b0;
				scan_fifo_count_q <= 3'd0;
				scan_fifo_head_q <= 2'd0;
				scan_fifo_tail_q <= 2'd0;
				scan_prefetch_count_q <= 3'd0;
				active_valid_q <= 1'b0;
				detail_started_q <= 1'b0;
				detail_loaded_count_q <= 3'd0;
				detail_word0_valid_q <= 1'b0;
				detail_word1_valid_q <= 1'b0;
				detail_word3_valid_q <= 1'b0;
				record_valid_q <= 1'b0;
			end else if (ce_i) begin
				if (abort_cleanup_q && local_cleanup_drained_w) begin
					abort_cleanup_q <= 1'b0;
				end

				if (start_accept_o) begin
					context_active_q <= 1'b1;
					context_strip_q <= start_strip_i;
					context_epoch_q <= start_epoch_i;
					context_final_index_q <=
						start_final_index_i;
					scan_issue_index_q <= start_first_index_i;
					scan_issue_remaining_q <=
						(start_count_valid_w &&
						 (start_entry_count_i ==
						  start_expected_count_w)) ?
						start_entry_count_i : start_expected_count_w;
					final_class_retired_q <= 1'b0;
					if (!start_count_valid_w) begin
						invalid_context_o <= 1'b1;
						protocol_error_o <= 1'b1;
					end
					if (start_count_valid_w &&
						(start_entry_count_i !=
						 start_expected_count_w)) begin
						context_count_mismatch_o <= 1'b1;
						protocol_error_o <= 1'b1;
					end
				end

				if (word_offer_load_w) begin
					word_offer_valid_q <= 1'b1;
					word_offer_tag_q <= selected_candidate_tag_w;
					if (detail_candidate_valid_w) begin
						detail_loaded_count_q <=
							detail_loaded_count_after_w;
						detail_next_field_q <=
							detail_field_after_w;
					end else begin
						scan_issue_index_q <=
							scan_issue_index_after_w;
						scan_issue_remaining_q <=
							scan_issue_remaining_after_w;
					end
				end else if (word_offer_fire_w) begin
					word_offer_valid_q <= 1'b0;
				end

				if (scan_fifo_push_w) begin
					case (scan_fifo_tail_q)
						2'd0: begin
							scan_fifo_data0_q <= streamer_result_data_w;
							scan_fifo_tag0_q <= streamer_result_tag_w;
						end
						2'd1: begin
							scan_fifo_data1_q <= streamer_result_data_w;
							scan_fifo_tag1_q <= streamer_result_tag_w;
						end
						2'd2: begin
							scan_fifo_data2_q <= streamer_result_data_w;
							scan_fifo_tag2_q <= streamer_result_tag_w;
						end
						default: begin
							scan_fifo_data3_q <= streamer_result_data_w;
							scan_fifo_tag3_q <= streamer_result_tag_w;
						end
					endcase
				end
				case ({scan_fifo_push_w, scan_fifo_pop_w})
					2'b10: begin
						scan_fifo_count_q <= scan_fifo_count_q + 3'd1;
						scan_fifo_tail_q <= scan_fifo_tail_q + 2'd1;
					end
					2'b01: begin
						scan_fifo_count_q <= scan_fifo_count_q - 3'd1;
						scan_fifo_head_q <= scan_fifo_head_q + 2'd1;
					end
					2'b11: begin
						scan_fifo_head_q <= scan_fifo_head_q + 2'd1;
						scan_fifo_tail_q <= scan_fifo_tail_q + 2'd1;
					end
					default: begin
						scan_fifo_count_q <= scan_fifo_count_q;
					end
				endcase
				case ({scan_prefetch_push_w, scan_prefetch_pop_w})
					2'b10: scan_prefetch_count_q <=
						scan_prefetch_count_q + 3'd1;
					2'b01: scan_prefetch_count_q <=
						scan_prefetch_count_q - 3'd1;
					default: scan_prefetch_count_q <=
						scan_prefetch_count_q;
				endcase

				if (classifier_input_accept_w) begin
					class_mirror_valid_q <= 1'b1;
					class_mirror_word2_q <= scan_source_data_w;
					class_mirror_tag_q <= scan_source_tag_w;
				end else if (class_accept_w) begin
					class_mirror_valid_q <= 1'b0;
				end

				if (class_mirror_valid_q !=
					classifier_result_valid_w) begin
					class_alignment_error_o <= 1'b1;
					protocol_error_o <= 1'b1;
					if (class_mirror_valid_q &&
						!classifier_result_valid_w) begin
						class_mirror_valid_q <= 1'b0;
					end
				end else if (class_mirror_valid_q &&
					!class_payload_aligned_w) begin
					class_alignment_error_o <= 1'b1;
					protocol_error_o <= 1'b1;
				end

				if (class_accept_w) begin
					if (classifier_final_w) begin
						final_class_retired_q <= 1'b1;
					end
					if (classifier_appears_w) begin
						active_valid_q <= 1'b1;
						active_index_q <= classifier_index_w;
						active_strip_q <= classifier_strip_w;
						active_epoch_q <= classifier_epoch_w;
						active_final_q <= classifier_final_w;
						active_continuation_q <=
							classifier_continuation_w;
						active_visible_rows_q <=
							classifier_visible_rows_w;
						active_first_screen_y_q <=
							classifier_first_screen_y_w;
						active_first_source_row_q <=
							classifier_first_source_row_w;
						active_raw_jy_q <= classifier_raw_jy_w;
						active_word2_q <= class_mirror_word2_q;
						active_unresolved_jy_q <=
							classifier_unresolved_jy_w;
						detail_started_q <= 1'b0;
						detail_next_field_q <= 2'd0;
						detail_loaded_count_q <= 3'd0;
						detail_word0_valid_q <= 1'b0;
						detail_word1_valid_q <= 1'b0;
						detail_word3_valid_q <= 1'b0;
					end
				end

				if (detail_start_accept_o) begin
					detail_started_q <= 1'b1;
					if (!(word_offer_load_w &&
						detail_candidate_valid_w)) begin
						detail_next_field_q <= 2'd0;
						detail_loaded_count_q <= 3'd0;
					end
					if ((detail_start_index_i != active_index_q) ||
						(detail_start_epoch_i != active_epoch_q)) begin
						detail_start_tag_mismatch_o <= 1'b1;
						protocol_error_o <= 1'b1;
					end
				end

				if (detail_result_fire_w) begin
					case (stream_result_field_w)
						2'd0: begin
							if (detail_word0_valid_q) begin
								detail_sequence_error_o <= 1'b1;
								protocol_error_o <= 1'b1;
							end else begin
								detail_word0_valid_q <= 1'b1;
								detail_word0_q <=
									streamer_result_data_w;
							end
						end
						2'd1: begin
							if (detail_word1_valid_q) begin
								detail_sequence_error_o <= 1'b1;
								protocol_error_o <= 1'b1;
							end else begin
								detail_word1_valid_q <= 1'b1;
								detail_word1_q <=
									streamer_result_data_w;
							end
						end
						default: begin
							if (detail_word3_valid_q) begin
								detail_sequence_error_o <= 1'b1;
								protocol_error_o <= 1'b1;
							end else begin
								detail_word3_valid_q <= 1'b1;
								detail_word3_q <=
									streamer_result_data_w;
							end
						end
					endcase
				end else if (streamer_result_fire_w &&
					!valid_scan_result_w) begin
					stream_tag_error_o <= 1'b1;
					protocol_error_o <= 1'b1;
				end

				if (detail_words_complete_w && !record_valid_q) begin
					record_valid_q <= 1'b1;
					record_data_q <= {
						detail_word3_q,
						active_word2_q,
						detail_word1_q,
						detail_word0_q
					};
					record_object_index_q <= active_index_q;
					record_strip_q <= active_strip_q;
					record_epoch_q <= active_epoch_q;
					record_final_q <= active_final_q;
					record_continuation_q <=
						active_continuation_q;
					record_visible_rows_q <=
						active_visible_rows_q;
					record_first_screen_y_q <=
						active_first_screen_y_q;
					record_first_source_row_q <=
						active_first_source_row_q;
					record_raw_jy_q <= active_raw_jy_q;
					record_unresolved_jy_q <=
						active_unresolved_jy_q;
				end

				if (record_fire_w) begin
					record_valid_q <= 1'b0;
					if (!(class_accept_w && classifier_appears_w)) begin
						active_valid_q <= 1'b0;
						detail_started_q <= 1'b0;
						detail_loaded_count_q <= 3'd0;
						detail_word0_valid_q <= 1'b0;
						detail_word1_valid_q <= 1'b0;
						detail_word3_valid_q <= 1'b0;
					end
				end

				if (terminal_will_idle_o) begin
					context_active_q <= 1'b0;
					final_class_retired_q <= 1'b0;
				end else if (context_drained_w) begin
					context_active_q <= 1'b0;
				end

				if (streamer_accept_without_request_w ||
					streamer_unowned_response_w ||
					streamer_capture_overflow_w ||
					streamer_pending_overlap_w) begin
					transport_protocol_error_o <= 1'b1;
					protocol_error_o <= 1'b1;
				end
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Single-entry OAM halfword transport.
//
// Tag order is {epoch, object index, field, scan}. Hold accepted tags through
// response. Abort drops offers and drains accepted reads.

module vip_xp_obj_oam_streamer
(
	input  wire         clk_i,
	input  wire         reset_i,
	input  wire         ce_i,
	input  wire         abort_i,

	input  wire         word_valid_i,
	output wire         word_ready_o,
	output wire         word_accept_o,
	input  wire [16:0]  word_tag_i,

	output wire         dram_req_o,
	output wire [15:0]  dram_addr_o,
	input  wire         dram_accept_i,
	input  wire         dram_resp_valid_i,
	input  wire [15:0]  dram_resp_data_i,

	output wire         result_valid_o,
	input  wire         result_ready_i,
	output wire [15:0]  result_data_o,
	output wire [16:0]  result_tag_o,

	output wire         busy_o,
	output wire         cleanup_busy_o,
	output wire         offer_valid_o,
	output wire         read_pending_o,
	output wire         response_capture_valid_o,
	output reg          stale_response_discarded_o,
	output reg          accept_without_request_o,
	output reg          unowned_response_o,
	output reg          response_capture_overflow_o,
	output reg          pending_owner_overlap_o
);

	reg offer_valid_q;
	reg [16:0] offer_tag_q;

	reg pending_q;
	reg pending_stale_q;
	reg [16:0] pending_tag_q;

	reg response_capture_valid_q;
	reg [15:0] response_capture_data_q;

	reg result_valid_q;
	reg [15:0] result_data_q;
	reg [16:0] result_tag_q;

	wire result_fire_w = ce_i && result_valid_o && result_ready_i;
	wire result_slot_available_w = !result_valid_q || result_fire_w;
	wire response_available_w = response_capture_valid_q ||
		dram_resp_valid_i;
	wire [15:0] response_data_w = response_capture_valid_q ?
		response_capture_data_q : dram_resp_data_i;
	wire pending_abort_w = pending_stale_q || abort_i;
	wire live_response_fire_w = ce_i && pending_q &&
		!pending_abort_w && response_available_w &&
		result_slot_available_w;
	wire stale_response_fire_w = ce_i && pending_q &&
		pending_abort_w && response_available_w;
	wire request_window_w = (!pending_q && !response_capture_valid_q) ||
		live_response_fire_w;
	// Keep request selection independent of returned acceptance.
	wire selected_live_word_w = !offer_valid_q && ce_i && word_valid_i;
	wire selected_word_valid_w = offer_valid_q || selected_live_word_w;
	wire [16:0] selected_word_tag_w = offer_valid_q ?
		offer_tag_q : word_tag_i;
	wire request_accept_fire_w = ce_i && dram_req_o && dram_accept_i;
	wire offer_request_fire_w = request_accept_fire_w && offer_valid_q;
	wire live_request_fire_w = request_accept_fire_w && !offer_valid_q;
	wire offer_replacement_window_w = ce_i && !reset_i && !abort_i &&
		!cleanup_busy_o && offer_valid_q && request_window_w &&
		dram_accept_i;

	assign cleanup_busy_o = pending_q && pending_abort_w;
	assign word_ready_o = ce_i && !reset_i && !abort_i &&
		!cleanup_busy_o &&
		(!offer_valid_q || offer_replacement_window_w);
	assign word_accept_o = word_valid_i && word_ready_o;

	assign dram_req_o = !reset_i && !abort_i && !cleanup_busy_o &&
		request_window_w && selected_word_valid_w;
	assign dram_addr_o = {4'hf, selected_word_tag_w[12:3],
		selected_word_tag_w[2:1]};

	assign result_valid_o = !reset_i && !abort_i && result_valid_q;
	assign result_data_o = result_data_q;
	assign result_tag_o = result_tag_q;

	assign busy_o = offer_valid_q || pending_q ||
		response_capture_valid_q || result_valid_q;
	assign offer_valid_o = offer_valid_q;
	assign read_pending_o = pending_q;
	assign response_capture_valid_o = response_capture_valid_q;

	always @(posedge clk_i) begin
		if (reset_i) begin
			offer_valid_q <= 1'b0;
			offer_tag_q <= 17'd0;
			pending_q <= 1'b0;
			pending_stale_q <= 1'b0;
			pending_tag_q <= 17'd0;
			response_capture_valid_q <= 1'b0;
			response_capture_data_q <= 16'd0;
			result_valid_q <= 1'b0;
			result_data_q <= 16'd0;
			result_tag_q <= 17'd0;
			stale_response_discarded_o <= 1'b0;
			accept_without_request_o <= 1'b0;
			unowned_response_o <= 1'b0;
			response_capture_overflow_o <= 1'b0;
			pending_owner_overlap_o <= 1'b0;
		end else begin
			stale_response_discarded_o <= 1'b0;

			// Capture responses on the raw clock.
			if (dram_resp_valid_i) begin
				if (!pending_q) begin
					unowned_response_o <= 1'b1;
				end else if (response_capture_valid_q) begin
					if (!live_response_fire_w &&
						!stale_response_fire_w) begin
						response_capture_overflow_o <= 1'b1;
					end
				end else if (!live_response_fire_w &&
					!stale_response_fire_w) begin
					response_capture_valid_q <= 1'b1;
					response_capture_data_q <= dram_resp_data_i;
				end
			end

			// Abort may change ownership while CE is paused.
			if (abort_i) begin
				offer_valid_q <= 1'b0;
				result_valid_q <= 1'b0;
				if (pending_q) begin
					pending_stale_q <= 1'b1;
				end else begin
					pending_stale_q <= 1'b0;
				end
			end else if (ce_i) begin
				// The offer slot supports fall-through and same-edge replacement.
				if (offer_valid_q) begin
					if (offer_request_fire_w) begin
						if (word_accept_o) begin
							offer_valid_q <= 1'b1;
							offer_tag_q <= word_tag_i;
						end else begin
							offer_valid_q <= 1'b0;
						end
					end
				end else if (word_accept_o) begin
					if (!live_request_fire_w) begin
						offer_valid_q <= 1'b1;
						offer_tag_q <= word_tag_i;
					end
				end
			end

			if (ce_i) begin
				if (dram_accept_i && !dram_req_o) begin
					accept_without_request_o <= 1'b1;
				end

				if (stale_response_fire_w) begin
					pending_q <= 1'b0;
					pending_stale_q <= 1'b0;
					pending_tag_q <= 17'd0;
					response_capture_valid_q <= 1'b0;
					stale_response_discarded_o <= 1'b1;
				end else if (live_response_fire_w) begin
					pending_q <= 1'b0;
					pending_stale_q <= 1'b0;
					pending_tag_q <= 17'd0;
					response_capture_valid_q <= 1'b0;
					result_valid_q <= 1'b1;
					result_data_q <= response_data_w;
					result_tag_q <= pending_tag_q;
				end else if (result_fire_w) begin
					result_valid_q <= 1'b0;
				end

				if (!abort_i && request_accept_fire_w) begin
					if (pending_q && !live_response_fire_w &&
						!stale_response_fire_w) begin
						pending_owner_overlap_o <= 1'b1;
					end
					pending_q <= 1'b1;
					pending_stale_q <= 1'b0;
					pending_tag_q <= selected_word_tag_w;
				end
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Held Object vertical classifier.
//
// Intersect JY with one eight-row strip. E0-F8 produces no visible rows and is
// flagged. Hold each result until accepted.

module vip_xp_obj_vertical_classify
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	input  wire                 classify_valid_i,
	output wire                 classify_ready_o,
	output wire                 classify_accept_o,
	input  wire [9:0]           object_index_i,
	input  wire [4:0]           strip_i,
	input  wire [7:0]           raw_jy_i,
	input  wire                 final_i,
	input  wire [3:0]           epoch_i,

	output wire                 result_valid_o,
	input  wire                 result_ready_i,
	output reg  [9:0]           object_index_o,
	output reg  [4:0]           strip_o,
	output reg  [7:0]           raw_jy_o,
	output reg                  final_o,
	output reg  [3:0]           epoch_o,
	output reg                  appears_o,
	output reg                  continuation_o,
	output reg  [3:0]           visible_rows_o,
	output reg  [8:0]           first_screen_y_o,
	output reg  [2:0]           first_source_row_o,
	output reg                  unresolved_jy_o,
	output reg                  invalid_strip_o
);

	reg result_valid_q;

	// Silicon unknown: JY E0-F8 is undefined. Treat it as off-screen and flag it.
	wire unresolved_jy_w =
		(raw_jy_i >= 8'he0) && (raw_jy_i <= 8'hf8);
	wire negative_tail_w = raw_jy_i >= 8'hf9;
	wire invalid_strip_w = strip_i >= 5'd28;

	// Only JY F9-FF sign-extends to -7..-1.
	wire signed [10:0] object_top_w = negative_tail_w ?
		$signed({3'b111, raw_jy_i}) :
		$signed({3'b000, raw_jy_i});
	wire signed [10:0] object_end_w = object_top_w + 11'sd8;

	wire [8:0] strip_start_unsigned_w =
		{1'b0, strip_i, 3'b000};
	wire signed [10:0] strip_start_w =
		$signed({2'b00, strip_start_unsigned_w});
	wire signed [10:0] strip_end_w = strip_start_w + 11'sd8;

	wire signed [10:0] intersection_start_w =
		(object_top_w > strip_start_w) ? object_top_w : strip_start_w;
	wire signed [10:0] intersection_end_w =
		(object_end_w < strip_end_w) ? object_end_w : strip_end_w;
	wire resolved_appears_w = !unresolved_jy_w && !invalid_strip_w &&
		(intersection_start_w < intersection_end_w);
	wire resolved_continuation_w = resolved_appears_w &&
		(object_top_w < strip_start_w);

	wire signed [10:0] visible_delta_w =
		intersection_end_w - intersection_start_w;
	wire signed [10:0] source_delta_w =
		intersection_start_w - object_top_w;
	wire visible_delta_high_w = |visible_delta_w[10:4];
	wire source_delta_high_w = |source_delta_w[10:3];
	wire screen_y_high_w = |intersection_start_w[10:9];

	wire [3:0] resolved_visible_rows_w =
		resolved_appears_w && !visible_delta_high_w ?
		visible_delta_w[3:0] : 4'd0;
	wire [8:0] resolved_first_screen_y_w =
		resolved_appears_w && !screen_y_high_w ?
		intersection_start_w[8:0] : 9'd0;
	wire [2:0] resolved_first_source_row_w =
		resolved_appears_w && !source_delta_high_w ?
		source_delta_w[2:0] : 3'd0;

	wire result_fire_w = ce_i && result_valid_o && result_ready_i;

	assign classify_ready_o = ce_i && !reset_i && !abort_i &&
		(!result_valid_q || result_ready_i);
	assign classify_accept_o = classify_valid_i && classify_ready_o;
	assign result_valid_o = !reset_i && !abort_i && result_valid_q;

	always @(posedge clk_i) begin
		if (reset_i) begin
			result_valid_q <= 1'b0;
			object_index_o <= 10'd0;
			strip_o <= 5'd0;
			raw_jy_o <= 8'd0;
			final_o <= 1'b0;
			epoch_o <= 4'd0;
			appears_o <= 1'b0;
			continuation_o <= 1'b0;
			visible_rows_o <= 4'd0;
			first_screen_y_o <= 9'd0;
			first_source_row_o <= 3'd0;
			unresolved_jy_o <= 1'b0;
			invalid_strip_o <= 1'b0;
		end else if (abort_i) begin
			result_valid_q <= 1'b0;
		end else if (ce_i) begin
			if (classify_accept_o) begin
				result_valid_q <= 1'b1;
				object_index_o <= object_index_i;
				strip_o <= strip_i;
				raw_jy_o <= raw_jy_i;
				final_o <= final_i;
				epoch_o <= epoch_i;
				appears_o <= resolved_appears_w;
				continuation_o <= resolved_continuation_w;
				visible_rows_o <= resolved_visible_rows_w;
				first_screen_y_o <=
					resolved_first_screen_y_w;
				first_source_row_o <=
					resolved_first_source_row_w;
				unresolved_jy_o <= unresolved_jy_w;
				invalid_strip_o <= invalid_strip_w;
			end else if (result_fire_w) begin
				result_valid_q <= 1'b0;
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Held Object record decoder.
//
// Words zero through three occupy successive 16-bit slices. Hold decoded fields
// until retire or replacement. Raw abort clears them even while CE is low.

module vip_xp_obj_decode
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	input  wire                 descriptor_valid_i,
	output wire                 descriptor_ready_o,
	output wire                 descriptor_accept_o,
	input  wire [63:0]          descriptor_i,

	output wire                 record_valid_o,
	input  wire                 record_ready_i,
	output reg  signed [9:0]    jx_o,
	output reg  signed [9:0]    jp_o,
	output reg  [7:0]           jy_raw_o,
	output reg                  jlon_o,
	output reg                  jron_o,
	output reg  [1:0]           jplt_select_o,
	output reg                  hflip_o,
	output reg                  vflip_o,
	output reg  [10:0]          jca_o,
	output reg  signed [11:0]   left_base_o,
	output reg  signed [11:0]   right_base_o,
	output reg                  jy_unresolved_o,
	output reg                  ignored_bits_nonzero_o
);

	reg record_valid_q;

	wire signed [9:0] descriptor_jx_w = descriptor_i[9:0];
	wire signed [9:0] descriptor_jp_w = descriptor_i[25:16];
	wire [7:0] descriptor_jy_raw_w = descriptor_i[39:32];
	wire signed [11:0] descriptor_jx_extended_w =
		{{2{descriptor_jx_w[9]}}, descriptor_jx_w};
	wire signed [11:0] descriptor_jp_extended_w =
		{{2{descriptor_jp_w[9]}}, descriptor_jp_w};
	wire signed [11:0] descriptor_left_base_w =
		descriptor_jx_extended_w - descriptor_jp_extended_w;
	wire signed [11:0] descriptor_right_base_w =
		descriptor_jx_extended_w + descriptor_jp_extended_w;
	wire descriptor_jy_unresolved_w =
		(descriptor_jy_raw_w >= 8'he0) &&
		(descriptor_jy_raw_w <= 8'hf8);
	wire descriptor_ignored_bits_nonzero_w =
		|{descriptor_i[15:10], descriptor_i[29:26],
			descriptor_i[47:40], descriptor_i[59]};
	wire record_fire_w = ce_i && record_valid_o && record_ready_i;

	assign descriptor_ready_o = ce_i && !reset_i && !abort_i &&
		(!record_valid_q || record_ready_i);
	assign descriptor_accept_o = descriptor_valid_i &&
		descriptor_ready_o;
	assign record_valid_o = !reset_i && !abort_i && record_valid_q;

	always @(posedge clk_i) begin
		if (reset_i) begin
			record_valid_q <= 1'b0;
			jx_o <= 10'sd0;
			jp_o <= 10'sd0;
			jy_raw_o <= 8'd0;
			jlon_o <= 1'b0;
			jron_o <= 1'b0;
			jplt_select_o <= 2'd0;
			hflip_o <= 1'b0;
			vflip_o <= 1'b0;
			jca_o <= 11'd0;
			left_base_o <= 12'sd0;
			right_base_o <= 12'sd0;
			jy_unresolved_o <= 1'b0;
			ignored_bits_nonzero_o <= 1'b0;
		end else if (abort_i) begin
			record_valid_q <= 1'b0;
		end else if (ce_i) begin
			if (descriptor_accept_o) begin
				record_valid_q <= 1'b1;
				jx_o <= descriptor_jx_w;
				jp_o <= descriptor_jp_w;
				jy_raw_o <= descriptor_jy_raw_w;
				jlon_o <= descriptor_i[31];
				jron_o <= descriptor_i[30];
				jplt_select_o <= descriptor_i[63:62];
				hflip_o <= descriptor_i[61];
				vflip_o <= descriptor_i[60];
				jca_o <= descriptor_i[58:48];
				left_base_o <= descriptor_left_base_w;
				right_base_o <= descriptor_right_base_w;
				jy_unresolved_o <= descriptor_jy_unresolved_w;
				ignored_bits_nonzero_o <=
					descriptor_ignored_bits_nonzero_w;
			end else if (record_fire_w) begin
				record_valid_q <= 1'b0;
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Object character-row transport and shared decode pipeline.
//
// Each visible row makes one held VRM read. Keep ownership through response,
// then send it through the shared character decoder and Object row-token block.

module vip_xp_obj_char_pipeline
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	// Held row prefetch context.
	input  wire                 context_valid_i,
	output wire                 context_ready_o,
	output wire                 context_accept_o,
	input  wire [3:0]           context_epoch_i,
	input  wire [9:0]           context_object_index_i,
	input  wire [8:0]           context_screen_y_i,
	input  wire [2:0]           context_source_row_i,
	input  wire [10:0]          context_jca_i,
	input  wire                 context_vflip_i,
	input  wire                 context_hflip_i,
	input  wire [1:0]           context_jplt_select_i,
	input  wire [31:0]          context_jplt_active_i,
	input  wire signed [11:0]   context_left_base_i,
	input  wire signed [11:0]   context_right_base_i,
	input  wire                 context_jlon_i,
	input  wire                 context_jron_i,

	// Read-only VRM client.
	output wire                 vrm_req_o,
	output wire                 vrm_write_o,
	output wire [15:0]          vrm_addr_o,
	input  wire                 vrm_accept_i,
	input  wire                 vrm_resp_valid_i,
	input  wire [15:0]          vrm_resp_data_i,

	// Held query to the shared character decoder.
	output wire                 decode_query_valid_o,
	output wire                 decode_query_ready_o,
	input  wire                 decode_grant_i,
	input  wire                 decode_conflict_i,
	output wire                 decode_accept_o,
	output wire [15:0]          decode_character_row_o,
	output wire [1:0]           decode_palette_o,
	output wire                 decode_hflip_o,
	output wire [31:0]          decode_jplt_active_o,
	input  wire [7:0]           decoded_raw_nonzero_i,
	input  wire [15:0]          decoded_mapped_pixels_i,

	// Held Object row token.
	output wire                 token_valid_o,
	input  wire                 token_ready_i,
	output wire                 token_accept_o,
	output wire [3:0]           token_epoch_o,
	output wire [9:0]           token_object_index_o,
	output wire [8:0]           token_screen_y_o,
	output wire [2:0]           token_source_row_o,
	output wire [2:0]           token_row_o,
	output wire signed [15:0]   token_left_base_x_o,
	output wire                 token_left_enable_o,
	output wire [7:0]           token_left_active_o,
	output wire [7:0]           token_left_opaque_o,
	output wire [15:0]          token_left_values_o,
	output wire signed [15:0]   token_right_base_x_o,
	output wire                 token_right_enable_o,
	output wire [7:0]           token_right_active_o,
	output wire [7:0]           token_right_opaque_o,
	output wire [15:0]          token_right_values_o,
	output wire [2:0]           character_effective_row_o,
	output wire [15:0]          character_row_addr_o,

	output wire                 busy_o,
	output wire                 cleanup_busy_o,
	output wire                 quiescent_o,
	output wire                 offer_valid_o,
	output wire                 read_pending_o,
	output wire                 response_capture_valid_o,
	output wire                 decode_pending_o,
	output wire                 row_token_busy_o,
	output reg                  stale_response_discarded_o,
	output reg                  accept_without_request_o,
	output reg                  unowned_response_o,
	output reg                  response_capture_overflow_o,
	output reg                  pending_owner_overlap_o,
	output reg                  decode_conflict_o
);

	// Packed context, high to low:
	// epoch, index, screen Y, source row, JCA, VFLIP, HFLIP, JPLT select,
	// active JPLTs, signed left base, signed right base, JLON, JRON.
	localparam integer CONTEXT_WIDTH = 99;

	reg offer_valid_q;
	reg [CONTEXT_WIDTH-1:0] offer_payload_q;
	reg pending_q;
	reg pending_stale_q;
	reg [CONTEXT_WIDTH-1:0] pending_payload_q;
	reg response_capture_valid_q;
	reg [15:0] response_capture_data_q;
	reg decode_valid_q;
	reg [CONTEXT_WIDTH-1:0] decode_payload_q;
	reg [15:0] decode_character_row_q;

	wire [CONTEXT_WIDTH-1:0] context_payload_w = {
		context_epoch_i,
		context_object_index_i,
		context_screen_y_i,
		context_source_row_i,
		context_jca_i,
		context_vflip_i,
		context_hflip_i,
		context_jplt_select_i,
		context_jplt_active_i,
		context_left_base_i,
		context_right_base_i,
		context_jlon_i,
		context_jron_i
	};

	wire pending_aborted_w = pending_stale_q || abort_i;
	wire response_available_w = response_capture_valid_q ||
		vrm_resp_valid_i;
	wire [15:0] response_data_w = response_capture_valid_q ?
		response_capture_data_q : vrm_resp_data_i;

	wire row_leaf_ready_w;
	wire row_leaf_accept_w;
	wire row_leaf_busy_w;
	wire decode_fire_w = ce_i && decode_query_valid_o &&
		decode_grant_i && !decode_conflict_i && row_leaf_ready_w;
	wire decode_slot_available_w = !decode_valid_q || decode_fire_w;
	wire live_response_fire_w = ce_i && pending_q &&
		!pending_aborted_w && response_available_w &&
		decode_slot_available_w;
	wire stale_response_fire_w = ce_i && pending_q &&
		pending_aborted_w && response_available_w;
	wire request_window_w =
		(!pending_q && !response_capture_valid_q) ||
		live_response_fire_w;

	wire offer_replacement_window_w = ce_i && !reset_i && !abort_i &&
		!cleanup_busy_o && offer_valid_q && request_window_w &&
		vrm_accept_i;
	// Keep request selection independent of returned acceptance.
	wire selected_live_context_w = !offer_valid_q && ce_i &&
		context_valid_i;
	wire selected_context_valid_w = offer_valid_q ||
		selected_live_context_w;
	wire [CONTEXT_WIDTH-1:0] selected_context_payload_w =
		offer_valid_q ? offer_payload_q : context_payload_w;
	wire [2:0] selected_source_row_w =
		selected_context_payload_w[75:73];
	wire selected_vflip_w = selected_context_payload_w[61];
	wire [2:0] selected_effective_row_w = selected_vflip_w ?
		(3'd7 - selected_source_row_w) : selected_source_row_w;
	wire [15:0] selected_character_addr_w = {
		selected_context_payload_w[72:71],
		2'b11,
		selected_context_payload_w[70:62],
		selected_effective_row_w
	};

	wire request_accept_fire_w = ce_i && vrm_req_o && vrm_accept_i;
	wire offer_request_fire_w = request_accept_fire_w && offer_valid_q;
	wire live_request_fire_w = request_accept_fire_w && !offer_valid_q;

	wire [3:0] decode_epoch_w = decode_payload_q[98:95];
	wire [9:0] decode_object_index_w = decode_payload_q[94:85];
	wire [8:0] decode_screen_y_w = decode_payload_q[84:76];
	wire [2:0] decode_source_row_w = decode_payload_q[75:73];
	wire [10:0] decode_jca_w = decode_payload_q[72:62];
	wire decode_vflip_w = decode_payload_q[61];
	wire decode_hflip_w = decode_payload_q[60];
	wire [1:0] decode_jplt_select_w = decode_payload_q[59:58];
	wire [31:0] decode_jplt_active_w = decode_payload_q[57:26];
	wire signed [11:0] decode_left_base_w = decode_payload_q[25:14];
	wire signed [11:0] decode_right_base_w = decode_payload_q[13:2];
	wire decode_jlon_w = decode_payload_q[1];
	wire decode_jron_w = decode_payload_q[0];

	assign cleanup_busy_o = pending_q && pending_aborted_w;
	assign context_ready_o = ce_i && !reset_i && !abort_i &&
		!cleanup_busy_o && (!offer_valid_q || offer_replacement_window_w);
	assign context_accept_o = context_valid_i && context_ready_o;

	assign vrm_req_o = !reset_i && !abort_i && !cleanup_busy_o &&
		request_window_w && selected_context_valid_w;
	assign vrm_write_o = 1'b0;
	assign vrm_addr_o = selected_context_valid_w ?
		selected_character_addr_w : 16'd0;

	assign decode_query_valid_o = !reset_i && !abort_i && decode_valid_q;
	assign decode_query_ready_o = row_leaf_ready_w;
	assign decode_accept_o = row_leaf_accept_w;
	assign decode_character_row_o = decode_character_row_q;
	assign decode_palette_o = decode_jplt_select_w;
	assign decode_hflip_o = decode_hflip_w;
	assign decode_jplt_active_o = decode_jplt_active_w;

	assign busy_o = offer_valid_q || pending_q ||
		response_capture_valid_q || decode_valid_q || row_leaf_busy_w;
	assign quiescent_o = !reset_i && !abort_i && !busy_o;
	assign offer_valid_o = offer_valid_q;
	assign read_pending_o = pending_q;
	assign response_capture_valid_o = response_capture_valid_q;
	assign decode_pending_o = decode_valid_q;
	assign row_token_busy_o = row_leaf_busy_w;

	vip_xp_obj_row_token u_row_token
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(abort_i),
		.row_valid_i(decode_query_valid_o && decode_grant_i &&
			!decode_conflict_i),
		.row_ready_o(row_leaf_ready_w),
		.row_accept_o(row_leaf_accept_w),
		.epoch_i(decode_epoch_w),
		.object_index_i(decode_object_index_w),
		.screen_y_i(decode_screen_y_w),
		.source_row_i(decode_source_row_w),
		.jca_i(decode_jca_w),
		.vflip_i(decode_vflip_w),
		.left_base_i(decode_left_base_w),
		.right_base_i(decode_right_base_w),
		.jlon_i(decode_jlon_w),
		.jron_i(decode_jron_w),
		.decoded_raw_nonzero_i(decoded_raw_nonzero_i),
		.decoded_mapped_pixels_i(decoded_mapped_pixels_i),
		.token_valid_o(token_valid_o),
		.token_ready_i(token_ready_i),
		.token_accept_o(token_accept_o),
		.token_epoch_o(token_epoch_o),
		.token_object_index_o(token_object_index_o),
		.token_screen_y_o(token_screen_y_o),
		.token_source_row_o(token_source_row_o),
		.token_row_o(token_row_o),
		.token_left_base_x_o(token_left_base_x_o),
		.token_left_enable_o(token_left_enable_o),
		.token_left_active_o(token_left_active_o),
		.token_left_opaque_o(token_left_opaque_o),
		.token_left_values_o(token_left_values_o),
		.token_right_base_x_o(token_right_base_x_o),
		.token_right_enable_o(token_right_enable_o),
		.token_right_active_o(token_right_active_o),
		.token_right_opaque_o(token_right_opaque_o),
		.token_right_values_o(token_right_values_o),
		.character_effective_row_o(character_effective_row_o),
		.character_row_addr_o(character_row_addr_o),
		.busy_o(row_leaf_busy_w)
	);

	always @(posedge clk_i) begin
		if (reset_i) begin
			offer_valid_q <= 1'b0;
			offer_payload_q <= {CONTEXT_WIDTH{1'b0}};
			pending_q <= 1'b0;
			pending_stale_q <= 1'b0;
			pending_payload_q <= {CONTEXT_WIDTH{1'b0}};
			response_capture_valid_q <= 1'b0;
			response_capture_data_q <= 16'd0;
			decode_valid_q <= 1'b0;
			decode_payload_q <= {CONTEXT_WIDTH{1'b0}};
			decode_character_row_q <= 16'd0;
			stale_response_discarded_o <= 1'b0;
			accept_without_request_o <= 1'b0;
			unowned_response_o <= 1'b0;
			response_capture_overflow_o <= 1'b0;
			pending_owner_overlap_o <= 1'b0;
			decode_conflict_o <= 1'b0;
		end else begin
			stale_response_discarded_o <= 1'b0;

			// Preserve raw VRM responses through CE pauses.
			if (vrm_resp_valid_i) begin
				if (!pending_q) begin
					unowned_response_o <= 1'b1;
				end else if (response_capture_valid_q) begin
					response_capture_overflow_o <= 1'b1;
				end else if (!live_response_fire_w &&
					!stale_response_fire_w) begin
					response_capture_valid_q <= 1'b1;
					response_capture_data_q <= vrm_resp_data_i;
				end
			end

			if (decode_conflict_i ||
				(decode_grant_i && !decode_query_valid_o)) begin
				decode_conflict_o <= 1'b1;
			end

			// Raw abort drops offers and decoder state, then drains accepted reads.
			if (abort_i) begin
				offer_valid_q <= 1'b0;
				decode_valid_q <= 1'b0;
				if (pending_q) begin
					pending_stale_q <= 1'b1;
				end else begin
					pending_stale_q <= 1'b0;
					response_capture_valid_q <= 1'b0;
				end
			end else if (ce_i) begin
				// Held request with same-edge replacement.
				if (offer_valid_q) begin
					if (offer_request_fire_w) begin
						if (context_accept_o) begin
							offer_valid_q <= 1'b1;
							offer_payload_q <= context_payload_w;
						end else begin
							offer_valid_q <= 1'b0;
						end
					end
				end else if (context_accept_o) begin
					if (!live_request_fire_w) begin
						offer_valid_q <= 1'b1;
						offer_payload_q <= context_payload_w;
					end
				end

				// Replace the held decoder query on response.
				if (live_response_fire_w) begin
					decode_valid_q <= 1'b1;
					decode_payload_q <= pending_payload_q;
					decode_character_row_q <= response_data_w;
				end else if (decode_fire_w) begin
					decode_valid_q <= 1'b0;
				end
			end

			if (ce_i) begin
				if (vrm_accept_i && !vrm_req_o)
					accept_without_request_o <= 1'b1;

				if (stale_response_fire_w) begin
					pending_q <= 1'b0;
					pending_stale_q <= 1'b0;
					response_capture_valid_q <= 1'b0;
					stale_response_discarded_o <= 1'b1;
				end else if (live_response_fire_w) begin
					pending_q <= 1'b0;
					pending_stale_q <= 1'b0;
					response_capture_valid_q <= 1'b0;
				end

				if (request_accept_fire_w) begin
					if (pending_q && !live_response_fire_w)
						pending_owner_overlap_o <= 1'b1;
					pending_q <= 1'b1;
					pending_stale_q <= 1'b0;
					pending_payload_q <= selected_context_payload_w;
				end
			end
		end
	end

endmodule

`timescale 1ns/1ps

// Object visible-row to strip-store token.
//
// HFLIP and JPLT are already applied. Hold one decoded row, clip it for each
// eye, and emit an eight-pixel token. Support same-edge replacement and raw abort.

module vip_xp_obj_row_token
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	input  wire                 row_valid_i,
	output wire                 row_ready_o,
	output wire                 row_accept_o,
	input  wire [3:0]           epoch_i,
	input  wire [9:0]           object_index_i,
	input  wire [8:0]           screen_y_i,
	input  wire [2:0]           source_row_i,
	input  wire [10:0]          jca_i,
	input  wire                 vflip_i,
	input  wire signed [11:0]   left_base_i,
	input  wire signed [11:0]   right_base_i,
	input  wire                 jlon_i,
	input  wire                 jron_i,
	input  wire [7:0]           decoded_raw_nonzero_i,
	input  wire [15:0]          decoded_mapped_pixels_i,

	output wire                 token_valid_o,
	input  wire                 token_ready_i,
	output wire                 token_accept_o,
	output reg  [3:0]           token_epoch_o,
	output reg  [9:0]           token_object_index_o,
	output reg  [8:0]           token_screen_y_o,
	output reg  [2:0]           token_source_row_o,
	output reg  [2:0]           token_row_o,
	output reg  signed [15:0]   token_left_base_x_o,
	output reg                  token_left_enable_o,
	output reg  [7:0]           token_left_active_o,
	output reg  [7:0]           token_left_opaque_o,
	output reg  [15:0]          token_left_values_o,
	output reg  signed [15:0]   token_right_base_x_o,
	output reg                  token_right_enable_o,
	output reg  [7:0]           token_right_active_o,
	output reg  [7:0]           token_right_opaque_o,
	output reg  [15:0]          token_right_values_o,
	output reg  [2:0]           character_effective_row_o,
	output reg  [15:0]          character_row_addr_o,
	output wire                 busy_o
);

	reg token_valid_q;

	// Diagnostic recompute of the address vip_xp_obj_char_pipeline issued;
	// same shape as vip_xp_bg_address's vrm_character_row_addr_o.
	wire [2:0] effective_row_w = vflip_i ?
		(3'd7 - source_row_i) : source_row_i;
	wire [15:0] character_row_addr_w =
		{jca_i[10:9], 2'b11, jca_i[8:0], effective_row_w};

	// Pixel i is visible when base_x + i lands on screen columns 0..383.
	function automatic [7:0] clipping_mask_fn;
		input signed [11:0] base_x;
		integer pixel_t;
		reg signed [12:0] column_t;
		begin
			for (pixel_t = 0; pixel_t < 8; pixel_t = pixel_t + 1) begin
				column_t = {base_x[11], base_x} +
					$signed({10'd0, pixel_t[2:0]});
				clipping_mask_fn[pixel_t] =
					(column_t >= 13'sd0) && (column_t <= 13'sd383);
			end
		end
	endfunction

	assign row_ready_o = ce_i && !reset_i && !abort_i &&
		(!token_valid_q || token_ready_i);
	assign row_accept_o = row_valid_i && row_ready_o;
	assign token_valid_o = !reset_i && !abort_i && token_valid_q;
	assign token_accept_o = ce_i && token_valid_o && token_ready_i;
	assign busy_o = token_valid_q;

	always @(posedge clk_i) begin
		if (reset_i) begin
			token_valid_q <= 1'b0;
			token_epoch_o <= 4'd0;
			token_object_index_o <= 10'd0;
			token_screen_y_o <= 9'd0;
			token_source_row_o <= 3'd0;
			token_row_o <= 3'd0;
			token_left_base_x_o <= 16'sd0;
			token_left_enable_o <= 1'b0;
			token_left_active_o <= 8'd0;
			token_left_opaque_o <= 8'd0;
			token_left_values_o <= 16'd0;
			token_right_base_x_o <= 16'sd0;
			token_right_enable_o <= 1'b0;
			token_right_active_o <= 8'd0;
			token_right_opaque_o <= 8'd0;
			token_right_values_o <= 16'd0;
			character_effective_row_o <= 3'd0;
			character_row_addr_o <= 16'd0;
		end else if (abort_i) begin
			token_valid_q <= 1'b0;
		end else if (ce_i) begin
			if (row_accept_o) begin
				token_valid_q <= 1'b1;
				token_epoch_o <= epoch_i;
				token_object_index_o <= object_index_i;
				token_screen_y_o <= screen_y_i;
				token_source_row_o <= source_row_i;
				token_row_o <= screen_y_i[2:0];
				token_left_base_x_o <=
					{{4{left_base_i[11]}}, left_base_i};
				token_left_enable_o <= jlon_i;
				token_left_active_o <= clipping_mask_fn(left_base_i);
				token_left_opaque_o <= decoded_raw_nonzero_i;
				token_left_values_o <= decoded_mapped_pixels_i;
				token_right_base_x_o <=
					{{4{right_base_i[11]}}, right_base_i};
				token_right_enable_o <= jron_i;
				token_right_active_o <= clipping_mask_fn(right_base_i);
				token_right_opaque_o <= decoded_raw_nonzero_i;
				token_right_values_o <= decoded_mapped_pixels_i;
				character_effective_row_o <= effective_row_w;
				character_row_addr_o <= character_row_addr_w;
			end else if (token_accept_o) begin
				token_valid_q <= 1'b0;
			end
		end
	end

endmodule

/* verilator lint_on DECLFILENAME */
