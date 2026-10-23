// Copyright (c) 2026 Jamie Blanks

// NEC V810 exception-entry plan decoder.
//
// Decodes a registered exception into the manual's NMI, fatal, duplexed, or
// ordinary entry path.
module necv810_exception_entry
(
	input  wire [15:0] code_i,
	input  wire [31:0] restore_pc_i,
	input  wire [31:0] psw_i,
	input  wire [31:0] ecr_i,

	output reg         fatal_o,
	output reg         save_ei_o,
	output reg         save_fe_o,
	output reg  [31:0] saved_pc_o,
	output reg  [31:0] saved_psw_o,
	output reg  [31:0] next_ecr_o,
	output reg         psw_write_o,
	output reg  [31:0] next_psw_o,
	output reg         pc_write_o,
	output reg  [31:0] handler_o,
	output reg         clear_nmi_pending_o,
	output reg         clear_halt_o,
	output reg         is_nmi_o,
	output reg         is_interrupt_o
);

	localparam [15:0] EXC_CODE_NMI = 16'hffd0;

	localparam [31:0] EXC_HANDLER_NMI = 32'hffff_ffd0;
	localparam [31:0] EXC_HANDLER_FLOAT = 32'hffff_ff60;

	localparam [31:0] PSW_WRITE_MASK = 32'h000f_f3ff;
	localparam [31:0] PSW_ID_MASK = 32'h0000_1000;
	localparam [31:0] PSW_AE_MASK = 32'h0000_2000;
	localparam [31:0] PSW_EP_MASK = 32'h0000_4000;
	localparam [31:0] PSW_NP_MASK = 32'h0000_8000;

	reg [3:0] next_irq_level_v;

	always @* begin
		fatal_o = 1'b0;
		save_ei_o = 1'b0;
		save_fe_o = 1'b0;
		saved_pc_o = {restore_pc_i[31:1], 1'b0};
		saved_psw_o = psw_i & PSW_WRITE_MASK;
		next_ecr_o = ecr_i;
		psw_write_o = 1'b0;
		next_psw_o = psw_i & PSW_WRITE_MASK;
		pc_write_o = 1'b0;
		handler_o = 32'd0;
		clear_nmi_pending_o = 1'b0;
		clear_halt_o = 1'b0;
		is_nmi_o = (code_i == EXC_CODE_NMI);
		is_interrupt_o = (code_i[15:8] == 8'hfe);
		next_irq_level_v = (code_i[7:4] == 4'hf) ? 4'hf :
			(code_i[7:4] + 4'd1);

		if (is_nmi_o) begin
			save_fe_o = 1'b1;
			next_ecr_o = {code_i, ecr_i[15:0]};
			psw_write_o = 1'b1;
			next_psw_o =
				((psw_i | PSW_NP_MASK | PSW_ID_MASK) & ~PSW_AE_MASK) &
				PSW_WRITE_MASK;
			pc_write_o = 1'b1;
			handler_o = EXC_HANDLER_NMI;
			clear_nmi_pending_o = 1'b1;
			clear_halt_o = 1'b1;
		end else if ((psw_i & PSW_NP_MASK) != 32'd0) begin
			fatal_o = 1'b1;
		end else if ((psw_i & PSW_EP_MASK) != 32'd0) begin
			save_fe_o = 1'b1;
			next_ecr_o = {code_i, ecr_i[15:0]};
			psw_write_o = 1'b1;
			next_psw_o =
				((psw_i | PSW_NP_MASK | PSW_ID_MASK) & ~PSW_AE_MASK) &
				PSW_WRITE_MASK;
			pc_write_o = 1'b1;
			handler_o = EXC_HANDLER_NMI;
			clear_halt_o = 1'b1;
		end else begin
			save_ei_o = 1'b1;
			next_ecr_o = {ecr_i[31:16], code_i};
			psw_write_o = 1'b1;
			next_psw_o =
				((psw_i | PSW_EP_MASK | PSW_ID_MASK) & ~PSW_AE_MASK) &
				PSW_WRITE_MASK;
			if (is_interrupt_o) begin
				next_psw_o[19:16] = next_irq_level_v;
				clear_halt_o = 1'b1;
			end
			pc_write_o = 1'b1;
			if (code_i[15:5] == 11'h7fb) begin
				handler_o = EXC_HANDLER_FLOAT;
			end else begin
				handler_o = {16'hffff, code_i[15:4], 4'b0000};
			end
		end
	end

endmodule
