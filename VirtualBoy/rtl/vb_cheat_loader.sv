// Copyright (c) 2026 Jamie Blanks

// Builds a 16-byte MiSTer cheat record from WIDE(1) IOCTL halfword writes.
// The HPS streams records little-endian in the field order method/width,
// address, compare, value; the assembled record uses the layout documented in
// vb_cheat_engine.sv. Bit 128 strobes for one clock when a record completes.
module vb_cheat_loader
(
	input  wire         clk_sys_i,
	input  wire         cheat_download_i,
	input  wire         rom_download_i,
	input  wire         ioctl_wr_i,
	input  wire [3:0]   ioctl_addr_i,
	input  wire [15:0]  ioctl_dout_i,
	output reg          clear_o = 1'b0,
	output reg  [128:0] code_o = 129'd0
);

	reg cheat_download_q = 1'b0;
	reg rom_download_q   = 1'b0;

	always @(posedge clk_sys_i) begin
		code_o[128] <= 1'b0;
		clear_o <= 1'b0;
		cheat_download_q <= cheat_download_i;
		rom_download_q <= rom_download_i;

		// A new cheat transfer replaces the whole table, and a new ROM
		// invalidates it. Either start clears the engine before any record
		// arrives.
		if ((cheat_download_i && !cheat_download_q) ||
				(rom_download_i && !rom_download_q)) begin
			clear_o <= 1'b1;
		end

		if (cheat_download_i && ioctl_wr_i) begin
			case (ioctl_addr_i)
				4'd0:  code_o[111:96]  <= ioctl_dout_i;
				4'd2:  code_o[127:112] <= ioctl_dout_i;
				4'd4:  code_o[79:64]   <= ioctl_dout_i;
				4'd6:  code_o[95:80]   <= ioctl_dout_i;
				4'd8:  code_o[47:32]   <= ioctl_dout_i;
				4'd10: code_o[63:48]   <= ioctl_dout_i;
				4'd12: code_o[15:0]    <= ioctl_dout_i;
				4'd14: begin
					code_o[31:16] <= ioctl_dout_i;
					code_o[128]   <= 1'b1;
				end
				default: begin
				end
			endcase
		end
	end

endmodule
