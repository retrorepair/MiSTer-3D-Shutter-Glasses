// Copyright (c) 2026 Jamie Blanks

`timescale 1ns/1ps
/* verilator lint_off DECLFILENAME */

// Host bus, VIP memory, native display timing, and scanout.
//
// Connects the VIP bus, display timing, interrupts, memories, and renderers.

module vip_host_display_subsystem
#(
	parameter integer EVENT_SET_WINS = 1,
	parameter integer WRITE_FIRST_ON_BOUNDARY = 0,
	parameter integer NORMAL_MEMORY_CLIENT_ENABLE = 0,
	parameter integer AFFINE_STREAM_ENABLE = 0,
	parameter [7:0] LOCAL_TOTAL_CE = 8'd2,
	parameter [7:0] VRM_WRITE_TOTAL_CE = 8'd3,
	parameter [7:0] VRM_READ_TOTAL_CE = 8'd7,
	parameter [7:0] DRAM_WRITE_TOTAL_CE = 8'd3,
	parameter [7:0] DRAM_READ_TOTAL_CE = 8'd7,
	parameter [15:0] H_VISIBLE = 16'd384,
	parameter [15:0] H_TOTAL = 16'd1280,
	parameter [15:0] H_SYNC_BEG = 16'd1056,
	parameter [15:0] H_SYNC_END = 16'd1152,
	parameter [15:0] V_VISIBLE = 16'd224,
	parameter [15:0] V_TOTAL = 16'd312,
	parameter [15:0] V_SYNC_BEG = 16'd289,
	parameter [15:0] V_SYNC_END = 16'd292,
	parameter [18:0] NATIVE_LEFT_START_PRE = 19'd59999,
	parameter CTA_TIMED_EYE_END_ENABLE = 1'b0,
	parameter NATIVE_FRAMEBUFFER_CAPTURE_ENABLE = 1'b0
)
(
	input  wire         clk_i,
	input  wire         reset_i,
	input  wire         ce_i,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire         sim_snapshot_restore_commit_i,
	input  wire         sim_snapshot_restore_apply_i,
	input  wire [3647:0] sim_snapshot_restore_packet_i,
`endif
`endif
	input  wire         phi1_i,
	input  wire [5:0]   savestate_state_addr_i,
	input  wire [63:0]  savestate_state_wdata_i,
	input  wire         savestate_state_wren_i,
	input  wire         savestate_vram_mem_active_i,
	input  wire         savestate_dram_mem_active_i,
	input  wire [16:0]  savestate_mem_addr_i,
	input  wire         savestate_mem_rden_i,
	input  wire         savestate_mem_wren_i,
	input  wire [7:0]   savestate_mem_wdata_i,
	output wire [7:0]   savestate_vram_mem_rdata_o,
	output wire [7:0]   savestate_dram_mem_rdata_o,
	output wire [36:0]  savestate_scan_state_o,
	input  wire         video_ce_i,
	input  wire         video_phi1_i,
	input  wire         savestate_boundary_stop_i,

	// Public VIP host bus.
	input  wire         cs_i,
	input  wire [23:1]  a_i,
	input  wire [15:0]  din_i,
	input  wire [3:0]   be_i,
	input  wire [1:0]   st_i,
	input  wire         da_i,
	input  wire         mrq_i,
	input  wire         rw_i,
	input  wire         bcyst_i,
	output wire [15:0]  dout_o,
	output wire         ready_o,
	output wire         irq_o,

	// Native framebuffer DP client.
	input  wire         vram_dp_req_i,
	input  wire         vram_dp_write_i,
	input  wire [15:0]  vram_dp_addr_i,
	input  wire [15:0]  vram_dp_wdata_i,
	input  wire [1:0]   vram_dp_byte_enable_i,
	output wire         vram_dp_accept_o,
	output wire         vram_dp_resp_valid_o,
	output wire [15:0]  vram_dp_resp_data_o,

	// Raw-clocked DRAM observer.
	input  wire         dram_observer_enable_i,
	input  wire [15:0]  dram_observer_addr_i,
	output wire [15:0]  dram_observer_rdata_o,
	output wire         dram_observer_rvalid_o,

	// Optional Normal-world memory clients.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire         normal_memory_abort_i,
	input  wire         normal_vrm_req_i,
	input  wire [15:0]  normal_vrm_addr_i,
	input  wire         normal_dram_req_i,
	input  wire [15:0]  normal_dram_addr_i,
	/* verilator lint_on UNUSEDSIGNAL */
	output wire         normal_vrm_accept_o,
	output wire         normal_vrm_resp_valid_o,
	output wire [15:0]  normal_vrm_resp_data_o,
	output wire         normal_vrm_cleanup_busy_o,
	output wire         normal_vrm_stale_discarded_o,
	output wire         normal_vrm_router_error_o,
	output wire         normal_dram_accept_o,
	output wire         normal_dram_resp_valid_o,
	output wire [15:0]  normal_dram_resp_data_o,
	output wire         normal_dram_cleanup_busy_o,
	output wire         normal_dram_stale_discarded_o,
	output wire         normal_dram_router_error_o,

	// External native timing and presentation controls.
	input  wire         dp_scan_ready_i,
	input  wire         scanerr_event_i,
	input  wire [7:0]   cta_left_servo_i,
	input  wire [7:0]   cta_right_servo_i,
	input  wire         column_group_valid_i,
	output wire         column_group_ready_o,
	input  wire         cta_timed_eye_end_i,
	input  wire         cta_timed_eye_end_eye_i,
	input  wire         completed_framebuffer_collision_free_i,
	input  wire [1:0]   presentation_mode_i,
	input  wire         flat_eye_i,
	input  wire         side_by_side_i,
	input  wire         compat_60hz_i,
	input  wire         shutter_i,
	input  wire         presentation_hlg_i,
	input  wire         brightness_table_legacy_sdr_i,
	input  wire         brightness_table_download_i,
	input  wire         brightness_table_write_i,
	input  wire [9:0]   brightness_table_addr_i,
	input  wire [15:0]  brightness_table_data_i,
	input  wire         brightness_cache_collision_free_i,

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

	// Registered row token from the renderer.
	input  wire         producer_valid_i,
	output wire         producer_ready_o,
	input  wire [8:0]   producer_column_i,
	input  wire         producer_left_enable_i,
	input  wire [15:0]  producer_left_preserve_mask_i,
	input  wire [15:0]  producer_left_value_i,
	input  wire         producer_right_enable_i,
	input  wire [15:0]  producer_right_preserve_mask_i,
	input  wire [15:0]  producer_right_value_i,
	output wire         producer_done_o,

	// Optional Normal renderer row token.
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
	output wire         row_producer_ready_o,
	output wire         row_producer_done_o,

	// Optional four-pixel Affine row-store input.
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
	output wire         affine_active_o,
	output wire         affine_quiescent_o,
	output wire         affine_done_o,

	// Registers and interrupt state.
	output wire [15:0]  event_o,
	output wire [15:0]  int_pending_o,
	output wire [15:0]  int_enable_o,
	output wire         dprst_o,
	output wire         xprst_o,
	output wire         dp_lock_o,
	output wire         dp_synce_program_o,
	output wire         dp_synce_active_o,
	output wire         dp_refresh_o,
	output wire         dp_display_program_o,
	output wire         dp_display_active_o,
	output wire [4:0]   xp_sbcmp_o,
	output wire         xp_enable_o,
	output wire [1:0]   bkcol_register_o,
	output wire [1:0]   bkcol_active_o,
	output wire [31:0]  brightness_register_o,
	output wire [31:0]  brightness_active_o,
	output wire [3:0]   frmcyc_register_o,
	output wire [3:0]   frmcyc_register_active_o,
	output wire [15:0]  cta_o,
	output wire [39:0]  spt_register_o,
	output wire [39:0]  spt_active_o,
	output wire [31:0]  gplt_register_o,
	output wire [31:0]  gplt_active_o,
	output wire [31:0]  jplt_register_o,
	output wire [31:0]  jplt_active_o,
	output wire         bkcol_pending_o,
	output wire         bkcol_wait_first_group_o,
	output wire [6:0]   event_history_o,

	// Native timing and boundary events.
	output wire [18:0]  native_frame_cycle_o,
	output wire         native_fclk_o,
	output wire         native_waiting_for_fclk_o,
	output wire         native_left_busy_o,
	output wire         native_right_busy_o,
	output wire         native_frame_start_o,
	output wire         native_left_start_o,
	output wire         native_left_end_o,
	output wire         native_right_start_o,
	output wire         native_right_end_o,
	output wire         native_gclk_rise_o,
	output wire         native_game_start_o,
	output wire         native_frame_start_fire_o,
	output wire         native_left_start_fire_o,
	output wire         native_left_end_fire_o,
	output wire         native_right_start_fire_o,
	output wire         native_right_end_fire_o,
	output wire         native_gclk_rise_fire_o,
	output wire         native_game_start_fire_o,
	output wire [3:0]   native_frmcyc_active_o,
	output wire [3:0]   native_game_frame_wait_o,

	// CTA results and memory health.
	output wire         ctc_valid_o,
	output wire [15:0]  ctc_data_o,
	output wire         ctc_eye_o,
	output wire [6:0]   ctc_ordinal_o,
	output wire [7:0]   ctc_index_o,
	output wire         cta_field_active_o,
	output wire         cta_transaction_active_o,
	output wire         host_busy_o,
	output wire         host_local_active_o,
	output wire         vram_cpu_timing_busy_o,
	output wire         vram_store_busy_o,
	output wire         vram_inner_offer_held_o,
	output wire         vram_read_pending_o,
	output wire         dram_cpu_timing_busy_o,
	output wire         dram_store_busy_o,
	output wire         dram_inner_offer_held_o,
	output wire         dram_read_pending_o,
	output wire         brightness_worker_owner_active_o,
	output wire         brightness_allocator_owner_active_o,
	output wire         brightness_result_owner_active_o,
	output wire         brightness_raster_read_owner_active_o,
	output wire         scanout_owner_active_o,
	output wire         abort_cleanup_owner_active_o,
	output wire         cta_dram_accept_o,
	output wire         cta_dram_resp_valid_o,
	output wire         vram_physical_accept_o,
	output wire         vram_physical_write_o,
	output wire [1:0]   vram_physical_owner_o,
	output wire [15:0]  vram_physical_addr_o,
	output wire [15:0]  vram_physical_wdata_o,
	output wire [1:0]   vram_physical_byte_enable_o,
	output wire         vram_physical_resp_valid_o,
	output wire [1:0]   vram_physical_resp_owner_o,
	output wire         dram_physical_accept_o,
	output wire         dram_physical_write_o,
	output wire [1:0]   dram_physical_owner_o,
	output wire [15:0]  dram_physical_addr_o,
	output wire [15:0]  dram_physical_wdata_o,
	output wire [1:0]   dram_physical_byte_enable_o,
	output wire         dram_physical_resp_valid_o,
	output wire [1:0]   dram_physical_resp_owner_o,

	// MiSTer raster observer.
	output wire         displayed_fb_latched_o,
	output wire         vrm_observer_enable_o,
	output wire [15:0]  vrm_observer_addr_o,
	output wire         vrm_observer_rvalid_o,
	output wire [15:0]  vrm_observer_rdata_o,
	output wire         framebuffer_collision_precondition_violation_o,
	output wire         observer_alignment_error_o,
	output wire         brightness_alignment_error_o,
	output wire         pixel_ce_o,
	output wire [15:0]  raster_x_o,
	output wire [15:0]  raster_y_o,
	output wire         video_hblank_o,
	output wire         video_vblank_o,
	output wire         video_hsync_o,
	output wire         video_vsync_o,
	output wire [1:0]   raw_pixel_left_o,
	output wire [1:0]   raw_pixel_right_o,
	output wire [7:0]   video_luma_left_o,
	output wire [7:0]   video_luma_right_o,

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

	// Completed framebuffer state.
	output wire         displayed_fb_o,
	output wire         active_draw_valid_o,
	output wire         active_draw_target_o,
	output wire         completed_pending_valid_o,
	output wire         completed_pending_target_o,
	output wire         display_swap_o,
	output wire         completion_commit_o,

	// Aggregate XP memory diagnostics.
	output wire         xp_vrm_req_o,
	output wire         xp_vrm_write_o,
	output wire [15:0]  xp_vrm_addr_o,
	output wire [15:0]  xp_vrm_wdata_o,
	output wire [1:0]   xp_vrm_byte_enable_o,
	output wire         xp_vrm_accept_o,
	output wire         xp_vrm_resp_valid_o,
	output wire [15:0]  xp_vrm_resp_data_o,
	output wire         xp_dram_req_o,
	output wire         xp_dram_write_o,
	output wire [15:0]  xp_dram_addr_o,
	output wire [15:0]  xp_dram_wdata_o,
	output wire [1:0]   xp_dram_byte_enable_o,
	output wire         xp_dram_accept_o,
	output wire         xp_dram_resp_valid_o,
	output wire [15:0]  xp_dram_resp_data_o,

	// Render coordinator diagnostics.
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
	// Simulation-only descriptor retirement trace.
	output wire [7:0]   sim_p06_observation_schema_o,
	output wire         snapshot_stale_response_discarded_o,
	output wire [9:0]   snapshot_discarded_count_o,
`endif
	output wire         ownership_mismatch_o,

	// Stopped-state status for simulation snapshots.
	output wire         snapshot_cta_idle_o,
	output wire         snapshot_brightness_worker_idle_o,
	output wire         snapshot_brightness_allocator_idle_o,
	output wire         snapshot_brightness_raster_pipe_empty_o,
	output wire         snapshot_framebuffer_capture_idle_o,
	output wire         snapshot_scan_converter_pipe_empty_o,
	output wire         snapshot_event_coherent_o
);
	localparam integer NORMAL_MEMORY_PATH_ENABLE =
		(NORMAL_MEMORY_CLIENT_ENABLE != 0) ? 1 : 0;

`ifndef SYNTHESIS
	assign sim_p06_observation_schema_o = 8'd1;
`endif

	wire         xp_vrm_req_w;
	wire         xp_vrm_write_w;
	wire [15:0]  xp_vrm_addr_w;
	wire [15:0]  xp_vrm_wdata_w;
	wire [1:0]   xp_vrm_byte_enable_w;
	wire         xp_vrm_accept_w;
	wire         xp_dram_req_w;
	wire         xp_dram_write_w;
	wire [15:0]  xp_dram_addr_w;
	wire [15:0]  xp_dram_wdata_w;
	wire [1:0]   xp_dram_byte_enable_w;
	wire         xp_dram_accept_w;
	wire         xp_dram_resp_valid_w;
	wire [15:0]  xp_dram_resp_data_w;
	wire         framebuffer_handoff_fire_w =
		native_game_start_fire_o && xp_enable_o &&
		completed_pending_valid_o;

	wire         xp_engine_cmd_valid_w;
	wire         xp_engine_cmd_ready_w;
	wire [1:0]   xp_engine_cmd_kind_w;
	wire [4:0]   xp_engine_cmd_strip_w;
	wire [4:0]   xp_engine_cmd_world_w;
	wire [255:0] xp_engine_cmd_descriptor_w;
	wire         xp_engine_cmd_first_visit_w;
	wire         xp_engine_done_w;
	wire         xp_engine_abort_w;

	// External renderers use the shared memory routers; the subclient
	// muxes' internal-client ports are tied off below.
	/* verilator lint_off UNUSEDSIGNAL */
	wire         normal_vrm_router_abort_status_w;
	wire         normal_vrm_router_cleanup_status_w;
	wire         normal_vrm_router_stale_status_w;
	wire         normal_dram_router_abort_status_w;
	wire         normal_dram_router_cleanup_status_w;
	wire         normal_dram_router_stale_status_w;
	wire         selected_abort_active_w;
	wire         selected_engine_cleanup_active_w;
	wire         client_cleanup_active_w;
	wire         router_cleanup_active_w;
	/* verilator lint_on UNUSEDSIGNAL */


	assign engine_abort_o = xp_engine_abort_w;
	assign selected_abort_active_w = xp_engine_abort_w ||
		((NORMAL_MEMORY_PATH_ENABLE != 0) && normal_memory_abort_i) ||
		((AFFINE_STREAM_ENABLE != 0) && affine_abort_i);
	assign selected_engine_cleanup_active_w = engine_cleanup_busy_i;
	assign client_cleanup_active_w =
		normal_vrm_cleanup_busy_o || normal_vrm_stale_discarded_o ||
		normal_dram_cleanup_busy_o || normal_dram_stale_discarded_o;
	assign router_cleanup_active_w =
		normal_vrm_router_abort_status_w ||
		normal_vrm_router_cleanup_status_w ||
		normal_vrm_router_stale_status_w ||
		normal_dram_router_abort_status_w ||
		normal_dram_router_cleanup_status_w ||
		normal_dram_router_stale_status_w;
	assign abort_cleanup_owner_active_o = selected_abort_active_w ||
		selected_engine_cleanup_active_w || client_cleanup_active_w ||
		router_cleanup_active_w;

	// Pass commands and row tokens through the renderer interface.
	assign xp_engine_cmd_ready_w = engine_cmd_ready_i;
	assign xp_engine_done_w = engine_done_i;
	assign engine_cmd_valid_o = xp_engine_cmd_valid_w;
	assign engine_cmd_kind_o = xp_engine_cmd_kind_w;
	assign engine_cmd_strip_o = xp_engine_cmd_strip_w;
	assign engine_cmd_world_o = xp_engine_cmd_world_w;
	assign engine_cmd_descriptor_o =
		xp_engine_cmd_descriptor_w;
	assign engine_cmd_first_visit_o =
		xp_engine_cmd_first_visit_w;

	generate
		if (NORMAL_MEMORY_PATH_ENABLE != 0) begin : g_normal_memory_routers
			wire normal_vrm_router_abort_w;
			wire normal_vrm_router_req_w;
			wire [15:0] normal_vrm_router_addr_w;
			wire normal_vrm_router_accept_w;
			wire normal_vrm_router_resp_valid_w;
			wire [15:0] normal_vrm_router_resp_data_w;
			wire normal_vrm_router_cleanup_busy_w;
			wire normal_vrm_router_stale_discarded_w;
			wire vrm_subclient_accept_without_offer_w;
			wire vrm_subclient_retire_without_pending_w;
			wire vrm_subclient_outstanding_overlap_w;
			wire normal_dram_router_abort_w;
			wire normal_dram_router_req_w;
			wire [15:0] normal_dram_router_addr_w;
			wire normal_dram_router_accept_w;
			wire normal_dram_router_resp_valid_w;
			wire [15:0] normal_dram_router_resp_data_w;
			wire normal_dram_router_cleanup_busy_w;
			wire normal_dram_router_stale_discarded_w;
			wire dram_subclient_accept_without_offer_w;
			wire dram_subclient_retire_without_pending_w;
			wire dram_subclient_outstanding_overlap_w;
			wire vrm_unexpected_response_w;
			wire vrm_capture_overflow_w;
			wire vrm_owner_overlap_w;
			wire dram_unexpected_response_w;
			wire dram_capture_overflow_w;
			wire dram_owner_overlap_w;

			/* verilator lint_off PINCONNECTEMPTY */
			vip_xp_read_subclient_mux u_vrm_subclient_mux
			(
				.clk_i(clk_i),
				.reset_i(reset_i),
				.ce_i(ce_i),
				.global_abort_i(xp_engine_abort_w),
				.external_abort_i(normal_memory_abort_i),
				.internal_req_i(1'b0),
				.internal_addr_i(16'd0),
				.internal_accept_o(),
				.internal_resp_valid_o(),
				.internal_resp_data_o(),
				.internal_cleanup_busy_o(),
				.internal_stale_discarded_o(),
				.external_req_i(normal_vrm_req_i),
				.external_addr_i(normal_vrm_addr_i),
				.external_accept_o(normal_vrm_accept_o),
				.external_resp_valid_o(normal_vrm_resp_valid_o),
				.external_resp_data_o(normal_vrm_resp_data_o),
				.external_cleanup_busy_o(normal_vrm_cleanup_busy_o),
				.external_stale_discarded_o(
					normal_vrm_stale_discarded_o),
				.aggregate_abort_o(normal_vrm_router_abort_w),
				.aggregate_req_o(normal_vrm_router_req_w),
				.aggregate_addr_o(normal_vrm_router_addr_w),
				.aggregate_accept_i(normal_vrm_router_accept_w),
				.aggregate_resp_valid_i(normal_vrm_router_resp_valid_w),
				.aggregate_resp_data_i(normal_vrm_router_resp_data_w),
				.aggregate_cleanup_busy_i(
					normal_vrm_router_cleanup_busy_w),
				.aggregate_stale_discarded_i(
					normal_vrm_router_stale_discarded_w),
				.held_offer_o(),
				.held_owner_internal_o(),
				.read_pending_o(),
				.pending_owner_internal_o(),
				.accept_without_offer_o(
					vrm_subclient_accept_without_offer_w),
				.retire_without_pending_o(
					vrm_subclient_retire_without_pending_w),
				.outstanding_overlap_o(
					vrm_subclient_outstanding_overlap_w)
			);

			vip_xp_read_subclient_mux u_dram_subclient_mux
			(
				.clk_i(clk_i),
				.reset_i(reset_i),
				.ce_i(ce_i),
				.global_abort_i(xp_engine_abort_w),
				.external_abort_i(normal_memory_abort_i),
				.internal_req_i(1'b0),
				.internal_addr_i(16'd0),
				.internal_accept_o(),
				.internal_resp_valid_o(),
				.internal_resp_data_o(),
				.internal_cleanup_busy_o(),
				.internal_stale_discarded_o(),
				.external_req_i(normal_dram_req_i),
				.external_addr_i(normal_dram_addr_i),
				.external_accept_o(normal_dram_accept_o),
				.external_resp_valid_o(normal_dram_resp_valid_o),
				.external_resp_data_o(normal_dram_resp_data_o),
				.external_cleanup_busy_o(normal_dram_cleanup_busy_o),
				.external_stale_discarded_o(
					normal_dram_stale_discarded_o),
				.aggregate_abort_o(normal_dram_router_abort_w),
				.aggregate_req_o(normal_dram_router_req_w),
				.aggregate_addr_o(normal_dram_router_addr_w),
				.aggregate_accept_i(normal_dram_router_accept_w),
				.aggregate_resp_valid_i(normal_dram_router_resp_valid_w),
				.aggregate_resp_data_i(normal_dram_router_resp_data_w),
				.aggregate_cleanup_busy_i(
					normal_dram_router_cleanup_busy_w),
				.aggregate_stale_discarded_i(
					normal_dram_router_stale_discarded_w),
				.held_offer_o(),
				.held_owner_internal_o(),
				.read_pending_o(),
				.pending_owner_internal_o(),
				.accept_without_offer_o(
					dram_subclient_accept_without_offer_w),
				.retire_without_pending_o(
					dram_subclient_retire_without_pending_w),
				.outstanding_overlap_o(
					dram_subclient_outstanding_overlap_w)
			);

			vip_xp_memory_router u_vrm_router
			(
				.clk_i(clk_i),
				.reset_i(reset_i),
				.ce_i(ce_i),
				.normal_abort_i(normal_vrm_router_abort_w),
				.primary_req_i(xp_vrm_req_w),
				.primary_write_i(xp_vrm_write_w),
				.primary_addr_i(xp_vrm_addr_w),
				.primary_wdata_i(xp_vrm_wdata_w),
				.primary_byte_enable_i(xp_vrm_byte_enable_w),
				.primary_accept_o(xp_vrm_accept_w),
				.primary_resp_valid_o(),
				.primary_resp_data_o(),
				.normal_req_i(normal_vrm_router_req_w),
				.normal_addr_i(normal_vrm_router_addr_w),
				.normal_accept_o(normal_vrm_router_accept_w),
				.normal_resp_valid_o(normal_vrm_router_resp_valid_w),
				.normal_resp_data_o(normal_vrm_router_resp_data_w),
				.downstream_req_o(xp_vrm_req_o),
				.downstream_write_o(xp_vrm_write_o),
				.downstream_addr_o(xp_vrm_addr_o),
				.downstream_wdata_o(xp_vrm_wdata_o),
				.downstream_byte_enable_o(xp_vrm_byte_enable_o),
				.downstream_accept_i(xp_vrm_accept_o),
				.downstream_resp_valid_i(xp_vrm_resp_valid_o),
				.downstream_resp_data_i(xp_vrm_resp_data_o),
				.offer_locked_o(),
				.read_pending_o(),
				.normal_cleanup_busy_o(normal_vrm_router_cleanup_busy_w),
				.stale_response_discarded_o(
					normal_vrm_router_stale_discarded_w),
				.unexpected_response_o(vrm_unexpected_response_w),
				.response_capture_overflow_o(vrm_capture_overflow_w),
				.read_owner_overlap_o(vrm_owner_overlap_w)
			);

			vip_xp_memory_router u_dram_router
			(
				.clk_i(clk_i),
				.reset_i(reset_i),
				.ce_i(ce_i),
				.normal_abort_i(normal_dram_router_abort_w),
				.primary_req_i(xp_dram_req_w),
				.primary_write_i(xp_dram_write_w),
				.primary_addr_i(xp_dram_addr_w),
				.primary_wdata_i(xp_dram_wdata_w),
				.primary_byte_enable_i(xp_dram_byte_enable_w),
				.primary_accept_o(xp_dram_accept_w),
				.primary_resp_valid_o(xp_dram_resp_valid_w),
				.primary_resp_data_o(xp_dram_resp_data_w),
				.normal_req_i(normal_dram_router_req_w),
				.normal_addr_i(normal_dram_router_addr_w),
				.normal_accept_o(normal_dram_router_accept_w),
				.normal_resp_valid_o(normal_dram_router_resp_valid_w),
				.normal_resp_data_o(normal_dram_router_resp_data_w),
				.downstream_req_o(xp_dram_req_o),
				.downstream_write_o(xp_dram_write_o),
				.downstream_addr_o(xp_dram_addr_o),
				.downstream_wdata_o(xp_dram_wdata_o),
				.downstream_byte_enable_o(xp_dram_byte_enable_o),
				.downstream_accept_i(xp_dram_accept_o),
				.downstream_resp_valid_i(xp_dram_resp_valid_o),
				.downstream_resp_data_i(xp_dram_resp_data_o),
				.offer_locked_o(),
				.read_pending_o(),
				.normal_cleanup_busy_o(normal_dram_router_cleanup_busy_w),
				.stale_response_discarded_o(
					normal_dram_router_stale_discarded_w),
				.unexpected_response_o(dram_unexpected_response_w),
				.response_capture_overflow_o(dram_capture_overflow_w),
				.read_owner_overlap_o(dram_owner_overlap_w)
			);
			/* verilator lint_on PINCONNECTEMPTY */

			assign normal_vrm_router_error_o =
				vrm_unexpected_response_w || vrm_capture_overflow_w ||
				vrm_owner_overlap_w ||
				vrm_subclient_accept_without_offer_w ||
				vrm_subclient_retire_without_pending_w ||
				vrm_subclient_outstanding_overlap_w;
			assign normal_dram_router_error_o =
				dram_unexpected_response_w || dram_capture_overflow_w ||
				dram_owner_overlap_w ||
				dram_subclient_accept_without_offer_w ||
				dram_subclient_retire_without_pending_w ||
				dram_subclient_outstanding_overlap_w;
			assign normal_vrm_router_abort_status_w =
				normal_vrm_router_abort_w;
			assign normal_vrm_router_cleanup_status_w =
				normal_vrm_router_cleanup_busy_w;
			assign normal_vrm_router_stale_status_w =
				normal_vrm_router_stale_discarded_w;
			assign normal_dram_router_abort_status_w =
				normal_dram_router_abort_w;
			assign normal_dram_router_cleanup_status_w =
				normal_dram_router_cleanup_busy_w;
			assign normal_dram_router_stale_status_w =
				normal_dram_router_stale_discarded_w;
		end else begin : g_xp_memory_passthrough
			assign xp_vrm_req_o = xp_vrm_req_w;
			assign xp_vrm_write_o = xp_vrm_write_w;
			assign xp_vrm_addr_o = xp_vrm_addr_w;
			assign xp_vrm_wdata_o = xp_vrm_wdata_w;
			assign xp_vrm_byte_enable_o = xp_vrm_byte_enable_w;
			assign xp_vrm_accept_w = xp_vrm_accept_o;
			assign xp_dram_req_o = xp_dram_req_w;
			assign xp_dram_write_o = xp_dram_write_w;
			assign xp_dram_addr_o = xp_dram_addr_w;
			assign xp_dram_wdata_o = xp_dram_wdata_w;
			assign xp_dram_byte_enable_o = xp_dram_byte_enable_w;
			assign xp_dram_accept_w = xp_dram_accept_o;
			assign xp_dram_resp_valid_w = xp_dram_resp_valid_o;
			assign xp_dram_resp_data_w = xp_dram_resp_data_o;
			assign normal_vrm_accept_o = 1'b0;
			assign normal_vrm_resp_valid_o = 1'b0;
			assign normal_vrm_resp_data_o = 16'd0;
			assign normal_vrm_cleanup_busy_o = 1'b0;
			assign normal_vrm_stale_discarded_o = 1'b0;
			assign normal_vrm_router_error_o = 1'b0;
			assign normal_dram_accept_o = 1'b0;
			assign normal_dram_resp_valid_o = 1'b0;
			assign normal_dram_resp_data_o = 16'd0;
			assign normal_dram_cleanup_busy_o = 1'b0;
			assign normal_dram_stale_discarded_o = 1'b0;
			assign normal_dram_router_error_o = 1'b0;
			assign normal_vrm_router_abort_status_w = 1'b0;
			assign normal_vrm_router_cleanup_status_w = 1'b0;
			assign normal_vrm_router_stale_status_w = 1'b0;
			assign normal_dram_router_abort_status_w = 1'b0;
			assign normal_dram_router_cleanup_status_w = 1'b0;
			assign normal_dram_router_stale_status_w = 1'b0;
		end
	endgenerate

	/* verilator lint_off PINCONNECTEMPTY */
	vip_display_subsystem
	#(
		.EVENT_SET_WINS(EVENT_SET_WINS),
		.WRITE_FIRST_ON_BOUNDARY(WRITE_FIRST_ON_BOUNDARY),
		.LOCAL_TOTAL_CE(LOCAL_TOTAL_CE),
		.VRM_WRITE_TOTAL_CE(VRM_WRITE_TOTAL_CE),
		.VRM_READ_TOTAL_CE(VRM_READ_TOTAL_CE),
		.DRAM_WRITE_TOTAL_CE(DRAM_WRITE_TOTAL_CE),
		.DRAM_READ_TOTAL_CE(DRAM_READ_TOTAL_CE),
		.H_VISIBLE(H_VISIBLE),
		.H_TOTAL(H_TOTAL),
		.H_SYNC_BEG(H_SYNC_BEG),
		.H_SYNC_END(H_SYNC_END),
		.V_VISIBLE(V_VISIBLE),
		.V_TOTAL(V_TOTAL),
		.V_SYNC_BEG(V_SYNC_BEG),
		.V_SYNC_END(V_SYNC_END),
		.NATIVE_LEFT_START_PRE(NATIVE_LEFT_START_PRE),
		.CTA_TIMED_EYE_END_ENABLE(CTA_TIMED_EYE_END_ENABLE),
		.NATIVE_FRAMEBUFFER_CAPTURE_ENABLE(
			NATIVE_FRAMEBUFFER_CAPTURE_ENABLE)
	)
	u_display_subsystem
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		.sim_snapshot_restore_commit_i(sim_snapshot_restore_commit_i),
		.sim_snapshot_restore_apply_i(sim_snapshot_restore_apply_i),
		.sim_snapshot_restore_packet_i(sim_snapshot_restore_packet_i),
`endif
`endif
		.phi1_i(phi1_i),
		.savestate_state_addr_i(savestate_state_addr_i),
		.savestate_state_wdata_i(savestate_state_wdata_i),
		.savestate_state_wren_i(savestate_state_wren_i),
		.savestate_vram_mem_active_i(savestate_vram_mem_active_i),
		.savestate_dram_mem_active_i(savestate_dram_mem_active_i),
		.savestate_mem_addr_i(savestate_mem_addr_i),
		.savestate_mem_rden_i(savestate_mem_rden_i),
		.savestate_mem_wren_i(savestate_mem_wren_i),
		.savestate_mem_wdata_i(savestate_mem_wdata_i),
		.savestate_vram_mem_rdata_o(savestate_vram_mem_rdata_o),
		.savestate_dram_mem_rdata_o(savestate_dram_mem_rdata_o),
		.savestate_scan_state_o(savestate_scan_state_o),
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
		.vram_dp_req_i(vram_dp_req_i),
		.vram_dp_write_i(vram_dp_write_i),
		.vram_dp_addr_i(vram_dp_addr_i),
		.vram_dp_wdata_i(vram_dp_wdata_i),
		.vram_dp_byte_enable_i(vram_dp_byte_enable_i),
		.vram_dp_accept_o(vram_dp_accept_o),
		.vram_dp_resp_valid_o(vram_dp_resp_valid_o),
		.vram_dp_resp_data_o(vram_dp_resp_data_o),
		.vram_xp_req_i(xp_vrm_req_o),
		.vram_xp_write_i(xp_vrm_write_o),
		.vram_xp_addr_i(xp_vrm_addr_o),
		.vram_xp_wdata_i(xp_vrm_wdata_o),
		.vram_xp_byte_enable_i(xp_vrm_byte_enable_o),
		.vram_xp_accept_o(xp_vrm_accept_o),
		.vram_xp_resp_valid_o(xp_vrm_resp_valid_o),
		.vram_xp_resp_data_o(xp_vrm_resp_data_o),
		.dram_xp_req_i(xp_dram_req_o),
		.dram_xp_write_i(xp_dram_write_o),
		.dram_xp_addr_i(xp_dram_addr_o),
		.dram_xp_wdata_i(xp_dram_wdata_o),
		.dram_xp_byte_enable_i(xp_dram_byte_enable_o),
		.dram_xp_accept_o(xp_dram_accept_o),
		.dram_xp_resp_valid_o(xp_dram_resp_valid_o),
		.dram_xp_resp_data_o(xp_dram_resp_data_o),
		.dram_observer_enable_i(dram_observer_enable_i),
		.dram_observer_addr_i(dram_observer_addr_i),
		.dram_observer_rdata_o(dram_observer_rdata_o),
		.dram_observer_rvalid_o(dram_observer_rvalid_o),
		.vram_physical_accept_o(vram_physical_accept_o),
		.vram_physical_write_o(vram_physical_write_o),
		.vram_physical_owner_o(vram_physical_owner_o),
		.vram_physical_addr_o(vram_physical_addr_o),
		.vram_physical_wdata_o(vram_physical_wdata_o),
		.vram_physical_byte_enable_o(vram_physical_byte_enable_o),
		.vram_physical_resp_valid_o(vram_physical_resp_valid_o),
		.vram_physical_resp_owner_o(vram_physical_resp_owner_o),
		.dram_physical_accept_o(dram_physical_accept_o),
		.dram_physical_write_o(dram_physical_write_o),
		.dram_physical_owner_o(dram_physical_owner_o),
		.dram_physical_addr_o(dram_physical_addr_o),
		.dram_physical_wdata_o(dram_physical_wdata_o),
		.dram_physical_byte_enable_o(dram_physical_byte_enable_o),
		.dram_physical_resp_valid_o(dram_physical_resp_valid_o),
		.dram_physical_resp_owner_o(dram_physical_resp_owner_o),
		.dp_scan_ready_i(dp_scan_ready_i),
		.xp_sbout_i(xp_sbout_o),
		.xp_sbcount_i(xp_sbcount_o),
		.xp_overtime_i(xp_overtime_o),
		.xp_busy_i(xp_busy_o),
		.scanerr_event_i(scanerr_event_i),
		.cta_left_servo_i(cta_left_servo_i),
		.cta_right_servo_i(cta_right_servo_i),
		.xp_draw_start_i(draw_start_fire_o),
		.xp_first_group_done_i(first_group_done_fire_o),
		.xp_sb_hit_fire_i(sb_hit_fire_o),
		.xp_end_fire_i(xp_end_fire_o),
		.xp_timeerr_fire_i(timeerr_fire_o),
		.column_group_valid_i(column_group_valid_i),
		.column_group_ready_o(column_group_ready_o),
		.cta_timed_eye_end_i(cta_timed_eye_end_i),
		.cta_timed_eye_end_eye_i(cta_timed_eye_end_eye_i),
		.displayed_fb_i(displayed_fb_o),
		.framebuffer_handoff_fire_i(framebuffer_handoff_fire_w),
		.framebuffer_handoff_target_i(completed_pending_target_o),
		.completed_framebuffer_collision_free_i(
			completed_framebuffer_collision_free_i),
		.presentation_mode_i(presentation_mode_i),
		.flat_eye_i(flat_eye_i),
		.side_by_side_i(side_by_side_i),
		.compat_60hz_i(compat_60hz_i),
		.shutter_i(shutter_i),
		.presentation_hlg_i(presentation_hlg_i),
		.brightness_table_legacy_sdr_i(brightness_table_legacy_sdr_i),
		.brightness_table_download_i(brightness_table_download_i),
		.brightness_table_write_i(brightness_table_write_i),
		.brightness_table_addr_i(brightness_table_addr_i),
		.brightness_table_data_i(brightness_table_data_i),
		.brightness_cache_collision_free_i(
			brightness_cache_collision_free_i),
		.event_o(event_o),
		.int_pending_o(int_pending_o),
		.int_enable_o(int_enable_o),
		.dprst_o(dprst_o),
		.xprst_o(xprst_o),
		.dp_lock_o(dp_lock_o),
		.dp_synce_program_o(dp_synce_program_o),
		.dp_synce_active_o(dp_synce_active_o),
		.dp_refresh_o(dp_refresh_o),
		.dp_display_program_o(dp_display_program_o),
		.dp_display_active_o(dp_display_active_o),
		.xp_sbcmp_o(xp_sbcmp_o),
		.xp_enable_o(xp_enable_o),
		.bkcol_register_o(bkcol_register_o),
		.bkcol_active_o(bkcol_active_o),
		.brightness_register_o(brightness_register_o),
		.brightness_active_o(brightness_active_o),
		.frmcyc_register_o(frmcyc_register_o),
		.frmcyc_register_active_o(frmcyc_register_active_o),
		.cta_o(cta_o),
		.spt_register_o(spt_register_o),
		.spt_active_o(spt_active_o),
		.gplt_register_o(gplt_register_o),
		.gplt_active_o(gplt_active_o),
		.jplt_register_o(jplt_register_o),
		.jplt_active_o(jplt_active_o),
		.bkcol_pending_o(bkcol_pending_o),
		.bkcol_wait_first_group_o(bkcol_wait_first_group_o),
		.event_history_o(event_history_o),
		.native_frame_cycle_o(native_frame_cycle_o),
		.native_fclk_o(native_fclk_o),
		.native_waiting_for_fclk_o(native_waiting_for_fclk_o),
		.native_left_busy_o(native_left_busy_o),
		.native_right_busy_o(native_right_busy_o),
		.native_frame_start_o(native_frame_start_o),
		.native_left_start_o(native_left_start_o),
		.native_left_end_o(native_left_end_o),
		.native_right_start_o(native_right_start_o),
		.native_right_end_o(native_right_end_o),
		.native_gclk_rise_o(native_gclk_rise_o),
		.native_game_start_o(native_game_start_o),
		.native_frame_start_fire_o(native_frame_start_fire_o),
		.native_left_start_fire_o(native_left_start_fire_o),
		.native_left_end_fire_o(native_left_end_fire_o),
		.native_right_start_fire_o(native_right_start_fire_o),
		.native_right_end_fire_o(native_right_end_fire_o),
		.native_gclk_rise_fire_o(native_gclk_rise_fire_o),
		.native_game_start_fire_o(native_game_start_fire_o),
		.native_frmcyc_active_o(native_frmcyc_active_o),
		.native_game_frame_wait_o(native_game_frame_wait_o),
		.ctc_valid_o(ctc_valid_o),
		.ctc_data_o(ctc_data_o),
		.ctc_eye_o(ctc_eye_o),
		.ctc_ordinal_o(ctc_ordinal_o),
		.ctc_index_o(ctc_index_o),
		.cta_field_complete_o(),
		.cta_field_complete_eye_o(),
		.cta_field_incomplete_o(),
		.cta_field_overlap_o(),
		.cta_field_active_o(cta_field_active_o),
		.cta_transaction_active_o(cta_transaction_active_o),
		.cta_group_count_o(),
		.cta_request_count_o(),
		.cta_response_count_o(),
		.brightness_busy_o(),
		.brightness_result_valid_o(),
		.brightness_result_eye_o(),
		.brightness_result_group_o(),
		.brightness_result_exposure_1_o(),
		.brightness_result_exposure_2_o(),
		.brightness_result_exposure_3_o(),
		.brightness_result_overrun_o(),
		.brightness_result_short_column_o(),
		.brightness_cycle_count_o(),
		.brightness_cache_write_candidate_o(),
		.brightness_cache_write_o(),
		.brightness_cache_write_blocked_o(),
		.brightness_cache_levels_o(),
		.brightness_generation_build_active_o(),
		.brightness_generation_pending_o(),
		.brightness_generation_display_valid_o(),
		.brightness_generation_display_o(),
		.brightness_generation_swap_o(),
		.brightness_alignment_error_o(brightness_alignment_error_o),
		.snapshot_cta_idle_o(snapshot_cta_idle_o),
		.snapshot_brightness_worker_idle_o(
			snapshot_brightness_worker_idle_o),
		.snapshot_brightness_allocator_idle_o(
			snapshot_brightness_allocator_idle_o),
		.snapshot_brightness_raster_pipe_empty_o(
			snapshot_brightness_raster_pipe_empty_o),
		.snapshot_framebuffer_capture_idle_o(
			snapshot_framebuffer_capture_idle_o),
		.snapshot_scan_converter_pipe_empty_o(
			snapshot_scan_converter_pipe_empty_o),
		.snapshot_event_coherent_o(snapshot_event_coherent_o),
		.brightness_worker_owner_active_o(
			brightness_worker_owner_active_o),
		.brightness_allocator_owner_active_o(
			brightness_allocator_owner_active_o),
		.brightness_result_owner_active_o(
			brightness_result_owner_active_o),
		.brightness_raster_read_owner_active_o(
			brightness_raster_read_owner_active_o),
		.scanout_owner_active_o(scanout_owner_active_o),
		.displayed_fb_latched_o(displayed_fb_latched_o),
		.vrm_observer_enable_o(vrm_observer_enable_o),
		.vrm_observer_addr_o(vrm_observer_addr_o),
		.vrm_observer_rvalid_o(vrm_observer_rvalid_o),
		.vrm_observer_rdata_o(vrm_observer_rdata_o),
		.framebuffer_collision_precondition_violation_o(
			framebuffer_collision_precondition_violation_o),
		.observer_alignment_error_o(observer_alignment_error_o),
		.pixel_ce_o(pixel_ce_o),
		.raster_x_o(raster_x_o),
		.raster_y_o(raster_y_o),
		.video_hblank_o(video_hblank_o),
		.video_vblank_o(video_vblank_o),
		.video_hsync_o(video_hsync_o),
		.video_vsync_o(video_vsync_o),
		.raw_pixel_left_o(raw_pixel_left_o),
		.raw_pixel_right_o(raw_pixel_right_o),
		.video_luma_left_o(video_luma_left_o),
		.video_luma_right_o(video_luma_right_o),
		.host_busy_o(host_busy_o),
		.host_local_active_o(host_local_active_o),
		.vram_cpu_timing_busy_o(vram_cpu_timing_busy_o),
		.vram_store_busy_o(vram_store_busy_o),
		.vram_inner_offer_held_o(vram_inner_offer_held_o),
		.vram_read_pending_o(vram_read_pending_o),
		.dram_cpu_timing_busy_o(dram_cpu_timing_busy_o),
		.dram_store_busy_o(dram_store_busy_o),
		.dram_inner_offer_held_o(dram_inner_offer_held_o),
		.dram_read_pending_o(dram_read_pending_o),
		.cta_dram_accept_o(cta_dram_accept_o),
		.cta_dram_resp_valid_o(cta_dram_resp_valid_o)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	vip_xp_storage_subsystem
	#(
		.AFFINE_STREAM_ENABLE(AFFINE_STREAM_ENABLE)
	)
	u_xp_storage_subsystem
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
		.game_start_fire_i(native_game_start_fire_o),
		.xp_enable_i(xp_enable_o),
		.xprst_i(xprst_o),
		.xp_sbcmp_i(xp_sbcmp_o),
		.bkcol_register_i(bkcol_register_o),
		.bkcol_active_i(bkcol_active_o),
		.dram_req_o(xp_dram_req_w),
		.dram_write_o(xp_dram_write_w),
		.dram_addr_o(xp_dram_addr_w),
		.dram_wdata_o(xp_dram_wdata_w),
		.dram_byte_enable_o(xp_dram_byte_enable_w),
		.dram_accept_i(xp_dram_accept_w),
		.dram_resp_valid_i(xp_dram_resp_valid_w),
		.dram_resp_data_i(xp_dram_resp_data_w),
		.vrm_req_o(xp_vrm_req_w),
		.vrm_write_o(xp_vrm_write_w),
		.vrm_addr_o(xp_vrm_addr_w),
		.vrm_wdata_o(xp_vrm_wdata_w),
		.vrm_byte_enable_o(xp_vrm_byte_enable_w),
		.vrm_accept_i(xp_vrm_accept_w),
		.engine_cmd_valid_o(xp_engine_cmd_valid_w),
		.engine_cmd_ready_i(xp_engine_cmd_ready_w),
		.engine_cmd_kind_o(xp_engine_cmd_kind_w),
		.engine_cmd_strip_o(xp_engine_cmd_strip_w),
		.engine_cmd_world_o(xp_engine_cmd_world_w),
		.engine_cmd_descriptor_o(xp_engine_cmd_descriptor_w),
		.engine_cmd_first_visit_o(xp_engine_cmd_first_visit_w),
		.engine_done_i(xp_engine_done_w),
		.engine_cleanup_busy_i(engine_cleanup_busy_i),
		.engine_abort_o(xp_engine_abort_w),
		.producer_valid_i(producer_valid_i),
		.producer_ready_o(producer_ready_o),
		.producer_column_i(producer_column_i),
		.producer_left_enable_i(producer_left_enable_i),
		.producer_left_preserve_mask_i(
			producer_left_preserve_mask_i),
		.producer_left_value_i(producer_left_value_i),
		.producer_right_enable_i(producer_right_enable_i),
		.producer_right_preserve_mask_i(
			producer_right_preserve_mask_i),
		.producer_right_value_i(producer_right_value_i),
		.producer_done_o(producer_done_o),
		.row_producer_valid_i(row_producer_valid_i),
		.row_producer_ready_o(row_producer_ready_o),
		.row_producer_row_i(row_producer_row_i),
		.row_producer_left_base_x_i(row_producer_left_base_x_i),
		.row_producer_left_enable_i(row_producer_left_enable_i),
		.row_producer_left_active_i(row_producer_left_active_i),
		.row_producer_left_opaque_i(row_producer_left_opaque_i),
		.row_producer_left_values_i(row_producer_left_values_i),
		.row_producer_right_base_x_i(row_producer_right_base_x_i),
		.row_producer_right_enable_i(row_producer_right_enable_i),
		.row_producer_right_active_i(row_producer_right_active_i),
		.row_producer_right_opaque_i(row_producer_right_opaque_i),
		.row_producer_right_values_i(row_producer_right_values_i),
		.row_producer_done_o(row_producer_done_o),
		.affine_abort_i(affine_abort_i),
		.affine_prepare_valid_i(affine_prepare_valid_i),
		.affine_prepare_ready_o(affine_prepare_ready_o),
		.affine_prepare_accept_o(affine_prepare_accept_o),
		.affine_prepare_row_i(affine_prepare_row_i),
		.affine_prepare_left_base_x_i(affine_prepare_left_base_x_i),
		.affine_prepare_left_enable_i(affine_prepare_left_enable_i),
		.affine_prepare_right_base_x_i(affine_prepare_right_base_x_i),
		.affine_prepare_right_enable_i(affine_prepare_right_enable_i),
		.affine_commit_valid_i(affine_commit_valid_i),
		.affine_commit_ready_o(affine_commit_ready_o),
		.affine_commit_accept_o(affine_commit_accept_o),
		.affine_commit_left_active_i(affine_commit_left_active_i),
		.affine_commit_left_opaque_i(affine_commit_left_opaque_i),
		.affine_commit_left_values_i(affine_commit_left_values_i),
		.affine_commit_right_active_i(affine_commit_right_active_i),
		.affine_commit_right_opaque_i(affine_commit_right_opaque_i),
		.affine_commit_right_values_i(affine_commit_right_values_i),
		.affine_active_o(affine_active_o),
		.affine_quiescent_o(affine_quiescent_o),
		.affine_done_o(affine_done_o),
		.draw_start_fire_o(draw_start_fire_o),
		.first_group_done_fire_o(first_group_done_fire_o),
		.sb_hit_fire_o(sb_hit_fire_o),
		.xp_end_fire_o(xp_end_fire_o),
		.timeerr_fire_o(timeerr_fire_o),
		.drawing_o(drawing_o),
		.xp_busy_o(xp_busy_o),
		.xp_strip_o(xp_strip_o),
		.xp_sbcount_o(xp_sbcount_o),
		.xp_sbout_o(xp_sbout_o),
		.xp_overtime_o(xp_overtime_o),
		.displayed_fb_o(displayed_fb_o),
		.active_draw_valid_o(active_draw_valid_o),
		.active_draw_target_o(active_draw_target_o),
		.completed_pending_valid_o(completed_pending_valid_o),
		.completed_pending_target_o(completed_pending_target_o),
		.display_swap_o(display_swap_o),
		.completion_commit_o(completion_commit_o),
		.snapshot_valid_o(snapshot_valid_o),
		.snapshot_accepted_count_o(snapshot_accepted_count_o),
		.snapshot_response_count_o(snapshot_response_count_o),
	`ifndef SYNTHESIS
		.snapshot_stale_response_discarded_o(
			snapshot_stale_response_discarded_o),
		.snapshot_discarded_count_o(snapshot_discarded_count_o),
	`endif
		.loadout_accept_count_o(loadout_accept_count_o),
		.coordinator_state_o(coordinator_state_o),
		.coordinator_world_o(coordinator_world_o),
		.setup_remaining_o(setup_remaining_o),
		.service_remaining_o(service_remaining_o),
		.world_interval_elapsed_o(world_interval_elapsed_o),
		.world_interval_target_o(world_interval_target_o),
		.recovery_remaining_o(recovery_remaining_o),
		.strip_start_fire_o(strip_start_fire_o),
		.strip_commit_fire_o(strip_commit_fire_o),
		.completion_gclk_tie_o(completion_gclk_tie_o),
		.classification_mismatch_o(classification_mismatch_o),
		.peripheral_busy_o(peripheral_busy_o),
		.descriptor_snapshot_owner_active_o(
			descriptor_snapshot_owner_active_o),
		.descriptor_consumer_owner_active_o(
			descriptor_consumer_owner_active_o),
		.strip_transport_owner_active_o(
			strip_transport_owner_active_o),
		.affine_loadout_owner_active_o(affine_loadout_owner_active_o),
		.snapshot_response_owner_error_o(
			snapshot_response_owner_error_o),
		.ownership_mismatch_o(ownership_mismatch_o)
	);

endmodule

// XP-domain memory router shared by the render and display paths.


// Two-client router for one XP memory channel.
//
// The primary client reads and writes; the Normal client only reads. A blocked
// offer stays selected until accepted. Abort drops an offer and drains accepted
// stale reads.

module vip_xp_memory_router
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire        normal_abort_i,

	input  wire        primary_req_i,
	input  wire        primary_write_i,
	input  wire [15:0] primary_addr_i,
	input  wire [15:0] primary_wdata_i,
	input  wire [1:0]  primary_byte_enable_i,
	output wire        primary_accept_o,
	output wire        primary_resp_valid_o,
	output wire [15:0] primary_resp_data_o,

	input  wire        normal_req_i,
	input  wire [15:0] normal_addr_i,
	output wire        normal_accept_o,
	output wire        normal_resp_valid_o,
	output wire [15:0] normal_resp_data_o,

	output wire        downstream_req_o,
	output wire        downstream_write_o,
	output wire [15:0] downstream_addr_o,
	output wire [15:0] downstream_wdata_o,
	output wire [1:0]  downstream_byte_enable_o,
	input  wire        downstream_accept_i,
	input  wire        downstream_resp_valid_i,
	input  wire [15:0] downstream_resp_data_i,

	output wire        offer_locked_o,
	output wire        read_pending_o,
	output wire        normal_cleanup_busy_o,
	output reg         stale_response_discarded_o,
	output reg         unexpected_response_o,
	output reg         response_capture_overflow_o,
	output reg         read_owner_overlap_o
);

	reg        offer_locked_q;
	reg        offer_owner_normal_q;
	reg        offer_req_q;
	reg        offer_write_q;
	reg [15:0] offer_addr_q;
	reg [15:0] offer_wdata_q;
	reg [1:0]  offer_byte_enable_q;

	reg        response_pending_q;
	reg        response_owner_normal_q;
	reg        response_stale_q;
	reg        response_capture_valid_q;
	reg [15:0] response_capture_data_q;

	wire live_owner_normal_w = !primary_req_i && normal_req_i;
	wire live_req_w = primary_req_i || (normal_req_i && !normal_abort_i);
	wire live_write_w = live_owner_normal_w ? 1'b0 : primary_write_i;
	wire [15:0] live_addr_w = live_owner_normal_w ?
		normal_addr_i : primary_addr_i;
	wire [15:0] live_wdata_w = live_owner_normal_w ?
		16'd0 : primary_wdata_i;
	wire [1:0] live_byte_enable_w = live_owner_normal_w ?
		2'b11 : primary_byte_enable_i;

	wire routed_owner_normal_w = offer_locked_q ?
		offer_owner_normal_q : live_owner_normal_w;
	wire routed_req_w = offer_locked_q ?
		(offer_req_q && !(offer_owner_normal_q && normal_abort_i)) :
		live_req_w;
	wire routed_write_w = offer_locked_q ? offer_write_q : live_write_w;
	wire [15:0] routed_addr_w = offer_locked_q ?
		offer_addr_q : live_addr_w;
	wire [15:0] routed_wdata_w = offer_locked_q ?
		offer_wdata_q : live_wdata_w;
	wire [1:0] routed_byte_enable_w = offer_locked_q ?
		offer_byte_enable_q : live_byte_enable_w;

	wire response_available_w = response_capture_valid_q ||
		downstream_resp_valid_i;
	wire [15:0] response_data_w = response_capture_valid_q ?
		response_capture_data_q : downstream_resp_data_i;
	wire response_aborted_w = response_stale_q ||
		(normal_abort_i && response_owner_normal_q);
	wire response_fire_w = ce_i && response_available_w &&
		response_pending_q;
	wire can_offer_w = !response_pending_q || response_available_w;

	assign downstream_req_o = !reset_i && routed_req_w && can_offer_w;
	assign downstream_write_o = routed_write_w;
	assign downstream_addr_o = routed_addr_w;
	assign downstream_wdata_o = routed_wdata_w;
	assign downstream_byte_enable_o = routed_byte_enable_w;

	wire downstream_accept_fire_w = ce_i && downstream_req_o &&
		downstream_accept_i;
	wire read_accept_fire_w = downstream_accept_fire_w &&
		!downstream_write_o;

	assign primary_accept_o = downstream_accept_fire_w &&
		!routed_owner_normal_w;
	assign normal_accept_o = downstream_accept_fire_w &&
		routed_owner_normal_w;
	assign primary_resp_valid_o = response_fire_w &&
		!response_owner_normal_q && !response_aborted_w;
	assign normal_resp_valid_o = response_fire_w &&
		response_owner_normal_q && !response_aborted_w;
	assign primary_resp_data_o = primary_resp_valid_o ?
		response_data_w : 16'd0;
	assign normal_resp_data_o = normal_resp_valid_o ?
		response_data_w : 16'd0;

	assign offer_locked_o = offer_locked_q;
	assign read_pending_o = response_pending_q;
	assign normal_cleanup_busy_o = response_pending_q &&
		response_owner_normal_q && response_aborted_w;

	always @(posedge clk_i) begin
		if (reset_i) begin
			offer_locked_q <= 1'b0;
			offer_owner_normal_q <= 1'b0;
			offer_req_q <= 1'b0;
			offer_write_q <= 1'b0;
			offer_addr_q <= 16'd0;
			offer_wdata_q <= 16'd0;
			offer_byte_enable_q <= 2'b00;
			response_pending_q <= 1'b0;
			response_owner_normal_q <= 1'b0;
			response_stale_q <= 1'b0;
			response_capture_valid_q <= 1'b0;
			response_capture_data_q <= 16'd0;
			stale_response_discarded_o <= 1'b0;
			unexpected_response_o <= 1'b0;
			response_capture_overflow_o <= 1'b0;
			read_owner_overlap_o <= 1'b0;
		end else begin
			stale_response_discarded_o <= 1'b0;

			// Save a response that arrives while CE is paused.
			if (!ce_i && downstream_resp_valid_i) begin
				if (!response_pending_q) begin
					unexpected_response_o <= 1'b1;
				end else if (response_capture_valid_q) begin
					response_capture_overflow_o <= 1'b1;
				end else begin
					response_capture_valid_q <= 1'b1;
					response_capture_data_q <= downstream_resp_data_i;
				end
			end

			// Raw abort cancels offers but accepted reads still drain.
			if (normal_abort_i) begin
				if (offer_locked_q && offer_owner_normal_q) begin
					offer_locked_q <= 1'b0;
					offer_req_q <= 1'b0;
				end
				if (response_pending_q && response_owner_normal_q) begin
					response_stale_q <= 1'b1;
				end
			end

			if (ce_i) begin
				if (response_available_w && !response_pending_q) begin
					unexpected_response_o <= 1'b1;
				end
				if (response_capture_valid_q &&
					downstream_resp_valid_i) begin
					response_capture_overflow_o <= 1'b1;
				end

				if (response_fire_w) begin
					response_pending_q <= 1'b0;
					response_stale_q <= 1'b0;
					response_capture_valid_q <= 1'b0;
					if (response_aborted_w) begin
						stale_response_discarded_o <= 1'b1;
					end
				end

				if (read_accept_fire_w) begin
					if (response_pending_q && !response_fire_w) begin
						read_owner_overlap_o <= 1'b1;
					end
					response_pending_q <= 1'b1;
					response_owner_normal_q <=
						routed_owner_normal_w;
					response_stale_q <= 1'b0;
				end

				if (offer_locked_q) begin
					if (downstream_accept_fire_w) begin
						offer_locked_q <= 1'b0;
						offer_req_q <= 1'b0;
					end
				end else if (routed_req_w &&
					!downstream_accept_fire_w) begin
					offer_locked_q <= 1'b1;
					offer_owner_normal_q <= routed_owner_normal_w;
					offer_req_q <= 1'b1;
					offer_write_q <= routed_write_w;
					offer_addr_q <= routed_addr_w;
					offer_wdata_q <= routed_wdata_w;
					offer_byte_enable_q <= routed_byte_enable_w;
				end
			end
		end
	end

endmodule

// Native display timing, CTA sequencing, brightness, and scanout.
//
// The native DP clock sets eye timing. CTA uses the DRAM DP port, while scanout
// uses only the VRM observer port.
//
// Combinational events serve same-edge logic; registered strobes serve diagnostics.
//
// Native brightness ends at raw exposure counts. The luma lookup that maps
// them to display levels is MiSTer presentation logic, not Virtual Boy
// behavior. Clients must avoid RAM collisions.

module vip_display_subsystem
#(
	parameter integer EVENT_SET_WINS = 1,
	parameter integer WRITE_FIRST_ON_BOUNDARY = 0,
	parameter [7:0] LOCAL_TOTAL_CE = 8'd2,
	parameter [7:0] VRM_WRITE_TOTAL_CE = 8'd3,
	parameter [7:0] VRM_READ_TOTAL_CE = 8'd7,
	parameter [7:0] DRAM_WRITE_TOTAL_CE = 8'd3,
	parameter [7:0] DRAM_READ_TOTAL_CE = 8'd7,
	parameter [15:0] H_VISIBLE = 16'd384,
	parameter [15:0] H_TOTAL = 16'd1280,
	parameter [15:0] H_SYNC_BEG = 16'd1056,
	parameter [15:0] H_SYNC_END = 16'd1152,
	parameter [15:0] V_VISIBLE = 16'd224,
	parameter [15:0] V_TOTAL = 16'd312,
	parameter [15:0] V_SYNC_BEG = 16'd289,
	parameter [15:0] V_SYNC_END = 16'd292,
	parameter [18:0] NATIVE_LEFT_START_PRE = 19'd59999,
	parameter CTA_TIMED_EYE_END_ENABLE = 1'b0,
	parameter NATIVE_FRAMEBUFFER_CAPTURE_ENABLE = 1'b0
)
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire        phi1_i,
	input  wire [5:0]  savestate_state_addr_i,
	input  wire [63:0] savestate_state_wdata_i,
	input  wire        savestate_state_wren_i,
	input  wire        savestate_vram_mem_active_i,
	input  wire        savestate_dram_mem_active_i,
	input  wire [16:0] savestate_mem_addr_i,
	input  wire        savestate_mem_rden_i,
	input  wire        savestate_mem_wren_i,
	input  wire [7:0]  savestate_mem_wdata_i,
	output wire [7:0]  savestate_vram_mem_rdata_o,
	output wire [7:0]  savestate_dram_mem_rdata_o,
	output wire [36:0] savestate_scan_state_o,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire        sim_snapshot_restore_commit_i,
	input  wire        sim_snapshot_restore_apply_i,
	input  wire [3647:0] sim_snapshot_restore_packet_i,
`endif
`endif

	// Presentation stages do not affect native timing or arbitration.
	input  wire        video_ce_i,
	input  wire        video_phi1_i,
	input  wire        savestate_boundary_stop_i,

	// Public VIP host bus.
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

	// Optional framebuffer DP client.
	input  wire        vram_dp_req_i,
	input  wire        vram_dp_write_i,
	input  wire [15:0] vram_dp_addr_i,
	input  wire [15:0] vram_dp_wdata_i,
	input  wire [1:0]  vram_dp_byte_enable_i,
	output wire        vram_dp_accept_o,
	output wire        vram_dp_resp_valid_o,
	output wire [15:0] vram_dp_resp_data_o,

	// Separate external XP channels for VRM and DRAM.
	input  wire        vram_xp_req_i,
	input  wire        vram_xp_write_i,
	input  wire [15:0] vram_xp_addr_i,
	input  wire [15:0] vram_xp_wdata_i,
	input  wire [1:0]  vram_xp_byte_enable_i,
	output wire        vram_xp_accept_o,
	output wire        vram_xp_resp_valid_o,
	output wire [15:0] vram_xp_resp_data_o,
	input  wire        dram_xp_req_i,
	input  wire        dram_xp_write_i,
	input  wire [15:0] dram_xp_addr_i,
	input  wire [15:0] dram_xp_wdata_i,
	input  wire [1:0]  dram_xp_byte_enable_i,
	output wire        dram_xp_accept_o,
	output wire        dram_xp_resp_valid_o,
	output wire [15:0] dram_xp_resp_data_o,

	// Raw-clocked DRAM observer.
	input  wire        dram_observer_enable_i,
	input  wire [15:0] dram_observer_addr_i,
	output wire [15:0] dram_observer_rdata_o,
	output wire        dram_observer_rvalid_o,

	// Accepted-transaction traces for both stores.
	output wire        vram_physical_accept_o,
	output wire        vram_physical_write_o,
	output wire [1:0]  vram_physical_owner_o,
	output wire [15:0] vram_physical_addr_o,
	output wire [15:0] vram_physical_wdata_o,
	output wire [1:0]  vram_physical_byte_enable_o,
	output wire        vram_physical_resp_valid_o,
	output wire [1:0]  vram_physical_resp_owner_o,
	output wire        dram_physical_accept_o,
	output wire        dram_physical_write_o,
	output wire [1:0]  dram_physical_owner_o,
	output wire [15:0] dram_physical_addr_o,
	output wire [15:0] dram_physical_wdata_o,
	output wire [1:0]  dram_physical_byte_enable_o,
	output wire        dram_physical_resp_valid_o,
	output wire [1:0]  dram_physical_resp_owner_o,

	// Native status and XP control inputs.
	input  wire        dp_scan_ready_i,
	input  wire        xp_sbout_i,
	input  wire [4:0]  xp_sbcount_i,
	input  wire        xp_overtime_i,
	input  wire [1:0]  xp_busy_i,
	input  wire        scanerr_event_i,
	input  wire [7:0]  cta_left_servo_i,
	input  wire [7:0]  cta_right_servo_i,
	input  wire        xp_draw_start_i,
	input  wire        xp_first_group_done_i,
	input  wire        xp_sb_hit_fire_i,
	input  wire        xp_end_fire_i,
	input  wire        xp_timeerr_fire_i,

	// One held token represents each four-column group.
	input  wire        column_group_valid_i,
	output wire        column_group_ready_o,
	// Timed mode ends an eye after the last CTC period; fixed mode uses native timing.
	input  wire        cta_timed_eye_end_i,
	input  wire        cta_timed_eye_end_eye_i,

	// Downstream framebuffer and presentation controls.
	input  wire        displayed_fb_i,
	input  wire        framebuffer_handoff_fire_i,
	input  wire        framebuffer_handoff_target_i,
	input  wire        completed_framebuffer_collision_free_i,
	input  wire [1:0]  presentation_mode_i,
	input  wire        flat_eye_i,
	input  wire        side_by_side_i,
	input  wire        compat_60hz_i,
	input  wire        shutter_i,
	input  wire        presentation_hlg_i,
	input  wire        brightness_table_legacy_sdr_i,
	input  wire        brightness_table_download_i,
	input  wire        brightness_table_write_i,
	input  wire [9:0]  brightness_table_addr_i,
	input  wire [15:0] brightness_table_data_i,
	input  wire        brightness_cache_collision_free_i,

	// Register and event state.
	output wire [15:0] event_o,
	output wire [15:0] int_pending_o,
	output wire [15:0] int_enable_o,
	output wire        dprst_o,
	output wire        xprst_o,
	output wire        dp_lock_o,
	output wire        dp_synce_program_o,
	output wire        dp_synce_active_o,
	output wire        dp_refresh_o,
	output wire        dp_display_program_o,
	output wire        dp_display_active_o,
	output wire [4:0]  xp_sbcmp_o,
	output wire        xp_enable_o,
	output wire [1:0]  bkcol_register_o,
	output wire [1:0]  bkcol_active_o,
	output wire [31:0] brightness_register_o,
	output wire [31:0] brightness_active_o,
	output wire [3:0]  frmcyc_register_o,
	output wire [3:0]  frmcyc_register_active_o,
	output wire [15:0] cta_o,
	output wire [39:0] spt_register_o,
	output wire [39:0] spt_active_o,
	output wire [31:0] gplt_register_o,
	output wire [31:0] gplt_active_o,
	output wire [31:0] jplt_register_o,
	output wire [31:0] jplt_active_o,
	output wire        bkcol_pending_o,
	output wire        bkcol_wait_first_group_o,
	output wire [6:0]  event_history_o,

	// Native timing and boundary events.
	output wire [18:0] native_frame_cycle_o,
	output wire        native_fclk_o,
	output wire        native_waiting_for_fclk_o,
	output wire        native_left_busy_o,
	output wire        native_right_busy_o,
	output wire        native_frame_start_o,
	output wire        native_left_start_o,
	output wire        native_left_end_o,
	output wire        native_right_start_o,
	output wire        native_right_end_o,
	output wire        native_gclk_rise_o,
	output wire        native_game_start_o,
	output wire        native_frame_start_fire_o,
	output wire        native_left_start_fire_o,
	output wire        native_left_end_fire_o,
	output wire        native_right_start_fire_o,
	output wire        native_right_end_fire_o,
	output wire        native_gclk_rise_fire_o,
	output wire        native_game_start_fire_o,
	output wire [3:0]  native_frmcyc_active_o,
	output wire [3:0]  native_game_frame_wait_o,

	// CTA state and diagnostics.
	output wire        ctc_valid_o,
	output wire [15:0] ctc_data_o,
	output wire        ctc_eye_o,
	output wire [6:0]  ctc_ordinal_o,
	output wire [7:0]  ctc_index_o,
	output wire        cta_field_complete_o,
	output wire        cta_field_complete_eye_o,
	output wire        cta_field_incomplete_o,
	output wire        cta_field_overlap_o,
	output wire        cta_field_active_o,
	output wire        cta_transaction_active_o,
	output wire [6:0]  cta_group_count_o,
	output wire [6:0]  cta_request_count_o,
	output wire [6:0]  cta_response_count_o,

	// Native exposure and presentation-cache state.
	output wire        brightness_busy_o,
	output wire        brightness_result_valid_o,
	output wire        brightness_result_eye_o,
	output wire [6:0]  brightness_result_group_o,
	output wire [10:0] brightness_result_exposure_1_o,
	output wire [10:0] brightness_result_exposure_2_o,
	output wire [10:0] brightness_result_exposure_3_o,
	output wire        brightness_result_overrun_o,
	output wire        brightness_result_short_column_o,
	output wire [7:0]  brightness_cycle_count_o,
	output wire        brightness_cache_write_candidate_o,
	output wire        brightness_cache_write_o,
	output wire        brightness_cache_write_blocked_o,
	output wire [31:0] brightness_cache_levels_o,
	output wire        brightness_generation_build_active_o,
	output wire        brightness_generation_pending_o,
	output wire        brightness_generation_display_valid_o,
	output wire [7:0]  brightness_generation_display_o,
	output wire        brightness_generation_swap_o,
	output wire        brightness_alignment_error_o,

	// Stopped-state status for simulation snapshots.
	output wire        snapshot_cta_idle_o,
	output wire        snapshot_brightness_worker_idle_o,
	output wire        snapshot_brightness_allocator_idle_o,
	output wire        snapshot_brightness_raster_pipe_empty_o,
	output wire        snapshot_framebuffer_capture_idle_o,
	output wire        snapshot_scan_converter_pipe_empty_o,
	output wire        snapshot_event_coherent_o,
	output wire        brightness_worker_owner_active_o,
	output wire        brightness_allocator_owner_active_o,
	output wire        brightness_result_owner_active_o,
	output wire        brightness_raster_read_owner_active_o,
	output wire        scanout_owner_active_o,

	// MiSTer raster and collision diagnostics.
	output wire        displayed_fb_latched_o,
	output wire        vrm_observer_enable_o,
	output wire [15:0] vrm_observer_addr_o,
	output wire        vrm_observer_rvalid_o,
	output wire [15:0] vrm_observer_rdata_o,
	output wire        framebuffer_collision_precondition_violation_o,
	output wire        observer_alignment_error_o,
	output wire        pixel_ce_o,
	output wire [15:0] raster_x_o,
	output wire [15:0] raster_y_o,
	output wire        video_hblank_o,
	output wire        video_vblank_o,
	output wire        video_hsync_o,
	output wire        video_vsync_o,
	output wire [1:0]  raw_pixel_left_o,
	output wire [1:0]  raw_pixel_right_o,
	output wire [7:0]  video_luma_left_o,
	output wire [7:0]  video_luma_right_o,

	// Composition health.
	output wire        host_busy_o,
	output wire        host_local_active_o,
	output wire        vram_cpu_timing_busy_o,
	output wire        vram_store_busy_o,
	output wire        vram_inner_offer_held_o,
	output wire        vram_read_pending_o,
	output wire        dram_cpu_timing_busy_o,
	output wire        dram_store_busy_o,
	output wire        dram_inner_offer_held_o,
	output wire        dram_read_pending_o,
	output wire        cta_dram_accept_o,
	output wire        cta_dram_resp_valid_o
);

	localparam CAPTURE_ENABLED =
		(NATIVE_FRAMEBUFFER_CAPTURE_ENABLE != 0);

	wire        cta_dram_req_w;
	wire [15:0] cta_dram_addr_w;
	wire        cta_dram_accept_w;
	wire        cta_dram_resp_valid_w;
	wire [15:0] cta_dram_resp_data_w;
	wire        cta_column_ready_w;
	wire        brightness_job_ready_w;
	wire        brightness_worker_job_ready_w;
	wire        brightness_worker_quiescent_w;
	wire        brightness_result_valid_w;
	wire        brightness_result_eye_w;
	wire [6:0]  brightness_result_group_w;
	wire [10:0] brightness_exposure_1_w;
	wire [10:0] brightness_exposure_2_w;
	wire [10:0] brightness_exposure_3_w;
	wire        brightness_overrun_w;
	wire        brightness_short_w;
	wire [7:0]  brightness_cycle_count_w;
	wire [7:0]  cta_left_start_w;
	wire [7:0]  cta_right_start_w;
	wire [31:0] presentation_levels_w;
	wire        presentation_candidate_w;
	wire        presentation_transfer_ready_w;
	wire        presentation_transfer_busy_w;
	wire        presentation_result_valid_w;
	wire        presentation_result_eye_w;
	wire [6:0]  presentation_result_group_w;
	reg  [31:0] presentation_brightness_frame_q;
	reg         presentation_hlg_frame_q;
	reg         presentation_legacy_sdr_frame_q;
	wire        presentation_brightness_frame_start_w;
	wire [31:0] presentation_brightness_job_w;
	reg  [7:0]  brightness_generation_next_q;
	reg  [7:0]  brightness_generation_begin_tag_q;
	reg         brightness_generation_begin_pending_q;
	wire        brightness_generation_start_w;
	wire        brightness_generation_write_accept_w;
	wire        brightness_generation_build_active_w;
	wire [7:0]  brightness_generation_build_tag_w;
	wire        brightness_generation_build_complete_w;
	wire        brightness_generation_pending_w;
	wire        brightness_generation_display_valid_w;
	wire [7:0]  brightness_generation_display_w;
	wire        brightness_generation_swap_w;
	wire        brightness_raster_boundary_w;
	wire        brightness_raster_read_enable_w;
	wire [6:0]  brightness_raster_read_group_w;
	wire        brightness_raster_response_valid_w;
	wire        brightness_raster_pipeline_empty_w;
	wire        brightness_raster_generation_valid_w;
	wire [31:0] brightness_raster_left_levels_w;
	wire [31:0] brightness_raster_right_levels_w;
	wire        scan_converter_pipeline_empty_w;
	wire        native_capture_group_ready_w /* verilator public_flat_rd */;
	wire        native_capture_vram_req_w;
	wire [15:0] native_capture_vram_addr_w;
	wire        native_capture_vram_accept_w;
	wire        native_capture_vram_resp_valid_w;
	wire [15:0] native_capture_vram_resp_data_w;
	wire        native_capture_pending_w;
	wire        native_capture_build_active_w;
	wire        native_capture_transfer_owner_w;
	wire        native_capture_raster_pipeline_empty_w;
	wire        native_capture_raster_response_valid_w;
	// public_flat_rd: read hierarchically by VirtualBoySim.cpp.
	wire        native_capture_raster_generation_valid_w
		/* verilator public_flat_rd */;
	wire [15:0] native_capture_raster_data_w;
	wire        native_capture_protocol_error_w
		/* verilator public_flat_rd */;
	wire        native_capture_unexpected_response_w
		/* verilator public_flat_rd */;
	wire        presentation_raster_commit_w;
	wire        scanout_read_enable_w;
	wire [15:0] scanout_read_addr_w;
	wire        physical_vram_observer_rvalid_w;
	wire [15:0] physical_vram_observer_rdata_w;
	wire        internal_vram_dp_accept_w;
	wire        internal_vram_dp_resp_valid_w;
	wire [15:0] internal_vram_dp_resp_data_w;
	wire        event_levels_coherent_w;
	wire [3:0]  native_dp_busy_w;
	wire        column_group_fire_w;
	wire        display_transfer_enable_w;
	wire        scanout_display_enable_w;
	wire        native_capture_source_fb_w;
	reg         presentation_epoch_valid_q;

`ifndef SYNTHESIS
	// Optional brightness trace tagged with its framebuffer generation.
	reg         sim_brightness_trace_enable_q;
	integer     sim_brightness_trace_start_v;
	integer     sim_brightness_trace_end_v;
	reg [31:0]  sim_brightness_trace_frame_q;
	reg         sim_brightness_trace_capture_build_prev_q;
	reg         sim_brightness_trace_capture_pending_prev_q;
	reg         sim_brightness_trace_luma_build_prev_q;
	reg         sim_brightness_trace_luma_pending_prev_q;
	reg [31:0]  sim_brightness_trace_capture_build_tag_q;
	reg [31:0]  sim_brightness_trace_capture_pending_tag_q;
	reg [31:0]  sim_brightness_trace_luma_build_tag_q;
	reg [31:0]  sim_brightness_trace_luma_pending_tag_q;
	wire        sim_brightness_trace_in_range_w =
		sim_brightness_trace_enable_q &&
		(sim_brightness_trace_frame_q >= sim_brightness_trace_start_v) &&
		(sim_brightness_trace_frame_q <= sim_brightness_trace_end_v);
`endif

	// Accept a new CTA group only after the prior CTC result enters the worker.
	// Shared by column_group_ready_o and the sequencer's qualified valid.
	wire column_group_gate_w =
		brightness_job_ready_w && !ctc_valid_o &&
		(!CAPTURE_ENABLED ||
		 native_capture_group_ready_w);
	assign column_group_ready_o = cta_column_ready_w &&
		column_group_gate_w;
	assign column_group_fire_w = column_group_valid_i &&
		column_group_ready_o;
	assign cta_left_start_w = dp_lock_o ? cta_o[7:0] : cta_left_servo_i;
	assign cta_right_start_w = dp_lock_o ? cta_o[15:8] : cta_right_servo_i;
	assign native_dp_busy_w = displayed_fb_i ?
		{native_right_busy_o, native_left_busy_o, 2'b00} :
		{2'b00, native_right_busy_o, native_left_busy_o};
	// Eye transfer needs both display and scanner sync enabled.
	assign display_transfer_enable_w =
		dp_display_active_o && dp_synce_active_o;
	assign scanout_display_enable_w = display_transfer_enable_w &&
		presentation_epoch_valid_q;
	assign native_capture_source_fb_w = framebuffer_handoff_fire_i ?
		framebuffer_handoff_target_i : displayed_fb_i;
	assign presentation_raster_commit_w = brightness_raster_boundary_w &&
		(!CAPTURE_ENABLED ||
		 (native_capture_pending_w && brightness_generation_pending_w));

`ifndef SYNTHESIS
	initial begin
		sim_brightness_trace_enable_q =
			$test$plusargs("vip_brightness_trace");
		if (!$value$plusargs("vip_brightness_trace_start=%d",
			sim_brightness_trace_start_v)) begin
			sim_brightness_trace_start_v = 0;
		end
		if (!$value$plusargs("vip_brightness_trace_end=%d",
			sim_brightness_trace_end_v)) begin
			sim_brightness_trace_end_v = 32'h7fff_ffff;
		end
	end

	always @(posedge clk_i) begin
		if (reset_i) begin
			sim_brightness_trace_frame_q <= 32'd0;
			sim_brightness_trace_capture_build_prev_q <= 1'b0;
			sim_brightness_trace_capture_pending_prev_q <= 1'b0;
			sim_brightness_trace_luma_build_prev_q <= 1'b0;
			sim_brightness_trace_luma_pending_prev_q <= 1'b0;
			sim_brightness_trace_capture_build_tag_q <= 32'd0;
			sim_brightness_trace_capture_pending_tag_q <= 32'd0;
			sim_brightness_trace_luma_build_tag_q <= 32'd0;
			sim_brightness_trace_luma_pending_tag_q <= 32'd0;
		end else begin
			if (ce_i && native_frame_start_fire_o) begin
				sim_brightness_trace_frame_q <=
					sim_brightness_trace_frame_q + 32'd1;
			end

			sim_brightness_trace_capture_build_prev_q <=
				native_capture_build_active_w;
			sim_brightness_trace_capture_pending_prev_q <=
				native_capture_pending_w;
			sim_brightness_trace_luma_build_prev_q <=
				brightness_generation_build_active_w;
			sim_brightness_trace_luma_pending_prev_q <=
				brightness_generation_pending_w;

			if (native_capture_build_active_w &&
				!sim_brightness_trace_capture_build_prev_q) begin
				sim_brightness_trace_capture_build_tag_q <=
					sim_brightness_trace_frame_q;
			end
			if (native_capture_pending_w &&
				!sim_brightness_trace_capture_pending_prev_q) begin
				sim_brightness_trace_capture_pending_tag_q <=
					sim_brightness_trace_capture_build_tag_q;
			end
			if (brightness_generation_build_active_w &&
				!sim_brightness_trace_luma_build_prev_q) begin
				sim_brightness_trace_luma_build_tag_q <=
					sim_brightness_trace_frame_q;
			end
			if (brightness_generation_pending_w &&
				!sim_brightness_trace_luma_pending_prev_q) begin
				sim_brightness_trace_luma_pending_tag_q <=
					sim_brightness_trace_luma_build_tag_q;
			end

			if (presentation_raster_commit_w) begin
				if (sim_brightness_trace_in_range_w) begin
					$display("VIP_BRIGHTNESS_PAIR frame=%0d framebuffer_generation=%0d luma_generation=%0d match=%0d",
						sim_brightness_trace_frame_q,
						sim_brightness_trace_capture_pending_tag_q,
						sim_brightness_trace_luma_pending_tag_q,
						!CAPTURE_ENABLED ||
						(sim_brightness_trace_capture_pending_tag_q ==
						 sim_brightness_trace_luma_pending_tag_q));
				end
			end

			if (sim_brightness_trace_in_range_w && ce_i && ctc_valid_o) begin
				$display("VIP_BRIGHTNESS_CTC frame=%0d eye=%0d group=%0d cta=%02x ctc=%04x lock=%0d visible_cta=%04x brt=%08x",
					sim_brightness_trace_frame_q,
					ctc_eye_o,
					ctc_ordinal_o,
					ctc_index_o,
					ctc_data_o,
					dp_lock_o,
					cta_o,
					brightness_active_o);
			end
			if (sim_brightness_trace_in_range_w && ce_i &&
				brightness_result_valid_w) begin
				$display("VIP_BRIGHTNESS_RAW frame=%0d eye=%0d group=%0d raw1=%0d raw2=%0d raw3=%0d overrun=%0d short=%0d",
					sim_brightness_trace_frame_q,
					brightness_result_eye_w,
					brightness_result_group_w,
					brightness_exposure_1_w,
					brightness_exposure_2_w,
					brightness_exposure_3_w,
					brightness_overrun_w,
					brightness_short_w);
			end
			if (sim_brightness_trace_in_range_w && ce_i &&
				presentation_result_valid_w) begin
				$display("VIP_BRIGHTNESS_LUMA frame=%0d eye=%0d group=%0d levels=%08x",
					sim_brightness_trace_frame_q,
					presentation_result_eye_w,
					presentation_result_group_w,
					presentation_levels_w);
			end
		end
	end
`endif

	// Keep old banks while display is off, but show black until a new pair is
	// published after display resumes.
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
				presentation_epoch_valid_q <= 1'b0;
			end
		end else
`endif
`endif
		if (reset_i || dprst_o || !display_transfer_enable_w) begin
			presentation_epoch_valid_q <= 1'b0;
		end else if (presentation_raster_commit_w) begin
			presentation_epoch_valid_q <= 1'b1;
		end
	end
	assign vram_dp_accept_o = !CAPTURE_ENABLED ?
		internal_vram_dp_accept_w : 1'b0;
	assign vram_dp_resp_valid_o =
		!CAPTURE_ENABLED ?
			internal_vram_dp_resp_valid_w : 1'b0;
	assign vram_dp_resp_data_o =
		!CAPTURE_ENABLED ?
			internal_vram_dp_resp_data_w : 16'd0;
	assign native_capture_vram_accept_w =
		CAPTURE_ENABLED &&
		internal_vram_dp_accept_w;
	assign native_capture_vram_resp_valid_w =
		CAPTURE_ENABLED &&
		internal_vram_dp_resp_valid_w;
	assign native_capture_vram_resp_data_w =
		internal_vram_dp_resp_data_w;
	assign vrm_observer_enable_o = scanout_read_enable_w;
	assign vrm_observer_addr_o = scanout_read_addr_w;
	assign vrm_observer_rvalid_o =
		CAPTURE_ENABLED ?
			native_capture_raster_response_valid_w :
			physical_vram_observer_rvalid_w;
	assign vrm_observer_rdata_o =
		CAPTURE_ENABLED ?
			native_capture_raster_data_w :
			physical_vram_observer_rdata_w;

	assign brightness_job_ready_w = brightness_worker_job_ready_w &&
		presentation_transfer_ready_w;
	assign presentation_candidate_w = ce_i && presentation_result_valid_w;
	assign brightness_cache_write_candidate_o = presentation_candidate_w;
	assign brightness_cache_write_o = brightness_generation_write_accept_w;
	assign brightness_cache_write_blocked_o = presentation_candidate_w &&
		!brightness_generation_write_accept_w;
	assign brightness_cache_levels_o = presentation_levels_w;
	assign brightness_generation_build_active_o =
		brightness_generation_build_active_w;
	assign brightness_generation_pending_o = brightness_generation_pending_w;
	assign brightness_generation_display_valid_o =
		brightness_generation_display_valid_w;
	assign brightness_generation_display_o = brightness_generation_display_w;
	assign brightness_generation_swap_o = brightness_generation_swap_w;
	assign framebuffer_collision_precondition_violation_o =
		!CAPTURE_ENABLED &&
		vrm_observer_enable_o && !completed_framebuffer_collision_free_i;
	assign cta_dram_accept_o = cta_dram_accept_w;
	assign cta_dram_resp_valid_o = cta_dram_resp_valid_w;
	assign snapshot_cta_idle_o = !cta_field_active_o &&
		!cta_transaction_active_o && !ctc_valid_o &&
		!cta_field_complete_o && !cta_field_incomplete_o &&
		!cta_field_overlap_o && !cta_dram_req_w &&
		!cta_dram_accept_w && !cta_dram_resp_valid_w;
	assign snapshot_brightness_worker_idle_o =
		brightness_worker_quiescent_w;
	assign snapshot_brightness_allocator_idle_o =
		!brightness_generation_begin_pending_q &&
		!brightness_generation_build_active_w &&
		!brightness_generation_start_w && !presentation_transfer_busy_w &&
		!presentation_result_valid_w && !presentation_candidate_w &&
		!brightness_generation_write_accept_w &&
		!brightness_generation_build_complete_w &&
		!brightness_generation_swap_w;
	assign snapshot_brightness_raster_pipe_empty_o =
		brightness_raster_pipeline_empty_w;
	assign snapshot_framebuffer_capture_idle_o =
		!CAPTURE_ENABLED ||
		(!native_capture_build_active_w &&
		 !native_capture_transfer_owner_w);
	assign snapshot_scan_converter_pipe_empty_o =
		scan_converter_pipeline_empty_w &&
		snapshot_framebuffer_capture_idle_o &&
		(!CAPTURE_ENABLED ||
		 native_capture_raster_pipeline_empty_w);
	// Sticky presentation diagnostics describe a past dropped frame or bad
	// response; they are not live owners and must not make pause unreachable.
	assign snapshot_event_coherent_o = (event_o == 16'd0) &&
		event_levels_coherent_w;
	assign brightness_worker_owner_active_o =
		!brightness_worker_quiescent_w;
	assign brightness_allocator_owner_active_o =
		!snapshot_brightness_allocator_idle_o;
	assign brightness_result_owner_active_o = ctc_valid_o ||
		brightness_result_valid_w;
	assign brightness_raster_read_owner_active_o =
		!brightness_raster_pipeline_empty_w;

	assign brightness_result_valid_o = brightness_result_valid_w;
	assign brightness_result_eye_o = brightness_result_eye_w;
	assign brightness_result_group_o = brightness_result_group_w;
	assign brightness_result_exposure_1_o = brightness_exposure_1_w;
	assign brightness_result_exposure_2_o = brightness_exposure_2_w;
	assign brightness_result_exposure_3_o = brightness_exposure_3_w;
	assign brightness_result_overrun_o = brightness_overrun_w;
	assign brightness_result_short_column_o = brightness_short_w;
	assign brightness_cycle_count_o = brightness_cycle_count_w;
	assign brightness_generation_start_w = native_frame_start_fire_o &&
		dp_display_program_o && !brightness_table_download_i;

	// Start a generation one CE after frame start so an old build can cancel.
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
				brightness_generation_next_q <= 8'd1;
				brightness_generation_begin_tag_q <= 8'd0;
				brightness_generation_begin_pending_q <= 1'b0;
			end
		end else
`endif
`endif
		if (reset_i) begin
			brightness_generation_next_q <= 8'd1;
			brightness_generation_begin_tag_q <= 8'd0;
			brightness_generation_begin_pending_q <= 1'b0;
		end else if (ce_i) begin
			if (brightness_generation_start_w) begin
				brightness_generation_begin_tag_q <=
					brightness_generation_next_q;
				brightness_generation_next_q <=
					brightness_generation_next_q + 8'd1;
				brightness_generation_begin_pending_q <= 1'b1;
			end else if (brightness_generation_begin_pending_q) begin
				// If no bank is free, discard this generation.
				brightness_generation_begin_pending_q <= 1'b0;
			end
		end
	end

	vip_native_dp_timing
	#(
		.LEFT_START_PRE(NATIVE_LEFT_START_PRE),
		.TIMED_EYE_END_ENABLE(CTA_TIMED_EYE_END_ENABLE)
	)
	u_native_dp_timing
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
		.display_enable_i(display_transfer_enable_w),
		.frmcyc_staged_i(frmcyc_register_o),
		.dprst_i(dprst_o),
		.timed_eye_end_valid_i(cta_timed_eye_end_i),
		.timed_eye_end_eye_i(cta_timed_eye_end_eye_i),
		.frame_cycle_o(native_frame_cycle_o),
		.fclk_o(native_fclk_o),
		.waiting_for_fclk_o(native_waiting_for_fclk_o),
		.left_busy_o(native_left_busy_o),
		.right_busy_o(native_right_busy_o),
		.frame_start_o(native_frame_start_o),
		.left_start_o(native_left_start_o),
		.left_end_o(native_left_end_o),
		.right_start_o(native_right_start_o),
		.right_end_o(native_right_end_o),
		.frame_start_fire_o(native_frame_start_fire_o),
		.left_start_fire_o(native_left_start_fire_o),
		.left_end_fire_o(native_left_end_fire_o),
		.right_start_fire_o(native_right_start_fire_o),
		.right_end_fire_o(native_right_end_fire_o),
		.gclk_rise_o(native_gclk_rise_o),
		.game_start_o(native_game_start_o),
		.gclk_rise_fire_o(native_gclk_rise_fire_o),
		.game_start_fire_o(native_game_start_fire_o),
		.frmcyc_active_o(native_frmcyc_active_o),
		.game_frame_wait_o(native_game_frame_wait_o)
	);

	/* verilator lint_off PINCONNECTEMPTY */
	vip_native_cta_sequencer u_native_cta_sequencer
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(dprst_o),
		.left_field_start_i(native_left_start_fire_o),
		.left_field_end_i(native_left_end_fire_o),
		.right_field_start_i(native_right_start_fire_o),
		.right_field_end_i(native_right_end_fire_o),
		.cta_left_i(cta_left_start_w),
		.cta_right_i(cta_right_start_w),
		.column_group_valid_i(column_group_valid_i &&
			column_group_gate_w),
		.column_group_ready_o(cta_column_ready_w),
		.dram_req_o(cta_dram_req_w),
		.dram_addr_o(cta_dram_addr_w),
		.dram_accept_i(cta_dram_accept_w),
		.dram_resp_valid_i(cta_dram_resp_valid_w),
		.dram_resp_data_i(cta_dram_resp_data_w),
		.ctc_valid_o(ctc_valid_o),
		.ctc_data_o(ctc_data_o),
		.ctc_eye_o(ctc_eye_o),
		.ctc_ordinal_o(ctc_ordinal_o),
		.ctc_index_o(ctc_index_o),
		.field_complete_o(cta_field_complete_o),
		.field_complete_eye_o(cta_field_complete_eye_o),
		.field_incomplete_o(cta_field_incomplete_o),
		.field_overlap_o(cta_field_overlap_o),
		.field_active_o(cta_field_active_o),
		.field_eye_o(),
		.transaction_active_o(cta_transaction_active_o),
		.group_count_o(cta_group_count_o),
		.request_count_o(cta_request_count_o),
		.response_count_o(cta_response_count_o)
	);

	vip_native_brightness_precompute u_native_brightness_precompute
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.job_valid_i(ctc_valid_o),
		.job_ready_o(brightness_worker_job_ready_w),
		.job_eye_i(ctc_eye_o),
		.job_group_i(ctc_ordinal_o),
		.job_brta_i(presentation_brightness_job_w[7:0]),
		.job_brtb_i(presentation_brightness_job_w[15:8]),
		.job_brtc_i(presentation_brightness_job_w[23:16]),
		.job_rest_i(presentation_brightness_job_w[31:24]),
		.job_ctc_i(ctc_data_o),
		.result_valid_o(brightness_result_valid_w),
		.result_eye_o(brightness_result_eye_w),
		.result_group_o(brightness_result_group_w),
		.result_exposure_0_o(),
		.result_exposure_1_o(brightness_exposure_1_w),
		.result_exposure_2_o(brightness_exposure_2_w),
		.result_exposure_3_o(brightness_exposure_3_w),
		.result_overrun_o(brightness_overrun_w),
		.result_short_column_o(brightness_short_w),
		.busy_o(brightness_busy_o),
		.cycle_count_o(brightness_cycle_count_w),
		.quiescent_o(brightness_worker_quiescent_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	// Silicon unknown: BRT sampling time is undocumented. MiSTer snapshots BRT at
	// left group zero for both eyes, while CTC is sampled for every group.
	assign presentation_brightness_frame_start_w = ctc_valid_o &&
		!ctc_eye_o && (ctc_ordinal_o == 7'd0);
	assign presentation_brightness_job_w =
		presentation_brightness_frame_start_w ? brightness_active_o :
		presentation_brightness_frame_q;

	always @(posedge clk_i) begin
		if (reset_i) begin
			presentation_brightness_frame_q <= 32'd0;
			presentation_hlg_frame_q <= 1'b0;
			presentation_legacy_sdr_frame_q <= 1'b0;
		end else if (ce_i && presentation_brightness_frame_start_w) begin
			presentation_brightness_frame_q <= brightness_active_o;
			presentation_hlg_frame_q <= presentation_hlg_i;
			presentation_legacy_sdr_frame_q <=
				brightness_table_legacy_sdr_i;
		end
	end

	vip_presentation_luma_transfer u_presentation_luma_transfer
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.job_valid_i(brightness_result_valid_w &&
			!brightness_short_w),
		.job_ready_o(presentation_transfer_ready_w),
		.job_eye_i(brightness_result_eye_w),
		.job_group_i(brightness_result_group_w),
		.job_exposure_1_i(brightness_exposure_1_w),
		.job_exposure_2_i(brightness_exposure_2_w),
		.job_exposure_3_i(brightness_exposure_3_w),
		.transfer_hlg_i(presentation_hlg_frame_q),
		.legacy_sdr_clamp_i(presentation_legacy_sdr_frame_q),
		.table_download_i(brightness_table_download_i),
		.table_write_i(brightness_table_write_i),
		.table_addr_i(brightness_table_addr_i),
		.table_data_i(brightness_table_data_i),
		.result_valid_o(presentation_result_valid_w),
		.result_eye_o(presentation_result_eye_w),
		.result_group_o(presentation_result_group_w),
		.result_levels_o(presentation_levels_w),
		.busy_o(presentation_transfer_busy_w)
	);

	// Copy four-column DP transfers into triple-buffered MiSTer storage.
	/* verilator lint_off PINCONNECTEMPTY */
	vip_native_framebuffer_capture u_native_framebuffer_capture
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.abort_i(dprst_o),
		.frame_start_i(native_frame_start_fire_o),
		.begin_enable_i(
			CAPTURE_ENABLED &&
			dp_display_program_o),
		.source_fb_i(native_capture_source_fb_w),
		.group_accept_i(
			CAPTURE_ENABLED &&
			column_group_fire_w),
		.group_ready_o(native_capture_group_ready_w),
		.ctc_valid_i(
			CAPTURE_ENABLED && ctc_valid_o),
		.ctc_eye_i(ctc_eye_o),
		.ctc_ordinal_i(ctc_ordinal_o),
		.vram_req_o(native_capture_vram_req_w),
		.vram_addr_o(native_capture_vram_addr_w),
		.vram_accept_i(native_capture_vram_accept_w),
		.vram_resp_valid_i(native_capture_vram_resp_valid_w),
		.vram_resp_data_i(native_capture_vram_resp_data_w),
		.raster_commit_i(presentation_raster_commit_w),
		.display_swap_o(),
		.display_valid_o(),
		.display_bank_o(),
		.pending_valid_o(native_capture_pending_w),
		.build_active_o(native_capture_build_active_w),
		.raster_read_enable_i(
			CAPTURE_ENABLED &&
			scanout_read_enable_w),
		.raster_read_addr_i(scanout_read_addr_w),
		.raster_read_response_valid_o(
			native_capture_raster_response_valid_w),
		.raster_read_generation_valid_o(
			native_capture_raster_generation_valid_w),
		.raster_read_data_o(native_capture_raster_data_w),
		.protocol_error_o(native_capture_protocol_error_w),
		.unexpected_response_o(native_capture_unexpected_response_w),
		.transfer_owner_active_o(native_capture_transfer_owner_w),
		.raster_read_pipeline_empty_o(
			native_capture_raster_pipeline_empty_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	// Build brightness off-screen and publish a complete pair at raster frame start.
	/* verilator lint_off PINCONNECTEMPTY */
	vip_brightness_generation_cache u_brightness_generation_cache
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		.sim_snapshot_restore_commit_i(sim_snapshot_restore_commit_i),
		.sim_snapshot_restore_apply_i(sim_snapshot_restore_apply_i),
		.sim_snapshot_restore_packet_i(sim_snapshot_restore_packet_i),
`endif
`endif
		.cancel_build_i((native_frame_start_fire_o ||
			brightness_table_download_i) &&
			brightness_generation_build_active_w),
		.begin_valid_i(brightness_generation_begin_pending_q),
		.begin_generation_i(brightness_generation_begin_tag_q),
		.begin_ready_o(),
		.begin_accept_o(),
		.begin_blocked_o(),
		.reuse_blocked_o(),
		.generation_tag_collision_o(),
		.write_valid_i(presentation_candidate_w &&
			brightness_cache_collision_free_i),
		.write_generation_i(brightness_generation_build_tag_w),
		.write_eye_i(presentation_result_eye_w),
		.write_group_i(presentation_result_group_w),
		.write_levels_i(presentation_levels_w),
		.write_ready_o(),
		.write_accept_o(brightness_generation_write_accept_w),
		.write_blocked_o(),
		.write_tag_mismatch_o(),
		.commit_valid_i(brightness_generation_build_complete_w),
		.commit_generation_i(brightness_generation_build_tag_w),
		.commit_ready_o(),
		.commit_accept_o(),
		.commit_blocked_o(),
		.commit_incomplete_o(),
		.commit_tag_mismatch_o(),
		.raster_frame_boundary_i(presentation_raster_commit_w),
		.display_swap_o(brightness_generation_swap_w),
		.display_valid_o(brightness_generation_display_valid_w),
		.display_generation_o(brightness_generation_display_w),
		.display_bank_o(),
		.raster_read_enable_i(brightness_raster_read_enable_w),
		.raster_read_eye_i(1'b0),
		.raster_read_group_i(brightness_raster_read_group_w),
		.raster_read_response_valid_o(brightness_raster_response_valid_w),
		.raster_read_generation_valid_o(),
		.raster_read_generation_o(),
		.raster_read_levels_o(),
		.raster_read_pair_generation_valid_o(
			brightness_raster_generation_valid_w),
		.raster_read_left_levels_o(brightness_raster_left_levels_w),
		.raster_read_right_levels_o(brightness_raster_right_levels_w),
		.build_active_o(brightness_generation_build_active_w),
		.build_bank_o(),
		.build_generation_o(brightness_generation_build_tag_w),
		.build_left_count_o(),
		.build_right_count_o(),
		.build_complete_o(brightness_generation_build_complete_w),
		.pending_valid_o(brightness_generation_pending_w),
		.pending_bank_o(),
		.pending_generation_o(),
		.raster_read_pipeline_empty_o(
			brightness_raster_pipeline_empty_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	vip_mister_scan_converter
	#(
		.H_VISIBLE(H_VISIBLE),
		.H_TOTAL(H_TOTAL),
		.H_SYNC_BEG(H_SYNC_BEG),
		.H_SYNC_END(H_SYNC_END),
		.V_VISIBLE(V_VISIBLE),
		.V_TOTAL(V_TOTAL),
		.V_SYNC_BEG(V_SYNC_BEG),
		.V_SYNC_END(V_SYNC_END),
		.EXTERNAL_BRIGHTNESS(1),
		.EXTERNAL_FRAMEBUFFER(NATIVE_FRAMEBUFFER_CAPTURE_ENABLE)
	)
	u_mister_scan_converter
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(video_ce_i),
		.phi1_i(video_phi1_i),
		.savestate_boundary_stop_i(savestate_boundary_stop_i),
		.savestate_state_addr_i(savestate_state_addr_i),
		.savestate_state_wdata_i(savestate_state_wdata_i),
		.savestate_state_wren_i(savestate_state_wren_i),
		.savestate_state_o(savestate_scan_state_o),
		.display_enable_i(scanout_display_enable_w),
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		.sim_snapshot_restore_commit_i(sim_snapshot_restore_commit_i),
		.sim_snapshot_restore_apply_i(sim_snapshot_restore_apply_i),
		.sim_snapshot_restore_packet_i(sim_snapshot_restore_packet_i),
`endif
`endif
		.displayed_fb_i(displayed_fb_i),
		.framebuffer_handoff_fire_i(framebuffer_handoff_fire_i),
		.framebuffer_handoff_target_i(framebuffer_handoff_target_i),
		.displayed_fb_latched_o(displayed_fb_latched_o),
		.presentation_mode_i(presentation_mode_i),
		.flat_eye_i(flat_eye_i),
		.side_by_side_i(side_by_side_i),
		.compat_60hz_i(compat_60hz_i),
		.shutter_i(shutter_i),
		.brightness_write_i(1'b0),
		.brightness_eye_i(1'b0),
		.brightness_group_i(7'd0),
		.brightness_levels_i(32'd0),
		.raster_frame_boundary_o(brightness_raster_boundary_w),
		.brightness_read_enable_o(brightness_raster_read_enable_w),
		.brightness_read_group_o(brightness_raster_read_group_w),
		.brightness_read_response_valid_i(
			brightness_raster_response_valid_w),
		.brightness_read_generation_valid_i(
			brightness_raster_generation_valid_w),
		.brightness_read_left_levels_i(brightness_raster_left_levels_w),
		.brightness_read_right_levels_i(brightness_raster_right_levels_w),
		.brightness_alignment_error_o(brightness_alignment_error_o),
		.framebuffer_generation_valid_i(
			native_capture_raster_generation_valid_w),
		.vrm_observer_enable_o(scanout_read_enable_w),
		.vrm_observer_addr_o(scanout_read_addr_w),
		.vrm_observer_rvalid_i(vrm_observer_rvalid_o),
		.vrm_observer_rdata_i(vrm_observer_rdata_o),
		.observer_alignment_error_o(observer_alignment_error_o),
		.observer_owner_active_o(scanout_owner_active_o),
		.snapshot_pipeline_empty_o(scan_converter_pipeline_empty_w),
		.pixel_ce_o(pixel_ce_o),
		.raster_x_o(raster_x_o),
		.raster_y_o(raster_y_o),
		.video_hblank_o(video_hblank_o),
		.video_vblank_o(video_vblank_o),
		.video_hsync_o(video_hsync_o),
		.video_vsync_o(video_vsync_o),
		.raw_pixel_left_o(raw_pixel_left_o),
		.raw_pixel_right_o(raw_pixel_right_o),
		.video_luma_left_o(video_luma_left_o),
		.video_luma_right_o(video_luma_right_o)
	);

	/* verilator lint_off PINCONNECTEMPTY */
	vip_host_memory_subsystem
	#(
		.EVENT_SET_WINS(EVENT_SET_WINS),
		.WRITE_FIRST_ON_BOUNDARY(WRITE_FIRST_ON_BOUNDARY),
		.LOCAL_TOTAL_CE(LOCAL_TOTAL_CE),
		.VRM_WRITE_TOTAL_CE(VRM_WRITE_TOTAL_CE),
		.VRM_READ_TOTAL_CE(VRM_READ_TOTAL_CE),
		.DRAM_WRITE_TOTAL_CE(DRAM_WRITE_TOTAL_CE),
		.DRAM_READ_TOTAL_CE(DRAM_READ_TOTAL_CE)
	)
	u_host_memory_subsystem
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.phi1_i(phi1_i),
		.savestate_state_addr_i(savestate_state_addr_i),
		.savestate_state_wdata_i(savestate_state_wdata_i),
		.savestate_state_wren_i(savestate_state_wren_i),
		.savestate_vram_mem_active_i(savestate_vram_mem_active_i),
		.savestate_dram_mem_active_i(savestate_dram_mem_active_i),
		.savestate_mem_addr_i(savestate_mem_addr_i),
		.savestate_mem_rden_i(savestate_mem_rden_i),
		.savestate_mem_wren_i(savestate_mem_wren_i),
		.savestate_mem_wdata_i(savestate_mem_wdata_i),
		.savestate_vram_mem_rdata_o(savestate_vram_mem_rdata_o),
		.savestate_dram_mem_rdata_o(savestate_dram_mem_rdata_o),
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
		.sim_snapshot_restore_commit_i(sim_snapshot_restore_commit_i),
		.sim_snapshot_restore_apply_i(sim_snapshot_restore_apply_i),
		.sim_snapshot_restore_packet_i(sim_snapshot_restore_packet_i),
`endif
`endif
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
		.vram_dp_req_i(CAPTURE_ENABLED ?
			native_capture_vram_req_w : vram_dp_req_i),
		.vram_dp_write_i(CAPTURE_ENABLED ?
			1'b0 : vram_dp_write_i),
		.vram_dp_addr_i(CAPTURE_ENABLED ?
			native_capture_vram_addr_w : vram_dp_addr_i),
		.vram_dp_wdata_i(CAPTURE_ENABLED ?
			16'd0 : vram_dp_wdata_i),
		.vram_dp_byte_enable_i(CAPTURE_ENABLED ?
			2'b11 : vram_dp_byte_enable_i),
		.vram_dp_accept_o(internal_vram_dp_accept_w),
		.vram_dp_resp_valid_o(internal_vram_dp_resp_valid_w),
		.vram_dp_resp_data_o(internal_vram_dp_resp_data_w),
		.vram_xp_req_i(vram_xp_req_i),
		.vram_xp_write_i(vram_xp_write_i),
		.vram_xp_addr_i(vram_xp_addr_i),
		.vram_xp_wdata_i(vram_xp_wdata_i),
		.vram_xp_byte_enable_i(vram_xp_byte_enable_i),
		.vram_xp_accept_o(vram_xp_accept_o),
		.vram_xp_resp_valid_o(vram_xp_resp_valid_o),
		.vram_xp_resp_data_o(vram_xp_resp_data_o),
		.dram_dp_req_i(cta_dram_req_w),
		.dram_dp_write_i(1'b0),
		.dram_dp_addr_i(cta_dram_addr_w),
		.dram_dp_wdata_i(16'd0),
		.dram_dp_byte_enable_i(2'b11),
		.dram_dp_accept_o(cta_dram_accept_w),
		.dram_dp_resp_valid_o(cta_dram_resp_valid_w),
		.dram_dp_resp_data_o(cta_dram_resp_data_w),
		.dram_xp_req_i(dram_xp_req_i),
		.dram_xp_write_i(dram_xp_write_i),
		.dram_xp_addr_i(dram_xp_addr_i),
		.dram_xp_wdata_i(dram_xp_wdata_i),
		.dram_xp_byte_enable_i(dram_xp_byte_enable_i),
		.dram_xp_accept_o(dram_xp_accept_o),
		.dram_xp_resp_valid_o(dram_xp_resp_valid_o),
		.dram_xp_resp_data_o(dram_xp_resp_data_o),
		.vram_observer_ce_i(1'b1),
		.vram_observer_enable_i(
			!CAPTURE_ENABLED &&
			scanout_read_enable_w),
		.vram_observer_addr_i(scanout_read_addr_w),
		.vram_observer_rdata_o(physical_vram_observer_rdata_w),
		.vram_observer_rvalid_o(physical_vram_observer_rvalid_w),
		.dram_observer_ce_i(1'b1),
		.dram_observer_enable_i(dram_observer_enable_i),
		.dram_observer_addr_i(dram_observer_addr_i),
		.dram_observer_rdata_o(dram_observer_rdata_o),
		.dram_observer_rvalid_o(dram_observer_rvalid_o),
		.vram_physical_accept_o(vram_physical_accept_o),
		.vram_physical_write_o(vram_physical_write_o),
		.vram_physical_owner_o(vram_physical_owner_o),
		.vram_physical_addr_o(vram_physical_addr_o),
		.vram_physical_wdata_o(vram_physical_wdata_o),
		.vram_physical_byte_enable_o(vram_physical_byte_enable_o),
		.vram_physical_resp_valid_o(vram_physical_resp_valid_o),
		.vram_physical_resp_owner_o(vram_physical_resp_owner_o),
		.dram_physical_accept_o(dram_physical_accept_o),
		.dram_physical_write_o(dram_physical_write_o),
		.dram_physical_owner_o(dram_physical_owner_o),
		.dram_physical_addr_o(dram_physical_addr_o),
		.dram_physical_wdata_o(dram_physical_wdata_o),
		.dram_physical_byte_enable_o(dram_physical_byte_enable_o),
		.dram_physical_resp_valid_o(dram_physical_resp_valid_o),
		.dram_physical_resp_owner_o(dram_physical_resp_owner_o),
		.dp_fclk_i(native_fclk_o),
		.dp_gclk_i(native_gclk_rise_o),
		.dp_left_busy_i(native_left_busy_o),
		.dp_right_busy_i(native_right_busy_o),
		.dp_scan_ready_i(dp_scan_ready_i),
		.dp_busy_i(native_dp_busy_w),
		.xp_sbout_i(xp_sbout_i),
		.xp_sbcount_i(xp_sbcount_i),
		.xp_overtime_i(xp_overtime_i),
		.xp_busy_i(xp_busy_i),
		.scanerr_event_i(scanerr_event_i),
		.direct_event_i({
			xp_timeerr_fire_i,
			xp_end_fire_i,
			xp_sb_hit_fire_i,
			8'd0,
			native_frame_start_fire_o,
			native_game_start_fire_o,
			native_right_end_fire_o,
			native_left_end_fire_o,
			1'b0
		}),
		.direct_event_mask_i(16'he01e),
		.fclk_rise_i(native_frame_start_fire_o),
		.display_column_boundary_i(column_group_fire_w),
		.gclk_rise_i(native_gclk_rise_fire_o),
		.cta_left_latch_i(native_left_start_fire_o),
		.cta_right_latch_i(native_right_start_fire_o),
		.cta_left_i(cta_left_servo_i),
		.cta_right_i(cta_right_servo_i),
		.xp_draw_start_i(xp_draw_start_i),
		.xp_first_group_done_i(xp_first_group_done_i),
		.event_o(event_o),
		.event_levels_coherent_o(event_levels_coherent_w),
		.int_pending_o(int_pending_o),
		.int_enable_o(int_enable_o),
		.dprst_o(dprst_o),
		.xprst_o(xprst_o),
		.dp_lock_o(dp_lock_o),
		.dp_synce_program_o(dp_synce_program_o),
		.dp_synce_active_o(dp_synce_active_o),
		.dp_refresh_o(dp_refresh_o),
		.dp_display_program_o(dp_display_program_o),
		.dp_display_active_o(dp_display_active_o),
		.xp_sbcmp_o(xp_sbcmp_o),
		.xp_enable_o(xp_enable_o),
		.brightness_register_o(brightness_register_o),
		.brightness_active_o(brightness_active_o),
		.frmcyc_register_o(frmcyc_register_o),
		.frmcyc_active_o(frmcyc_register_active_o),
		.cta_o(cta_o),
		.spt_register_o(spt_register_o),
		.spt_active_o(spt_active_o),
		.gplt_register_o(gplt_register_o),
		.gplt_active_o(gplt_active_o),
		.jplt_register_o(jplt_register_o),
		.jplt_active_o(jplt_active_o),
		.bkcol_register_o(bkcol_register_o),
		.bkcol_active_o(bkcol_active_o),
		.bkcol_pending_o(bkcol_pending_o),
		.bkcol_wait_first_group_o(bkcol_wait_first_group_o),
		.bkcol_update_pending_o(),
		.event_history_o(event_history_o),
		.host_effective_address_o(),
		.host_target_vram_o(),
		.host_target_dram_o(),
		.host_target_register_o(),
		.host_target_unmapped_o(),
		.host_framebuffer_o(),
		.host_framebuffer_index_o(),
		.host_framebuffer_padding_o(),
		.host_character_o(),
		.host_character_index_o(),
		.host_character_alias_o(),
		.host_read_defined_mask_o(),
		.host_read_value_valid_o(),
		.host_undefined_access_o(),
		.host_unmapped_access_o(),
		.host_static_access_undefined_o(),
		.host_boundary_collision_o(),
		.host_local_active_o(host_local_active_o),
		.host_busy_o(host_busy_o),
		.vram_cpu_timing_busy_o(vram_cpu_timing_busy_o),
		.vram_store_busy_o(vram_store_busy_o),
		.vram_inner_offer_held_o(vram_inner_offer_held_o),
		.vram_read_pending_o(vram_read_pending_o),
		.dram_cpu_timing_busy_o(dram_cpu_timing_busy_o),
		.dram_store_busy_o(dram_store_busy_o),
		.dram_inner_offer_held_o(dram_inner_offer_held_o),
		.dram_read_pending_o(dram_read_pending_o)
	);
	/* verilator lint_on PINCONNECTEMPTY */

endmodule

// Host registers and the logical VRM/DRAM memory service.
//
// CPU requests pass through the host shell and timing adapters. Native DP and XP
// clients connect directly to the VRM and DRAM stores. Requests stay valid until
// accepted, and read ownership stays tagged until response.
//
// VRM writes launch on C3, reads on C6, and read data returns on C7 by default.
// Silicon unknown: DRAM host waits are unmeasured. They have separate parameters
// but currently use the verified VRM defaults.
//
// Silicon unknown: refresh slot behavior is not known. Expose the request but do
// not reserve invented memory slots.


module vip_host_memory_subsystem
#(
	parameter integer EVENT_SET_WINS = 1,
	parameter integer WRITE_FIRST_ON_BOUNDARY = 0,
	parameter [7:0] LOCAL_TOTAL_CE = 8'd2,
	parameter [7:0] VRM_WRITE_TOTAL_CE = 8'd3,
	parameter [7:0] VRM_READ_TOTAL_CE = 8'd7,
	parameter [7:0] DRAM_WRITE_TOTAL_CE = 8'd3,
	parameter [7:0] DRAM_READ_TOTAL_CE = 8'd7
)
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire        phi1_i,
	input  wire [5:0]  savestate_state_addr_i,
	input  wire [63:0] savestate_state_wdata_i,
	input  wire        savestate_state_wren_i,
	input  wire        savestate_vram_mem_active_i,
	input  wire        savestate_dram_mem_active_i,
	input  wire [16:0] savestate_mem_addr_i,
	input  wire        savestate_mem_rden_i,
	input  wire        savestate_mem_wren_i,
	input  wire [7:0]  savestate_mem_wdata_i,
	output wire [7:0]  savestate_vram_mem_rdata_o,
	output wire [7:0]  savestate_dram_mem_rdata_o,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire        sim_snapshot_restore_commit_i,
	input  wire        sim_snapshot_restore_apply_i,
	input  wire [3647:0] sim_snapshot_restore_packet_i,
`endif
`endif

	// Public VIP host bus.
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

	// VRM DP channel; hold until accepted.
	input  wire        vram_dp_req_i,
	input  wire        vram_dp_write_i,
	input  wire [15:0] vram_dp_addr_i,
	input  wire [15:0] vram_dp_wdata_i,
	input  wire [1:0]  vram_dp_byte_enable_i,
	output wire        vram_dp_accept_o,
	output wire        vram_dp_resp_valid_o,
	output wire [15:0] vram_dp_resp_data_o,

	// VRM XP channel; hold until accepted.
	input  wire        vram_xp_req_i,
	input  wire        vram_xp_write_i,
	input  wire [15:0] vram_xp_addr_i,
	input  wire [15:0] vram_xp_wdata_i,
	input  wire [1:0]  vram_xp_byte_enable_i,
	output wire        vram_xp_accept_o,
	output wire        vram_xp_resp_valid_o,
	output wire [15:0] vram_xp_resp_data_o,

	// DRAM DP channel; hold until accepted.
	input  wire        dram_dp_req_i,
	input  wire        dram_dp_write_i,
	input  wire [15:0] dram_dp_addr_i,
	input  wire [15:0] dram_dp_wdata_i,
	input  wire [1:0]  dram_dp_byte_enable_i,
	output wire        dram_dp_accept_o,
	output wire        dram_dp_resp_valid_o,
	output wire [15:0] dram_dp_resp_data_o,

	// DRAM XP channel; hold until accepted.
	input  wire        dram_xp_req_i,
	input  wire        dram_xp_write_i,
	input  wire [15:0] dram_xp_addr_i,
	input  wire [15:0] dram_xp_wdata_i,
	input  wire [1:0]  dram_xp_byte_enable_i,
	output wire        dram_xp_accept_o,
	output wire        dram_xp_resp_valid_o,
	output wire [15:0] dram_xp_resp_data_o,

	// Read-only observer ports outside memory arbitration.
	input  wire        vram_observer_ce_i,
	input  wire        vram_observer_enable_i,
	input  wire [15:0] vram_observer_addr_i,
	output wire [15:0] vram_observer_rdata_o,
	output wire        vram_observer_rvalid_o,
	input  wire        dram_observer_ce_i,
	input  wire        dram_observer_enable_i,
	input  wire [15:0] dram_observer_addr_i,
	output wire [15:0] dram_observer_rdata_o,
	output wire        dram_observer_rvalid_o,

	// Output-only traces of accepted memory transactions.
	output wire        vram_physical_accept_o,
	output wire        vram_physical_write_o,
	output wire [1:0]  vram_physical_owner_o,
	output wire [15:0] vram_physical_addr_o,
	output wire [15:0] vram_physical_wdata_o,
	output wire [1:0]  vram_physical_byte_enable_o,
	output wire        vram_physical_resp_valid_o,
	output wire [1:0]  vram_physical_resp_owner_o,
	output wire        dram_physical_accept_o,
	output wire        dram_physical_write_o,
	output wire [1:0]  dram_physical_owner_o,
	output wire [15:0] dram_physical_addr_o,
	output wire [15:0] dram_physical_wdata_o,
	output wire [1:0]  dram_physical_byte_enable_o,
	output wire        dram_physical_resp_valid_o,
	output wire [1:0]  dram_physical_resp_owner_o,

	// Native status and control-consumer events.
	input  wire        dp_fclk_i,
	input  wire        dp_gclk_i,
	input  wire        dp_left_busy_i,
	input  wire        dp_right_busy_i,
	input  wire        dp_scan_ready_i,
	input  wire [3:0]  dp_busy_i,
	input  wire        xp_sbout_i,
	input  wire [4:0]  xp_sbcount_i,
	input  wire        xp_overtime_i,
	input  wire [1:0]  xp_busy_i,
	input  wire        scanerr_event_i,
	input  wire [15:0] direct_event_i,
	input  wire [15:0] direct_event_mask_i,
	input  wire        fclk_rise_i,
	input  wire        display_column_boundary_i,
	input  wire        gclk_rise_i,
	input  wire        cta_left_latch_i,
	input  wire        cta_right_latch_i,
	input  wire [7:0]  cta_left_i,
	input  wire [7:0]  cta_right_i,
	input  wire        xp_draw_start_i,
	input  wire        xp_first_group_done_i,

	// Interrupts, register actions, and staged DP/XP controls.
	output wire [15:0] event_o,
	output wire        event_levels_coherent_o,
	output wire [15:0] int_pending_o,
	output wire [15:0] int_enable_o,
	output wire        dprst_o,
	output wire        xprst_o,
	output wire        dp_lock_o,
	output wire        dp_synce_program_o,
	output wire        dp_synce_active_o,
	output wire        dp_refresh_o,
	output wire        dp_display_program_o,
	output wire        dp_display_active_o,
	output wire [4:0]  xp_sbcmp_o,
	output wire        xp_enable_o,
	output wire [31:0] brightness_register_o,
	output wire [31:0] brightness_active_o,
	output wire [3:0]  frmcyc_register_o,
	output wire [3:0]  frmcyc_active_o,
	output wire [15:0] cta_o,
	output wire [39:0] spt_register_o,
	output wire [39:0] spt_active_o,
	output wire [31:0] gplt_register_o,
	output wire [31:0] gplt_active_o,
	output wire [31:0] jplt_register_o,
	output wire [31:0] jplt_active_o,
	output wire [1:0]  bkcol_register_o,
	output wire [1:0]  bkcol_active_o,
	output wire        bkcol_pending_o,
	output wire        bkcol_wait_first_group_o,
	output wire        bkcol_update_pending_o,
	output wire [6:0]  event_history_o,

	// Address-decoder diagnostics.
	output wire [18:0] host_effective_address_o,
	output wire        host_target_vram_o,
	output wire        host_target_dram_o,
	output wire        host_target_register_o,
	output wire        host_target_unmapped_o,
	output wire        host_framebuffer_o,
	output wire [1:0]  host_framebuffer_index_o,
	output wire        host_framebuffer_padding_o,
	output wire        host_character_o,
	output wire [1:0]  host_character_index_o,
	output wire        host_character_alias_o,
	output wire [15:0] host_read_defined_mask_o,
	output wire        host_read_value_valid_o,
	output wire        host_undefined_access_o,
	output wire        host_unmapped_access_o,
	output wire        host_static_access_undefined_o,
	output wire        host_boundary_collision_o,
	output wire        host_local_active_o,
	output wire        host_busy_o,
	output wire        vram_cpu_timing_busy_o,
	output wire        vram_store_busy_o,
	output wire        vram_inner_offer_held_o,
	output wire        vram_read_pending_o,
	output wire        dram_cpu_timing_busy_o,
	output wire        dram_store_busy_o,
	output wire        dram_inner_offer_held_o,
	output wire        dram_read_pending_o
);

	wire        vram_cpu_request_w;
	wire        vram_cpu_accept_w;
	wire [15:0] vram_cpu_address_w;
	wire        vram_cpu_write_w;
	wire [15:0] vram_cpu_write_data_w;
	wire [1:0]  vram_cpu_byte_enable_w;
	wire        vram_cpu_response_valid_w;
	wire [15:0] vram_cpu_response_data_w;
	wire        vram_store_cpu_request_w;
	wire        vram_store_cpu_accept_w;
	wire [15:0] vram_store_cpu_address_w;
	wire        vram_store_cpu_write_w;
	wire [15:0] vram_store_cpu_write_data_w;
	wire [1:0]  vram_store_cpu_byte_enable_w;
	wire        vram_store_cpu_response_valid_w;
	wire [15:0] vram_store_cpu_response_data_w;
	wire        vram_cpu_timing_busy_w;
	wire        vram_physical_store_busy_w;

	wire        dram_cpu_request_w;
	wire        dram_cpu_accept_w;
	wire [15:0] dram_cpu_address_w;
	wire        dram_cpu_write_w;
	wire [15:0] dram_cpu_write_data_w;
	wire [1:0]  dram_cpu_byte_enable_w;
	wire        dram_cpu_response_valid_w;
	wire [15:0] dram_cpu_response_data_w;
	wire        dram_store_cpu_request_w;
	wire        dram_store_cpu_accept_w;
	wire [15:0] dram_store_cpu_address_w;
	wire        dram_store_cpu_write_w;
	wire [15:0] dram_store_cpu_write_data_w;
	wire [1:0]  dram_store_cpu_byte_enable_w;
	wire        dram_store_cpu_response_valid_w;
	wire [15:0] dram_store_cpu_response_data_w;
	wire        dram_cpu_timing_busy_w;
	wire        dram_physical_store_busy_w;
	wire        host_request_cycle_w;

	assign vram_store_busy_o = vram_cpu_timing_busy_w ||
		vram_physical_store_busy_w;
	assign dram_store_busy_o = dram_cpu_timing_busy_w ||
		dram_physical_store_busy_w;
	assign vram_cpu_timing_busy_o = vram_cpu_timing_busy_w;
	assign dram_cpu_timing_busy_o = dram_cpu_timing_busy_w;

	vip_host_register_shell
	#(
		.EVENT_SET_WINS(EVENT_SET_WINS),
		.WRITE_FIRST_ON_BOUNDARY(WRITE_FIRST_ON_BOUNDARY),
		.LOCAL_TOTAL_CE(LOCAL_TOTAL_CE)
	)
	u_host_register_shell
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.phi1_i(phi1_i),
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
		.vram_cpu_request_o(vram_cpu_request_w),
		.vram_cpu_accept_i(vram_cpu_accept_w),
		.vram_cpu_address_o(vram_cpu_address_w),
		.vram_cpu_write_o(vram_cpu_write_w),
		.vram_cpu_write_data_o(vram_cpu_write_data_w),
		.vram_cpu_byte_enable_o(vram_cpu_byte_enable_w),
		.vram_cpu_response_valid_i(vram_cpu_response_valid_w),
		.vram_cpu_response_data_i(vram_cpu_response_data_w),
		.dram_cpu_request_o(dram_cpu_request_w),
		.dram_cpu_accept_i(dram_cpu_accept_w),
		.dram_cpu_address_o(dram_cpu_address_w),
		.dram_cpu_write_o(dram_cpu_write_w),
		.dram_cpu_write_data_o(dram_cpu_write_data_w),
		.dram_cpu_byte_enable_o(dram_cpu_byte_enable_w),
		.dram_cpu_response_valid_i(dram_cpu_response_valid_w),
		.dram_cpu_response_data_i(dram_cpu_response_data_w),
		.dp_fclk_i(dp_fclk_i),
		.dp_gclk_i(dp_gclk_i),
		.dp_left_busy_i(dp_left_busy_i),
		.dp_right_busy_i(dp_right_busy_i),
		.dp_scan_ready_i(dp_scan_ready_i),
		.dp_busy_i(dp_busy_i),
		.xp_sbout_i(xp_sbout_i),
		.xp_sbcount_i(xp_sbcount_i),
		.xp_overtime_i(xp_overtime_i),
		.xp_busy_i(xp_busy_i),
		.scanerr_event_i(scanerr_event_i),
		.direct_event_i(direct_event_i),
		.direct_event_mask_i(direct_event_mask_i),
		.fclk_rise_i(fclk_rise_i),
		.display_column_boundary_i(display_column_boundary_i),
		.gclk_rise_i(gclk_rise_i),
		.cta_left_latch_i(cta_left_latch_i),
		.cta_right_latch_i(cta_right_latch_i),
		.cta_left_i(cta_left_i),
		.cta_right_i(cta_right_i),
		.xp_draw_start_i(xp_draw_start_i),
		.xp_first_group_done_i(xp_first_group_done_i),
		.event_o(event_o),
		.event_levels_coherent_o(event_levels_coherent_o),
		.int_pending_o(int_pending_o),
		.int_enable_o(int_enable_o),
		.dprst_o(dprst_o),
		.xprst_o(xprst_o),
		.dp_lock_o(dp_lock_o),
		.dp_synce_program_o(dp_synce_program_o),
		.dp_synce_active_o(dp_synce_active_o),
		.dp_refresh_o(dp_refresh_o),
		.dp_display_program_o(dp_display_program_o),
		.dp_display_active_o(dp_display_active_o),
		.xp_sbcmp_o(xp_sbcmp_o),
		.xp_enable_o(xp_enable_o),
		.brightness_register_o(brightness_register_o),
		.brightness_active_o(brightness_active_o),
		.frmcyc_register_o(frmcyc_register_o),
		.frmcyc_active_o(frmcyc_active_o),
		.cta_o(cta_o),
		.spt_register_o(spt_register_o),
		.spt_active_o(spt_active_o),
		.gplt_register_o(gplt_register_o),
		.gplt_active_o(gplt_active_o),
		.jplt_register_o(jplt_register_o),
		.jplt_active_o(jplt_active_o),
		.bkcol_register_o(bkcol_register_o),
		.bkcol_active_o(bkcol_active_o),
		.bkcol_pending_o(bkcol_pending_o),
		.bkcol_wait_first_group_o(bkcol_wait_first_group_o),
		.bkcol_update_pending_o(bkcol_update_pending_o),
		.event_history_o(event_history_o),
		.host_effective_address_o(host_effective_address_o),
		.host_target_vram_o(host_target_vram_o),
		.host_target_dram_o(host_target_dram_o),
		.host_target_register_o(host_target_register_o),
		.host_target_unmapped_o(host_target_unmapped_o),
		.host_framebuffer_o(host_framebuffer_o),
		.host_framebuffer_index_o(host_framebuffer_index_o),
		.host_framebuffer_padding_o(host_framebuffer_padding_o),
		.host_character_o(host_character_o),
		.host_character_index_o(host_character_index_o),
		.host_character_alias_o(host_character_alias_o),
		.host_read_defined_mask_o(host_read_defined_mask_o),
		.host_read_value_valid_o(host_read_value_valid_o),
		.host_undefined_access_o(host_undefined_access_o),
		.host_unmapped_access_o(host_unmapped_access_o),
		.host_static_access_undefined_o(host_static_access_undefined_o),
		.host_boundary_collision_o(host_boundary_collision_o),
		.host_local_active_o(host_local_active_o),
		.host_busy_o(host_busy_o),
		.host_request_cycle_o(host_request_cycle_w)
	);

	vip_host_memory_timing
	#(
		.WRITE_TOTAL_CE(VRM_WRITE_TOTAL_CE),
		.READ_TOTAL_CE(VRM_READ_TOTAL_CE)
	)
	u_vram_host_timing
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.upstream_valid_i(vram_cpu_request_w),
		.upstream_cycle_i(host_request_cycle_w),
		.upstream_write_i(vram_cpu_write_w),
		.upstream_addr_i(vram_cpu_address_w),
		.upstream_wdata_i(vram_cpu_write_data_w),
		.upstream_byte_enable_i(vram_cpu_byte_enable_w),
		.upstream_accept_o(vram_cpu_accept_w),
		.upstream_response_valid_o(vram_cpu_response_valid_w),
		.upstream_response_data_o(vram_cpu_response_data_w),
		.downstream_valid_o(vram_store_cpu_request_w),
		.downstream_write_o(vram_store_cpu_write_w),
		.downstream_addr_o(vram_store_cpu_address_w),
		.downstream_wdata_o(vram_store_cpu_write_data_w),
		.downstream_byte_enable_o(vram_store_cpu_byte_enable_w),
		.downstream_accept_i(vram_store_cpu_accept_w),
		.downstream_response_valid_i(vram_store_cpu_response_valid_w),
		.downstream_response_data_i(vram_store_cpu_response_data_w),
		.busy_o(vram_cpu_timing_busy_w)
	);

	vip_host_memory_timing
	#(
		.WRITE_TOTAL_CE(DRAM_WRITE_TOTAL_CE),
		.READ_TOTAL_CE(DRAM_READ_TOTAL_CE)
	)
	u_dram_host_timing
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.upstream_valid_i(dram_cpu_request_w),
		.upstream_cycle_i(host_request_cycle_w),
		.upstream_write_i(dram_cpu_write_w),
		.upstream_addr_i(dram_cpu_address_w),
		.upstream_wdata_i(dram_cpu_write_data_w),
		.upstream_byte_enable_i(dram_cpu_byte_enable_w),
		.upstream_accept_o(dram_cpu_accept_w),
		.upstream_response_valid_o(dram_cpu_response_valid_w),
		.upstream_response_data_o(dram_cpu_response_data_w),
		.downstream_valid_o(dram_store_cpu_request_w),
		.downstream_write_o(dram_store_cpu_write_w),
		.downstream_addr_o(dram_store_cpu_address_w),
		.downstream_wdata_o(dram_store_cpu_write_data_w),
		.downstream_byte_enable_o(dram_store_cpu_byte_enable_w),
		.downstream_accept_i(dram_store_cpu_accept_w),
		.downstream_response_valid_i(dram_store_cpu_response_valid_w),
		.downstream_response_data_i(dram_store_cpu_response_data_w),
		.busy_o(dram_cpu_timing_busy_w)
	);

	vip_memory_store
	u_vram_store
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.reserve_i(1'b0),
		.dp_req_i(vram_dp_req_i),
		.dp_write_i(vram_dp_write_i),
		.dp_addr_i(vram_dp_addr_i),
		.dp_wdata_i(vram_dp_wdata_i),
		.dp_byte_enable_i(vram_dp_byte_enable_i),
		.dp_accept_o(vram_dp_accept_o),
		.dp_resp_valid_o(vram_dp_resp_valid_o),
		.dp_resp_data_o(vram_dp_resp_data_o),
		.xp_req_i(vram_xp_req_i),
		.xp_write_i(vram_xp_write_i),
		.xp_addr_i(vram_xp_addr_i),
		.xp_wdata_i(vram_xp_wdata_i),
		.xp_byte_enable_i(vram_xp_byte_enable_i),
		.xp_accept_o(vram_xp_accept_o),
		.xp_resp_valid_o(vram_xp_resp_valid_o),
		.xp_resp_data_o(vram_xp_resp_data_o),
		.cpu_req_i(vram_store_cpu_request_w),
		.cpu_write_i(vram_store_cpu_write_w),
		.cpu_addr_i(vram_store_cpu_address_w),
		.cpu_wdata_i(vram_store_cpu_write_data_w),
		.cpu_byte_enable_i(vram_store_cpu_byte_enable_w),
		.cpu_accept_o(vram_store_cpu_accept_w),
		.cpu_resp_valid_o(vram_store_cpu_response_valid_w),
		.cpu_resp_data_o(vram_store_cpu_response_data_w),
		.observer_ce_i(vram_observer_ce_i),
		.observer_enable_i(vram_observer_enable_i),
		.observer_addr_i(vram_observer_addr_i),
		.observer_rdata_o(vram_observer_rdata_o),
		.observer_rvalid_o(vram_observer_rvalid_o),
		.savestate_mem_active_i(savestate_vram_mem_active_i),
		.savestate_mem_addr_i(savestate_mem_addr_i),
		.savestate_mem_rden_i(savestate_mem_rden_i),
		.savestate_mem_wren_i(savestate_mem_wren_i),
		.savestate_mem_wdata_i(savestate_mem_wdata_i),
		.savestate_mem_rdata_o(savestate_vram_mem_rdata_o),
		.physical_accept_o(vram_physical_accept_o),
		.physical_write_o(vram_physical_write_o),
		.physical_owner_o(vram_physical_owner_o),
		.physical_addr_o(vram_physical_addr_o),
		.physical_wdata_o(vram_physical_wdata_o),
		.physical_byte_enable_o(vram_physical_byte_enable_o),
		.physical_resp_valid_o(vram_physical_resp_valid_o),
		.physical_resp_owner_o(vram_physical_resp_owner_o),
		.busy_o(vram_physical_store_busy_w),
		.read_pending_o(vram_read_pending_o),
		.offer_held_o(vram_inner_offer_held_o)
	);

	vip_memory_store
	u_dram_store
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.reserve_i(1'b0),
		.dp_req_i(dram_dp_req_i),
		.dp_write_i(dram_dp_write_i),
		.dp_addr_i(dram_dp_addr_i),
		.dp_wdata_i(dram_dp_wdata_i),
		.dp_byte_enable_i(dram_dp_byte_enable_i),
		.dp_accept_o(dram_dp_accept_o),
		.dp_resp_valid_o(dram_dp_resp_valid_o),
		.dp_resp_data_o(dram_dp_resp_data_o),
		.xp_req_i(dram_xp_req_i),
		.xp_write_i(dram_xp_write_i),
		.xp_addr_i(dram_xp_addr_i),
		.xp_wdata_i(dram_xp_wdata_i),
		.xp_byte_enable_i(dram_xp_byte_enable_i),
		.xp_accept_o(dram_xp_accept_o),
		.xp_resp_valid_o(dram_xp_resp_valid_o),
		.xp_resp_data_o(dram_xp_resp_data_o),
		.cpu_req_i(dram_store_cpu_request_w),
		.cpu_write_i(dram_store_cpu_write_w),
		.cpu_addr_i(dram_store_cpu_address_w),
		.cpu_wdata_i(dram_store_cpu_write_data_w),
		.cpu_byte_enable_i(dram_store_cpu_byte_enable_w),
		.cpu_accept_o(dram_store_cpu_accept_w),
		.cpu_resp_valid_o(dram_store_cpu_response_valid_w),
		.cpu_resp_data_o(dram_store_cpu_response_data_w),
		.observer_ce_i(dram_observer_ce_i),
		.observer_enable_i(dram_observer_enable_i),
		.observer_addr_i(dram_observer_addr_i),
		.observer_rdata_o(dram_observer_rdata_o),
		.observer_rvalid_o(dram_observer_rvalid_o),
		.savestate_mem_active_i(savestate_dram_mem_active_i),
		.savestate_mem_addr_i(savestate_mem_addr_i),
		.savestate_mem_rden_i(savestate_mem_rden_i),
		.savestate_mem_wren_i(savestate_mem_wren_i),
		.savestate_mem_wdata_i(savestate_mem_wdata_i),
		.savestate_mem_rdata_o(savestate_dram_mem_rdata_o),
		.physical_accept_o(dram_physical_accept_o),
		.physical_write_o(dram_physical_write_o),
		.physical_owner_o(dram_physical_owner_o),
		.physical_addr_o(dram_physical_addr_o),
		.physical_wdata_o(dram_physical_wdata_o),
		.physical_byte_enable_o(dram_physical_byte_enable_o),
		.physical_resp_valid_o(dram_physical_resp_valid_o),
		.physical_resp_owner_o(dram_physical_resp_owner_o),
		.busy_o(dram_physical_store_busy_w),
		.read_pending_o(dram_read_pending_o),
		.offer_held_o(dram_inner_offer_held_o)
	);

endmodule


module vip_host_register_shell
#(
	parameter integer EVENT_SET_WINS = 1,
	parameter integer WRITE_FIRST_ON_BOUNDARY = 0,
	parameter [7:0] LOCAL_TOTAL_CE = 8'd2
)
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire        phi1_i,
	input  wire [5:0]  savestate_state_addr_i,
	input  wire [63:0] savestate_state_wdata_i,
	input  wire        savestate_state_wren_i,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire        sim_snapshot_restore_commit_i,
	input  wire        sim_snapshot_restore_apply_i,
	input  wire [3647:0] sim_snapshot_restore_packet_i,
`endif
`endif

	// Public VIP host bus.
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

	// CPU channel for the 128 KiB VRM store, addressed by halfword.
	output wire        vram_cpu_request_o,
	input  wire        vram_cpu_accept_i,
	output wire [15:0] vram_cpu_address_o,
	output wire        vram_cpu_write_o,
	output wire [15:0] vram_cpu_write_data_o,
	output wire [1:0]  vram_cpu_byte_enable_o,
	input  wire        vram_cpu_response_valid_i,
	input  wire [15:0] vram_cpu_response_data_i,

	// CPU channel for the 128 KiB VIP DRAM store.
	output wire        dram_cpu_request_o,
	input  wire        dram_cpu_accept_i,
	output wire [15:0] dram_cpu_address_o,
	output wire        dram_cpu_write_o,
	output wire [15:0] dram_cpu_write_data_o,
	output wire [1:0]  dram_cpu_byte_enable_o,
	input  wire        dram_cpu_response_valid_i,
	input  wire [15:0] dram_cpu_response_data_i,

	// Native status for edge detection and registers.
	input  wire        dp_fclk_i,
	input  wire        dp_gclk_i,
	input  wire        dp_left_busy_i,
	input  wire        dp_right_busy_i,
	input  wire        dp_scan_ready_i,
	input  wire [3:0]  dp_busy_i,
	input  wire        xp_sbout_i,
	input  wire [4:0]  xp_sbcount_i,
	input  wire        xp_overtime_i,
	input  wire [1:0]  xp_busy_i,
	input  wire        scanerr_event_i,

	// Selected native events bypass the registered detector for same-edge timing.
	input  wire [15:0] direct_event_i,
	input  wire [15:0] direct_event_mask_i,

	// Separate control-consumer events update staged values on native boundaries.
	input  wire        fclk_rise_i,
	input  wire        display_column_boundary_i,
	input  wire        gclk_rise_i,
	input  wire        cta_left_latch_i,
	input  wire        cta_right_latch_i,
	input  wire [7:0]  cta_left_i,
	input  wire [7:0]  cta_right_i,
	input  wire        xp_draw_start_i,
	input  wire        xp_first_group_done_i,

	// Interrupt state is visible for diagnostics; irq_o is the CPU interrupt.
	output wire [15:0] event_o,
	output wire        event_levels_coherent_o,
	output wire [15:0] int_pending_o,
	output wire [15:0] int_enable_o,

	// Auto-clearing display and draw actions.
	output wire        dprst_o,
	output wire        xprst_o,

	// Programmed and staged DP/XP controls.
	output wire        dp_lock_o,
	output wire        dp_synce_program_o,
	output wire        dp_synce_active_o,
	output wire        dp_refresh_o,
	output wire        dp_display_program_o,
	output wire        dp_display_active_o,
	output wire [4:0]  xp_sbcmp_o,
	output wire        xp_enable_o,
	output wire [31:0] brightness_register_o,
	output wire [31:0] brightness_active_o,
	output wire [3:0]  frmcyc_register_o,
	output wire [3:0]  frmcyc_active_o,
	output wire [15:0] cta_o,
	output wire [39:0] spt_register_o,
	output wire [39:0] spt_active_o,
	output wire [31:0] gplt_register_o,
	output wire [31:0] gplt_active_o,
	output wire [31:0] jplt_register_o,
	output wire [31:0] jplt_active_o,
	output wire [1:0]  bkcol_register_o,
	output wire [1:0]  bkcol_active_o,
	output wire        bkcol_pending_o,
	output wire        bkcol_wait_first_group_o,
	output wire        bkcol_update_pending_o,
	output wire [6:0]  event_history_o,

	// Decode state follows the held host request.
	output wire [18:0] host_effective_address_o,
	output wire        host_target_vram_o,
	output wire        host_target_dram_o,
	output wire        host_target_register_o,
	output wire        host_target_unmapped_o,
	output wire        host_framebuffer_o,
	output wire [1:0]  host_framebuffer_index_o,
	output wire        host_framebuffer_padding_o,
	output wire        host_character_o,
	output wire [1:0]  host_character_index_o,
	output wire        host_character_alias_o,

	// Last completed read. Undefined reads return zero with no valid mask.
	output reg  [15:0] host_read_defined_mask_o,
	output reg         host_read_value_valid_o,
	output reg         host_undefined_access_o,
	output reg         host_unmapped_access_o,
	output reg         host_static_access_undefined_o,
	output wire        host_boundary_collision_o,
	output wire        host_local_active_o,
	output wire        host_busy_o,
	output wire        host_request_cycle_o
);

	wire        request_valid_w;
	wire        request_cycle_w;
	wire        request_accept_w;
	wire [18:0] request_address_w;
	wire        request_write_w;
	wire        request_instruction_w;
	wire        request_data_w;
	wire [3:0]  request_be_w;
	wire [1:0]  request_st_w;
	wire        request_byte_w;
	wire        request_halfword_w;
	wire        request_byte_high_w;
	wire [1:0]  request_memory_byte_enable_w;
	wire [15:0] request_write_source_w;
	wire [15:0] request_memory_write_data_w;
	wire [15:0] request_register_write_data_w;
	wire        response_valid_w;
	wire [15:0] response_data_w;
	wire        frontend_busy_w;

	wire [18:0] effective_address_w;
	wire [16:0] vram_byte_address_w;
	wire [16:0] dram_byte_address_w;
	wire        target_vram_w;
	wire        target_dram_w;
	wire        target_register_w;
	wire        target_unmapped_w;
	wire        framebuffer_w;
	wire [1:0]  framebuffer_index_w;
	wire        framebuffer_padding_w;
	wire        character_w;
	wire [1:0]  character_index_w;
	wire        character_alias_w;
	wire [26:0] register_select_w;

	wire [15:0] register_read_data_w;
	wire [15:0] register_read_defined_mask_w;
	wire        register_read_value_defined_w;
	wire        register_read_response_w;
	wire        register_select_valid_w;
	wire        register_write_handled_w;
	wire        register_static_access_undefined_w;
	wire        register_boundary_collision_w;
	wire        intenb_write_w;
	wire [15:0] intenb_write_data_w;
	wire        intclr_write_w;
	wire [15:0] intclr_write_data_w;
	wire        dprst_seed_busy_w;
	wire [15:0] detected_event_w;
	wire        host_bus_value_valid_w = (mrq_i && !rw_i) ||
		(response_valid_w && frontend_busy_w);
	wire [15:0] host_bus_value_w = (mrq_i && !rw_i) ?
		din_i : response_data_w;

	reg        local_active_q;
	reg [7:0]  local_elapsed_q;

	wire local_target_w = target_register_w || target_unmapped_w;
	wire local_due_w = local_active_q &&
		(local_elapsed_q == (LOCAL_TOTAL_CE - 8'd1));
	wire local_accept_w = ce_i && !reset_i && request_valid_w &&
		local_target_w && local_due_w;
	wire register_read_w = local_accept_w && target_register_w &&
		!request_write_w;
	wire register_write_commit_w = local_accept_w && target_register_w &&
		request_write_w;
	wire local_read_response_w = local_accept_w && !request_write_w;

	assign request_accept_w = request_valid_w && (
		local_accept_w ||
		(target_vram_w && vram_cpu_accept_i) ||
		(target_dram_w && dram_cpu_accept_i)
	);

	assign response_valid_w = !request_write_w && (
		local_read_response_w ||
		(target_vram_w && vram_cpu_response_valid_i) ||
		(target_dram_w && dram_cpu_response_valid_i)
	);
	assign response_data_w = target_register_w ?
		(register_read_data_w & register_read_defined_mask_w) :
		target_vram_w ? vram_cpu_response_data_i :
		target_dram_w ? dram_cpu_response_data_i : 16'd0;

	assign vram_cpu_request_o = request_valid_w && target_vram_w;
	assign vram_cpu_address_o = vram_byte_address_w[16:1];
	assign vram_cpu_write_o = request_write_w;
	assign vram_cpu_write_data_o = request_memory_write_data_w;
	assign vram_cpu_byte_enable_o = request_memory_byte_enable_w;

	assign dram_cpu_request_o = request_valid_w && target_dram_w;
	assign dram_cpu_address_o = dram_byte_address_w[16:1];
	assign dram_cpu_write_o = request_write_w;
	assign dram_cpu_write_data_o = request_memory_write_data_w;
	assign dram_cpu_byte_enable_o = request_memory_byte_enable_w;

	assign host_effective_address_o = effective_address_w;
	assign host_target_vram_o = frontend_busy_w && target_vram_w;
	assign host_target_dram_o = frontend_busy_w && target_dram_w;
	assign host_target_register_o = frontend_busy_w && target_register_w;
	assign host_target_unmapped_o = frontend_busy_w && target_unmapped_w;
	assign host_framebuffer_o = frontend_busy_w && framebuffer_w;
	assign host_framebuffer_index_o = framebuffer_index_w;
	assign host_framebuffer_padding_o = frontend_busy_w && framebuffer_padding_w;
	assign host_character_o = frontend_busy_w && character_w;
	assign host_character_index_o = character_index_w;
	assign host_character_alias_o = frontend_busy_w && character_alias_w;
	assign host_boundary_collision_o = register_boundary_collision_w;
	assign host_local_active_o = local_active_q;
	assign host_request_cycle_o = request_cycle_w;
	// Block snapshots until DPRST finishes its delayed register initialization.
	assign host_busy_o = frontend_busy_w || dprst_seed_busy_w;
	assign event_o = (detected_event_w & ~direct_event_mask_i) |
		(direct_event_i & direct_event_mask_i);

	vip_host_beat_frontend u_host_frontend
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.phi1_i(phi1_i),
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
		.request_valid_o(request_valid_w),
		.request_cycle_o(request_cycle_w),
		.request_accept_i(request_accept_w),
		.request_address_o(request_address_w),
		.request_write_o(request_write_w),
		.request_instruction_o(request_instruction_w),
		.request_data_o(request_data_w),
		.request_be_o(request_be_w),
		.request_st_o(request_st_w),
		.request_byte_o(request_byte_w),
		.request_halfword_o(request_halfword_w),
		.request_byte_high_o(request_byte_high_w),
		.request_memory_byte_enable_o(request_memory_byte_enable_w),
		.request_write_source_o(request_write_source_w),
		.request_memory_write_data_o(request_memory_write_data_w),
		.request_register_write_data_o(request_register_write_data_w),
		.response_valid_i(response_valid_w),
		.response_data_i(response_data_w),
		.busy_o(frontend_busy_w)
	);

	vip_host_address_decoder u_address_decoder
	(
		.address_i({5'd0, request_address_w}),
		.effective_address_o(effective_address_w),
		.vram_address_o(vram_byte_address_w),
		.dram_address_o(dram_byte_address_w),
		.target_vram_o(target_vram_w),
		.target_dram_o(target_dram_w),
		.target_register_o(target_register_w),
		.target_unmapped_o(target_unmapped_w),
		.framebuffer_o(framebuffer_w),
		.framebuffer_index_o(framebuffer_index_w),
		.framebuffer_padding_o(framebuffer_padding_w),
		.character_o(character_w),
		.character_index_o(character_index_w),
		.character_alias_o(character_alias_w),
		.register_select_o(register_select_w)
	);

	vip_event_detector u_event_detector
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
		.fclk_i(dp_fclk_i),
		.gclk_i(dp_gclk_i),
		.left_busy_i(dp_left_busy_i),
		.right_busy_i(dp_right_busy_i),
		.sbout_i(xp_sbout_i),
		.sbcount_i(xp_sbcount_i),
		.sbcmp_i(xp_sbcmp_o),
		.xp_busy_i(|xp_busy_i),
		.overtime_i(xp_overtime_i),
		.scanerr_event_i(scanerr_event_i),
		.event_o(detected_event_w),
		.event_history_o(event_history_o),
		.levels_coherent_o(event_levels_coherent_o)
	);

	vip_register_bank
	#(
		.WRITE_FIRST_ON_BOUNDARY(WRITE_FIRST_ON_BOUNDARY)
	)
	u_register_bank
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
		.register_select_i(register_select_w),
		.read_i(register_read_w),
		.write_commit_i(register_write_commit_w),
		.write_data_i(request_register_write_data_w),
		.host_bus_value_valid_i(host_bus_value_valid_w),
		.host_bus_value_i(host_bus_value_w),
		.int_pending_i(int_pending_o),
		.int_enable_i(int_enable_o),
		.intenb_write_o(intenb_write_w),
		.intenb_write_data_o(intenb_write_data_w),
		.intclr_write_o(intclr_write_w),
		.intclr_write_data_o(intclr_write_data_w),
		.dprst_o(dprst_o),
		.dprst_seed_busy_o(dprst_seed_busy_w),
		.xprst_o(xprst_o),
		.dp_fclk_i(dp_fclk_i),
		.dp_scan_ready_i(dp_scan_ready_i),
		.dp_busy_i(dp_busy_i),
		.xp_sbout_i(xp_sbout_i),
		.xp_sbcount_i(xp_sbcount_i),
		.xp_overtime_i(xp_overtime_i),
		.xp_busy_i(xp_busy_i),
		.fclk_rise_i(fclk_rise_i),
		.display_column_boundary_i(display_column_boundary_i),
		.gclk_rise_i(gclk_rise_i),
		.cta_left_latch_i(cta_left_latch_i),
		.cta_right_latch_i(cta_right_latch_i),
		.cta_left_i(cta_left_i),
		.cta_right_i(cta_right_i),
		.xp_draw_start_i(xp_draw_start_i),
		.xp_first_group_done_i(xp_first_group_done_i),
		.read_data_o(register_read_data_w),
		.read_defined_mask_o(register_read_defined_mask_w),
		.read_value_defined_o(register_read_value_defined_w),
		.read_response_o(register_read_response_w),
		.register_select_valid_o(register_select_valid_w),
		.write_handled_o(register_write_handled_w),
		.static_access_undefined_o(register_static_access_undefined_w),
		.boundary_collision_o(register_boundary_collision_w),
		.dp_lock_o(dp_lock_o),
		.dp_synce_program_o(dp_synce_program_o),
		.dp_synce_active_o(dp_synce_active_o),
		.dp_refresh_o(dp_refresh_o),
		.dp_display_program_o(dp_display_program_o),
		.dp_display_active_o(dp_display_active_o),
		.xp_sbcmp_o(xp_sbcmp_o),
		.xp_enable_o(xp_enable_o),
		.brightness_register_o(brightness_register_o),
		.brightness_active_o(brightness_active_o),
		.frmcyc_register_o(frmcyc_register_o),
		.frmcyc_active_o(frmcyc_active_o),
		.cta_o(cta_o),
		.spt_register_o(spt_register_o),
		.spt_active_o(spt_active_o),
		.gplt_register_o(gplt_register_o),
		.gplt_active_o(gplt_active_o),
		.jplt_register_o(jplt_register_o),
		.jplt_active_o(jplt_active_o),
		.bkcol_register_o(bkcol_register_o),
		.bkcol_active_o(bkcol_active_o),
		.bkcol_pending_o(bkcol_pending_o),
		.bkcol_wait_first_group_o(bkcol_wait_first_group_o),
		.bkcol_update_pending_o(bkcol_update_pending_o)
	);

	vip_interrupt_bank
	#(
		.EVENT_SET_WINS(EVENT_SET_WINS)
	)
	u_interrupt_bank
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
		.event_i(event_o),
		.intenb_write_i(intenb_write_w),
		.intenb_wdata_i(intenb_write_data_w),
		.intclr_write_i(intclr_write_w),
		.intclr_wdata_i(intclr_write_data_w),
		.dprst_i(dprst_o),
		.xprst_i(xprst_o),
		.pending_o(int_pending_o),
		.enable_o(int_enable_o),
		.irq_o(irq_o)
	);

	// Register and unmapped accesses capture on C1 and complete on C2. CE pauses
	// hold the request and timer.
	always @(posedge clk_i) begin
		if (reset_i) begin
			local_active_q <= 1'b0;
			local_elapsed_q <= 8'd0;
		end else if (ce_i) begin
			if (local_active_q) begin
				if (local_due_w) begin
					local_active_q <= 1'b0;
					local_elapsed_q <= 8'd0;
				end else begin
					local_elapsed_q <= local_elapsed_q + 8'd1;
				end
			end else if (request_valid_w && local_target_w) begin
				local_active_q <= 1'b1;
				local_elapsed_q <= 8'd1;
			end
		end
	end

	// Hold read diagnostics until the next response; pulse diagnostics follow CE.
	always @(posedge clk_i) begin
		if (reset_i) begin
			host_read_defined_mask_o <= 16'd0;
			host_read_value_valid_o <= 1'b0;
			host_undefined_access_o <= 1'b0;
			host_unmapped_access_o <= 1'b0;
			host_static_access_undefined_o <= 1'b0;
		end else if (ce_i) begin
			host_undefined_access_o <= 1'b0;
			host_unmapped_access_o <= 1'b0;
			host_static_access_undefined_o <= 1'b0;

			if (request_valid_w && request_accept_w) begin
				if (target_unmapped_w) begin
					host_unmapped_access_o <= 1'b1;
					host_undefined_access_o <= 1'b1;
				end
				if (target_register_w && register_static_access_undefined_w) begin
					host_static_access_undefined_o <= 1'b1;
					host_undefined_access_o <= 1'b1;
				end
				if (target_register_w && !request_write_w &&
					!register_read_value_defined_w) begin
					host_undefined_access_o <= 1'b1;
				end
			end

			if (response_valid_w && frontend_busy_w) begin
				if (target_register_w) begin
					host_read_defined_mask_o <= request_byte_w ?
						(request_byte_high_w ?
							{register_read_defined_mask_w[15:8], 8'd0} :
							{8'd0, register_read_defined_mask_w[7:0]}) :
						register_read_defined_mask_w;
					host_read_value_valid_o <= register_read_value_defined_w;
				end else if (target_vram_w || target_dram_w) begin
					host_read_defined_mask_o <= request_byte_w ?
						(request_byte_high_w ? 16'hff00 : 16'h00ff) :
						16'hffff;
					host_read_value_valid_o <= 1'b1;
				end else begin
					host_read_defined_mask_o <= 16'd0;
					host_read_value_valid_o <= 1'b0;
				end
			end
		end
	end

`ifdef VERILATOR
	// Keep request metadata visible for timing checks.
	/* verilator lint_off UNUSED */
	wire _unused_metadata_ok = &{
		1'b0,
		request_instruction_w,
		request_data_w,
		request_be_w,
		request_st_w,
		request_halfword_w,
		request_write_source_w,
		vram_byte_address_w[0],
		dram_byte_address_w[0],
		register_read_response_w,
		register_select_valid_w,
		register_write_handled_w,
		1'b0
	};
	/* verilator lint_on UNUSED */
`endif

`ifndef SYNTHESIS
	initial begin
		if (LOCAL_TOTAL_CE < 8'd2) begin
			$error("vip_host_register_shell LOCAL_TOTAL_CE must be at least 2");
		end
	end
`endif

endmodule

module vip_host_beat_frontend
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire        phi1_i,

	input  wire        cs_i,
	input  wire [23:1] a_i,
	input  wire [15:0] din_i,
	input  wire [3:0]  be_i,
	input  wire [1:0]  st_i,
	input  wire        da_i,
	input  wire        mrq_i,
	input  wire        rw_i,
	input  wire        bcyst_i,
	output reg  [15:0] dout_o,
	output reg         ready_o,

	output wire        request_valid_o,
	output wire        request_cycle_o,
	input  wire        request_accept_i,
	output wire [18:0] request_address_o,
	output wire        request_write_o,
	output wire        request_instruction_o,
	output wire        request_data_o,
	output wire [3:0]  request_be_o,
	output wire [1:0]  request_st_o,
	output wire        request_byte_o,
	output wire        request_halfword_o,
	output wire        request_byte_high_o,
	output wire [1:0]  request_memory_byte_enable_o,
	output wire [15:0] request_write_source_o,
	output wire [15:0] request_memory_write_data_o,
	output wire [15:0] request_register_write_data_o,

	input  wire        response_valid_i,
	input  wire [15:0] response_data_i,

	output wire        busy_o
);

	localparam [1:0] ST_DATA = 2'b10;

	reg        active_q;
	reg        accepted_q;
	reg        complete_q;
	reg        retired_q;
	reg        request_cycle_q;

	reg [23:1] bus_address_q;
	reg [18:0] address_q;
	reg [15:0] source_data_q;
	reg [3:0]  be_q;
	reg [1:0]  st_q;
	reg        da_q;
	reg        write_q;
	reg        byte_q;
	reg        byte_high_q;

	wire bus_byte_low_w = (be_i == 4'b1110);
	wire bus_byte_high_w = (be_i == 4'b1101);
	wire bus_halfword_w = (be_i == 4'b1100);
	wire bus_size_valid_w = bus_byte_low_w || bus_byte_high_w || bus_halfword_w;
	wire bus_write_w = !rw_i && da_i && (st_i == ST_DATA);
	wire bus_beat_valid_w = cs_i && mrq_i && bus_size_valid_w &&
		(rw_i || bus_write_w);
	wire bus_matches_identity_w = bus_beat_valid_w &&
		(a_i == bus_address_q) &&
		(be_i == be_q) &&
		(st_i == st_q) &&
		(da_i == da_q) &&
		(bus_write_w == write_q);
	wire bus_matches_token_w = bus_matches_identity_w &&
		(!write_q || (din_i == source_data_q));
	// V810 write data changes at phi1, after the address/control token has been
	// captured on that edge. Drive the pending downstream request from the live
	// package data pins and register that value on the accepting CPU edge.
	wire [15:0] pending_write_source_w =
		(write_q && !accepted_q && !complete_q) ? din_i : source_data_q;

	wire [15:0] response_data_shaped_w = byte_q ?
		(byte_high_q ? {response_data_i[15:8], 8'd0} :
			{8'd0, response_data_i[7:0]}) :
		response_data_i;
	wire [7:0] selected_write_byte_w = byte_high_q ?
		pending_write_source_w[15:8] : pending_write_source_w[7:0];

	assign request_valid_o = active_q && !accepted_q && !complete_q;
	assign request_cycle_o = request_cycle_q;
	assign request_address_o = address_q;
	assign request_write_o = write_q;
	assign request_instruction_o = active_q && !write_q && !da_q;
	assign request_data_o = active_q && da_q;
	assign request_be_o = be_q;
	assign request_st_o = st_q;
	assign request_byte_o = byte_q;
	assign request_halfword_o = !byte_q;
	assign request_byte_high_o = byte_high_q;
	assign request_memory_byte_enable_o = byte_q ?
		(byte_high_q ? 2'b10 : 2'b01) : 2'b11;
	assign request_write_source_o = pending_write_source_w;

	// Replicate the selected V810 byte across both BRAM lanes.
	assign request_memory_write_data_o = byte_q ?
		{selected_write_byte_w, selected_write_byte_w} :
		pending_write_source_w;

	// VIP register byte writes use the full source halfword on even addresses and
	// move DIN[15:8] to the high byte on odd addresses.
	assign request_register_write_data_o = (byte_q && byte_high_q) ?
		{selected_write_byte_w, 8'd0} : pending_write_source_w;

	assign busy_o = active_q;

	// Retire the active beat and pulse READY.
	task retire_beat_task;
		begin
			active_q <= 1'b0;
			accepted_q <= 1'b0;
			complete_q <= 1'b0;
			retired_q <= 1'b1;
			ready_o <= 1'b1;
		end
	endtask

	always @(posedge clk_i) begin
		if (reset_i) begin
			active_q <= 1'b0;
			accepted_q <= 1'b0;
			complete_q <= 1'b0;
			retired_q <= 1'b0;
			request_cycle_q <= 1'b0;
			bus_address_q <= 23'd0;
			address_q <= 19'd0;
			source_data_q <= 16'd0;
			be_q <= 4'd0;
			st_q <= 2'd0;
			da_q <= 1'b0;
			write_q <= 1'b0;
			byte_q <= 1'b0;
			byte_high_q <= 1'b0;
			dout_o <= 16'd0;
			ready_o <= 1'b0;
		end else begin
			if (ce_i) begin
				ready_o <= 1'b0;
				if (active_q && write_q && !accepted_q && !complete_q) begin
					source_data_q <= din_i;
				end

				if (active_q) begin
					if (complete_q) begin
						if (bus_matches_token_w) begin
							retire_beat_task;
						end
					end else if (!accepted_q && request_accept_i) begin
						accepted_q <= 1'b1;
						if (write_q) begin
							complete_q <= 1'b1;
							if (bus_matches_identity_w) begin
								retire_beat_task;
							end
						end else if (response_valid_i) begin
							dout_o <= response_data_shaped_w;
							complete_q <= 1'b1;
							if (bus_matches_token_w) begin
								retire_beat_task;
							end
						end
					end else if (accepted_q && !write_q && response_valid_i) begin
						dout_o <= response_data_shaped_w;
						complete_q <= 1'b1;
						if (bus_matches_token_w) begin
							retire_beat_task;
						end
					end
				end
			end

			// A low request rearms the same beat. BCYST identifies a new physical
			// cycle when a zero-bubble replacement has identical address, lanes,
			// direction, and write data.
			if (!active_q && !bus_beat_valid_w) begin
				retired_q <= 1'b0;
			end

			if (phi1_i && !active_q && bus_beat_valid_w &&
				(bcyst_i || !retired_q || !bus_matches_token_w)) begin
				active_q <= 1'b1;
				request_cycle_q <= ~request_cycle_q;
				accepted_q <= 1'b0;
				complete_q <= 1'b0;
				retired_q <= 1'b0;
				bus_address_q <= a_i;
				address_q <= {a_i[18:1], bus_byte_high_w};
				source_data_q <= din_i;
				be_q <= be_i;
				st_q <= st_i;
				da_q <= da_i;
				write_q <= bus_write_w;
				byte_q <= bus_byte_low_w || bus_byte_high_w;
				byte_high_q <= bus_byte_high_w;
			end
		end
	end

endmodule

module vip_host_address_decoder
(
	input  wire [23:0] address_i,

	output wire [18:0] effective_address_o,
	output reg  [16:0] vram_address_o,
	output reg  [16:0] dram_address_o,

	output reg         target_vram_o,
	output reg         target_dram_o,
	output reg         target_register_o,
	output reg         target_unmapped_o,

	output reg         framebuffer_o,
	output reg  [1:0]  framebuffer_index_o,
	output reg         framebuffer_padding_o,
	output reg         character_o,
	output reg  [1:0]  character_index_o,
	output reg         character_alias_o,

	output reg  [26:0] register_select_o
);

	// register_select_o bits in address order.
	localparam integer REG_INTPND = 0;
	localparam integer REG_INTENB = 1;
	localparam integer REG_INTCLR = 2;
	localparam integer REG_DPSTTS = 3;
	localparam integer REG_DPCTRL = 4;
	localparam integer REG_BRTA = 5;
	localparam integer REG_BRTB = 6;
	localparam integer REG_BRTC = 7;
	localparam integer REG_REST = 8;
	localparam integer REG_FRMCYC = 9;
	localparam integer REG_CTA = 10;
	localparam integer REG_XPSTTS = 11;
	localparam integer REG_XPCTRL = 12;
	localparam integer REG_VER = 13;
	localparam integer REG_SPT0 = 14;
	localparam integer REG_SPT1 = 15;
	localparam integer REG_SPT2 = 16;
	localparam integer REG_SPT3 = 17;
	localparam integer REG_GPLT0 = 18;
	localparam integer REG_GPLT1 = 19;
	localparam integer REG_GPLT2 = 20;
	localparam integer REG_GPLT3 = 21;
	localparam integer REG_JPLT0 = 22;
	localparam integer REG_JPLT1 = 23;
	localparam integer REG_JPLT2 = 24;
	localparam integer REG_JPLT3 = 25;
	localparam integer REG_BKCOL = 26;

	wire [18:0] effective_address_w = address_i[18:0];
	wire [18:0] register_halfword_address_w = {effective_address_w[18:1], 1'b0};

	assign effective_address_o = effective_address_w;

	always @* begin
		vram_address_o = 17'd0;
		dram_address_o = 17'd0;

		target_vram_o = 1'b0;
		target_dram_o = 1'b0;
		target_register_o = 1'b0;
		target_unmapped_o = 1'b1;

		framebuffer_o = 1'b0;
		framebuffer_index_o = 2'd0;
		framebuffer_padding_o = 1'b0;
		character_o = 1'b0;
		character_index_o = 2'd0;
		character_alias_o = 1'b0;

		register_select_o = 27'd0;

		// 00000-1ffff: VRM, with 24 KiB framebuffer and 8 KiB characters per quarter.
		if (effective_address_w[18:17] == 2'b00) begin
			target_vram_o = 1'b1;
			target_unmapped_o = 1'b0;
			vram_address_o = effective_address_w[16:0];
			if (effective_address_w[14:13] == 2'b11) begin
				character_o = 1'b1;
				character_index_o = effective_address_w[16:15];
			end else begin
				framebuffer_o = 1'b1;
				framebuffer_index_o = effective_address_w[16:15];
				// The last eight bytes of each 64-byte column are CPU-only padding.
				framebuffer_padding_o = &effective_address_w[5:3];
			end
		end else if (effective_address_w[18:17] == 2'b01) begin
			// 20000-3ffff: 128 KiB DRAM.
			target_dram_o = 1'b1;
			target_unmapped_o = 1'b0;
			dram_address_o = effective_address_w[16:0];
		end else if (effective_address_w[18:15] == 4'b1111) begin
			// 78000-7ffff: four 8 KiB character aliases.
			target_vram_o = 1'b1;
			target_unmapped_o = 1'b0;
			vram_address_o = {
				effective_address_w[14:13],
				2'b11,
				effective_address_w[12:0]
			};
			character_o = 1'b1;
			character_index_o = effective_address_w[14:13];
			character_alias_o = 1'b1;
		end else begin
			// Odd addresses select the high byte of the aligned register.
			case (register_halfword_address_w)
				19'h5f800: begin
					target_register_o = 1'b1;
					register_select_o[REG_INTPND] = 1'b1;
				end
				19'h5f802: begin
					target_register_o = 1'b1;
					register_select_o[REG_INTENB] = 1'b1;
				end
				19'h5f804: begin
					target_register_o = 1'b1;
					register_select_o[REG_INTCLR] = 1'b1;
				end
				19'h5f820: begin
					target_register_o = 1'b1;
					register_select_o[REG_DPSTTS] = 1'b1;
				end
				19'h5f822: begin
					target_register_o = 1'b1;
					register_select_o[REG_DPCTRL] = 1'b1;
				end
				19'h5f824: begin
					target_register_o = 1'b1;
					register_select_o[REG_BRTA] = 1'b1;
				end
				19'h5f826: begin
					target_register_o = 1'b1;
					register_select_o[REG_BRTB] = 1'b1;
				end
				19'h5f828: begin
					target_register_o = 1'b1;
					register_select_o[REG_BRTC] = 1'b1;
				end
				19'h5f82a: begin
					target_register_o = 1'b1;
					register_select_o[REG_REST] = 1'b1;
				end
				19'h5f82e: begin
					target_register_o = 1'b1;
					register_select_o[REG_FRMCYC] = 1'b1;
				end
				19'h5f830: begin
					target_register_o = 1'b1;
					register_select_o[REG_CTA] = 1'b1;
				end
				19'h5f840: begin
					target_register_o = 1'b1;
					register_select_o[REG_XPSTTS] = 1'b1;
				end
				19'h5f842: begin
					target_register_o = 1'b1;
					register_select_o[REG_XPCTRL] = 1'b1;
				end
				19'h5f844: begin
					target_register_o = 1'b1;
					register_select_o[REG_VER] = 1'b1;
				end
				19'h5f848: begin
					target_register_o = 1'b1;
					register_select_o[REG_SPT0] = 1'b1;
				end
				19'h5f84a: begin
					target_register_o = 1'b1;
					register_select_o[REG_SPT1] = 1'b1;
				end
				19'h5f84c: begin
					target_register_o = 1'b1;
					register_select_o[REG_SPT2] = 1'b1;
				end
				19'h5f84e: begin
					target_register_o = 1'b1;
					register_select_o[REG_SPT3] = 1'b1;
				end
				19'h5f860: begin
					target_register_o = 1'b1;
					register_select_o[REG_GPLT0] = 1'b1;
				end
				19'h5f862: begin
					target_register_o = 1'b1;
					register_select_o[REG_GPLT1] = 1'b1;
				end
				19'h5f864: begin
					target_register_o = 1'b1;
					register_select_o[REG_GPLT2] = 1'b1;
				end
				19'h5f866: begin
					target_register_o = 1'b1;
					register_select_o[REG_GPLT3] = 1'b1;
				end
				19'h5f868: begin
					target_register_o = 1'b1;
					register_select_o[REG_JPLT0] = 1'b1;
				end
				19'h5f86a: begin
					target_register_o = 1'b1;
					register_select_o[REG_JPLT1] = 1'b1;
				end
				19'h5f86c: begin
					target_register_o = 1'b1;
					register_select_o[REG_JPLT2] = 1'b1;
				end
				19'h5f86e: begin
					target_register_o = 1'b1;
					register_select_o[REG_JPLT3] = 1'b1;
				end
				19'h5f870: begin
					target_register_o = 1'b1;
					register_select_o[REG_BKCOL] = 1'b1;
				end
				default: begin
				end
			endcase

			if (target_register_o) begin
				target_unmapped_o = 1'b0;
			end
		end
	end

`ifdef VERILATOR
	// Ignore these bits to repeat the map every 0x80000 bytes.
	/* verilator lint_off UNUSED */
	wire _unused_address_ok = &{1'b0, address_i[23:19], 1'b0};
	/* verilator lint_on UNUSED */
`endif

endmodule

module vip_event_detector
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire [5:0]  savestate_state_addr_i,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [63:0] savestate_state_wdata_i,
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire        savestate_state_wren_i,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire        sim_snapshot_restore_commit_i,
	input  wire        sim_snapshot_restore_apply_i,
	input  wire [3647:0] sim_snapshot_restore_packet_i,
`endif
`endif

	input  wire        fclk_i,
	input  wire        gclk_i,
	input  wire        left_busy_i,
	input  wire        right_busy_i,
	input  wire        sbout_i,
	input  wire [4:0]  sbcount_i,
	input  wire [4:0]  sbcmp_i,
	input  wire        xp_busy_i,
	input  wire        overtime_i,

	// Silicon unknown: SCANERR timing is undocumented. Accept only a qualified pulse.
	input  wire        scanerr_event_i,

	output reg  [15:0] event_o,
	output wire [6:0]  event_history_o,
	output wire        levels_coherent_o
);

	reg fclk_prev_q;
	reg gclk_prev_q;
	reg left_busy_prev_q;
	reg right_busy_prev_q;
	reg sbout_prev_q;
	reg xp_busy_prev_q;
	reg overtime_prev_q;

	assign event_history_o = {
		overtime_prev_q,
		xp_busy_prev_q,
		sbout_prev_q,
		right_busy_prev_q,
		left_busy_prev_q,
		gclk_prev_q,
		fclk_prev_q
	};

	// Snapshot edge history only when it matches the stable source levels.
	assign levels_coherent_o =
		(fclk_prev_q == fclk_i) &&
		(gclk_prev_q == gclk_i) &&
		(left_busy_prev_q == left_busy_i) &&
		(right_busy_prev_q == right_busy_i) &&
		(sbout_prev_q == sbout_i) &&
		(xp_busy_prev_q == xp_busy_i) &&
		(overtime_prev_q == overtime_i);

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
				fclk_prev_q <= sim_snapshot_restore_packet_i[320];
				gclk_prev_q <= sim_snapshot_restore_packet_i[321];
				left_busy_prev_q <= sim_snapshot_restore_packet_i[322];
				right_busy_prev_q <= sim_snapshot_restore_packet_i[323];
				sbout_prev_q <= sim_snapshot_restore_packet_i[324];
				xp_busy_prev_q <= sim_snapshot_restore_packet_i[325];
				overtime_prev_q <= sim_snapshot_restore_packet_i[326];
				event_o <= 16'd0;
			end
		end else
`endif
`endif
		if (reset_i) begin
			fclk_prev_q <= fclk_i;
			gclk_prev_q <= gclk_i;
			left_busy_prev_q <= left_busy_i;
			right_busy_prev_q <= right_busy_i;
			sbout_prev_q <= sbout_i;
			xp_busy_prev_q <= xp_busy_i;
			overtime_prev_q <= overtime_i;
			event_o <= 16'd0;
		end else if (savestate_state_wren_i &&
			(savestate_state_addr_i == 6'd5)) begin
			fclk_prev_q <= savestate_state_wdata_i[0];
			gclk_prev_q <= savestate_state_wdata_i[1];
			left_busy_prev_q <= savestate_state_wdata_i[2];
			right_busy_prev_q <= savestate_state_wdata_i[3];
			sbout_prev_q <= savestate_state_wdata_i[4];
			xp_busy_prev_q <= savestate_state_wdata_i[5];
			overtime_prev_q <= savestate_state_wdata_i[6];
			event_o <= 16'd0;
		end else if (ce_i) begin
			event_o <= {
				!overtime_prev_q && overtime_i,
				xp_busy_prev_q && !xp_busy_i,
				!sbout_prev_q && sbout_i && (sbcount_i == sbcmp_i),
				8'd0,
				!fclk_prev_q && fclk_i,
				!gclk_prev_q && gclk_i,
				right_busy_prev_q && !right_busy_i,
				left_busy_prev_q && !left_busy_i,
				scanerr_event_i
			};

			fclk_prev_q <= fclk_i;
			gclk_prev_q <= gclk_i;
			left_busy_prev_q <= left_busy_i;
			right_busy_prev_q <= right_busy_i;
			sbout_prev_q <= sbout_i;
			xp_busy_prev_q <= xp_busy_i;
			overtime_prev_q <= overtime_i;
		end
	end

endmodule


module vip_register_bank
#(
	// Silicon unknown: same-edge software and hardware update priority is selectable.
	parameter integer WRITE_FIRST_ON_BOUNDARY = 0
)
(
	input  wire         clk_i,
	input  wire         reset_i,
	input  wire         ce_i,
	input  wire [5:0]   savestate_state_addr_i,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [63:0]  savestate_state_wdata_i,
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire         savestate_state_wren_i,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire         sim_snapshot_restore_commit_i,
	input  wire         sim_snapshot_restore_apply_i,
	input  wire [3647:0] sim_snapshot_restore_packet_i,
`endif
`endif

	// register_select_i is one-hot. write_data_i already includes byte-write behavior.
	input  wire [26:0]  register_select_i,
	input  wire         read_i,
	input  wire         write_commit_i,
	input  wire [15:0]  write_data_i,
	// DPRST seeds several display registers from the shared data bus.
	input  wire         host_bus_value_valid_i,
	input  wire [15:0]  host_bus_value_i,

	// vip_interrupt_bank owns interrupt state.
	input  wire [15:0]  int_pending_i,
	input  wire [15:0]  int_enable_i,
	output wire         intenb_write_o,
	output wire [15:0]  intenb_write_data_o,
	output wire         intclr_write_o,
	output wire [15:0]  intclr_write_data_o,
	output wire         dprst_o,
	output wire         dprst_seed_busy_o,
	output wire         xprst_o,

	// Live display and draw status.
	input  wire         dp_fclk_i,
	input  wire         dp_scan_ready_i,
	input  wire [3:0]   dp_busy_i,
	input  wire         xp_sbout_i,
	input  wire [4:0]   xp_sbcount_i,
	input  wire         xp_overtime_i,
	input  wire [1:0]   xp_busy_i,

	// CE-qualified control-consumer events.
	input  wire         fclk_rise_i,
	input  wire         display_column_boundary_i,
	input  wire         gclk_rise_i,
	input  wire         cta_left_latch_i,
	input  wire         cta_right_latch_i,
	input  wire [7:0]   cta_left_i,
	input  wire [7:0]   cta_right_i,
	input  wire         xp_draw_start_i,
	input  wire         xp_first_group_done_i,

	// Undefined, write-only, and reserved read bits return zero without a valid mask.
	output reg  [15:0]  read_data_o,
	output reg  [15:0]  read_defined_mask_o,
	output reg          read_value_defined_o,
	output wire         read_response_o,
	output wire         register_select_valid_o,
	output wire         write_handled_o,
	output wire         static_access_undefined_o,
	output wire         boundary_collision_o,

	// Programmed controls and staged consumer values.
	output wire         dp_lock_o,
	output wire         dp_synce_program_o,
	output wire         dp_synce_active_o,
	output wire         dp_refresh_o,
	output wire         dp_display_program_o,
	output wire         dp_display_active_o,
	output wire [4:0]   xp_sbcmp_o,
	output wire         xp_enable_o,
	output wire [31:0]  brightness_register_o,
	output wire [31:0]  brightness_active_o,
	output wire [3:0]   frmcyc_register_o,
	output wire [3:0]   frmcyc_active_o,
	output wire [15:0]  cta_o,
	output wire [39:0]  spt_register_o,
	output wire [39:0]  spt_active_o,
	output wire [31:0]  gplt_register_o,
	output wire [31:0]  gplt_active_o,
	output wire [31:0]  jplt_register_o,
	output wire [31:0]  jplt_active_o,
	output wire [1:0]   bkcol_register_o,
	output wire [1:0]   bkcol_active_o,
	output wire         bkcol_pending_o,
	output wire         bkcol_wait_first_group_o,
	output wire         bkcol_update_pending_o
);

	localparam WRITE_FIRST = (WRITE_FIRST_ON_BOUNDARY != 0);

	localparam [15:0] INT_VALID_MASK = 16'he01f;

	localparam [4:0] REG_INTPND = 5'd0;
	localparam [4:0] REG_INTENB = 5'd1;
	localparam [4:0] REG_INTCLR = 5'd2;
	localparam [4:0] REG_DPSTTS = 5'd3;
	localparam [4:0] REG_DPCTRL = 5'd4;
	localparam [4:0] REG_BRTA = 5'd5;
	localparam [4:0] REG_BRTB = 5'd6;
	localparam [4:0] REG_BRTC = 5'd7;
	localparam [4:0] REG_REST = 5'd8;
	localparam [4:0] REG_FRMCYC = 5'd9;
	localparam [4:0] REG_CTA = 5'd10;
	localparam [4:0] REG_XPSTTS = 5'd11;
	localparam [4:0] REG_XPCTRL = 5'd12;
	localparam [4:0] REG_VER = 5'd13;
	localparam [4:0] REG_SPT0 = 5'd14;
	localparam [4:0] REG_SPT1 = 5'd15;
	localparam [4:0] REG_SPT2 = 5'd16;
	localparam [4:0] REG_SPT3 = 5'd17;
	localparam [4:0] REG_GPLT0 = 5'd18;
	localparam [4:0] REG_GPLT1 = 5'd19;
	localparam [4:0] REG_GPLT2 = 5'd20;
	localparam [4:0] REG_GPLT3 = 5'd21;
	localparam [4:0] REG_JPLT0 = 5'd22;
	localparam [4:0] REG_JPLT1 = 5'd23;
	localparam [4:0] REG_JPLT2 = 5'd24;
	localparam [4:0] REG_JPLT3 = 5'd25;
	localparam [4:0] REG_BKCOL = 5'd26;

	reg [4:0] register_index_t;
	reg       register_select_valid_t;

	reg       dp_lock_q;
	reg       dp_synce_program_q;
	reg       dp_synce_active_q;
	reg       dp_refresh_q;
	reg       dp_display_program_q;
	reg       dp_display_active_q;
	reg [4:0] xp_sbcmp_q;
	reg       xp_enable_q;

	reg [7:0] brta_q;
	reg [7:0] brtb_q;
	reg [7:0] brtc_q;
	reg [7:0] rest_q;
	reg [7:0] brta_active_q;
	reg [7:0] brtb_active_q;
	reg [7:0] brtc_active_q;
	reg [7:0] rest_active_q;
	reg [3:0] frmcyc_q;
	reg [3:0] frmcyc_active_q;
	reg [7:0] cta_left_q;
	reg [7:0] cta_right_q;
	reg [1:0] dprst_seed_count_q;
	reg [15:0] dprst_seed_q;

	reg [9:0] spt0_q;
	reg [9:0] spt1_q;
	reg [9:0] spt2_q;
	reg [9:0] spt3_q;
	reg [9:0] spt0_active_q;
	reg [9:0] spt1_active_q;
	reg [9:0] spt2_active_q;
	reg [9:0] spt3_active_q;
	reg [7:0] gplt0_q;
	reg [7:0] gplt1_q;
	reg [7:0] gplt2_q;
	reg [7:0] gplt3_q;
	reg [7:0] gplt0_active_q;
	reg [7:0] gplt1_active_q;
	reg [7:0] gplt2_active_q;
	reg [7:0] gplt3_active_q;
	reg [7:0] jplt0_q;
	reg [7:0] jplt1_q;
	reg [7:0] jplt2_q;
	reg [7:0] jplt3_q;
	reg [7:0] jplt0_active_q;
	reg [7:0] jplt1_active_q;
	reg [7:0] jplt2_active_q;
	reg [7:0] jplt3_active_q;
	reg [1:0] bkcol_q;
	reg [1:0] bkcol_active_q;
	reg       bkcol_pending_q;
	reg       bkcol_wait_first_group_q;

	// Accept only an exact one-hot register select.
	always @* begin
		register_index_t = REG_INTPND;
		register_select_valid_t = 1'b1;
		case (register_select_i)
			27'h0000001: register_index_t = REG_INTPND;
			27'h0000002: register_index_t = REG_INTENB;
			27'h0000004: register_index_t = REG_INTCLR;
			27'h0000008: register_index_t = REG_DPSTTS;
			27'h0000010: register_index_t = REG_DPCTRL;
			27'h0000020: register_index_t = REG_BRTA;
			27'h0000040: register_index_t = REG_BRTB;
			27'h0000080: register_index_t = REG_BRTC;
			27'h0000100: register_index_t = REG_REST;
			27'h0000200: register_index_t = REG_FRMCYC;
			27'h0000400: register_index_t = REG_CTA;
			27'h0000800: register_index_t = REG_XPSTTS;
			27'h0001000: register_index_t = REG_XPCTRL;
			27'h0002000: register_index_t = REG_VER;
			27'h0004000: register_index_t = REG_SPT0;
			27'h0008000: register_index_t = REG_SPT1;
			27'h0010000: register_index_t = REG_SPT2;
			27'h0020000: register_index_t = REG_SPT3;
			27'h0040000: register_index_t = REG_GPLT0;
			27'h0080000: register_index_t = REG_GPLT1;
			27'h0100000: register_index_t = REG_GPLT2;
			27'h0200000: register_index_t = REG_GPLT3;
			27'h0400000: register_index_t = REG_JPLT0;
			27'h0800000: register_index_t = REG_JPLT1;
			27'h1000000: register_index_t = REG_JPLT2;
			27'h2000000: register_index_t = REG_JPLT3;
			27'h4000000: register_index_t = REG_BKCOL;
			default: begin
				register_select_valid_t = 1'b0;
			end
		endcase
	end

	wire static_register_w = register_select_valid_t &&
		(register_index_t >= REG_VER);
	wire xp_active_w = |xp_busy_i;
	// Silicon unknown: writes during XP are unsafe but may not be blocked. Accept
	// them for the next draw and flag the access as undefined.
	wire static_access_undefined_w = (read_i || write_commit_i) &&
		static_register_w && xp_active_w;
	wire write_allowed_w = write_commit_i && register_select_valid_t &&
		!reset_i;

	wire intenb_write_w = write_allowed_w && (register_index_t == REG_INTENB);
	wire intclr_write_w = write_allowed_w && (register_index_t == REG_INTCLR);
	wire dpctrl_write_w = write_allowed_w && (register_index_t == REG_DPCTRL);
	wire brta_write_w = write_allowed_w && (register_index_t == REG_BRTA);
	wire brtb_write_w = write_allowed_w && (register_index_t == REG_BRTB);
	wire brtc_write_w = write_allowed_w && (register_index_t == REG_BRTC);
	wire rest_write_w = write_allowed_w && (register_index_t == REG_REST);
	wire frmcyc_write_w = write_allowed_w && (register_index_t == REG_FRMCYC);
	wire xpctrl_write_w = write_allowed_w && (register_index_t == REG_XPCTRL);
	wire spt0_write_w = write_allowed_w && (register_index_t == REG_SPT0);
	wire spt1_write_w = write_allowed_w && (register_index_t == REG_SPT1);
	wire spt2_write_w = write_allowed_w && (register_index_t == REG_SPT2);
	wire spt3_write_w = write_allowed_w && (register_index_t == REG_SPT3);
	wire gplt0_write_w = write_allowed_w && (register_index_t == REG_GPLT0);
	wire gplt1_write_w = write_allowed_w && (register_index_t == REG_GPLT1);
	wire gplt2_write_w = write_allowed_w && (register_index_t == REG_GPLT2);
	wire gplt3_write_w = write_allowed_w && (register_index_t == REG_GPLT3);
	wire jplt0_write_w = write_allowed_w && (register_index_t == REG_JPLT0);
	wire jplt1_write_w = write_allowed_w && (register_index_t == REG_JPLT1);
	wire jplt2_write_w = write_allowed_w && (register_index_t == REG_JPLT2);
	wire jplt3_write_w = write_allowed_w && (register_index_t == REG_JPLT3);
	wire bkcol_write_w = write_allowed_w && (register_index_t == REG_BKCOL);

	wire brightness_write_w = brta_write_w || brtb_write_w ||
		brtc_write_w || rest_write_w;
	wire drawing_static_write_w = spt0_write_w || spt1_write_w ||
		spt2_write_w || spt3_write_w || gplt0_write_w ||
		gplt1_write_w || gplt2_write_w || gplt3_write_w ||
		jplt0_write_w || jplt1_write_w || jplt2_write_w ||
		jplt3_write_w || bkcol_write_w;

	assign register_select_valid_o = register_select_valid_t;
	assign read_response_o = read_i;
	assign write_handled_o = ce_i && write_allowed_w;
	assign static_access_undefined_o = static_access_undefined_w;

	assign intenb_write_o = ce_i && intenb_write_w;
	assign intenb_write_data_o = write_data_i & INT_VALID_MASK;
	assign intclr_write_o = ce_i && intclr_write_w;
	assign intclr_write_data_o = write_data_i & INT_VALID_MASK;
	assign dprst_o = ce_i && dpctrl_write_w && write_data_i[0];
	assign dprst_seed_busy_o = dprst_seed_count_q != 2'd0;
	assign xprst_o = ce_i && xpctrl_write_w && write_data_i[0];

	assign boundary_collision_o = ce_i && (
		(dpctrl_write_w && (fclk_rise_i || cta_left_latch_i || cta_right_latch_i)) ||
		(brightness_write_w && display_column_boundary_i) ||
		(frmcyc_write_w && gclk_rise_i) ||
		(drawing_static_write_w && xp_draw_start_i)
	);

	// Reads use registered state. WO, W1C, malformed, and unmapped selects are undefined.
	always @* begin
		read_data_o = 16'd0;
		read_defined_mask_o = 16'd0;
		read_value_defined_o = 1'b0;
		if (read_i && register_select_valid_t && !static_access_undefined_w) begin
			case (register_index_t)
				REG_INTPND: begin
					read_data_o = int_pending_i & INT_VALID_MASK;
					read_defined_mask_o = INT_VALID_MASK;
					read_value_defined_o = 1'b1;
				end
				REG_INTENB: begin
					read_data_o = int_enable_i & INT_VALID_MASK;
					read_defined_mask_o = INT_VALID_MASK;
					read_value_defined_o = 1'b1;
				end
				REG_DPSTTS: begin
					read_data_o = {
						5'd0,
						dp_lock_q,
						dp_synce_active_q,
						dp_refresh_q,
						dp_fclk_i,
						dp_scan_ready_i,
						dp_busy_i,
						dp_display_active_q,
						1'b0
					};
					read_defined_mask_o = 16'h07fe;
					read_value_defined_o = 1'b1;
				end
				REG_BRTA: begin
					read_data_o = {8'd0, brta_q};
					read_defined_mask_o = 16'h00ff;
					read_value_defined_o = 1'b1;
				end
				REG_BRTB: begin
					read_data_o = {8'd0, brtb_q};
					read_defined_mask_o = 16'h00ff;
					read_value_defined_o = 1'b1;
				end
				REG_BRTC: begin
					read_data_o = {8'd0, brtc_q};
					read_defined_mask_o = 16'h00ff;
					read_value_defined_o = 1'b1;
				end
				REG_REST: begin
					read_data_o = {8'd0, rest_q};
					read_defined_mask_o = 16'h00ff;
					read_value_defined_o = 1'b1;
				end
				REG_FRMCYC: begin
					read_data_o = {12'd0, frmcyc_q};
					read_defined_mask_o = 16'h000f;
					read_value_defined_o = 1'b1;
				end
				REG_CTA: begin
					read_data_o = {cta_right_q, cta_left_q};
					read_defined_mask_o = 16'hffff;
					read_value_defined_o = 1'b1;
				end
				REG_XPSTTS: begin
					read_data_o = {
						xp_sbout_i,
						2'd0,
						xp_sbcount_i,
						3'd0,
						xp_overtime_i,
						xp_busy_i,
						xp_enable_q,
						1'b0
					};
					read_defined_mask_o = 16'h9f1e;
					read_value_defined_o = 1'b1;
				end
				REG_VER: begin
					read_data_o = 16'd2;
					read_defined_mask_o = 16'h001f;
					read_value_defined_o = 1'b1;
				end
				REG_SPT0: begin
					read_data_o = {6'd0, spt0_q};
					read_defined_mask_o = 16'h03ff;
					read_value_defined_o = 1'b1;
				end
				REG_SPT1: begin
					read_data_o = {6'd0, spt1_q};
					read_defined_mask_o = 16'h03ff;
					read_value_defined_o = 1'b1;
				end
				REG_SPT2: begin
					read_data_o = {6'd0, spt2_q};
					read_defined_mask_o = 16'h03ff;
					read_value_defined_o = 1'b1;
				end
				REG_SPT3: begin
					read_data_o = {6'd0, spt3_q};
					read_defined_mask_o = 16'h03ff;
					read_value_defined_o = 1'b1;
				end
				REG_GPLT0: begin
					read_data_o = {8'd0, gplt0_q};
					read_defined_mask_o = 16'h00fc;
					read_value_defined_o = 1'b1;
				end
				REG_GPLT1: begin
					read_data_o = {8'd0, gplt1_q};
					read_defined_mask_o = 16'h00fc;
					read_value_defined_o = 1'b1;
				end
				REG_GPLT2: begin
					read_data_o = {8'd0, gplt2_q};
					read_defined_mask_o = 16'h00fc;
					read_value_defined_o = 1'b1;
				end
				REG_GPLT3: begin
					read_data_o = {8'd0, gplt3_q};
					read_defined_mask_o = 16'h00fc;
					read_value_defined_o = 1'b1;
				end
				REG_JPLT0: begin
					read_data_o = {8'd0, jplt0_q};
					read_defined_mask_o = 16'h00fc;
					read_value_defined_o = 1'b1;
				end
				REG_JPLT1: begin
					read_data_o = {8'd0, jplt1_q};
					read_defined_mask_o = 16'h00fc;
					read_value_defined_o = 1'b1;
				end
				REG_JPLT2: begin
					read_data_o = {8'd0, jplt2_q};
					read_defined_mask_o = 16'h00fc;
					read_value_defined_o = 1'b1;
				end
				REG_JPLT3: begin
					read_data_o = {8'd0, jplt3_q};
					read_defined_mask_o = 16'h00fc;
					read_value_defined_o = 1'b1;
				end
				REG_BKCOL: begin
					read_data_o = {14'd0, bkcol_q};
					read_defined_mask_o = 16'h0003;
					read_value_defined_o = 1'b1;
				end
				default: begin
					// INTCLR, DPCTRL, and XPCTRL reads are undefined.
				end
			endcase
		end
	end

	// Reset unknown FPGA state to zero. Only documented registers are guarantees.
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
				dp_lock_q <= sim_snapshot_restore_packet_i[522];
				dp_synce_program_q <= sim_snapshot_restore_packet_i[521];
				dp_synce_active_q <= sim_snapshot_restore_packet_i[585];
				dp_refresh_q <= sim_snapshot_restore_packet_i[520];
				dp_display_program_q <= sim_snapshot_restore_packet_i[513];
				dp_display_active_q <= sim_snapshot_restore_packet_i[577];
				xp_sbcmp_q <= sim_snapshot_restore_packet_i[1356:1352];
				xp_enable_q <= sim_snapshot_restore_packet_i[1345];
				brta_q <= sim_snapshot_restore_packet_i[647:640];
				brtb_q <= sim_snapshot_restore_packet_i[775:768];
				brtc_q <= sim_snapshot_restore_packet_i[903:896];
				rest_q <= sim_snapshot_restore_packet_i[1031:1024];
				brta_active_q <= sim_snapshot_restore_packet_i[711:704];
				brtb_active_q <= sim_snapshot_restore_packet_i[839:832];
				brtc_active_q <= sim_snapshot_restore_packet_i[967:960];
				rest_active_q <= sim_snapshot_restore_packet_i[1095:1088];
				frmcyc_q <= sim_snapshot_restore_packet_i[1155:1152];
				frmcyc_active_q <= sim_snapshot_restore_packet_i[1219:1216];
				cta_left_q <= sim_snapshot_restore_packet_i[1287:1280];
				cta_right_q <= sim_snapshot_restore_packet_i[1295:1288];
				spt0_q <= sim_snapshot_restore_packet_i[1417:1408];
				spt1_q <= sim_snapshot_restore_packet_i[1545:1536];
				spt2_q <= sim_snapshot_restore_packet_i[1673:1664];
				spt3_q <= sim_snapshot_restore_packet_i[1801:1792];
				spt0_active_q <= sim_snapshot_restore_packet_i[1481:1472];
				spt1_active_q <= sim_snapshot_restore_packet_i[1609:1600];
				spt2_active_q <= sim_snapshot_restore_packet_i[1737:1728];
				spt3_active_q <= sim_snapshot_restore_packet_i[1865:1856];
				gplt0_q <= sim_snapshot_restore_packet_i[1927:1920];
				gplt1_q <= sim_snapshot_restore_packet_i[2055:2048];
				gplt2_q <= sim_snapshot_restore_packet_i[2183:2176];
				gplt3_q <= sim_snapshot_restore_packet_i[2311:2304];
				gplt0_active_q <= sim_snapshot_restore_packet_i[1991:1984];
				gplt1_active_q <= sim_snapshot_restore_packet_i[2119:2112];
				gplt2_active_q <= sim_snapshot_restore_packet_i[2247:2240];
				gplt3_active_q <= sim_snapshot_restore_packet_i[2375:2368];
				jplt0_q <= sim_snapshot_restore_packet_i[2439:2432];
				jplt1_q <= sim_snapshot_restore_packet_i[2567:2560];
				jplt2_q <= sim_snapshot_restore_packet_i[2695:2688];
				jplt3_q <= sim_snapshot_restore_packet_i[2823:2816];
				jplt0_active_q <= sim_snapshot_restore_packet_i[2503:2496];
				jplt1_active_q <= sim_snapshot_restore_packet_i[2631:2624];
				jplt2_active_q <= sim_snapshot_restore_packet_i[2759:2752];
				jplt3_active_q <= sim_snapshot_restore_packet_i[2887:2880];
				bkcol_q <= sim_snapshot_restore_packet_i[2945:2944];
				bkcol_active_q <= sim_snapshot_restore_packet_i[3009:3008];
				bkcol_pending_q <= sim_snapshot_restore_packet_i[3072];
				bkcol_wait_first_group_q <= sim_snapshot_restore_packet_i[3073];
				// Snapshots wait until DPRST seeding finishes.
				dprst_seed_count_q <= 2'd0;
				dprst_seed_q <= 16'd0;
			end
		end else
`endif
`endif
		if (reset_i) begin
			dp_lock_q <= 1'b0;
			dp_synce_program_q <= 1'b0;
			dp_synce_active_q <= 1'b0;
			dp_refresh_q <= 1'b0;
			dp_display_program_q <= 1'b0;
			dp_display_active_q <= 1'b0;
			xp_sbcmp_q <= 5'd0;
			xp_enable_q <= 1'b0;
			brta_q <= 8'd0;
			brtb_q <= 8'd0;
			brtc_q <= 8'd0;
			rest_q <= 8'd0;
			brta_active_q <= 8'd0;
			brtb_active_q <= 8'd0;
			brtc_active_q <= 8'd0;
			rest_active_q <= 8'd0;
			frmcyc_q <= 4'd0;
			frmcyc_active_q <= 4'd0;
			cta_left_q <= 8'd0;
			cta_right_q <= 8'd0;
			dprst_seed_count_q <= 2'd0;
			dprst_seed_q <= 16'd0;
			spt0_q <= 10'd0;
			spt1_q <= 10'd0;
			spt2_q <= 10'd0;
			spt3_q <= 10'd0;
			spt0_active_q <= 10'd0;
			spt1_active_q <= 10'd0;
			spt2_active_q <= 10'd0;
			spt3_active_q <= 10'd0;
			gplt0_q <= 8'd0;
			gplt1_q <= 8'd0;
			gplt2_q <= 8'd0;
			gplt3_q <= 8'd0;
			gplt0_active_q <= 8'd0;
			gplt1_active_q <= 8'd0;
			gplt2_active_q <= 8'd0;
			gplt3_active_q <= 8'd0;
			jplt0_q <= 8'd0;
			jplt1_q <= 8'd0;
			jplt2_q <= 8'd0;
			jplt3_q <= 8'd0;
			jplt0_active_q <= 8'd0;
			jplt1_active_q <= 8'd0;
			jplt2_active_q <= 8'd0;
			jplt3_active_q <= 8'd0;
			bkcol_q <= 2'd0;
			bkcol_active_q <= 2'd0;
			bkcol_pending_q <= 1'b0;
			bkcol_wait_first_group_q <= 1'b0;
		end else if (savestate_state_wren_i) begin
			case (savestate_state_addr_i)
				6'd8: begin
					dp_display_program_q <= savestate_state_wdata_i[1];
					dp_refresh_q <= savestate_state_wdata_i[8];
					dp_synce_program_q <= savestate_state_wdata_i[9];
					dp_lock_q <= savestate_state_wdata_i[10];
				end
				6'd9: begin
					dp_display_active_q <= savestate_state_wdata_i[1];
					dp_synce_active_q <= savestate_state_wdata_i[9];
				end
				6'd10: brta_q <= savestate_state_wdata_i[7:0];
				6'd11: brta_active_q <= savestate_state_wdata_i[7:0];
				6'd12: brtb_q <= savestate_state_wdata_i[7:0];
				6'd13: brtb_active_q <= savestate_state_wdata_i[7:0];
				6'd14: brtc_q <= savestate_state_wdata_i[7:0];
				6'd15: brtc_active_q <= savestate_state_wdata_i[7:0];
				6'd16: rest_q <= savestate_state_wdata_i[7:0];
				6'd17: rest_active_q <= savestate_state_wdata_i[7:0];
				6'd18: frmcyc_q <= savestate_state_wdata_i[3:0];
				6'd19: frmcyc_active_q <= savestate_state_wdata_i[3:0];
				6'd20: begin
					cta_left_q <= savestate_state_wdata_i[7:0];
					cta_right_q <= savestate_state_wdata_i[15:8];
				end
				6'd21: begin
					xp_enable_q <= savestate_state_wdata_i[1];
					xp_sbcmp_q <= savestate_state_wdata_i[12:8];
				end
				6'd22: spt0_q <= savestate_state_wdata_i[9:0];
				6'd23: spt0_active_q <= savestate_state_wdata_i[9:0];
				6'd24: spt1_q <= savestate_state_wdata_i[9:0];
				6'd25: spt1_active_q <= savestate_state_wdata_i[9:0];
				6'd26: spt2_q <= savestate_state_wdata_i[9:0];
				6'd27: spt2_active_q <= savestate_state_wdata_i[9:0];
				6'd28: spt3_q <= savestate_state_wdata_i[9:0];
				6'd29: spt3_active_q <= savestate_state_wdata_i[9:0];
				6'd30: gplt0_q <= savestate_state_wdata_i[7:0];
				6'd31: gplt0_active_q <= savestate_state_wdata_i[7:0];
				6'd32: gplt1_q <= savestate_state_wdata_i[7:0];
				6'd33: gplt1_active_q <= savestate_state_wdata_i[7:0];
				6'd34: gplt2_q <= savestate_state_wdata_i[7:0];
				6'd35: gplt2_active_q <= savestate_state_wdata_i[7:0];
				6'd36: gplt3_q <= savestate_state_wdata_i[7:0];
				6'd37: gplt3_active_q <= savestate_state_wdata_i[7:0];
				6'd38: jplt0_q <= savestate_state_wdata_i[7:0];
				6'd39: jplt0_active_q <= savestate_state_wdata_i[7:0];
				6'd40: jplt1_q <= savestate_state_wdata_i[7:0];
				6'd41: jplt1_active_q <= savestate_state_wdata_i[7:0];
				6'd42: jplt2_q <= savestate_state_wdata_i[7:0];
				6'd43: jplt2_active_q <= savestate_state_wdata_i[7:0];
				6'd44: jplt3_q <= savestate_state_wdata_i[7:0];
				6'd45: jplt3_active_q <= savestate_state_wdata_i[7:0];
				6'd46: bkcol_q <= savestate_state_wdata_i[1:0];
				6'd47: bkcol_active_q <= savestate_state_wdata_i[1:0];
				6'd48: begin
					bkcol_pending_q <= savestate_state_wdata_i[0];
					bkcol_wait_first_group_q <= savestate_state_wdata_i[1];
				end
				default: begin
				end
			endcase
		end else if (ce_i) begin
			if (dpctrl_write_w) begin
				dp_lock_q <= write_data_i[10];
				dp_synce_program_q <= write_data_i[9];
				dp_refresh_q <= write_data_i[8];
				dp_display_program_q <= write_data_i[1];
			end
			if (xpctrl_write_w) begin
				xp_sbcmp_q <= write_data_i[12:8];
				xp_enable_q <= write_data_i[1];
			end
			// XPRST is an action pulse. The same write still stores XPEN.

			if (brta_write_w) begin
				brta_q <= write_data_i[7:0];
			end
			if (brtb_write_w) begin
				brtb_q <= write_data_i[7:0];
			end
			if (brtc_write_w) begin
				brtc_q <= write_data_i[7:0];
			end
			if (rest_write_w) begin
				rest_q <= write_data_i[7:0];
			end
			if (frmcyc_write_w) begin
				frmcyc_q <= write_data_i[3:0];
			end

			if (spt0_write_w) begin
				spt0_q <= write_data_i[9:0];
			end
			if (spt1_write_w) begin
				spt1_q <= write_data_i[9:0];
			end
			if (spt2_write_w) begin
				spt2_q <= write_data_i[9:0];
			end
			if (spt3_write_w) begin
				spt3_q <= write_data_i[9:0];
			end
			if (gplt0_write_w) begin
				gplt0_q <= write_data_i[7:0] & 8'hfc;
			end
			if (gplt1_write_w) begin
				gplt1_q <= write_data_i[7:0] & 8'hfc;
			end
			if (gplt2_write_w) begin
				gplt2_q <= write_data_i[7:0] & 8'hfc;
			end
			if (gplt3_write_w) begin
				gplt3_q <= write_data_i[7:0] & 8'hfc;
			end
			if (jplt0_write_w) begin
				jplt0_q <= write_data_i[7:0] & 8'hfc;
			end
			if (jplt1_write_w) begin
				jplt1_q <= write_data_i[7:0] & 8'hfc;
			end
			if (jplt2_write_w) begin
				jplt2_q <= write_data_i[7:0] & 8'hfc;
			end
			if (jplt3_write_w) begin
				jplt3_q <= write_data_i[7:0] & 8'hfc;
			end
			if (bkcol_write_w) begin
				bkcol_q <= write_data_i[1:0];
				bkcol_pending_q <= 1'b1;
			end

			if (fclk_rise_i) begin
				if (WRITE_FIRST && dpctrl_write_w) begin
					dp_synce_active_q <= write_data_i[9];
					dp_display_active_q <= write_data_i[1];
				end else begin
					dp_synce_active_q <= dp_synce_program_q;
					dp_display_active_q <= dp_display_program_q;
				end
			end
			if (display_column_boundary_i) begin
				brta_active_q <= (WRITE_FIRST && brta_write_w) ?
					write_data_i[7:0] : brta_q;
				brtb_active_q <= (WRITE_FIRST && brtb_write_w) ?
					write_data_i[7:0] : brtb_q;
				brtc_active_q <= (WRITE_FIRST && brtc_write_w) ?
					write_data_i[7:0] : brtc_q;
				rest_active_q <= (WRITE_FIRST && rest_write_w) ?
					write_data_i[7:0] : rest_q;
			end
			if (gclk_rise_i) begin
				frmcyc_active_q <= (WRITE_FIRST && frmcyc_write_w) ?
					write_data_i[3:0] : frmcyc_q;
			end

			if (cta_left_latch_i) begin
				if (WRITE_FIRST && dpctrl_write_w) begin
					if (!write_data_i[10]) begin
						cta_left_q <= cta_left_i;
					end
				end else if (!dp_lock_q) begin
					cta_left_q <= cta_left_i;
				end
			end
			if (cta_right_latch_i) begin
				if (WRITE_FIRST && dpctrl_write_w) begin
					if (!write_data_i[10]) begin
						cta_right_q <= cta_right_i;
					end
				end else if (!dp_lock_q) begin
					cta_right_q <= cta_right_i;
				end
			end

			if (xp_draw_start_i) begin
				spt0_active_q <= (WRITE_FIRST && spt0_write_w) ?
					write_data_i[9:0] : spt0_q;
				spt1_active_q <= (WRITE_FIRST && spt1_write_w) ?
					write_data_i[9:0] : spt1_q;
				spt2_active_q <= (WRITE_FIRST && spt2_write_w) ?
					write_data_i[9:0] : spt2_q;
				spt3_active_q <= (WRITE_FIRST && spt3_write_w) ?
					write_data_i[9:0] : spt3_q;
				gplt0_active_q <= (WRITE_FIRST && gplt0_write_w) ?
					(write_data_i[7:0] & 8'hfc) : gplt0_q;
				gplt1_active_q <= (WRITE_FIRST && gplt1_write_w) ?
					(write_data_i[7:0] & 8'hfc) : gplt1_q;
				gplt2_active_q <= (WRITE_FIRST && gplt2_write_w) ?
					(write_data_i[7:0] & 8'hfc) : gplt2_q;
				gplt3_active_q <= (WRITE_FIRST && gplt3_write_w) ?
					(write_data_i[7:0] & 8'hfc) : gplt3_q;
				jplt0_active_q <= (WRITE_FIRST && jplt0_write_w) ?
					(write_data_i[7:0] & 8'hfc) : jplt0_q;
				jplt1_active_q <= (WRITE_FIRST && jplt1_write_w) ?
					(write_data_i[7:0] & 8'hfc) : jplt1_q;
				jplt2_active_q <= (WRITE_FIRST && jplt2_write_w) ?
					(write_data_i[7:0] & 8'hfc) : jplt2_q;
				jplt3_active_q <= (WRITE_FIRST && jplt3_write_w) ?
					(write_data_i[7:0] & 8'hfc) : jplt3_q;

				if (bkcol_pending_q || (WRITE_FIRST && bkcol_write_w)) begin
					bkcol_wait_first_group_q <= 1'b1;
				end else begin
					bkcol_active_q <= bkcol_q;
					bkcol_wait_first_group_q <= 1'b0;
				end
			end
			if (xp_first_group_done_i && bkcol_wait_first_group_q) begin
				bkcol_active_q <= bkcol_q;
				bkcol_pending_q <= 1'b0;
				bkcol_wait_first_group_q <= 1'b0;
			end

			// Physical tests settled within three NVC cycles. Use that bound for DPRST.
			if (dprst_o) begin
				dprst_seed_count_q <= 2'd3;
				dprst_seed_q <= write_data_i;
			end else if (dprst_seed_count_q != 2'd0) begin
				if (host_bus_value_valid_i) begin
					dprst_seed_q <= host_bus_value_i;
				end
				if (dprst_seed_count_q == 2'd1) begin
					dprst_seed_count_q <= 2'd0;
					brta_q <= host_bus_value_valid_i ?
						host_bus_value_i[7:0] : dprst_seed_q[7:0];
					brtb_q <= host_bus_value_valid_i ?
						host_bus_value_i[7:0] : dprst_seed_q[7:0];
					brtc_q <= host_bus_value_valid_i ?
						host_bus_value_i[7:0] : dprst_seed_q[7:0];
					rest_q <= host_bus_value_valid_i ?
						host_bus_value_i[7:0] : dprst_seed_q[7:0];
					frmcyc_q <= host_bus_value_valid_i ?
						host_bus_value_i[3:0] : dprst_seed_q[3:0];
					cta_left_q <= host_bus_value_valid_i ?
						host_bus_value_i[7:0] : dprst_seed_q[7:0];
					cta_right_q <= host_bus_value_valid_i ?
						host_bus_value_i[15:8] : dprst_seed_q[15:8];
				end else begin
					dprst_seed_count_q <= dprst_seed_count_q - 2'd1;
				end
			end
		end
	end

	assign dp_lock_o = dp_lock_q;
	assign dp_synce_program_o = dp_synce_program_q;
	assign dp_synce_active_o = dp_synce_active_q;
	assign dp_refresh_o = dp_refresh_q;
	assign dp_display_program_o = dp_display_program_q;
	assign dp_display_active_o = dp_display_active_q;
	assign xp_sbcmp_o = xp_sbcmp_q;
	assign xp_enable_o = xp_enable_q;
	assign brightness_register_o = {rest_q, brtc_q, brtb_q, brta_q};
	assign brightness_active_o = {
		rest_active_q,
		brtc_active_q,
		brtb_active_q,
		brta_active_q
	};
	assign frmcyc_register_o = frmcyc_q;
	assign frmcyc_active_o = frmcyc_active_q;
	assign cta_o = {cta_right_q, cta_left_q};
	assign spt_register_o = {spt3_q, spt2_q, spt1_q, spt0_q};
	assign spt_active_o = {
		spt3_active_q,
		spt2_active_q,
		spt1_active_q,
		spt0_active_q
	};
	assign gplt_register_o = {gplt3_q, gplt2_q, gplt1_q, gplt0_q};
	assign gplt_active_o = {
		gplt3_active_q,
		gplt2_active_q,
		gplt1_active_q,
		gplt0_active_q
	};
	assign jplt_register_o = {jplt3_q, jplt2_q, jplt1_q, jplt0_q};
	assign jplt_active_o = {
		jplt3_active_q,
		jplt2_active_q,
		jplt1_active_q,
		jplt0_active_q
	};
	assign bkcol_register_o = bkcol_q;
	assign bkcol_active_o = bkcol_active_q;
	assign bkcol_pending_o = bkcol_pending_q;
	assign bkcol_wait_first_group_o = bkcol_wait_first_group_q;
	assign bkcol_update_pending_o = bkcol_pending_q || bkcol_wait_first_group_q;

endmodule

module vip_interrupt_bank
#(
	// Silicon unknown: same-edge event and clear priority is selectable; default set wins.
	parameter integer EVENT_SET_WINS = 1
)
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire [5:0]  savestate_state_addr_i,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [63:0] savestate_state_wdata_i,
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire        savestate_state_wren_i,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire        sim_snapshot_restore_commit_i,
	input  wire        sim_snapshot_restore_apply_i,
	input  wire [3647:0] sim_snapshot_restore_packet_i,
`endif
`endif

	input  wire [15:0] event_i,
	input  wire        intenb_write_i,
	input  wire [15:0] intenb_wdata_i,
	input  wire        intclr_write_i,
	input  wire [15:0] intclr_wdata_i,
	input  wire        dprst_i,
	input  wire        xprst_i,

	output wire [15:0] pending_o,
	output wire [15:0] enable_o,
	output wire        irq_o
);

	localparam [15:0] INT_VALID_MASK   = 16'he01f;
	localparam [15:0] DPRST_CLEAR_MASK = 16'h801f;
	localparam [15:0] XPRST_CLEAR_MASK = 16'he000;

	reg [15:0] pending_q;
	reg [15:0] enable_q;

	reg [15:0] pending_next_t;
	reg [15:0] enable_next_t;
	reg [15:0] pending_clear_t;
	reg [15:0] enable_clear_t;
	reg [15:0] event_masked_t;

	always @* begin
		pending_clear_t = 16'd0;
		enable_clear_t = 16'd0;
		event_masked_t = event_i & INT_VALID_MASK;

		if (intclr_write_i) begin
			pending_clear_t = pending_clear_t | (intclr_wdata_i & INT_VALID_MASK);
		end
		if (dprst_i) begin
			pending_clear_t = pending_clear_t | DPRST_CLEAR_MASK;
			enable_clear_t = enable_clear_t | DPRST_CLEAR_MASK;
		end
		if (xprst_i) begin
			pending_clear_t = pending_clear_t | XPRST_CLEAR_MASK;
			enable_clear_t = enable_clear_t | XPRST_CLEAR_MASK;
		end

		enable_next_t = enable_q;
		if (intenb_write_i) begin
			enable_next_t = intenb_wdata_i & INT_VALID_MASK;
		end
		enable_next_t = enable_next_t & ~enable_clear_t;

		if (EVENT_SET_WINS != 0) begin
			pending_next_t = (pending_q & ~pending_clear_t) | event_masked_t;
		end else begin
			pending_next_t = (pending_q | event_masked_t) & ~pending_clear_t;
		end
		pending_next_t = pending_next_t & INT_VALID_MASK;
	end

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
				pending_q <= sim_snapshot_restore_packet_i[399:384];
				enable_q <= sim_snapshot_restore_packet_i[463:448];
			end
		end else
`endif
`endif
		if (reset_i) begin
			pending_q <= 16'd0;
			enable_q <= 16'd0;
		end else if (savestate_state_wren_i) begin
			case (savestate_state_addr_i)
				6'd6: pending_q <= savestate_state_wdata_i[15:0] & INT_VALID_MASK;
				6'd7: enable_q <= savestate_state_wdata_i[15:0] & INT_VALID_MASK;
				default: begin
				end
			endcase
		end else if (ce_i) begin
			pending_q <= pending_next_t;
			enable_q <= enable_next_t;
		end
	end

	assign pending_o = pending_q;
	assign enable_o = enable_q;
	assign irq_o = |(pending_q & enable_q & INT_VALID_MASK);

endmodule

// CPU timing adapter for VIP memory requests.
//
// Capture a held host request on C1 and schedule the registered frontend READY
// for the configured public completion edge:
//
//   write: downstream launch/accept one CE before WRITE_TOTAL_CE
//   read:  downstream launch two CEs before READ_TOTAL_CE, followed by the
//          synchronous downstream response one CE before READ_TOTAL_CE
//
// The frontend registers acceptance/response into its CE-owned READY pulse, so
// the internal memory operation must lead the public boundary by one CE. Only
// CPU requests use these delays. Hold a launched command until accepted.
// A changed frontend epoch permits a zero-bubble successor; a held epoch may
// not replay until valid drops.

module vip_host_memory_timing
#(
	parameter [7:0] WRITE_TOTAL_CE = 8'd3,
	parameter [7:0] READ_TOTAL_CE = 8'd7
)
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,

	input  wire        upstream_valid_i,
	input  wire        upstream_cycle_i,
	input  wire        upstream_write_i,
	input  wire [15:0] upstream_addr_i,
	input  wire [15:0] upstream_wdata_i,
	input  wire [1:0]  upstream_byte_enable_i,
	output wire        upstream_accept_o,
	output wire        upstream_response_valid_o,
	output wire [15:0] upstream_response_data_o,

	output wire        downstream_valid_o,
	output wire        downstream_write_o,
	output wire [15:0] downstream_addr_o,
	output wire [15:0] downstream_wdata_o,
	output wire [1:0]  downstream_byte_enable_o,
	input  wire        downstream_accept_i,
	input  wire        downstream_response_valid_i,
	input  wire [15:0] downstream_response_data_i,

	output wire        busy_o
);

	localparam [1:0] STATE_IDLE = 2'd0;
	localparam [1:0] STATE_TIME = 2'd1;
	localparam [1:0] STATE_READ = 2'd2;
	localparam [1:0] STATE_REARM = 2'd3;

	reg [1:0] state_q;
	reg [7:0] elapsed_q;
	reg       token_cycle_q;
	reg       token_write_q;
	reg [15:0] token_addr_q;
	reg [15:0] token_wdata_q;
	reg [1:0] token_byte_enable_q;

	wire [7:0] launch_elapsed_w = token_write_q ?
		(WRITE_TOTAL_CE - 8'd2) : (READ_TOTAL_CE - 8'd3);
	wire launch_due_w = (state_q == STATE_TIME) &&
		(elapsed_q == launch_elapsed_w);
	wire downstream_handshake_w = ce_i && downstream_valid_o &&
		downstream_accept_i && !reset_i;
	wire upstream_response_w = ce_i && (state_q == STATE_READ) &&
		downstream_response_valid_i && !reset_i;

	// Do not gate valid with CE; hold it through stalls and pauses.
	assign downstream_valid_o = launch_due_w && !reset_i;
	assign downstream_write_o = token_write_q;
	assign downstream_addr_o = token_addr_q;
	assign downstream_wdata_o = token_wdata_q;
	assign downstream_byte_enable_o = token_byte_enable_q;

	// Sequential clients sample these on the handshake edge.
	assign upstream_accept_o = downstream_handshake_w;
	assign upstream_response_valid_o = upstream_response_w;
	assign upstream_response_data_o = downstream_response_data_i;
	assign busy_o = (state_q != STATE_IDLE);

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			elapsed_q <= 8'd0;
			token_cycle_q <= 1'b0;
			token_write_q <= 1'b0;
			token_addr_q <= 16'd0;
			token_wdata_q <= 16'd0;
			token_byte_enable_q <= 2'b00;
		end else if (ce_i) begin
			case (state_q)
				STATE_IDLE: begin
					if (upstream_valid_i) begin
						state_q <= STATE_TIME;
						elapsed_q <= 8'd1;
						token_cycle_q <= upstream_cycle_i;
						token_write_q <= upstream_write_i;
						token_addr_q <= upstream_addr_i;
						token_wdata_q <= upstream_wdata_i;
						token_byte_enable_q <=
							upstream_byte_enable_i;
					end
				end

				STATE_TIME: begin
					if (launch_due_w) begin
						if (downstream_accept_i) begin
							elapsed_q <= elapsed_q + 8'd1;
							if (token_write_q) begin
								state_q <= STATE_REARM;
							end else begin
								state_q <= STATE_READ;
							end
						end
					end else begin
						elapsed_q <= elapsed_q + 8'd1;
					end
				end

				STATE_READ: begin
					if (downstream_response_valid_i) begin
						elapsed_q <= 8'd0;
						if (upstream_valid_i) begin
							state_q <= STATE_REARM;
						end else begin
							state_q <= STATE_IDLE;
						end
					end
				end

				STATE_REARM: begin
					if (!upstream_valid_i) begin
						state_q <= STATE_IDLE;
						elapsed_q <= 8'd0;
					end else if (upstream_cycle_i != token_cycle_q) begin
						state_q <= STATE_TIME;
						elapsed_q <= 8'd1;
						token_cycle_q <= upstream_cycle_i;
						token_write_q <= upstream_write_i;
						token_addr_q <= upstream_addr_i;
						token_wdata_q <= upstream_wdata_i;
						token_byte_enable_q <=
							upstream_byte_enable_i;
					end
				end

				default: begin
					state_q <= STATE_IDLE;
					elapsed_q <= 8'd0;
				end
			endcase
		end
	end

`ifndef SYNTHESIS
	initial begin
		if (WRITE_TOTAL_CE < 8'd3) begin
			$error("vip_host_memory_timing WRITE_TOTAL_CE must be at least 3");
		end
		if (READ_TOTAL_CE < 8'd4) begin
			$error("vip_host_memory_timing READ_TOTAL_CE must be at least 4");
		end
	end
`endif

endmodule

// 128 KiB VIP memory store.
//
// Port A serves DP, XP, then CPU priority and returns reads one enabled edge
// later. Port B is a read-only observer outside arbitration.
//
// Different-address port accesses are independent. Same-address collisions are
// undefined and must be avoided by clients.

module vip_memory_store
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire        reserve_i,

	input  wire        dp_req_i,
	input  wire        dp_write_i,
	input  wire [15:0] dp_addr_i,
	input  wire [15:0] dp_wdata_i,
	input  wire [1:0]  dp_byte_enable_i,
	output wire        dp_accept_o,
	output wire        dp_resp_valid_o,
	output wire [15:0] dp_resp_data_o,

	input  wire        xp_req_i,
	input  wire        xp_write_i,
	input  wire [15:0] xp_addr_i,
	input  wire [15:0] xp_wdata_i,
	input  wire [1:0]  xp_byte_enable_i,
	output wire        xp_accept_o,
	output wire        xp_resp_valid_o,
	output wire [15:0] xp_resp_data_o,

	input  wire        cpu_req_i,
	input  wire        cpu_write_i,
	input  wire [15:0] cpu_addr_i,
	input  wire [15:0] cpu_wdata_i,
	input  wire [1:0]  cpu_byte_enable_i,
	output wire        cpu_accept_o,
	output wire        cpu_resp_valid_o,
	output wire [15:0] cpu_resp_data_o,

	input  wire        observer_ce_i,
	input  wire        observer_enable_i,
	input  wire [15:0] observer_addr_i,
	output wire [15:0] observer_rdata_o,
	output wire        observer_rvalid_o,

	// Paused byte access uses observer port B.
	input  wire        savestate_mem_active_i,
	input  wire [16:0] savestate_mem_addr_i,
	input  wire        savestate_mem_rden_i,
	input  wire        savestate_mem_wren_i,
	input  wire [7:0]  savestate_mem_wdata_i,
	output wire [7:0]  savestate_mem_rdata_o,

	// Physical transaction trace. Owner values are 0 none, 1 DP, 2 XP, 3 CPU.
	output wire        physical_accept_o,
	output wire        physical_write_o,
	output reg  [1:0]  physical_owner_o,
	output wire [15:0] physical_addr_o,
	output wire [15:0] physical_wdata_o,
	output wire [1:0]  physical_byte_enable_o,
	output wire        physical_resp_valid_o,
	output reg  [1:0]  physical_resp_owner_o,

	output wire        busy_o,
	output wire        read_pending_o,
	output wire        offer_held_o
);
	localparam [1:0] PHYSICAL_OWNER_NONE = 2'd0;
	localparam [1:0] PHYSICAL_OWNER_DP   = 2'd1;
	localparam [1:0] PHYSICAL_OWNER_XP   = 2'd2;
	localparam [1:0] PHYSICAL_OWNER_CPU  = 2'd3;

	wire        arb_mem_req_w;
	wire        arb_mem_write_w;
	wire [15:0] arb_mem_addr_w;
	wire [15:0] arb_mem_wdata_w;
	wire [1:0]  arb_mem_byte_enable_w;
	wire [15:0] ram_rdata_w;
	wire        ram_rvalid_w;
	wire [15:0] observer_rdata_w;
	wire        observer_rvalid_w;
	wire        physical_slot_accept_w = ce_i && arb_mem_req_w && !reserve_i;

	vip_logical_arbiter
	#(
		.ADDR_WIDTH(16),
		.DATA_WIDTH(16),
		.BYTE_ENABLE_WIDTH(2)
	)
	u_arbiter
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_i(ce_i),
		.dp_req_i(dp_req_i),
		.dp_write_i(dp_write_i),
		.dp_addr_i(dp_addr_i),
		.dp_wdata_i(dp_wdata_i),
		.dp_byte_enable_i(dp_byte_enable_i),
		.dp_accept_o(dp_accept_o),
		.dp_resp_valid_o(dp_resp_valid_o),
		.dp_resp_data_o(dp_resp_data_o),
		.xp_req_i(xp_req_i),
		.xp_write_i(xp_write_i),
		.xp_addr_i(xp_addr_i),
		.xp_wdata_i(xp_wdata_i),
		.xp_byte_enable_i(xp_byte_enable_i),
		.xp_accept_o(xp_accept_o),
		.xp_resp_valid_o(xp_resp_valid_o),
		.xp_resp_data_o(xp_resp_data_o),
		.cpu_req_i(cpu_req_i),
		.cpu_write_i(cpu_write_i),
		.cpu_addr_i(cpu_addr_i),
		.cpu_wdata_i(cpu_wdata_i),
		.cpu_byte_enable_i(cpu_byte_enable_i),
		.cpu_accept_o(cpu_accept_o),
		.cpu_resp_valid_o(cpu_resp_valid_o),
		.cpu_resp_data_o(cpu_resp_data_o),
		.mem_req_o(arb_mem_req_w),
		.mem_write_o(arb_mem_write_w),
		.mem_addr_o(arb_mem_addr_w),
		.mem_wdata_o(arb_mem_wdata_w),
		.mem_byte_enable_o(arb_mem_byte_enable_w),
		.mem_accept_i(!reserve_i),
		.mem_resp_valid_i(ram_rvalid_w),
		.mem_resp_data_i(ram_rdata_w),
		.read_pending_o(read_pending_o),
		.offer_held_o(offer_held_o)
	);

	vip_byte_lane_ram u_ram
	(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.ce_a_i(ce_i),
		.enable_a_i(physical_slot_accept_w),
		.addr_a_i(arb_mem_addr_w),
		.wren_a_i(arb_mem_write_w),
		.byte_enable_a_i(arb_mem_byte_enable_w),
		.wdata_a_i(arb_mem_wdata_w),
		.rdata_a_o(ram_rdata_w),
		.rvalid_a_o(ram_rvalid_w),
		.ce_b_i(observer_ce_i || savestate_mem_active_i),
		.allow_b_during_reset_i(savestate_mem_active_i),
		.enable_b_i(savestate_mem_active_i ?
			(savestate_mem_rden_i || savestate_mem_wren_i) :
			observer_enable_i),
		.addr_b_i(savestate_mem_active_i ?
			savestate_mem_addr_i[16:1] : observer_addr_i),
		.wren_b_i(savestate_mem_active_i && savestate_mem_wren_i),
		.byte_enable_b_i(savestate_mem_addr_i[0] ? 2'b10 : 2'b01),
		.wdata_b_i({savestate_mem_wdata_i, savestate_mem_wdata_i}),
		.rdata_b_o(observer_rdata_w),
		.rvalid_b_o(observer_rvalid_w)
	);

	assign observer_rdata_o = observer_rdata_w;
	assign observer_rvalid_o = observer_rvalid_w && !savestate_mem_active_i;
	assign savestate_mem_rdata_o = savestate_mem_addr_i[0] ?
		observer_rdata_w[15:8] : observer_rdata_w[7:0];

	assign busy_o = dp_req_i || xp_req_i || cpu_req_i || read_pending_o;
	assign physical_accept_o = dp_accept_o || xp_accept_o || cpu_accept_o;
	assign physical_write_o = arb_mem_write_w;
	assign physical_addr_o = arb_mem_addr_w;
	assign physical_wdata_o = arb_mem_wdata_w;
	assign physical_byte_enable_o = arb_mem_byte_enable_w;
	assign physical_resp_valid_o = dp_resp_valid_o || xp_resp_valid_o ||
		cpu_resp_valid_o;

	always @* begin
		physical_owner_o = PHYSICAL_OWNER_NONE;
		case ({cpu_accept_o, xp_accept_o, dp_accept_o})
			3'b001: physical_owner_o = PHYSICAL_OWNER_DP;
			3'b010: physical_owner_o = PHYSICAL_OWNER_XP;
			3'b100: physical_owner_o = PHYSICAL_OWNER_CPU;
			default: begin
			end
		endcase

		physical_resp_owner_o = PHYSICAL_OWNER_NONE;
		case ({cpu_resp_valid_o, xp_resp_valid_o, dp_resp_valid_o})
			3'b001: physical_resp_owner_o = PHYSICAL_OWNER_DP;
			3'b010: physical_resp_owner_o = PHYSICAL_OWNER_XP;
			3'b100: physical_resp_owner_o = PHYSICAL_OWNER_CPU;
			default: begin
			end
		endcase
	end

`ifndef SYNTHESIS
	// Simulation checks that trace data matches the real handshake.
	always @(posedge clk_i) begin
		if (!reset_i) begin
			if (physical_slot_accept_w != physical_accept_o) begin
				$fatal(1, "physical accept diverged from RAM port acceptance");
			end
			if (physical_accept_o && (!ce_i ||
				(physical_owner_o == PHYSICAL_OWNER_NONE))) begin
				$fatal(1, "physical accept is not CE/owner aligned");
			end
			if (!physical_accept_o &&
				(physical_owner_o != PHYSICAL_OWNER_NONE)) begin
				$fatal(1, "physical owner asserted without acceptance");
			end
			if (physical_resp_valid_o && (!ce_i ||
				(physical_resp_owner_o == PHYSICAL_OWNER_NONE))) begin
				$fatal(1, "physical response is not CE/owner aligned");
			end
			if (!physical_resp_valid_o &&
				(physical_resp_owner_o != PHYSICAL_OWNER_NONE)) begin
				$fatal(1, "physical response owner asserted without response");
			end
		end
	end
`endif

endmodule

module vip_logical_arbiter
#(
	parameter integer ADDR_WIDTH = 16,
	parameter integer DATA_WIDTH = 16,
	parameter integer BYTE_ENABLE_WIDTH = 2
)
(
	input  wire                  clk_i,
	input  wire                  reset_i,
	input  wire                  ce_i,

	input  wire                  dp_req_i,
	input  wire                  dp_write_i,
	input  wire [ADDR_WIDTH-1:0] dp_addr_i,
	input  wire [DATA_WIDTH-1:0] dp_wdata_i,
	input  wire [BYTE_ENABLE_WIDTH-1:0] dp_byte_enable_i,
	output reg                   dp_accept_o,
	output reg                   dp_resp_valid_o,
	output reg  [DATA_WIDTH-1:0] dp_resp_data_o,

	input  wire                  xp_req_i,
	input  wire                  xp_write_i,
	input  wire [ADDR_WIDTH-1:0] xp_addr_i,
	input  wire [DATA_WIDTH-1:0] xp_wdata_i,
	input  wire [BYTE_ENABLE_WIDTH-1:0] xp_byte_enable_i,
	output reg                   xp_accept_o,
	output reg                   xp_resp_valid_o,
	output reg  [DATA_WIDTH-1:0] xp_resp_data_o,

	input  wire                  cpu_req_i,
	input  wire                  cpu_write_i,
	input  wire [ADDR_WIDTH-1:0] cpu_addr_i,
	input  wire [DATA_WIDTH-1:0] cpu_wdata_i,
	input  wire [BYTE_ENABLE_WIDTH-1:0] cpu_byte_enable_i,
	output reg                   cpu_accept_o,
	output reg                   cpu_resp_valid_o,
	output reg  [DATA_WIDTH-1:0] cpu_resp_data_o,

	output reg                   mem_req_o,
	output reg                   mem_write_o,
	output reg  [ADDR_WIDTH-1:0] mem_addr_o,
	output reg  [DATA_WIDTH-1:0] mem_wdata_o,
	output reg  [BYTE_ENABLE_WIDTH-1:0] mem_byte_enable_o,
	input  wire                  mem_accept_i,
	input  wire                  mem_resp_valid_i,
	input  wire [DATA_WIDTH-1:0] mem_resp_data_i,

	output wire                  read_pending_o,
	output wire                  offer_held_o
);

	localparam [1:0] OWNER_DP   = 2'd0;
	localparam [1:0] OWNER_XP   = 2'd1;
	localparam [1:0] OWNER_CPU  = 2'd2;
	localparam [1:0] OWNER_NONE = 2'd3;

	reg       selected_valid_t;
	reg       selected_write_t;
	reg [1:0] selected_owner_t;
	reg [ADDR_WIDTH-1:0] selected_addr_t;
	reg [DATA_WIDTH-1:0] selected_wdata_t;
	reg [BYTE_ENABLE_WIDTH-1:0] selected_byte_enable_t;
	reg       held_valid_q;
	reg       held_write_q;
	reg [1:0] held_owner_q;
	reg [ADDR_WIDTH-1:0] held_addr_q;
	reg [DATA_WIDTH-1:0] held_wdata_q;
	reg [BYTE_ENABLE_WIDTH-1:0] held_byte_enable_q;

	reg       active_write_t;
	reg [1:0] active_owner_t;
	reg [ADDR_WIDTH-1:0] active_addr_t;
	reg [DATA_WIDTH-1:0] active_wdata_t;
	reg [BYTE_ENABLE_WIDTH-1:0] active_byte_enable_t;

	reg       read_pending_q;
	reg [1:0] read_owner_q;

	wire read_slot_available_w = !read_pending_q || mem_resp_valid_i;
	wire mem_accept_w = ce_i && mem_req_o && mem_accept_i;

	always @* begin
		dp_accept_o = 1'b0;
		dp_resp_valid_o = 1'b0;
		dp_resp_data_o = {DATA_WIDTH{1'b0}};
		xp_accept_o = 1'b0;
		xp_resp_valid_o = 1'b0;
		xp_resp_data_o = {DATA_WIDTH{1'b0}};
		cpu_accept_o = 1'b0;
		cpu_resp_valid_o = 1'b0;
		cpu_resp_data_o = {DATA_WIDTH{1'b0}};

		selected_valid_t = 1'b0;
		selected_write_t = 1'b0;
		selected_owner_t = OWNER_NONE;
		selected_addr_t = {ADDR_WIDTH{1'b0}};
		selected_wdata_t = {DATA_WIDTH{1'b0}};
		selected_byte_enable_t = {BYTE_ENABLE_WIDTH{1'b0}};

		if (dp_req_i) begin
			selected_valid_t = 1'b1;
			selected_write_t = dp_write_i;
			selected_owner_t = OWNER_DP;
			selected_addr_t = dp_addr_i;
			selected_wdata_t = dp_wdata_i;
			selected_byte_enable_t = dp_byte_enable_i;
		end else if (xp_req_i) begin
			selected_valid_t = 1'b1;
			selected_write_t = xp_write_i;
			selected_owner_t = OWNER_XP;
			selected_addr_t = xp_addr_i;
			selected_wdata_t = xp_wdata_i;
			selected_byte_enable_t = xp_byte_enable_i;
		end else if (cpu_req_i) begin
			selected_valid_t = 1'b1;
			selected_write_t = cpu_write_i;
			selected_owner_t = OWNER_CPU;
			selected_addr_t = cpu_addr_i;
			selected_wdata_t = cpu_wdata_i;
			selected_byte_enable_t = cpu_byte_enable_i;
		end

		active_write_t = held_valid_q ? held_write_q : selected_write_t;
		active_owner_t = held_valid_q ? held_owner_q : selected_owner_t;
		active_addr_t = held_valid_q ? held_addr_q : selected_addr_t;
		active_wdata_t = held_valid_q ? held_wdata_q : selected_wdata_t;
		active_byte_enable_t = held_valid_q ? held_byte_enable_q :
			selected_byte_enable_t;

		mem_req_o = (held_valid_q || selected_valid_t) &&
			read_slot_available_w && ce_i && !reset_i;
		mem_write_o = active_write_t;
		mem_addr_o = active_addr_t;
		mem_wdata_o = active_wdata_t;
		mem_byte_enable_o = active_byte_enable_t;

		// Keep accepts combinational so held requests retire on the accepting CE.
		if (mem_accept_w) begin
			case (active_owner_t)
				OWNER_DP: dp_accept_o = 1'b1;
				OWNER_XP: xp_accept_o = 1'b1;
				OWNER_CPU: cpu_accept_o = 1'b1;
				default: begin
				end
			endcase
		end

		if (!reset_i && ce_i && mem_resp_valid_i && read_pending_q) begin
			case (read_owner_q)
				OWNER_DP: begin
					dp_resp_valid_o = 1'b1;
					dp_resp_data_o = mem_resp_data_i;
				end
				OWNER_XP: begin
					xp_resp_valid_o = 1'b1;
					xp_resp_data_o = mem_resp_data_i;
				end
				OWNER_CPU: begin
					cpu_resp_valid_o = 1'b1;
					cpu_resp_data_o = mem_resp_data_i;
				end
				default: begin
				end
			endcase
		end
	end

	always @(posedge clk_i) begin
		if (reset_i) begin
			held_valid_q <= 1'b0;
			held_write_q <= 1'b0;
			held_owner_q <= OWNER_NONE;
			held_addr_q <= {ADDR_WIDTH{1'b0}};
			held_wdata_q <= {DATA_WIDTH{1'b0}};
			held_byte_enable_q <= {BYTE_ENABLE_WIDTH{1'b0}};
			read_pending_q <= 1'b0;
			read_owner_q <= OWNER_NONE;
		end else if (ce_i) begin
			// Hold a stalled command; later requests wait for the next slot.
			if (!held_valid_q && mem_req_o && !mem_accept_i) begin
				held_valid_q <= 1'b1;
				held_write_q <= selected_write_t;
				held_owner_q <= selected_owner_t;
				held_addr_q <= selected_addr_t;
				held_wdata_q <= selected_wdata_t;
				held_byte_enable_q <= selected_byte_enable_t;
			end

			if (mem_resp_valid_i && read_pending_q) begin
				read_pending_q <= 1'b0;
				read_owner_q <= OWNER_NONE;
			end

			if (mem_accept_w) begin
				if (held_valid_q) begin
					held_valid_q <= 1'b0;
				end

				if (!active_write_t) begin
					read_pending_q <= 1'b1;
					read_owner_q <= active_owner_t;
				end
			end
		end
	end

	assign read_pending_o = read_pending_q;
	assign offer_held_o = held_valid_q;

endmodule

// 128 KiB byte-lane dual-port VIP RAM.
//
// A port accepts on a rising edge with CE and enable high. Reads return through
// the RAM register; writes do not raise rvalid. Low CE holds the response.
//
// Clients must prevent same-address cross-port collisions.

module vip_byte_lane_ram
(
	input  wire        clk_i,
	input  wire        reset_i,

	input  wire        ce_a_i,
	input  wire        enable_a_i,
	input  wire [15:0] addr_a_i,
	input  wire        wren_a_i,
	input  wire [1:0]  byte_enable_a_i,
	input  wire [15:0] wdata_a_i,
	output wire [15:0] rdata_a_o,
	output reg         rvalid_a_o,

	input  wire        ce_b_i,
	input  wire        allow_b_during_reset_i,
	input  wire        enable_b_i,
	input  wire [15:0] addr_b_i,
	input  wire        wren_b_i,
	input  wire [1:0]  byte_enable_b_i,
	input  wire [15:0] wdata_b_i,
	output wire [15:0] rdata_b_o,
	output reg         rvalid_b_o
);

	reg [15:0] addr_a_q;
	reg [15:0] addr_b_q;

	wire accept_a_w = !reset_i && ce_a_i && enable_a_i;
	// Port B also serves savestate and initialization writes while paused.
	wire accept_b_w = (!reset_i || allow_b_during_reset_i) &&
		ce_b_i && enable_b_i;

	// Send new requests directly to RAM, then hold the address while disabled.
	wire [15:0] ram_addr_a_w = accept_a_w ? addr_a_i : addr_a_q;
	wire [15:0] ram_addr_b_w = accept_b_w ? addr_b_i : addr_b_q;

	wire wren_a_low_w  = accept_a_w && wren_a_i && byte_enable_a_i[0];
	wire wren_a_high_w = accept_a_w && wren_a_i && byte_enable_a_i[1];
	wire wren_b_low_w  = accept_b_w && wren_b_i && byte_enable_b_i[0];
	wire wren_b_high_w = accept_b_w && wren_b_i && byte_enable_b_i[1];

	wire [7:0] rdata_a_low_w;
	wire [7:0] rdata_a_high_w;
	wire [7:0] rdata_b_low_w;
	wire [7:0] rdata_b_high_w;

	always @(posedge clk_i) begin
		if (reset_i) begin
			addr_a_q <= 16'd0;
			addr_b_q <= 16'd0;
			rvalid_a_o <= 1'b0;
			rvalid_b_o <= 1'b0;
		end else begin
			if (ce_a_i) begin
				if (enable_a_i) begin
					addr_a_q <= addr_a_i;
				end
				rvalid_a_o <= enable_a_i && !wren_a_i;
			end

			if (ce_b_i) begin
				if (enable_b_i) begin
					addr_b_q <= addr_b_i;
				end
				rvalid_b_o <= enable_b_i && !wren_b_i;
			end
		end
	end

	cache_ram_dp
	#(
		.ADDR_WIDTH(16),
		.DATA_WIDTH(8)
	)
	u_low_lane
	(
		.clk_i(clk_i),
		.addr_a_i(ram_addr_a_w),
		.wren_a_i(wren_a_low_w),
		.wdata_a_i(wdata_a_i[7:0]),
		.q_a_o(rdata_a_low_w),
		.addr_b_i(ram_addr_b_w),
		.wren_b_i(wren_b_low_w),
		.wdata_b_i(wdata_b_i[7:0]),
		.q_b_o(rdata_b_low_w)
	);

	cache_ram_dp
	#(
		.ADDR_WIDTH(16),
		.DATA_WIDTH(8)
	)
	u_high_lane
	(
		.clk_i(clk_i),
		.addr_a_i(ram_addr_a_w),
		.wren_a_i(wren_a_high_w),
		.wdata_a_i(wdata_a_i[15:8]),
		.q_a_o(rdata_a_high_w),
		.addr_b_i(ram_addr_b_w),
		.wren_b_i(wren_b_high_w),
		.wdata_b_i(wdata_b_i[15:8]),
		.q_b_o(rdata_b_high_w)
	);

	assign rdata_a_o = {rdata_a_high_w, rdata_a_low_w};
	assign rdata_b_o = {rdata_b_high_w, rdata_b_low_w};

endmodule

module vip_native_dp_timing
#(
	// Default to the measured left-eye boundary. Tests may move only this boundary.
	parameter [18:0] LEFT_START_PRE = 19'd59999,
	// Fixed mode uses nominal eye ends; timed mode ends after group 95.
	parameter TIMED_EYE_END_ENABLE = 1'b0
)
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire [5:0]  savestate_state_addr_i,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [63:0] savestate_state_wdata_i,
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire        savestate_state_wren_i,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire        sim_snapshot_restore_commit_i,
	input  wire        sim_snapshot_restore_apply_i,
	input  wire [3647:0] sim_snapshot_restore_packet_i,
`endif
`endif

	// Display enable combines DISP and SYNCE. Sample FRMCYC at game-frame start.
	input  wire        display_enable_i,
	input  wire [3:0]  frmcyc_staged_i,
	input  wire        dprst_i,
	input  wire        timed_eye_end_valid_i,
	input  wire        timed_eye_end_eye_i,

	// FCLK and frame_cycle_o run continuously. DPRST does not create FCLK edges.
	output reg  [18:0] frame_cycle_o,
	output reg         fclk_o,
	output reg         waiting_for_fclk_o,

	// Display status registers.
	output reg         left_busy_o,
	output reg         right_busy_o,

	// CE-wide native boundary strobes.
	output reg         frame_start_o,
	output reg         left_start_o,
	output reg         left_end_o,
	output reg         right_start_o,
	output reg         right_end_o,

	// Same-edge boundary events for clocked consumers.
	output wire        frame_start_fire_o,
	output wire        left_start_fire_o,
	output wire        left_end_fire_o,
	output wire        right_start_fire_o,
	output wire        right_end_fire_o,

	// Only the documented rising GCLK event is modeled.
	output reg         gclk_rise_o,
	output reg         game_start_o,
	output wire        gclk_rise_fire_o,
	output wire        game_start_fire_o,
	output reg  [3:0]  frmcyc_active_o,
	output wire [3:0]  game_frame_wait_o
);

	localparam [18:0] FRAME_LAST = 19'd399999;
	localparam [18:0] LEFT_END_PRE = 19'd159999;
	localparam [18:0] FCLK_LOW_PRE = 19'd199999;
	localparam [18:0] RIGHT_START_PRE = 19'd259999;
	localparam [18:0] RIGHT_END_PRE = 19'd359999;

	// Number of extra display frames before the next game frame.
	reg [3:0] game_frame_wait_q;

	wire enabled_fire_w = ce_i && !reset_i && !dprst_i;
	wire ordinary_eye_fire_w = enabled_fire_w && !waiting_for_fclk_o &&
		(frame_cycle_o != FRAME_LAST);
	wire frame_start_fire_w = enabled_fire_w &&
		(frame_cycle_o == FRAME_LAST);
	wire game_start_fire_w = frame_start_fire_w &&
		(waiting_for_fclk_o || (game_frame_wait_q == 4'd0));

	assign frame_start_fire_o = frame_start_fire_w;
	assign left_start_fire_o = enabled_fire_w && !waiting_for_fclk_o &&
		(frame_cycle_o == LEFT_START_PRE) && display_enable_i;
	assign left_end_fire_o = ordinary_eye_fire_w && left_busy_o &&
		(TIMED_EYE_END_ENABLE ?
			(timed_eye_end_valid_i && !timed_eye_end_eye_i) :
			(frame_cycle_o == LEFT_END_PRE));
	assign right_start_fire_o = enabled_fire_w && !waiting_for_fclk_o &&
		(frame_cycle_o == RIGHT_START_PRE) && display_enable_i;
	assign right_end_fire_o = ordinary_eye_fire_w && right_busy_o &&
		(TIMED_EYE_END_ENABLE ?
			(timed_eye_end_valid_i && timed_eye_end_eye_i) :
			(frame_cycle_o == RIGHT_END_PRE));
	assign gclk_rise_fire_o = game_start_fire_w;
	assign game_start_fire_o = game_start_fire_w;
	assign game_frame_wait_o = game_frame_wait_q;

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
				frame_cycle_o <= sim_snapshot_restore_packet_i[18:0];
				fclk_o <= sim_snapshot_restore_packet_i[64];
				waiting_for_fclk_o <= sim_snapshot_restore_packet_i[128];
				left_busy_o <= 1'b0;
				right_busy_o <= 1'b0;
				frame_start_o <= 1'b0;
				left_start_o <= 1'b0;
				left_end_o <= 1'b0;
				right_start_o <= 1'b0;
				right_end_o <= 1'b0;
				gclk_rise_o <= 1'b0;
				game_start_o <= 1'b0;
				frmcyc_active_o <= sim_snapshot_restore_packet_i[259:256];
				game_frame_wait_q <= sim_snapshot_restore_packet_i[195:192];
			end
		end else
`endif
`endif
		if (reset_i) begin
			frame_cycle_o <= FRAME_LAST;
			fclk_o <= 1'b0;
			waiting_for_fclk_o <= 1'b1;
			left_busy_o <= 1'b0;
			right_busy_o <= 1'b0;
			frame_start_o <= 1'b0;
			left_start_o <= 1'b0;
			left_end_o <= 1'b0;
			right_start_o <= 1'b0;
			right_end_o <= 1'b0;
			gclk_rise_o <= 1'b0;
			game_start_o <= 1'b0;
			frmcyc_active_o <= 4'd0;
			game_frame_wait_q <= 4'd0;
		end else if (savestate_state_wren_i) begin
			case (savestate_state_addr_i)
				6'd0: frame_cycle_o <= savestate_state_wdata_i[18:0];
				6'd1: fclk_o <= savestate_state_wdata_i[0];
				6'd2: waiting_for_fclk_o <= savestate_state_wdata_i[0];
				6'd3: game_frame_wait_q <= savestate_state_wdata_i[3:0];
				6'd4: frmcyc_active_o <= savestate_state_wdata_i[3:0];
				default: begin
				end
			endcase
		end else if (ce_i) begin
			frame_start_o <= 1'b0;
			left_start_o <= 1'b0;
			left_end_o <= 1'b0;
			right_start_o <= 1'b0;
			right_end_o <= 1'b0;
			gclk_rise_o <= 1'b0;
			game_start_o <= 1'b0;

			// DPRST does not reset scanner state.
			if (frame_cycle_o == FRAME_LAST) begin
				frame_cycle_o <= 19'd0;
				fclk_o <= 1'b1;
			end else begin
				frame_cycle_o <= frame_cycle_o + 19'd1;
				if (frame_cycle_o == FCLK_LOW_PRE) begin
					fclk_o <= 1'b0;
				end
			end

			if (dprst_i) begin
				// Silicon unknown: DPRST boundary priority is undocumented. DPRST
				// wins, and display resumes on the next natural FCLK edge.
				waiting_for_fclk_o <= 1'b1;
				left_busy_o <= 1'b0;
				right_busy_o <= 1'b0;
				frmcyc_active_o <= 4'd0;
				game_frame_wait_q <= 4'd0;
			end else if (frame_cycle_o == FRAME_LAST) begin
				// State-zero FCLK releases DPRST wait or starts a display frame.
				waiting_for_fclk_o <= 1'b0;
				left_busy_o <= 1'b0;
				right_busy_o <= 1'b0;
				frame_start_o <= 1'b1;

				if (waiting_for_fclk_o || (game_frame_wait_q == 4'd0)) begin
					gclk_rise_o <= 1'b1;
					game_start_o <= 1'b1;
					frmcyc_active_o <= frmcyc_staged_i;
					game_frame_wait_q <= frmcyc_staged_i;
				end else begin
					game_frame_wait_q <= game_frame_wait_q - 4'd1;
				end
			end else if (waiting_for_fclk_o) begin
				left_busy_o <= 1'b0;
				right_busy_o <= 1'b0;
			end else begin
				case (frame_cycle_o)
					LEFT_START_PRE: begin
						if (display_enable_i) begin
							left_busy_o <= 1'b1;
							left_start_o <= 1'b1;
						end
					end
					LEFT_END_PRE: begin
						if (!TIMED_EYE_END_ENABLE) begin
							if (left_busy_o) begin
								left_end_o <= 1'b1;
							end
							left_busy_o <= 1'b0;
						end
					end
					RIGHT_START_PRE: begin
						if (display_enable_i) begin
							right_busy_o <= 1'b1;
							right_start_o <= 1'b1;
						end
					end
					RIGHT_END_PRE: begin
						if (!TIMED_EYE_END_ENABLE) begin
							if (right_busy_o) begin
								right_end_o <= 1'b1;
							end
							right_busy_o <= 1'b0;
						end
					end
					default: begin
					end
				endcase

				if (TIMED_EYE_END_ENABLE && timed_eye_end_valid_i) begin
					if (!timed_eye_end_eye_i && left_busy_o) begin
						left_busy_o <= 1'b0;
						left_end_o <= 1'b1;
					end else if (timed_eye_end_eye_i && right_busy_o) begin
						right_busy_o <= 1'b0;
						right_end_o <= 1'b1;
					end
				end
			end
		end
	end

endmodule


// Native column-table request sequencer.
//
// The source supplies one held token per four columns. Silicon unknown: sources
// define 96 groups per eye but not the exact CTA read edge.
//
// Only one DRAM read may be active. Keep its group tag until response. Silicon
// unknown: DPRST partial-transfer timing is not documented.

module vip_native_cta_sequencer
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	// Raw-clock abort cancels offers but lets accepted DRAM reads drain.
	input  wire        abort_i,

	// DP timing already qualifies these eye boundaries.
	input  wire        left_field_start_i,
	input  wire        left_field_end_i,
	input  wire        right_field_start_i,
	input  wire        right_field_end_i,

	// LOCK retains CTA at the eye boundary, then the private pointer walks 96 groups.
	input  wire [7:0]  cta_left_i,
	input  wire [7:0]  cta_right_i,

	input  wire        column_group_valid_i,
	output wire        column_group_ready_o,

	// DRAM halfword read channel.
	output wire        dram_req_o,
	output wire [15:0] dram_addr_o,
	input  wire        dram_accept_i,
	input  wire        dram_resp_valid_i,
	input  wire [15:0] dram_resp_data_i,

	// Registered one-CE CTC result.
	output reg         ctc_valid_o,
	output reg  [15:0] ctc_data_o,
	output reg         ctc_eye_o,
	output reg  [6:0]  ctc_ordinal_o,
	output reg  [7:0]  ctc_index_o,

	// Group 95 completes the eye. Diagnostics report early end or overlapping starts.
	output reg         field_complete_o,
	output reg         field_complete_eye_o,
	output reg         field_incomplete_o,
	output reg         field_overlap_o,

	output wire        field_active_o,
	output wire        field_eye_o,
	output wire        transaction_active_o,
	output wire [6:0]  group_count_o,
	output wire [6:0]  request_count_o,
	output wire [6:0]  response_count_o
);

	localparam [1:0] STATE_GROUP = 2'd0;
	localparam [1:0] STATE_REQUEST = 2'd1;
	localparam [1:0] STATE_RESPONSE = 2'd2;

	reg [1:0] state_q;
	reg       field_active_q;
	reg       field_eye_q;
	reg [7:0] cta_pointer_q;
	reg [6:0] group_count_q;
	reg [6:0] request_count_q;
	reg [6:0] response_count_q;

	reg       transaction_eye_q;
	reg [6:0] transaction_ordinal_q;
	reg [7:0] transaction_index_q;
	reg       transaction_discard_q;

	wire group_fire_w = ce_i && column_group_valid_i &&
		column_group_ready_o;
	wire request_fire_w = ce_i && dram_req_o && dram_accept_i;
	wire response_fire_w = ce_i && (state_q == STATE_RESPONSE) &&
		dram_resp_valid_i;
	wire response_finishes_field_w = response_fire_w &&
		(response_count_q == 7'd95);
	wire matching_field_end_w = field_eye_q ? right_field_end_i :
		left_field_end_i;

	assign column_group_ready_o = ce_i && !reset_i && !abort_i &&
		field_active_q &&
		(state_q == STATE_GROUP) && (group_count_q < 7'd96);
	assign dram_req_o = !reset_i && !abort_i &&
		(state_q == STATE_REQUEST);
	assign dram_addr_o = {
		transaction_eye_q ? 8'hef : 8'hee,
		transaction_index_q
	};

	assign field_active_o = field_active_q && !abort_i;
	assign field_eye_o = field_eye_q;
	assign transaction_active_o = (state_q == STATE_RESPONSE) ||
		((state_q == STATE_REQUEST) && !abort_i);
	assign group_count_o = group_count_q;
	assign request_count_o = request_count_q;
	assign response_count_o = response_count_q;

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_GROUP;
			field_active_q <= 1'b0;
			field_eye_q <= 1'b0;
			cta_pointer_q <= 8'd0;
			group_count_q <= 7'd0;
			request_count_q <= 7'd0;
			response_count_q <= 7'd0;
			transaction_eye_q <= 1'b0;
			transaction_ordinal_q <= 7'd0;
			transaction_index_q <= 8'd0;
			transaction_discard_q <= 1'b0;
			ctc_valid_o <= 1'b0;
			ctc_data_o <= 16'd0;
			ctc_eye_o <= 1'b0;
			ctc_ordinal_o <= 7'd0;
			ctc_index_o <= 8'd0;
			field_complete_o <= 1'b0;
			field_complete_eye_o <= 1'b0;
			field_incomplete_o <= 1'b0;
			field_overlap_o <= 1'b0;
		end else if (abort_i) begin
			// Abort clears pulses and drains any accepted response without CTC output.
			ctc_valid_o <= 1'b0;
			field_complete_o <= 1'b0;
			field_incomplete_o <= 1'b0;
			field_overlap_o <= 1'b0;
			field_active_q <= 1'b0;

			case (state_q)
				STATE_REQUEST: begin
					state_q <= STATE_GROUP;
					transaction_discard_q <= 1'b0;
				end

				STATE_RESPONSE: begin
					transaction_discard_q <= 1'b1;
					if (ce_i && dram_resp_valid_i) begin
						state_q <= STATE_GROUP;
						response_count_q <= response_count_q + 7'd1;
						transaction_discard_q <= 1'b0;
					end
				end

				default: begin
					state_q <= STATE_GROUP;
					transaction_discard_q <= 1'b0;
				end
			endcase
		end else if (ce_i) begin
			ctc_valid_o <= 1'b0;
			field_complete_o <= 1'b0;
			field_incomplete_o <= 1'b0;
			field_overlap_o <= 1'b0;

			// Start only while idle; reject simultaneous eye starts.
			if (left_field_start_i && right_field_start_i) begin
				field_overlap_o <= 1'b1;
			end else if (left_field_start_i || right_field_start_i) begin
				if (field_active_q || (state_q != STATE_GROUP)) begin
					field_overlap_o <= 1'b1;
				end else begin
					field_active_q <= 1'b1;
					field_eye_q <= right_field_start_i;
					cta_pointer_q <= right_field_start_i ?
						cta_right_i : cta_left_i;
					group_count_q <= 7'd0;
					request_count_q <= 7'd0;
					response_count_q <= 7'd0;
				end
			end

			if (group_fire_w) begin
				state_q <= STATE_REQUEST;
				transaction_discard_q <= 1'b0;
				transaction_eye_q <= field_eye_q;
				transaction_ordinal_q <= group_count_q;
				transaction_index_q <= cta_pointer_q;
				group_count_q <= group_count_q + 7'd1;
				cta_pointer_q <= cta_pointer_q - 8'd1;
			end

			if (request_fire_w) begin
				state_q <= STATE_RESPONSE;
				request_count_q <= request_count_q + 7'd1;
			end

			if (response_fire_w) begin
				state_q <= STATE_GROUP;
				response_count_q <= response_count_q + 7'd1;
				transaction_discard_q <= 1'b0;
				if (!transaction_discard_q) begin
					ctc_valid_o <= 1'b1;
					ctc_data_o <= dram_resp_data_i;
					ctc_eye_o <= transaction_eye_q;
					ctc_ordinal_o <= transaction_ordinal_q;
					ctc_index_o <= transaction_index_q;

					if (field_active_q &&
						(response_count_q == 7'd95)) begin
						field_active_q <= 1'b0;
						field_complete_o <= 1'b1;
						field_complete_eye_o <= transaction_eye_q;
					end
				end
			end

			// A final same-edge response completes; otherwise stop and drain.
			if (field_active_q && matching_field_end_w) begin
				if (!response_finishes_field_w &&
					(response_count_q != 7'd96)) begin
					field_incomplete_o <= 1'b1;
				end
				field_active_q <= 1'b0;
			end
		end
	end

endmodule


// Native VIP brightness exposure precompute for CTC jobs.
//
// Exposure uses 20 MHz LED-on ticks. Process one brightness unit per enabled
// clock and keep the visible part of the last unit at the column boundary.
//
// job_ready_o is CE-qualified. Valid must drop before the next job.

module vip_native_brightness_precompute
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,

	input  wire        job_valid_i,
	output wire        job_ready_o,
	input  wire        job_eye_i,
	input  wire [6:0]  job_group_i,
	input  wire [7:0]  job_brta_i,
	input  wire [7:0]  job_brtb_i,
	input  wire [7:0]  job_brtc_i,
	input  wire [7:0]  job_rest_i,
	input  wire [15:0] job_ctc_i,

	output reg         result_valid_o,
	output reg         result_eye_o,
	output reg  [6:0]  result_group_o,
	output wire [10:0] result_exposure_0_o,
	output reg  [10:0] result_exposure_1_o,
	output reg  [10:0] result_exposure_2_o,
	output reg  [10:0] result_exposure_3_o,
	output reg         result_overrun_o,
	output reg         result_short_column_o,

	output wire        busy_o,
	output wire [7:0]  cycle_count_o,
	output wire        quiescent_o
);

	localparam [3:0] STATE_IDLE     = 4'd0;
	localparam [3:0] STATE_SUM_AB   = 4'd1;
	localparam [3:0] STATE_SUM_ABC  = 4'd2;
	localparam [3:0] STATE_SUM_UNIT = 4'd3;
	localparam [3:0] STATE_REPEAT   = 4'd4;
	localparam [3:0] STATE_SHORT    = 4'd5;
	localparam [3:0] STATE_CLIP_A   = 4'd6;
	localparam [3:0] STATE_CLIP_B   = 4'd7;
	localparam [3:0] STATE_CLIP_C   = 4'd8;

	reg [3:0] state_q;
	reg       job_consumed_q;
	reg       eye_q;
	reg [6:0] group_q;
	reg [7:0] brta_q;
	reg [7:0] brtb_q;
	reg [7:0] brtc_q;
	reg [7:0] rest_q;
	reg [8:0] ab_q;
	reg [9:0] abc_q;
	reg [10:0] rest_plus_five_q;
	reg [10:0] unit_ticks_q;
	reg [10:0] remaining_ticks_q;
	reg [8:0] repeats_left_q;
	reg [10:0] exposure_1_q;
	reg [10:0] exposure_2_q;
	reg [10:0] exposure_3_q;
	reg [10:0] partial_ticks_q;
	reg [7:0] cycle_count_q;

	wire [8:0] ab_sum_w =
		{1'b0, brta_q} + {1'b0, brtb_q};
	wire [9:0] abc_sum_w =
		{1'b0, ab_q} + {2'b00, brtc_q};
	wire [10:0] rest_plus_five_w =
		{3'b000, rest_q} + 11'd5;
	wire [10:0] unit_sum_w =
		{1'b0, abc_q} + rest_plus_five_q;

	// Keep the 11-bit accumulator carry explicit before truncation.
	/* verilator lint_off UNUSEDSIGNAL */
	wire [11:0] exposure_1_sum_w =
		{1'b0, exposure_1_q} + {4'b0000, brta_q};
	wire [11:0] exposure_2_sum_w =
		{1'b0, exposure_2_q} + {4'b0000, brtb_q};
	wire [11:0] exposure_3_sum_w =
		{1'b0, exposure_3_q} + {2'b00, abc_q};
	wire [11:0] exposure_1_partial_sum_w =
		{1'b0, exposure_1_q} + {1'b0, partial_ticks_q};
	wire [11:0] exposure_2_partial_sum_w =
		{1'b0, exposure_2_q} + {1'b0, partial_ticks_q};
	wire [11:0] exposure_3_partial_sum_w =
		{1'b0, exposure_3_q} + {1'b0, partial_ticks_q};
	wire [11:0] exposure_3_brta_sum_w =
		{1'b0, exposure_3_q} + {4'b0000, brta_q};
	wire [11:0] exposure_3_brtb_sum_w =
		{1'b0, exposure_3_q} + {4'b0000, brtb_q};
	wire [11:0] exposure_3_brtc_sum_w =
		{1'b0, exposure_3_q} + {4'b0000, brtc_q};
	/* verilator lint_on UNUSEDSIGNAL */

	assign job_ready_o =
		ce_i && !reset_i && (state_q == STATE_IDLE) && !job_consumed_q;
	assign result_exposure_0_o = 11'd0;
	assign busy_o = (state_q != STATE_IDLE);
	assign cycle_count_o = cycle_count_q;
	// Snapshot readiness also includes the held-token guard and result pulse.
	assign quiescent_o = (state_q == STATE_IDLE) && !job_consumed_q &&
		!result_valid_o;

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			job_consumed_q <= 1'b0;
			eye_q <= 1'b0;
			group_q <= 7'd0;
			brta_q <= 8'd0;
			brtb_q <= 8'd0;
			brtc_q <= 8'd0;
			rest_q <= 8'd0;
			ab_q <= 9'd0;
			abc_q <= 10'd0;
			rest_plus_five_q <= 11'd0;
			unit_ticks_q <= 11'd0;
			remaining_ticks_q <= 11'd0;
			repeats_left_q <= 9'd0;
			exposure_1_q <= 11'd0;
			exposure_2_q <= 11'd0;
			exposure_3_q <= 11'd0;
			partial_ticks_q <= 11'd0;
			cycle_count_q <= 8'd0;
			result_valid_o <= 1'b0;
			result_eye_o <= 1'b0;
			result_group_o <= 7'd0;
			result_exposure_1_o <= 11'd0;
			result_exposure_2_o <= 11'd0;
			result_exposure_3_o <= 11'd0;
			result_overrun_o <= 1'b0;
			result_short_column_o <= 1'b0;
		end else if (ce_i) begin
			result_valid_o <= 1'b0;

			if (!job_valid_i) begin
				job_consumed_q <= 1'b0;
			end

			case (state_q)
				STATE_IDLE: begin
					if (job_valid_i && !job_consumed_q) begin
						job_consumed_q <= 1'b1;
						eye_q <= job_eye_i;
						group_q <= job_group_i;
						brta_q <= job_brta_i;
						brtb_q <= job_brtb_i;
						brtc_q <= job_brtc_i;
						rest_q <= job_rest_i;
						remaining_ticks_q <=
							{1'b0, job_ctc_i[7:0], 2'b00} + 11'd4;
						repeats_left_q <=
							{1'b0, job_ctc_i[15:8]} + 9'd1;
						exposure_1_q <= 11'd0;
						exposure_2_q <= 11'd0;
						exposure_3_q <= 11'd0;
						cycle_count_q <= 8'd1;

						if (job_ctc_i[7:0] < 8'h2c) begin
							state_q <= STATE_SHORT;
						end else begin
							state_q <= STATE_SUM_AB;
						end
					end
				end

				STATE_SUM_AB: begin
					cycle_count_q <= cycle_count_q + 8'd1;
					ab_q <= ab_sum_w;
					state_q <= STATE_SUM_ABC;
				end

				STATE_SUM_ABC: begin
					cycle_count_q <= cycle_count_q + 8'd1;
					abc_q <= abc_sum_w;
					rest_plus_five_q <= rest_plus_five_w;
					state_q <= STATE_SUM_UNIT;
				end

				STATE_SUM_UNIT: begin
					cycle_count_q <= cycle_count_q + 8'd1;
					unit_ticks_q <= unit_sum_w;
					state_q <= STATE_REPEAT;
				end

				STATE_REPEAT: begin
					cycle_count_q <= cycle_count_q + 8'd1;

					if (remaining_ticks_q <= unit_ticks_q) begin
						partial_ticks_q <= remaining_ticks_q;
						state_q <= STATE_CLIP_A;
					end else if (repeats_left_q == 9'd1) begin
						result_valid_o <= 1'b1;
						result_eye_o <= eye_q;
						result_group_o <= group_q;
						result_exposure_1_o <= exposure_1_sum_w[10:0];
						result_exposure_2_o <= exposure_2_sum_w[10:0];
						result_exposure_3_o <= exposure_3_sum_w[10:0];
						result_overrun_o <= 1'b0;
						result_short_column_o <= 1'b0;
						state_q <= STATE_IDLE;
					end else begin
						remaining_ticks_q <=
							remaining_ticks_q - unit_ticks_q;
						repeats_left_q <= repeats_left_q - 9'd1;
						exposure_1_q <= exposure_1_sum_w[10:0];
						exposure_2_q <= exposure_2_sum_w[10:0];
						exposure_3_q <= exposure_3_sum_w[10:0];
					end
				end

				STATE_CLIP_A: begin
					cycle_count_q <= cycle_count_q + 8'd1;

					if (partial_ticks_q >= {3'b000, brta_q}) begin
						exposure_1_q <= exposure_1_sum_w[10:0];
						exposure_3_q <= exposure_3_brta_sum_w[10:0];
						if (partial_ticks_q >
							({3'b000, brta_q} + 11'd1)) begin
							partial_ticks_q <= partial_ticks_q -
								{3'b000, brta_q} - 11'd1;
						end else begin
							partial_ticks_q <= 11'd0;
						end
					end else begin
						exposure_1_q <= exposure_1_partial_sum_w[10:0];
						exposure_3_q <= exposure_3_partial_sum_w[10:0];
						partial_ticks_q <= 11'd0;
					end
					state_q <= STATE_CLIP_B;
				end

				STATE_CLIP_B: begin
					cycle_count_q <= cycle_count_q + 8'd1;

					if (partial_ticks_q >= {3'b000, brtb_q}) begin
						exposure_2_q <= exposure_2_sum_w[10:0];
						exposure_3_q <= exposure_3_brtb_sum_w[10:0];
						if (partial_ticks_q >
							({3'b000, brtb_q} + 11'd1)) begin
							partial_ticks_q <= partial_ticks_q -
								{3'b000, brtb_q} - 11'd1;
						end else begin
							partial_ticks_q <= 11'd0;
						end
					end else begin
						exposure_2_q <= exposure_2_partial_sum_w[10:0];
						exposure_3_q <= exposure_3_partial_sum_w[10:0];
						partial_ticks_q <= 11'd0;
					end
					state_q <= STATE_CLIP_C;
				end

				STATE_CLIP_C: begin
					cycle_count_q <= cycle_count_q + 8'd1;
					result_valid_o <= 1'b1;
					result_eye_o <= eye_q;
					result_group_o <= group_q;
					result_exposure_1_o <= exposure_1_q;
					result_exposure_2_o <= exposure_2_q;
					if (partial_ticks_q >= {3'b000, brtc_q}) begin
						result_exposure_3_o <=
							exposure_3_brtc_sum_w[10:0];
					end else begin
						result_exposure_3_o <=
							exposure_3_partial_sum_w[10:0];
					end
					result_overrun_o <= 1'b1;
					result_short_column_o <= 1'b0;
					state_q <= STATE_IDLE;
				end

				STATE_SHORT: begin
					cycle_count_q <= cycle_count_q + 8'd1;
					result_valid_o <= 1'b1;
					result_eye_o <= eye_q;
					result_group_o <= group_q;
					result_exposure_1_o <= 11'd0;
					result_exposure_2_o <= 11'd0;
					result_exposure_3_o <= 11'd0;
					result_overrun_o <= 1'b0;
					result_short_column_o <= 1'b1;
					state_q <= STATE_IDLE;
				end

				default: begin
					state_q <= STATE_IDLE;
					cycle_count_q <= 8'd0;
				end
			endcase
		end
	end

endmodule


// Converts one four-column native brightness group for MiSTer. Two parallel
// 1024x8 block RAM byte lanes hold complete SDR and HLG E0..E1023 tables. The
// worker performs three bounded synchronous reads; all nonlinear math remains
// offline. HPS loading uses only the ordinary fabric write ports.

module vip_presentation_luma_transfer
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,

	input  wire        job_valid_i,
	output wire        job_ready_o,
	input  wire        job_eye_i,
	input  wire [6:0]  job_group_i,
	input  wire [10:0] job_exposure_1_i,
	input  wire [10:0] job_exposure_2_i,
	input  wire [10:0] job_exposure_3_i,
	input  wire        transfer_hlg_i,
	input  wire        legacy_sdr_clamp_i,
	input  wire        table_download_i,
	input  wire        table_write_i,
	input  wire [9:0]  table_addr_i,
	input  wire [15:0] table_data_i,

	output reg         result_valid_o,
	output reg         result_eye_o,
	output reg  [6:0]  result_group_o,
	output reg  [31:0] result_levels_o,
	output wire        busy_o
);

	localparam [2:0] STATE_IDLE   = 3'd0;
	localparam [2:0] STATE_LEVEL1 = 3'd1;
	localparam [2:0] STATE_LEVEL2 = 3'd2;
	localparam [2:0] STATE_LEVEL3 = 3'd3;
	localparam [2:0] STATE_COMMIT = 3'd4;

	reg [2:0]  state_q;
	reg [9:0]  lut_addr_q;
	reg        lut_byte_select_q;
	reg        transfer_hlg_q;
	reg        legacy_sdr_clamp_q;
	reg [7:0]  level_1_q;
	reg [7:0]  level_2_q;
	reg [10:0] exposure_2_q;
	reg [10:0] exposure_3_q;
	wire [9:0] ram_addr_w = table_download_i ? table_addr_i : lut_addr_q;
	wire       table_ram_write_w = table_download_i && table_write_i;
	wire [7:0] lut_even_w;
	wire [7:0] lut_odd_w;
	wire [7:0] lut_data_w;

	function [9:0] exposure_to_lut_addr_fn;
		input [10:0] exposure_v;
		input        transfer_hlg_v;
		input        legacy_sdr_clamp_v;
		begin
			if (!transfer_hlg_v && legacy_sdr_clamp_v &&
				exposure_v >= 11'd255) begin
				exposure_to_lut_addr_fn = 10'd127;
			end else if (exposure_v >= 11'd1012) begin
				exposure_to_lut_addr_fn = {transfer_hlg_v, 9'd506};
			end else begin
				exposure_to_lut_addr_fn = {
					transfer_hlg_v, exposure_v[9:1]};
			end
		end
	endfunction

	function exposure_to_lut_byte_fn;
		input [10:0] exposure_v;
		input        transfer_hlg_v;
		input        legacy_sdr_clamp_v;
		begin
			if (!transfer_hlg_v && legacy_sdr_clamp_v &&
				exposure_v >= 11'd255) begin
				exposure_to_lut_byte_fn = 1'b1;
			end else if (exposure_v >= 11'd1012) begin
				exposure_to_lut_byte_fn = 1'b0;
			end else begin
				exposure_to_lut_byte_fn = exposure_v[0];
			end
		end
	endfunction

`ifdef __ICARUS__
	localparam LUMA_EVEN_SIM_INIT_FILE =
		"../../rtl/VIP/vip_luma_temporal_sdr22_hlg700_e1023_even.hex";
	localparam LUMA_ODD_SIM_INIT_FILE =
		"../../rtl/VIP/vip_luma_temporal_sdr22_hlg700_e1023_odd.hex";
`else
	localparam LUMA_EVEN_SIM_INIT_FILE =
		"rtl/VIP/vip_luma_temporal_sdr22_hlg700_e1023_even.hex";
	localparam LUMA_ODD_SIM_INIT_FILE =
		"rtl/VIP/vip_luma_temporal_sdr22_hlg700_e1023_odd.hex";
`endif

	cache_ram #(
		.ADDR_WIDTH(10),
		.DATA_WIDTH(8),
		.MEM_INIT_FILE("rtl/VIP/vip_luma_temporal_sdr22_hlg700_e1023_even.mif"),
		.SIM_INIT_FILE(LUMA_EVEN_SIM_INIT_FILE)
	) u_luma_even (
		.clk_i(clk_i),
		.addr_i(ram_addr_w),
		.wren_i(table_ram_write_w),
		.wdata_i(table_data_i[7:0]),
		.q_o(lut_even_w)
	);

	cache_ram #(
		.ADDR_WIDTH(10),
		.DATA_WIDTH(8),
		.MEM_INIT_FILE("rtl/VIP/vip_luma_temporal_sdr22_hlg700_e1023_odd.mif"),
		.SIM_INIT_FILE(LUMA_ODD_SIM_INIT_FILE)
	) u_luma_odd (
		.clk_i(clk_i),
		.addr_i(ram_addr_w),
		.wren_i(table_ram_write_w),
		.wdata_i(table_data_i[15:8]),
		.q_o(lut_odd_w)
	);

	assign lut_data_w = lut_byte_select_q ? lut_odd_w : lut_even_w;
	assign job_ready_o = ce_i && !reset_i &&
		!table_download_i && (state_q == STATE_IDLE) && !result_valid_o;
	assign busy_o = (state_q != STATE_IDLE);

	always @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= STATE_IDLE;
			lut_addr_q <= 10'd0;
			lut_byte_select_q <= 1'b0;
			transfer_hlg_q <= 1'b0;
			legacy_sdr_clamp_q <= 1'b0;
			level_1_q <= 8'd0;
			level_2_q <= 8'd0;
			exposure_2_q <= 11'd0;
			exposure_3_q <= 11'd0;
			result_valid_o <= 1'b0;
			result_eye_o <= 1'b0;
			result_group_o <= 7'd0;
			result_levels_o <= 32'd0;
		end else if (table_download_i) begin
			state_q <= STATE_IDLE;
			result_valid_o <= 1'b0;
		end else if (ce_i) begin
			result_valid_o <= 1'b0;

			case (state_q)
				STATE_IDLE: begin
					if (job_valid_i && !result_valid_o) begin
						result_eye_o <= job_eye_i;
						result_group_o <= job_group_i;
						exposure_2_q <= job_exposure_2_i;
						exposure_3_q <= job_exposure_3_i;
						transfer_hlg_q <= transfer_hlg_i;
						legacy_sdr_clamp_q <= legacy_sdr_clamp_i;
						lut_addr_q <= exposure_to_lut_addr_fn(
							job_exposure_1_i, transfer_hlg_i,
							legacy_sdr_clamp_i);
						lut_byte_select_q <= exposure_to_lut_byte_fn(
							job_exposure_1_i, transfer_hlg_i,
							legacy_sdr_clamp_i);
						state_q <= STATE_LEVEL1;
					end
				end

				STATE_LEVEL1: begin
					level_1_q <= lut_data_w;
					lut_addr_q <= exposure_to_lut_addr_fn(
						exposure_2_q, transfer_hlg_q,
						legacy_sdr_clamp_q);
					lut_byte_select_q <= exposure_to_lut_byte_fn(
						exposure_2_q, transfer_hlg_q,
						legacy_sdr_clamp_q);
					state_q <= STATE_LEVEL2;
				end

				STATE_LEVEL2: begin
					level_2_q <= lut_data_w;
					lut_addr_q <= exposure_to_lut_addr_fn(
						exposure_3_q, transfer_hlg_q,
						legacy_sdr_clamp_q);
					lut_byte_select_q <= exposure_to_lut_byte_fn(
						exposure_3_q, transfer_hlg_q,
						legacy_sdr_clamp_q);
					state_q <= STATE_LEVEL3;
				end

				STATE_LEVEL3: begin
					result_levels_o <= {
						lut_data_w,
						level_2_q,
						level_1_q,
						8'd0
					};
					state_q <= STATE_COMMIT;
				end

				STATE_COMMIT: begin
					result_valid_o <= 1'b1;
					state_q <= STATE_IDLE;
				end

				default: begin
					state_q <= STATE_IDLE;
					result_levels_o <= 32'd0;
				end
			endcase
		end
	end

endmodule


// Triple-buffered MiSTer brightness cache.
//
// Build in a bank that is neither displayed nor pending. Commit only complete
// 96-group stereo frames, and publish them at raster frame start.
//
// Three banks cover the state drift between the 399,360-CE MiSTer raster and
// 400,000-CE native frame.

module vip_brightness_generation_cache
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
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [3647:0]               sim_snapshot_restore_packet_i,
	/* verilator lint_on UNUSEDSIGNAL */
`endif
`endif
	// Cancel only the active unpublished build.
	input  wire                        cancel_build_i,

	// Allocate a free bank for the next native frame.
	input  wire                        begin_valid_i,
	input  wire [GENERATION_WIDTH-1:0] begin_generation_i,
	output wire                        begin_ready_o,
	output wire                        begin_accept_o,
	output wire                        begin_blocked_o,
	output wire                        reuse_blocked_o,
	output wire                        generation_tag_collision_o,

	// Duplicate group writes replace data without increasing the count.
	input  wire                        write_valid_i,
	input  wire [GENERATION_WIDTH-1:0] write_generation_i,
	input  wire                        write_eye_i,
	input  wire [6:0]                  write_group_i,
	input  wire [31:0]                 write_levels_i,
	output wire                        write_ready_o,
	output wire                        write_accept_o,
	output wire                        write_blocked_o,
	output wire                        write_tag_mismatch_o,

	// Commit marks a complete build pending.
	input  wire                        commit_valid_i,
	input  wire [GENERATION_WIDTH-1:0] commit_generation_i,
	output wire                        commit_ready_o,
	output wire                        commit_accept_o,
	output wire                        commit_blocked_o,
	output wire                        commit_incomplete_o,
	output wire                        commit_tag_mismatch_o,

	// Raster ownership changes only at this raw-clock boundary.
	input  wire                        raster_frame_boundary_i,
	output reg                         display_swap_o,
	output reg                         display_valid_o,
	output reg  [GENERATION_WIDTH-1:0] display_generation_o,
	output reg  [1:0]                  display_bank_o,

	// Raw-clock raster read with separate response and generation validity.
	input  wire                        raster_read_enable_i,
	input  wire                        raster_read_eye_i,
	input  wire [6:0]                  raster_read_group_i,
	output wire                        raster_read_response_valid_o,
	output wire                        raster_read_generation_valid_o,
	output wire [GENERATION_WIDTH-1:0] raster_read_generation_o,
	output wire [31:0]                 raster_read_levels_o,
	// Return both eyes from the same published bank.
	output wire                        raster_read_pair_generation_valid_o,
	output wire [31:0]                 raster_read_left_levels_o,
	output wire [31:0]                 raster_read_right_levels_o,

	// Ownership and completion state.
	output wire                        build_active_o,
	output wire [1:0]                  build_bank_o,
	output wire [GENERATION_WIDTH-1:0] build_generation_o,
	output wire [6:0]                  build_left_count_o,
	output wire [6:0]                  build_right_count_o,
	output wire                        build_complete_o,
	output wire                        pending_valid_o,
	output wire [1:0]                  pending_bank_o,
	output wire [GENERATION_WIDTH-1:0] pending_generation_o,
	output wire                        raster_read_pipeline_empty_o
);

	reg                         build_active_q;
	reg  [1:0]                  build_bank_q;
	reg  [GENERATION_WIDTH-1:0] build_generation_q;
	reg  [6:0]                  left_count_bank0_q;
	reg  [6:0]                  right_count_bank0_q;
	reg  [6:0]                  left_count_bank1_q;
	reg  [6:0]                  right_count_bank1_q;
	reg  [6:0]                  left_count_bank2_q;
	reg  [6:0]                  right_count_bank2_q;
	reg  [95:0]                 left_valid_bank0_q;
	reg  [95:0]                 right_valid_bank0_q;
	reg  [95:0]                 left_valid_bank1_q;
	reg  [95:0]                 right_valid_bank1_q;
	reg  [95:0]                 left_valid_bank2_q;
	reg  [95:0]                 right_valid_bank2_q;

	reg                         pending_valid_q;
	reg  [1:0]                  pending_bank_q;
	reg  [GENERATION_WIDTH-1:0] pending_generation_q;

	reg                         read_response_valid_q;
	reg                         read_entry_valid_q;
	reg                         read_left_entry_valid_q;
	reg                         read_right_entry_valid_q;
	reg                         read_eye_q;
	reg  [GENERATION_WIDTH-1:0] read_generation_q;

	wire bank0_displayed_w = display_valid_o &&
		(display_bank_o == 2'd0);
	wire bank1_displayed_w = display_valid_o &&
		(display_bank_o == 2'd1);
	wire bank2_displayed_w = display_valid_o &&
		(display_bank_o == 2'd2);
	wire bank0_pending_w = pending_valid_q &&
		(pending_bank_q == 2'd0);
	wire bank1_pending_w = pending_valid_q &&
		(pending_bank_q == 2'd1);
	wire bank2_pending_w = pending_valid_q &&
		(pending_bank_q == 2'd2);
	wire bank0_free_w = !bank0_displayed_w && !bank0_pending_w &&
		!(build_active_q && (build_bank_q == 2'd0));
	wire bank1_free_w = !bank1_displayed_w && !bank1_pending_w &&
		!(build_active_q && (build_bank_q == 2'd1));
	wire bank2_free_w = !bank2_displayed_w && !bank2_pending_w &&
		!(build_active_q && (build_bank_q == 2'd2));
	wire free_bank_available_w = bank0_free_w || bank1_free_w ||
		bank2_free_w;
	wire [1:0] selected_begin_bank_w = bank0_free_w ? 2'd0 :
		(bank1_free_w ? 2'd1 : 2'd2);

	wire begin_tag_hits_display_w = display_valid_o &&
		(begin_generation_i == display_generation_o);
	wire begin_tag_hits_pending_w = pending_valid_q &&
		(begin_generation_i == pending_generation_q);
	wire begin_tag_collision_w = begin_tag_hits_display_w ||
		begin_tag_hits_pending_w;

	wire build_left_complete_w = (build_bank_q == 2'd0) ?
		(left_count_bank0_q == 7'd96) :
		((build_bank_q == 2'd1) ?
		 (left_count_bank1_q == 7'd96) :
		 (left_count_bank2_q == 7'd96));
	wire build_right_complete_w = (build_bank_q == 2'd0) ?
		(right_count_bank0_q == 7'd96) :
		((build_bank_q == 2'd1) ?
		 (right_count_bank1_q == 7'd96) :
		 (right_count_bank2_q == 7'd96));
	wire build_complete_w = build_active_q && build_left_complete_w &&
		build_right_complete_w;

	wire write_group_valid_w = write_group_i < 7'd96;
	wire write_tag_match_w = build_active_q &&
		(write_generation_i == build_generation_q);
	wire build_bank_live_w = (build_bank_q == 2'd0) ?
		(bank0_displayed_w || bank0_pending_w) :
		((build_bank_q == 2'd1) ?
		 (bank1_displayed_w || bank1_pending_w) :
		 (bank2_displayed_w || bank2_pending_w));
	wire raster_selects_pending_w = raster_frame_boundary_i &&
		pending_valid_q;
	wire raster_selected_valid_w = raster_selects_pending_w ||
		display_valid_o;
	wire [1:0] raster_selected_bank_w = raster_selects_pending_w ? pending_bank_q :
		display_bank_o;
	wire [GENERATION_WIDTH-1:0] raster_selected_generation_w =
		raster_selects_pending_w ? pending_generation_q :
		display_generation_o;
	// Bank-selected per-eye valid bits for the raster read below.
	wire raster_left_valid_bit_w =
		(raster_selected_bank_w == 2'd0) ?
			left_valid_bank0_q[raster_read_group_i] :
		(raster_selected_bank_w == 2'd1) ?
			left_valid_bank1_q[raster_read_group_i] :
		left_valid_bank2_q[raster_read_group_i];
	wire raster_right_valid_bit_w =
		(raster_selected_bank_w == 2'd0) ?
			right_valid_bank0_q[raster_read_group_i] :
		(raster_selected_bank_w == 2'd1) ?
			right_valid_bank1_q[raster_read_group_i] :
		right_valid_bank2_q[raster_read_group_i];

	assign begin_ready_o = ce_i && !reset_i && !build_active_q &&
		free_bank_available_w && !begin_tag_collision_w;
	assign begin_accept_o = begin_valid_i && begin_ready_o;
	assign begin_blocked_o = begin_valid_i && !begin_ready_o;
	assign reuse_blocked_o = begin_valid_i && !build_active_q &&
		!free_bank_available_w;
	assign generation_tag_collision_o = begin_valid_i &&
		begin_tag_collision_w;

	assign write_ready_o = ce_i && !reset_i && !cancel_build_i &&
		write_tag_match_w &&
		write_group_valid_w && !build_bank_live_w;
	assign write_accept_o = write_valid_i && write_ready_o;
	assign write_blocked_o = write_valid_i && !write_ready_o;
	assign write_tag_mismatch_o = write_valid_i &&
		(!build_active_q || (write_generation_i != build_generation_q));

	assign commit_ready_o = ce_i && !reset_i && !cancel_build_i &&
		build_complete_w &&
		!pending_valid_q &&
		(commit_generation_i == build_generation_q);
	assign commit_accept_o = commit_valid_i && commit_ready_o;
	assign commit_blocked_o = commit_valid_i && !commit_ready_o;
	assign commit_incomplete_o = commit_valid_i && build_active_q &&
		(commit_generation_i == build_generation_q) &&
		!build_complete_w;
	assign commit_tag_mismatch_o = commit_valid_i &&
		(!build_active_q || (commit_generation_i != build_generation_q));

	assign build_active_o = build_active_q;
	assign build_bank_o = build_bank_q;
	assign build_generation_o = build_generation_q;
	assign build_left_count_o = (build_bank_q == 2'd0) ?
		left_count_bank0_q : ((build_bank_q == 2'd1) ?
		left_count_bank1_q : left_count_bank2_q);
	assign build_right_count_o = (build_bank_q == 2'd0) ?
		right_count_bank0_q : ((build_bank_q == 2'd1) ?
		right_count_bank1_q : right_count_bank2_q);
	assign build_complete_o = build_complete_w;
	assign pending_valid_o = pending_valid_q;
	assign pending_bank_o = pending_bank_q;
	assign pending_generation_o = pending_generation_q;

	// Store all three banks in one RAM per eye using high address bits as the tag.
	wire [8:0] brightness_write_storage_addr_w =
		{build_bank_q, write_group_i};
	wire [8:0] brightness_raster_storage_addr_w =
		{raster_selected_bank_w, raster_read_group_i};
	wire [31:0] packed_left_read_w;
	wire [31:0] packed_right_read_w;

	/* verilator lint_off PINCONNECTEMPTY */
	cache_ram_dp
	#(
		.ADDR_WIDTH(9),
		.DATA_WIDTH(32)
	)
	u_left_store
	(
		.clk_i(clk_i),
		.addr_a_i(brightness_write_storage_addr_w),
		.wren_a_i(write_accept_o && !write_eye_i),
		.wdata_a_i(write_levels_i),
		.q_a_o(),
		.addr_b_i(brightness_raster_storage_addr_w),
		.wren_b_i(1'b0),
		.wdata_b_i(32'd0),
		.q_b_o(packed_left_read_w)
	);

	cache_ram_dp
	#(
		.ADDR_WIDTH(9),
		.DATA_WIDTH(32)
	)
	u_right_store
	(
		.clk_i(clk_i),
		.addr_a_i(brightness_write_storage_addr_w),
		.wren_a_i(write_accept_o && write_eye_i),
		.wdata_a_i(write_levels_i),
		.q_a_o(),
		.addr_b_i(brightness_raster_storage_addr_w),
		.wren_b_i(1'b0),
		.wdata_b_i(32'd0),
		.q_b_o(packed_right_read_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	wire [31:0] selected_read_levels_w = read_eye_q ?
		packed_right_read_w : packed_left_read_w;

	assign raster_read_response_valid_o = read_response_valid_q;
	assign raster_read_generation_valid_o = read_response_valid_q &&
		read_entry_valid_q;
	assign raster_read_generation_o = read_generation_q;
	assign raster_read_levels_o = (read_response_valid_q &&
		read_entry_valid_q) ? selected_read_levels_w : 32'd0;
	assign raster_read_pair_generation_valid_o = read_response_valid_q &&
		read_left_entry_valid_q && read_right_entry_valid_q;
	assign raster_read_left_levels_o =
		raster_read_pair_generation_valid_o ?
		packed_left_read_w : 32'd0;
	assign raster_read_right_levels_o =
		raster_read_pair_generation_valid_o ?
		packed_right_read_w : 32'd0;
	// Include the current request when checking whether the read pipe is empty.
	assign raster_read_pipeline_empty_o = !raster_read_enable_i &&
		!read_response_valid_q;

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
				build_active_q <= 1'b0;
				build_bank_q <= 2'd0;
				build_generation_q <= {GENERATION_WIDTH{1'b0}};
				left_count_bank0_q <= 7'd0;
				right_count_bank0_q <= 7'd0;
				left_count_bank1_q <= 7'd0;
				right_count_bank1_q <= 7'd0;
				left_count_bank2_q <= 7'd0;
				right_count_bank2_q <= 7'd0;
				left_valid_bank0_q <= 96'd0;
				right_valid_bank0_q <= 96'd0;
				left_valid_bank1_q <= 96'd0;
				right_valid_bank1_q <= 96'd0;
				left_valid_bank2_q <= 96'd0;
				right_valid_bank2_q <= 96'd0;
				pending_valid_q <= 1'b0;
				pending_bank_q <= 2'd0;
				pending_generation_q <= {GENERATION_WIDTH{1'b0}};
				display_swap_o <= 1'b0;
				display_valid_o <= 1'b0;
				display_generation_o <= {GENERATION_WIDTH{1'b0}};
				display_bank_o <= 2'd0;
				read_response_valid_q <= 1'b0;
				read_entry_valid_q <= 1'b0;
				read_left_entry_valid_q <= 1'b0;
				read_right_entry_valid_q <= 1'b0;
				read_eye_q <= 1'b0;
				read_generation_q <= {GENERATION_WIDTH{1'b0}};
			end
		end else
`endif
`endif
		if (reset_i) begin
			build_active_q <= 1'b0;
			build_bank_q <= 2'd0;
			build_generation_q <= {GENERATION_WIDTH{1'b0}};
			left_count_bank0_q <= 7'd0;
			right_count_bank0_q <= 7'd0;
			left_count_bank1_q <= 7'd0;
			right_count_bank1_q <= 7'd0;
			left_count_bank2_q <= 7'd0;
			right_count_bank2_q <= 7'd0;
			left_valid_bank0_q <= 96'd0;
			right_valid_bank0_q <= 96'd0;
			left_valid_bank1_q <= 96'd0;
			right_valid_bank1_q <= 96'd0;
			left_valid_bank2_q <= 96'd0;
			right_valid_bank2_q <= 96'd0;
			pending_valid_q <= 1'b0;
			pending_bank_q <= 2'd0;
			pending_generation_q <= {GENERATION_WIDTH{1'b0}};
			display_swap_o <= 1'b0;
			display_valid_o <= 1'b0;
			display_generation_o <= {GENERATION_WIDTH{1'b0}};
			display_bank_o <= 2'd0;
			read_response_valid_q <= 1'b0;
			read_entry_valid_q <= 1'b0;
			read_left_entry_valid_q <= 1'b0;
			read_right_entry_valid_q <= 1'b0;
			read_eye_q <= 1'b0;
			read_generation_q <= {GENERATION_WIDTH{1'b0}};
		end else begin
			display_swap_o <= 1'b0;
			read_response_valid_q <= raster_read_enable_i;
			if (raster_read_enable_i) begin
				read_eye_q <= raster_read_eye_i;
				read_generation_q <= raster_selected_generation_w;
				if (!raster_selected_valid_w ||
					(raster_read_group_i >= 7'd96)) begin
					read_entry_valid_q <= 1'b0;
					read_left_entry_valid_q <= 1'b0;
					read_right_entry_valid_q <= 1'b0;
				end else begin
					// The requested eye gates the entry itself; both
					// per-eye bits ride along for the pair check.
					read_entry_valid_q <= raster_read_eye_i ?
						raster_right_valid_bit_w :
						raster_left_valid_bit_w;
					read_left_entry_valid_q <=
						raster_left_valid_bit_w;
					read_right_entry_valid_q <=
						raster_right_valid_bit_w;
				end
			end

			if (raster_frame_boundary_i && pending_valid_q) begin
				display_valid_o <= 1'b1;
				display_bank_o <= pending_bank_q;
				display_generation_o <= pending_generation_q;
				pending_valid_q <= 1'b0;
				display_swap_o <= 1'b1;
			end

			if (cancel_build_i) begin
				build_active_q <= 1'b0;
			end else if (ce_i) begin
				if (begin_accept_o) begin
					build_active_q <= 1'b1;
					build_bank_q <= selected_begin_bank_w;
					build_generation_q <= begin_generation_i;
					if (selected_begin_bank_w == 2'd0) begin
						left_count_bank0_q <= 7'd0;
						right_count_bank0_q <= 7'd0;
						left_valid_bank0_q <= 96'd0;
						right_valid_bank0_q <= 96'd0;
					end else if (selected_begin_bank_w == 2'd1) begin
						left_count_bank1_q <= 7'd0;
						right_count_bank1_q <= 7'd0;
						left_valid_bank1_q <= 96'd0;
						right_valid_bank1_q <= 96'd0;
					end else begin
						left_count_bank2_q <= 7'd0;
						right_count_bank2_q <= 7'd0;
						left_valid_bank2_q <= 96'd0;
						right_valid_bank2_q <= 96'd0;
					end
				end

				if (write_accept_o) begin
					if ((build_bank_q == 2'd0) && !write_eye_i) begin
						if (!left_valid_bank0_q[write_group_i]) begin
							left_count_bank0_q <= left_count_bank0_q + 7'd1;
						end
						left_valid_bank0_q[write_group_i] <= 1'b1;
					end else if ((build_bank_q == 2'd0) && write_eye_i) begin
						if (!right_valid_bank0_q[write_group_i]) begin
							right_count_bank0_q <= right_count_bank0_q + 7'd1;
						end
						right_valid_bank0_q[write_group_i] <= 1'b1;
					end else if ((build_bank_q == 2'd1) && !write_eye_i) begin
						if (!left_valid_bank1_q[write_group_i]) begin
							left_count_bank1_q <= left_count_bank1_q + 7'd1;
						end
						left_valid_bank1_q[write_group_i] <= 1'b1;
					end else if ((build_bank_q == 2'd1) && write_eye_i) begin
						if (!right_valid_bank1_q[write_group_i]) begin
							right_count_bank1_q <= right_count_bank1_q + 7'd1;
						end
						right_valid_bank1_q[write_group_i] <= 1'b1;
					end else if (!write_eye_i) begin
						if (!left_valid_bank2_q[write_group_i]) begin
							left_count_bank2_q <= left_count_bank2_q + 7'd1;
						end
						left_valid_bank2_q[write_group_i] <= 1'b1;
					end else begin
						if (!right_valid_bank2_q[write_group_i]) begin
							right_count_bank2_q <= right_count_bank2_q + 7'd1;
						end
						right_valid_bank2_q[write_group_i] <= 1'b1;
					end
				end

				if (commit_accept_o) begin
					pending_valid_q <= 1'b1;
					pending_bank_q <= build_bank_q;
					pending_generation_q <= build_generation_q;
					build_active_q <= 1'b0;
				end
			end
		end
	end

endmodule


// MiSTer raster reader for completed Virtual Boy frames.
//
// This read-only port sits outside VIP arbitration. Paired mode reads left on CE
// and right on phi1. Side-by-side mode reads one eye per 40 MHz CE. Only completed
// framebuffers may be exposed to avoid write collisions.
//
// Brightness packs four levels. Use local RAMs or the external generation cache.

module vip_mister_scan_converter
#(
	parameter [15:0] H_VISIBLE = 16'd384,
	parameter [15:0] H_TOTAL = 16'd1280,
	parameter [15:0] H_SYNC_BEG = 16'd1056,
	parameter [15:0] H_SYNC_END = 16'd1152,
	parameter [15:0] V_VISIBLE = 16'd224,
	parameter [15:0] V_TOTAL = 16'd312,
	parameter [15:0] V_SYNC_BEG = 16'd289,
	parameter [15:0] V_SYNC_END = 16'd292,
	// Select local or generation-owned brightness RAMs.
	parameter integer EXTERNAL_BRIGHTNESS = 0,
	// Black invalid generation-owned framebuffer responses.
	parameter EXTERNAL_FRAMEBUFFER = 1'b0
)
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire        phi1_i,
	input  wire        savestate_boundary_stop_i,
	input  wire [5:0]  savestate_state_addr_i,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [63:0] savestate_state_wdata_i,
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire        savestate_state_wren_i,
	output wire [36:0] savestate_state_o,
	// Raster timing continues when native display transfer is off.
	input  wire        display_enable_i,
`ifndef SYNTHESIS
`ifdef VIP_SIM_SNAPSHOT_IMPORT
	input  wire        sim_snapshot_restore_commit_i,
	input  wire        sim_snapshot_restore_apply_i,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [3647:0] sim_snapshot_restore_packet_i,
	/* verilator lint_on UNUSEDSIGNAL */
`endif
`endif

	// Direct VRM follows native ownership; external capture changes only at frame start.
	input  wire        displayed_fb_i,
	input  wire        framebuffer_handoff_fire_i,
	input  wire        framebuffer_handoff_target_i,
	output wire        displayed_fb_latched_o,

	// Presentation modes after observer reads:
	//   00: dual/stereo       left -> L, right -> R
	//   01: left single       left -> L, black -> R
	//   10: right single      black -> L, right -> R
	//   11: flat selected eye selected eye -> L and R
	// side_by_side_i independently selects full-rate left-then-right scanout.
	input  wire [1:0]  presentation_mode_i,
	input  wire        flat_eye_i,
	input  wire        side_by_side_i,
	// Sampled only at a source-raster boundary. Production supplies the public
	// scheduler's already committed selection, so terminal blanking cannot let
	// an asynchronous menu update split the two timing domains.
	input  wire        compat_60hz_i,
	input  wire        shutter_i,

	// Brightness groups 0..95 map to x[8:2]. Ignore larger values and avoid
	// same-address read/write collisions.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire        brightness_write_i,
	input  wire        brightness_eye_i,
	input  wire [6:0]  brightness_group_i,
	input  wire [31:0] brightness_levels_i,
	/* verilator lint_on UNUSEDSIGNAL */

	// Read both eye levels one raw clock after the left framebuffer prefetch.
	output wire        raster_frame_boundary_o,
	output wire        brightness_read_enable_o,
	output wire [6:0]  brightness_read_group_o,
	input  wire        brightness_read_response_valid_i,
	input  wire        brightness_read_generation_valid_i,
	input  wire [31:0] brightness_read_left_levels_i,
	input  wire [31:0] brightness_read_right_levels_i,
	output reg         brightness_alignment_error_o,
	input  wire        framebuffer_generation_valid_i,

	// VRM observer responses must return one clock after each request.
	output wire        vrm_observer_enable_o,
	output wire [15:0] vrm_observer_addr_o,
	input  wire        vrm_observer_rvalid_i,
	input  wire [15:0] vrm_observer_rdata_i,
	output reg         observer_alignment_error_o,
	output wire        observer_owner_active_o,
	output wire        snapshot_pipeline_empty_o,

	output wire        pixel_ce_o,
	output reg  [15:0] raster_x_o,
	output reg  [15:0] raster_y_o,
	output reg         video_hblank_o,
	output reg         video_vblank_o,
	output reg         video_hsync_o,
	output reg         video_vsync_o,
	output reg  [1:0]  raw_pixel_left_o,
	output reg  [1:0]  raw_pixel_right_o,
	output reg  [7:0]  video_luma_left_o,
	output reg  [7:0]  video_luma_right_o
);

	localparam [15:0] NATIVE_WIDTH = 16'd384;
	localparam [15:0] NATIVE_HEIGHT = 16'd224;

	reg [15:0] raster_x_q;
	reg [15:0] raster_y_q;
	reg        raster_started_q;
	reg        side_by_side_q;
	reg        compat_60hz_q;
	reg        shutter_q = 1'b0;      // 3D shutter-glasses raster (256 lines), committed by the public scheduler
	reg        displayed_fb_q;
	reg        handoff_discard_pending_q;
	// X-defence: only a definite high on an undriven selector requests a
	// snapshot stop. The same pattern squashes X on the two mode selects
	// below.
	reg        savestate_boundary_stop_t;
	always @(*) begin
		case (savestate_boundary_stop_i)
			1'b1: savestate_boundary_stop_t = 1'b1;
			default: savestate_boundary_stop_t = 1'b0;
		endcase
	end
	wire       savestate_restore_scan_w = savestate_state_wren_i &&
		(savestate_state_addr_i == 6'd48);
	reg        prefetch_valid_q;
	reg [8:0]  prefetch_x_q;
	reg [8:0]  prefetch_y_q;
	reg        prefetch_fb_q;

	reg        observer_pending_q;
	reg        observer_pending_eye_q;
	reg [8:0]  observer_pending_x_q;
	reg [8:0]  observer_pending_y_q;
	reg [2:0]  observer_pending_pixel_q;

	reg [15:0] left_halfword_q;
	reg        left_halfword_valid_q;
	reg [8:0]  left_tag_x_q;
	reg [8:0]  left_tag_y_q;
	reg [2:0]  left_tag_pixel_q;
	reg [15:0] right_halfword_q;
	reg        right_halfword_valid_q;
	reg [8:0]  right_tag_x_q;
	reg [8:0]  right_tag_y_q;
	reg [2:0]  right_tag_pixel_q;

	/* verilator lint_off UNUSEDSIGNAL */
	reg [6:0] brightness_read_addr_q;
	/* verilator lint_on UNUSEDSIGNAL */
	reg        external_brightness_pending_q;
	reg [8:0]  external_brightness_pending_x_q;
	reg        external_brightness_pair_valid_q;
	reg [8:0]  external_brightness_tag_x_q;
	/* verilator lint_off UNUSEDSIGNAL */
	reg [31:0] external_brightness_left_levels_q;
	reg [31:0] external_brightness_right_levels_q;
	/* verilator lint_on UNUSEDSIGNAL */

	reg side_by_side_requested_t;
	reg compat_60hz_requested_t;
	always @(*) begin
		// Default an undriven selector to normal presentation.
		case (side_by_side_i)
			1'b1: side_by_side_requested_t = 1'b1;
			default: side_by_side_requested_t = 1'b0;
		endcase
		case (compat_60hz_i)
			1'b1: compat_60hz_requested_t = 1'b1;
			default: compat_60hz_requested_t = 1'b0;
		endcase
	end
	wire scan_mode_ready_w =
		(side_by_side_q == side_by_side_requested_t);
	wire [15:0] raster_h_visible_w = side_by_side_q ?
		(H_VISIBLE << 1) : H_VISIBLE;
	wire [15:0] raster_h_total_base_w = compat_60hz_q ?
		16'd1270 : H_TOTAL;
	wire [15:0] raster_h_total_w = side_by_side_q ?
		(raster_h_total_base_w << 1) : raster_h_total_base_w;
	wire [15:0] raster_h_sync_beg_w = side_by_side_q ?
		(H_SYNC_BEG << 1) : H_SYNC_BEG;
	wire [15:0] raster_h_sync_end_w = side_by_side_q ?
		(H_SYNC_END << 1) : H_SYNC_END;
	wire [15:0] raster_last_x_w = raster_h_total_w - 16'd1;
	wire [15:0] raster_v_total_w = shutter_q ? 16'd256 : (compat_60hz_q ? 16'd262 : V_TOTAL);
	wire [15:0] raster_v_sync_beg_w = shutter_q ? 16'd237 : (compat_60hz_q ?
		16'd243 : V_SYNC_BEG);
	wire [15:0] raster_v_sync_end_w = shutter_q ? 16'd240 : (compat_60hz_q ?
		16'd246 : V_SYNC_END);
	wire [15:0] raster_last_y_w = raster_v_total_w - 16'd1;
	wire        savestate_scan_bootstrap_w = !raster_started_q &&
		(raster_x_q == 16'd0) && (raster_y_q == 16'd0);
	wire        savestate_scan_stop_point_w = savestate_scan_bootstrap_w ||
		(raster_started_q && (raster_x_q == raster_last_x_w) &&
		 (raster_y_q == raster_last_y_w));
	assign savestate_state_o = {
		savestate_scan_stop_point_w, compat_60hz_q,
		displayed_fb_q, side_by_side_q, raster_started_q,
		raster_y_q, raster_x_q};
	wire [15:0] raster_next_x_w =
		(raster_x_q == raster_last_x_w) ? 16'd0 : (raster_x_q + 16'd1);
	wire [15:0] raster_next_y_w =
		(raster_x_q == raster_last_x_w) ?
			((raster_y_q == raster_last_y_w) ? 16'd0 : (raster_y_q + 16'd1)) :
			raster_y_q;

	// Prefetch pixel zero before active raster, then prefetch one pixel ahead.
	wire [15:0] fetch_raster_x_w = raster_started_q ? raster_next_x_w : 16'd0;
	wire [15:0] fetch_raster_y_w = raster_started_q ? raster_next_y_w : 16'd0;
	wire        fetch_eye_w = side_by_side_q &&
		(fetch_raster_x_w >= H_VISIBLE);
	wire [15:0] fetch_native_x_w = fetch_eye_w ?
		(fetch_raster_x_w - H_VISIBLE) : fetch_raster_x_w;
	wire        fetch_visible_w =
		(fetch_raster_x_w < raster_h_visible_w) &&
		(fetch_raster_y_w < V_VISIBLE) &&
		(fetch_native_x_w < NATIVE_WIDTH) &&
		(fetch_raster_y_w < NATIVE_HEIGHT);
	wire        fetch_frame_start_w =
		!raster_started_q ||
		((raster_x_q == raster_last_x_w) &&
		 (raster_y_q == raster_last_y_w));
	// External framebuffer ownership changes only at raster boundaries.
	wire        framebuffer_handoff_effective_w =
		(EXTERNAL_FRAMEBUFFER == 0) && framebuffer_handoff_fire_i;
	wire        fetch_fb_w = framebuffer_handoff_effective_w ?
		framebuffer_handoff_target_i :
		(fetch_frame_start_w ? displayed_fb_i : displayed_fb_q);
	wire [8:0]  fetch_x_w = fetch_native_x_w[8:0];
	wire [8:0]  fetch_y_w = fetch_raster_y_w[8:0];
	wire [15:0] fetch_offset_w =
		{2'b00, fetch_x_w, 5'b00000} +
		{11'd0, fetch_y_w[7:3]};
	wire [15:0] prefetch_offset_w =
		{2'b00, prefetch_x_q, 5'b00000} +
		{11'd0, prefetch_y_q[7:3]};

	wire observer_left_request_w = scan_mode_ready_w && ce_i &&
		!savestate_boundary_stop_t &&
		fetch_visible_w &&
		(!side_by_side_q || raster_started_q || !prefetch_valid_q);
	wire observer_right_request_w =
		!side_by_side_q && phi1_i && prefetch_valid_q &&
		!framebuffer_handoff_effective_w;
	wire observer_request_w = observer_left_request_w || observer_right_request_w;
	wire [15:0] observer_left_base_w = fetch_eye_w ?
		(fetch_fb_w ? 16'hc000 : 16'h8000) :
		(fetch_fb_w ? 16'h4000 : 16'h0000);
	wire [15:0] observer_right_base_w = prefetch_fb_q ? 16'hc000 : 16'h8000;

	assign vrm_observer_enable_o = observer_request_w;
	assign vrm_observer_addr_o = observer_left_request_w ?
		(observer_left_base_w + fetch_offset_w) :
		(observer_right_base_w + prefetch_offset_w);

	assign displayed_fb_latched_o = displayed_fb_q;
	assign pixel_ce_o = scan_mode_ready_w && ce_i && raster_started_q &&
		!savestate_boundary_stop_t;
	assign raster_frame_boundary_o =
		(observer_left_request_w ||
		 (savestate_boundary_stop_t && ce_i)) && fetch_frame_start_w;
	assign brightness_read_enable_o =
		(EXTERNAL_BRIGHTNESS != 0) && observer_left_request_w;
	assign brightness_read_group_o = fetch_x_w[8:2];
	assign observer_owner_active_o = observer_request_w ||
		observer_pending_q || vrm_observer_rvalid_i;

	// Snapshot import resets presentation state after the raster drains.
	assign snapshot_pipeline_empty_o = !ce_i && !phi1_i &&
		!framebuffer_handoff_effective_w && !observer_request_w &&
		!vrm_observer_rvalid_i && !brightness_read_enable_o &&
		!brightness_read_response_valid_i && !handoff_discard_pending_q &&
		!prefetch_valid_q && !observer_pending_q &&
		!left_halfword_valid_q && !right_halfword_valid_q &&
		!external_brightness_pending_q &&
		!external_brightness_pair_valid_q;

	wire [31:0] brightness_left_levels_w;
	wire [31:0] brightness_right_levels_w;

	generate
		if (EXTERNAL_BRIGHTNESS == 0) begin : g_local_brightness
			wire brightness_write_valid_w =
				brightness_write_i && (brightness_group_i < 7'd96);

			/* verilator lint_off PINCONNECTEMPTY */
			cache_ram_dp
			#(
				.ADDR_WIDTH(7),
				.DATA_WIDTH(32)
			)
			u_brightness_left
			(
				.clk_i(clk_i),
				.addr_a_i(brightness_group_i),
				.wren_a_i(brightness_write_valid_w && !brightness_eye_i),
				.wdata_a_i(brightness_levels_i),
				.q_a_o(),
				.addr_b_i(brightness_read_addr_q),
				.wren_b_i(1'b0),
				.wdata_b_i(32'd0),
				.q_b_o(brightness_left_levels_w)
			);

			cache_ram_dp
			#(
				.ADDR_WIDTH(7),
				.DATA_WIDTH(32)
			)
			u_brightness_right
			(
				.clk_i(clk_i),
				.addr_a_i(brightness_group_i),
				.wren_a_i(brightness_write_valid_w && brightness_eye_i),
				.wdata_a_i(brightness_levels_i),
				.q_a_o(),
				.addr_b_i(brightness_read_addr_q),
				.wren_b_i(1'b0),
				.wdata_b_i(32'd0),
				.q_b_o(brightness_right_levels_w)
			);
			/* verilator lint_on PINCONNECTEMPTY */
		end else begin : g_external_brightness
			assign brightness_left_levels_w =
				external_brightness_left_levels_q;
			assign brightness_right_levels_w =
				external_brightness_right_levels_q;
		end
	endgenerate

	function [1:0] pixel_select_fn;
		input [15:0] halfword_i;
		input [2:0] pixel_i;
		begin
			case (pixel_i)
				3'd0: pixel_select_fn = halfword_i[1:0];
				3'd1: pixel_select_fn = halfword_i[3:2];
				3'd2: pixel_select_fn = halfword_i[5:4];
				3'd3: pixel_select_fn = halfword_i[7:6];
				3'd4: pixel_select_fn = halfword_i[9:8];
				3'd5: pixel_select_fn = halfword_i[11:10];
				3'd6: pixel_select_fn = halfword_i[13:12];
				default: pixel_select_fn = halfword_i[15:14];
			endcase
		end
	endfunction

	function [7:0] luma_select_fn;
		input [31:0] levels_i;
		input [1:0] pixel_i;
		begin
			case (pixel_i)
				2'd0: luma_select_fn = levels_i[7:0];
				2'd1: luma_select_fn = levels_i[15:8];
				2'd2: luma_select_fn = levels_i[23:16];
				default: luma_select_fn = levels_i[31:24];
			endcase
		end
	endfunction

	wire left_response_now_w =
		vrm_observer_rvalid_i && observer_pending_q && !observer_pending_eye_q;
	wire [15:0] left_halfword_for_output_w =
		left_response_now_w ? vrm_observer_rdata_i : left_halfword_q;
	wire [8:0] left_tag_x_for_output_w =
		left_response_now_w ? observer_pending_x_q : left_tag_x_q;
	wire [8:0] left_tag_y_for_output_w =
		left_response_now_w ? observer_pending_y_q : left_tag_y_q;
	wire [2:0] left_tag_pixel_for_output_w =
		left_response_now_w ? observer_pending_pixel_q : left_tag_pixel_q;
	wire left_halfword_for_output_valid_w =
		left_response_now_w || left_halfword_valid_q;
	wire [1:0] selected_left_pixel_w = pixel_select_fn(
		left_halfword_for_output_w, left_tag_pixel_for_output_w);
	wire right_response_now_w =
		vrm_observer_rvalid_i && observer_pending_q && observer_pending_eye_q;
	wire [15:0] right_halfword_for_output_w =
		right_response_now_w ? vrm_observer_rdata_i : right_halfword_q;
	wire [8:0] right_tag_x_for_output_w =
		right_response_now_w ? observer_pending_x_q : right_tag_x_q;
	wire [8:0] right_tag_y_for_output_w =
		right_response_now_w ? observer_pending_y_q : right_tag_y_q;
	wire [2:0] right_tag_pixel_for_output_w =
		right_response_now_w ? observer_pending_pixel_q : right_tag_pixel_q;
	wire right_halfword_for_output_valid_w =
		right_response_now_w || right_halfword_valid_q;
	wire [1:0] selected_right_pixel_w =
		pixel_select_fn(right_halfword_for_output_w, right_tag_pixel_for_output_w);
	wire brightness_response_now_w = side_by_side_q &&
		brightness_read_response_valid_i && external_brightness_pending_q &&
		!framebuffer_handoff_effective_w;
	wire [31:0] brightness_left_for_output_w = brightness_response_now_w ?
		brightness_read_left_levels_i : brightness_left_levels_w;
	wire [31:0] brightness_right_for_output_w = brightness_response_now_w ?
		brightness_read_right_levels_i : brightness_right_levels_w;
	wire [7:0] selected_left_luma_w = luma_select_fn(
		brightness_left_for_output_w, selected_left_pixel_w);
	wire [7:0] selected_right_luma_w = luma_select_fn(
		brightness_right_for_output_w, selected_right_pixel_w);
	wire        raster_eye_w = side_by_side_q &&
		(raster_x_q >= H_VISIBLE);
	wire [15:0] raster_native_x_w = raster_eye_w ?
		(raster_x_q - H_VISIBLE) : raster_x_q;
	wire external_brightness_pixel_valid_w =
		(brightness_response_now_w &&
		 brightness_read_generation_valid_i &&
		 (external_brightness_pending_x_q == raster_native_x_w[8:0])) ||
		(external_brightness_pair_valid_q &&
		 (external_brightness_tag_x_q == raster_native_x_w[8:0]));
	wire brightness_pixel_valid_w = (EXTERNAL_BRIGHTNESS == 0) ?
		1'b1 : external_brightness_pixel_valid_w;
	wire framebuffer_pixel_valid_w = (EXTERNAL_FRAMEBUFFER == 0) ?
		1'b1 : framebuffer_generation_valid_i;

	// Return the raster to the top-left of a fresh frame.
	task restart_scan_raster_task;
		begin
			raster_x_q <= 16'd0;
			raster_y_q <= 16'd0;
			raster_started_q <= 1'b0;
			raster_x_o <= 16'd0;
			raster_y_o <= 16'd0;
			video_hblank_o <= 1'b1;
			video_vblank_o <= 1'b1;
			video_hsync_o <= 1'b0;
			video_vsync_o <= 1'b0;
		end
	endtask

	// Drain every fetch, observer, tag, and brightness hold in the pipe.
	task clear_scan_pipeline_task;
		begin
			compat_60hz_q <= compat_60hz_requested_t;
			shutter_q <= shutter_i;
			handoff_discard_pending_q <= 1'b0;
			prefetch_valid_q <= 1'b0;
			prefetch_x_q <= 9'd0;
			prefetch_y_q <= 9'd0;
			prefetch_fb_q <= 1'b0;
			observer_pending_q <= 1'b0;
			observer_pending_eye_q <= 1'b0;
			observer_pending_x_q <= 9'd0;
			observer_pending_y_q <= 9'd0;
			observer_pending_pixel_q <= 3'd0;
			left_halfword_q <= 16'd0;
			left_halfword_valid_q <= 1'b0;
			left_tag_x_q <= 9'd0;
			left_tag_y_q <= 9'd0;
			left_tag_pixel_q <= 3'd0;
			right_halfword_q <= 16'd0;
			right_halfword_valid_q <= 1'b0;
			right_tag_x_q <= 9'd0;
			right_tag_y_q <= 9'd0;
			right_tag_pixel_q <= 3'd0;
			external_brightness_pending_q <= 1'b0;
			external_brightness_pending_x_q <= 9'd0;
			external_brightness_pair_valid_q <= 1'b0;
			external_brightness_tag_x_q <= 9'd0;
			external_brightness_left_levels_q <= 32'd0;
			external_brightness_right_levels_q <= 32'd0;
			observer_alignment_error_o <= 1'b0;
			brightness_alignment_error_o <= 1'b0;
			raw_pixel_left_o <= 2'd0;
			raw_pixel_right_o <= 2'd0;
			video_luma_left_o <= 8'd0;
			video_luma_right_o <= 8'd0;
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
				restart_scan_raster_task;
				clear_scan_pipeline_task;
				side_by_side_q <= side_by_side_requested_t;
				displayed_fb_q <= sim_snapshot_restore_packet_i[3336];
				brightness_read_addr_q <= 7'd0;
			end
		end else
`endif
`endif
		if (reset_i || !scan_mode_ready_w) begin
			restart_scan_raster_task;
			clear_scan_pipeline_task;
			side_by_side_q <= side_by_side_requested_t;
			displayed_fb_q <= 1'b0;
			brightness_read_addr_q <= 7'd0;
		end else if (savestate_restore_scan_w) begin
			// Restore scan position and ownership after the raster pipe drains.
			clear_scan_pipeline_task;
			raster_x_q <= savestate_state_wdata_i[24:9];
			raster_y_q <= savestate_state_wdata_i[40:25];
			raster_started_q <= savestate_state_wdata_i[41];
			side_by_side_q <= savestate_state_wdata_i[42];
			displayed_fb_q <= savestate_state_wdata_i[43];
			// Bits 17:11 alias into the raster-x field on purpose: the
			// restored brightness group is raster_x[8:2] of the same word.
			brightness_read_addr_q <= savestate_state_wdata_i[17:11];
			raster_x_o <= savestate_state_wdata_i[24:9];
			raster_y_o <= savestate_state_wdata_i[40:25];
			video_hblank_o <= savestate_state_wdata_i[24:9] >=
				(savestate_state_wdata_i[42] ? (H_VISIBLE << 1) : H_VISIBLE);
			video_vblank_o <= savestate_state_wdata_i[40:25] >= V_VISIBLE;
			video_hsync_o <=
				(savestate_state_wdata_i[24:9] >=
				 (savestate_state_wdata_i[42] ? (H_SYNC_BEG << 1) : H_SYNC_BEG)) &&
				(savestate_state_wdata_i[24:9] <
				 (savestate_state_wdata_i[42] ? (H_SYNC_END << 1) : H_SYNC_END));
			video_vsync_o <=
				(savestate_state_wdata_i[40:25] >=
				 (shutter_i ? 16'd237 : (compat_60hz_requested_t ? 16'd243 : V_SYNC_BEG))) &&
				(savestate_state_wdata_i[40:25] <
				 (shutter_i ? 16'd240 : (compat_60hz_requested_t ? 16'd246 : V_SYNC_END)));
			raw_pixel_left_o <= 2'd0;
			raw_pixel_right_o <= 2'd0;
			video_luma_left_o <= 8'd0;
			video_luma_right_o <= 8'd0;
		end else if (savestate_boundary_stop_t && ce_i &&
			fetch_frame_start_w) begin
			// Commit at frame start, then let bootstrap fetch the first pixel.
			restart_scan_raster_task;
			clear_scan_pipeline_task;
			side_by_side_q <= side_by_side_requested_t;
			displayed_fb_q <= displayed_fb_i;
			brightness_read_addr_q <= 7'd0;
		end else begin
			side_by_side_q <= side_by_side_requested_t;
			if (ce_i && fetch_frame_start_w) begin
				compat_60hz_q <= compat_60hz_requested_t;
				shutter_q <= shutter_i;
			end
			if (EXTERNAL_BRIGHTNESS != 0) begin
				if (external_brightness_pending_q !=
					brightness_read_response_valid_i) begin
					brightness_alignment_error_o <= 1'b1;
				end
				if (brightness_read_response_valid_i &&
					external_brightness_pending_q &&
					!framebuffer_handoff_effective_w) begin
					external_brightness_pair_valid_q <=
						brightness_read_generation_valid_i;
					external_brightness_tag_x_q <=
						external_brightness_pending_x_q;
					external_brightness_left_levels_q <=
						brightness_read_left_levels_i;
					external_brightness_right_levels_q <=
						brightness_read_right_levels_i;
				end
				external_brightness_pending_q <=
					brightness_read_enable_o;
				if (brightness_read_enable_o) begin
					external_brightness_pending_x_q <= fetch_x_w;
				end
			end

			// Flag missing or unsolicited one-clock observer responses.
			if (observer_pending_q != vrm_observer_rvalid_i) begin
				observer_alignment_error_o <= 1'b1;
			end

			if (vrm_observer_rvalid_i && observer_pending_q &&
				!framebuffer_handoff_effective_w) begin
				if (!observer_pending_eye_q) begin
					left_halfword_q <= vrm_observer_rdata_i;
					left_halfword_valid_q <= 1'b1;
					left_tag_x_q <= observer_pending_x_q;
					left_tag_y_q <= observer_pending_y_q;
					left_tag_pixel_q <= observer_pending_pixel_q;
				end else begin
					right_halfword_q <= vrm_observer_rdata_i;
					right_halfword_valid_q <= 1'b1;
					right_tag_x_q <= observer_pending_x_q;
					right_tag_y_q <= observer_pending_y_q;
					right_tag_pixel_q <= observer_pending_pixel_q;
				end
			end

			observer_pending_q <= observer_request_w;
			if (observer_request_w) begin
				observer_pending_eye_q <= observer_left_request_w ?
					fetch_eye_w : 1'b1;
				if (observer_left_request_w) begin
					observer_pending_x_q <= fetch_x_w;
					observer_pending_y_q <= fetch_y_w;
					observer_pending_pixel_q <= fetch_y_w[2:0];
				end else begin
					observer_pending_x_q <= prefetch_x_q;
					observer_pending_y_q <= prefetch_y_q;
					observer_pending_pixel_q <= prefetch_y_q[2:0];
				end
			end

			if (ce_i && phi1_i && !side_by_side_q) begin
				observer_alignment_error_o <= 1'b1;
			end

			if (ce_i) begin
				prefetch_valid_q <= fetch_visible_w;
				prefetch_x_q <= fetch_x_w;
				prefetch_y_q <= fetch_y_w;
				prefetch_fb_q <= fetch_fb_w;
				brightness_read_addr_q <= fetch_x_w[8:2];

				if (!raster_started_q) begin
					raster_x_q <= 16'd0;
					raster_y_q <= 16'd0;
					raster_x_o <= 16'd0;
					raster_y_o <= 16'd0;
					video_hblank_o <= 1'b1;
					video_vblank_o <= 1'b1;
					video_hsync_o <= 1'b0;
					video_vsync_o <= 1'b0;
					raw_pixel_left_o <= 2'd0;
					raw_pixel_right_o <= 2'd0;
					video_luma_left_o <= 8'd0;
					video_luma_right_o <= 8'd0;
				end else begin
					raster_x_o <= raster_x_q;
					raster_y_o <= raster_y_q;
					video_hblank_o <= (raster_x_q >= raster_h_visible_w);
					video_vblank_o <= (raster_y_q >= V_VISIBLE);
					video_hsync_o <=
						(raster_x_q >= raster_h_sync_beg_w) &&
						(raster_x_q < raster_h_sync_end_w);
					video_vsync_o <=
						(raster_y_q >= raster_v_sync_beg_w) &&
						(raster_y_q < raster_v_sync_end_w);

					if ((raster_x_q < raster_h_visible_w) &&
						(raster_y_q < V_VISIBLE) &&
						(raster_native_x_w < NATIVE_WIDTH) &&
						(raster_y_q < NATIVE_HEIGHT)) begin
						if (side_by_side_q) begin
							if ((raster_eye_w ?
								 right_halfword_for_output_valid_w :
								 left_halfword_for_output_valid_w) &&
								((raster_eye_w ? right_tag_x_for_output_w :
								  left_tag_x_for_output_w) == raster_native_x_w[8:0]) &&
								((raster_eye_w ? right_tag_y_for_output_w :
								  left_tag_y_for_output_w) == raster_y_q[8:0])) begin
								if (display_enable_i && brightness_pixel_valid_w &&
									framebuffer_pixel_valid_w) begin
									if (!raster_eye_w) begin
										raw_pixel_left_o <= selected_left_pixel_w;
										raw_pixel_right_o <= 2'd0;
										video_luma_left_o <= selected_left_luma_w;
										video_luma_right_o <= 8'd0;
									end else begin
										raw_pixel_left_o <= 2'd0;
										raw_pixel_right_o <= selected_right_pixel_w;
										video_luma_left_o <= 8'd0;
										video_luma_right_o <= selected_right_luma_w;
									end
								end else begin
									raw_pixel_left_o <= 2'd0;
									raw_pixel_right_o <= 2'd0;
									video_luma_left_o <= 8'd0;
									video_luma_right_o <= 8'd0;
								end
							end else begin
								raw_pixel_left_o <= 2'd0;
								raw_pixel_right_o <= 2'd0;
								video_luma_left_o <= 8'd0;
								video_luma_right_o <= 8'd0;
								if (!framebuffer_handoff_effective_w &&
									!handoff_discard_pending_q) begin
									observer_alignment_error_o <= 1'b1;
								end
							end
						end else if (right_halfword_for_output_valid_w &&
							left_halfword_for_output_valid_w &&
							(left_tag_x_for_output_w == raster_x_q[8:0]) &&
							(left_tag_y_for_output_w == raster_y_q[8:0]) &&
							(right_tag_x_for_output_w == raster_x_q[8:0]) &&
							(right_tag_y_for_output_w == raster_y_q[8:0]) &&
							(left_tag_pixel_for_output_w ==
							 right_tag_pixel_for_output_w)) begin
							if (display_enable_i && brightness_pixel_valid_w &&
								framebuffer_pixel_valid_w) begin
								raw_pixel_left_o <= selected_left_pixel_w;
								raw_pixel_right_o <= selected_right_pixel_w;
								case (presentation_mode_i)
									2'b00: begin
										video_luma_left_o <= selected_left_luma_w;
										video_luma_right_o <= selected_right_luma_w;
									end
									2'b01: begin
										video_luma_left_o <= selected_left_luma_w;
										video_luma_right_o <= 8'd0;
									end
									2'b10: begin
										video_luma_left_o <= 8'd0;
										video_luma_right_o <= selected_right_luma_w;
									end
									default: begin
										video_luma_left_o <= flat_eye_i ?
											selected_right_luma_w : selected_left_luma_w;
										video_luma_right_o <= flat_eye_i ?
											selected_right_luma_w : selected_left_luma_w;
									end
								endcase
							end else begin
								raw_pixel_left_o <= 2'd0;
								raw_pixel_right_o <= 2'd0;
								video_luma_left_o <= 8'd0;
								video_luma_right_o <= 8'd0;
							end
						end else begin
							raw_pixel_left_o <= 2'd0;
							raw_pixel_right_o <= 2'd0;
							video_luma_left_o <= 8'd0;
							video_luma_right_o <= 8'd0;
							if (!framebuffer_handoff_effective_w &&
								!handoff_discard_pending_q) begin
								observer_alignment_error_o <= 1'b1;
							end
						end
						if (EXTERNAL_BRIGHTNESS != 0) begin
							external_brightness_pair_valid_q <= 1'b0;
						end
						left_halfword_valid_q <= 1'b0;
						right_halfword_valid_q <= 1'b0;
						handoff_discard_pending_q <= 1'b0;
					end else begin
						raw_pixel_left_o <= 2'd0;
						raw_pixel_right_o <= 2'd0;
						video_luma_left_o <= 8'd0;
						video_luma_right_o <= 8'd0;
					end

					raster_x_q <= raster_next_x_w;
					raster_y_q <= raster_next_y_w;
				end
			end

			// On ownership change, discard any half-pair instead of mixing buffers.
			if (framebuffer_handoff_effective_w) begin
				displayed_fb_q <= framebuffer_handoff_target_i;
				left_halfword_valid_q <= 1'b0;
				right_halfword_valid_q <= 1'b0;
				external_brightness_pair_valid_q <= 1'b0;
				if (!ce_i) begin
					prefetch_valid_q <= 1'b0;
					if (raster_started_q &&
						(raster_x_q < raster_h_visible_w) &&
						(raster_y_q < V_VISIBLE) &&
						(raster_native_x_w < NATIVE_WIDTH) &&
						(raster_y_q < NATIVE_HEIGHT)) begin
						handoff_discard_pending_q <= 1'b1;
					end
				end
			end else if (ce_i && fetch_frame_start_w) begin
				displayed_fb_q <= displayed_fb_i;
			end

			// Start paired mode after right-eye request and side-by-side after one response.
			if (((!side_by_side_q && phi1_i && prefetch_valid_q) ||
				 (side_by_side_q && vrm_observer_rvalid_i &&
				  observer_pending_q)) && !raster_started_q &&
				!framebuffer_handoff_effective_w) begin
				raster_started_q <= 1'b1;
			end
		end
	end

endmodule

/* verilator lint_on DECLFILENAME */
