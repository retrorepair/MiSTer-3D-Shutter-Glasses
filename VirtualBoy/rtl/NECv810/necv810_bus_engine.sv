// Copyright (c) 2026 Jamie Blanks

// Registered NEC V810 external-bus transaction engine.
//
// SIZ16B selects fixed 16-bit mode. In 32-bit mode, active-low SZRQ requests a
// second 16-bit beat. The registered transaction drives stable pins until READY.
module necv810_bus_engine (
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        clk_en_i,

	input  wire        launch_i,
	input  wire [31:0] launch_addr_i,
	input  wire        launch_fetch_i,
	input  wire        launch_fetch_branch_i,
	input  wire        launch_write_i,
	input  wire        launch_posted_i,
	input  wire        launch_addr_error_i,
	input  wire [1:0]  launch_size_i,
	input  wire [31:0] launch_wdata_i,

	input  wire        fixed_16_i,
	input  wire        szrq_i,
	input  wire        ready_i,
	input  wire [31:0] din_i,
	input  wire [31:1] idle_addr_i,

	output wire        launch_ready_o,
	output wire        posted_ready_o,
	output wire        launch_accept_o,
	output wire        beat_accept_o,
	output wire        first_beat_o,
	output wire        complete_o,
	output wire [31:0] read_data_o,

	output wire        active_o,
	output wire [31:0] active_addr_o,
	output wire        active_fetch_o,
	output wire        active_write_o,
	output wire        active_posted_o,
	output wire        posted_pending_o,
	output wire [1:0]  active_size_o,
	output wire        active_phase_o,
	output wire [31:0] active_wdata_o,
	output wire [15:0] first_half_o,

	output wire [31:1] a_o,
	output wire [31:0] dout_o,
	output wire        dout_oe_o,
	output wire [3:0]  be_o,
	output wire [1:0]  st_o,
	output wire        da_o,
	output wire        mrq_o,
	output wire        rw_o,
	output wire        bcyst_o,
	output wire        adrs_err_n_o,
	output wire        cycle_tag_o
);

	localparam [1:0] SIZE_B = 2'b00;
	localparam [1:0] SIZE_W = 2'b10;

	reg        active_q;
	reg [31:0] addr_q;
	reg [31:1] second_a_q;
	reg        fetch_q;
	reg        fetch_branch_q;
	reg        write_q;
	reg        posted_q;
	reg        addr_error_q;
	reg [1:0]  size_q;
	reg        phase_q;
	reg [31:0] wdata_q;
	reg [15:0] first_half_q;
	reg        split_dynamic_q;
	reg        cycle_tag_q;
	reg        cycle_start_q;
	reg        pending_q;
	reg [31:0] pending_addr_q;
	reg        pending_addr_error_q;
	reg [1:0]  pending_size_q;
	reg [31:0] pending_wdata_q;

	// Sample active-low SZRQ when the first word beat is accepted.
	wire       split_word_first_w =
		(size_q == SIZE_W) && !phase_q && (fixed_16_i || !szrq_i);
	// READY is combinational into the CE edge: the beat is accepted, and DIN
	// consumed, at the first CE edge where READY is high.
	wire       accepted_w = clk_en_i && active_q && ready_i;
	wire       complete_w = accepted_w && !split_word_first_w;
	wire       direct_ready_w = !active_q || (complete_w && !pending_q);
	wire       posted_ready_w = direct_ready_w ||
		(active_q && posted_q && (!pending_q || complete_w));
	wire       launch_ready_w = (launch_posted_i && launch_write_i) ?
		posted_ready_w : direct_ready_w;
	wire       launch_accept_w = clk_en_i && launch_i && launch_ready_w;
	wire       direct_accept_w = launch_accept_w && direct_ready_w;
	wire       queue_accept_w = launch_accept_w && !direct_ready_w;
	assign launch_ready_o = launch_ready_w;
	assign posted_ready_o = posted_ready_w;
	assign launch_accept_o = launch_accept_w;
	assign beat_accept_o = accepted_w;
	assign first_beat_o = accepted_w && split_word_first_w;
	assign complete_o = complete_w;
	assign read_data_o = read_data_fn(
		din_i, first_half_q, fixed_16_i, split_dynamic_q,
		size_q, phase_q, addr_q[1:0]);

	assign active_o = active_q;
	assign active_addr_o = addr_q;
	assign active_fetch_o = fetch_q;
	assign active_write_o = write_q;
	assign active_posted_o = posted_q;
	assign posted_pending_o = pending_q;
	assign active_size_o = size_q;
	assign active_phase_o = phase_q;
	assign active_wdata_o = wdata_q;
	assign first_half_o = first_half_q;

	// Register the second halfword address when the first beat is accepted.
	assign a_o = active_q ? (phase_q ? second_a_q : addr_q[31:1]) : idle_addr_i;
	assign dout_o = write_data_fn(
		wdata_q, fixed_16_i, split_dynamic_q, size_q, phase_q, addr_q[1:0]);
	assign dout_oe_o = active_q && write_q;
	assign be_o = active_q ?
		byte_enable_fn(fixed_16_i, split_dynamic_q, size_q, phase_q, addr_q[1:0]) :
		4'b0000;
	// The data sheet omits ST encodings, so use the conventional NVC mapping.
	assign st_o = !active_q ? 2'b00 : fetch_q ?
		(fetch_branch_q ? 2'b01 : 2'b11) : 2'b10;
	assign da_o = active_q && !fetch_q;
	assign mrq_o = active_q;
	assign rw_o = !write_q;
	assign bcyst_o = active_q && cycle_start_q;
	// Hold active-low ADRSERR with its transaction through stalls.
	assign adrs_err_n_o = !(active_q && addr_error_q);
	assign cycle_tag_o = cycle_tag_q;

	// Capture a launch request into the active transaction registers.
	task launch_to_active_task;
		begin
			active_q <= 1'b1;
			addr_q <= launch_addr_i;
			fetch_q <= launch_fetch_i;
			fetch_branch_q <= launch_fetch_branch_i;
			write_q <= launch_write_i;
			posted_q <= launch_posted_i;
			addr_error_q <= launch_addr_error_i;
			size_q <= launch_size_i;
			phase_q <= 1'b0;
			split_dynamic_q <= 1'b0;
			wdata_q <= launch_wdata_i;
			cycle_tag_q <= ~cycle_tag_q;
			cycle_start_q <= 1'b1;
		end
	endtask

	// Queue a posted-store launch behind the active transaction.
	task launch_to_pending_task;
		begin
			pending_q <= 1'b1;
			pending_addr_q <= launch_addr_i;
			pending_addr_error_q <= launch_addr_error_i;
			pending_size_q <= launch_size_i;
			pending_wdata_q <= launch_wdata_i;
		end
	endtask

	always @(posedge clk_i or posedge reset_i) begin
		if (reset_i) begin
			active_q <= 1'b0;
			addr_q <= 32'd0;
			second_a_q <= 31'd0;
			fetch_q <= 1'b1;
			fetch_branch_q <= 1'b1;
			write_q <= 1'b0;
			posted_q <= 1'b0;
			addr_error_q <= 1'b0;
			size_q <= 2'b01;
			phase_q <= 1'b0;
			wdata_q <= 32'd0;
			first_half_q <= 16'd0;
			split_dynamic_q <= 1'b0;
			cycle_tag_q <= 1'b0;
			cycle_start_q <= 1'b0;
			pending_q <= 1'b0;
			pending_addr_q <= 32'd0;
			pending_addr_error_q <= 1'b0;
			pending_size_q <= 2'b01;
			pending_wdata_q <= 32'd0;
		end else if (clk_en_i) begin
			cycle_start_q <= 1'b0;
			if (accepted_w) begin
				// Keep the low half until the high beat or next fetch half arrives.
				if (!write_q && (split_word_first_w ||
					(launch_i && launch_fetch_i && fetch_q))) begin
					first_half_q <= read_halfword_fn(din_i, fixed_16_i, addr_q[1]);
				end
				if (split_word_first_w) begin
					second_a_q <= addr_q[31:1] + 31'd1;
					phase_q <= 1'b1;
					split_dynamic_q <= !fixed_16_i;
					cycle_tag_q <= ~cycle_tag_q;
					cycle_start_q <= 1'b1;
					if (queue_accept_w) begin
						launch_to_pending_task;
					end
				end else if (pending_q) begin
					active_q <= 1'b1;
					addr_q <= pending_addr_q;
					fetch_q <= 1'b0;
					fetch_branch_q <= 1'b0;
					write_q <= 1'b1;
					posted_q <= 1'b1;
					addr_error_q <= pending_addr_error_q;
					size_q <= pending_size_q;
					phase_q <= 1'b0;
					split_dynamic_q <= 1'b0;
					wdata_q <= pending_wdata_q;
					cycle_tag_q <= ~cycle_tag_q;
					cycle_start_q <= 1'b1;
					if (queue_accept_w) begin
						launch_to_pending_task;
					end else begin
						pending_q <= 1'b0;
					end
				end else if (direct_accept_w) begin
					launch_to_active_task;
				end else begin
					active_q <= 1'b0;
				end
			end else if (direct_accept_w) begin
				launch_to_active_task;
			end else if (queue_accept_w) begin
				launch_to_pending_task;
			end
		end
	end

	function [3:0] byte_enable_fn;
		input fixed_16;
		input split_dynamic;
		input [1:0] size;
		input phase;
		input [1:0] addr_low;
		begin
			if (fixed_16) begin
				byte_enable_fn = (size == SIZE_B) ?
					(addr_low[0] ? 4'b1101 : 4'b1110) : 4'b1100;
			end else if (split_dynamic && phase) begin
				byte_enable_fn = 4'b0011;
			end else begin
				case (size)
					SIZE_B: begin
						case (addr_low)
							2'b00: byte_enable_fn = 4'b1110;
							2'b01: byte_enable_fn = 4'b1101;
							2'b10: byte_enable_fn = 4'b1011;
							default: byte_enable_fn = 4'b0111;
						endcase
					end
					2'b01: byte_enable_fn = addr_low[1] ? 4'b0011 : 4'b1100;
					default: byte_enable_fn = 4'b0000;
				endcase
			end
		end
	endfunction

	function [31:0] write_data_fn;
		input [31:0] data;
		input fixed_16;
		input split_dynamic;
		input [1:0] size;
		input phase;
		input [1:0] addr_low;
		begin
			if (fixed_16) begin
				case (size)
					// Fixed-16 byte stores still place all source bits 15:0 on the bus.
					SIZE_B: write_data_fn = addr_low[0] ?
						{16'd0, data[7:0], 8'd0} : {16'd0, data[15:0]};
					SIZE_W: write_data_fn = phase ?
						{16'd0, data[31:16]} : {16'd0, data[15:0]};
					default: write_data_fn = {16'd0, data[15:0]};
				endcase
			end else if (split_dynamic && phase) begin
				write_data_fn = {data[31:16], 16'd0};
			end else begin
				case (size)
					SIZE_B: begin
						case (addr_low)
							2'b00: write_data_fn = {24'd0, data[7:0]};
							2'b01: write_data_fn = {16'd0, data[7:0], 8'd0};
							2'b10: write_data_fn = {8'd0, data[7:0], 16'd0};
							default: write_data_fn = {data[7:0], 24'd0};
						endcase
					end
					2'b01: write_data_fn = addr_low[1] ?
						{data[15:0], 16'd0} : {16'd0, data[15:0]};
					default: write_data_fn = data;
				endcase
			end
		end
	endfunction

	function [15:0] read_halfword_fn;
		input [31:0] data;
		input fixed_16;
		input addr_bit1;
		begin
			read_halfword_fn = (fixed_16 || !addr_bit1) ? data[15:0] : data[31:16];
		end
	endfunction

	function [31:0] read_data_fn;
		input [31:0] data;
		input [15:0] first_half;
		input fixed_16;
		input split_dynamic;
		input [1:0] size;
		input phase;
		input [1:0] addr_low;
		reg [7:0] byte_v;
		reg [15:0] half_v;
		begin
			byte_v = 8'd0;
			half_v = 16'd0;
			if (fixed_16) begin
				byte_v = addr_low[0] ? data[15:8] : data[7:0];
			end else begin
				case (addr_low)
					2'b00: byte_v = data[7:0];
					2'b01: byte_v = data[15:8];
					2'b10: byte_v = data[23:16];
					default: byte_v = data[31:24];
				endcase
			end
			half_v = read_halfword_fn(data, fixed_16, addr_low[1]);
			case (size)
				SIZE_B: read_data_fn = {24'd0, byte_v};
				SIZE_W: begin
					if (phase) begin
						read_data_fn = split_dynamic ?
							{data[31:16], first_half} : {data[15:0], first_half};
					end else begin
						read_data_fn = data;
					end
				end
				default: read_data_fn = {16'd0, half_v};
			endcase
		end
	endfunction

endmodule
