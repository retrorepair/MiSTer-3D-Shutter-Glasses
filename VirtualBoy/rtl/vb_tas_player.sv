// Copyright (c) 2026 Jamie Blanks

// VBTAS version-1 loader and controller-poll player. The fixed header is
// validated while payload words are packed into 64-bit MiSTer DDR3 writes.
// The first two beats are retained in registers so word zero is available
// before the console leaves reset.
module vb_tas_player #(
	// ddram channel addresses carry physical byte-address bits 27:1. This is
	// physical DDR3 address 0x31000000 after ddram adds its 0x30000000 window.
	parameter [27:1] DDR_BASE_ADDR = 27'h0800000
) (
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        cancel_i,

	input  wire        download_i,
	input  wire        write_i,
	input  wire [26:0] addr_i,
	input  wire [15:0] data_i,
	output wire        ioctl_wait_o,

	input  wire        pad_latch_i,
	output wire [15:0] pad_word_o,
	output wire        pad_override_o,
	output wire        hold_reset_o,
	output reg         load_start_o,
	output wire        loaded_o,
	output wire        complete_o,
	output wire        load_error_o,
	output wire        fault_o,

	output reg  [27:1] ddr_addr_o,
	input  wire [63:0] ddr_dout_i,
	output reg  [63:0] ddr_din_o,
	output reg         ddr_req_o,
	output reg         ddr_rnw_o,
	output reg  [7:0]  ddr_be_o,
	input  wire        ddr_ready_i
);

	localparam [15:0] VBTAS_MAGIC_LO = 16'h4256;
	localparam [15:0] VBTAS_MAGIC_HI = 16'h4d54;
	localparam [15:0] VBTAS_VERSION = 16'd1;
	localparam [15:0] VBTAS_HEADER_SIZE = 16'd32;
	localparam [15:0] VBTAS_RATE_NUM_LO = 16'h312d;
	localparam [15:0] VBTAS_RATE_NUM_HI = 16'h0001;
	localparam [15:0] VBTAS_RATE_DEN_LO = 16'h0612;
	localparam [15:0] VBTAS_RATE_DEN_HI = 16'h0000;
	localparam [15:0] PAD_IDLE = 16'h0002;
	localparam [24:0] MAX_FRAME_COUNT = 25'h0800000;

	reg download_q;
	reg pad_latch_q;
	reg load_hold_q;
	reg finalize_q;
	reg loaded_q;
	reg complete_q;
	reg load_error_q;
	reg fault_q;
	reg header_valid_q;
	reg [15:0] header_seen_q;
	reg battery_flag_q;
	reg battery_seen_q;
	reg [31:0] frame_count_q;
	reg [31:0] expected_crc_q;
	reg [31:0] crc_q;
	reg [26:0] expected_addr_q;
	reg [24:0] payload_count_q;
	reg [1:0] pack_count_q;
	reg [63:0] pack_data_q;
	reg [21:0] write_beat_q;
	reg [1:0] prefill_count_q;
	reg [63:0] buffer0_q;
	reg [63:0] buffer1_q;
	reg [1:0] buffer_count_q;
	reg [1:0] word_lane_q;
	reg [23:0] frame_index_q;
	reg [21:0] total_beats_q;
	reg [21:0] next_read_beat_q;
	reg ddr_busy_q;

	wire download_start_w = download_i && !download_q;
	wire download_end_w = !download_i && download_q;
	wire pad_latch_rise_w = pad_latch_i && !pad_latch_q;
	wire write_accept_w = download_i && write_i && !ioctl_wait_o;
	wire payload_write_w = write_accept_w && (addr_i >= 27'd32);
	wire ddr_read_ack_w = ddr_busy_q && ddr_rnw_o && ddr_ready_i;
	wire [63:0] completed_beat_w = {data_i, pack_data_q[47:0]};
	wire [21:0] frame_total_beats_w =
		frame_count_q[23:2] + {21'd0, |frame_count_q[1:0]};
	wire load_valid_w = header_valid_q && (header_seen_q == 16'hffff) &&
		(frame_count_q != 32'd0) &&
		(frame_count_q <= {7'd0, MAX_FRAME_COUNT}) &&
		(payload_count_q == {1'b0, frame_count_q[23:0]}) &&
		(expected_crc_q == ~crc_q) &&
		(battery_flag_q == battery_seen_q) &&
		(prefill_count_q != 2'd0);

	function automatic [31:0] crc32_byte_fn;
		input [31:0] crc_v;
		input [7:0] data_v;
		reg [31:0] value_v;
		integer bit_index_v;
		begin
			value_v = crc_v ^ {24'd0, data_v};
			for (bit_index_v = 0; bit_index_v < 8;
				bit_index_v = bit_index_v + 1) begin
				if (value_v[0]) begin
					value_v = (value_v >> 1) ^ 32'hedb88320;
				end else begin
					value_v = value_v >> 1;
				end
			end
			crc32_byte_fn = value_v;
		end
	endfunction

	function automatic [31:0] crc32_word_fn;
		input [31:0] crc_v;
		input [15:0] data_v;
		reg [31:0] low_byte_crc_v;
		begin
			low_byte_crc_v = crc32_byte_fn(crc_v, data_v[7:0]);
			crc32_word_fn = crc32_byte_fn(low_byte_crc_v, data_v[15:8]);
		end
	endfunction

	function automatic [7:0] partial_be_fn;
		input [1:0] word_count_v;
		begin
			case (word_count_v)
				2'd1: partial_be_fn = 8'h03;
				2'd2: partial_be_fn = 8'h0f;
				2'd3: partial_be_fn = 8'h3f;
				default: partial_be_fn = 8'h00;
			endcase
		end
	endfunction

	function automatic [15:0] selected_word_fn;
		input [63:0] beat_v;
		input [1:0] lane_v;
		begin
			case (lane_v)
				2'd0: selected_word_fn = beat_v[15:0];
				2'd1: selected_word_fn = beat_v[31:16];
				2'd2: selected_word_fn = beat_v[47:32];
				default: selected_word_fn = beat_v[63:48];
			endcase
		end
	endfunction

	// Match the ROM loader's one-cycle admission guard so a first WIDE word
	// cannot coincide with download-state initialization.
	assign ioctl_wait_o = download_i && (!download_q || ddr_busy_q);
	assign hold_reset_o = download_i || load_hold_q || fault_q;
	assign pad_override_o = loaded_q;
	assign pad_word_o = loaded_q && !complete_q && !fault_q &&
		(buffer_count_q != 2'd0) ?
		selected_word_fn(buffer0_q, word_lane_q) : PAD_IDLE;
	assign loaded_o = loaded_q;
	assign complete_o = complete_q;
	assign load_error_o = load_error_q;
	assign fault_o = fault_q;

	always @(posedge clk_i) begin
		if (reset_i) begin
			download_q <= 1'b0;
			pad_latch_q <= 1'b0;
			load_hold_q <= 1'b0;
			finalize_q <= 1'b0;
			loaded_q <= 1'b0;
			complete_q <= 1'b0;
			load_error_q <= 1'b0;
			fault_q <= 1'b0;
			header_valid_q <= 1'b0;
			header_seen_q <= 16'd0;
			battery_flag_q <= 1'b0;
			battery_seen_q <= 1'b0;
			frame_count_q <= 32'd0;
			expected_crc_q <= 32'd0;
			crc_q <= 32'hffffffff;
			expected_addr_q <= 27'd0;
			payload_count_q <= 25'd0;
			pack_count_q <= 2'd0;
			pack_data_q <= 64'd0;
			write_beat_q <= 22'd0;
			prefill_count_q <= 2'd0;
			buffer0_q <= 64'd0;
			buffer1_q <= 64'd0;
			buffer_count_q <= 2'd0;
			word_lane_q <= 2'd0;
			frame_index_q <= 24'd0;
			total_beats_q <= 22'd0;
			next_read_beat_q <= 22'd0;
			ddr_busy_q <= 1'b0;
			ddr_addr_o <= 27'd0;
			ddr_din_o <= 64'd0;
			ddr_req_o <= 1'b0;
			ddr_rnw_o <= 1'b0;
			ddr_be_o <= 8'd0;
			load_start_o <= 1'b0;
		end else begin
			download_q <= download_i;
			pad_latch_q <= pad_latch_i;
			ddr_req_o <= 1'b0;
			load_start_o <= 1'b0;

			if (ddr_busy_q && ddr_ready_i) begin
				ddr_busy_q <= 1'b0;
			end

			if (cancel_i && !download_i) begin
				load_hold_q <= 1'b0;
				finalize_q <= 1'b0;
				loaded_q <= 1'b0;
				complete_q <= 1'b0;
				load_error_q <= 1'b0;
				fault_q <= 1'b0;
				buffer_count_q <= 2'd0;
				word_lane_q <= 2'd0;
			end

			if (download_start_w) begin
				load_hold_q <= 1'b1;
				finalize_q <= 1'b0;
				loaded_q <= 1'b0;
				complete_q <= 1'b0;
				load_error_q <= 1'b0;
				fault_q <= 1'b0;
				header_valid_q <= 1'b1;
				header_seen_q <= 16'd0;
				battery_flag_q <= 1'b0;
				battery_seen_q <= 1'b0;
				frame_count_q <= 32'd0;
				expected_crc_q <= 32'd0;
				crc_q <= 32'hffffffff;
				expected_addr_q <= 27'd0;
				payload_count_q <= 25'd0;
				pack_count_q <= 2'd0;
				pack_data_q <= 64'd0;
				write_beat_q <= 22'd0;
				prefill_count_q <= 2'd0;
				buffer0_q <= 64'd0;
				buffer1_q <= 64'd0;
				buffer_count_q <= 2'd0;
				word_lane_q <= 2'd0;
				frame_index_q <= 24'd0;
				total_beats_q <= 22'd0;
				next_read_beat_q <= 22'd0;
				load_start_o <= 1'b1;
			end else if (write_accept_w) begin
				if (addr_i != expected_addr_q) begin
					header_valid_q <= 1'b0;
				end
				expected_addr_q <= expected_addr_q + 27'd2;

				if (addr_i < 27'd32) begin
					header_seen_q[addr_i[4:1]] <= 1'b1;
					case (addr_i[4:1])
						4'd0: if (data_i != VBTAS_MAGIC_LO) header_valid_q <= 1'b0;
						4'd1: if (data_i != VBTAS_MAGIC_HI) header_valid_q <= 1'b0;
						4'd2: if (data_i != VBTAS_VERSION) header_valid_q <= 1'b0;
						4'd3: if (data_i != VBTAS_HEADER_SIZE) header_valid_q <= 1'b0;
						4'd4: begin
							battery_flag_q <= data_i[1];
							if (!data_i[0] || (data_i[15:2] != 14'd0)) begin
								header_valid_q <= 1'b0;
							end
						end
						4'd5: if (data_i != 16'd0) header_valid_q <= 1'b0;
						4'd6: frame_count_q[15:0] <= data_i;
						4'd7: frame_count_q[31:16] <= data_i;
						4'd8: if (data_i != VBTAS_RATE_NUM_LO) header_valid_q <= 1'b0;
						4'd9: if (data_i != VBTAS_RATE_NUM_HI) header_valid_q <= 1'b0;
						4'd10: if (data_i != VBTAS_RATE_DEN_LO) header_valid_q <= 1'b0;
						4'd11: if (data_i != VBTAS_RATE_DEN_HI) header_valid_q <= 1'b0;
						4'd12: expected_crc_q[15:0] <= data_i;
						4'd13: expected_crc_q[31:16] <= data_i;
						4'd14,
						4'd15: if (data_i != 16'd0) header_valid_q <= 1'b0;
						default: header_valid_q <= 1'b0;
					endcase
				end else if (payload_write_w) begin
					if (payload_count_q >= MAX_FRAME_COUNT) begin
						header_valid_q <= 1'b0;
						if (payload_count_q == MAX_FRAME_COUNT) begin
							payload_count_q <= payload_count_q + 25'd1;
						end
					end else begin
						payload_count_q <= payload_count_q + 25'd1;
						crc_q <= crc32_word_fn(crc_q, data_i);
						battery_seen_q <= battery_seen_q || data_i[0];
						if (!data_i[1]) begin
							header_valid_q <= 1'b0;
						end

						case (pack_count_q)
							2'd0: pack_data_q[15:0] <= data_i;
							2'd1: pack_data_q[31:16] <= data_i;
							2'd2: pack_data_q[47:32] <= data_i;
							default: begin
								ddr_addr_o <= DDR_BASE_ADDR +
									{3'd0, write_beat_q, 2'b00};
								ddr_din_o <= completed_beat_w;
								ddr_rnw_o <= 1'b0;
								ddr_be_o <= 8'hff;
								ddr_req_o <= 1'b1;
								ddr_busy_q <= 1'b1;
								write_beat_q <= write_beat_q + 22'd1;
								if (prefill_count_q == 2'd0) begin
									buffer0_q <= completed_beat_w;
									prefill_count_q <= 2'd1;
								end else if (prefill_count_q == 2'd1) begin
									buffer1_q <= completed_beat_w;
									prefill_count_q <= 2'd2;
								end
								pack_data_q <= 64'd0;
							end
						endcase
						if (pack_count_q == 2'd3) begin
							pack_count_q <= 2'd0;
						end else begin
							pack_count_q <= pack_count_q + 2'd1;
						end
					end
				end else begin
					header_valid_q <= 1'b0;
				end
			end

			if (download_end_w) begin
				finalize_q <= 1'b1;
				if (pack_count_q != 2'd0) begin
					ddr_addr_o <= DDR_BASE_ADDR +
						{3'd0, write_beat_q, 2'b00};
					ddr_din_o <= pack_data_q;
					ddr_rnw_o <= 1'b0;
					ddr_be_o <= partial_be_fn(pack_count_q);
					ddr_req_o <= 1'b1;
					ddr_busy_q <= 1'b1;
					write_beat_q <= write_beat_q + 22'd1;
					if (prefill_count_q == 2'd0) begin
						buffer0_q <= pack_data_q;
						prefill_count_q <= 2'd1;
					end else if (prefill_count_q == 2'd1) begin
						buffer1_q <= pack_data_q;
						prefill_count_q <= 2'd2;
					end
					pack_count_q <= 2'd0;
				end
			end

			if (finalize_q && !ddr_busy_q && !cancel_i) begin
				finalize_q <= 1'b0;
				load_hold_q <= 1'b0;
				if (load_valid_w) begin
					loaded_q <= 1'b1;
					complete_q <= 1'b0;
					load_error_q <= 1'b0;
					buffer_count_q <= prefill_count_q;
					word_lane_q <= 2'd0;
					frame_index_q <= 24'd0;
					total_beats_q <= frame_total_beats_w;
					next_read_beat_q <= {20'd0, prefill_count_q};
				end else begin
					loaded_q <= 1'b0;
					complete_q <= 1'b0;
					load_error_q <= 1'b1;
					buffer_count_q <= 2'd0;
				end
			end

			if (ddr_read_ack_w && loaded_q && !fault_q && !cancel_i) begin
				if (buffer_count_q == 2'd0) begin
					buffer0_q <= ddr_dout_i;
					buffer_count_q <= 2'd1;
				end else if (buffer_count_q == 2'd1) begin
					buffer1_q <= ddr_dout_i;
					buffer_count_q <= 2'd2;
				end else begin
					fault_q <= 1'b1;
				end
			end

			if (loaded_q && !complete_q && !fault_q && !cancel_i &&
				pad_latch_rise_w) begin
				if ({1'b0, frame_index_q} + 25'd1 >=
					{1'b0, frame_count_q[23:0]}) begin
					complete_q <= 1'b1;
					word_lane_q <= 2'd0;
				end else begin
					frame_index_q <= frame_index_q + 24'd1;
					if (word_lane_q == 2'd3) begin
						word_lane_q <= 2'd0;
						if (buffer_count_q >= 2'd2) begin
							buffer0_q <= buffer1_q;
							buffer_count_q <= buffer_count_q - 2'd1;
						end else if (ddr_read_ack_w &&
							(buffer_count_q == 2'd1)) begin
							buffer0_q <= ddr_dout_i;
							buffer_count_q <= 2'd1;
						end else begin
							fault_q <= 1'b1;
						end
					end else begin
						word_lane_q <= word_lane_q + 2'd1;
					end
				end
			end

			if (loaded_q && !complete_q && !fault_q && !cancel_i &&
				!ddr_busy_q &&
				(buffer_count_q < 2'd2) &&
				(next_read_beat_q < total_beats_q)) begin
				ddr_addr_o <= DDR_BASE_ADDR +
					{3'd0, next_read_beat_q, 2'b00};
				ddr_din_o <= 64'd0;
				ddr_rnw_o <= 1'b1;
				ddr_be_o <= 8'hff;
				ddr_req_o <= 1'b1;
				ddr_busy_q <= 1'b1;
				next_read_beat_q <= next_read_beat_q + 22'd1;
			end
		end
	end

endmodule
