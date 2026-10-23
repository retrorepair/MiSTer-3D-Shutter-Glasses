// Copyright (c) 2026 Jamie Blanks

`timescale 1ns/1ps
`default_nettype none

// Cartridge-facing ROM and SRAM service.
//
// ROM download finalization, mirroring, and runtime reads retain the sealed RC5
// wrapper contract. Cartridge SRAM clients pass through the same restored
// physical SDRAM service instead of using the rejected monolithic wrapper.
module vb_cart_rom
(
	input  wire        clk_sys,
	input  wire        clk_ram,
	input  wire        reset_i,

	input  wire        rom_download_i,
	input  wire        ioctl_wr_i,
	input  wire [26:0] ioctl_addr_i,
	input  wire [15:0] ioctl_dout_i,
	output wire        ioctl_wait_o,
	output wire        rom_loaded_o,

	input  wire        req_valid_i,
	input  wire        req_tag_i,
	input  wire [23:0] req_addr_i,
	output wire [15:0] resp_data_o,
	output wire        resp_ready_o,

	input  wire        sram_req_i,
	input  wire        sram_we_i,
	input  wire [25:0] sram_addr_i,
	input  wire [15:0] sram_write_data_i,
	input  wire [1:0]  sram_be_i,
	input  wire        sram_read_lane_i,
	input  wire        sram_tag_i,
	output wire [15:0] sram_read_data_o,
	output wire        sram_read_valid_o,
	output wire        sram_access_done_o,

	input  wire        sram_bg_req_i,
	input  wire        sram_bg_we_i,
	input  wire [25:0] sram_bg_addr_i,
	input  wire [15:0] sram_bg_write_data_i,
	input  wire [1:0]  sram_bg_be_i,
	output wire        sram_bg_ready_o,
	output wire        sram_bg_done_o,
	output wire [15:0] sram_bg_read_data_o,
	output wire        foreground_idle_o,

	inout  wire [15:0] SDRAM_DQ,
	output wire [12:0] SDRAM_A,
	output wire        SDRAM_DQML,
	output wire        SDRAM_DQMH,
	output wire  [1:0] SDRAM_BA,
	output wire        SDRAM_nCS,
	output wire        SDRAM_nWE,
	output wire        SDRAM_nRAS,
	output wire        SDRAM_nCAS,
	output wire        SDRAM_CKE,
	output wire        SDRAM_CLK
);

	function automatic [23:0] rom_loaded_addr_mask_fn;
		input [26:0] addr_v;
		reg [26:0] last_byte_addr_v;
		begin
			last_byte_addr_v = addr_v + 27'd1;
			rom_loaded_addr_mask_fn = addr_v[23:0] |
				last_byte_addr_v[23:0];
		end
	endfunction

	function automatic [23:0] rom_mirror_addr_fn;
		input [23:0] addr_v;
		input [23:0] mask_v;
		begin
			rom_mirror_addr_fn = addr_v & mask_v;
		end
	endfunction

	reg        old_rom_download_q = 1'b0;
	reg        rom_loaded_q = 1'b0;
	reg [23:0] rom_mask_q = 24'd0;
	reg        rom_received_data_q = 1'b0;
	reg        rom_finalize_pending_q = 1'b0;
	reg        load_pending_q = 1'b0;
	reg        runtime_enable_ram_q = 1'b0;
	reg [23:0] rom_mask_ram_q = 24'd0;

	wire        storage_write_ready_w;
	wire        storage_write_done_w;
	wire        storage_read_valid_w;
	wire [15:0] storage_read_data_w;
	wire [23:0] req_rom_addr_w =
		rom_mirror_addr_fn(req_addr_i, rom_mask_ram_q);
	wire runtime_read_req_w = req_valid_i && runtime_enable_ram_q;
	wire rom_download_start_w = rom_download_i && !old_rom_download_q;
	wire load_accept_w = rom_download_i && old_rom_download_q &&
		ioctl_wr_i && !load_pending_q && storage_write_ready_w;

	assign ioctl_wait_o = rom_download_i &&
		(!old_rom_download_q || load_pending_q || !storage_write_ready_w);
	assign rom_loaded_o = rom_loaded_q;
	assign resp_data_o = storage_read_data_w;
	assign resp_ready_o = req_valid_i && storage_read_valid_w;

	vb_cart_sdram u_sdram (
		.clk_sys(clk_sys),
		.clk_ram(clk_ram),
		.reset_i(reset_i),
		.read_req_i(runtime_read_req_w),
		.read_visible_req_i(req_valid_i),
		.read_tag_i(req_tag_i),
		.read_addr_i({2'b00, req_rom_addr_w}),
		.read_valid_o(storage_read_valid_w),
		.read_data_o(storage_read_data_w),
		.write_req_i(load_accept_w),
		.write_addr_i({2'b00, ioctl_addr_i[23:0]}),
		.write_data_i(ioctl_dout_i),
		.write_ready_o(storage_write_ready_w),
		.write_done_o(storage_write_done_w),
		.sram_req_i(sram_req_i),
		.sram_we_i(sram_we_i),
		.sram_addr_i(sram_addr_i),
		.sram_write_data_i(sram_write_data_i),
		.sram_be_i(sram_be_i),
		.sram_read_lane_i(sram_read_lane_i),
		.sram_tag_i(sram_tag_i),
		.sram_read_data_o(sram_read_data_o),
		.sram_read_valid_o(sram_read_valid_o),
		.sram_access_done_o(sram_access_done_o),
		.sram_bg_req_i(sram_bg_req_i),
		.sram_bg_we_i(sram_bg_we_i),
		.sram_bg_addr_i(sram_bg_addr_i),
		.sram_bg_write_data_i(sram_bg_write_data_i),
		.sram_bg_be_i(sram_bg_be_i),
		.sram_bg_ready_o(sram_bg_ready_o),
		.sram_bg_done_o(sram_bg_done_o),
		.sram_bg_read_data_o(sram_bg_read_data_o),
		.foreground_idle_o(foreground_idle_o),
		.SDRAM_DQ(SDRAM_DQ),
		.SDRAM_A(SDRAM_A),
		.SDRAM_DQML(SDRAM_DQML),
		.SDRAM_DQMH(SDRAM_DQMH),
		.SDRAM_BA(SDRAM_BA),
		.SDRAM_nCS(SDRAM_nCS),
		.SDRAM_nWE(SDRAM_nWE),
		.SDRAM_nRAS(SDRAM_nRAS),
		.SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_CKE(SDRAM_CKE),
		.SDRAM_CLK(SDRAM_CLK)
	);

	always @(posedge clk_ram) begin
		if (reset_i) begin
			runtime_enable_ram_q <= 1'b0;
			rom_mask_ram_q <= 24'd0;
		end else begin
			runtime_enable_ram_q <= rom_loaded_q && !old_rom_download_q;
			rom_mask_ram_q <= rom_mask_q;
		end
	end

	always @(posedge clk_sys) begin
		old_rom_download_q <= rom_download_i;

		if (reset_i) begin
			old_rom_download_q <= 1'b0;
			rom_loaded_q <= 1'b0;
			rom_mask_q <= 24'd0;
			rom_received_data_q <= 1'b0;
			rom_finalize_pending_q <= 1'b0;
			load_pending_q <= 1'b0;
		end else begin
			if (storage_write_done_w) load_pending_q <= 1'b0;

			if (rom_download_start_w) begin
				rom_loaded_q <= 1'b0;
				rom_mask_q <= 24'd0;
				rom_received_data_q <= 1'b0;
				rom_finalize_pending_q <= 1'b0;
			end

			if (load_accept_w) begin
				load_pending_q <= 1'b1;
				rom_received_data_q <= 1'b1;
				rom_mask_q <= rom_mask_q |
					rom_loaded_addr_mask_fn(ioctl_addr_i);
			end

			if (old_rom_download_q && !rom_download_i) begin
				rom_finalize_pending_q <= 1'b1;
			end

			if (rom_finalize_pending_q && !load_pending_q &&
				storage_write_ready_w) begin
				if (rom_received_data_q && (rom_mask_q == 24'd0)) begin
					rom_mask_q <= 24'h000001;
				end
				rom_loaded_q <= rom_received_data_q;
				rom_finalize_pending_q <= 1'b0;
			end
		end
	end

endmodule

`default_nettype wire
