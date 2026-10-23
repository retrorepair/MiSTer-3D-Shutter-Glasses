// Copyright (c) 2026 Jamie Blanks

// Mirrored synchronous register file for the NEC V810.
//
// Two RAM copies provide independent source reads. Both receive the same write
// stream. A five-entry pending table exposes each commit atomically while the
// RAM writes drain.

module necv810_regfile
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        clk_en_i,

	input  wire [4:0]  read_addr_a_i,
	input  wire [4:0]  read_addr_b_i,
	output wire [31:0] read_data_a_o,
	output wire [31:0] read_data_b_o,

	input  wire        commit_en_i,
	input  wire        commit_valid_i,
	input  wire [4:0]  commit_we_i,
	input  wire [4:0]  commit_addr0_i,
	input  wire [4:0]  commit_addr1_i,
	input  wire [4:0]  commit_addr2_i,
	input  wire [4:0]  commit_addr3_i,
	input  wire [4:0]  commit_addr4_i,
	input  wire [31:0] commit_data0_i,
	input  wire [31:0] commit_data1_i,
	input  wire [31:0] commit_data2_i,
	input  wire [31:0] commit_data3_i,
	input  wire [31:0] commit_data4_i,
	output wire        commit_ready_o,
	output wire        commit_accept_o,
	output wire [2:0]  pending_count_o,

	input  wire        savestate_active_i,
	input  wire [6:0]  savestate_addr_i,
	input  wire        savestate_rden_i,
	input  wire        savestate_wren_i,
	input  wire [7:0]  savestate_wdata_i,
	output reg  [7:0]  savestate_rdata_o
);

	reg [4:0]  pending_valid_q;
	reg [4:0]  pending_addr_q [0:4];
	reg [31:0] pending_data_q [0:4];

	reg [4:0]  pending_valid_post_v;
	reg [4:0]  pending_addr_post_v [0:4];
	reg [31:0] pending_data_post_v [0:4];
	reg [4:0]  pending_valid_trial_v;
	reg [4:0]  pending_addr_trial_v [0:4];
	reg [31:0] pending_data_trial_v [0:4];

	reg [4:0] read_addr_a_q;
	reg [4:0] read_addr_b_q;
	reg       last_drain_valid_q;
	reg [4:0] last_drain_addr_q;
	reg [31:0] last_drain_data_q;

	wire       drain_valid_w = |pending_valid_q;
	wire [2:0] drain_slot_w =
		pending_valid_q[0] ? 3'd0 :
		pending_valid_q[1] ? 3'd1 :
		pending_valid_q[2] ? 3'd2 :
		pending_valid_q[3] ? 3'd3 : 3'd4;
	wire [4:0] drain_addr_w =
		pending_valid_q[0] ? pending_addr_q[0] :
		pending_valid_q[1] ? pending_addr_q[1] :
		pending_valid_q[2] ? pending_addr_q[2] :
		pending_valid_q[3] ? pending_addr_q[3] : pending_addr_q[4];
	wire [31:0] drain_data_w =
		pending_valid_q[0] ? pending_data_q[0] :
		pending_valid_q[1] ? pending_data_q[1] :
		pending_valid_q[2] ? pending_data_q[2] :
		pending_valid_q[3] ? pending_data_q[3] : pending_data_q[4];

	wire [2:0] pending_count_w =
		{2'd0, pending_valid_q[0]} +
		{2'd0, pending_valid_q[1]} +
		{2'd0, pending_valid_q[2]} +
		{2'd0, pending_valid_q[3]} +
		{2'd0, pending_valid_q[4]};

	wire [31:0] ram_data_a_w;
	wire [31:0] ram_data_b_w;
	wire [4:0]  savestate_word_addr_w = savestate_addr_i[6:2];
	reg [31:0]  savestate_merged_data_v;
	reg [31:0] read_data_a_v;
	reg [31:0] read_data_b_v;
	integer pending_post_index_v;
	integer pending_trial_index_v;
	integer pending_read_index_v;
	integer pending_seq_index_v;

	// The first matching destination chooses the slot; the last supplies data.
	// Five parallel searches avoid a serial commit path.
	wire commit_live0_w = commit_we_i[0] && (commit_addr0_i != 5'd0);
	wire commit_live1_w = commit_we_i[1] && (commit_addr1_i != 5'd0);
	wire commit_live2_w = commit_we_i[2] && (commit_addr2_i != 5'd0);
	wire commit_live3_w = commit_we_i[3] && (commit_addr3_i != 5'd0);
	wire commit_live4_w = commit_we_i[4] && (commit_addr4_i != 5'd0);

	wire commit_same01_w = commit_live0_w && commit_live1_w && (commit_addr0_i == commit_addr1_i);
	wire commit_same02_w = commit_live0_w && commit_live2_w && (commit_addr0_i == commit_addr2_i);
	wire commit_same03_w = commit_live0_w && commit_live3_w && (commit_addr0_i == commit_addr3_i);
	wire commit_same04_w = commit_live0_w && commit_live4_w && (commit_addr0_i == commit_addr4_i);
	wire commit_same12_w = commit_live1_w && commit_live2_w && (commit_addr1_i == commit_addr2_i);
	wire commit_same13_w = commit_live1_w && commit_live3_w && (commit_addr1_i == commit_addr3_i);
	wire commit_same14_w = commit_live1_w && commit_live4_w && (commit_addr1_i == commit_addr4_i);
	wire commit_same23_w = commit_live2_w && commit_live3_w && (commit_addr2_i == commit_addr3_i);
	wire commit_same24_w = commit_live2_w && commit_live4_w && (commit_addr2_i == commit_addr4_i);
	wire commit_same34_w = commit_live3_w && commit_live4_w && (commit_addr3_i == commit_addr4_i);

	wire commit_first0_w = commit_live0_w;
	wire commit_first1_w = commit_live1_w && !commit_same01_w;
	wire commit_first2_w = commit_live2_w && !(commit_same02_w || commit_same12_w);
	wire commit_first3_w = commit_live3_w && !((commit_same03_w || commit_same13_w) || commit_same23_w);
	wire commit_first4_w = commit_live4_w && !((commit_same04_w || commit_same14_w) ||
		(commit_same24_w || commit_same34_w));

	wire [31:0] commit_final_data0_w =
		commit_same04_w ? commit_data4_i :
		commit_same03_w ? commit_data3_i :
		commit_same02_w ? commit_data2_i :
		commit_same01_w ? commit_data1_i : commit_data0_i;
	wire [31:0] commit_final_data1_w =
		commit_same14_w ? commit_data4_i :
		commit_same13_w ? commit_data3_i :
		commit_same12_w ? commit_data2_i : commit_data1_i;
	wire [31:0] commit_final_data2_w =
		commit_same24_w ? commit_data4_i :
		commit_same23_w ? commit_data3_i : commit_data2_i;
	wire [31:0] commit_final_data3_w =
		commit_same34_w ? commit_data4_i : commit_data3_i;
	wire [31:0] commit_final_data4_w = commit_data4_i;

	wire [4:0] commit_pending_match0_w = {
		commit_live0_w && pending_valid_post_v[4] && (commit_addr0_i == pending_addr_post_v[4]),
		commit_live0_w && pending_valid_post_v[3] && (commit_addr0_i == pending_addr_post_v[3]),
		commit_live0_w && pending_valid_post_v[2] && (commit_addr0_i == pending_addr_post_v[2]),
		commit_live0_w && pending_valid_post_v[1] && (commit_addr0_i == pending_addr_post_v[1]),
		commit_live0_w && pending_valid_post_v[0] && (commit_addr0_i == pending_addr_post_v[0])};
	wire [4:0] commit_pending_match1_w = {
		commit_live1_w && pending_valid_post_v[4] && (commit_addr1_i == pending_addr_post_v[4]),
		commit_live1_w && pending_valid_post_v[3] && (commit_addr1_i == pending_addr_post_v[3]),
		commit_live1_w && pending_valid_post_v[2] && (commit_addr1_i == pending_addr_post_v[2]),
		commit_live1_w && pending_valid_post_v[1] && (commit_addr1_i == pending_addr_post_v[1]),
		commit_live1_w && pending_valid_post_v[0] && (commit_addr1_i == pending_addr_post_v[0])};
	wire [4:0] commit_pending_match2_w = {
		commit_live2_w && pending_valid_post_v[4] && (commit_addr2_i == pending_addr_post_v[4]),
		commit_live2_w && pending_valid_post_v[3] && (commit_addr2_i == pending_addr_post_v[3]),
		commit_live2_w && pending_valid_post_v[2] && (commit_addr2_i == pending_addr_post_v[2]),
		commit_live2_w && pending_valid_post_v[1] && (commit_addr2_i == pending_addr_post_v[1]),
		commit_live2_w && pending_valid_post_v[0] && (commit_addr2_i == pending_addr_post_v[0])};
	wire [4:0] commit_pending_match3_w = {
		commit_live3_w && pending_valid_post_v[4] && (commit_addr3_i == pending_addr_post_v[4]),
		commit_live3_w && pending_valid_post_v[3] && (commit_addr3_i == pending_addr_post_v[3]),
		commit_live3_w && pending_valid_post_v[2] && (commit_addr3_i == pending_addr_post_v[2]),
		commit_live3_w && pending_valid_post_v[1] && (commit_addr3_i == pending_addr_post_v[1]),
		commit_live3_w && pending_valid_post_v[0] && (commit_addr3_i == pending_addr_post_v[0])};
	wire [4:0] commit_pending_match4_w = {
		commit_live4_w && pending_valid_post_v[4] && (commit_addr4_i == pending_addr_post_v[4]),
		commit_live4_w && pending_valid_post_v[3] && (commit_addr4_i == pending_addr_post_v[3]),
		commit_live4_w && pending_valid_post_v[2] && (commit_addr4_i == pending_addr_post_v[2]),
		commit_live4_w && pending_valid_post_v[1] && (commit_addr4_i == pending_addr_post_v[1]),
		commit_live4_w && pending_valid_post_v[0] && (commit_addr4_i == pending_addr_post_v[0])};

	wire [4:0] commit_new_w = {
		commit_first4_w && !(|commit_pending_match4_w),
		commit_first3_w && !(|commit_pending_match3_w),
		commit_first2_w && !(|commit_pending_match2_w),
		commit_first1_w && !(|commit_pending_match1_w),
		commit_first0_w && !(|commit_pending_match0_w)};
	wire [4:0] pending_free_w = ~pending_valid_post_v;

	wire [1:0] commit_new_count01_w = {1'b0, commit_new_w[0]} + {1'b0, commit_new_w[1]};
	wire [1:0] commit_new_count23_w = {1'b0, commit_new_w[2]} + {1'b0, commit_new_w[3]};
	wire [2:0] commit_new_count0123_w = {1'b0, commit_new_count01_w} + {1'b0, commit_new_count23_w};
	wire [2:0] commit_new_count_w = commit_new_count0123_w + {2'b00, commit_new_w[4]};
	wire [1:0] pending_free_count01_w = {1'b0, pending_free_w[0]} + {1'b0, pending_free_w[1]};
	wire [1:0] pending_free_count23_w = {1'b0, pending_free_w[2]} + {1'b0, pending_free_w[3]};
	wire [2:0] pending_free_count0123_w = {1'b0, pending_free_count01_w} + {1'b0, pending_free_count23_w};
	wire [2:0] pending_free_count_w = pending_free_count0123_w + {2'b00, pending_free_w[4]};

	wire [2:0] commit_new_rank0_w = 3'd0;
	wire [2:0] commit_new_rank1_w = {2'b00, commit_new_w[0]};
	wire [2:0] commit_new_rank2_w = {1'b0, commit_new_count01_w};
	wire [2:0] commit_new_rank3_w = {1'b0, commit_new_count01_w} + {2'b00, commit_new_w[2]};
	wire [2:0] commit_new_rank4_w = commit_new_count0123_w;
	wire [2:0] pending_free_rank0_w = 3'd0;
	wire [2:0] pending_free_rank1_w = {2'b00, pending_free_w[0]};
	wire [2:0] pending_free_rank2_w = {1'b0, pending_free_count01_w};
	wire [2:0] pending_free_rank3_w = {1'b0, pending_free_count01_w} + {2'b00, pending_free_w[2]};
	wire [2:0] pending_free_rank4_w = pending_free_count0123_w;

	wire [4:0] pending_new_grant_w [0:4];
	assign pending_new_grant_w[0] = {
		pending_free_w[0] && commit_new_w[4] && (pending_free_rank0_w == commit_new_rank4_w),
		pending_free_w[0] && commit_new_w[3] && (pending_free_rank0_w == commit_new_rank3_w),
		pending_free_w[0] && commit_new_w[2] && (pending_free_rank0_w == commit_new_rank2_w),
		pending_free_w[0] && commit_new_w[1] && (pending_free_rank0_w == commit_new_rank1_w),
		pending_free_w[0] && commit_new_w[0] && (pending_free_rank0_w == commit_new_rank0_w)};
	assign pending_new_grant_w[1] = {
		pending_free_w[1] && commit_new_w[4] && (pending_free_rank1_w == commit_new_rank4_w),
		pending_free_w[1] && commit_new_w[3] && (pending_free_rank1_w == commit_new_rank3_w),
		pending_free_w[1] && commit_new_w[2] && (pending_free_rank1_w == commit_new_rank2_w),
		pending_free_w[1] && commit_new_w[1] && (pending_free_rank1_w == commit_new_rank1_w),
		pending_free_w[1] && commit_new_w[0] && (pending_free_rank1_w == commit_new_rank0_w)};
	assign pending_new_grant_w[2] = {
		pending_free_w[2] && commit_new_w[4] && (pending_free_rank2_w == commit_new_rank4_w),
		pending_free_w[2] && commit_new_w[3] && (pending_free_rank2_w == commit_new_rank3_w),
		pending_free_w[2] && commit_new_w[2] && (pending_free_rank2_w == commit_new_rank2_w),
		pending_free_w[2] && commit_new_w[1] && (pending_free_rank2_w == commit_new_rank1_w),
		pending_free_w[2] && commit_new_w[0] && (pending_free_rank2_w == commit_new_rank0_w)};
	assign pending_new_grant_w[3] = {
		pending_free_w[3] && commit_new_w[4] && (pending_free_rank3_w == commit_new_rank4_w),
		pending_free_w[3] && commit_new_w[3] && (pending_free_rank3_w == commit_new_rank3_w),
		pending_free_w[3] && commit_new_w[2] && (pending_free_rank3_w == commit_new_rank2_w),
		pending_free_w[3] && commit_new_w[1] && (pending_free_rank3_w == commit_new_rank1_w),
		pending_free_w[3] && commit_new_w[0] && (pending_free_rank3_w == commit_new_rank0_w)};
	assign pending_new_grant_w[4] = {
		pending_free_w[4] && commit_new_w[4] && (pending_free_rank4_w == commit_new_rank4_w),
		pending_free_w[4] && commit_new_w[3] && (pending_free_rank4_w == commit_new_rank3_w),
		pending_free_w[4] && commit_new_w[2] && (pending_free_rank4_w == commit_new_rank2_w),
		pending_free_w[4] && commit_new_w[1] && (pending_free_rank4_w == commit_new_rank1_w),
		pending_free_w[4] && commit_new_w[0] && (pending_free_rank4_w == commit_new_rank0_w)};

	always @* begin
		pending_valid_post_v = pending_valid_q;
		for (pending_post_index_v = 0; pending_post_index_v < 5; pending_post_index_v = pending_post_index_v + 1) begin
			pending_addr_post_v[pending_post_index_v] = pending_addr_q[pending_post_index_v];
			pending_data_post_v[pending_post_index_v] = pending_data_q[pending_post_index_v];
		end

		if (clk_en_i && drain_valid_w) begin
			case (drain_slot_w)
				3'd0: pending_valid_post_v[0] = 1'b0;
				3'd1: pending_valid_post_v[1] = 1'b0;
				3'd2: pending_valid_post_v[2] = 1'b0;
				3'd3: pending_valid_post_v[3] = 1'b0;
				default: pending_valid_post_v[4] = 1'b0;
			endcase
		end

	end

	always @* begin
		pending_valid_trial_v = pending_valid_post_v;
		for (pending_trial_index_v = 0; pending_trial_index_v < 5; pending_trial_index_v = pending_trial_index_v + 1) begin
			pending_addr_trial_v[pending_trial_index_v] = pending_addr_post_v[pending_trial_index_v];
			pending_data_trial_v[pending_trial_index_v] = pending_data_post_v[pending_trial_index_v];

			if (pending_valid_post_v[pending_trial_index_v]) begin
				if (commit_pending_match4_w[pending_trial_index_v]) begin
					pending_data_trial_v[pending_trial_index_v] = commit_data4_i;
				end else if (commit_pending_match3_w[pending_trial_index_v]) begin
					pending_data_trial_v[pending_trial_index_v] = commit_data3_i;
				end else if (commit_pending_match2_w[pending_trial_index_v]) begin
					pending_data_trial_v[pending_trial_index_v] = commit_data2_i;
				end else if (commit_pending_match1_w[pending_trial_index_v]) begin
					pending_data_trial_v[pending_trial_index_v] = commit_data1_i;
				end else if (commit_pending_match0_w[pending_trial_index_v]) begin
					pending_data_trial_v[pending_trial_index_v] = commit_data0_i;
				end
			end else begin
				case (pending_new_grant_w[pending_trial_index_v])
					5'b00001: begin
						pending_valid_trial_v[pending_trial_index_v] = 1'b1;
						pending_addr_trial_v[pending_trial_index_v] = commit_addr0_i;
						pending_data_trial_v[pending_trial_index_v] = commit_final_data0_w;
					end
					5'b00010: begin
						pending_valid_trial_v[pending_trial_index_v] = 1'b1;
						pending_addr_trial_v[pending_trial_index_v] = commit_addr1_i;
						pending_data_trial_v[pending_trial_index_v] = commit_final_data1_w;
					end
					5'b00100: begin
						pending_valid_trial_v[pending_trial_index_v] = 1'b1;
						pending_addr_trial_v[pending_trial_index_v] = commit_addr2_i;
						pending_data_trial_v[pending_trial_index_v] = commit_final_data2_w;
					end
					5'b01000: begin
						pending_valid_trial_v[pending_trial_index_v] = 1'b1;
						pending_addr_trial_v[pending_trial_index_v] = commit_addr3_i;
						pending_data_trial_v[pending_trial_index_v] = commit_final_data3_w;
					end
					5'b10000: begin
						pending_valid_trial_v[pending_trial_index_v] = 1'b1;
						pending_addr_trial_v[pending_trial_index_v] = commit_addr4_i;
						pending_data_trial_v[pending_trial_index_v] = commit_final_data4_w;
					end
					default: begin
					end
				endcase
			end
		end
	end

	assign commit_ready_o = (commit_new_count_w <= pending_free_count_w);
	assign commit_accept_o = clk_en_i && commit_en_i && commit_valid_i && commit_ready_o;
	assign pending_count_o = pending_count_w;

	// RAM data, overridden by newer drain, pending, and same-edge commit data.
	// The final r0 override dominates, so the forwarding matches need no r0 guards.
	always @* begin
		read_data_a_v = ram_data_a_w;
		read_data_b_v = ram_data_b_w;

		if (last_drain_valid_q && (last_drain_addr_q == read_addr_a_q)) begin
			read_data_a_v = last_drain_data_q;
		end
		if (last_drain_valid_q && (last_drain_addr_q == read_addr_b_q)) begin
			read_data_b_v = last_drain_data_q;
		end

		for (pending_read_index_v = 0; pending_read_index_v < 5; pending_read_index_v = pending_read_index_v + 1) begin
			if (pending_valid_q[pending_read_index_v] &&
				(pending_addr_q[pending_read_index_v] == read_addr_a_q)) begin
				read_data_a_v = pending_data_q[pending_read_index_v];
			end
			if (pending_valid_q[pending_read_index_v] &&
				(pending_addr_q[pending_read_index_v] == read_addr_b_q)) begin
				read_data_b_v = pending_data_q[pending_read_index_v];
			end
		end

		if (commit_valid_i && commit_we_i[0] && (commit_addr0_i == read_addr_a_q)) read_data_a_v = commit_data0_i;
		if (commit_valid_i && commit_we_i[1] && (commit_addr1_i == read_addr_a_q)) read_data_a_v = commit_data1_i;
		if (commit_valid_i && commit_we_i[2] && (commit_addr2_i == read_addr_a_q)) read_data_a_v = commit_data2_i;
		if (commit_valid_i && commit_we_i[3] && (commit_addr3_i == read_addr_a_q)) read_data_a_v = commit_data3_i;
		if (commit_valid_i && commit_we_i[4] && (commit_addr4_i == read_addr_a_q)) read_data_a_v = commit_data4_i;
		if (commit_valid_i && commit_we_i[0] && (commit_addr0_i == read_addr_b_q)) read_data_b_v = commit_data0_i;
		if (commit_valid_i && commit_we_i[1] && (commit_addr1_i == read_addr_b_q)) read_data_b_v = commit_data1_i;
		if (commit_valid_i && commit_we_i[2] && (commit_addr2_i == read_addr_b_q)) read_data_b_v = commit_data2_i;
		if (commit_valid_i && commit_we_i[3] && (commit_addr3_i == read_addr_b_q)) read_data_b_v = commit_data3_i;
		if (commit_valid_i && commit_we_i[4] && (commit_addr4_i == read_addr_b_q)) read_data_b_v = commit_data4_i;

		// r0 always reads zero.
		if (read_addr_a_q == 5'd0) begin
			read_data_a_v = 32'd0;
		end
		if (read_addr_b_q == 5'd0) begin
			read_data_b_v = 32'd0;
		end
	end

	assign read_data_a_o = read_data_a_v;
	assign read_data_b_o = read_data_b_v;

	always @* begin
		savestate_rdata_o = 8'd0;
		savestate_merged_data_v = ram_data_a_w;
		case (savestate_addr_i[1:0])
			2'd0: begin
				savestate_rdata_o = savestate_rden_i ? ram_data_a_w[7:0] : 8'd0;
				savestate_merged_data_v[7:0] = savestate_wdata_i;
			end
			2'd1: begin
				savestate_rdata_o = savestate_rden_i ? ram_data_a_w[15:8] : 8'd0;
				savestate_merged_data_v[15:8] = savestate_wdata_i;
			end
			2'd2: begin
				savestate_rdata_o = savestate_rden_i ? ram_data_a_w[23:16] : 8'd0;
				savestate_merged_data_v[23:16] = savestate_wdata_i;
			end
			default: begin
				savestate_rdata_o = savestate_rden_i ? ram_data_a_w[31:24] : 8'd0;
				savestate_merged_data_v[31:24] = savestate_wdata_i;
			end
		endcase
	end

	always @(posedge clk_i or posedge reset_i) begin
		if (reset_i) begin
			pending_valid_q <= 5'b00000;
			read_addr_a_q <= 5'd0;
			read_addr_b_q <= 5'd0;
			last_drain_valid_q <= 1'b0;
		end else if (clk_en_i) begin
			read_addr_a_q <= read_addr_a_i;
			read_addr_b_q <= read_addr_b_i;
			last_drain_valid_q <= drain_valid_w;
			if (drain_valid_w) begin
				last_drain_addr_q <= drain_addr_w;
				last_drain_data_q <= drain_data_w;
			end
			if (commit_accept_o) begin
				pending_valid_q <= pending_valid_trial_v;
			end else begin
				pending_valid_q <= pending_valid_post_v;
			end
			for (pending_seq_index_v = 0; pending_seq_index_v < 5; pending_seq_index_v = pending_seq_index_v + 1) begin
				if (commit_accept_o) begin
					pending_addr_q[pending_seq_index_v] <= pending_addr_trial_v[pending_seq_index_v];
					pending_data_q[pending_seq_index_v] <= pending_data_trial_v[pending_seq_index_v];
				end else begin
					pending_addr_q[pending_seq_index_v] <= pending_addr_post_v[pending_seq_index_v];
					pending_data_q[pending_seq_index_v] <= pending_data_post_v[pending_seq_index_v];
				end
			end
		end
	end

	/* verilator lint_off PINCONNECTEMPTY */
	// NEC leaves r1-r31 undefined after reset, so these RAMs do not reset their data.
	cache_ram_dp
	#(
		.ADDR_WIDTH(5),
		.DATA_WIDTH(32)
	)
	u_image_a
	(
		.clk_i(clk_i),
		.addr_a_i(savestate_active_i ? savestate_word_addr_w : read_addr_a_i),
		.wren_a_i(1'b0),
		.wdata_a_i(32'd0),
		.q_a_o(ram_data_a_w),
		.addr_b_i(savestate_active_i ? savestate_word_addr_w : drain_addr_w),
		.wren_b_i(savestate_active_i ? savestate_wren_i :
			(clk_en_i && drain_valid_w)),
		.wdata_b_i(savestate_active_i ? savestate_merged_data_v : drain_data_w),
		.q_b_o()
	);

	cache_ram_dp
	#(
		.ADDR_WIDTH(5),
		.DATA_WIDTH(32)
	)
	u_image_b
	(
		.clk_i(clk_i),
		.addr_a_i(savestate_active_i ? savestate_word_addr_w : read_addr_b_i),
		.wren_a_i(1'b0),
		.wdata_a_i(32'd0),
		.q_a_o(ram_data_b_w),
		.addr_b_i(savestate_active_i ? savestate_word_addr_w : drain_addr_w),
		.wren_b_i(savestate_active_i ? savestate_wren_i :
			(clk_en_i && drain_valid_w)),
		.wdata_b_i(savestate_active_i ? savestate_merged_data_v : drain_data_w),
		.q_b_o()
	);
	/* verilator lint_on PINCONNECTEMPTY */

// synthesis translate_off
`ifndef SYNTHESIS
	task sim_set_gpr_task;
		input [4:0]  write_addr;
		input [31:0] write_data;
		begin
			if (write_addr != 5'd0) begin
				u_image_a.mem_q[write_addr] = write_data;
				u_image_b.mem_q[write_addr] = write_data;
			end
		end
	endtask

	function [31:0] sim_read_gpr_fn;
		input [4:0] read_addr;
		integer sim_index_v;
		begin
			sim_read_gpr_fn = (read_addr == 5'd0) ? 32'd0 : u_image_a.mem_q[read_addr];
			if (last_drain_valid_q && (last_drain_addr_q == read_addr) && (read_addr != 5'd0)) begin
				sim_read_gpr_fn = last_drain_data_q;
			end
			for (sim_index_v = 0; sim_index_v < 5; sim_index_v = sim_index_v + 1) begin
				if (pending_valid_q[sim_index_v] && (pending_addr_q[sim_index_v] == read_addr) && (read_addr != 5'd0)) begin
					sim_read_gpr_fn = pending_data_q[sim_index_v];
				end
			end
			if (commit_valid_i && commit_we_i[0] && (commit_addr0_i == read_addr) && (read_addr != 5'd0)) sim_read_gpr_fn = commit_data0_i;
			if (commit_valid_i && commit_we_i[1] && (commit_addr1_i == read_addr) && (read_addr != 5'd0)) sim_read_gpr_fn = commit_data1_i;
			if (commit_valid_i && commit_we_i[2] && (commit_addr2_i == read_addr) && (read_addr != 5'd0)) sim_read_gpr_fn = commit_data2_i;
			if (commit_valid_i && commit_we_i[3] && (commit_addr3_i == read_addr) && (read_addr != 5'd0)) sim_read_gpr_fn = commit_data3_i;
			if (commit_valid_i && commit_we_i[4] && (commit_addr4_i == read_addr) && (read_addr != 5'd0)) sim_read_gpr_fn = commit_data4_i;
		end
	endfunction
`endif
// synthesis translate_on

endmodule
