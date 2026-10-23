// Copyright (c) 2026 Jamie Blanks

`timescale 1ns/1ps

// Copies native eye fields into stable MiSTer display storage.
//
// Each CTA group copies four columns through the VIP DP port. A complete stereo
// pair is published at a MiSTer frame boundary, so scanout never reads live VRAM.

module vip_native_framebuffer_capture
#(
	parameter NATIVE_READ_PACING = 1'b1
)
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        ce_i,
	input  wire        abort_i,

	input  wire        frame_start_i,
	input  wire        begin_enable_i,
	input  wire        source_fb_i,

	input  wire        group_accept_i,
	output wire        group_ready_o,
	input  wire        ctc_valid_i,
	input  wire        ctc_eye_i,
	input  wire [6:0]  ctc_ordinal_i,

	output wire        vram_req_o,
	output wire [15:0] vram_addr_o,
	input  wire        vram_accept_i,
	input  wire        vram_resp_valid_i,
	input  wire [15:0] vram_resp_data_i,

	input  wire        raster_commit_i,
	output reg         display_swap_o,
	output reg         display_valid_o,
	output reg  [1:0]  display_bank_o,
	output wire        pending_valid_o,
	output wire        build_active_o,

	input  wire        raster_read_enable_i,
	// Only bit 14 is unused: eye rides in bit 15, column and word below.
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire [15:0] raster_read_addr_i,
	/* verilator lint_on UNUSEDSIGNAL */
	output wire        raster_read_response_valid_o,
	output wire        raster_read_generation_valid_o,
	output wire [15:0] raster_read_data_o,

	output reg         protocol_error_o,
	output reg         unexpected_response_o,
	output wire        transfer_owner_active_o,
	output wire        raster_read_pipeline_empty_o
);
	localparam [4:0] LAST_VISIBLE_WORD = 5'd27;
	localparam [6:0] LAST_GROUP = 7'd95;

	reg        build_active_q;
	reg [1:0]  build_bank_q;
	reg        build_source_fb_q;
	reg        pending_valid_q;
	reg [1:0]  pending_bank_q;

	reg        group_reserved_q;
	reg        issue_active_q;
	reg        issue_eye_q;
	reg [6:0]  issue_ordinal_q;
	reg [1:0]  issue_column_q;
	reg [4:0]  issue_word_q;
	reg [1:0]  issue_idle_slots_q;
	reg        issue_extra_idle_q;

	reg        read_pending_q;
	reg        read_stale_q;
	reg [15:0] read_destination_q;
	reg [1:0]  read_bank_q;
	reg        read_last_q;
	reg        read_eye_q;
	reg [6:0]  read_ordinal_q;

	reg [6:0] expected_left_ordinal_q;
	reg [6:0] expected_right_ordinal_q;
	reg       left_complete_q;

	reg       raster_read_response_valid_q;
	reg       raster_read_generation_valid_q;

	// Packed field layout: 28 words per column (224 visible rows / 8),
	// so the offset is column * 28 + word, built as 32c - 4c without a DSP.
	function automatic [13:0] compact_address_fn;
		input [8:0] column_i;
		input [4:0] word_i;
		reg [13:0] column_times_32_t;
		reg [13:0] column_times_4_t;
		begin
			column_times_32_t = {column_i, 5'b00000};
			column_times_4_t = {3'b000, column_i, 2'b00};
			compact_address_fn = column_times_32_t -
				column_times_4_t + {9'd0, word_i};
		end
	endfunction

	// Three packed stereo frames use 64,512 words and fit in one 64K x 16 RAM.
	function automatic [15:0] storage_address_fn;
		input [1:0]  bank_i;
		input        eye_i;
		input [13:0] compact_i;
		reg [15:0] field_base_t;
		begin
			case ({bank_i, eye_i})
				3'b000: field_base_t = 16'h0000;
				3'b001: field_base_t = 16'h2a00;
				3'b010: field_base_t = 16'h5400;
				3'b011: field_base_t = 16'h7e00;
				3'b100: field_base_t = 16'ha800;
				3'b101: field_base_t = 16'hd200;
				// Bank 2'd3 never occurs; only banks 0-2 are allocated.
				default: field_base_t = 16'h0000;
			endcase
			storage_address_fn = field_base_t + {2'b00, compact_i};
		end
	endfunction

	wire [8:0] request_column_w =
		{issue_ordinal_q, 2'b00} + {7'd0, issue_column_q};
	wire [13:0] request_compact_address_w =
		compact_address_fn(request_column_w, issue_word_q);
	wire request_last_w = (issue_column_q == 2'd3) &&
		(issue_word_q == LAST_VISIBLE_WORD);
	// Silicon unknown: exact display slots have not been measured. Alternating
	// one and two idle slots after each issue (two reads per five slots)
	// matches measured bandwidth while keeping DP priority.
	wire request_pace_ready_w = (NATIVE_READ_PACING == 0) ||
		(issue_idle_slots_q == 2'd0);
	wire request_can_issue_w = issue_active_q && request_pace_ready_w &&
		(!read_pending_q || vram_resp_valid_i);

	assign vram_req_o = request_can_issue_w && !reset_i && !abort_i;
	assign vram_addr_o = {
		issue_eye_q,
		build_source_fb_q,
		request_column_w,
		issue_word_q
	};

	wire response_fire_w = vram_resp_valid_i && read_pending_q;
	wire response_write_w = response_fire_w && !read_stale_q &&
		build_active_q && (read_bank_q == build_bank_q);

	// Display state as it will read after a same-edge pending commit.
	wire selected_display_valid_w = display_valid_o ||
		(raster_commit_i && pending_valid_q);
	wire [1:0] selected_display_bank_w = (raster_commit_i && pending_valid_q) ?
		pending_bank_q : display_bank_o;
	wire raster_read_word_valid_w =
		raster_read_addr_i[4:0] <= LAST_VISIBLE_WORD;
	wire [13:0] raster_read_compact_address_w =
		compact_address_fn(
			raster_read_addr_i[13:5],
			raster_read_addr_i[4:0]
		);
	wire [15:0] raster_read_storage_address_w = storage_address_fn(
		selected_display_bank_w,
		raster_read_addr_i[15],
		raster_read_compact_address_w
	);

	wire begin_pending_valid_w = pending_valid_q && !raster_commit_i;
	// Pick the lowest bank not owned by the displayed or pending frame.
	reg [1:0] begin_bank_t;
	always @* begin
		if ((!selected_display_valid_w ||
			(selected_display_bank_w != 2'd0)) &&
			(!begin_pending_valid_w || (pending_bank_q != 2'd0))) begin
			begin_bank_t = 2'd0;
		end else if ((!selected_display_valid_w ||
			(selected_display_bank_w != 2'd1)) &&
			(!begin_pending_valid_w || (pending_bank_q != 2'd1))) begin
			begin_bank_t = 2'd1;
		end else begin
			begin_bank_t = 2'd2;
		end
	end

	assign group_ready_o = !build_active_q ||
		(!group_reserved_q && !issue_active_q && !read_pending_q);
	assign pending_valid_o = pending_valid_q;
	assign build_active_o = build_active_q;
	assign transfer_owner_active_o = group_reserved_q ||
		issue_active_q || read_pending_q;
	assign raster_read_response_valid_o =
		raster_read_response_valid_q;
	// Generation validity already implies a response; see the registers below.
	assign raster_read_generation_valid_o =
		raster_read_generation_valid_q;
	assign raster_read_pipeline_empty_o =
		!raster_read_enable_i && !raster_read_response_valid_q;

	wire [15:0] presentation_read_data_w;

	/* verilator lint_off PINCONNECTEMPTY */
	cache_ram_dp
	#(
		.ADDR_WIDTH(16),
		.DATA_WIDTH(16)
	)
	u_presentation_store
	(
		.clk_i(clk_i),
		.addr_a_i(read_destination_q),
		.wren_a_i(response_write_w),
		.wdata_a_i(vram_resp_data_i),
		.q_a_o(),
		.addr_b_i(raster_read_storage_address_w),
		.wren_b_i(1'b0),
		.wdata_b_i(16'd0),
		.q_b_o(presentation_read_data_w)
	);
	/* verilator lint_on PINCONNECTEMPTY */

	assign raster_read_data_o =
		raster_read_generation_valid_o ?
			presentation_read_data_w : 16'd0;

	always @(posedge clk_i) begin
		if (reset_i) begin
			build_active_q <= 1'b0;
			build_bank_q <= 2'd0;
			build_source_fb_q <= 1'b0;
			pending_valid_q <= 1'b0;
			pending_bank_q <= 2'd0;
			display_swap_o <= 1'b0;
			display_valid_o <= 1'b0;
			display_bank_o <= 2'd0;
			group_reserved_q <= 1'b0;
			issue_active_q <= 1'b0;
			issue_eye_q <= 1'b0;
			issue_ordinal_q <= 7'd0;
			issue_column_q <= 2'd0;
			issue_word_q <= 5'd0;
			issue_idle_slots_q <= 2'd0;
			issue_extra_idle_q <= 1'b0;
			read_pending_q <= 1'b0;
			read_stale_q <= 1'b0;
			read_destination_q <= 16'd0;
			read_bank_q <= 2'd0;
			read_last_q <= 1'b0;
			read_eye_q <= 1'b0;
			read_ordinal_q <= 7'd0;
			expected_left_ordinal_q <= 7'd0;
			expected_right_ordinal_q <= 7'd0;
			left_complete_q <= 1'b0;
			raster_read_response_valid_q <= 1'b0;
			raster_read_generation_valid_q <= 1'b0;
			protocol_error_o <= 1'b0;
			unexpected_response_o <= 1'b0;
		end else begin
			display_swap_o <= 1'b0;
			// Default decrement; abort, frame start, and a new issue below
			// override it through last-assignment-wins.
			if (ce_i && (issue_idle_slots_q != 2'd0)) begin
				issue_idle_slots_q <= issue_idle_slots_q - 2'd1;
			end
			// Scanout read pipe runs on every clk_i, not the ce_i domain.
			raster_read_response_valid_q <= raster_read_enable_i;
			raster_read_generation_valid_q <=
				raster_read_enable_i &&
				raster_read_word_valid_w &&
				selected_display_valid_w;

			if (vram_resp_valid_i && !read_pending_q) begin
				unexpected_response_o <= 1'b1;
			end

			if (raster_commit_i && pending_valid_q) begin
				display_valid_o <= 1'b1;
				display_bank_o <= pending_bank_q;
				pending_valid_q <= 1'b0;
				display_swap_o <= 1'b1;
			end

			if (response_fire_w) begin
				read_pending_q <= 1'b0;
				read_stale_q <= 1'b0;

				if (!read_stale_q && build_active_q &&
					(read_bank_q == build_bank_q) &&
					read_last_q) begin
					group_reserved_q <= 1'b0;
					if (!read_eye_q) begin
						if (read_ordinal_q !=
							expected_left_ordinal_q) begin
							protocol_error_o <= 1'b1;
							build_active_q <= 1'b0;
						end else if (read_ordinal_q == LAST_GROUP) begin
							// 96 is a beyond-last sentinel no CTC ordinal matches.
							expected_left_ordinal_q <= 7'd96;
							left_complete_q <= 1'b1;
						end else begin
							expected_left_ordinal_q <=
								expected_left_ordinal_q + 7'd1;
						end
					end else begin
						if ((read_ordinal_q !=
							expected_right_ordinal_q) ||
							((read_ordinal_q == LAST_GROUP) &&
							 !left_complete_q)) begin
							protocol_error_o <= 1'b1;
							build_active_q <= 1'b0;
						end else if ((read_ordinal_q == LAST_GROUP) &&
							pending_valid_q && !raster_commit_i) begin
							protocol_error_o <= 1'b1;
							build_active_q <= 1'b0;
						end else if (read_ordinal_q == LAST_GROUP) begin
							expected_right_ordinal_q <= 7'd96;
							build_active_q <= 1'b0;
							pending_valid_q <= 1'b1;
							pending_bank_q <= build_bank_q;
						end else begin
							expected_right_ordinal_q <=
								expected_right_ordinal_q + 7'd1;
						end
					end
				end
			end

			if (abort_i) begin
				build_active_q <= 1'b0;
				group_reserved_q <= 1'b0;
				issue_active_q <= 1'b0;
				issue_idle_slots_q <= 2'd0;
				issue_extra_idle_q <= 1'b0;
				if (read_pending_q) begin
					read_stale_q <= 1'b1;
				end
			end else begin
				if (frame_start_i) begin
					group_reserved_q <= 1'b0;
					issue_active_q <= 1'b0;
					issue_idle_slots_q <= 2'd0;
					issue_extra_idle_q <= 1'b0;
					expected_left_ordinal_q <= 7'd0;
					expected_right_ordinal_q <= 7'd0;
					left_complete_q <= 1'b0;

					// A still-pending VRAM read blocks a new build.
					if (begin_enable_i && !read_pending_q) begin
						build_active_q <= 1'b1;
						build_bank_q <= begin_bank_t;
						build_source_fb_q <= source_fb_i;
					end else begin
						build_active_q <= 1'b0;
					end
				end

				if (ce_i && group_accept_i) begin
					if (build_active_q && group_ready_o) begin
						group_reserved_q <= 1'b1;
					end else if (build_active_q) begin
						protocol_error_o <= 1'b1;
						build_active_q <= 1'b0;
					end
				end

				if (ce_i && ctc_valid_i) begin
					if (build_active_q) begin
						if (!group_reserved_q ||
							issue_active_q || read_pending_q ||
							(!ctc_eye_i &&
							 (ctc_ordinal_i !=
							  expected_left_ordinal_q)) ||
							(ctc_eye_i &&
							 (ctc_ordinal_i !=
							  expected_right_ordinal_q))) begin
							protocol_error_o <= 1'b1;
							build_active_q <= 1'b0;
							group_reserved_q <= 1'b0;
						end else begin
							issue_active_q <= 1'b1;
							issue_idle_slots_q <= 2'd0;
							issue_extra_idle_q <= 1'b0;
							issue_eye_q <= ctc_eye_i;
							issue_ordinal_q <= ctc_ordinal_i;
							issue_column_q <= 2'd0;
							issue_word_q <= 5'd0;
						end
					end else begin
						group_reserved_q <= 1'b0;
					end
				end

				if (ce_i && vram_req_o && vram_accept_i) begin
					if (NATIVE_READ_PACING != 0) begin
						issue_idle_slots_q <= issue_extra_idle_q ?
							2'd2 : 2'd1;
						issue_extra_idle_q <= !issue_extra_idle_q;
					end
					read_pending_q <= 1'b1;
					read_stale_q <= 1'b0;
					read_destination_q <= storage_address_fn(
						build_bank_q,
						issue_eye_q,
						request_compact_address_w
					);
					read_bank_q <= build_bank_q;
					read_last_q <= request_last_w;
					read_eye_q <= issue_eye_q;
					read_ordinal_q <= issue_ordinal_q;

					if (request_last_w) begin
						issue_active_q <= 1'b0;
					end else if (issue_word_q ==
						LAST_VISIBLE_WORD) begin
						issue_column_q <=
							issue_column_q + 2'd1;
						issue_word_q <= 5'd0;
					end else begin
						issue_word_q <= issue_word_q + 5'd1;
					end
				end
			end
		end
	end

endmodule
