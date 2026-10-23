`timescale 1ns/1ps
// Testbench for vb_eyesync: every frame start gives one 64-bit ring write with the right address, sequence, eye and flags.
module tb_vb_eyesync;

reg clk = 0;
always #12.5 clk = ~clk;                 // 40 MHz

reg reset = 1, enable = 1, frame_start = 0, eye_left = 0;
wire [27:1] ddr_addr; wire [63:0] ddr_din; wire ddr_req, ddr_rnw; wire [7:0] ddr_be;
reg ddr_ready = 0;

vb_eyesync dut
(
	.clk_i(clk), .reset_i(reset), .enable_i(enable), .frame_start_i(frame_start), .eye_left_i(eye_left),
	.ddr_addr_o(ddr_addr), .ddr_din_o(ddr_din), .ddr_req_o(ddr_req), .ddr_rnw_o(ddr_rnw), .ddr_be_o(ddr_be),
	.ddr_ready_i(ddr_ready)
);

integer errors = 0;
task check(input cond, input [511:0] what);
	if (!cond) begin errors = errors + 1; $display("FAIL @%0t: %0s", $time, what); end
endtask

// DDR model: the request is answered some clocks later; the address and data are read when the request pulse is seen,
// like the arbiter does when it grants.
reg [63:0] mem [0:63];
integer i, writes = 0, delay = 0;
reg [63:0] last_word;
reg [27:1] last_addr;
reg        in_flight = 0;
always @(posedge clk) begin
	ddr_ready <= 0;
	if (ddr_req) begin
		check(!in_flight, "no request while one is in flight");
		in_flight <= 1;
		delay <= 1 + ($urandom % 20);
	end
	if (in_flight) begin
		if (delay == 0) begin
			last_word = ddr_din; last_addr = ddr_addr;
			check(ddr_rnw == 0 && ddr_be == 8'hFF, "write, all byte enables");
			check(ddr_addr >= 27'h6FFF800 && ddr_addr < 27'h6FFF800 + 27'd2048, "address inside the 64-entry ring");
			mem[(ddr_addr - 27'h6FFF800) >> 5] = ddr_din;
			writes = writes + 1;
			ddr_ready <= 1;
			in_flight <= 0;
		end else delay <= delay - 1;
	end
end

task frame(input left);
	begin
		eye_left = left;
		@(posedge clk); frame_start = 1; @(posedge clk); frame_start = 0;
		repeat (700) @(posedge clk);          // 17.5 us: the model answers long before the next frame in real life
	end
endtask

reg [63:0] w;
integer n, k;
initial begin
	for (i = 0; i < 64; i = i + 1) mem[i] = 0;
	#200; reset = 0;
	repeat (10) @(posedge clk);

	// 1) alternate eyes for 100 frames
	for (n = 1; n <= 100; n = n + 1) begin
		frame(n % 2);
		w = mem[n % 64];
		check(w[63:48] == n, "sequence number");
		check(w[39:32] == 8'h5D, "magic");
		check(w[47:40] == (8'h5A | (n % 2)), "flags: frame event, active, enabled, VB clock, eye");
		check(w[31:0] > 0, "timestamp");
	end
	check(writes == 100, "one ring write per frame");

	// 2) timestamps of consecutive frames differ by the frame spacing in clocks (700 + 2 + 2 cycles here)
	w = mem[99 % 64]; k = w[31:0];
	w = mem[100 % 64];
	check(w[31:0] - k >= 32'd700 && w[31:0] - k <= 32'd706, "frame spacing in clk_sys cycles");

	// 3) disabled: no traffic
	enable = 0;
	k = writes;
	frame(1); frame(0);
	check(writes == k, "no DDR traffic while disabled");

	// 4) re-enabled: sequence restarts
	enable = 1;
	repeat (3) @(posedge clk);
	frame(1);
	w = mem[1];
	check(w[63:48] == 1 && w[47:40] == 8'h5B, "sequence restarts after a disable");

	if (errors == 0) $display("PASS: vb_eyesync (%0d ring writes)", writes);
	else $display("FAILED with %0d errors", errors);
	$finish;
end

endmodule
