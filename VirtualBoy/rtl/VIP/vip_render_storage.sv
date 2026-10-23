// Copyright (c) 2026 Jamie Blanks

`timescale 1ns/1ps
/* verilator lint_off DECLFILENAME */

// Draw control, descriptor snapshots, row storage, and framebuffer ownership.

module vip_xp_storage_subsystem
#(
	parameter integer AFFINE_STREAM_ENABLE = 0
)
(
	input  wire         clk_i,
	input  wire         reset_i,
	input  wire         ce_i,
	input  wire [5:0]   savestate_state_addr_i,
	input  wire [63:0]  savestate_state_wdata_i,
	input  wire         savestate_state_wren_i,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire         sim_snapshot_restore_commit_i,
	input  wire         sim_snapshot_restore_apply_i,
	input  wire [3647:0] sim_snapshot_restore_packet_i,
`endif
`endif

	input  wire         game_start_fire_i,
	input  wire         xp_enable_i,
	input  wire         xprst_i,
	input  wire [4:0]   xp_sbcmp_i,
	input  wire [1:0]   bkcol_register_i,
	input  wire [1:0]   bkcol_active_i,

	// Descriptor snapshot DRAM channel.
	output wire         dram_req_o,
	output wire         dram_write_o,
	output wire [15:0]  dram_addr_o,
	output wire [15:0]  dram_wdata_o,
	output wire [1:0]   dram_byte_enable_o,
	input  wire         dram_accept_i,
	input  wire         dram_resp_valid_i,
	input  wire [15:0]  dram_resp_data_i,

	// Strip loadout VRM channel.
	output wire         vrm_req_o,
	output wire         vrm_write_o,
	output wire [15:0]  vrm_addr_o,
	output wire [15:0]  vrm_wdata_o,
	output wire [1:0]   vrm_byte_enable_o,
	input  wire         vrm_accept_i,

	// Selected renderer.
	output wire         engine_cmd_valid_o,
	input  wire         engine_cmd_ready_i,
	output wire [1:0]   engine_cmd_kind_o,
	output wire [4:0]   engine_cmd_strip_o,
	output wire [4:0]   engine_cmd_world_o,
	output wire [255:0] engine_cmd_descriptor_o,
	output wire         engine_cmd_first_visit_o,
	input  wire         engine_done_i,
	input  wire         engine_cleanup_busy_i,
	output wire         engine_abort_o,

	// Legacy single-eye row token. Permanently tied off: every instantiation
	// drives producer_valid_i low, and this module never accepts it.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire         producer_valid_i,
	output wire         producer_ready_o,
	input  wire [8:0]   producer_column_i,
	input  wire         producer_left_enable_i,
	input  wire [15:0]  producer_left_preserve_mask_i,
	input  wire [15:0]  producer_left_value_i,
	input  wire         producer_right_enable_i,
	input  wire [15:0]  producer_right_preserve_mask_i,
	input  wire [15:0]  producer_right_value_i,
	/* verilator lint_on UNUSEDSIGNAL */
	output wire         producer_done_o,

	// Stereo row token from the selected renderer.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire         row_producer_valid_i,
	input  wire [2:0]   row_producer_row_i,
	input  wire signed [15:0] row_producer_left_base_x_i,
	input  wire         row_producer_left_enable_i,
	input  wire [7:0]   row_producer_left_active_i,
	input  wire [7:0]   row_producer_left_opaque_i,
	input  wire [15:0]  row_producer_left_values_i,
	input  wire signed [15:0] row_producer_right_base_x_i,
	input  wire         row_producer_right_enable_i,
	input  wire [7:0]   row_producer_right_active_i,
	input  wire [7:0]   row_producer_right_opaque_i,
	input  wire [15:0]  row_producer_right_values_i,
	/* verilator lint_on UNUSEDSIGNAL */
	output wire         row_producer_ready_o,
	output wire         row_producer_done_o,

	// Optional four-pixel Affine input.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire         affine_abort_i,
	input  wire         affine_prepare_valid_i,
	output wire         affine_prepare_ready_o,
	output wire         affine_prepare_accept_o,
	input  wire [2:0]   affine_prepare_row_i,
	input  wire signed [15:0] affine_prepare_left_base_x_i,
	input  wire         affine_prepare_left_enable_i,
	input  wire signed [15:0] affine_prepare_right_base_x_i,
	input  wire         affine_prepare_right_enable_i,
	input  wire         affine_commit_valid_i,
	output wire         affine_commit_ready_o,
	output wire         affine_commit_accept_o,
	input  wire [3:0]   affine_commit_left_active_i,
	input  wire [3:0]   affine_commit_left_opaque_i,
	input  wire [7:0]   affine_commit_left_values_i,
	input  wire [3:0]   affine_commit_right_active_i,
	input  wire [3:0]   affine_commit_right_opaque_i,
	input  wire [7:0]   affine_commit_right_values_i,
	/* verilator lint_on UNUSEDSIGNAL */
	output wire         affine_active_o,
	output wire         affine_quiescent_o,
	output wire         affine_done_o,

	// XP status and same-edge events.
	output wire         draw_start_fire_o,
	output wire         first_group_done_fire_o,
	output wire         sb_hit_fire_o,
	output wire         xp_end_fire_o,
	output wire         timeerr_fire_o,
	output wire         drawing_o,
	output wire [1:0]   xp_busy_o,
	output wire [4:0]   xp_strip_o,
	output wire [4:0]   xp_sbcount_o,
	output wire         xp_sbout_o,
	output wire         xp_overtime_o,

	// Framebuffer ownership changes only at draw completion and GCLK.
	output wire         displayed_fb_o,
	output wire         active_draw_valid_o,
	output wire         active_draw_target_o,
	output wire         completed_pending_valid_o,
	output wire         completed_pending_target_o,
	output wire         display_swap_o,
	output wire         completion_commit_o,

	// Composition diagnostics.
	output wire         snapshot_valid_o,
	output wire [9:0]   snapshot_accepted_count_o,
	output wire [9:0]   snapshot_response_count_o,
	output wire [9:0]   loadout_accept_count_o,
	output wire [3:0]   coordinator_state_o,
	output wire [4:0]   coordinator_world_o,
	output wire [15:0]  setup_remaining_o,
	output wire [15:0]  service_remaining_o,
	output wire [5:0]   world_interval_elapsed_o,
	output wire [5:0]   world_interval_target_o,
	output wire [7:0]   recovery_remaining_o,
	output wire         strip_start_fire_o,
	output wire         strip_commit_fire_o,
	output wire         completion_gclk_tie_o,
	output wire         classification_mismatch_o,
	output wire         peripheral_busy_o,
	output wire         descriptor_snapshot_owner_active_o,
	output wire         descriptor_consumer_owner_active_o,
	output wire         strip_transport_owner_active_o,
	output wire         affine_loadout_owner_active_o,
	output wire         snapshot_response_owner_error_o,
`ifndef SYNTHESIS
	// Simulation pulse for one discarded stale response.
	output wire         snapshot_stale_response_discarded_o,
	output wire [9:0]   snapshot_discarded_count_o,
`endif
	output wire         ownership_mismatch_o
);

	wire         snapshot_start_w;
	wire         snapshot_abort_w;
	wire         snapshot_start_ready_w;
	wire         snapshot_busy_w;
	wire         snapshot_done_w;
	wire         snapshot_cleanup_busy_w;
	wire         snapshot_request_outstanding_w;
	wire         snapshot_head_read_w;
	wire [8:0]   snapshot_head_addr_w;
	wire         snapshot_read_valid_w;
	wire         snapshot_read_data_valid_w;
	wire [15:0]  snapshot_read_data_w;
	wire         snapshot_unexpected_response_w;
	wire         snapshot_read_issue_w;
	wire [8:0]   snapshot_read_addr_w;

	wire         descriptor_fetch_start_w;
	wire [4:0]   descriptor_fetch_world_w;
	wire         descriptor_fetch_abort_w;
	wire         descriptor_fetch_start_ready_w;
	wire         descriptor_fetch_req_w;
	wire [8:0]   descriptor_fetch_addr_w;
	wire         descriptor_fetch_ready_w;
	wire         descriptor_fetch_rvalid_w;
	wire         descriptor_fetch_busy_w;
	wire         descriptor_fetch_done_w;
	wire [255:0] descriptor_w;
	wire         descriptor_end_w;
	wire         descriptor_dummy_w;
	wire [1:0]   descriptor_kind_w;

	wire         strip_init_start_w;
	wire [15:0]  strip_bkcol_word_w;
	wire         strip_init_ready_w;
	wire         strip_init_active_w;
	wire         strip_init_done_w;
	wire         strip_load_start_w;
	wire [4:0]   strip_load_strip_w;
	wire         strip_load_fb_w;
	wire         strip_load_ready_w;
	wire         strip_load_active_w;
	wire         strip_load_done_w;
	wire         strip_abort_w;
	wire         strip_store_busy_w;

	wire         owner_draw_target_for_start_w;
	wire [1:0]   owner_xp_busy_w;
	wire         owner_draw_complete_fire_w;
	wire         owner_illegal_start_w;
	wire         owner_illegal_complete_w;
	wire         owner_completion_gclk_tie_w;
	wire [1:0]   coordinator_xp_busy_w;
	wire         coordinator_draw_fb_w;
	wire         coordinator_completion_gclk_tie_w;

	// One owner bit routes the synchronous snapshot response to the coordinator
	// or descriptor reader.
	reg snapshot_read_owner_fetch_q;
	reg snapshot_response_owner_error_q;

	// "Ready" here means the snapshot read port can accept the fetch's
	// request this cycle, not that the fetch itself is ready.
	assign descriptor_fetch_ready_w = ce_i && snapshot_valid_o &&
		!snapshot_head_read_w;
	assign snapshot_read_issue_w = ce_i && snapshot_valid_o &&
		(snapshot_head_read_w ||
		 (descriptor_fetch_req_w && descriptor_fetch_ready_w));
	assign snapshot_read_addr_w = snapshot_head_read_w ?
		snapshot_head_addr_w : descriptor_fetch_addr_w;
	// Fetch keeps raw responses long enough to drain reads after an abort.
	assign descriptor_fetch_rvalid_w = snapshot_read_valid_w &&
		snapshot_read_owner_fetch_q;
	assign snapshot_cleanup_busy_w = snapshot_busy_w &&
		snapshot_request_outstanding_w;

	assign dram_write_o = 1'b0;
	assign dram_wdata_o = 16'd0;
	assign dram_byte_enable_o = 2'b11;
	assign vrm_byte_enable_o = 2'b11;
	// Keep one XPSTTS framebuffer busy during the documented XPRST recovery time.
	assign xp_busy_o = coordinator_xp_busy_w;
	assign ownership_mismatch_o =
		((recovery_remaining_o == 8'd0) &&
		 (owner_xp_busy_w != coordinator_xp_busy_w)) ||
		(active_draw_valid_o &&
		 (active_draw_target_o != coordinator_draw_fb_w)) ||
		owner_illegal_start_w || owner_illegal_complete_w;
	assign completion_gclk_tie_o = coordinator_completion_gclk_tie_w ||
		owner_completion_gclk_tie_w;
	assign descriptor_snapshot_owner_active_o = snapshot_busy_w;
	assign descriptor_consumer_owner_active_o = snapshot_head_read_w ||
		snapshot_read_issue_w || snapshot_read_valid_w ||
		descriptor_fetch_busy_w;
	assign strip_transport_owner_active_o = strip_store_busy_w;
	assign affine_loadout_owner_active_o = affine_active_o ||
		strip_load_active_w;

	always @(posedge clk_i
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		or posedge sim_snapshot_restore_commit_i
`endif
`endif
	) begin
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		if (sim_snapshot_restore_commit_i) begin
			if (sim_snapshot_restore_apply_i) begin
				snapshot_read_owner_fetch_q <= 1'b0;
				snapshot_response_owner_error_q <= 1'b0;
			end
		end else
`endif
`endif
		if (reset_i) begin
			snapshot_read_owner_fetch_q <= 1'b0;
			snapshot_response_owner_error_q <= 1'b0;
		end else begin
			if (snapshot_read_issue_w) begin
				snapshot_read_owner_fetch_q <= !snapshot_head_read_w;
			end
			if (snapshot_read_valid_w && snapshot_read_owner_fetch_q &&
				!descriptor_fetch_abort_w && snapshot_read_data_valid_w &&
				!descriptor_fetch_busy_w) begin
				snapshot_response_owner_error_q <= 1'b1;
			end
		end
	end

	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_descriptor_snapshot u_descriptor_snapshot
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		.sim_snapshot_restore_commit_i(sim_snapshot_restore_commit_i),
		.sim_snapshot_restore_apply_i(sim_snapshot_restore_apply_i),
`endif
`endif
		.start_i(snapshot_start_w),
		.start_ready_o(snapshot_start_ready_w),
		.start_accept_o(),
		.abort_i(snapshot_abort_w),
		.dram_req_o(dram_req_o),
		.dram_addr_o(dram_addr_o),
		.dram_accept_i(dram_accept_i),
		.dram_resp_valid_i(dram_resp_valid_i),
		.dram_resp_data_i(dram_resp_data_i),
		.read_ce_i(ce_i),
		.read_enable_i(snapshot_read_issue_w),
		.read_addr_i(snapshot_read_addr_w),
		.read_valid_o(snapshot_read_valid_w),
		.read_snapshot_valid_o(snapshot_read_data_valid_w),
		.read_data_o(snapshot_read_data_w),
		.busy_o(snapshot_busy_w),
		.request_outstanding_o(snapshot_request_outstanding_w),
		.snapshot_valid_o(snapshot_valid_o),
		.done_o(snapshot_done_w),
		.aborted_o(),
		.abort_done_o(),
		.unexpected_response_o(snapshot_unexpected_response_w),
`ifndef SYNTHESIS
		.stale_response_discarded_o(
			snapshot_stale_response_discarded_o),
`else
		.stale_response_discarded_o(),
`endif
		.accepted_count_o(snapshot_accepted_count_o),
		.response_count_o(snapshot_response_count_o),
`ifndef SYNTHESIS
		.discarded_count_o(snapshot_discarded_count_o),
`else
		.discarded_count_o(),
