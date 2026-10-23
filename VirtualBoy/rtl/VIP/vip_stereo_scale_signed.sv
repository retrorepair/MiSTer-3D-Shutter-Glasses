// Copyright (c) 2026 Jamie Blanks

`timescale 1ns/1ps

// Signed parallax scaler using wiring-only binary fractions.
//
// Scale table: 0 -> x1, 1 -> x3/4, 2 -> x5/8, 3 -> x1/2,
//              4 -> x3/8, 5 -> x1/4, 6 -> x1/8, 7 -> x0.

module vip_stereo_scale_signed
#(
	parameter integer WIDTH = 16
)
(
	input  wire signed [WIDTH-1:0] value_i,
	input  wire        [2:0]       scale_i,
	output reg  signed [WIDTH-1:0] value_o
);

	wire signed [WIDTH-1:0] half_w = value_i >>> 1;
	wire signed [WIDTH-1:0] quarter_w = value_i >>> 2;
	wire signed [WIDTH-1:0] eighth_w = value_i >>> 3;

	always @* begin
		case (scale_i)
			3'd0: value_o = value_i;
			3'd1: value_o = value_i - quarter_w;
			3'd2: value_o = half_w + eighth_w;
			3'd3: value_o = half_w;
			3'd4: value_o = quarter_w + eighth_w;
			3'd5: value_o = quarter_w;
			3'd6: value_o = eighth_w;
			// 3'd7 is the legitimate "x0" step, not an error catch-all.
			default: value_o = {WIDTH{1'b0}};
		endcase
	end

endmodule
