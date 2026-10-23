// Copyright (c) 2026 Jamie Blanks

`timescale 1ns/1ps

module vb_cart_ram_clear
(
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        start_i,
	input  wire        cancel_i,
	input  wire        mem_ready_i,
	output reg         busy_o,
	output reg  [2:0]  mem_type_o,
	output reg  [24:0] mem_addr_o,
	output wire        mem_wren_o,
	output wire [7:0]  mem_wdata_o
);
	localparam [2:0] MEM_TYPE_WRAM = 3'd0;
	localparam [2:0] MEM_TYPE_VRAM = 3'd1;
	localparam [2:0] MEM_TYPE_DRAM = 3'd2;

	localparam [24:0] WRAM_LAST_ADDR = 25'd65535;
	localparam [24:0] VIP_LAST_ADDR  = 25'd131071;

	assign mem_wren_o = busy_o;
	assign mem_wdata_o = 8'd0;

	always @(posedge clk_i) begin
		if (reset_i || cancel_i) begin
			busy_o <= 1'b0;
			mem_type_o <= MEM_TYPE_WRAM;
			mem_addr_o <= 25'd0;
		end else if (start_i) begin
			busy_o <= 1'b1;
			mem_type_o <= MEM_TYPE_WRAM;
			mem_addr_o <= 25'd0;
		end else if (busy_o && mem_ready_i) begin
			case (mem_type_o)
				MEM_TYPE_WRAM: begin
					if (mem_addr_o == WRAM_LAST_ADDR) begin
						mem_type_o <= MEM_TYPE_VRAM;
						mem_addr_o <= 25'd0;
					end else begin
						mem_addr_o <= mem_addr_o + 25'd1;
					end
				end

				MEM_TYPE_VRAM: begin
					if (mem_addr_o == VIP_LAST_ADDR) begin
						mem_type_o <= MEM_TYPE_DRAM;
						mem_addr_o <= 25'd0;
					end else begin
						mem_addr_o <= mem_addr_o + 25'd1;
					end
				end

				MEM_TYPE_DRAM: begin
					if (mem_addr_o == VIP_LAST_ADDR) begin
						busy_o <= 1'b0;
						mem_type_o <= MEM_TYPE_WRAM;
						mem_addr_o <= 25'd0;
					end else begin
						mem_addr_o <= mem_addr_o + 25'd1;
					end
				end

				default: begin
					busy_o <= 1'b0;
					mem_type_o <= MEM_TYPE_WRAM;
					mem_addr_o <= 25'd0;
				end
			endcase
		end
	end

endmodule
