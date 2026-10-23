// Copyright (c) 2026 Jamie Blanks

`timescale 1ns/1ps

// Top-level VIP connection between the host, display, memory, and renderers.
//
// "Silicon unknown" marks behavior that available sources do not settle.

/* verilator lint_off DECLFILENAME */
module VIP
#(
	parameter integer H_VISIBLE             = 384,
	parameter integer H_TOTAL               = 512,
	parameter integer H_SYNC_BEG            = 416,
	parameter integer H_SYNC_END            = 480,
	parameter integer V_VISIBLE             = 224,
	parameter integer V_TOTAL               = 262,
	parameter integer V_SYNC_BEG            = 240,
	parameter integer V_SYNC_END            = 244,
	parameter         FLAT_OUTPUT            = 1'b0
)
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire        phi1_i,
	input  wire        video_ce_i,
	input  wire        video_phi1_i,
	input  wire        savestate_pause_req_i,
	input  wire        savestate_boundary_stop_i,
	output wire        savestate_pause_drain_ready_o,
	output wire        savestate_pause_scan_boundary_o,
	output wire        savestate_pause_ready_o,
	input  wire        savestate_restore_i,
	input  wire [5:0]  savestate_state_addr_i,
	input  wire [63:0] savestate_state_wdata_i,
	input  wire        savestate_state_wren_i,
	output reg  [63:0] savestate_state_rdata_o,
	input  wire        savestate_mem_active_i,
	input  wire        savestate_mem_dram_i,
	input  wire [16:0] savestate_mem_addr_i,
	input  wire        savestate_mem_rden_i,
	input  wire        savestate_mem_wren_i,
	input  wire [7:0]  savestate_mem_wdata_i,
	output wire [7:0]  savestate_mem_rdata_o,

	input  wire        cs_i,
	input  wire [23:1] a_i,
	input  wire [15:0] din_i,
	input  wire [3:0]  be_i,
	input  wire [1:0]  st_i,
	input  wire        da_i,
	input  wire        mrq_i,
	input  wire        rw_i,
	input  wire        bcyst_i,
	output wire [15:0] dout_o,
	output wire        ready_o,

	output wire        irq_o,

	input  wire        flat_dual_eye_i,
	input  wire        side_by_side_i,
	input  wire        compat_60hz_i,
	input  wire        shutter_i,
	input  wire [2:0]  parallax_scale_i,
	input  wire        presentation_hlg_i,
	input  wire        brightness_table_legacy_sdr_i,
	input  wire        brightness_table_download_i,
	input  wire        brightness_table_write_i,
	input  wire [9:0]  brightness_table_addr_i,
	input  wire [15:0] brightness_table_data_i,

	output wire [1:0]  video_raw_l_o,
	output wire [1:0]  video_raw_r_o,
	output wire [7:0]  video_luma_l_o,
	output wire [7:0]  video_luma_r_o,
	output wire        video_hblank_o,
	output wire        video_vblank_o,
	output wire        video_hsync_o,
	output wire        video_vsync_o
);
	localparam [15:0] VIDEO_H_VISIBLE  = H_VISIBLE[15:0];
	localparam [15:0] VIDEO_H_TOTAL    = H_TOTAL[15:0];
	localparam [15:0] VIDEO_H_SYNC_BEG = H_SYNC_BEG[15:0];
	localparam [15:0] VIDEO_H_SYNC_END = H_SYNC_END[15:0];
	localparam [15:0] VIDEO_V_VISIBLE  = V_VISIBLE[15:0];
	localparam [15:0] VIDEO_V_TOTAL    = V_TOTAL[15:0];
	localparam [15:0] VIDEO_V_SYNC_BEG = V_SYNC_BEG[15:0];
	localparam [15:0] VIDEO_V_SYNC_END = V_SYNC_END[15:0];
	wire vip_reset_w = reset_i || savestate_restore_i;
	// Draw-coordinator command handshake.
	wire         engine_cmd_valid_w;
	wire         engine_cmd_ready_w;
	wire [1:0]   engine_cmd_kind_w;
	wire [4:0]   engine_cmd_strip_w;
	wire [4:0]   engine_cmd_world_w;
	wire [255:0] engine_cmd_descriptor_w;
	wire         engine_cmd_first_visit_w;
	wire         engine_done_w;
	wire         engine_abort_w;
	wire         engine_cleanup_busy_w;
	wire         render_global_quiescent_w;

	// Selected renderer memory channels.
	wire        aggregate_dram_abort_w;
	wire        aggregate_dram_req_w;
	wire [15:0] aggregate_dram_addr_w;
	wire        aggregate_vrm_abort_w;
	wire        aggregate_vrm_req_w;
	wire [15:0] aggregate_vrm_addr_w;
	wire        aggregate_dram_accept_w;
	wire        aggregate_dram_resp_valid_w;
	wire [15:0] aggregate_dram_resp_data_w;
	wire        aggregate_dram_cleanup_busy_w;
	wire        aggregate_dram_stale_discarded_w;
	wire        aggregate_vrm_accept_w;
	wire        aggregate_vrm_resp_valid_w;
	wire [15:0] aggregate_vrm_resp_data_w;
	wire        aggregate_vrm_cleanup_busy_w;
	wire        aggregate_vrm_stale_discarded_w;

	// Normal, H-bias, and Object row token.
	wire               row_producer_valid_w;
	wire               row_producer_ready_w;
	wire [2:0]         row_producer_row_w;
	wire signed [15:0] row_producer_left_base_x_w;
	wire               row_producer_left_enable_w;
	wire [7:0]         row_producer_left_active_w;
	wire [7:0]         row_producer_left_opaque_w;
	wire [15:0]        row_producer_left_values_w;
	wire signed [15:0] row_producer_right_base_x_w;
	wire               row_producer_right_enable_w;
	wire [7:0]         row_producer_right_active_w;
	wire [7:0]         row_producer_right_opaque_w;
	wire [15:0]        row_producer_right_values_w;
	wire               row_producer_done_w;

	// Affine row prepare and commit.
	wire               affine_abort_w;
	wire               affine_prepare_valid_w;
	wire               affine_prepare_ready_w;
	wire [2:0]         affine_prepare_row_w;
	wire signed [15:0] affine_prepare_left_base_x_w;
	wire               affine_prepare_left_enable_w;
	wire signed [15:0] affine_prepare_right_base_x_w;
	wire               affine_prepare_right_enable_w;
	wire               affine_commit_valid_w;
	wire               affine_commit_ready_w;
	wire [3:0]         affine_commit_left_active_w;
	wire [3:0]         affine_commit_left_opaque_w;
	wire [7:0]         affine_commit_left_values_w;
	wire [3:0]         affine_commit_right_active_w;
	wire [3:0]         affine_commit_right_opaque_w;
	wire [7:0]         affine_commit_right_values_w;
	wire               affine_store_quiescent_w;

	// Draw-time register values.
	wire [39:0] spt_active_w;
	wire [39:0] spt_register_w;
	wire [31:0] gplt_active_w;
	wire [31:0] gplt_register_w;
	wire [31:0] jplt_active_w;
	wire [31:0] jplt_register_w;
	wire [15:0] vip_int_pending_w;
	wire [15:0] vip_int_enable_w;
	wire        vip_dp_lock_w;
	wire        vip_dp_synce_program_w;
	wire        vip_dp_synce_active_w;
	wire        vip_dp_refresh_w;
	wire        vip_dp_display_program_w;
	wire        vip_dp_display_active_w;
	wire [4:0]  vip_xp_sbcmp_w;
	wire        vip_xp_enable_w;
	wire [1:0]  vip_bkcol_register_w;
	wire [1:0]  vip_bkcol_active_w;
	wire [31:0] vip_brightness_register_w;
	wire [31:0] vip_brightness_active_w;
	wire [3:0]  vip_frmcyc_register_w;
	wire [3:0]  vip_frmcyc_active_w;
	wire [15:0] vip_cta_w;
	wire        vip_bkcol_pending_w;
	wire        vip_bkcol_wait_first_group_w;
	wire [6:0]  vip_event_history_w;
	wire [18:0] vip_native_frame_cycle_w;
	wire        vip_native_fclk_w;
	wire        vip_native_waiting_for_fclk_w;
	wire [3:0]  vip_native_game_frame_wait_w;
	wire [3:0]  vip_native_frmcyc_active_w;

	// Hold each CTA group until the display sequencer accepts it.
	wire native_dprst_w;
	wire native_left_start_fire_w;
	wire native_right_start_fire_w;
	wire cta_field_active_w;
	wire cta_transaction_active_w;
	wire cta_group_valid_w;
	wire cta_group_ready_w;
	wire cta_ctc_valid_w;
	wire [15:0] cta_ctc_data_w;
	wire cta_ctc_eye_w;
	wire [6:0] cta_ctc_ordinal_w;
	wire cta_source_terminal_fire_w;
	wire cta_source_terminal_eye_w;
	wire cta_source_incomplete_w;
	wire cta_source_incomplete_eye_w;
	wire cta_source_timed_eye_end_w = cta_source_terminal_fire_w ||
		cta_source_incomplete_w;
	wire cta_source_timed_eye_end_eye_w = cta_source_terminal_fire_w ?
		cta_source_terminal_eye_w : cta_source_incomplete_eye_w;

	// Check observer collisions against the current framebuffer owner.
	wire displayed_fb_latched_w;
	wire vrm_observer_enable_w;
	wire active_draw_valid_w;
	wire active_draw_target_w;
	wire displayed_fb_w;
	wire completed_pending_valid_w;
	wire completed_pending_target_w;
	wire native_left_busy_w;
	wire native_right_busy_w;
	wire host_busy_w;
	wire vram_store_busy_w;
	wire vram_offer_held_w;
	wire vram_read_pending_w;
	wire dram_store_busy_w;
	wire dram_offer_held_w;
	wire dram_read_pending_w;
	wire peripheral_busy_w;
	wire abort_cleanup_owner_active_w;
	wire snapshot_cta_idle_w;
	wire snapshot_brightness_worker_idle_w;
	wire snapshot_brightness_allocator_idle_w;
	wire snapshot_brightness_raster_empty_w;
	wire snapshot_framebuffer_capture_idle_w;
	wire snapshot_scan_converter_empty_w;
	wire snapshot_event_coherent_w;
	wire [3:0] coordinator_state_w;
	wire drawing_w;
	wire [7:0] savestate_vram_mem_rdata_w;
	wire [7:0] savestate_dram_mem_rdata_w;
	/* verilator lint_off UNUSEDSIGNAL */
	wire [36:0] savestate_scan_state_w;
	/* verilator lint_on UNUSEDSIGNAL */
	// The scan converter owns all presentation timing and reports whether its
	// live, frame-latched mode is at a legal canonical stop point.
	wire savestate_scan_boundary_w = savestate_scan_state_w[36];
	wire framebuffer_collision_w = vrm_observer_enable_w &&
		active_draw_valid_w &&
		(active_draw_target_w == displayed_fb_latched_w);

	// FLAT_OUTPUT shows the left eye unless dual-eye output is selected.
	wire [1:0] presentation_mode_w =
		(FLAT_OUTPUT && !flat_dual_eye_i) ? 2'b01 : 2'b00;

	// Stop new work before the parent pauses CE and phi1 for a snapshot.
	wire savestate_pause_owner_safe_w =
		render_global_quiescent_w &&
		(coordinator_state_w == 4'd0) &&
		!drawing_w && !active_draw_valid_w &&
		!native_left_busy_w && !native_right_busy_w &&
		!host_busy_w &&
		!vram_store_busy_w && !vram_offer_held_w &&
		!vram_read_pending_w &&
		!dram_store_busy_w && !dram_offer_held_w &&
		!dram_read_pending_w &&
		!peripheral_busy_w && !abort_cleanup_owner_active_w &&
		snapshot_cta_idle_w &&
		snapshot_brightness_worker_idle_w &&
		snapshot_brightness_allocator_idle_w &&
		snapshot_brightness_raster_empty_w &&
		snapshot_framebuffer_capture_idle_w &&
		snapshot_event_coherent_w;
	wire savestate_pause_safe_w = savestate_pause_owner_safe_w &&
		snapshot_scan_converter_empty_w;

	assign savestate_pause_drain_ready_o = savestate_pause_req_i &&
		savestate_pause_owner_safe_w;
	assign savestate_pause_scan_boundary_o = savestate_pause_req_i &&
		savestate_scan_boundary_w;
	assign savestate_pause_ready_o = savestate_pause_req_i &&
		savestate_pause_safe_w;
	assign savestate_mem_rdata_o = savestate_mem_dram_i ?
		savestate_dram_mem_rdata_w : savestate_vram_mem_rdata_w;

	always @* begin
		case (savestate_state_addr_i)
			6'd0: savestate_state_rdata_o = {45'd0, vip_native_frame_cycle_w};
			6'd1: savestate_state_rdata_o = {63'd0, vip_native_fclk_w};
			6'd2: savestate_state_rdata_o =
				{63'd0, vip_native_waiting_for_fclk_w};
			6'd3: savestate_state_rdata_o =
				{60'd0, vip_native_game_frame_wait_w};
			6'd4: savestate_state_rdata_o =
				{60'd0, vip_native_frmcyc_active_w};
			6'd5: savestate_state_rdata_o = {57'd0, vip_event_history_w};
			6'd6: savestate_state_rdata_o = {48'd0, vip_int_pending_w};
			6'd7: savestate_state_rdata_o = {48'd0, vip_int_enable_w};
			6'd8: savestate_state_rdata_o =
				{53'd0, vip_dp_lock_w, vip_dp_synce_program_w,
				 vip_dp_refresh_w, 6'd0, vip_dp_display_program_w, 1'b0};
			6'd9: savestate_state_rdata_o =
				{53'd0, vip_dp_lock_w, vip_dp_synce_active_w,
				 vip_dp_refresh_w, 6'd0, vip_dp_display_active_w, 1'b0};
			6'd10: savestate_state_rdata_o =
				{56'd0, vip_brightness_register_w[7:0]};
			6'd11: savestate_state_rdata_o =
				{56'd0, vip_brightness_active_w[7:0]};
			6'd12: savestate_state_rdata_o =
				{56'd0, vip_brightness_register_w[15:8]};
			6'd13: savestate_state_rdata_o =
				{56'd0, vip_brightness_active_w[15:8]};
			6'd14: savestate_state_rdata_o =
				{56'd0, vip_brightness_register_w[23:16]};
			6'd15: savestate_state_rdata_o =
				{56'd0, vip_brightness_active_w[23:16]};
			6'd16: savestate_state_rdata_o =
				{56'd0, vip_brightness_register_w[31:24]};
			6'd17: savestate_state_rdata_o =
				{56'd0, vip_brightness_active_w[31:24]};
			6'd18: savestate_state_rdata_o = {60'd0, vip_frmcyc_register_w};
			6'd19: savestate_state_rdata_o = {60'd0, vip_frmcyc_active_w};
			6'd20: savestate_state_rdata_o = {48'd0, vip_cta_w};
			6'd21: savestate_state_rdata_o =
				{51'd0, vip_xp_sbcmp_w, 6'd0, vip_xp_enable_w, 1'b0};
			6'd22: savestate_state_rdata_o = {54'd0, spt_register_w[9:0]};
			6'd23: savestate_state_rdata_o = {54'd0, spt_active_w[9:0]};
			6'd24: savestate_state_rdata_o = {54'd0, spt_register_w[19:10]};
			6'd25: savestate_state_rdata_o = {54'd0, spt_active_w[19:10]};
			6'd26: savestate_state_rdata_o = {54'd0, spt_register_w[29:20]};
			6'd27: savestate_state_rdata_o = {54'd0, spt_active_w[29:20]};
			6'd28: savestate_state_rdata_o = {54'd0, spt_register_w[39:30]};
			6'd29: savestate_state_rdata_o = {54'd0, spt_active_w[39:30]};
			6'd30: savestate_state_rdata_o = {56'd0, gplt_register_w[7:0]};
			6'd31: savestate_state_rdata_o = {56'd0, gplt_active_w[7:0]};
			6'd32: savestate_state_rdata_o = {56'd0, gplt_register_w[15:8]};
			6'd33: savestate_state_rdata_o = {56'd0, gplt_active_w[15:8]};
			6'd34: savestate_state_rdata_o = {56'd0, gplt_register_w[23:16]};
			6'd35: savestate_state_rdata_o = {56'd0, gplt_active_w[23:16]};
			6'd36: savestate_state_rdata_o = {56'd0, gplt_register_w[31:24]};
			6'd37: savestate_state_rdata_o = {56'd0, gplt_active_w[31:24]};
			6'd38: savestate_state_rdata_o = {56'd0, jplt_register_w[7:0]};
			6'd39: savestate_state_rdata_o = {56'd0, jplt_active_w[7:0]};
			6'd40: savestate_state_rdata_o = {56'd0, jplt_register_w[15:8]};
			6'd41: savestate_state_rdata_o = {56'd0, jplt_active_w[15:8]};
			6'd42: savestate_state_rdata_o = {56'd0, jplt_register_w[23:16]};
			6'd43: savestate_state_rdata_o = {56'd0, jplt_active_w[23:16]};
			6'd44: savestate_state_rdata_o = {56'd0, jplt_register_w[31:24]};
			6'd45: savestate_state_rdata_o = {56'd0, jplt_active_w[31:24]};
			6'd46: savestate_state_rdata_o = {62'd0, vip_bkcol_register_w};
			6'd47: savestate_state_rdata_o = {62'd0, vip_bkcol_active_w};
			6'd48: savestate_state_rdata_o =
				{20'd0, savestate_scan_state_w[34:33], 1'b0, 30'd0,
				 completed_pending_valid_w, completed_pending_target_w,
				 displayed_fb_w, 6'd0,
				 vip_bkcol_wait_first_group_w, vip_bkcol_pending_w};
			default: savestate_state_rdata_o = 64'd0;
		endcase
	end

	/* verilator lint_off PINMISSING */
	// MiSTer serializes the eye fields at the established 0x56 group cadence.
	// CTC length and repeat still control LED exposure.
	vip_native_cta_group_source
	#(
		.FIXED_GROUP_PERIOD_CE(13'd1392)
	)
	u_cta_group_source
	(
		.clk_i(clk_i),
		.reset_i(vip_reset_w),
		.ce_i(ce_i),
		.abort_i(native_dprst_w),
		.consumer_busy_i(cta_field_active_w || cta_transaction_active_w),
		.left_field_start_i(native_left_start_fire_w),
		.left_field_end_i(1'b0),
		.right_field_start_i(native_right_start_fire_w),
		.right_field_end_i(1'b0),
		.group_ready_i(cta_group_ready_w),
		.ctc_valid_i(cta_ctc_valid_w),
		.ctc_data_i(cta_ctc_data_w),
		.ctc_eye_i(cta_ctc_eye_w),
		.ctc_ordinal_i(cta_ctc_ordinal_w),
		.group_valid_o(cta_group_valid_w),
		.field_complete_o(),
		.field_complete_eye_o(),
		.field_incomplete_o(cta_source_incomplete_w),
		.field_incomplete_eye_o(cta_source_incomplete_eye_w),
		.field_underrun_o(),
		.field_terminal_fire_o(cta_source_terminal_fire_w),
		.field_terminal_eye_o(cta_source_terminal_eye_w)
	);

	vip_host_display_subsystem
	#(
		.NORMAL_MEMORY_CLIENT_ENABLE(1),
		.AFFINE_STREAM_ENABLE(1),
		.H_VISIBLE(VIDEO_H_VISIBLE),
		.H_TOTAL(VIDEO_H_TOTAL),
		.H_SYNC_BEG(VIDEO_H_SYNC_BEG),
		.H_SYNC_END(VIDEO_H_SYNC_END),
		.V_VISIBLE(VIDEO_V_VISIBLE),
		.V_TOTAL(VIDEO_V_TOTAL),
		.V_SYNC_BEG(VIDEO_V_SYNC_BEG),
		.V_SYNC_END(VIDEO_V_SYNC_END),
		.CTA_TIMED_EYE_END_ENABLE(1'b1),
		.NATIVE_FRAMEBUFFER_CAPTURE_ENABLE(1'b1)
	)
	u_host_display
	(
		.clk_i(clk_i),
		.reset_i(vip_reset_w),
		.ce_i(ce_i),
		.phi1_i(phi1_i),
		.savestate_state_addr_i(savestate_state_addr_i),
		.savestate_state_wdata_i(savestate_state_wdata_i),
		.savestate_state_wren_i(savestate_state_wren_i),
		.savestate_vram_mem_active_i(savestate_mem_active_i &&
			!savestate_mem_dram_i),
		.savestate_dram_mem_active_i(savestate_mem_active_i &&
			savestate_mem_dram_i),
		.savestate_mem_addr_i(savestate_mem_addr_i),
		.savestate_mem_rden_i(savestate_mem_rden_i),
		.savestate_mem_wren_i(savestate_mem_wren_i),
		.savestate_mem_wdata_i(savestate_mem_wdata_i),
		.savestate_vram_mem_rdata_o(savestate_vram_mem_rdata_w),
		.savestate_dram_mem_rdata_o(savestate_dram_mem_rdata_w),
		.savestate_scan_state_o(savestate_scan_state_w),
		.video_ce_i(video_ce_i),
		.video_phi1_i(video_phi1_i),
		.savestate_boundary_stop_i(savestate_boundary_stop_i),
		.cs_i(cs_i),
		.a_i(a_i),
		.din_i(din_i),
		.be_i(be_i),
		.st_i(st_i),
		.da_i(da_i),
		.mrq_i(mrq_i),
		.rw_i(rw_i),
		.bcyst_i(bcyst_i),
		.dout_o(dout_o),
		.ready_o(ready_o),
		.irq_o(irq_o),
		.vram_dp_req_i(1'b0),
		.vram_dp_write_i(1'b0),
		.vram_dp_addr_i(16'd0),
		.vram_dp_wdata_i(16'd0),
		.vram_dp_byte_enable_i(2'b00),
		.dram_observer_enable_i(1'b0),
		.dram_observer_addr_i(16'd0),
		.normal_memory_abort_i(
			aggregate_dram_abort_w || aggregate_vrm_abort_w),
		.normal_vrm_req_i(aggregate_vrm_req_w),
		.normal_vrm_addr_i(aggregate_vrm_addr_w),
		.normal_dram_req_i(aggregate_dram_req_w),
		.normal_dram_addr_i(aggregate_dram_addr_w),
		.normal_vrm_accept_o(aggregate_vrm_accept_w),
		.normal_vrm_resp_valid_o(aggregate_vrm_resp_valid_w),
		.normal_vrm_resp_data_o(aggregate_vrm_resp_data_w),
		.normal_vrm_cleanup_busy_o(aggregate_vrm_cleanup_busy_w),
		.normal_vrm_stale_discarded_o(
			aggregate_vrm_stale_discarded_w),
		.normal_dram_accept_o(aggregate_dram_accept_w),
		.normal_dram_resp_valid_o(aggregate_dram_resp_valid_w),
		.normal_dram_resp_data_o(aggregate_dram_resp_data_w),
		.normal_dram_cleanup_busy_o(aggregate_dram_cleanup_busy_w),
		.normal_dram_stale_discarded_o(
			aggregate_dram_stale_discarded_w),
		// MiSTer has no SCANRDY input, so keep the scanner ready.
		.dp_scan_ready_i(1'b1),
		// Silicon unknown: SCANERR timing is undocumented. MiSTer leaves it quiet.
		.scanerr_event_i(1'b0),
		// MiSTer has no mirror servo. Use the measured 0xfa field-start CTA value.
		.cta_left_servo_i(8'hfa),
		.cta_right_servo_i(8'hfa),
		.column_group_valid_i(cta_group_valid_w),
		.column_group_ready_o(cta_group_ready_w),
		.cta_timed_eye_end_i(cta_source_timed_eye_end_w),
		.cta_timed_eye_end_eye_i(cta_source_timed_eye_end_eye_w),
		.completed_framebuffer_collision_free_i(!framebuffer_collision_w),
		.presentation_mode_i(presentation_mode_w),
		.flat_eye_i(1'b0),
		.side_by_side_i(side_by_side_i),
		.compat_60hz_i(compat_60hz_i),
		.shutter_i(shutter_i),
		.presentation_hlg_i(presentation_hlg_i),
		.brightness_table_legacy_sdr_i(brightness_table_legacy_sdr_i),
		.brightness_table_download_i(brightness_table_download_i),
		.brightness_table_write_i(brightness_table_write_i),
		.brightness_table_addr_i(brightness_table_addr_i),
		.brightness_table_data_i(brightness_table_data_i),
		.brightness_cache_collision_free_i(1'b1),
		.engine_cmd_valid_o(engine_cmd_valid_w),
		.engine_cmd_ready_i(engine_cmd_ready_w),
		.engine_cmd_kind_o(engine_cmd_kind_w),
		.engine_cmd_strip_o(engine_cmd_strip_w),
		.engine_cmd_world_o(engine_cmd_world_w),
		.engine_cmd_descriptor_o(engine_cmd_descriptor_w),
		.engine_cmd_first_visit_o(engine_cmd_first_visit_w),
		.engine_done_i(engine_done_w),
		.engine_cleanup_busy_i(engine_cleanup_busy_w),
		.engine_abort_o(engine_abort_w),
		.producer_valid_i(1'b0),
		.producer_column_i(9'd0),
		.producer_left_enable_i(1'b0),
		.producer_left_preserve_mask_i(16'hffff),
		.producer_left_value_i(16'd0),
		.producer_right_enable_i(1'b0),
		.producer_right_preserve_mask_i(16'hffff),
		.producer_right_value_i(16'd0),
		.row_producer_valid_i(row_producer_valid_w),
		.row_producer_row_i(row_producer_row_w),
		.row_producer_left_base_x_i(row_producer_left_base_x_w),
		.row_producer_left_enable_i(row_producer_left_enable_w),
		.row_producer_left_active_i(row_producer_left_active_w),
		.row_producer_left_opaque_i(row_producer_left_opaque_w),
		.row_producer_left_values_i(row_producer_left_values_w),
		.row_producer_right_base_x_i(row_producer_right_base_x_w),
		.row_producer_right_enable_i(row_producer_right_enable_w),
		.row_producer_right_active_i(row_producer_right_active_w),
		.row_producer_right_opaque_i(row_producer_right_opaque_w),
		.row_producer_right_values_i(row_producer_right_values_w),
		.row_producer_ready_o(row_producer_ready_w),
		.row_producer_done_o(row_producer_done_w),
		.affine_abort_i(affine_abort_w),
		.affine_prepare_valid_i(affine_prepare_valid_w),
		.affine_prepare_ready_o(affine_prepare_ready_w),
		.affine_prepare_row_i(affine_prepare_row_w),
		.affine_prepare_left_base_x_i(affine_prepare_left_base_x_w),
		.affine_prepare_left_enable_i(affine_prepare_left_enable_w),
		.affine_prepare_right_base_x_i(affine_prepare_right_base_x_w),
		.affine_prepare_right_enable_i(affine_prepare_right_enable_w),
		.affine_commit_valid_i(affine_commit_valid_w),
		.affine_commit_ready_o(affine_commit_ready_w),
		.affine_commit_left_active_i(affine_commit_left_active_w),
		.affine_commit_left_opaque_i(affine_commit_left_opaque_w),
		.affine_commit_left_values_i(affine_commit_left_values_w),
		.affine_commit_right_active_i(affine_commit_right_active_w),
		.affine_commit_right_opaque_i(affine_commit_right_opaque_w),
		.affine_commit_right_values_i(affine_commit_right_values_w),
		.affine_quiescent_o(affine_store_quiescent_w),
		.int_pending_o(vip_int_pending_w),
		.int_enable_o(vip_int_enable_w),
		.dp_lock_o(vip_dp_lock_w),
		.dp_synce_program_o(vip_dp_synce_program_w),
		.dp_synce_active_o(vip_dp_synce_active_w),
		.dp_refresh_o(vip_dp_refresh_w),
		.dp_display_program_o(vip_dp_display_program_w),
		.dp_display_active_o(vip_dp_display_active_w),
		.xp_sbcmp_o(vip_xp_sbcmp_w),
		.xp_enable_o(vip_xp_enable_w),
		.bkcol_register_o(vip_bkcol_register_w),
		.bkcol_active_o(vip_bkcol_active_w),
		.brightness_register_o(vip_brightness_register_w),
		.brightness_active_o(vip_brightness_active_w),
		.frmcyc_register_o(vip_frmcyc_register_w),
		.frmcyc_register_active_o(vip_frmcyc_active_w),
		.cta_o(vip_cta_w),
		.spt_register_o(spt_register_w),
		.spt_active_o(spt_active_w),
		.gplt_register_o(gplt_register_w),
		.gplt_active_o(gplt_active_w),
		.jplt_register_o(jplt_register_w),
		.jplt_active_o(jplt_active_w),
		.bkcol_pending_o(vip_bkcol_pending_w),
		.bkcol_wait_first_group_o(vip_bkcol_wait_first_group_w),
		.event_history_o(vip_event_history_w),
		.native_frame_cycle_o(vip_native_frame_cycle_w),
		.native_fclk_o(vip_native_fclk_w),
		.native_waiting_for_fclk_o(vip_native_waiting_for_fclk_w),
		.native_frmcyc_active_o(vip_native_frmcyc_active_w),
		.native_game_frame_wait_o(vip_native_game_frame_wait_w),
		.native_left_busy_o(native_left_busy_w),
		.native_right_busy_o(native_right_busy_w),
		.dprst_o(native_dprst_w),
		.native_left_start_fire_o(native_left_start_fire_w),
		.native_left_end_fire_o(),
		.native_right_start_fire_o(native_right_start_fire_w),
		.native_right_end_fire_o(),
		.cta_field_active_o(cta_field_active_w),
		.cta_transaction_active_o(cta_transaction_active_w),
		.host_busy_o(host_busy_w),
		.vram_store_busy_o(vram_store_busy_w),
		.vram_inner_offer_held_o(vram_offer_held_w),
		.vram_read_pending_o(vram_read_pending_w),
		.dram_store_busy_o(dram_store_busy_w),
		.dram_inner_offer_held_o(dram_offer_held_w),
		.dram_read_pending_o(dram_read_pending_w),
		.abort_cleanup_owner_active_o(abort_cleanup_owner_active_w),
		.ctc_valid_o(cta_ctc_valid_w),
		.ctc_data_o(cta_ctc_data_w),
		.ctc_eye_o(cta_ctc_eye_w),
		.ctc_ordinal_o(cta_ctc_ordinal_w),
		.displayed_fb_latched_o(displayed_fb_latched_w),
		.vrm_observer_enable_o(vrm_observer_enable_w),
		.video_hblank_o(video_hblank_o),
		.video_vblank_o(video_vblank_o),
		.video_hsync_o(video_hsync_o),
		.video_vsync_o(video_vsync_o),
		.raw_pixel_left_o(video_raw_l_o),
		.raw_pixel_right_o(video_raw_r_o),
		.video_luma_left_o(video_luma_l_o),
		.video_luma_right_o(video_luma_r_o),
		.drawing_o(drawing_w),
		.displayed_fb_o(displayed_fb_w),
		.active_draw_valid_o(active_draw_valid_w),
		.active_draw_target_o(active_draw_target_w),
		.completed_pending_valid_o(completed_pending_valid_w),
		.completed_pending_target_o(completed_pending_target_w),
		.coordinator_state_o(coordinator_state_w),
		.peripheral_busy_o(peripheral_busy_w),
		.snapshot_cta_idle_o(snapshot_cta_idle_w),
		.snapshot_brightness_worker_idle_o(
			snapshot_brightness_worker_idle_w),
		.snapshot_brightness_allocator_idle_o(
			snapshot_brightness_allocator_idle_w),
		.snapshot_brightness_raster_pipe_empty_o(
			snapshot_brightness_raster_empty_w),
		.snapshot_framebuffer_capture_idle_o(
			snapshot_framebuffer_capture_idle_w),
		.snapshot_scan_converter_pipe_empty_o(
			snapshot_scan_converter_empty_w),
		.snapshot_event_coherent_o(snapshot_event_coherent_w)
	);

	vip_render_subsystem
	#(
		.COMPOSED_TIMING_CREDIT_ENABLE(1)
	)
	u_render_subsystem
	(
		.clk_i(clk_i),
		.reset_i(vip_reset_w),
		.ce_i(ce_i),
		.engine_cmd_valid_i(engine_cmd_valid_w),
		.engine_cmd_ready_o(engine_cmd_ready_w),
		.engine_cmd_kind_i(engine_cmd_kind_w),
		.engine_cmd_strip_i(engine_cmd_strip_w),
		.engine_cmd_world_i(engine_cmd_world_w),
		.engine_cmd_descriptor_i(engine_cmd_descriptor_w),
		.engine_cmd_first_visit_i(engine_cmd_first_visit_w),
		.engine_done_o(engine_done_w),
		.engine_abort_i(engine_abort_w),
		.parallax_scale_i(parallax_scale_i),
		.gplt_active_i(gplt_active_w),
		.spt_active_i(spt_active_w),
		.jplt_active_i(jplt_active_w),
		.aggregate_dram_abort_o(aggregate_dram_abort_w),
		.aggregate_dram_req_o(aggregate_dram_req_w),
		.aggregate_dram_addr_o(aggregate_dram_addr_w),
		.aggregate_dram_accept_i(aggregate_dram_accept_w),
		.aggregate_dram_resp_valid_i(aggregate_dram_resp_valid_w),
		.aggregate_dram_resp_data_i(aggregate_dram_resp_data_w),
		.aggregate_dram_cleanup_busy_i(aggregate_dram_cleanup_busy_w),
		.aggregate_dram_stale_discard_i(
			aggregate_dram_stale_discarded_w),
		.aggregate_vrm_abort_o(aggregate_vrm_abort_w),
		.aggregate_vrm_req_o(aggregate_vrm_req_w),
		.aggregate_vrm_addr_o(aggregate_vrm_addr_w),
		.aggregate_vrm_accept_i(aggregate_vrm_accept_w),
		.aggregate_vrm_resp_valid_i(aggregate_vrm_resp_valid_w),
		.aggregate_vrm_resp_data_i(aggregate_vrm_resp_data_w),
		.aggregate_vrm_cleanup_busy_i(aggregate_vrm_cleanup_busy_w),
		.aggregate_vrm_stale_discard_i(
			aggregate_vrm_stale_discarded_w),
		.row_producer_valid_o(row_producer_valid_w),
		.row_producer_ready_i(row_producer_ready_w),
		.row_producer_row_o(row_producer_row_w),
		.row_producer_left_base_x_o(row_producer_left_base_x_w),
		.row_producer_left_enable_o(row_producer_left_enable_w),
		.row_producer_left_active_o(row_producer_left_active_w),
		.row_producer_left_opaque_o(row_producer_left_opaque_w),
		.row_producer_left_values_o(row_producer_left_values_w),
		.row_producer_right_base_x_o(row_producer_right_base_x_w),
		.row_producer_right_enable_o(row_producer_right_enable_w),
		.row_producer_right_active_o(row_producer_right_active_w),
		.row_producer_right_opaque_o(row_producer_right_opaque_w),
		.row_producer_right_values_o(row_producer_right_values_w),
		.row_producer_done_i(row_producer_done_w),
		.affine_abort_o(affine_abort_w),
		.affine_prepare_valid_o(affine_prepare_valid_w),
		.affine_prepare_ready_i(affine_prepare_ready_w),
		.affine_prepare_row_o(affine_prepare_row_w),
		.affine_prepare_left_base_x_o(affine_prepare_left_base_x_w),
		.affine_prepare_left_enable_o(affine_prepare_left_enable_w),
		.affine_prepare_right_base_x_o(affine_prepare_right_base_x_w),
		.affine_prepare_right_enable_o(affine_prepare_right_enable_w),
		.affine_commit_valid_o(affine_commit_valid_w),
		.affine_commit_ready_i(affine_commit_ready_w),
		.affine_commit_left_active_o(affine_commit_left_active_w),
		.affine_commit_left_opaque_o(affine_commit_left_opaque_w),
		.affine_commit_left_values_o(affine_commit_left_values_w),
		.affine_commit_right_active_o(affine_commit_right_active_w),
		.affine_commit_right_opaque_o(affine_commit_right_opaque_w),
		.affine_commit_right_values_o(affine_commit_right_values_w),
		.affine_store_quiescent_i(affine_store_quiescent_w),
		.global_quiescent_o(render_global_quiescent_w),
		.engine_cleanup_busy_o(engine_cleanup_busy_w)
	);
	/* verilator lint_on PINMISSING */
endmodule
/* verilator lint_on DECLFILENAME */
