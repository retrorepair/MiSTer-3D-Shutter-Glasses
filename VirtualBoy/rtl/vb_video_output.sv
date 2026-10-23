// Copyright (c) 2026 Jamie Blanks

// MiSTer startup, free-running video timing, and Virtual Boy line conversion.
// Public sync runs independently, and core pixels start only at a frame boundary.

module vb_startup_osd_button
#(
	parameter [24:0] WAIT_CYCLES = 25'd20000000,
	parameter [24:0] END_CYCLES  = 25'd24000000
)
(
	input  wire clk_i,
	input  wire ce_i,
	input  wire reset_i,
	input  wire rom_download_i,
	input  wire rom_loaded_i,
	output wire osd_button_o
);

	reg [24:0] timeout_q;

	wire idle_without_rom_w = !reset_i && !rom_download_i &&
		!rom_loaded_i;
	wire button_window_w = (timeout_q >= WAIT_CYCLES) &&
		(timeout_q < END_CYCLES);

	// ROM activity restarts the idle timer; a loaded game keeps it at zero.
	always @(posedge clk_i) begin
		if (reset_i || rom_download_i || rom_loaded_i) begin
			timeout_q <= 25'd0;
		end else if (ce_i && (timeout_q < END_CYCLES)) begin
			timeout_q <= timeout_q + 25'd1;
		end
	end

	assign osd_button_o = idle_without_rom_w && button_window_w;

endmodule

module vb_video_source_coordinator
(
	input  wire clk_i,
	input  wire reset_i,
	input  wire core_reset_i,
	input  wire execution_block_i,
	input  wire pause_req_i,
	input  wire pause_ready_i,
	input  wire frame_wrap_i,
	output reg  pause_active_o,
	output reg  core_enable_o,
	output reg  source_enable_o
);

	always @(posedge clk_i) begin
		if (reset_i) begin
			pause_active_o <= 1'b0;
			core_enable_o <= 1'b0;
			source_enable_o <= 1'b0;
		end else begin
			if (pause_req_i) begin
				if (pause_ready_i) begin
					pause_active_o <= 1'b1;
					core_enable_o <= 1'b0;
					source_enable_o <= 1'b0;
				end
			end else if (pause_active_o) begin
				// Keep the console stopped until the public raster reaches frame start.
				if (frame_wrap_i && !core_reset_i &&
					!execution_block_i) begin
					pause_active_o <= 1'b0;
					core_enable_o <= 1'b1;
					source_enable_o <= 1'b1;
				end
			end else if (frame_wrap_i && !core_reset_i) begin
				if (execution_block_i) begin
					// Start queued loads and initialization at this frame edge.
					core_enable_o <= 1'b0;
					source_enable_o <= 1'b0;
				end else begin
					// Reset, ROM load, and transfer release share this frame start.
					core_enable_o <= 1'b1;
					source_enable_o <= 1'b1;
				end
			end

			if (core_reset_i) begin
				core_enable_o <= 1'b0;
				source_enable_o <= 1'b0;
			end
		end
	end

endmodule