`endif
		.request_index_o(),
		.response_owner_index_o(),
		.active_generation_o(),
		.completed_generation_o()
	);

	vip_xp_descriptor_fetch u_descriptor_fetch
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(descriptor_fetch_abort_w),
		.start_i(descriptor_fetch_start_w),
		.world_i(descriptor_fetch_world_w),
		.start_ready_o(descriptor_fetch_start_ready_w),
		.snapshot_req_o(descriptor_fetch_req_w),
		.snapshot_addr_o(descriptor_fetch_addr_w),
		.snapshot_ready_i(descriptor_fetch_ready_w),
		.snapshot_rvalid_i(descriptor_fetch_rvalid_w),
		.snapshot_rdata_i(snapshot_read_data_w),
		.busy_o(descriptor_fetch_busy_w),
		.done_o(descriptor_fetch_done_w),
		.world_tag_o(),
		.descriptor_o(descriptor_w),
		.word0_o(),
		.word0_valid_o(),
		.end_marker_o(descriptor_end_w),
		.dummy_world_o(descriptor_dummy_w),
		.world_kind_o(descriptor_kind_w),
		.word_accept_o(),
		.word_accept_index_o(),
		.word_accept_count_o(),
		.current_word_index_o(),
		.cleanup_busy_o()
	);

	wire affine_store_abort_w;
	wire affine_prepare_ready_w;
	wire affine_prepare_accept_w;
	wire affine_commit_ready_w;
	wire affine_commit_accept_w;
	wire affine_active_w;
	wire affine_quiescent_w;
	wire affine_done_w;

	assign affine_store_abort_w = strip_abort_w ||
		((AFFINE_STREAM_ENABLE != 0) && affine_abort_i);

	/* verilator lint_off PINCONNECTEMPTY */
	vip_xp_row_strip_store u_row_strip_store
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(affine_store_abort_w),
		.init_start_i(strip_init_start_w),
		.init_bkcol_word_i(strip_bkcol_word_w),
		.init_ready_o(strip_init_ready_w),
		.init_active_o(strip_init_active_w),
		.init_done_o(strip_init_done_w),
		.producer_valid_i(row_producer_valid_i),
		.producer_ready_o(row_producer_ready_o),
		.producer_row_i(row_producer_row_i),
		.producer_left_base_x_i(
			row_producer_left_base_x_i),
		.producer_left_enable_i(
			row_producer_left_enable_i),
		.producer_left_active_i(
			row_producer_left_active_i),
		.producer_left_opaque_i(
			row_producer_left_opaque_i),
		.producer_left_values_i(
			row_producer_left_values_i),
		.producer_right_base_x_i(
			row_producer_right_base_x_i),
		.producer_right_enable_i(
			row_producer_right_enable_i),
		.producer_right_active_i(
			row_producer_right_active_i),
		.producer_right_opaque_i(
			row_producer_right_opaque_i),
		.producer_right_values_i(
			row_producer_right_values_i),
		.producer_done_o(row_producer_done_o),
		.affine_prepare_valid_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_prepare_valid_i : 1'b0),
		.affine_prepare_ready_o(affine_prepare_ready_w),
		.affine_prepare_accept_o(affine_prepare_accept_w),
		.affine_prepare_row_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_prepare_row_i : 3'd0),
		.affine_prepare_left_base_x_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_prepare_left_base_x_i : 16'sd0),
		.affine_prepare_left_enable_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_prepare_left_enable_i : 1'b0),
		.affine_prepare_right_base_x_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_prepare_right_base_x_i : 16'sd0),
		.affine_prepare_right_enable_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_prepare_right_enable_i : 1'b0),
		.affine_commit_valid_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_commit_valid_i : 1'b0),
		.affine_commit_ready_o(affine_commit_ready_w),
		.affine_commit_accept_o(affine_commit_accept_w),
		.affine_commit_left_active_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_commit_left_active_i : 4'd0),
		.affine_commit_left_opaque_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_commit_left_opaque_i : 4'd0),
		.affine_commit_left_values_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_commit_left_values_i : 8'd0),
		.affine_commit_right_active_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_commit_right_active_i : 4'd0),
		.affine_commit_right_opaque_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_commit_right_opaque_i : 4'd0),
		.affine_commit_right_values_i(
			(AFFINE_STREAM_ENABLE != 0) ?
			affine_commit_right_values_i : 8'd0),
		.affine_active_o(affine_active_w),
		.affine_quiescent_o(affine_quiescent_w),
		.affine_done_o(affine_done_w),
		.loadout_start_i(strip_load_start_w),
		.loadout_strip_i(strip_load_strip_w),
		.loadout_fb_i(strip_load_fb_w),
		.loadout_ready_o(strip_load_ready_w),
		.loadout_active_o(strip_load_active_w),
		.loadout_done_o(strip_load_done_w),
		.vrm_req_o(vrm_req_o),
		.vrm_write_o(vrm_write_o),
		.vrm_addr_o(vrm_addr_o),
		.vrm_wdata_o(vrm_wdata_o),
		.vrm_accept_i(vrm_accept_i),
		.store_busy_o(strip_store_busy_w),
		.producer_active_o(),
		.state_o(),
		.diag_init_address_count_o(),
		.diag_init_bank_write_count_o(),
		.diag_producer_accept_count_o(),
		.diag_producer_done_count_o(),
		.diag_producer_access_count_o(),
		.diag_producer_pixel_write_count_o(),
		.diag_loadout_prefetch_count_o(),
		.diag_loadout_accept_count_o(loadout_accept_count_o),
		.diag_loadout_internal_stall_count_o()
	);
	/* verilator lint_on PINCONNECTEMPTY */

	assign producer_ready_o = 1'b0;
	assign producer_done_o = 1'b0;
	assign affine_prepare_ready_o =
		(AFFINE_STREAM_ENABLE != 0) ?
		affine_prepare_ready_w : 1'b0;
	assign affine_prepare_accept_o =
		(AFFINE_STREAM_ENABLE != 0) ?
		affine_prepare_accept_w : 1'b0;
	assign affine_commit_ready_o =
		(AFFINE_STREAM_ENABLE != 0) ?
		affine_commit_ready_w : 1'b0;
	assign affine_commit_accept_o =
		(AFFINE_STREAM_ENABLE != 0) ?
		affine_commit_accept_w : 1'b0;
	assign affine_active_o =
		(AFFINE_STREAM_ENABLE != 0) ? affine_active_w : 1'b0;
	assign affine_quiescent_o =
		(AFFINE_STREAM_ENABLE != 0) ? affine_quiescent_w : 1'b1;
	assign affine_done_o =
		(AFFINE_STREAM_ENABLE != 0) ? affine_done_w : 1'b0;

	vip_xp_framebuffer_owner u_framebuffer_owner
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.savestate_state_addr_i(savestate_state_addr_i),
		.savestate_state_wdata_i(savestate_state_wdata_i),
		.savestate_state_wren_i(savestate_state_wren_i),
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		.sim_snapshot_restore_commit_i(sim_snapshot_restore_commit_i),
		.sim_snapshot_restore_apply_i(sim_snapshot_restore_apply_i),
		.sim_snapshot_restore_packet_i(sim_snapshot_restore_packet_i),
`endif
`endif
		.game_start_fire_i(game_start_fire_i),
		.xp_enable_i(xp_enable_i),
		.draw_start_fire_i(draw_start_fire_o),
		.draw_complete_fire_i(owner_draw_complete_fire_w),
		.draw_abort_i(xprst_i),
		.display_selected_o(displayed_fb_o),
		.active_valid_o(active_draw_valid_o),
		.active_target_o(active_draw_target_o),
		.completed_pending_valid_o(completed_pending_valid_o),
		.completed_pending_target_o(completed_pending_target_o),
		.draw_start_target_o(owner_draw_target_for_start_w),
		.xp_busy_o(owner_xp_busy_w),
		.draw_start_accept_o(),
		.completion_commit_o(completion_commit_o),
		.completion_commit_target_o(),
		.display_swap_o(display_swap_o),
		.display_swap_target_o(),
		.draw_aborted_o(),
		.illegal_start_o(owner_illegal_start_w),
		.illegal_complete_o(owner_illegal_complete_w),
		.completion_gclk_tie_o(owner_completion_gclk_tie_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	assign snapshot_response_owner_error_o =
		snapshot_response_owner_error_q ||
		snapshot_unexpected_response_w;

	// The coordinator contains control only.
	vip_xp_render_coordinator u_render_coordinator
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.game_start_fire_i(game_start_fire_i),
		.xp_enable_i(xp_enable_i),
		.xprst_i(xprst_i),
		.xp_sbcmp_i(xp_sbcmp_i),
		.owner_draw_target_for_start_i(owner_draw_target_for_start_w),
		.bkcol_register_i(bkcol_register_i),
		.bkcol_active_i(bkcol_active_i),
		.snapshot_start_ready_i(snapshot_start_ready_w),
		.snapshot_busy_i(snapshot_busy_w),
		.snapshot_done_i(snapshot_done_w),
		.snapshot_valid_i(snapshot_valid_o),
		.snapshot_cleanup_busy_i(snapshot_cleanup_busy_w),
		.snapshot_head_rvalid_i(snapshot_read_data_valid_w &&
			!snapshot_read_owner_fetch_q),
		.snapshot_head_rdata_i(snapshot_read_data_w),
		.descriptor_fetch_start_ready_i(
			descriptor_fetch_start_ready_w),
		.descriptor_fetch_busy_i(descriptor_fetch_busy_w),
		.descriptor_fetch_done_i(descriptor_fetch_done_w),
		.descriptor_fetch_descriptor_i(descriptor_w),
		.descriptor_fetch_end_i(descriptor_end_w),
		.descriptor_fetch_dummy_i(descriptor_dummy_w),
		.descriptor_fetch_kind_i(descriptor_kind_w),
		.strip_init_start_ready_i(strip_init_ready_w),
		.strip_init_active_i(strip_init_active_w),
		.strip_init_done_i(strip_init_done_w),
		.strip_load_start_ready_i(strip_load_ready_w),
		.strip_load_active_i(strip_load_active_w),
		.strip_load_done_i(strip_load_done_w),
		.engine_cmd_ready_i(engine_cmd_ready_i),
		.engine_done_i(engine_done_i),
		.engine_cleanup_busy_i(engine_cleanup_busy_i),
		.snapshot_start_o(snapshot_start_w),
		.snapshot_abort_o(snapshot_abort_w),
		.snapshot_head_read_o(snapshot_head_read_w),
		.snapshot_head_addr_o(snapshot_head_addr_w),
		.descriptor_fetch_start_o(descriptor_fetch_start_w),
		.descriptor_fetch_world_o(descriptor_fetch_world_w),
		.descriptor_fetch_abort_o(descriptor_fetch_abort_w),
		.strip_init_start_o(strip_init_start_w),
		.strip_init_bkcol_word_o(strip_bkcol_word_w),
		.strip_load_start_o(strip_load_start_w),
		.strip_load_strip_o(strip_load_strip_w),
		.strip_load_draw_fb_o(strip_load_fb_w),
		.strip_abort_o(strip_abort_w),
		.engine_cmd_valid_o(engine_cmd_valid_o),
		.engine_cmd_kind_o(engine_cmd_kind_o),
		.engine_cmd_strip_o(engine_cmd_strip_o),
		.engine_cmd_world_o(engine_cmd_world_o),
		.engine_cmd_descriptor_o(engine_cmd_descriptor_o),
		.engine_cmd_first_visit_o(engine_cmd_first_visit_o),
		.engine_abort_o(engine_abort_o),
		.draw_start_fire_o(draw_start_fire_o),
		.first_group_done_fire_o(first_group_done_fire_o),
		.sb_hit_fire_o(sb_hit_fire_o),
		.xp_end_fire_o(xp_end_fire_o),
		.timeerr_fire_o(timeerr_fire_o),
		.owner_draw_complete_fire_o(owner_draw_complete_fire_w),
		.drawing_o(drawing_o),
		.xp_busy_o(coordinator_xp_busy_w),
		.xp_strip_o(xp_strip_o),
		.xp_sbcount_o(xp_sbcount_o),
		.xp_sbout_o(xp_sbout_o),
		.xp_overtime_o(xp_overtime_o),
		.draw_fb_o(coordinator_draw_fb_w),
		.state_o(coordinator_state_o),
		.world_o(coordinator_world_o),
		.draw_setup_remaining_o(setup_remaining_o),
		.strip_service_remaining_o(service_remaining_o),
		.world_interval_elapsed_o(world_interval_elapsed_o),
		.world_interval_target_o(world_interval_target_o),
		.recovery_remaining_o(recovery_remaining_o),
		.strip_start_fire_o(strip_start_fire_o),
		.strip_commit_fire_o(strip_commit_fire_o),
		.completion_gclk_tie_o(coordinator_completion_gclk_tie_w),
		.classification_mismatch_o(classification_mismatch_o),
		.peripheral_busy_o(peripheral_busy_o)
	);

endmodule

// Snapshot of 32 world descriptors, 16 halfwords each.
//
// One DRAM read is active at a time. A new request may replace a completed one
// on the same CE. Abort drops unaccepted work and drains accepted reads.

module vip_xp_descriptor_snapshot
#(
	parameter integer GENERATION_WIDTH = 8
)
(
	input  wire                        clk_i,
	input  wire                        reset_i,
	input  wire                        ce_i,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire                        sim_snapshot_restore_commit_i,
	input  wire                        sim_snapshot_restore_apply_i,
`endif
`endif

	input  wire                        start_i,
	output wire                        start_ready_o,
	output wire                        start_accept_o,
	input  wire                        abort_i,

	// DRAM read channel.
	output wire                        dram_req_o,
	output wire [15:0]                 dram_addr_o,
	input  wire                        dram_accept_i,
	input  wire                        dram_resp_valid_i,
	input  wire [15:0]                 dram_resp_data_i,

	// Synchronous snapshot read port.
	input  wire                        read_ce_i,
	input  wire                        read_enable_i,
	input  wire [8:0]                  read_addr_i,
	output wire                        read_valid_o,
	output wire                        read_snapshot_valid_o,
	output wire [15:0]                 read_data_o,

	output wire                        busy_o,
	output wire                        request_outstanding_o,
	output reg                         snapshot_valid_o,
	output reg                         done_o,
	output reg                         aborted_o,
	output reg                         abort_done_o,
	output reg                         unexpected_response_o,
	output reg                         stale_response_discarded_o,
	output reg  [9:0]                  accepted_count_o,
	output reg  [9:0]                  response_count_o,
	output reg  [9:0]                  discarded_count_o,
	output wire [8:0]                  request_index_o,
	output wire [8:0]                  response_owner_index_o,
	output wire [GENERATION_WIDTH-1:0] active_generation_o,
	output reg  [GENERATION_WIDTH-1:0] completed_generation_o
);

	localparam [1:0] STATE_IDLE = 2'd0;
	localparam [1:0] STATE_REQUEST = 2'd1;
	localparam [1:0] STATE_RESPONSE = 2'd2;
	localparam [1:0] STATE_DISCARD = 2'd3;

	reg  [1:0]                  state_q;
	reg  [8:0]                  next_index_q;
	reg  [8:0]                  owner_index_q;
	reg  [GENERATION_WIDTH-1:0] generation_counter_q;
	reg  [GENERATION_WIDTH-1:0] active_generation_q;
	reg  [GENERATION_WIDTH-1:0] owner_generation_q;
	reg  [8:0]                  read_addr_q;
	reg                         read_valid_q;

	wire owner_matches_active_w =
		owner_generation_q == active_generation_q;
	wire more_requests_w = accepted_count_o < 10'd512;
	wire response_owned_w = (state_q == STATE_RESPONSE) ||
		(state_q == STATE_DISCARD);
	wire response_fire_w = ce_i && response_owned_w &&
		dram_resp_valid_i;
	wire normal_response_fire_w = response_fire_w &&
		(state_q == STATE_RESPONSE) && owner_matches_active_w && !abort_i;
	wire request_offer_w = (state_q == STATE_REQUEST) ||
		((state_q == STATE_RESPONSE) && dram_resp_valid_i &&
		owner_matches_active_w && more_requests_w);
	wire request_fire_w = ce_i && dram_req_o && dram_accept_i;
	wire [8:0] snapshot_ram_read_addr_w =
		(read_ce_i && read_enable_i) ? read_addr_i : read_addr_q;
	wire [15:0] snapshot_ram_read_data_w;

	assign start_ready_o = ce_i && !reset_i && !abort_i &&
		(state_q == STATE_IDLE);
	assign start_accept_o = start_i && start_ready_o;
	assign dram_req_o = !reset_i && !abort_i && request_offer_w;
	assign dram_addr_o = {7'b1110110, next_index_q};
	assign busy_o = state_q != STATE_IDLE;
	assign request_outstanding_o = response_owned_w;
	assign request_index_o = next_index_q;
	assign response_owner_index_o = owner_index_q;
	assign active_generation_o = active_generation_q;
	assign read_valid_o = read_valid_q;
	assign read_snapshot_valid_o = read_valid_q && snapshot_valid_o;
	assign read_data_o = read_snapshot_valid_o ?
		snapshot_ram_read_data_w : 16'd0;

	/* verilator lint_off PINCONNECTEMPTY */
	cache_ram_dp
	#(
		.ADDR_WIDTH(9),
		.DATA_WIDTH(16)
	)
	u_snapshot_ram
	(
		.clk_i(clk_i),
		.addr_a_i(owner_index_q),
		.wren_a_i(normal_response_fire_w),
		.wdata_a_i(dram_resp_data_i),
		.q_a_o(),
		.addr_b_i(snapshot_ram_read_addr_w),
		.wren_b_i(1'b0),
		.wdata_b_i(16'd0),
		.q_b_o(snapshot_ram_read_data_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	// Retire the final outstanding response of a superseded or aborted pass.
	task drain_stale_response_task;
		begin
			state_q <= STATE_IDLE;
			response_count_o <= response_count_o + 10'd1;
			discarded_count_o <= discarded_count_o + 10'd1;
			stale_response_discarded_o <= 1'b1;
			abort_done_o <= 1'b1;
		end
	endtask

	always @(posedge clk_i
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		or posedge sim_snapshot_restore_commit_i
`endif
`endif
	) begin
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		if (sim_snapshot_restore_commit_i) begin
			if (sim_snapshot_restore_apply_i) begin
				state_q <= STATE_IDLE;
				next_index_q <= 9'd0;
				owner_index_q <= 9'd0;
				generation_counter_q <= {GENERATION_WIDTH{1'b0}};
				active_generation_q <= {GENERATION_WIDTH{1'b0}};
				owner_generation_q <= {GENERATION_WIDTH{1'b0}};
				read_addr_q <= 9'd0;
				read_valid_q <= 1'b0;
				snapshot_valid_o <= 1'b0;
				done_o <= 1'b0;
				aborted_o <= 1'b0;
				abort_done_o <= 1'b0;
				unexpected_response_o <= 1'b0;
				stale_response_discarded_o <= 1'b0;
				accepted_count_o <= 10'd0;
				response_count_o <= 10'd0;
				discarded_count_o <= 10'd0;
				completed_generation_o <= {GENERATION_WIDTH{1'b0}};
			end
		end else
`endif
`endif
		if (reset_i) begin
			state_q <= STATE_IDLE;
			next_index_q <= 9'd0;
			owner_index_q <= 9'd0;
			generation_counter_q <= {GENERATION_WIDTH{1'b0}};
			active_generation_q <= {GENERATION_WIDTH{1'b0}};
			owner_generation_q <= {GENERATION_WIDTH{1'b0}};
			read_addr_q <= 9'd0;
			read_valid_q <= 1'b0;
			snapshot_valid_o <= 1'b0;
			done_o <= 1'b0;
			aborted_o <= 1'b0;
			abort_done_o <= 1'b0;
			unexpected_response_o <= 1'b0;
			stale_response_discarded_o <= 1'b0;
			accepted_count_o <= 10'd0;
			response_count_o <= 10'd0;
			discarded_count_o <= 10'd0;
			completed_generation_o <= {GENERATION_WIDTH{1'b0}};
		end else begin
			if (read_ce_i) begin
				read_valid_q <= read_enable_i;
				if (read_enable_i) begin
					read_addr_q <= read_addr_i;
				end
			end

			if (ce_i) begin
				done_o <= 1'b0;
				aborted_o <= 1'b0;
				abort_done_o <= 1'b0;
				unexpected_response_o <= 1'b0;
				stale_response_discarded_o <= 1'b0;
				if (dram_resp_valid_i && (state_q != STATE_RESPONSE) &&
					(state_q != STATE_DISCARD)) begin
					unexpected_response_o <= 1'b1;
				end

				if (abort_i) begin
					snapshot_valid_o <= 1'b0;
					case (state_q)
						STATE_REQUEST: begin
							state_q <= STATE_IDLE;
							aborted_o <= 1'b1;
							abort_done_o <= 1'b1;
						end

						STATE_RESPONSE: begin
							aborted_o <= 1'b1;
							if (dram_resp_valid_i) begin
								drain_stale_response_task;
							end else begin
								state_q <= STATE_DISCARD;
							end
						end

						STATE_DISCARD: begin
							if (dram_resp_valid_i) begin
								drain_stale_response_task;
							end
						end

						default: begin
							aborted_o <= start_i;
							abort_done_o <= start_i;
						end
					endcase
				end else begin
					if (start_accept_o) begin
						state_q <= STATE_REQUEST;
						next_index_q <= 9'd0;
						generation_counter_q <= generation_counter_q +
							{{(GENERATION_WIDTH-1){1'b0}}, 1'b1};
						active_generation_q <= generation_counter_q +
							{{(GENERATION_WIDTH-1){1'b0}}, 1'b1};
						snapshot_valid_o <= 1'b0;
						accepted_count_o <= 10'd0;
						response_count_o <= 10'd0;
						discarded_count_o <= 10'd0;
					end

					case (state_q)
						STATE_REQUEST: begin
							if (request_fire_w) begin
								owner_index_q <= next_index_q;
								owner_generation_q <= active_generation_q;
								accepted_count_o <= accepted_count_o + 10'd1;
								if (next_index_q != 9'd511) begin
									next_index_q <= next_index_q + 9'd1;
								end
								state_q <= STATE_RESPONSE;
							end
						end

						STATE_RESPONSE: begin
							if (dram_resp_valid_i) begin
								response_count_o <= response_count_o + 10'd1;
								if (!owner_matches_active_w) begin
									discarded_count_o <= discarded_count_o + 10'd1;
									stale_response_discarded_o <= 1'b1;
									state_q <= STATE_IDLE;
								end else if (owner_index_q == 9'd511) begin
									state_q <= STATE_IDLE;
									snapshot_valid_o <= 1'b1;
									done_o <= 1'b1;
									completed_generation_o <= active_generation_q;
								end else if (request_fire_w) begin
									owner_index_q <= next_index_q;
									owner_generation_q <= active_generation_q;
									accepted_count_o <= accepted_count_o + 10'd1;
									if (next_index_q != 9'd511) begin
										next_index_q <= next_index_q + 9'd1;
									end
									state_q <= STATE_RESPONSE;
								end else begin
									state_q <= STATE_REQUEST;
								end
							end
						end

						STATE_DISCARD: begin
							if (dram_resp_valid_i) begin
								drain_stale_response_task;
							end
						end

						// IDLE: the shared check above already flags any
						// unexpected response.
						default: begin
						end
					endcase
				end
			end
		end
	end

endmodule


// Pipelined reader for one 16-halfword world descriptor.
//
// Requests and responses advance in order, with separate positions so stalls do
// not duplicate or mislabel data. A response during a CE pause is consumed once.
//
// Raw-clock abort cancels offers and drains accepted stale reads before restart.

module vip_xp_descriptor_fetch
(
	input  wire         clk_i,
	input  wire         reset_i,
	input  wire         ce_i,
	input  wire         abort_i,

	input  wire         start_i,
	input  wire [4:0]   world_i,
	output wire         start_ready_o,

	output wire         snapshot_req_o,
	output wire [8:0]   snapshot_addr_o,
	input  wire         snapshot_ready_i,
	input  wire         snapshot_rvalid_i,
	input  wire [15:0]  snapshot_rdata_i,

	output wire         busy_o,
	output reg          done_o,
	output reg  [4:0]   world_tag_o,
	output reg  [255:0] descriptor_o,

	output reg  [15:0]  word0_o,
	output reg          word0_valid_o,
	output reg          end_marker_o,
	output reg          dummy_world_o,
	output reg  [1:0]   world_kind_o,

	output reg          word_accept_o,
	output reg  [3:0]   word_accept_index_o,
	output reg  [4:0]   word_accept_count_o,
	output wire [3:0]   current_word_index_o,
	output wire         cleanup_busy_o
);

	localparam [1:0] STATE_IDLE        = 2'd0;
	localparam [1:0] STATE_ACTIVE      = 2'd1;
	localparam [1:0] STATE_ABORT_DRAIN = 2'd2;

	reg [1:0]  state_q;
	reg [3:0]  request_index_q;
	reg [4:0]  response_count_q;
	reg [4:0]  abort_remaining_q;
	reg        response_capture_valid_q;
	reg [15:0] response_capture_data_q;
	reg        drain_response_seen_q;

	wire request_fire_w = ce_i && snapshot_req_o && snapshot_ready_i;
	wire [4:0] outstanding_count_w =
		word_accept_count_o - response_count_q;
	wire response_outstanding_w =
		response_count_q < word_accept_count_o;
	wire response_available_w = response_outstanding_w &&
		(response_capture_valid_q || snapshot_rvalid_i);
	wire [15:0] response_data_w = response_capture_valid_q ?
		response_capture_data_q : snapshot_rdata_i;

	assign start_ready_o = ce_i && !reset_i && !abort_i &&
		(state_q == STATE_IDLE);
	assign snapshot_req_o = !reset_i && !abort_i &&
		(state_q == STATE_ACTIVE) &&
		(word_accept_count_o < 5'd16);
	assign snapshot_addr_o = {world_tag_o, request_index_q};
	assign busy_o = !reset_i && (state_q != STATE_IDLE);
	assign current_word_index_o = request_index_q;
	assign cleanup_busy_o = (state_q == STATE_ABORT_DRAIN);

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			request_index_q <= 4'd0;
			response_count_q <= 5'd0;
			abort_remaining_q <= 5'd0;
			response_capture_valid_q <= 1'b0;
			response_capture_data_q <= 16'd0;
			drain_response_seen_q <= 1'b0;
			done_o <= 1'b0;
			world_tag_o <= 5'd0;
			descriptor_o <= 256'd0;
			word0_o <= 16'd0;
			word0_valid_o <= 1'b0;
			end_marker_o <= 1'b0;
			dummy_world_o <= 1'b0;
			world_kind_o <= 2'd0;
			word_accept_o <= 1'b0;
			word_accept_index_o <= 4'd0;
			word_accept_count_o <= 5'd0;
		end else begin
			// Drain each raw-clock response once, including during a CE pause.
			if (state_q == STATE_ABORT_DRAIN) begin
				done_o <= 1'b0;
				word_accept_o <= 1'b0;
				response_capture_valid_q <= 1'b0;
				if (abort_i) begin
					descriptor_o <= 256'd0;
					word0_o <= 16'd0;
					word0_valid_o <= 1'b0;
					end_marker_o <= 1'b0;
					dummy_world_o <= 1'b0;
					world_kind_o <= 2'd0;
				end

				if (!snapshot_rvalid_i) begin
					drain_response_seen_q <= 1'b0;
				end else if (!drain_response_seen_q) begin
					if (abort_remaining_q <= 5'd1) begin
						state_q <= STATE_IDLE;
						abort_remaining_q <= 5'd0;
						drain_response_seen_q <= 1'b0;
					end else begin
						abort_remaining_q <= abort_remaining_q - 5'd1;
						drain_response_seen_q <= !ce_i;
					end
				end else if (ce_i) begin
					// Do not count a held response again on this edge.
					drain_response_seen_q <= 1'b0;
				end
			end else if (abort_i) begin
				// Raw abort drops the offer and partial descriptor.
				done_o <= 1'b0;
				word_accept_o <= 1'b0;
				descriptor_o <= 256'd0;
				word0_o <= 16'd0;
				word0_valid_o <= 1'b0;
				end_marker_o <= 1'b0;
				dummy_world_o <= 1'b0;
				world_kind_o <= 2'd0;
				response_capture_valid_q <= 1'b0;

				if ((state_q != STATE_ACTIVE) ||
					(outstanding_count_w == 5'd0)) begin
					state_q <= STATE_IDLE;
					abort_remaining_q <= 5'd0;
					drain_response_seen_q <= 1'b0;
				end else if (response_capture_valid_q ||
					snapshot_rvalid_i) begin
					if (outstanding_count_w == 5'd1) begin
						state_q <= STATE_IDLE;
						abort_remaining_q <= 5'd0;
					end else begin
						state_q <= STATE_ABORT_DRAIN;
						abort_remaining_q <=
							outstanding_count_w - 5'd1;
					end
					drain_response_seen_q <=
						!ce_i && snapshot_rvalid_i;
				end else begin
					state_q <= STATE_ABORT_DRAIN;
					abort_remaining_q <= outstanding_count_w;
					drain_response_seen_q <= 1'b0;
				end
			end else begin
				// Save a response that arrives while CE is paused.
				if (!ce_i && (state_q == STATE_ACTIVE) &&
					response_outstanding_w && snapshot_rvalid_i &&
					!response_capture_valid_q) begin
					response_capture_valid_q <= 1'b1;
					response_capture_data_q <= snapshot_rdata_i;
				end

				if (ce_i) begin
					done_o <= 1'b0;
					word_accept_o <= 1'b0;

					case (state_q)
						STATE_IDLE: begin
							if (start_i) begin
								state_q <= STATE_ACTIVE;
								world_tag_o <= world_i;
								request_index_q <= 4'd0;
								response_count_q <= 5'd0;
								abort_remaining_q <= 5'd0;
								response_capture_valid_q <= 1'b0;
								drain_response_seen_q <= 1'b0;
								descriptor_o <= 256'd0;
								word0_o <= 16'd0;
								word0_valid_o <= 1'b0;
								end_marker_o <= 1'b0;
								dummy_world_o <= 1'b0;
								world_kind_o <= 2'd0;
								word_accept_index_o <= 4'd0;
								word_accept_count_o <= 5'd0;
							end
						end

						STATE_ACTIVE: begin
							if (request_fire_w) begin
								word_accept_o <= 1'b1;
								word_accept_index_o <= request_index_q;
								word_accept_count_o <=
									word_accept_count_o + 5'd1;
								if (request_index_q != 4'd15) begin
									request_index_q <=
										request_index_q + 4'd1;
								end
							end

							if (response_available_w) begin
								descriptor_o[
									{response_count_q[3:0], 4'b0000} +: 16
								] <= response_data_w;
								response_capture_valid_q <= 1'b0;
								response_count_q <= response_count_q + 5'd1;

								if (response_count_q == 5'd0) begin
									word0_o <= response_data_w;
									word0_valid_o <= 1'b1;
									end_marker_o <= response_data_w[6];
									dummy_world_o <=
										(response_data_w[15:14] == 2'b00);
									world_kind_o <= response_data_w[13:12];
								end

								if (response_count_q == 5'd15) begin
									state_q <= STATE_IDLE;
									done_o <= 1'b1;
								end
							end
						end

						default: begin
							state_q <= STATE_IDLE;
							response_capture_valid_q <= 1'b0;
							drain_response_seen_q <= 1'b0;
						end
					endcase
				end
			end
		end
	end

endmodule


// Stereo row store used by the renderers.
//
// Each eye uses four 128x16 block RAM banks. Column[1:0] selects the bank and
// column[8:2] selects addresses 0..95.
//
// A token carries eight pixels per eye. Two stages write four banks at a time,
// allowing one token every two enabled clocks.
//
// `active` clips the destination and `opaque` controls source transparency.
//
// Affine prepare reads four pixels per eye. Commit writes the merged values one
// enabled edge later.

module vip_xp_row_strip_store
(
	input  wire                 clk_i,
	input  wire                 reset_i,
	input  wire                 ce_i,
	input  wire                 abort_i,

	// Initialize all banks and both eyes with BKCOL.
	input  wire                 init_start_i,
	input  wire [15:0]          init_bkcol_word_i,
	output wire                 init_ready_o,
	output wire                 init_active_o,
	output reg                  init_done_o,

	// Eight-pixel stereo row token.
	input  wire                 producer_valid_i,
	output wire                 producer_ready_o,
	input  wire [2:0]           producer_row_i,
	input  wire signed [15:0]   producer_left_base_x_i,
	input  wire                 producer_left_enable_i,
	input  wire [7:0]           producer_left_active_i,
	input  wire [7:0]           producer_left_opaque_i,
	input  wire [15:0]          producer_left_values_i,
	input  wire signed [15:0]   producer_right_base_x_i,
	input  wire                 producer_right_enable_i,
	input  wire [7:0]           producer_right_active_i,
	input  wire [7:0]           producer_right_opaque_i,
	input  wire [15:0]          producer_right_values_i,
	output reg                  producer_done_o,

	// Four-pixel Affine prepare and commit interface.
	input  wire                 affine_prepare_valid_i,
	output wire                 affine_prepare_ready_o,
	output wire                 affine_prepare_accept_o,
	input  wire [2:0]           affine_prepare_row_i,
	input  wire signed [15:0]   affine_prepare_left_base_x_i,
	input  wire                 affine_prepare_left_enable_i,
	input  wire signed [15:0]   affine_prepare_right_base_x_i,
	input  wire                 affine_prepare_right_enable_i,
	input  wire                 affine_commit_valid_i,
	output wire                 affine_commit_ready_o,
	output wire                 affine_commit_accept_o,
	input  wire [3:0]           affine_commit_left_active_i,
	input  wire [3:0]           affine_commit_left_opaque_i,
	input  wire [7:0]           affine_commit_left_values_i,
	input  wire [3:0]           affine_commit_right_active_i,
	input  wire [3:0]           affine_commit_right_opaque_i,
	input  wire [7:0]           affine_commit_right_values_i,
	output wire                 affine_active_o,
	output wire                 affine_quiescent_o,
	output reg                  affine_done_o,

	// Completed strip output, left columns first and then right columns.
	input  wire                 loadout_start_i,
	input  wire [4:0]           loadout_strip_i,
	input  wire                 loadout_fb_i,
	output wire                 loadout_ready_o,
	output wire                 loadout_active_o,
	output reg                  loadout_done_o,
	output wire                 vrm_req_o,
	output wire                 vrm_write_o,
	output wire [15:0]          vrm_addr_o,
	output wire [15:0]          vrm_wdata_o,
	input  wire                 vrm_accept_i,
	output wire                 store_busy_o,
	output wire                 producer_active_o,

	// State and activity diagnostics.
	output wire [2:0]           state_o,
`ifndef SYNTHESIS
	output reg  [6:0]           diag_init_address_count_o,
	output reg  [9:0]           diag_init_bank_write_count_o,
	output reg  [31:0]          diag_producer_accept_count_o,
	output reg  [31:0]          diag_producer_done_count_o,
	output reg  [31:0]          diag_producer_access_count_o,
	output reg  [31:0]          diag_producer_pixel_write_count_o,
	output reg  [7:0]           diag_loadout_prefetch_count_o,
	output reg  [9:0]           diag_loadout_accept_count_o,
	output reg  [15:0]          diag_loadout_internal_stall_count_o
