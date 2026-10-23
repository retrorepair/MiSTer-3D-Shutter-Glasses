`timescale 1ns/1ps
// Testbench for glasses3d: write events and frame-start events must land in the DDR3 ring with the right fields.
module tb_glasses3d;

reg clk_sys = 0;
always #9.311 clk_sys = ~clk_sys;      // 53.693 MHz (NTSC core clock)

reg reset = 1, enable = 1, swap = 0, pal = 0, fast = 0, wr = 0, eye = 0, vblank = 0, ddr_ok = 1;
reg DDRAM_BUSY = 0;
wire [28:0] DDRAM_ADDR; wire [63:0] DDRAM_DIN; wire [7:0] DDRAM_BE; wire DDRAM_WE;

glasses3d #(.IDLE_FRAMES(3)) dut
(
	.clk_sys(clk_sys), .reset(reset), .enable(enable), .swap(swap), .pal(pal), .fast(fast),
	.wr(wr), .eye(eye), .vblank(vblank),
	.ddr_ok(ddr_ok), .DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_ADDR(DDRAM_ADDR), .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE)
);

integer errors = 0;
task check(input cond, input [511:0] what);
	if (!cond) begin errors = errors + 1; $display("FAIL @%0t: %0s", $time, what); end
endtask

// ---- DDR3 slave model: random BUSY, a write is accepted when WE && !BUSY -------------------
localparam [28:0] BASE = 29'h07BFFE00;
reg [63:0] mem [0:511];
integer i;
initial for (i = 0; i < 512; i = i + 1) mem[i] = 0;

integer busy_rate = 30;
integer writes_accepted = 0;
always @(posedge clk_sys) begin
	if (DDRAM_WE && !DDRAM_BUSY) begin
		check(DDRAM_ADDR >= BASE && DDRAM_ADDR < BASE + 512, "write address outside the ring");
		check(DDRAM_ADDR[2:0] == 3'b000, "entries are 64-byte aligned");
		mem[DDRAM_ADDR - BASE] = DDRAM_DIN;
		writes_accepted = writes_accepted + 1;
		check(DDRAM_BE == 8'hFF, "byte enable");
	end
	DDRAM_BUSY <= ($urandom % 100) < busy_rate;
end

// ---- ring access ----------------------------------------------------------------------------
reg [63:0] ent;
task get_entry(input integer seqno);
	ent = mem[(seqno % 64) * 8];
endtask

// kind: 0 = write event, 1 = frame event, 2 = activity timeout
task expect_event(input integer seqno, input want_left, input integer kind, input [255:0] what);
	reg [7:0] want_flags;
	begin
		get_entry(seqno);
		want_flags = (kind == 2) ? {2'd0, fast, 1'b0, enable, pal, 1'b0, 1'b1}
		                         : {2'd0, fast, (kind == 1), enable, pal, 1'b1, want_left};
		check(ent[63:48] == seqno, what);
		check(ent[39:32] == 8'h5D, "magic");
		check(ent[47:40] == want_flags, what);
	end
endtask

// ---- game model -----------------------------------------------------------------------------
integer game_writes = 0;
task game_write(input new_eye);
	begin
		eye = new_eye;
		@(posedge clk_sys); wr = 1; @(posedge clk_sys); wr = 0;
		game_writes = game_writes + 1;
	end
endtask

// One NTSC frame, 16.683 ms: vertical blanking (4.4 ms) with the game's write in it, then the picture.
task do_frame(input write_it, input new_eye);
	begin
		vblank = 1;
		#20_000;
		if (write_it) game_write(new_eye);
		#4_380_000;
		vblank = 0;                       // the picture of the next frame starts
		#12_283_000;
	end
endtask

integer seq_n = 0;                        // number of events the DUT must have produced so far
integer k2, t0;
reg [31:0] ts1, ts2;

initial begin
	#1000; reset = 0;
	#100_000;

	// 1) enabled but no game running: nothing is published
	check(writes_accepted == 0, "no events before a game writes the register");

	// 2) left frame, right frame, ... each gives a write event and a frame-start event
	do_frame(1, 1); seq_n = seq_n + 2;
	expect_event(seq_n - 1, 1, 0, "write event, left");
	expect_event(seq_n,     1, 1, "frame event, left");
	do_frame(1, 0); seq_n = seq_n + 2;
	expect_event(seq_n - 1, 0, 0, "write event, right");
	expect_event(seq_n,     0, 1, "frame event, right");
	do_frame(1, 1); seq_n = seq_n + 2;
	expect_event(seq_n - 1, 1, 0, "write event, left again");
	expect_event(seq_n,     1, 1, "frame event, left again");

	// timestamps: two frame events one frame apart
	get_entry(seq_n - 2); ts1 = ent[31:0];
	get_entry(seq_n);     ts2 = ent[31:0];
	check(ts2 - ts1 > 800000 && ts2 - ts1 < 1000000, "frame events are one video frame apart");

	// 3) a frame without a write still gets its frame-start event, with the eye unchanged
	do_frame(0, 0); seq_n = seq_n + 1;
	expect_event(seq_n, 1, 1, "frame event without a write");

	// 4) eye swap while active flips the eye
	swap = 1; #300_000; seq_n = seq_n + 1;
	expect_event(seq_n, 0, 0, "swap flips the eye");
	swap = 0; #300_000; seq_n = seq_n + 1;
	expect_event(seq_n, 1, 0, "unswap");

	// 5) a game writing every frame, with the bus unavailable: events queue (up to 8) and arrive in order
	do_frame(1, 0); seq_n = seq_n + 2;
	ddr_ok = 0;
	do_frame(1, 1); seq_n = seq_n + 2;
	do_frame(1, 0); seq_n = seq_n + 2;
	get_entry(seq_n);
	check(ent[63:48] != seq_n, "nothing written while the bus is unavailable");
	ddr_ok = 1; #300_000;
	expect_event(seq_n - 3, 1, 0, "queued write event 1");
	expect_event(seq_n - 2, 1, 1, "queued frame event 1");
	expect_event(seq_n - 1, 0, 0, "queued write event 2");
	expect_event(seq_n,     0, 1, "queued frame event 2");

	// 6) the game stops writing: two more frame events, then the activity timeout
	do_frame(0, 0); seq_n = seq_n + 1;
	expect_event(seq_n, 0, 1, "frame event, still active");
	do_frame(0, 0); seq_n = seq_n + 1;
	expect_event(seq_n, 0, 1, "frame event, still active");
	do_frame(0, 0); seq_n = seq_n + 1;
	expect_event(seq_n, 1, 2, "activity timeout");
	do_frame(0, 0);
	check(writes_accepted > 0, "traffic counter");
	get_entry(seq_n + 1);
	check(ent[63:48] != seq_n + 1, "no frame events while idle");

	// 7) resume under heavy BUSY
	busy_rate = 90;
	do_frame(1, 0); seq_n = seq_n + 2;
	expect_event(seq_n - 1, 0, 0, "busy 90%: write event");
	expect_event(seq_n,     0, 1, "busy 90%: frame event");
	busy_rate = 30;

	// 8) sequence wraps the 64-entry ring
	for (k2 = 0; k2 < 40; k2 = k2 + 1) begin
		do_frame(1, k2 % 2); seq_n = seq_n + 2;
	end
	expect_event(seq_n, 1, 1, "ring wrap newest (last frame was left)");
	get_entry(seq_n - 63);
	check(ent[63:48] == seq_n - 63, "ring keeps the last 64 events");

	// 9) PAL flag
	pal = 1; do_frame(1, 0); seq_n = seq_n + 2;
	get_entry(seq_n); check(ent[44] == 1'b1, "pal flag in frame events");
	pal = 0;

	// 9b) the +2.2% glasses sync clock shows in flag bit 5, on write and frame events
	fast = 1; do_frame(1, 1); seq_n = seq_n + 2;
	expect_event(seq_n - 1, 1, 0, "fast flag, write event");
	expect_event(seq_n,     1, 1, "fast flag, frame event");
	fast = 0;

	// 10) disable: no traffic
	enable = 0; #1_000;
	t0 = writes_accepted;
	do_frame(1, 1); do_frame(1, 0);
	check(writes_accepted == t0, "no DDR traffic while disabled");

	if (errors == 0) $display("PASS: glasses3d (%0d ring writes, %0d game writes)", writes_accepted, game_writes);
	else $display("FAILED with %0d errors", errors);
	$finish;
end

endmodule
