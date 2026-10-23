// DE-9 pad responses. Types: 0 = SMS, 1 = MD3, 2 = MD6, 3 = SMS fallback.
// sms_pins/pins use the core's active-low {TR, TL, U, D, L, R} order.
// Extra button inputs are active-high; B/C are the existing SMS Fire 1/2.
module sega_controller #(
	// Nominal 1.5 ms at clk_sys = 53.693175 MHz. External pad time does not
	// depend on ce_cpu, turbo, or savestate freeze. Real RC timers vary.
	parameter integer TIMEOUT_CYCLES = 80540
)(
	input        clk,
	input        reset,
	input  [1:0] controller_type,
	input  [5:0] sms_pins,
	input        th,
	input        md_a, md_start, md_x, md_y, md_z, md_mode,
	output reg [5:0] pins
);

localparam integer TIMER_BITS = (TIMEOUT_CYCLES < 2) ? 1 : $clog2(TIMEOUT_CYCLES);
reg [TIMER_BITS-1:0] timer = 0;
reg [2:0] rises = 0;
reg th_prev = 1'b1;
reg [1:0] type_prev = 0;

always @(posedge clk) begin
	th_prev <= th;
	type_prev <= controller_type;
	if (reset || controller_type != 2'd2 || type_prev != controller_type) begin
		timer <= 0;
		rises <= 0;
	end else if (th && !th_prev) begin
		timer <= 0;
		// After the fourth rise, stay in ordinary MD3 responses until timeout.
		if (rises < 4) rises <= rises + 1'b1;
	end else if (timer == TIMEOUT_CYCLES - 1) begin
		rises <= 0;
	end else begin
		timer <= timer + 1'b1;
	end
end

always @* begin
	pins = sms_pins;
	if (controller_type == 2'd1 || controller_type == 2'd2) begin
		if (!th) begin
			// TH low: Start, A, Up, Down, 0, 0.
			pins = {~md_start, ~md_a, sms_pins[3:2], 2'b00};
			if (controller_type == 2'd2 && rises == 2) pins[3:0] = 4'b0000;
			if (controller_type == 2'd2 && rises == 3) pins[3:0] = 4'b1111;
		end else if (controller_type == 2'd2 && rises == 3) begin
			// Third rising edge: U=Z, D=Y, L=X, R=Mode; B/C unchanged.
			pins[3:0] = {~md_z, ~md_y, ~md_x, ~md_mode};
		end
	end
end

endmodule