`else
	output wire [6:0]           diag_init_address_count_o,
	output wire [9:0]           diag_init_bank_write_count_o,
	output wire [31:0]          diag_producer_accept_count_o,
	output wire [31:0]          diag_producer_done_count_o,
	output wire [31:0]          diag_producer_access_count_o,
	output wire [31:0]          diag_producer_pixel_write_count_o,
	output wire [7:0]           diag_loadout_prefetch_count_o,
	output wire [9:0]           diag_loadout_accept_count_o,
	output wire [15:0]          diag_loadout_internal_stall_count_o
`endif
);

	localparam [2:0]
		STATE_IDLE          = 3'd0,
		STATE_INIT          = 3'd1,
		STATE_PRODUCER_0    = 3'd2,
		STATE_PRODUCER_1    = 3'd3,
		STATE_LOAD_PREFETCH   = 3'd4,
		STATE_LOAD_STREAM     = 3'd5,
		STATE_AFFINE_PREFETCH = 3'd6,
		STATE_AFFINE_READY    = 3'd7;

	reg [2:0] state_q;
	reg [6:0] init_addr_q;
	reg [15:0] init_bkcol_q;

	reg [2:0] producer_row_q;
	reg signed [15:0] producer_left_base_x_q;
	reg producer_left_enable_q;
	reg [7:0] producer_left_active_q;
	reg [7:0] producer_left_opaque_q;
	reg [15:0] producer_left_values_q;
	reg signed [15:0] producer_right_base_x_q;
	reg producer_right_enable_q;
	reg [7:0] producer_right_active_q;
	reg [7:0] producer_right_opaque_q;
	reg [15:0] producer_right_values_q;

	reg [2:0] affine_row_q;
	reg signed [15:0] affine_left_base_x_q;
	reg affine_left_enable_q;
	reg signed [15:0] affine_right_base_x_q;
	reg affine_right_enable_q;
	reg [15:0] affine_left_old_q [0:3];
	reg [15:0] affine_right_old_q [0:3];

	reg loadout_eye_q;
	reg [8:0] loadout_column_q;
	reg [4:0] loadout_strip_q;
	reg loadout_fb_q;
	reg [6:0] prefetch_addr_q;
	reg [1:0] prefetch_wait_q;
	reg load_next_valid_q;
	reg right_seed0_valid_q;
	reg right_seed1_valid_q;
	reg [15:0] load_current_q [0:3];
	reg [15:0] load_next_q [0:3];
	reg [15:0] right_seed0_q [0:3];
	reg [15:0] right_seed1_q [0:3];

	reg [3:0] left_forward_valid_q;
	reg [3:0] right_forward_valid_q;
	reg [15:0] left_forward_data_q [0:3];
	reg [15:0] right_forward_data_q [0:3];

	wire [6:0] left_write_addr_w [0:3];
	wire [6:0] right_write_addr_w [0:3];
	wire [6:0] left_read_addr_w [0:3];
	wire [6:0] right_read_addr_w [0:3];
	wire left_write_pixel_w [0:3];
	wire right_write_pixel_w [0:3];
	wire [1:0] left_write_value_w [0:3];
	wire [1:0] right_write_value_w [0:3];
	wire [6:0] affine_left_addr_w [0:3];
	wire [6:0] affine_right_addr_w [0:3];
	wire [6:0] affine_left_read_addr_w [0:3];
	wire [6:0] affine_right_read_addr_w [0:3];
	wire affine_left_write_pixel_w [0:3];
	wire affine_right_write_pixel_w [0:3];
	wire [1:0] affine_left_write_value_w [0:3];
	wire [1:0] affine_right_write_value_w [0:3];

	wire [6:0] ram_left_a_addr_w [0:3];
	wire [6:0] ram_right_a_addr_w [0:3];
	wire ram_left_a_wren_w [0:3];
	wire ram_right_a_wren_w [0:3];
	wire [15:0] ram_left_a_wdata_w [0:3];
	wire [15:0] ram_right_a_wdata_w [0:3];
	wire [6:0] ram_left_b_addr_w [0:3];
	wire [6:0] ram_right_b_addr_w [0:3];
	wire [15:0] ram_left_b_data_w [0:3];
	wire [15:0] ram_right_b_data_w [0:3];
	wire [15:0] ram_left_old_w [0:3];
	wire [15:0] ram_right_old_w [0:3];

	wire producer_access_active_w =
		(state_q == STATE_PRODUCER_0) ||
		(state_q == STATE_PRODUCER_1);
	wire producer_write_access_w = state_q == STATE_PRODUCER_1;
	wire producer_accept_w = producer_valid_i && producer_ready_o;
	wire producer_read_live_w = producer_accept_w &&
		((state_q == STATE_IDLE) || (state_q == STATE_PRODUCER_1));
	wire producer_read_context_w =
		(state_q == STATE_PRODUCER_0) ||
		(state_q == STATE_PRODUCER_1) ||
		producer_read_live_w;
	wire affine_prepare_accept_w =
		affine_prepare_valid_i && affine_prepare_ready_o;
	wire affine_commit_accept_w =
		affine_commit_valid_i && affine_commit_ready_o;
	wire affine_read_live_w = affine_prepare_accept_w;
	wire affine_read_context_w =
		(state_q == STATE_AFFINE_PREFETCH) || affine_read_live_w;
	// Hold port B data while CE is low because the RAM has no clock enable.
	wire producer_read_access_w =
		((state_q == STATE_PRODUCER_0) && ce_i) ||
		((state_q == STATE_PRODUCER_1) && !producer_read_live_w);
	wire signed [15:0] producer_read_left_base_x_w =
		producer_read_live_w ?
		producer_left_base_x_i : producer_left_base_x_q;
	wire signed [15:0] producer_read_right_base_x_w =
		producer_read_live_w ?
		producer_right_base_x_i : producer_right_base_x_q;
	wire signed [15:0] affine_read_left_base_x_w =
		affine_read_live_w ?
		affine_prepare_left_base_x_i : affine_left_base_x_q;
	wire signed [15:0] affine_read_right_base_x_w =
		affine_read_live_w ?
		affine_prepare_right_base_x_i : affine_right_base_x_q;

	wire loadout_boundary_w = loadout_column_q[1:0] == 2'd3;
	wire loadout_left_final_w = !loadout_eye_q &&
		(loadout_column_q == 9'd383);
	wire loadout_right_final_w = loadout_eye_q &&
		(loadout_column_q == 9'd383);
	wire loadout_boundary_ready_w = !loadout_boundary_w ||
		loadout_right_final_w ||
		(loadout_left_final_w ?
		 (right_seed0_valid_q && right_seed1_valid_q) :
		 load_next_valid_q);
	wire loadout_accept_w = ce_i && vrm_req_o && vrm_accept_i;

	function automatic [1:0] bank_offset_fn;
		input [1:0] start_bank;
		input [1:0] bank;
		begin
			bank_offset_fn = bank - start_bank;
		end
	endfunction

	function automatic [2:0] pixel_index_fn;
		input state;
		input [1:0] offset;
		begin
			pixel_index_fn = {state, 2'b00} + {1'b0, offset};
		end
	endfunction

	function automatic pixel_flag_fn;
		input [7:0] flags;
		input [2:0] index;
		begin
			pixel_flag_fn = flags[index];
		end
	endfunction

	function automatic [1:0] pixel_value_fn;
		input [15:0] values;
		input [2:0] index;
		begin
			pixel_value_fn = values[{index, 1'b0} +: 2];
		end
	endfunction

	function automatic half_pixel_flag_fn;
		input [3:0] flags;
		input [1:0] index;
		begin
			half_pixel_flag_fn = flags[index];
		end
	endfunction

	function automatic [1:0] half_pixel_value_fn;
		input [7:0] values;
		input [1:0] index;
		begin
			half_pixel_value_fn = values[{index, 1'b0} +: 2];
		end
	endfunction

	function automatic signed [16:0] pixel_column_fn;
		input signed [15:0] base_x;
		input state;
		input [1:0] offset;
		begin
			pixel_column_fn = {{1{base_x[15]}}, base_x} +
				$signed({14'd0, state, 2'b00}) +
				$signed({15'd0, offset});
		end
	endfunction

	/* verilator lint_off UNUSEDSIGNAL */
	function automatic [6:0] pixel_address_fn;
		input signed [15:0] base_x;
		input state;
		input [1:0] offset;
		reg signed [16:0] column;
		begin
			column = pixel_column_fn(base_x, state, offset);
			pixel_address_fn = column[8:2];
		end
	endfunction
	/* verilator lint_on UNUSEDSIGNAL */

	function automatic [15:0] merge_pixel_fn;
		input [15:0] old_word;
		input [2:0] row;
		input [1:0] value;
		reg [15:0] bit_mask;
		reg [15:0] positioned_value;
		begin
			bit_mask = 16'h0003 << {row, 1'b0};
			positioned_value = {14'd0, value} << {row, 1'b0};
			merge_pixel_fn =
				(old_word & ~bit_mask) | (positioned_value & bit_mask);
		end
	endfunction

	function automatic [15:0] framebuffer_word_addr_fn;
		input eye;
		input framebuffer;
		input [8:0] column;
		input [4:0] strip;
		reg [15:0] base;
		begin
			case ({eye, framebuffer})
				2'b00: base = 16'h0000;
				2'b01: base = 16'h4000;
				2'b10: base = 16'h8000;
				default: base = 16'hc000;
			endcase
			framebuffer_word_addr_fn =
				base + {2'd0, column, 5'd0} + {11'd0, strip};
		end
	endfunction

	function automatic [2:0] popcount4_fn;
		input [3:0] bits;
		begin
			popcount4_fn =
				{2'd0, bits[0]} + {2'd0, bits[1]} +
				{2'd0, bits[2]} + {2'd0, bits[3]};
		end
	endfunction

	// Priority is init, producer, Affine prepare, then loadout. Affine owns the
	// store until commit or abort.
	assign init_ready_o = ce_i && !reset_i && !abort_i &&
		!init_done_o && !producer_done_o && !loadout_done_o &&
		(state_q == STATE_IDLE);
	assign init_active_o = !abort_i && (state_q == STATE_INIT);
	assign producer_ready_o = ce_i && !reset_i && !abort_i &&
		!producer_done_o && !init_start_i &&
		((state_q == STATE_IDLE) || (state_q == STATE_PRODUCER_1));
	assign affine_prepare_ready_o = ce_i && !reset_i && !abort_i &&
		!init_start_i && !producer_valid_i &&
		(state_q == STATE_IDLE);
	assign affine_prepare_accept_o = affine_prepare_accept_w;
	assign affine_commit_ready_o = ce_i && !reset_i && !abort_i &&
		(state_q == STATE_AFFINE_READY);
	assign affine_commit_accept_o = affine_commit_accept_w;
	assign affine_active_o = !reset_i && !abort_i &&
		((state_q == STATE_AFFINE_PREFETCH) ||
		 (state_q == STATE_AFFINE_READY));
	// Quiescent means the store owns no pending work.
	assign affine_quiescent_o = !reset_i &&
		(state_q == STATE_IDLE);
	assign loadout_ready_o = ce_i && !reset_i && !abort_i &&
		!init_done_o && !producer_done_o && !loadout_done_o &&
		(state_q == STATE_IDLE) && !init_start_i && !producer_valid_i &&
		!affine_prepare_valid_i &&
		(loadout_strip_i < 5'd28);
	assign loadout_active_o = !abort_i &&
		((state_q == STATE_LOAD_PREFETCH) ||
		 (state_q == STATE_LOAD_STREAM));
	assign store_busy_o = state_q != STATE_IDLE;
	assign producer_active_o = producer_access_active_w;

	assign vrm_req_o = !reset_i && !abort_i &&
		(state_q == STATE_LOAD_STREAM) && loadout_boundary_ready_w;
	assign vrm_write_o = vrm_req_o;
	assign vrm_addr_o = framebuffer_word_addr_fn(
		loadout_eye_q,
		loadout_fb_q,
		loadout_column_q,
		loadout_strip_q
	);
	assign vrm_wdata_o = load_current_q[loadout_column_q[1:0]];
	assign state_o = state_q;

`ifdef SYNTHESIS
	assign diag_init_address_count_o = 7'd0;
	assign diag_init_bank_write_count_o = 10'd0;
	assign diag_producer_accept_count_o = 32'd0;
	assign diag_producer_done_count_o = 32'd0;
	assign diag_producer_access_count_o = 32'd0;
	assign diag_producer_pixel_write_count_o = 32'd0;
	assign diag_loadout_prefetch_count_o = 8'd0;
	assign diag_loadout_accept_count_o = 10'd0;
	assign diag_loadout_internal_stall_count_o = 16'd0;
`endif

	genvar bank_g;
	generate
		for (bank_g = 0; bank_g < 4; bank_g = bank_g + 1) begin : g_bank
			localparam [1:0] BANK = bank_g[1:0];
			wire [1:0] left_write_offset_w;
			wire [1:0] right_write_offset_w;
			wire [2:0] left_write_index_w;
			wire [2:0] right_write_index_w;
			wire signed [16:0] left_write_column_w;
			wire signed [16:0] right_write_column_w;
			wire [1:0] left_read_offset_w;
			wire [1:0] right_read_offset_w;
			wire [1:0] affine_left_write_offset_w;
			wire [1:0] affine_right_write_offset_w;
			wire signed [16:0] affine_left_write_column_w;
			wire signed [16:0] affine_right_write_column_w;
			wire [1:0] affine_left_read_offset_w;
			wire [1:0] affine_right_read_offset_w;

			assign left_write_offset_w = bank_offset_fn(
				producer_left_base_x_q[1:0], BANK);
			assign right_write_offset_w = bank_offset_fn(
				producer_right_base_x_q[1:0], BANK);
			assign left_write_index_w = pixel_index_fn(
				producer_write_access_w, left_write_offset_w);
			assign right_write_index_w = pixel_index_fn(
				producer_write_access_w, right_write_offset_w);
			assign left_write_column_w = pixel_column_fn(
				producer_left_base_x_q,
				producer_write_access_w,
				left_write_offset_w);
			assign right_write_column_w = pixel_column_fn(
				producer_right_base_x_q,
				producer_write_access_w,
				right_write_offset_w);
			assign left_write_addr_w[bank_g] = left_write_column_w[8:2];
			assign right_write_addr_w[bank_g] = right_write_column_w[8:2];
			assign left_write_value_w[bank_g] = pixel_value_fn(
				producer_left_values_q, left_write_index_w);
			assign right_write_value_w[bank_g] = pixel_value_fn(
				producer_right_values_q, right_write_index_w);
			assign left_write_pixel_w[bank_g] =
				producer_left_enable_q &&
				pixel_flag_fn(producer_left_active_q, left_write_index_w) &&
				pixel_flag_fn(producer_left_opaque_q, left_write_index_w) &&
				!left_write_column_w[16] &&
				(left_write_column_w < 17'sd384);
			assign right_write_pixel_w[bank_g] =
				producer_right_enable_q &&
				pixel_flag_fn(producer_right_active_q, right_write_index_w) &&
				pixel_flag_fn(producer_right_opaque_q, right_write_index_w) &&
				!right_write_column_w[16] &&
				(right_write_column_w < 17'sd384);

			assign left_read_offset_w = bank_offset_fn(
				producer_read_left_base_x_w[1:0], BANK);
			assign right_read_offset_w = bank_offset_fn(
				producer_read_right_base_x_w[1:0], BANK);
			assign left_read_addr_w[bank_g] = pixel_address_fn(
				producer_read_left_base_x_w,
				producer_read_access_w,
				left_read_offset_w);
			assign right_read_addr_w[bank_g] = pixel_address_fn(
				producer_read_right_base_x_w,
				producer_read_access_w,
				right_read_offset_w);

			assign affine_left_write_offset_w = bank_offset_fn(
				affine_left_base_x_q[1:0], BANK);
			assign affine_right_write_offset_w = bank_offset_fn(
				affine_right_base_x_q[1:0], BANK);
			assign affine_left_write_column_w = pixel_column_fn(
				affine_left_base_x_q,
				1'b0,
				affine_left_write_offset_w);
			assign affine_right_write_column_w = pixel_column_fn(
				affine_right_base_x_q,
				1'b0,
				affine_right_write_offset_w);
			assign affine_left_addr_w[bank_g] =
				affine_left_write_column_w[8:2];
			assign affine_right_addr_w[bank_g] =
				affine_right_write_column_w[8:2];
			assign affine_left_write_value_w[bank_g] =
				half_pixel_value_fn(
					affine_commit_left_values_i,
					affine_left_write_offset_w);
			assign affine_right_write_value_w[bank_g] =
				half_pixel_value_fn(
					affine_commit_right_values_i,
					affine_right_write_offset_w);
			assign affine_left_write_pixel_w[bank_g] =
				affine_left_enable_q &&
				half_pixel_flag_fn(
					affine_commit_left_active_i,
					affine_left_write_offset_w) &&
				half_pixel_flag_fn(
					affine_commit_left_opaque_i,
					affine_left_write_offset_w) &&
				!affine_left_write_column_w[16] &&
				(affine_left_write_column_w < 17'sd384);
			assign affine_right_write_pixel_w[bank_g] =
				affine_right_enable_q &&
				half_pixel_flag_fn(
					affine_commit_right_active_i,
					affine_right_write_offset_w) &&
				half_pixel_flag_fn(
					affine_commit_right_opaque_i,
					affine_right_write_offset_w) &&
				!affine_right_write_column_w[16] &&
				(affine_right_write_column_w < 17'sd384);

			assign affine_left_read_offset_w = bank_offset_fn(
				affine_read_left_base_x_w[1:0], BANK);
			assign affine_right_read_offset_w = bank_offset_fn(
				affine_read_right_base_x_w[1:0], BANK);
			assign affine_left_read_addr_w[bank_g] = pixel_address_fn(
				affine_read_left_base_x_w,
				1'b0,
				affine_left_read_offset_w);
			assign affine_right_read_addr_w[bank_g] = pixel_address_fn(
				affine_read_right_base_x_w,
				1'b0,
				affine_right_read_offset_w);

			assign ram_left_old_w[bank_g] = left_forward_valid_q[bank_g] ?
				left_forward_data_q[bank_g] : ram_left_b_data_w[bank_g];
			assign ram_right_old_w[bank_g] = right_forward_valid_q[bank_g] ?
				right_forward_data_q[bank_g] : ram_right_b_data_w[bank_g];

			assign ram_left_a_addr_w[bank_g] =
				(state_q == STATE_INIT) ? init_addr_q :
				(state_q == STATE_AFFINE_READY) ?
				affine_left_addr_w[bank_g] :
				left_write_addr_w[bank_g];
			assign ram_right_a_addr_w[bank_g] =
				(state_q == STATE_INIT) ? init_addr_q :
				(state_q == STATE_AFFINE_READY) ?
				affine_right_addr_w[bank_g] :
				right_write_addr_w[bank_g];
			assign ram_left_a_wren_w[bank_g] =
				ce_i && !reset_i && !abort_i &&
				((state_q == STATE_INIT) ||
				 (affine_commit_accept_w &&
				  affine_left_write_pixel_w[bank_g]) ||
				 (producer_access_active_w && left_write_pixel_w[bank_g]));
			assign ram_right_a_wren_w[bank_g] =
				ce_i && !reset_i && !abort_i &&
				((state_q == STATE_INIT) ||
				 (affine_commit_accept_w &&
				  affine_right_write_pixel_w[bank_g]) ||
				 (producer_access_active_w && right_write_pixel_w[bank_g]));
			assign ram_left_a_wdata_w[bank_g] =
				(state_q == STATE_INIT) ? init_bkcol_q :
				(state_q == STATE_AFFINE_READY) ?
				merge_pixel_fn(
					affine_left_old_q[bank_g],
					affine_row_q,
					affine_left_write_value_w[bank_g]
				) :
				merge_pixel_fn(
					ram_left_old_w[bank_g],
					producer_row_q,
					left_write_value_w[bank_g]
				);
			assign ram_right_a_wdata_w[bank_g] =
				(state_q == STATE_INIT) ? init_bkcol_q :
				(state_q == STATE_AFFINE_READY) ?
				merge_pixel_fn(
					affine_right_old_q[bank_g],
					affine_row_q,
					affine_right_write_value_w[bank_g]
				) :
				merge_pixel_fn(
					ram_right_old_w[bank_g],
					producer_row_q,
					right_write_value_w[bank_g]
				);

			assign ram_left_b_addr_w[bank_g] = loadout_active_o ?
				prefetch_addr_q :
				(affine_read_context_w ?
				 affine_left_read_addr_w[bank_g] :
				 (producer_read_context_w ? left_read_addr_w[bank_g] : 7'd0));
			assign ram_right_b_addr_w[bank_g] = loadout_active_o ?
				prefetch_addr_q :
				(affine_read_context_w ?
				 affine_right_read_addr_w[bank_g] :
				 (producer_read_context_w ? right_read_addr_w[bank_g] : 7'd0));

			/* verilator lint_off PINCONNECTEMPTY */
			cache_ram_dp #(
				.ADDR_WIDTH (7),
				.DATA_WIDTH (16)
			) u_left_bank (
				.clk_i     (clk_i),
				.addr_a_i  (ram_left_a_addr_w[bank_g]),
				.wren_a_i  (ram_left_a_wren_w[bank_g]),
				.wdata_a_i (ram_left_a_wdata_w[bank_g]),
				.q_a_o     (),
				.addr_b_i  (ram_left_b_addr_w[bank_g]),
				.wren_b_i  (1'b0),
				.wdata_b_i (16'd0),
				.q_b_o     (ram_left_b_data_w[bank_g])
			);

			cache_ram_dp #(
				.ADDR_WIDTH (7),
				.DATA_WIDTH (16)
			) u_right_bank (
				.clk_i     (clk_i),
				.addr_a_i  (ram_right_a_addr_w[bank_g]),
				.wren_a_i  (ram_right_a_wren_w[bank_g]),
				.wdata_a_i (ram_right_a_wdata_w[bank_g]),
				.q_a_o     (),
				.addr_b_i  (ram_right_b_addr_w[bank_g]),
				.wren_b_i  (1'b0),
				.wdata_b_i (16'd0),
				.q_b_o     (ram_right_b_data_w[bank_g])
			);
			/* verilator lint_on PINCONNECTEMPTY */
		end
	endgenerate

	// Latch one producer row token and enter the two-CE producer window.
	task capture_producer_token_task;
		begin
			state_q <= STATE_PRODUCER_0;
			producer_row_q <= producer_row_i;
			producer_left_base_x_q <= producer_left_base_x_i;
			producer_left_enable_q <= producer_left_enable_i;
			producer_left_active_q <= producer_left_active_i;
			producer_left_opaque_q <= producer_left_opaque_i;
			producer_left_values_q <= producer_left_values_i;
			producer_right_base_x_q <= producer_right_base_x_i;
			producer_right_enable_q <= producer_right_enable_i;
			producer_right_active_q <= producer_right_active_i;
			producer_right_opaque_q <= producer_right_opaque_i;
			producer_right_values_q <= producer_right_values_i;
`ifndef SYNTHESIS
			diag_producer_accept_count_o <=
				diag_producer_accept_count_o + 32'd1;
`endif
		end
	endtask

`ifndef SYNTHESIS
	task count_producer_access_task;
		begin
			diag_producer_access_count_o <=
				diag_producer_access_count_o + 32'd1;
			diag_producer_pixel_write_count_o <=
				diag_producer_pixel_write_count_o +
				{29'd0, popcount4_fn({
					ram_left_a_wren_w[3], ram_left_a_wren_w[2],
					ram_left_a_wren_w[1], ram_left_a_wren_w[0]
				})} +
				{29'd0, popcount4_fn({
					ram_right_a_wren_w[3], ram_right_a_wren_w[2],
					ram_right_a_wren_w[1], ram_right_a_wren_w[0]
				})};
		end
	endtask
`endif

	integer bank_i;
	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			init_addr_q <= 7'd0;
			init_bkcol_q <= 16'd0;
			producer_row_q <= 3'd0;
			producer_left_base_x_q <= 16'sd0;
			producer_left_enable_q <= 1'b0;
			producer_left_active_q <= 8'd0;
			producer_left_opaque_q <= 8'd0;
			producer_left_values_q <= 16'd0;
			producer_right_base_x_q <= 16'sd0;
			producer_right_enable_q <= 1'b0;
			producer_right_active_q <= 8'd0;
			producer_right_opaque_q <= 8'd0;
			producer_right_values_q <= 16'd0;
			affine_row_q <= 3'd0;
			affine_left_base_x_q <= 16'sd0;
			affine_left_enable_q <= 1'b0;
			affine_right_base_x_q <= 16'sd0;
			affine_right_enable_q <= 1'b0;
			loadout_eye_q <= 1'b0;
			loadout_column_q <= 9'd0;
			loadout_strip_q <= 5'd0;
			loadout_fb_q <= 1'b0;
			prefetch_addr_q <= 7'd0;
			prefetch_wait_q <= 2'd0;
			load_next_valid_q <= 1'b0;
			right_seed0_valid_q <= 1'b0;
			right_seed1_valid_q <= 1'b0;
			left_forward_valid_q <= 4'd0;
			right_forward_valid_q <= 4'd0;
			init_done_o <= 1'b0;
			producer_done_o <= 1'b0;
			affine_done_o <= 1'b0;
			loadout_done_o <= 1'b0;
`ifndef SYNTHESIS
			diag_init_address_count_o <= 7'd0;
			diag_init_bank_write_count_o <= 10'd0;
			diag_producer_accept_count_o <= 32'd0;
			diag_producer_done_count_o <= 32'd0;
			diag_producer_access_count_o <= 32'd0;
			diag_producer_pixel_write_count_o <= 32'd0;
			diag_loadout_prefetch_count_o <= 8'd0;
			diag_loadout_accept_count_o <= 10'd0;
			diag_loadout_internal_stall_count_o <= 16'd0;
`endif
			for (bank_i = 0; bank_i < 4; bank_i = bank_i + 1) begin
				load_current_q[bank_i] <= 16'd0;
				load_next_q[bank_i] <= 16'd0;
				right_seed0_q[bank_i] <= 16'd0;
				right_seed1_q[bank_i] <= 16'd0;
				left_forward_data_q[bank_i] <= 16'd0;
				right_forward_data_q[bank_i] <= 16'd0;
				affine_left_old_q[bank_i] <= 16'd0;
				affine_right_old_q[bank_i] <= 16'd0;
			end
		end else begin
			if (abort_i) begin
				state_q <= STATE_IDLE;
				affine_row_q <= 3'd0;
				affine_left_base_x_q <= 16'sd0;
				affine_left_enable_q <= 1'b0;
				affine_right_base_x_q <= 16'sd0;
				affine_right_enable_q <= 1'b0;
				left_forward_valid_q <= 4'd0;
				right_forward_valid_q <= 4'd0;
				load_next_valid_q <= 1'b0;
				right_seed0_valid_q <= 1'b0;
				right_seed1_valid_q <= 1'b0;
				init_done_o <= 1'b0;
				producer_done_o <= 1'b0;
				affine_done_o <= 1'b0;
				loadout_done_o <= 1'b0;
				for (bank_i = 0; bank_i < 4; bank_i = bank_i + 1) begin
					affine_left_old_q[bank_i] <= 16'd0;
					affine_right_old_q[bank_i] <= 16'd0;
				end
			end else if (ce_i) begin
				init_done_o <= 1'b0;
				producer_done_o <= 1'b0;
				affine_done_o <= 1'b0;
				loadout_done_o <= 1'b0;

				// Forward same-address writes instead of relying on M10K collision mode.
				if (producer_access_active_w) begin
					for (bank_i = 0; bank_i < 4; bank_i = bank_i + 1) begin
						left_forward_valid_q[bank_i] <=
							ram_left_a_wren_w[bank_i] &&
							(ram_left_a_addr_w[bank_i] ==
							 ram_left_b_addr_w[bank_i]);
						right_forward_valid_q[bank_i] <=
							ram_right_a_wren_w[bank_i] &&
							(ram_right_a_addr_w[bank_i] ==
							 ram_right_b_addr_w[bank_i]);
						left_forward_data_q[bank_i] <=
							ram_left_a_wdata_w[bank_i];
						right_forward_data_q[bank_i] <=
							ram_right_a_wdata_w[bank_i];
					end
				end else if (producer_accept_w ||
					affine_prepare_accept_w) begin
					left_forward_valid_q <= 4'd0;
					right_forward_valid_q <= 4'd0;
				end

				case (state_q)
					STATE_IDLE: begin
						if (init_start_i && init_ready_o) begin
							state_q <= STATE_INIT;
							init_addr_q <= 7'd0;
							init_bkcol_q <= init_bkcol_word_i;
`ifndef SYNTHESIS
							diag_init_address_count_o <= 7'd0;
							diag_init_bank_write_count_o <= 10'd0;
`endif
						end else if (producer_accept_w) begin
							capture_producer_token_task;
						end else if (affine_prepare_accept_w) begin
							state_q <= STATE_AFFINE_PREFETCH;
							affine_row_q <= affine_prepare_row_i;
							affine_left_base_x_q <=
								affine_prepare_left_base_x_i;
							affine_left_enable_q <=
								affine_prepare_left_enable_i;
							affine_right_base_x_q <=
								affine_prepare_right_base_x_i;
							affine_right_enable_q <=
								affine_prepare_right_enable_i;
						end else if (loadout_start_i && loadout_ready_o) begin
							state_q <= STATE_LOAD_PREFETCH;
							loadout_eye_q <= 1'b0;
							loadout_column_q <= 9'd0;
							loadout_strip_q <= loadout_strip_i;
							loadout_fb_q <= loadout_fb_i;
							prefetch_addr_q <= 7'd0;
							prefetch_wait_q <= 2'd2;
							load_next_valid_q <= 1'b0;
							right_seed0_valid_q <= 1'b0;
							right_seed1_valid_q <= 1'b0;
`ifndef SYNTHESIS
							diag_loadout_prefetch_count_o <= 8'd0;
							diag_loadout_accept_count_o <= 10'd0;
							diag_loadout_internal_stall_count_o <= 16'd0;
`endif
						end
					end

					STATE_INIT: begin
`ifndef SYNTHESIS
						diag_init_address_count_o <=
							diag_init_address_count_o + 7'd1;
						diag_init_bank_write_count_o <=
							diag_init_bank_write_count_o + 10'd8;
`endif
						if (init_addr_q == 7'd95) begin
							state_q <= STATE_IDLE;
							init_done_o <= 1'b1;
						end else begin
							init_addr_q <= init_addr_q + 7'd1;
						end
					end

					STATE_PRODUCER_0: begin
						state_q <= STATE_PRODUCER_1;
`ifndef SYNTHESIS
						count_producer_access_task;
`endif
					end

					STATE_PRODUCER_1: begin
						producer_done_o <= 1'b1;
`ifndef SYNTHESIS
						diag_producer_done_count_o <=
							diag_producer_done_count_o + 32'd1;
						count_producer_access_task;
`endif
						if (producer_accept_w) begin
							capture_producer_token_task;
						end else begin
							state_q <= STATE_IDLE;
						end
					end

					STATE_AFFINE_PREFETCH: begin
						for (bank_i = 0; bank_i < 4;
							bank_i = bank_i + 1) begin
							affine_left_old_q[bank_i] <=
								ram_left_b_data_w[bank_i];
							affine_right_old_q[bank_i] <=
								ram_right_b_data_w[bank_i];
						end
						state_q <= STATE_AFFINE_READY;
					end

					STATE_AFFINE_READY: begin
						if (affine_commit_accept_w) begin
							state_q <= STATE_IDLE;
							affine_done_o <= 1'b1;
						end
					end

					STATE_LOAD_PREFETCH: begin
						if (prefetch_wait_q > 2'd1) begin
							prefetch_wait_q <= prefetch_wait_q - 2'd1;
						end else begin
							for (bank_i = 0; bank_i < 4;
								bank_i = bank_i + 1) begin
								load_current_q[bank_i] <=
									ram_left_b_data_w[bank_i];
								right_seed0_q[bank_i] <=
									ram_right_b_data_w[bank_i];
							end
							right_seed0_valid_q <= 1'b1;
							prefetch_addr_q <= 7'd1;
							prefetch_wait_q <= 2'd2;
							load_next_valid_q <= 1'b0;
`ifndef SYNTHESIS
							diag_loadout_prefetch_count_o <= 8'd1;
`endif
							state_q <= STATE_LOAD_STREAM;
						end
					end

					STATE_LOAD_STREAM: begin
						if (prefetch_wait_q > 2'd1) begin
							prefetch_wait_q <= prefetch_wait_q - 2'd1;
						end else if (prefetch_wait_q == 2'd1) begin
							for (bank_i = 0; bank_i < 4;
								bank_i = bank_i + 1) begin
								load_next_q[bank_i] <= loadout_eye_q ?
									ram_right_b_data_w[bank_i] :
									ram_left_b_data_w[bank_i];
								if (!loadout_eye_q &&
									(prefetch_addr_q == 7'd1)) begin
									right_seed1_q[bank_i] <=
										ram_right_b_data_w[bank_i];
								end
							end
							if (!loadout_eye_q &&
								(prefetch_addr_q == 7'd1)) begin
								right_seed1_valid_q <= 1'b1;
							end
							load_next_valid_q <= 1'b1;
							prefetch_wait_q <= 2'd0;
`ifndef SYNTHESIS
							diag_loadout_prefetch_count_o <=
								diag_loadout_prefetch_count_o + 8'd1;
`endif
						end

						if (loadout_boundary_w &&
							!loadout_boundary_ready_w) begin
`ifndef SYNTHESIS
							diag_loadout_internal_stall_count_o <=
								diag_loadout_internal_stall_count_o + 16'd1;
`endif
						end

						if (loadout_accept_w) begin
`ifndef SYNTHESIS
							diag_loadout_accept_count_o <=
								diag_loadout_accept_count_o + 10'd1;
`endif
							if (loadout_right_final_w) begin
								state_q <= STATE_IDLE;
								loadout_done_o <= 1'b1;
							end else if (loadout_left_final_w) begin
								loadout_eye_q <= 1'b1;
								loadout_column_q <= 9'd0;
								for (bank_i = 0; bank_i < 4;
									bank_i = bank_i + 1) begin
									load_current_q[bank_i] <=
										right_seed0_q[bank_i];
									load_next_q[bank_i] <=
										right_seed1_q[bank_i];
								end
								load_next_valid_q <= 1'b1;
								prefetch_wait_q <= 2'd0;
							end else if (loadout_boundary_w) begin
								loadout_column_q <= loadout_column_q + 9'd1;
								for (bank_i = 0; bank_i < 4;
									bank_i = bank_i + 1) begin
									load_current_q[bank_i] <=
										load_next_q[bank_i];
								end
								load_next_valid_q <= 1'b0;
								if (loadout_column_q[8:2] < 7'd94) begin
									prefetch_addr_q <=
										loadout_column_q[8:2] + 7'd2;
									prefetch_wait_q <= 2'd2;
								end else begin
									prefetch_wait_q <= 2'd0;
								end
							end else begin
								loadout_column_q <= loadout_column_q + 9'd1;
							end
						end
					end

					default: begin
						state_q <= STATE_IDLE;
					end
				endcase
			end
		end
	end

endmodule

// XP framebuffer ownership boundary.
//
// Displayed, drawing, and completed buffers have separate ownership. GCLK
// selects a pending frame, while completion only marks the active target ready.
//
// Silicon unknown: same-edge completion and GCLK ordering is not known. Keep
// the completed frame pending until the next GCLK and raise the diagnostic.

module vip_xp_framebuffer_owner
#(
	parameter RESET_DISPLAY_SELECTED = 1'b0
)
(
	input  wire       clk_i,
	input  wire       reset_i,
	input  wire       ce_i,
	input  wire [5:0] savestate_state_addr_i,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [63:0] savestate_state_wdata_i,
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire       savestate_state_wren_i,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire       sim_snapshot_restore_commit_i,
	input  wire       sim_snapshot_restore_apply_i,
	input  wire [3647:0] sim_snapshot_restore_packet_i,
`endif
`endif
	input  wire       game_start_fire_i,
	input  wire       xp_enable_i,
	input  wire       draw_start_fire_i,
	input  wire       draw_complete_fire_i,
	input  wire       draw_abort_i,

	output reg        display_selected_o,
	output reg        active_valid_o,
	output reg        active_target_o,
	output reg        completed_pending_valid_o,
	output reg        completed_pending_target_o,

	// Next draw target, including a same-edge display change.
	output wire       draw_start_target_o,
	output wire [1:0] xp_busy_o,

	output reg        draw_start_accept_o,
	output reg        completion_commit_o,
	output reg        completion_commit_target_o,
	output reg        display_swap_o,
	output reg        display_swap_target_o,
	output reg        draw_aborted_o,

	output reg        illegal_start_o,
	output reg        illegal_complete_o,
	output reg        completion_gclk_tie_o
);

	wire pending_consumed_w = game_start_fire_i && xp_enable_i &&
		completed_pending_valid_o;
	wire display_after_boundary_w = pending_consumed_w ?
		completed_pending_target_o : display_selected_o;
	wire legal_start_w = draw_start_fire_i && game_start_fire_i &&
		!active_valid_o;
	wire legal_complete_w = draw_complete_fire_i && active_valid_o &&
		(!completed_pending_valid_o || pending_consumed_w);

	assign draw_start_target_o = !display_after_boundary_w;
	assign xp_busy_o = active_valid_o ?
		(active_target_o ? 2'b10 : 2'b01) : 2'b00;

	always @(posedge clk_i
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		or posedge sim_snapshot_restore_commit_i
`endif
`endif
	) begin
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		if (sim_snapshot_restore_commit_i) begin
			if (sim_snapshot_restore_apply_i) begin
				display_selected_o <= sim_snapshot_restore_packet_i[3328];
				active_valid_o <= 1'b0;
				active_target_o <= 1'b0;
				completed_pending_valid_o <= 1'b0;
				completed_pending_target_o <= 1'b0;
				draw_start_accept_o <= 1'b0;
				completion_commit_o <= 1'b0;
				completion_commit_target_o <= 1'b0;
				display_swap_o <= 1'b0;
				display_swap_target_o <= 1'b0;
				draw_aborted_o <= 1'b0;
				illegal_start_o <= 1'b0;
				illegal_complete_o <= 1'b0;
				completion_gclk_tie_o <= 1'b0;
			end
		end else
`endif
`endif
		if (reset_i) begin
			display_selected_o <= RESET_DISPLAY_SELECTED;
			active_valid_o <= 1'b0;
			active_target_o <= !RESET_DISPLAY_SELECTED;
			completed_pending_valid_o <= 1'b0;
			completed_pending_target_o <= !RESET_DISPLAY_SELECTED;
			draw_start_accept_o <= 1'b0;
			completion_commit_o <= 1'b0;
			completion_commit_target_o <= !RESET_DISPLAY_SELECTED;
			display_swap_o <= 1'b0;
			display_swap_target_o <= RESET_DISPLAY_SELECTED;
			draw_aborted_o <= 1'b0;
			illegal_start_o <= 1'b0;
			illegal_complete_o <= 1'b0;
			completion_gclk_tie_o <= 1'b0;
		end else if (savestate_state_wren_i &&
			(savestate_state_addr_i == 6'd48)) begin
			display_selected_o <= savestate_state_wdata_i[8];
			active_valid_o <= 1'b0;
			active_target_o <= !savestate_state_wdata_i[8];
			completed_pending_valid_o <= savestate_state_wdata_i[10];
			completed_pending_target_o <= savestate_state_wdata_i[9];
			draw_start_accept_o <= 1'b0;
			completion_commit_o <= 1'b0;
			completion_commit_target_o <= !RESET_DISPLAY_SELECTED;
			display_swap_o <= 1'b0;
			display_swap_target_o <= savestate_state_wdata_i[8];
			draw_aborted_o <= 1'b0;
			illegal_start_o <= 1'b0;
			illegal_complete_o <= 1'b0;
			completion_gclk_tie_o <= 1'b0;
		end else if (draw_abort_i) begin
			// XPRST aborts unfinished work without changing completed ownership.
			draw_aborted_o <= active_valid_o;
			active_valid_o <= 1'b0;
			draw_start_accept_o <= 1'b0;
			completion_commit_o <= 1'b0;
			display_swap_o <= 1'b0;
			illegal_start_o <= 1'b0;
			illegal_complete_o <= 1'b0;
			completion_gclk_tie_o <= 1'b0;
		end else begin
			draw_aborted_o <= 1'b0;
			if (ce_i) begin
				draw_start_accept_o <= 1'b0;
				completion_commit_o <= 1'b0;
				display_swap_o <= 1'b0;
				illegal_start_o <= 1'b0;
				illegal_complete_o <= 1'b0;
				completion_gclk_tie_o <= 1'b0;

				// Select only a commit that was already pending.
				if (pending_consumed_w) begin
					display_selected_o <= completed_pending_target_o;
					completed_pending_valid_o <= 1'b0;
					display_swap_o <= 1'b1;
					display_swap_target_o <= completed_pending_target_o;
				end

				if (draw_start_fire_i) begin
					if (legal_start_w) begin
						active_valid_o <= 1'b1;
						active_target_o <= draw_start_target_o;
						draw_start_accept_o <= 1'b1;
					end else begin
						illegal_start_o <= 1'b1;
					end
				end

				if (draw_complete_fire_i) begin
					if (game_start_fire_i) begin
						completion_gclk_tie_o <= 1'b1;
					end
					if (legal_complete_w) begin
						active_valid_o <= 1'b0;
						completed_pending_valid_o <= 1'b1;
						completed_pending_target_o <= active_target_o;
						completion_commit_o <= 1'b1;
						completion_commit_target_o <= active_target_o;
					end else begin
						illegal_complete_o <= 1'b1;
					end
				end
			end
		end
	end

endmodule


// XP draw coordinator.
//
// The coordinator sequences descriptor, renderer, initialization, and loadout
// requests. World work pauses the strip budget. Silicon unknown: measurements
// give 54,688 non-world cycles but not their exact internal split, so the first
// and later strip budgets are calibrated to that total.

module vip_xp_render_coordinator
#(
	parameter integer DRAW_SETUP_CYCLES = 32,
	parameter integer FIRST_STRIP_SERVICE_CYCLES = 2033,
	parameter integer LATER_STRIP_SERVICE_CYCLES = 1949,
	parameter integer END_INTERVAL_CYCLES = 11,
	parameter integer DUMMY_FIRST_INTERVAL_CYCLES = 21,
	parameter integer DUMMY_INTERVAL_CYCLES = 20,
	parameter integer SBOUT_CYCLES = 1120,
	parameter integer XPRST_RECOVERY_CYCLES = 24
)
(
	input  wire         clk_i,
	input  wire         reset_i,
	input  wire         ce_i,

	input  wire         game_start_fire_i,
	input  wire         xp_enable_i,
	input  wire         xprst_i,
	input  wire [4:0]   xp_sbcmp_i,
	input  wire         owner_draw_target_for_start_i,
	input  wire [1:0]   bkcol_register_i,
	input  wire [1:0]   bkcol_active_i,

	input  wire         snapshot_start_ready_i,
	input  wire         snapshot_busy_i,
	input  wire         snapshot_done_i,
	input  wire         snapshot_valid_i,
	input  wire         snapshot_cleanup_busy_i,
	input  wire         snapshot_head_rvalid_i,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [15:0]  snapshot_head_rdata_i,
	/* verilator lint_on UNUSEDSIGNAL */

	input  wire         descriptor_fetch_start_ready_i,
	input  wire         descriptor_fetch_busy_i,
	input  wire         descriptor_fetch_done_i,
	input  wire [255:0] descriptor_fetch_descriptor_i,
	input  wire         descriptor_fetch_end_i,
	input  wire         descriptor_fetch_dummy_i,
	input  wire [1:0]   descriptor_fetch_kind_i,

	input  wire         strip_init_start_ready_i,
	input  wire         strip_init_active_i,
	input  wire         strip_init_done_i,
	input  wire         strip_load_start_ready_i,
	input  wire         strip_load_active_i,
	input  wire         strip_load_done_i,
	input  wire         engine_cmd_ready_i,
	input  wire         engine_done_i,
	input  wire         engine_cleanup_busy_i,

	output wire         snapshot_start_o,
	output wire         snapshot_abort_o,
	output wire         snapshot_head_read_o,
	output wire [8:0]   snapshot_head_addr_o,

	output wire         descriptor_fetch_start_o,
	output wire [4:0]   descriptor_fetch_world_o,
	output wire         descriptor_fetch_abort_o,

	output wire         strip_init_start_o,
	output wire [15:0]  strip_init_bkcol_word_o,
	output wire         strip_load_start_o,
	output wire [4:0]   strip_load_strip_o,
	output wire         strip_load_draw_fb_o,
	output wire         strip_abort_o,

	output wire         engine_cmd_valid_o,
	output wire [1:0]   engine_cmd_kind_o,
	output wire [4:0]   engine_cmd_strip_o,
	output wire [4:0]   engine_cmd_world_o,
	output wire [255:0] engine_cmd_descriptor_o,
	output wire         engine_cmd_first_visit_o,
	output wire         engine_abort_o,

	output wire         draw_start_fire_o,
	output wire         first_group_done_fire_o,
	output wire         sb_hit_fire_o,
	output wire         xp_end_fire_o,
	output wire         timeerr_fire_o,
	output wire         owner_draw_complete_fire_o,

	output wire         drawing_o,
	output wire [1:0]   xp_busy_o,
	output wire [4:0]   xp_strip_o,
	output wire [4:0]   xp_sbcount_o,
	output wire         xp_sbout_o,
	output wire         xp_overtime_o,
	output wire         draw_fb_o,

	output wire [3:0]   state_o,
	output wire [4:0]   world_o,
	output wire [15:0]  draw_setup_remaining_o,
	output wire [15:0]  strip_service_remaining_o,
	output wire [5:0]   world_interval_elapsed_o,
	output wire [5:0]   world_interval_target_o,
	output wire [7:0]   recovery_remaining_o,
	output wire         strip_start_fire_o,
	output wire         strip_commit_fire_o,
	output wire         completion_gclk_tie_o,
	output wire         classification_mismatch_o,
	output wire         peripheral_busy_o
);

	localparam [3:0] STATE_IDLE         = 4'd0;
	localparam [3:0] STATE_RECOVERY     = 4'd1;
	localparam [3:0] STATE_DRAW_SETUP   = 4'd2;
	localparam [3:0] STATE_STRIP_LAUNCH = 4'd3;
	localparam [3:0] STATE_STRIP_PREP   = 4'd4;
	localparam [3:0] STATE_HEAD_ISSUE   = 4'd5;
	localparam [3:0] STATE_HEAD_WAIT    = 4'd6;
	localparam [3:0] STATE_WORLD_DELAY  = 4'd7;
	localparam [3:0] STATE_FETCH_START  = 4'd8;
	localparam [3:0] STATE_FETCH_WAIT   = 4'd9;
	localparam [3:0] STATE_ENGINE_START = 4'd10;
	localparam [3:0] STATE_ENGINE_WAIT  = 4'd11;
	localparam [3:0] STATE_LOAD_START   = 4'd12;
	localparam [3:0] STATE_LOAD_WAIT    = 4'd13;
	localparam [3:0] STATE_STRIP_PAD    = 4'd14;

	reg [3:0]   state_q;
	reg         drawing_q;
	reg         draw_fb_q;
	reg [1:0]   bkcol_active_draw_q;
	reg [1:0]   bkcol_register_draw_q;
	reg [4:0]   strip_q;
	reg [4:0]   world_q;
	reg [15:0]  draw_setup_remaining_q;
	reg [15:0]  strip_service_remaining_q;
	reg [5:0]   world_interval_elapsed_q;
	reg [5:0]   world_interval_target_q;
	reg [7:0]   recovery_remaining_q;
	reg         snapshot_done_seen_q;
	reg         init_done_seen_q;
	reg         load_done_seen_q;
	reg         head_end_q;
	reg         head_dummy_q;
	reg [1:0]   head_kind_q;
	reg [255:0] engine_descriptor_q;
	reg [1:0]   engine_kind_q;
	reg [4:0]   engine_strip_q;
	reg [4:0]   engine_world_q;
	reg         engine_first_visit_q;
	reg         classification_mismatch_q;
	reg         sbout_q;
	reg [15:0]  sbout_remaining_q;
	reg         overtime_q;

	wire abort_active_w = xprst_i || (state_q == STATE_RECOVERY);
	wire service_state_w = (state_q == STATE_STRIP_LAUNCH) ||
		(state_q == STATE_STRIP_PREP) ||
		(state_q == STATE_LOAD_START) ||
		(state_q == STATE_LOAD_WAIT) ||
		(state_q == STATE_STRIP_PAD);
	wire world_state_w = (state_q == STATE_HEAD_ISSUE) ||
		(state_q == STATE_HEAD_WAIT) ||
		(state_q == STATE_WORLD_DELAY) ||
		(state_q == STATE_FETCH_START) ||
		(state_q == STATE_FETCH_WAIT) ||
		(state_q == STATE_ENGINE_START) ||
		(state_q == STATE_ENGINE_WAIT);
	wire snapshot_ready_for_world_w = snapshot_valid_i &&
		!snapshot_cleanup_busy_i &&
		(snapshot_done_seen_q || snapshot_done_i || !snapshot_busy_i);
	wire init_complete_w = init_done_seen_q || strip_init_done_i;
	wire load_complete_w = load_done_seen_q || strip_load_done_i;
	wire load_commit_w = (state_q == STATE_LOAD_WAIT) &&
		load_complete_w && (strip_service_remaining_q <= 16'd1);
	wire pad_commit_w = (state_q == STATE_STRIP_PAD) &&
		(strip_service_remaining_q <= 16'd1);
	wire [5:0] elapsed_next_w = (world_interval_elapsed_q == 6'd63) ?
		6'd63 : (world_interval_elapsed_q + 6'd1);
	wire [5:0] dummy_target_w = (strip_q == 5'd0) ?
		DUMMY_FIRST_INTERVAL_CYCLES[5:0] : DUMMY_INTERVAL_CYCLES[5:0];
	wire [1:0] selected_bkcol_w = (strip_q == 5'd0) ?
		bkcol_active_draw_q : bkcol_register_draw_q;
	wire recovery_status_active_w = recovery_remaining_q != 8'd0;

	assign draw_start_fire_o = ce_i && !reset_i && !xprst_i &&
		game_start_fire_i && xp_enable_i && !drawing_q &&
		(state_q == STATE_IDLE) && snapshot_start_ready_i &&
		!snapshot_cleanup_busy_i && !engine_cleanup_busy_i;
	assign snapshot_start_o = draw_start_fire_o;
	assign snapshot_abort_o = !reset_i && abort_active_w;
	assign snapshot_head_read_o = !reset_i && !abort_active_w &&
		drawing_q && (state_q == STATE_HEAD_ISSUE);
	assign snapshot_head_addr_o = {world_q, 4'd0};

	assign descriptor_fetch_start_o = !reset_i && !abort_active_w &&
		drawing_q && (state_q == STATE_FETCH_START);
	assign descriptor_fetch_world_o = world_q;
	assign descriptor_fetch_abort_o = !reset_i && abort_active_w;

	assign strip_init_start_o = !reset_i && !abort_active_w &&
		drawing_q && (state_q == STATE_STRIP_LAUNCH);
	assign strip_init_bkcol_word_o = {8{selected_bkcol_w}};
	assign strip_load_start_o = !reset_i && !abort_active_w &&
		drawing_q && (state_q == STATE_LOAD_START);
	assign strip_load_strip_o = strip_q;
	assign strip_load_draw_fb_o = draw_fb_q;
	assign strip_abort_o = !reset_i && abort_active_w;

	assign engine_cmd_valid_o = !reset_i && !abort_active_w &&
		!engine_cleanup_busy_i &&
		drawing_q && (state_q == STATE_ENGINE_START);
	assign engine_cmd_kind_o = engine_kind_q;
	assign engine_cmd_strip_o = engine_strip_q;
	assign engine_cmd_world_o = engine_world_q;
	assign engine_cmd_descriptor_o = engine_descriptor_q;
	assign engine_cmd_first_visit_o = engine_first_visit_q;
	assign engine_abort_o = !reset_i && abort_active_w;

	assign strip_start_fire_o = ce_i && strip_init_start_o &&
		strip_init_start_ready_i;
	assign strip_commit_fire_o = ce_i && !reset_i && !xprst_i &&
		drawing_q && (load_commit_w || pad_commit_w);
	assign first_group_done_fire_o = strip_commit_fire_o &&
		(strip_q == 5'd0);
	assign xp_end_fire_o = strip_commit_fire_o && (strip_q == 5'd27);
	assign owner_draw_complete_fire_o = xp_end_fire_o;
	assign sb_hit_fire_o = strip_start_fire_o && !sbout_q &&
		(strip_q == xp_sbcmp_i);
	assign timeerr_fire_o = ce_i && !reset_i && !xprst_i &&
		game_start_fire_i && drawing_q && !overtime_q;
	assign completion_gclk_tie_o = xp_end_fire_o && game_start_fire_i;

	assign drawing_o = drawing_q;
	assign xp_busy_o = (drawing_q || recovery_status_active_w) ?
		(draw_fb_q ? 2'b10 : 2'b01) : 2'b00;
	// Same value, two consumers: xp_sbcount_o feeds the host SBCOUNT field;
	// xp_strip_o is observation-only for the benches.
	assign xp_strip_o = strip_q;
	assign xp_sbcount_o = strip_q;
	assign xp_sbout_o = sbout_q;
	assign xp_overtime_o = overtime_q;
	assign draw_fb_o = draw_fb_q;
	assign state_o = state_q;
	assign world_o = world_q;
	assign draw_setup_remaining_o = draw_setup_remaining_q;
	assign strip_service_remaining_o = strip_service_remaining_q;
	assign world_interval_elapsed_o = world_interval_elapsed_q;
	assign world_interval_target_o = world_interval_target_q;
	assign recovery_remaining_o = recovery_remaining_q;
	assign classification_mismatch_o = classification_mismatch_q;
	assign peripheral_busy_o = snapshot_busy_i || snapshot_cleanup_busy_i ||
		descriptor_fetch_busy_i || strip_init_active_i ||
		strip_load_active_i || engine_cleanup_busy_i;

	// Restart the strip/world walk state shared by reset, XPRST, and draw start.
	task clear_strip_walk_state_task;
		begin
			strip_q <= 5'd0;
			world_q <= 5'd31;
			strip_service_remaining_q <= 16'd0;
			world_interval_elapsed_q <= 6'd0;
			world_interval_target_q <= 6'd0;
			snapshot_done_seen_q <= 1'b0;
			init_done_seen_q <= 1'b0;
			load_done_seen_q <= 1'b0;
			head_end_q <= 1'b0;
			head_dummy_q <= 1'b0;
			head_kind_q <= 2'd0;
			classification_mismatch_q <= 1'b0;
			sbout_q <= 1'b0;
			sbout_remaining_q <= 16'd0;
			overtime_q <= 1'b0;
		end
	endtask

	// Step to the next lower world, or begin loadout after world zero.
	task advance_world_task;
		begin
			if (world_q == 5'd0) begin
				state_q <= STATE_LOAD_START;
				load_done_seen_q <= 1'b0;
			end else begin
				world_q <= world_q - 5'd1;
				state_q <= STATE_HEAD_ISSUE;
				world_interval_elapsed_q <= 6'd0;
				world_interval_target_q <= 6'd0;
			end
		end
	endtask

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			drawing_q <= 1'b0;
			draw_fb_q <= 1'b0;
			bkcol_active_draw_q <= 2'd0;
			bkcol_register_draw_q <= 2'd0;
			draw_setup_remaining_q <= 16'd0;
			recovery_remaining_q <= 8'd0;
			engine_descriptor_q <= 256'd0;
			engine_kind_q <= 2'd0;
			engine_strip_q <= 5'd0;
			engine_world_q <= 5'd0;
			engine_first_visit_q <= 1'b0;
			clear_strip_walk_state_task;
		end else if (xprst_i) begin
			state_q <= STATE_RECOVERY;
			drawing_q <= 1'b0;
			// During recovery, show the next draw target as the busy framebuffer.
			draw_fb_q <= owner_draw_target_for_start_i;
			draw_setup_remaining_q <= 16'd0;
			recovery_remaining_q <= XPRST_RECOVERY_CYCLES[7:0];
			engine_descriptor_q <= 256'd0;
			engine_kind_q <= 2'd0;
			engine_strip_q <= 5'd0;
			engine_world_q <= 5'd0;
			engine_first_visit_q <= 1'b0;
			clear_strip_walk_state_task;
		end else if (ce_i) begin
			if (state_q == STATE_RECOVERY) begin
				if (recovery_remaining_q > 8'd1) begin
					recovery_remaining_q <= recovery_remaining_q - 8'd1;
				end else if (!peripheral_busy_o) begin
					recovery_remaining_q <= 8'd0;
					state_q <= STATE_IDLE;
				end else begin
					recovery_remaining_q <= 8'd0;
				end
			end

			if (strip_start_fire_o && !sbout_q) begin
				sbout_q <= 1'b1;
				sbout_remaining_q <= SBOUT_CYCLES[15:0];
			end else if (sbout_remaining_q != 16'd0) begin
				sbout_remaining_q <= sbout_remaining_q - 16'd1;
				if (sbout_remaining_q == 16'd1) begin
					sbout_q <= 1'b0;
				end
			end

			if (snapshot_done_i && drawing_q) begin
				snapshot_done_seen_q <= 1'b1;
			end
			if (strip_init_done_i && drawing_q) begin
				init_done_seen_q <= 1'b1;
			end
			if (strip_load_done_i && drawing_q) begin
				load_done_seen_q <= 1'b1;
			end

			if (draw_start_fire_o) begin
				state_q <= STATE_DRAW_SETUP;
				drawing_q <= 1'b1;
				draw_fb_q <= owner_draw_target_for_start_i;
				bkcol_active_draw_q <= bkcol_active_i;
				bkcol_register_draw_q <= bkcol_register_i;
				draw_setup_remaining_q <= DRAW_SETUP_CYCLES[15:0];
				recovery_remaining_q <= 8'd0;
				clear_strip_walk_state_task;
			end else if (drawing_q) begin
				if (timeerr_fire_o) begin
					overtime_q <= 1'b1;
				end

				if (strip_commit_fire_o) begin
					world_interval_elapsed_q <= 6'd0;
					world_interval_target_q <= 6'd0;
					init_done_seen_q <= 1'b0;
					load_done_seen_q <= 1'b0;
					if (strip_q == 5'd27) begin
						state_q <= STATE_IDLE;
						drawing_q <= 1'b0;
						strip_service_remaining_q <= 16'd0;
						overtime_q <= 1'b0;
					end else begin
						state_q <= STATE_STRIP_LAUNCH;
						strip_q <= strip_q + 5'd1;
						world_q <= 5'd31;
						strip_service_remaining_q <=
							LATER_STRIP_SERVICE_CYCLES[15:0];
					end
				end else begin
					if (service_state_w &&
						(strip_service_remaining_q != 16'd0)) begin
						strip_service_remaining_q <=
							strip_service_remaining_q - 16'd1;
					end

					if (world_state_w) begin
						world_interval_elapsed_q <= elapsed_next_w;
					end

					case (state_q)
						STATE_DRAW_SETUP: begin
							if (draw_setup_remaining_q <= 16'd1) begin
								draw_setup_remaining_q <= 16'd0;
								strip_service_remaining_q <=
									FIRST_STRIP_SERVICE_CYCLES[15:0];
								state_q <= STATE_STRIP_LAUNCH;
							end else begin
								draw_setup_remaining_q <=
									draw_setup_remaining_q - 16'd1;
							end
						end

						STATE_STRIP_LAUNCH: begin
							if (strip_start_fire_o) begin
								state_q <= STATE_STRIP_PREP;
							end
						end

						STATE_STRIP_PREP: begin
							if (init_complete_w &&
								((strip_q != 5'd0) ||
								snapshot_ready_for_world_w)) begin
								state_q <= STATE_HEAD_ISSUE;
								world_interval_elapsed_q <= 6'd0;
								world_interval_target_q <= 6'd0;
							end
						end

						STATE_HEAD_ISSUE: begin
							state_q <= STATE_HEAD_WAIT;
							world_interval_elapsed_q <= 6'd1;
						end

						STATE_HEAD_WAIT: begin
							if (snapshot_head_rvalid_i) begin
								head_end_q <= snapshot_head_rdata_i[6];
								head_dummy_q <=
									(snapshot_head_rdata_i[15:14] == 2'b00);
								head_kind_q <= snapshot_head_rdata_i[13:12];
								if (snapshot_head_rdata_i[6]) begin
									world_interval_target_q <=
										END_INTERVAL_CYCLES[5:0];
									if (elapsed_next_w >=
										END_INTERVAL_CYCLES[5:0]) begin
										state_q <= STATE_LOAD_START;
										load_done_seen_q <= 1'b0;
									end else begin
										state_q <= STATE_WORLD_DELAY;
									end
								end else if (snapshot_head_rdata_i[15:14] ==
									2'b00) begin
									world_interval_target_q <= dummy_target_w;
									if (elapsed_next_w >= dummy_target_w) begin
										advance_world_task;
									end else begin
										state_q <= STATE_WORLD_DELAY;
									end
								end else begin
									state_q <= STATE_FETCH_START;
									world_interval_target_q <= 6'd0;
								end
							end
						end

						STATE_WORLD_DELAY: begin
							if (elapsed_next_w >= world_interval_target_q) begin
								// An END world skips straight to loadout.
								if (head_end_q) begin
									state_q <= STATE_LOAD_START;
									load_done_seen_q <= 1'b0;
								end else begin
									advance_world_task;
								end
							end
						end

						STATE_FETCH_START: begin
							if (descriptor_fetch_start_ready_i) begin
								state_q <= STATE_FETCH_WAIT;
							end
						end

						STATE_FETCH_WAIT: begin
							if (descriptor_fetch_done_i) begin
								engine_descriptor_q <=
									descriptor_fetch_descriptor_i;
								engine_kind_q <= descriptor_fetch_kind_i;
								engine_strip_q <= strip_q;
								engine_world_q <= world_q;
								engine_first_visit_q <= (strip_q == 5'd0);
								if ((descriptor_fetch_end_i != head_end_q) ||
									(descriptor_fetch_dummy_i != head_dummy_q) ||
									(descriptor_fetch_kind_i != head_kind_q)) begin
									classification_mismatch_q <= 1'b1;
								end
								state_q <= STATE_ENGINE_START;
							end
						end

						STATE_ENGINE_START: begin
							if (engine_cmd_ready_i &&
								!engine_cleanup_busy_i) begin
								state_q <= STATE_ENGINE_WAIT;
							end
						end

						STATE_ENGINE_WAIT: begin
							if (engine_done_i) begin
								advance_world_task;
							end
						end

						STATE_LOAD_START: begin
							if (strip_load_start_ready_i) begin
								state_q <= STATE_LOAD_WAIT;
							end
						end

						STATE_LOAD_WAIT: begin
							if (load_complete_w &&
								(strip_service_remaining_q > 16'd1)) begin
								// Wait out the measured service budget after loadout.
								state_q <= STATE_STRIP_PAD;
							end
						end

						// Sit out the service budget; pad_commit_w exits above.
						STATE_STRIP_PAD: begin
						end

						default: begin
							state_q <= STATE_IDLE;
							drawing_q <= 1'b0;
						end
					endcase
				end
			end
		end
	end

endmodule

/* verilator lint_on DECLFILENAME */
