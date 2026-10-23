// Copyright (c) 2026 Jamie Blanks

`timescale 1ns/1ps
`default_nettype none

// Controller for MiSTer's 16-bit SDR SDRAM interfaces. On the primary module,
// connect CKE and both DQM pins for masked writes. On the secondary module,
// leave those outputs unconnected: reads and unmasked 16/32/64-bit writes work,
// but 8-bit or partially masked writes require read-modify-write outside this
// controller because the physical secondary interface has no DQM pins.
//
// `clk` is the fixed 100 MHz SDRAM clock and also drives `SDRAM_CLK`. `clk_en`
// only gates new requests; initialization, refresh, and active transfers keep
// running. `reset` is synchronous and active high.
//
// A request is accepted when `clk_en`, `req`, and `ready` are high. Hold its
// control and data signals until then.
// - Port priority is fixed: p0 beats p1, and p1 beats p2.
// PORTx_SIZE selects the access width:
//     0 = 8 bits, 1 = 16 bits, 2 = 32 bits, 3 = 64 bits.
// Data uses the 64-bit bus. Narrow reads are zero-filled and narrow writes use
// the low bits. `dout_valid` pulses when the last read beat arrives; `ready`
// stays low until precharge finishes.
//
// `addr` is a byte address. BA is [25:24], row is [23:11], and column is
// [10:1]. Wider ports clear the needed low alignment bits. For byte accesses,
// addr[0] selects the byte lane.
//
// Byte-enable bit N controls pX_din[(N*8)+:8]. An 8-bit port uses pX_be[0], a
// 16-bit port uses [1:0], a 32-bit port uses [3:0], and a 64-bit port uses
// [7:0]. Higher bits are ignored. Reads do not consume byte enables.
//
// Pin-facing outputs are registered for IOE placement. Each closed-page access
// runs ACTIVATE, READ/WRITE, PRECHARGE, and the required timing gaps. The mode
// register uses the widest configured burst; shorter reads terminate early.
module sdram_generic #(
	parameter int unsigned PORT0_SIZE = 1,
	parameter int unsigned PORT1_SIZE = 1,
	parameter int unsigned PORT2_SIZE = 1,
	parameter bit AUTO_REFRESH = 1'b1
) (
	input  wire        clk,
	input  wire        clk_en,
	input  wire        reset,

	input  wire        refresh,

	input  wire        p0_req,
	input  wire        p0_we,
	input  wire [25:0] p0_addr,
	input  wire [63:0] p0_din,
	input  wire [7:0]  p0_be,
	output logic [63:0] p0_dout,
	output logic       p0_ready,
	output logic       p0_dout_valid,

	input  wire        p1_req,
	input  wire        p1_we,
	input  wire [25:0] p1_addr,
	input  wire [63:0] p1_din,
	input  wire [7:0]  p1_be,
	output logic [63:0] p1_dout,
	output logic       p1_ready,
	output logic       p1_dout_valid,

	input  wire        p2_req,
	input  wire        p2_we,
	input  wire [25:0] p2_addr,
	input  wire [63:0] p2_din,
	input  wire [7:0]  p2_be,
	output logic [63:0] p2_dout,
	output logic       p2_ready,
	output logic       p2_dout_valid,

	output wire        SDRAM_CLK,
	output logic       SDRAM_CKE,
	output logic [12:0] SDRAM_A,
	output logic [1:0] SDRAM_BA,
	inout  wire [15:0] SDRAM_DQ,
	output logic       SDRAM_DQML,
	output logic       SDRAM_DQMH,
	output logic       SDRAM_nCS,
	output logic       SDRAM_nCAS,
	output logic       SDRAM_nRAS,
	output logic       SDRAM_nWE
);

	localparam logic [3:0] CMD_DESELECT      = 4'b1111;
	localparam logic [3:0] CMD_NOP           = 4'b0111;
	localparam logic [3:0] CMD_ACTIVE        = 4'b0011;
	localparam logic [3:0] CMD_READ          = 4'b0101;
	localparam logic [3:0] CMD_WRITE         = 4'b0100;
	localparam logic [3:0] CMD_BURST_STOP    = 4'b0110;
	localparam logic [3:0] CMD_PRECHARGE     = 4'b0010;
	localparam logic [3:0] CMD_AUTO_REFRESH  = 4'b0001;
	localparam logic [3:0] CMD_LOAD_MODE     = 4'b0000;

	// Extra clocks required before the next dependent command.
	function automatic [15:0] count_after_command;
		input [15:0] cycles;
		begin
			if (cycles > 16'd1) count_after_command = cycles - 16'd1;
			else count_after_command = 16'd0;
		end
	endfunction

	function automatic [2:0] size_to_beats;
		input [1:0] size;
		begin
			unique case (size)
				2'd2: size_to_beats = 3'd2;
				2'd3: size_to_beats = 3'd4;
				default: size_to_beats = 3'd1;
			endcase
		end
	endfunction

	function automatic [2:0] max3;
		input [2:0] a;
		input [2:0] b;
		input [2:0] c;
		reg [2:0] m;
		begin
			m = a;
			if (b > m) m = b;
			if (c > m) m = c;
			max3 = m;
		end
	endfunction

	function automatic [2:0] burst_code;
		input [2:0] beats;
		begin
			unique case (beats)
				3'd4: burst_code = 3'b010;
				3'd2: burst_code = 3'b001;
				default: burst_code = 3'b000;
			endcase
		end
	endfunction

	function automatic [1:0] port_size;
		input [1:0] port_id;
		begin
			unique case (port_id)
				2'd0: port_size = PORT0_SIZE[1:0];
				2'd1: port_size = PORT1_SIZE[1:0];
				default: port_size = PORT2_SIZE[1:0];
			endcase
		end
	endfunction

	function automatic [25:0] align_addr;
		input [1:0] size;
		input [25:0] addr;
		begin
			unique case (size)
				2'd0: align_addr = addr;
				2'd1: align_addr = {addr[25:1], 1'b0};
				2'd2: align_addr = {addr[25:2], 2'b00};
				default: align_addr = {addr[25:3], 3'b000};
			endcase
		end
	endfunction

	function automatic [15:0] write_beat_data;
		input [1:0] size;
		input [63:0] data;
		input [1:0] beat;
		begin
			unique case (size)
				2'd0: write_beat_data = {data[7:0], data[7:0]};
				2'd1: write_beat_data = data[15:0];
				2'd2: begin
					if (beat[0]) write_beat_data = data[31:16];
					else write_beat_data = data[15:0];
				end
				default: begin
					unique case (beat)
						2'd0: write_beat_data = data[15:0];
						2'd1: write_beat_data = data[31:16];
						2'd2: write_beat_data = data[47:32];
						default: write_beat_data = data[63:48];
					endcase
				end
			endcase
		end
	endfunction

	function automatic [1:0] write_beat_dqm;
		input [1:0] size;
		input addr_bit;
		input [7:0] byte_enable;
		input [1:0] beat;
		begin
			if (size == 2'd0) begin
				if (addr_bit) write_beat_dqm = byte_enable[0] ? 2'b01 : 2'b11;
				else write_beat_dqm = byte_enable[0] ? 2'b10 : 2'b11;
			end else begin
				unique case (beat)
					2'd0: write_beat_dqm = ~byte_enable[1:0];
					2'd1: write_beat_dqm = ~byte_enable[3:2];
					2'd2: write_beat_dqm = ~byte_enable[5:4];
					default: write_beat_dqm = ~byte_enable[7:6];
				endcase
			end
		end
	endfunction

	function automatic [63:0] format_read_data;
		input [1:0] size;
		input addr_bit;
		input [63:0] data;
		begin
			unique case (size)
				2'd0: begin
					if (addr_bit) format_read_data = {56'd0, data[15:8]};
					else format_read_data = {56'd0, data[7:0]};
				end
				2'd1: format_read_data = {48'd0, data[15:0]};
				2'd2: format_read_data = {32'd0, data[31:0]};
				default: format_read_data = data;
			endcase
		end
	endfunction

	function automatic [63:0] insert_read_beat;
		input [63:0] data;
		input  [1:0] beat;
		input [15:0] beat_data;
		begin
			unique case (beat)
				2'd0: insert_read_beat = {data[63:16], beat_data};
				2'd1: insert_read_beat = {data[63:32], beat_data, data[15:0]};
				2'd2: insert_read_beat = {data[63:48], beat_data, data[31:0]};
				default: insert_read_beat = {beat_data, data[47:0]};
			endcase
		end
	endfunction

	localparam logic [2:0] PORT0_BEATS = size_to_beats(PORT0_SIZE[1:0]);
	localparam logic [2:0] PORT1_BEATS = size_to_beats(PORT1_SIZE[1:0]);
	localparam logic [2:0] PORT2_BEATS = size_to_beats(PORT2_SIZE[1:0]);

	// Use the widest port burst. BL1 uses single-write mode.
	localparam logic [2:0] MODE_BEATS = max3(PORT0_BEATS, PORT1_BEATS, PORT2_BEATS);
	localparam logic [2:0] MODE_BURST = burst_code(MODE_BEATS);
	// CL2 is valid for the AS4C32M16SB at 100 MHz.
	localparam logic [2:0] CAS_LATENCY = 3'd2;
	localparam logic MODE_WRITE_SINGLE = (MODE_BEATS == 3'd1);
	localparam logic [12:0] MODE_REG = {3'b000, MODE_WRITE_SINGLE, 2'b00, CAS_LATENCY, 1'b0, MODE_BURST};
	// Commands are registered on the same zero-degree clock driven to the SDRAM
	// pin, so the chip observes each command on the following physical edge.
	// Allow that registered-command cycle plus CL2 before sampling DQ on a
	// positive controller edge. CAS_LATENCY+1 samples before worst-case tAC.
	localparam logic [15:0] READ_CAPTURE_CYCLES = {13'd0, CAS_LATENCY} + 16'd2;
	// Retain the established burst-stop drain after moving capture back to its
	// physical-data-safe edge.
	localparam logic [15:0] READ_STOP_CYCLES = {13'd0, CAS_LATENCY} + 16'd1;

	// Rounded-up AS4C32M16SB-6 timings at 100 MHz.
	localparam logic [15:0] T_INIT_WAIT = 16'd20000; // >= 200 us power stable
	localparam logic [15:0] T_CKE_WAIT  = 16'd2;     // CKE-to-command setup
	localparam logic [15:0] T_RCD       = 16'd2;     // >= 18 ns
	localparam logic [15:0] T_RP        = 16'd2;     // >= 18 ns
	localparam logic [15:0] T_RAS       = 16'd5;     // >= 42 ns
	localparam logic [15:0] T_RFC       = 16'd6;     // >= 60 ns
	localparam logic [15:0] T_WR        = 16'd2;     // >= 12 ns
	localparam logic [15:0] T_MRD       = 16'd2;     // >= 12 ns
	// Reload 779 gives one refresh every 780 clocks, or 7.8 us at 100 MHz.
	localparam logic [15:0] T_REFI      = 16'd779;

	// Pending refresh debt pauses all ports at the next idle point.
	localparam logic [4:0] REFRESH_BLOCK_P2 = 5'd1;
	localparam logic [4:0] REFRESH_BLOCK_P1 = 5'd1;
	localparam logic [4:0] REFRESH_BLOCK_P0 = 5'd1;
	localparam logic [4:0] REFRESH_DEBT_MAX = 5'd15;

	typedef enum logic [4:0] {
		ST_POWER_WAIT,
		ST_NOP_WAIT,
		ST_INIT_TRP,
		ST_INIT_RFC1,
		ST_INIT_RFC2,
		ST_INIT_MRD,
		ST_IDLE,
		ST_RCD,
		ST_READ_LATENCY,
		ST_READ_BEATS,
		ST_READ_STOP_WAIT,
		ST_WRITE_BEATS,
		ST_WRITE_RECOVERY,
		ST_RAS_WAIT,
		ST_TRP,
		ST_REFRESH_WAIT
	} state_e;

	state_e state_q;
	logic init_done_q;
	logic [15:0] wait_q;
	logic [15:0] active_age_q;

	logic [1:0] active_port_q;
	logic [1:0] active_size_q;
	logic active_we_q;
	logic [25:0] active_addr_q;
	logic [63:0] active_din_q;
	logic [7:0] active_be_q;
	logic [2:0] active_beats_q;
	logic [2:0] beat_q;
	logic [63:0] read_data_q;

	logic [15:0] refresh_ctr_q;
	logic [4:0] refresh_debt_q;
	logic refresh_old_q;

	logic [15:0] dq_out_q;
	logic dq_oe_q;
	wire [15:0] dq_in;

	wire [25:0] p0_aligned_addr = align_addr(PORT0_SIZE[1:0], p0_addr);
	wire [25:0] p1_aligned_addr = align_addr(PORT1_SIZE[1:0], p1_addr);
	wire [25:0] p2_aligned_addr = align_addr(PORT2_SIZE[1:0], p2_addr);
	wire [63:0] first_read_data = insert_read_beat(64'd0, 2'd0, dq_in);
	wire [63:0] next_read_data = insert_read_beat(read_data_q, beat_q[1:0], dq_in);

	wire idle_accept = clk_en && init_done_q && (state_q == ST_IDLE);
	wire refresh_block_p0 = refresh_debt_q >= REFRESH_BLOCK_P0;
	wire refresh_block_p1 = refresh_debt_q >= REFRESH_BLOCK_P1;
	wire refresh_block_p2 = refresh_debt_q >= REFRESH_BLOCK_P2;
	wire no_client_request = !p0_req && !p1_req && !p2_req;
	wire selected_client_refresh_blocked =
		(p0_req && refresh_block_p0) ||
		(!p0_req && p1_req && refresh_block_p1) ||
		(!p0_req && !p1_req && p2_req && refresh_block_p2);
	wire refresh_service_due =
		(refresh_debt_q != 5'd0) &&
		(!clk_en || no_client_request || selected_client_refresh_blocked);
	wire periodic_refresh_event =
		init_done_q && AUTO_REFRESH && (refresh_ctr_q >= T_REFI);
	wire external_refresh_event =
		init_done_q && refresh && !refresh_old_q;
	wire refresh_service_fire =
		(state_q == ST_IDLE) && refresh_service_due;
	// One saturating update handles automatic, external, and serviced refreshes.
	wire [1:0] refresh_event_count =
		{1'b0, periodic_refresh_event} + {1'b0, external_refresh_event};
	wire [5:0] refresh_debt_after_service =
		{1'b0, refresh_debt_q} - (refresh_service_fire ? 6'd1 : 6'd0);
	wire [5:0] refresh_debt_total =
		refresh_debt_after_service + {4'd0, refresh_event_count};
	wire [4:0] refresh_debt_next =
		(refresh_debt_total > {1'b0, REFRESH_DEBT_MAX}) ?
		REFRESH_DEBT_MAX : refresh_debt_total[4:0];

	// MiSTer expects the core to drive SDRAM_CLK.
	assign SDRAM_CLK = clk;

	// Register data and OE together so Quartus can place them in the IOE.
	assign dq_in = SDRAM_DQ;
	assign SDRAM_DQ = dq_oe_q ? dq_out_q : 16'hZZZZ;

	// Ready reflects idle state and fixed port priority.
	always_comb begin
		p0_ready = 1'b0;
		p1_ready = 1'b0;
		p2_ready = 1'b0;

		if (idle_accept) begin
			p0_ready = !refresh_block_p0;
			p1_ready = !p0_req && !refresh_block_p1;
			p2_ready = !p0_req && !p1_req && !refresh_block_p2;
		end
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			state_q <= ST_POWER_WAIT;
			init_done_q <= 1'b0;
			wait_q <= count_after_command(T_INIT_WAIT);
			active_age_q <= 16'd0;
			active_port_q <= 2'd0;
			active_size_q <= 2'd1;
			active_we_q <= 1'b0;
			active_addr_q <= 26'd0;
			active_din_q <= 64'd0;
			active_be_q <= 8'h00;
			active_beats_q <= 3'd1;
			beat_q <= 3'd0;
			read_data_q <= 64'd0;
			refresh_ctr_q <= 16'd0;
			refresh_debt_q <= 5'd0;
			refresh_old_q <= 1'b0;
			p0_dout <= 64'd0;
			p1_dout <= 64'd0;
			p2_dout <= 64'd0;
			p0_dout_valid <= 1'b0;
			p1_dout_valid <= 1'b0;
			p2_dout_valid <= 1'b0;
			SDRAM_CKE <= 1'b0;
			SDRAM_A <= 13'd0;
			SDRAM_BA <= 2'd0;
			SDRAM_DQML <= 1'b1;
			SDRAM_DQMH <= 1'b1;
			{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_DESELECT;
			dq_out_q <= 16'd0;
			dq_oe_q <= 1'b0;
		end else begin
			p0_dout_valid <= 1'b0;
			p1_dout_valid <= 1'b0;
			p2_dout_valid <= 1'b0;
			refresh_old_q <= refresh;
			refresh_debt_q <= refresh_debt_next;

			// Active work and refresh continue even when clk_en is low.
			{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= init_done_q ? CMD_NOP : CMD_DESELECT;
			// Mask both DQ lanes during startup.
			SDRAM_DQML <= !init_done_q;
			SDRAM_DQMH <= !init_done_q;
			dq_oe_q <= 1'b0;

			if (init_done_q) begin
				// Automatic and external refresh requests both add debt.
				if (AUTO_REFRESH) begin
					if (refresh_ctr_q >= T_REFI) begin
						refresh_ctr_q <= 16'd0;
					end else begin
						refresh_ctr_q <= refresh_ctr_q + 16'd1;
					end
				end
			end

			if ((state_q != ST_POWER_WAIT) && (state_q != ST_NOP_WAIT) && (state_q != ST_IDLE)) begin
				if (active_age_q != 16'hFFFF) active_age_q <= active_age_q + 16'd1;
			end

			unique case (state_q)
				ST_POWER_WAIT: begin
					// JEDEC startup sequence.
					SDRAM_CKE <= 1'b0;
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						SDRAM_CKE <= 1'b1;
						state_q <= ST_NOP_WAIT;
						wait_q <= count_after_command(T_CKE_WAIT);
					end
				end

				ST_NOP_WAIT: begin
					SDRAM_CKE <= 1'b1;
					{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP;
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						SDRAM_A <= 13'b0010000000000;
						SDRAM_BA <= 2'd0;
						{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRECHARGE;
						state_q <= ST_INIT_TRP;
						wait_q <= count_after_command(T_RP);
					end
				end

				ST_INIT_TRP: begin
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AUTO_REFRESH;
						state_q <= ST_INIT_RFC1;
						wait_q <= count_after_command(T_RFC);
					end
				end

				ST_INIT_RFC1: begin
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AUTO_REFRESH;
						state_q <= ST_INIT_RFC2;
						wait_q <= count_after_command(T_RFC);
					end
				end

				ST_INIT_RFC2: begin
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						SDRAM_A <= MODE_REG;
						SDRAM_BA <= 2'd0;
						{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_LOAD_MODE;
						state_q <= ST_INIT_MRD;
						wait_q <= count_after_command(T_MRD);
					end
				end

				ST_INIT_MRD: begin
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						init_done_q <= 1'b1;
						state_q <= ST_IDLE;
					end
				end

				ST_IDLE: begin
					active_age_q <= 16'd0;
					if (refresh_service_due) begin
						{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AUTO_REFRESH;
						state_q <= ST_REFRESH_WAIT;
						wait_q <= count_after_command(T_RFC);
					end else if (p0_req && p0_ready) begin
						// Accept a new request.
						active_port_q <= 2'd0;
						active_size_q <= PORT0_SIZE[1:0];
						active_we_q <= p0_we;
						active_addr_q <= p0_aligned_addr;
						active_din_q <= p0_din;
						active_be_q <= p0_be;
						active_beats_q <= PORT0_BEATS;
						beat_q <= 3'd0;
						read_data_q <= 64'd0;
						SDRAM_A <= p0_aligned_addr[23:11];
						SDRAM_BA <= p0_aligned_addr[25:24];
						{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACTIVE;
						state_q <= ST_RCD;
						wait_q <= count_after_command(T_RCD);
					end else if (p1_req && p1_ready) begin
						// p0 has priority over p1.
						active_port_q <= 2'd1;
						active_size_q <= PORT1_SIZE[1:0];
						active_we_q <= p1_we;
						active_addr_q <= p1_aligned_addr;
						active_din_q <= p1_din;
						active_be_q <= p1_be;
						active_beats_q <= PORT1_BEATS;
						beat_q <= 3'd0;
						read_data_q <= 64'd0;
						SDRAM_A <= p1_aligned_addr[23:11];
						SDRAM_BA <= p1_aligned_addr[25:24];
						{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACTIVE;
						state_q <= ST_RCD;
						wait_q <= count_after_command(T_RCD);
					end else if (p2_req && p2_ready) begin
						// p0 and p1 have priority over p2.
						active_port_q <= 2'd2;
						active_size_q <= PORT2_SIZE[1:0];
						active_we_q <= p2_we;
						active_addr_q <= p2_aligned_addr;
						active_din_q <= p2_din;
						active_be_q <= p2_be;
						active_beats_q <= PORT2_BEATS;
						beat_q <= 3'd0;
						read_data_q <= 64'd0;
						SDRAM_A <= p2_aligned_addr[23:11];
						SDRAM_BA <= p2_aligned_addr[25:24];
						{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACTIVE;
						state_q <= ST_RCD;
						wait_q <= count_after_command(T_RCD);
					end
				end

				ST_RCD: begin
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						// Keep A10 low because precharge is issued separately.
						SDRAM_A <= {2'b00, 1'b0, active_addr_q[10:1]};
						SDRAM_BA <= active_addr_q[25:24];
						if (active_we_q) begin
							{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_WRITE;
							{SDRAM_DQMH, SDRAM_DQML} <= write_beat_dqm(
								active_size_q, active_addr_q[0], active_be_q, 2'd0);
							dq_out_q <= write_beat_data(active_size_q, active_din_q, 2'd0);
							dq_oe_q <= 1'b1;
							beat_q <= 3'd1;
							if (active_beats_q == 3'd1) begin
								if (MODE_BEATS == 3'd1) begin
									state_q <= ST_WRITE_RECOVERY;
									wait_q <= count_after_command(T_WR);
								end else begin
									state_q <= ST_WRITE_BEATS;
								end
							end else begin
								state_q <= ST_WRITE_BEATS;
							end
						end else begin
							{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_READ;
							// Include the registered command delay before DQ arrives.
							wait_q <= count_after_command(READ_CAPTURE_CYCLES);
							state_q <= ST_READ_LATENCY;
							beat_q <= 3'd0;
						end
					end
				end

				ST_READ_LATENCY: begin
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						read_data_q <= first_read_data;
						beat_q <= 3'd1;
						if (active_beats_q == 3'd1) begin
							// Return the word now, then close the bank before ready.
							unique case (active_port_q)
								2'd0: begin
									p0_dout <= format_read_data(active_size_q, active_addr_q[0], first_read_data);
									p0_dout_valid <= 1'b1;
								end
								2'd1: begin
									p1_dout <= format_read_data(active_size_q, active_addr_q[0], first_read_data);
									p1_dout_valid <= 1'b1;
								end
								default: begin
									p2_dout <= format_read_data(active_size_q, active_addr_q[0], first_read_data);
									p2_dout_valid <= 1'b1;
								end
							endcase
							if (active_beats_q < MODE_BEATS) begin
								{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_BURST_STOP;
								state_q <= ST_READ_STOP_WAIT;
								wait_q <= count_after_command(READ_STOP_CYCLES);
							end else begin
								state_q <= ST_RAS_WAIT;
							end
						end else begin
							state_q <= ST_READ_BEATS;
						end
					end
				end

				ST_READ_BEATS: begin
					// Assemble 16-bit burst words from low to high.
					read_data_q <= next_read_data;

					if ((beat_q + 3'd1) >= active_beats_q) begin
						unique case (active_port_q)
							2'd0: begin
								p0_dout <= format_read_data(active_size_q, active_addr_q[0], next_read_data);
								p0_dout_valid <= 1'b1;
							end
							2'd1: begin
								p1_dout <= format_read_data(active_size_q, active_addr_q[0], next_read_data);
								p1_dout_valid <= 1'b1;
							end
							default: begin
								p2_dout <= format_read_data(active_size_q, active_addr_q[0], next_read_data);
								p2_dout_valid <= 1'b1;
							end
						endcase
						if (active_beats_q < MODE_BEATS) begin
							{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_BURST_STOP;
							state_q <= ST_READ_STOP_WAIT;
							wait_q <= count_after_command(READ_STOP_CYCLES);
						end else begin
							state_q <= ST_RAS_WAIT;
						end
					end else begin
						beat_q <= beat_q + 3'd1;
					end
				end

				ST_READ_STOP_WAIT: begin
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						state_q <= ST_RAS_WAIT;
					end
				end

				ST_WRITE_BEATS: begin
					// Drive one 16-bit word per clock; DQM masks byte writes.
					if (beat_q < active_beats_q) begin
						{SDRAM_DQMH, SDRAM_DQML} <= write_beat_dqm(
							active_size_q, active_addr_q[0], active_be_q,
							beat_q[1:0]);
						dq_out_q <= write_beat_data(active_size_q, active_din_q, beat_q[1:0]);
						dq_oe_q <= 1'b1;
						beat_q <= beat_q + 3'd1;
					end else if (active_beats_q < MODE_BEATS) begin
						{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_BURST_STOP;
						state_q <= ST_WRITE_RECOVERY;
						wait_q <= count_after_command(T_WR);
					end else begin
						state_q <= ST_WRITE_RECOVERY;
						wait_q <= count_after_command(T_WR);
					end
				end

				ST_WRITE_RECOVERY: begin
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						state_q <= ST_RAS_WAIT;
					end
				end

				ST_RAS_WAIT: begin
					if (active_age_q >= T_RAS) begin
						// Precharge the selected bank with A10 low.
						SDRAM_A <= 13'd0;
						SDRAM_A[10] <= 1'b0;
						SDRAM_BA <= active_addr_q[25:24];
						{SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRECHARGE;
						state_q <= ST_TRP;
						wait_q <= count_after_command(T_RP);
					end
				end

				ST_TRP: begin
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						// The response was sent on the final beat; accept new work.
						state_q <= ST_IDLE;
					end
				end

				ST_REFRESH_WAIT: begin
					if (wait_q != 16'd0) begin
						wait_q <= wait_q - 16'd1;
					end else begin
						state_q <= ST_IDLE;
					end
				end

				default: begin
					state_q <= ST_POWER_WAIT;
					init_done_q <= 1'b0;
					wait_q <= count_after_command(T_INIT_WAIT);
				end
			endcase
		end
	end

endmodule

`default_nettype wire
