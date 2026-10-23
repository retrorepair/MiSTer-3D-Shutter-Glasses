// 3D shutter-glasses telemetry for the Virtual Boy core.
//
// With OSD > Eye Sequential on, the public raster shows one eye per frame. At the start of every frame this module
// writes an event to a ring in DDR3 (byte address 0x3DFFF000, 64 entries of 64 bytes, entry = sequence mod 64; same layout
// as the SMS core's glasses3d) so the MiSTer's ARM side (usb_emitter/mister_bt3d.py) can steer Bluetooth 3D shutter glasses.
//
//     [63:48] sequence (+1 per event)   [47:40] flags   [39:32] magic 0x5D   [31:0] clk_sys cycle counter at the frame start
//     flags: bit0 the frame that starts shows the left eye   bit1 active   bit3 enabled   bit4 frame-start event
//            bit6 clk_sys is the 40 MHz Virtual Boy clock
module vb_eyesync
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        enable_i,
	input  wire        frame_start_i,      // one clk_i pulse at the start of each public frame
	input  wire        eye_left_i,         // the eye shown in the frame that starts now

	output reg  [27:1] ddr_addr_o,         // half-word address inside the 0x30000000 window (see ddram.v)
	output reg  [63:0] ddr_din_o,
	output reg         ddr_req_o,          // one-clock request pulse
	output wire        ddr_rnw_o,
	output wire [7:0]  ddr_be_o,
	input  wire        ddr_ready_i
);

	localparam [26:0] BASE = 27'h6FFF800; // byte offset 0x0DFFF000 in the window = physical 0x3DFFF000

	assign ddr_rnw_o = 1'b0;
	assign ddr_be_o  = 8'hFF;

	reg [31:0] ts = 32'd0;
	reg [15:0] seq = 16'd0;
	reg        pend = 1'b0;
	reg        busy = 1'b0;
	reg [63:0] pend_word = 64'd0;
	reg  [5:0] pend_idx = 6'd0;

	always @(posedge clk_i) begin
		ts <= ts + 1'd1;
		ddr_req_o <= 1'b0;

		if (reset_i || !enable_i) begin
			seq  <= 16'd0;
			pend <= 1'b0;
			busy <= 1'b0;
		end else begin
			if (frame_start_i) begin
				seq       <= seq + 1'd1;
				pend_idx  <= seq[5:0] + 1'd1;
				pend_word <= {seq + 1'd1, 8'h5A | {7'd0, eye_left_i}, 8'h5D, ts};
				pend      <= 1'b1;
			end
			if (pend && !busy) begin
				ddr_addr_o <= BASE + {16'd0, pend_idx, 5'd0};
				ddr_din_o  <= pend_word;
				ddr_req_o  <= 1'b1;
				busy       <= 1'b1;
				pend       <= frame_start_i;     // a new event in this very cycle stays queued
			end
			if (busy && ddr_ready_i) busy <= 1'b0;
		end
	end

endmodule
