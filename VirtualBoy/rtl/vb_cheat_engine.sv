// Copyright (c) 2026 Jamie Blanks

// Virtual Boy physical-read cheat engine using the standard MiSTer record:
// 128       record-valid strobe
// 105:104   replacement method (replace, OR, AND)
// 102:100   width (byte, 16-bit, 32-bit)
// 96        compare enable
// 95:64     physical byte address
// 63:32     compare value
// 31:0      replacement value
//
// Expand records into a byte-wide CAM so both V810 read lanes are checked in
// parallel, including odd-address byte cheats.
module vb_cheat_engine
(
	input  wire         clk_sys_i,
	input  wire         clear_i,
	input  wire         enable_i,
	input  wire [128:0] code_i,
	input  wire [26:1]  addr_i,
	input  wire [15:0]  data_i,
	output wire [15:0]  data_o,
	output wire         available_o
);

	localparam integer MAX_CODES = 32;
	localparam [5:0]   MAX_CODES_COUNT = 6'd32;
	localparam [1:0]   METHOD_REPLACE  = 2'd0;
	localparam [1:0]   METHOD_OR       = 2'd1;
	localparam [1:0]   METHOD_AND      = 2'd2;

	wire        code_valid_w          = code_i[128];
	wire [1:0]  code_method_w         = code_i[105:104];
	wire [2:0]  code_width_w          = code_i[102:100];
	wire        code_compare_enable_w = code_i[96];
	wire [4:0]  code_addr_high_w      = code_i[95:91];
	wire [26:0] code_addr_w           = code_i[90:64];
	wire [31:0] code_compare_w        = code_i[63:32];
	wire [31:0] code_value_w          = code_i[31:0];
	wire [26:0] read_addr_low_w       = {addr_i, 1'b0};
	wire [26:0] read_addr_high_w      = {addr_i, 1'b1};

	// One entry per expanded byte of a record.
	reg [26:0] code_addr_q           [0:MAX_CODES-1];
	reg [7:0]  code_value_q          [0:MAX_CODES-1];
	reg [7:0]  code_compare_q        [0:MAX_CODES-1];
	reg        code_compare_enable_q [0:MAX_CODES-1];
	reg [1:0]  code_method_q         [0:MAX_CODES-1];

	reg [5:0]  code_count_q  = 6'd0;
	// A validated record is expanded into byte entries over the next cycles.
	reg [2:0]  pending_count_q          = 3'd0;
	reg [26:0] pending_addr_q           = 27'd0;
	reg [31:0] pending_value_q          = 32'd0;
	reg [31:0] pending_compare_q        = 32'd0;
	reg        pending_compare_enable_q = 1'b0;
	reg [1:0]  pending_method_q         = METHOD_REPLACE;
	reg [2:0]  record_byte_count;
	reg        record_aligned;

	// Resolve the wide address CAM while the fixed-wait read is in flight. The
	// response edge retains only the registered address-hit mask, byte compares,
	// and balanced high-index-first selection. Keeping compare in that final
	// selection preserves fallback to an older code when a newer compare fails.
	wire [MAX_CODES-1:0] low_addr_match_w;
	wire [MAX_CODES-1:0] high_addr_match_w;
	reg  [MAX_CODES-1:0] low_addr_match_q  = {MAX_CODES{1'b0}};
	reg  [MAX_CODES-1:0] high_addr_match_q = {MAX_CODES{1'b0}};

	// Balanced tournament tree in heap order: leaf i sits at node
	// MAX_CODES-1+i, internal node n selects between children 2n+1 and 2n+2,
	// and node 0 is the winner. Child 2n+2 covers the higher code indices, so
	// preferring it whenever its hit bit [10] is set makes the newest matching
	// code win, exactly like the previous explicit four-level selector.
	// Each node packs {hit, method[1:0], value[7:0]}.
	wire [10:0] low_tree_w  [0:(2*MAX_CODES)-2];
	wire [10:0] high_tree_w [0:(2*MAX_CODES)-2];
	wire [10:0] low_select_w  = low_tree_w[0];
	wire [10:0] high_select_w = high_tree_w[0];

	assign available_o = (code_count_q != 6'd0);
	assign data_o[7:0] = (enable_i && low_select_w[10]) ?
		apply_method_fn(low_select_w[9:8], data_i[7:0],
			low_select_w[7:0]) : data_i[7:0];
	assign data_o[15:8] = (enable_i && high_select_w[10]) ?
		apply_method_fn(high_select_w[9:8], data_i[15:8],
			high_select_w[7:0]) : data_i[15:8];

	function [7:0] apply_method_fn;
		input [1:0] method_i;
		input [7:0] read_byte_i;
		input [7:0] value_i;
		begin
			case (method_i)
				METHOD_OR:  apply_method_fn = read_byte_i | value_i;
				METHOD_AND: apply_method_fn = read_byte_i & value_i;
				default:    apply_method_fn = value_i;
			endcase
		end
	endfunction

	genvar tree_idx;
	generate
		for (tree_idx = 0; tree_idx < MAX_CODES;
			 tree_idx = tree_idx + 1) begin : generate_leaves
			localparam [5:0] CODE_INDEX = tree_idx[5:0];
			wire code_active_w = (CODE_INDEX < code_count_q);
			wire low_compare_match_w =
				!code_compare_enable_q[tree_idx] ||
				(code_compare_q[tree_idx] == data_i[7:0]);
			wire high_compare_match_w =
				!code_compare_enable_q[tree_idx] ||
				(code_compare_q[tree_idx] == data_i[15:8]);

			assign low_addr_match_w[tree_idx] = code_active_w &&
				(code_addr_q[tree_idx] == read_addr_low_w);
			assign high_addr_match_w[tree_idx] = code_active_w &&
				(code_addr_q[tree_idx] == read_addr_high_w);

			assign low_tree_w[MAX_CODES - 1 + tree_idx] = {
				low_addr_match_q[tree_idx] && low_compare_match_w,
				code_method_q[tree_idx],
				code_value_q[tree_idx]
			};
			assign high_tree_w[MAX_CODES - 1 + tree_idx] = {
				high_addr_match_q[tree_idx] && high_compare_match_w,
				code_method_q[tree_idx],
				code_value_q[tree_idx]
			};
		end

		for (tree_idx = 0; tree_idx < MAX_CODES - 1;
			 tree_idx = tree_idx + 1) begin : generate_select_tree
			assign low_tree_w[tree_idx] =
				low_tree_w[(tree_idx * 2) + 2][10] ?
				low_tree_w[(tree_idx * 2) + 2] :
				low_tree_w[(tree_idx * 2) + 1];
			assign high_tree_w[tree_idx] =
				high_tree_w[(tree_idx * 2) + 2][10] ?
				high_tree_w[(tree_idx * 2) + 2] :
				high_tree_w[(tree_idx * 2) + 1];
		end
	endgenerate

	// Record validation: only byte/16/32-bit widths at their natural alignment
	// are accepted, and only while the expanded bytes still fit in the table.
	always @* begin
		record_byte_count = 3'd0;
		record_aligned = 1'b0;
		case (code_width_w)
			3'b000, 3'b001: begin
				record_byte_count = 3'd1;
				record_aligned = 1'b1;
			end
			3'b010: begin
				record_byte_count = 3'd2;
				record_aligned = !code_addr_w[0];
			end
			3'b100: begin
				record_byte_count = 3'd4;
				record_aligned = !(|code_addr_w[1:0]);
			end
			default: begin
				record_byte_count = 3'd0;
				record_aligned = 1'b0;
			end
		endcase
	end

	always @(posedge clk_sys_i) begin
		if (clear_i) begin
			code_count_q <= 6'd0;
			pending_count_q <= 3'd0;
			low_addr_match_q <= {MAX_CODES{1'b0}};
			high_addr_match_q <= {MAX_CODES{1'b0}};
		end else begin
			low_addr_match_q <= low_addr_match_w;
			high_addr_match_q <= high_addr_match_w;
			if (pending_count_q != 3'd0) begin
				code_addr_q[code_count_q[4:0]] <= pending_addr_q;
				code_value_q[code_count_q[4:0]] <= pending_value_q[7:0];
				code_compare_q[code_count_q[4:0]] <= pending_compare_q[7:0];
				code_compare_enable_q[code_count_q[4:0]] <= pending_compare_enable_q;
				code_method_q[code_count_q[4:0]] <= pending_method_q;
				code_count_q <= code_count_q + 6'd1;
				pending_addr_q <= pending_addr_q + 27'd1;
				pending_value_q <= {8'd0, pending_value_q[31:8]};
				pending_compare_q <= {8'd0, pending_compare_q[31:8]};
				pending_count_q <= pending_count_q - 3'd1;
			end

			if (code_valid_w && (pending_count_q == 3'd0) &&
				!(|code_addr_high_w) && record_aligned &&
				(record_byte_count != 3'd0) &&
				(({1'b0, code_count_q} + {4'd0, record_byte_count}) <=
				 {1'b0, MAX_CODES_COUNT})) begin
				pending_addr_q <= code_addr_w;
				pending_value_q <= code_value_w;
				pending_compare_q <= code_compare_w;
				pending_compare_enable_q <= code_compare_enable_w;
				pending_method_q <= code_method_w;
				pending_count_q <= record_byte_count;
			end
		end
	end

endmodule
