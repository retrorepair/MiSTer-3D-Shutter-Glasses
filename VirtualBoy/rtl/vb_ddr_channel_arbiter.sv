// Copyright (c) 2026 Jamie Blanks

// Two-client transaction arbiter for one logical ddram bridge channel.
// Requests are captured as pulses and an accepted transaction remains owned by
// one client until the bridge returns ready. Client 2 wins only at an idle
// boundary; an in-flight client-1 transaction is never interrupted.
module vb_ddr_channel_arbiter
(
	input  wire        clk_i,
	input  wire        reset_i,

	input  wire [27:1] ch1_addr_i,
	output wire [63:0] ch1_dout_o,
	input  wire [63:0] ch1_din_i,
	input  wire        ch1_req_i,
	input  wire        ch1_rnw_i,
	input  wire [7:0]  ch1_be_i,
	output reg         ch1_ready_o,

	input  wire [27:1] ch2_addr_i,
	output wire [63:0] ch2_dout_o,
	input  wire [63:0] ch2_din_i,
	input  wire        ch2_req_i,
	input  wire        ch2_rnw_i,
	input  wire [7:0]  ch2_be_i,
	output reg         ch2_ready_o,

	output reg  [27:1] shared_addr_o,
	input  wire [63:0] shared_dout_i,
	output reg  [63:0] shared_din_o,
	output reg         shared_req_o,
	output reg         shared_rnw_o,
	output reg  [7:0]  shared_be_o,
	input  wire        shared_ready_i
);

	reg active_q;
	reg active_ch2_q;
	reg ch1_pending_q;
	reg ch2_pending_q;

	assign ch1_dout_o = shared_dout_i;
	assign ch2_dout_o = shared_dout_i;

	always @(posedge clk_i) begin
		if (reset_i) begin
			active_q <= 1'b0;
			active_ch2_q <= 1'b0;
			ch1_pending_q <= 1'b0;
			ch2_pending_q <= 1'b0;
			ch1_ready_o <= 1'b0;
			ch2_ready_o <= 1'b0;
			shared_addr_o <= 27'd0;
			shared_din_o <= 64'd0;
			shared_req_o <= 1'b0;
			shared_rnw_o <= 1'b0;
			shared_be_o <= 8'd0;
		end else begin
			ch1_pending_q <= ch1_pending_q || ch1_req_i;
			ch2_pending_q <= ch2_pending_q || ch2_req_i;
			ch1_ready_o <= 1'b0;
			ch2_ready_o <= 1'b0;
			shared_req_o <= 1'b0;

			if (active_q) begin
				if (shared_ready_i) begin
					active_q <= 1'b0;
					if (active_ch2_q) begin
						ch2_ready_o <= 1'b1;
					end else begin
						ch1_ready_o <= 1'b1;
					end
				end
			end else if (ch2_pending_q || ch2_req_i) begin
				active_q <= 1'b1;
				active_ch2_q <= 1'b1;
				ch2_pending_q <= 1'b0;
				shared_addr_o <= ch2_addr_i;
				shared_din_o <= ch2_din_i;
				shared_rnw_o <= ch2_rnw_i;
				shared_be_o <= ch2_be_i;
				shared_req_o <= 1'b1;
			end else if (ch1_pending_q || ch1_req_i) begin
				active_q <= 1'b1;
				active_ch2_q <= 1'b0;
				ch1_pending_q <= 1'b0;
				shared_addr_o <= ch1_addr_i;
				shared_din_o <= ch1_din_i;
				shared_rnw_o <= ch1_rnw_i;
				shared_be_o <= ch1_be_i;
				shared_req_o <= 1'b1;
			end
		end
	end

endmodule