module vb_free_running_video
#(
	parameter [10:0] NORMAL_H_TOTAL        = 11'd640,
	parameter [10:0] NORMAL_H_ACTIVE_START = 11'd192,
	parameter [10:0] NORMAL_H_ACTIVE_END   = 11'd576,
	parameter [10:0] NORMAL_H_SYNC_END     = 11'd48,
	parameter [10:0] SBS_H_TOTAL           = 11'd1280,
	parameter [10:0] SBS_H_ACTIVE_START    = 11'd384,
	parameter [10:0] SBS_H_ACTIVE_END      = 11'd1152,
	parameter [10:0] SBS_H_SYNC_END        = 11'd96,
	parameter [8:0]  V_VISIBLE             = 9'd224,
	parameter [8:0]  V_TOTAL               = 9'd312,
	// Leave 16 extra post-sync lines before active video for CRTs.
	parameter [8:0]  V_SYNC_BEG            = 9'd273,
	parameter [8:0]  V_SYNC_END            = 9'd276,
	// One 40 MHz raw line contains 2,560 pixel-service clocks followed by
	// blanking-only cadence correction. Thirty-two VBlank lines carry one
	// additional raw clock so 312 lines total exactly 800,000 clocks (50 Hz).
	parameter [11:0] RAW_ACTIVE_CLOCKS      = 12'd2560,
	parameter [11:0] RAW_LINE_LAST          = 12'd2563,
	parameter [11:0] RAW_LONG_LINE_LAST     = 12'd2564,
	parameter [8:0]  LONG_LINE_BEG          = 9'd224,
	parameter [8:0]  LONG_LINE_END          = 9'd256,
	// Fixed progressive NTSC-compatibility raster. At 40 MHz this is
	// 15.7356 kHz horizontal and 60.0597 Hz vertical. Every line is full
	// length; there are no half-lines or alternating fields.
	parameter [10:0] COMPAT_NORMAL_H_TOTAL  = 11'd635,
	parameter [10:0] COMPAT_NORMAL_H_ACTIVE_START = 11'd160,
	parameter [10:0] COMPAT_NORMAL_H_ACTIVE_END = 11'd544,
	parameter [10:0] COMPAT_SBS_H_TOTAL     = 11'd1270,
	parameter [10:0] COMPAT_SBS_H_ACTIVE_START = 11'd320,
	parameter [10:0] COMPAT_SBS_H_ACTIVE_END = 11'd1088,
	parameter [8:0]  COMPAT_V_TOTAL         = 9'd262,
	parameter [8:0]  COMPAT_V_SYNC_BEG      = 9'd243,
	parameter [8:0]  COMPAT_V_SYNC_END      = 9'd246,
	parameter [11:0] COMPAT_RAW_ACTIVE_CLOCKS = 12'd2540,
	parameter [11:0] COMPAT_RAW_LINE_LAST   = 12'd2541,
	// 3D shutter-glasses raster: the compatibility raster shortened to 256 lines. One frame is then 16.27 ms (61.5 Hz)
	// and a left+right pair 32.54 ms, below the 32.7 ms the Bluetooth glasses' 15-bit frame period counter allows.
	parameter [8:0]  SHUTTER_V_TOTAL       = 9'd256,
	parameter [8:0]  SHUTTER_V_SYNC_BEG    = 9'd237,
	parameter [8:0]  SHUTTER_V_SYNC_END    = 9'd240
)
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        side_by_side_req_i,
	input  wire        compat_60hz_req_i,
	input  wire        shutter_req_i,
	output wire        side_by_side_o,
	output wire        compat_60hz_o,
	output wire        shutter_o,
	output wire        pixel_ce_o,
	output wire        source_timing_ce_o,
	output wire [10:0] raster_x_o,
	output wire [10:0] active_start_o,
	output reg  [8:0]  raster_y_o,
	output wire        frame_wrap_o,
	output wire        hsync_o,
	output wire        vsync_o,
	output wire        de_o
);

	reg side_by_side_q;
	reg compat_60hz_q;
	reg compat_60hz_pending_q;
	reg shutter_q;
	reg shutter_pending_q;
	reg [11:0] raw_line_clock_q;
	wire compat_60hz_requested_w = compat_60hz_req_i;

	wire [10:0] h_active_start_w = compat_60hz_q ?
		(side_by_side_q ? COMPAT_SBS_H_ACTIVE_START :
			COMPAT_NORMAL_H_ACTIVE_START) :
		(side_by_side_q ? SBS_H_ACTIVE_START : NORMAL_H_ACTIVE_START);
	wire [10:0] h_active_end_w = compat_60hz_q ?
		(side_by_side_q ? COMPAT_SBS_H_ACTIVE_END :
			COMPAT_NORMAL_H_ACTIVE_END) :
		(side_by_side_q ? SBS_H_ACTIVE_END : NORMAL_H_ACTIVE_END);
	wire [10:0] h_sync_end_w = side_by_side_q ?
		SBS_H_SYNC_END : NORMAL_H_SYNC_END;
	wire [10:0] normal_h_total_w = compat_60hz_q ?
		COMPAT_NORMAL_H_TOTAL : NORMAL_H_TOTAL;
	wire [10:0] sbs_h_total_w = compat_60hz_q ?
		COMPAT_SBS_H_TOTAL : SBS_H_TOTAL;
	wire [8:0] v_total_w = shutter_q ? SHUTTER_V_TOTAL : (compat_60hz_q ? COMPAT_V_TOTAL : V_TOTAL);
	wire [8:0] v_sync_beg_w = shutter_q ? SHUTTER_V_SYNC_BEG : (compat_60hz_q ?
		COMPAT_V_SYNC_BEG : V_SYNC_BEG);
	wire [8:0] v_sync_end_w = shutter_q ? SHUTTER_V_SYNC_END : (compat_60hz_q ?
		COMPAT_V_SYNC_END : V_SYNC_END);
	wire [8:0] v_last_w = v_total_w - 9'd1;
	wire long_line_w = (raster_y_o >= LONG_LINE_BEG) &&
		(raster_y_o < LONG_LINE_END);
	wire [11:0] raw_active_clocks_w = compat_60hz_q ?
		COMPAT_RAW_ACTIVE_CLOCKS : RAW_ACTIVE_CLOCKS;
	wire [11:0] raw_line_last_w = compat_60hz_q ?
		COMPAT_RAW_LINE_LAST :
		(long_line_w ? RAW_LONG_LINE_LAST : RAW_LINE_LAST);
	wire [11:0] source_last_clock_w = compat_60hz_q ?
		(side_by_side_q ? 12'd2539 : 12'd2538) :
		(side_by_side_q ? 12'd2559 : 12'd2558);
	wire source_frame_terminal_w =
		(raw_line_clock_q == source_last_clock_w) &&
		(raster_y_o == v_last_w);
	wire active_raw_clock_w = raw_line_clock_q < raw_active_clocks_w;
	wire public_sample_clock_w = side_by_side_q ?
		(raster_x_o < sbs_h_total_w) :
		(raster_x_o < normal_h_total_w);
	wire normal_pixel_phase_w = raw_line_clock_q[1:0] == 2'd0;
	wire sbs_pixel_phase_w = raw_line_clock_q[0] == 1'b0;

	assign side_by_side_o = side_by_side_q;
	assign compat_60hz_o = compat_60hz_q;
	assign shutter_o = shutter_q;
	assign pixel_ce_o = !reset_i && active_raw_clock_w && public_sample_clock_w &&
		(side_by_side_q ? sbs_pixel_phase_w : normal_pixel_phase_w);
	assign source_timing_ce_o = !reset_i && active_raw_clock_w &&
		(side_by_side_q || sbs_pixel_phase_w);
	assign raster_x_o = side_by_side_q ? raw_line_clock_q[11:1] :
		{1'b0, raw_line_clock_q[11:2]};
	assign active_start_o = h_active_start_w;
	assign frame_wrap_o = !reset_i &&
		(raw_line_clock_q == raw_line_last_w) &&
		(raster_y_o == v_last_w);
	assign hsync_o = active_raw_clock_w &&
		(raster_x_o < h_sync_end_w);
	assign vsync_o = (raster_y_o >= v_sync_beg_w) &&
		(raster_y_o < v_sync_end_w);
	assign de_o = active_raw_clock_w &&
		(raster_x_o >= h_active_start_w) &&
		(raster_x_o < h_active_end_w) && (raster_y_o < V_VISIBLE);

	always @(posedge clk_i) begin
		if (reset_i) begin
			side_by_side_q <= 1'b0;
			compat_60hz_q <= 1'b0;
			compat_60hz_pending_q <= 1'b0;
			shutter_q <= 1'b0;
			shutter_pending_q <= 1'b0;
			raw_line_clock_q <= 12'd0;
			raster_y_o <= 9'd0;
		end else begin
			// Capture the menu choice before terminal blanking. The VIP reader
			// receives this committed selection on line zero of the new frame.
			if (source_frame_terminal_w) begin
				compat_60hz_pending_q <= compat_60hz_requested_w;
				shutter_pending_q <= shutter_req_i;
			end
			if (raw_line_clock_q == raw_line_last_w) begin
				raw_line_clock_q <= 12'd0;
				if (raster_y_o == v_last_w) begin
					raster_y_o <= 9'd0;
					side_by_side_q <= side_by_side_req_i;
					compat_60hz_q <= compat_60hz_pending_q;
					shutter_q <= shutter_pending_q;
				end else begin
					raster_y_o <= raster_y_o + 9'd1;
				end
			end else begin
				raw_line_clock_q <= raw_line_clock_q + 12'd1;
			end
		end
	end

endmodule

module vb_crt_line_bridge
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        source_ce_i,
	input  wire        source_present_i,
	input  wire        side_by_side_i,
	input  wire [7:0]  source_red_i,
	input  wire [7:0]  source_green_i,
	input  wire [7:0]  source_blue_i,
	input  wire        source_hblank_i,
	input  wire        source_vblank_i,
	input  wire [10:0] public_x_i,
	input  wire [10:0] public_active_start_i,
	input  wire        public_de_i,
	output wire [7:0]  red_o,
	output wire [7:0]  green_o,
	output wire [7:0]  blue_o
);

	// Sample the newly registered source pixel one 40 MHz clock after its enable.
	reg        source_ce_q;
	reg        source_hblank_q;
	reg        line_locked_q;
	reg        side_by_side_q;
	reg  [9:0] write_addr_q;

	wire source_line_start_w = source_ce_q && source_hblank_q &&
		!source_hblank_i;
	wire source_active_w = source_ce_q && source_present_i &&
		!source_hblank_i && !source_vblank_i;
	wire [9:0] write_addr_w = source_line_start_w ? 10'd0 : write_addr_q;
	/* verilator lint_off UNUSEDSIGNAL */
	wire [10:0] read_offset_w = public_x_i - public_active_start_i;
	wire [10:0] read_prefetch_offset_w = read_offset_w + 11'd1;
	/* verilator lint_on UNUSEDSIGNAL */
	// The synchronous read is observed one clock after its address. Keep column
	// zero prefetched in blanking, then request the following column during DE.
	// Active width is at most 768 pixels, so bit 10 is unused.
	wire [9:0] read_addr_w = public_de_i ?
		read_prefetch_offset_w[9:0] : 10'd0;
	wire [23:0] line_pixel_w;
	wire source_pixel_valid_w = source_present_i && line_locked_q &&
		public_de_i && !source_vblank_i &&
		(side_by_side_q == side_by_side_i);

	/* verilator lint_off PINCONNECTEMPTY */
	cache_ram_dp #(
		.ADDR_WIDTH(10),
		.DATA_WIDTH(24)
	) u_crt_line_ram (
		.clk_i(clk_i),
		.addr_a_i(write_addr_w),
		.wren_a_i(source_active_w),
		.wdata_a_i({source_red_i, source_green_i, source_blue_i}),
		.q_a_o(),
		.addr_b_i(read_addr_w),
		.wren_b_i(1'b0),
		.wdata_b_i(24'd0),
		.q_b_o(line_pixel_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	always @(posedge clk_i) begin
		if (reset_i || !source_present_i ||
			(side_by_side_q != side_by_side_i)) begin
			source_ce_q <= 1'b0;
			source_hblank_q <= 1'b1;
			line_locked_q <= 1'b0;
			side_by_side_q <= side_by_side_i;
			write_addr_q <= 10'd0;
		end else begin
			source_ce_q <= source_ce_i;
			if (source_ce_q) begin
				source_hblank_q <= source_hblank_i;
				if (source_line_start_w) begin
					line_locked_q <= 1'b1;
					write_addr_q <= source_active_w ? 10'd1 : 10'd0;
				end else if (source_active_w) begin
					write_addr_q <= write_addr_q + 10'd1;
				end
			end
		end
	end

	assign red_o = source_pixel_valid_w ? line_pixel_w[23:16] : 8'd0;
	assign green_o = source_pixel_valid_w ? line_pixel_w[15:8] : 8'd0;
	assign blue_o = source_pixel_valid_w ? line_pixel_w[7:0] : 8'd0;

endmodule

module vb_video_output
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        side_by_side_req_i,
	input  wire        compat_60hz_req_i,
	input  wire        shutter_req_i,
	input  wire        source_ce_i,
	input  wire        source_present_i,
	input  wire [7:0]  source_red_i,
	input  wire [7:0]  source_green_i,
	input  wire [7:0]  source_blue_i,
	input  wire        source_hblank_i,
	input  wire        source_vblank_i,
	output wire        side_by_side_o,
	output wire        compat_60hz_o,
	output wire        shutter_o,
	output wire        frame_wrap_o,
	output wire        pixel_ce_o,
	output wire        source_timing_ce_o,
	output wire [7:0]  red_o,
	output wire [7:0]  green_o,
	output wire [7:0]  blue_o,
	output wire        hsync_o,
	output wire        vsync_o,
	output wire        de_o
);

	wire [10:0] public_x_w;
	wire [10:0] public_active_start_w;
	wire public_de_w;

	/* verilator lint_off PINCONNECTEMPTY */
	vb_free_running_video u_free_running_video (
		.clk_i(clk_i),
		.reset_i(reset_i),
		.side_by_side_req_i(side_by_side_req_i),
		.compat_60hz_req_i(compat_60hz_req_i),
		.shutter_req_i(shutter_req_i),
		.side_by_side_o(side_by_side_o),
		.compat_60hz_o(compat_60hz_o),
		.shutter_o(shutter_o),
		.pixel_ce_o(pixel_ce_o),
		.source_timing_ce_o(source_timing_ce_o),
		.raster_x_o(public_x_w),
		.active_start_o(public_active_start_w),
		.raster_y_o(),
		.frame_wrap_o(frame_wrap_o),
		.hsync_o(hsync_o),
		.vsync_o(vsync_o),
		.de_o(public_de_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	vb_crt_line_bridge u_crt_line_bridge (
		.clk_i(clk_i),
		.reset_i(reset_i),
		.source_ce_i(source_ce_i),
		.source_present_i(source_present_i),
		.side_by_side_i(side_by_side_o),
		.source_red_i(source_red_i),
		.source_green_i(source_green_i),
		.source_blue_i(source_blue_i),
		.source_hblank_i(source_hblank_i),
		.source_vblank_i(source_vblank_i),
		.public_x_i(public_x_w),
		.public_active_start_i(public_active_start_w),
		.public_de_i(public_de_w),
		.red_o(red_o),
		.green_o(green_o),
		.blue_o(blue_o)
	);

	assign de_o = public_de_w;

endmodule
