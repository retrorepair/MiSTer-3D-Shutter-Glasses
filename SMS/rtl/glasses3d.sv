//============================================================================
//  SegaScope 3-D glasses support for the SMS core
//
//  The Sega 3-D glasses adapter sits in the card slot and snoops the Z80 bus.
//  A write to $FFF8-$FFFB (the adapter ignores A1:A0) selects the open lens:
//  bit 0 = 1 -> left lens open, bit 0 = 0 -> right lens open. The games write
//  it once per displayed frame, so each eye gets every other frame.
//
//  The FPGA has no USB, so events are published to DDR3 where the MiSTer's ARM
//  side can read them (/dev/mem) and forward them to an emitter. They go into a
//  ring of 64 entries of 64 bytes at DDR3 byte address 0x3DFFF000 (entry =
//  sequence number mod 64); only the first 64-bit word of an entry is used:
//
//     [63:48] sequence number (+1 per event)    [47:40] flags
//     [39:32] magic 0x5D                        [31:0]  clk_sys cycle counter
//                                                       at the event
//     flags: bit0 left lens open (1) / right lens open (0), after eye swap
//            bit1 a 3-D game wrote the register within the last IDLE_FRAMES
//            bit2 PAL timing       bit3 3-D output enabled in the OSD
//            bit5 core clock is the +2.2% glasses sync clock (clk_sys = 54.8868 MHz instead of 53.693175 MHz)
//            bit4 frame event: the picture of a new frame starts now (end of
//                 vertical blanking) with this eye; 0 = a write event
//
//  Events: every game write (the instant the real adapter would flip the
//  shutters), every frame start while a 3-D game is running (exact video
//  timing, for emitters that lock to the display), activity timing out, and an
//  eye swap while active.
//============================================================================

module glasses3d #(parameter IDLE_FRAMES = 30)
(
	input         clk_sys,
	input         reset,
	input         enable,        // OSD: publish events
	input         swap,          // OSD: exchange the eyes
	input         pal,
	input         fast,         // clk_sys runs at the +2.2% glasses sync clock
	input         wr,            // one clk_sys pulse after each $FFF8-$FFFB write
	input         eye,           // bit 0 of the last write: 1 = left open, 0 = right open
	input         vblank,

	input         ddr_ok,        // the DDRAM bus is free to start a transaction
	input         DDRAM_BUSY,
	output [28:0] DDRAM_ADDR,    // 64-bit word address
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE
);

localparam [28:0] BASE = 29'h07BFFE00;   // byte address 0x3DFFF000

// ---------------------------------------------------------------------------
//  Activity: a 3-D game writes the register every frame; if nothing has been
//  written for IDLE_FRAMES frames the game is not using the glasses.
// ---------------------------------------------------------------------------
reg [5:0] idle_frames = IDLE_FRAMES;
wire      act_now = enable & (idle_frames != IDLE_FRAMES);
reg       old_vblank = 0;
reg       active_r = 0;
reg       old_swap = 0;

always @(posedge clk_sys) begin
	old_vblank <= vblank;
	old_swap   <= swap;

	if (~old_vblank & vblank && idle_frames != IDLE_FRAMES)
		idle_frames <= idle_frames + 1'd1;

	if (wr)
		idle_frames <= 0;

	if (reset | ~enable)
		idle_frames <= IDLE_FRAMES;

	active_r <= act_now;
end

// ---------------------------------------------------------------------------
//  Event queue
// ---------------------------------------------------------------------------
reg [31:0] ts = 0;
always @(posedge clk_sys) ts <= ts + 1'd1;

wire       eye_eff   = eye ^ swap;
wire [7:0] flags_on  = {2'd0, fast, 1'b0, enable, pal, 1'b1, eye_eff};
wire [7:0] flags_off = {2'd0, fast, 1'b0, enable, pal, 1'b0, 1'b1};

wire ev_wr    = wr;
wire ev_frame = act_now & old_vblank & ~vblank;          // picture of a new frame starts
wire ev_off   = active_r & ~act_now;
wire ev_swap  = act_now & (swap != old_swap);
wire ev_any   = ev_wr | ev_frame | ev_off | ev_swap;
wire [7:0] ev_flags = ev_off ? flags_off : (ev_frame ? (flags_on | 8'h10) : flags_on);

reg [15:0] seq = 0;
reg [55:0] fifo [0:7];
reg  [2:0] f_wp = 0, f_rp = 0;
reg  [3:0] f_cnt = 0;

wire        f_empty = (f_cnt == 0);
wire [55:0] f_head  = fifo[f_rp];
reg         pop;

always @(posedge clk_sys) begin
	if (reset | ~enable) begin
		seq   <= 0;
		f_wp  <= 0;
		f_rp  <= 0;
		f_cnt <= 0;
	end else begin
		if (ev_any) begin
			fifo[f_wp] <= {seq + 1'd1, ev_flags, ts};
			seq        <= seq + 1'd1;
			f_wp       <= f_wp + 1'd1;
		end
		if (pop) f_rp <= f_rp + 1'd1;

		case ({ev_any, pop})
			2'b10: f_cnt <= (f_cnt == 4'd8) ? f_cnt : f_cnt + 1'd1;
			2'b01: f_cnt <= f_cnt - 1'd1;
			default: ;
		endcase
		// full queue: the oldest entry is overwritten
		if (ev_any && f_cnt == 4'd8 && !pop) f_rp <= f_rp + 1'd1;
	end
end

// ---------------------------------------------------------------------------
//  DDR3 writer: one single-beat write per event
// ---------------------------------------------------------------------------
reg [63:0] din = 0;
reg [28:0] addr = BASE;
reg        we = 0;

always @(posedge clk_sys) begin
	pop <= 0;

	if (we) begin
		if (!DDRAM_BUSY) we <= 0;                   // accepted
	end else if (!f_empty && ddr_ok && enable) begin
		din  <= {f_head[55:40], f_head[39:32], 8'h5D, f_head[31:0]};
		addr <= BASE + {20'd0, f_head[45:40], 3'b000};
		we   <= 1;
		pop  <= 1;
	end
end

assign DDRAM_ADDR = addr;
assign DDRAM_DIN  = din;
assign DDRAM_BE   = 8'hFF;
assign DDRAM_WE   = we;

endmodule
