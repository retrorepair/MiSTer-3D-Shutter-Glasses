
// NEC V810
// Copyright (c) Jamie Blanks

// FPGA model of the NEC V810. Sacred Tech Scrolls are the main behavior and
// timing reference. The design uses synchronous memories and staged control.

module NECv810
#(
	parameter [31:0] RESET_PC  = 32'hffff_fff0,
	parameter [31:0] RESET_PSW = 32'h0000_8000
)
(
	input  wire        clk_i,            // System clock
	input  wire        reset_i,          // Active-high FPGA reset; physical RESET is active low.
	input  wire        ce_i,             // Single-clk clock enable representing the positive edge of the driving clock.
	input  wire        phi1_i,           // Single-clk clock enable representing the negative edge of the driving clock.

	// Some package signals use FPGA-friendly active-high polarity.
	// READY and DIN are consumed combinationally at the CE (rising) edge: a
	// beat completes at the first CE edge where READY is high, and DIN is
	// latched at that same edge. Neither is sampled at phi1, so external
	// memory may return data up to the last moment before a CE edge.
	input  wire        ready_i,          // Active-high logical beat acceptance; physical READY is active low.
	input  wire [31:0] din_i,            // External data input, latched at the accepting CE edge.
	input  wire        hldrq_i,          // Active-high logical hold request; physical HLDRQ is active low.
	input  wire        icheen_i,         // Active-high logical cache permission; physical ICHEEN is active low.
	input  wire        siz16b_i,         // Logical high selects fixed 16-bit mode; physical SIZ16B is active low.
	input  wire        szrq_i,           // Literal active-low dynamic bus-size request.

	input  wire        irq_valid_i,      // Encoded active-high IRQ valid; replaces physical INT.
	input  wire [3:0]  irq_level_i,      // Decoded IRQ level; replaces physical INTV3:0.
	input  wire        nmi_i,            // Active-high NMI request, matching the physical NMI pin sense.

	// Savestate writes occur only while the parent has stopped CPU enables.
	input  wire        savestate_pause_req_i,
	output wire        savestate_pause_ready_o,
	input  wire        savestate_restore_i,
	input  wire [3:0]  savestate_state_addr_i,
	input  wire [63:0] savestate_state_wdata_i,
	input  wire        savestate_state_wren_i,
	output reg  [63:0] savestate_state_rdata_o,
	input  wire        savestate_mem_active_i,
	input  wire [10:0] savestate_mem_addr_i,
	input  wire        savestate_mem_rden_i,
	input  wire        savestate_mem_wren_i,
	input  wire [7:0]  savestate_mem_wdata_i,
	output reg  [7:0]  savestate_mem_rdata_o,

	output wire [31:1] a_o,              // External address bus, word-addressed with A0 omitted.
	output wire        a_oe_o,           // High while the physical address pins are driven.
	output wire [31:0] dout_o,           // External data output bus.
	output wire        dout_oe_o,        // Logical full-bus write-data enable used by the FPGA integration.
	output wire [3:0]  dout_lane_oe_o,   // Physical byte-lane OEs; fixed-16 mode never drives D31:D16.
	// BE, R/W, BLOCK, and ADRSERR keep package polarity. Other controls are
	// active high. Separate OEs model undriven package pins.
	output wire [3:0]  be_o,             // Literal active-low external byte enables.
	output wire [3:0]  be_oe_o,          // Physical BE pin OEs; fixed-16 mode never drives BE3:BE2.
	output wire [1:0]  st_o,             // Bus status outputs identifying fetch and data cycles.
	output wire        st_oe_o,          // High while the physical ST pins are driven.
	output wire        da_o,             // Normalized active-high data-access qualifier; physical DA is active low.
	output wire        da_oe_o,          // High while the physical DA pin is driven.
	output wire        mrq_o,            // Normalized request-valid; physical MRQ is active low on the shared memory/I/O carrier.
	output wire        mrq_oe_o,         // High while the physical MRQ pin is driven.
	output wire        rw_o,             // Literal high-read/low-write direction.
	output wire        rw_oe_o,          // High while the physical R/W pin is driven.
	output wire        bcyst_o,          // Normalized active-high cycle-start pulse; physical BCYST is active low.
	output wire        bcyst_oe_o,       // High while the physical BCYST pin is driven.
	output wire        adrs_err_n_o,     // Active-low illegal data-alignment indication.
	// FPGA-only tag that toggles for every cartridge transfer or split beat.
	output wire        cycle_tag_o,
	output wire        block_o,          // Literal active-high bus lock during CAXI.
	output wire        hldak_o,          // Normalized active-high hold acknowledge; physical HLDAK is active low.

	// FPGA-only debug and test outputs.
	input  wire [4:0]  dbg_reg_addr_i,   // Debug-only register-file read address.
	output wire [31:0] dbg_reg_data_o,   // Debug-only register-file read data.
	output wire [31:0] dbg_pc_o,         // Debug-only architectural PC mirror.
	output wire [31:0] dbg_psw_o,        // Debug-only architectural PSW mirror.
	output reg         trace_valid_o,    // Test-only retire trace valid pulse.
	output reg  [31:0] trace_pc_o,       // Test-only retired instruction PC.
	output reg  [15:0] trace_insn_o,     // Test-only retired first halfword.
	output wire        halted_o,         // Test-only architectural HALT-state mirror.
	output wire        illegal_o         // Test-only one-CE illegal-decode pulse.
);
	// Guy's Cycle Test measurements from a real Virtual Boy.

	// +----------+-----------+--------+--------+
	// | Mnemonic | Form      | Opcode | Cycles |
	// +----------+-----------+--------+--------+
	// | ADD      | Immediate | 051E   | 1      |
	// | ADD      | Register  | 051E   | 1      |
	// | ADDF.S   |           | 6F5C   | 22     |
	// | ADDI     |           | 051E   | 1      |
	// | AND      |           | 051E   | 1      |
	// | ANDI     |           | 051E   | 1      |
	// | CLI      |           | 3D71   | 12     |
	// | CMP      | Immediate | 06ED   | 1      |
	// | CMP      | Register  | 051E   | 1      |
	// | CMPF.S   |           | 228F   | 7      |
	// | CVT.SW   |           | 4666   | 14     |
	// | CVT.WS   |           | 27AE   | 8      |
	// | DIV      |           | C147   | 38     |
	// | DIVF.S   |           | DFFF   | 44     |
	// | DIVU     |           | B700   | 36     |
	// | LDSR     |           | 28F5   | 8      |
	// | MOV      | Immediate | 051E   | 1      |
	// | MOV      | Register  | 051E   | 1      |
	// | MOVEA    |           | 051E   | 1      |
	// | MOVHI    |           | 051E   | 1      |
	// | MPYHW    |           | 2C?C   | 9      |
	// | MUL      |           | 4147   | 13     |
	// | MULF.S   |           | 83D7   | 26     |
	// | MULU     |           | 4148   | 13     |
	// | NOT      |           | 051F   | 1      |
	// | OR       |           | 051E   | 1      |
	// | ORI      |           | 051E   | 1      |
	// | REV      |           | 6F5B   | 22     |
	// | SAR      | Immediate | 051E   | 1      |
	// | SAR      | Register  | 051E   | 1      |
	// | SEI      |           | 3D70   | 12     |
	// | SETF     |           | 051E   | 1      |
	// | SHL      | Immediate | 051E   | 1      |
	// | SHL      | Register  | 051E   | 1      |
	// | SHR      | Immediate | 051F   | 1      |
	// | SHR      | Register  | 051E   | 1      |
	// | STSR     |           | 28F5   | 8      |
	// | SUB      |           | 051E   | 1      |
	// | SUBF.S   |           | 83D7   | 26     |
	// | TRNC.SW  |           | 4147   | 13     |
	// | XB       |           | 1D70   | 6      |
	// | XH       |           | 051F   | 1      |
	// | XOR      |           | 051E   | 1      |
	// | XORI     |           | 051F   | 1      |
	// +----------+-----------+--------+--------+


	// Timing uses Sacred first and NEC tables 5-11 through 5-14 as backup.
	// Counts assume cache hits, no waits or hazards, and a 16-bit bus.
	//
	// +----------------------+----------------------+--------------------------------------+
	// | Family / instruction | Documented cycles    | Source / notes                       |
	// +----------------------+----------------------+--------------------------------------+
	// | Simple ALU / moves   | 1                    | Sacred fixed-count rows              |
	// |                      |                      | ADD/SUB/CMP/MOV/MOVEA/MOVHI/         |
	// |                      |                      | OR/AND/XOR/NOT/SHL/SHR/SAR/SETF/XH   |
	// | Bcond                | 1 / 3                | Sacred: not taken / taken            |
	// | JMP / JR / JAL       | 3                    | NEC backup; Sacred matches behavior  |
	// | LDSR / STSR          | 8                    | Sacred fixed-count rows              |
	// | CLI / SEI            | 12                   | Sacred fixed-count rows              |
	// | TRAP / RETI          | 15 / 10              | NEC backup; Sacred describes flow    |
	// | MUL / MULU           | 13                   | Sacred fixed-count rows              |
	// | DIV / DIVU           | 38 / 36              | Sacred fixed-count rows              |
	// | XB / XH / REV        | 6 / 1 / 22           | Sacred fixed-count rows              |
	// | MPYHW                | 9                    | Sacred fixed-count rows              |
	// | LD.B / LD.H          | 1..3                 | NEC backup; predecessor-sensitive    |
	// | LD.W                 | 1..5                 | NEC backup; 16-bit bus timing        |
	// | ST.* / OUT.*         | table-driven         | NEC backup; repeat family on 16-bit  |
	// | IN.B / IN.H / IN.W   | 3 / 3 / 5            | NEC backup; 16-bit bus timing        |
	// | CAXI                 | 26                   | Sacred CAXI row plus NEC 16-bit bus  |
	// | CMPF.S               | 7..10                | Sacred floating-point table          |
	// | CVT.WS               | 5..16                | Sacred floating-point table          |
	// | CVT.SW / TRNC.SW     | 9..14                | Sacred floating-point table          |
	// | ADDF.S / SUBF.S      | 9..28 / 12..28       | Sacred floating-point table          |
	// | MULF.S / DIVF.S      | 8..30 / 44           | Sacred floating-point table          |
	// | Search bit-string    | table-driven         | NEC Table 5-12; depends on direction,|
	// |                      |                      | boundaries, N, and detection point p |
	// | Arith bit-string     | table-driven         | NEC Table 5-13 / 5-14; depends on    |
	// |                      |                      | TYPE1..TYPE7 and 16-bit bus slope    |
	// +----------------------+----------------------+--------------------------------------+

	localparam [5:0] STATE_CACHE_INIT       = 6'd0;
	localparam [5:0] STATE_LOOKUP_CUR_REQ   = 6'd1;
	localparam [5:0] STATE_LOOKUP_CUR_WAIT  = 6'd2;
	localparam [5:0] STATE_LOOKUP_NEXT_REQ  = 6'd3;
	localparam [5:0] STATE_LOOKUP_NEXT_WAIT = 6'd4;
	localparam [5:0] STATE_FILL_REQ         = 6'd5;
	localparam [5:0] STATE_FILL_WAIT        = 6'd6;
	localparam [5:0] STATE_EXEC             = 6'd7;
	localparam [5:0] STATE_CACHE_CLEAR      = 6'd8;
	localparam [5:0] STATE_MEM_REQ          = 6'd9;
	localparam [5:0] STATE_MEM_WAIT         = 6'd10;
	localparam [5:0] STATE_EXC_ENTER        = 6'd11;
	localparam [5:0] STATE_FATAL_REQ        = 6'd12;
	localparam [5:0] STATE_FATAL_WAIT       = 6'd13;
	localparam [5:0] STATE_UCODE_WAIT       = 6'd14;
	localparam [5:0] STATE_LONG             = 6'd15;
	localparam [5:0] STATE_CHCW_RAM_REQ     = 6'd16;
	localparam [5:0] STATE_CHCW_RAM_WAIT    = 6'd17;
	localparam [5:0] STATE_CHCW_BUS_REQ     = 6'd18;
	localparam [5:0] STATE_CHCW_BUS_WAIT    = 6'd19;
	localparam [5:0] STATE_CHCW_RAM_WRITE   = 6'd20;
	localparam [5:0] STATE_CAXI_REQ         = 6'd21;
	localparam [5:0] STATE_CAXI_WAIT        = 6'd22;
	localparam [5:0] STATE_CAXI_STORE_REQ   = 6'd23;
	localparam [5:0] STATE_CAXI_STORE_WAIT  = 6'd24;
	localparam [5:0] STATE_BS_SRC_REQ       = 6'd25;
	localparam [5:0] STATE_BS_SRC_WAIT      = 6'd26;
	localparam [5:0] STATE_BS_DST_REQ       = 6'd27;
	localparam [5:0] STATE_BS_DST_WAIT      = 6'd28;
	localparam [5:0] STATE_BS_WRITE_REQ     = 6'd29;
	localparam [5:0] STATE_BS_WRITE_WAIT    = 6'd30;
	localparam [5:0] STATE_TIMING_WAIT      = 6'd31;
	localparam [5:0] STATE_BS_TIMING_WAIT   = 6'd32;
	localparam [5:0] STATE_BUS_HOLD         = 6'd33;
	localparam [5:0] STATE_FRONT_WAIT       = 6'd34;
	localparam [5:0] STATE_IFETCH_REQ       = 6'd35;
	localparam [5:0] STATE_IFETCH_WAIT      = 6'd36;
	localparam [5:0] STATE_IFETCH2_REQ      = 6'd37;
	localparam [5:0] STATE_IFETCH2_WAIT     = 6'd38;
	localparam [5:0] STATE_BS_SEARCH_SCAN   = 6'd39;
	localparam [5:0] STATE_BS_SEARCH_COMMIT = 6'd40;
	localparam [5:0] STATE_LONG_LOAD_WAIT   = 6'd41;
	localparam [5:0] STATE_IFETCH_ISSUE     = 6'd42;
	localparam [5:0] STATE_IFETCH_DISCARD   = 6'd43;
	localparam [5:0] STATE_SAVESTATE_HOLD   = 6'd44;

	localparam [1:0] SIZE_B = 2'b00;
	localparam [1:0] SIZE_H = 2'b01;
	localparam [1:0] SIZE_W = 2'b10;

	localparam [4:0] SYS_EIPC  = 5'd0;
	localparam [4:0] SYS_EIPSW = 5'd1;
	localparam [4:0] SYS_FEPC  = 5'd2;
	localparam [4:0] SYS_FEPSW = 5'd3;
	localparam [4:0] SYS_ECR   = 5'd4;
	localparam [4:0] SYS_PSW   = 5'd5;
	localparam [4:0] SYS_PIR   = 5'd6;
	localparam [4:0] SYS_TKCW  = 5'd7;
	localparam [4:0] SYS_CHCW  = 5'd24;
	localparam [4:0] SYS_ADTRE = 5'd25;
	localparam [4:0] SYS_SR29  = 5'd29;
	localparam [4:0] SYS_SR30  = 5'd30;
	localparam [4:0] SYS_SR31  = 5'd31;

	localparam [31:0] PIR_VALUE      = 32'h0000_5346;
	localparam [31:0] TKCW_VALUE     = 32'h0000_00e0;
	localparam [31:0] SR30_VALUE     = 32'h0000_0004;
	localparam [31:0] PSW_WRITE_MASK = 32'h000f_f3ff;
	localparam [31:0] PSW_Z_MASK = 32'h0000_0001;

	localparam [31:0] PSW_ID_MASK = 32'h0000_1000;
	localparam [31:0] PSW_AE_MASK = 32'h0000_2000;
	localparam [31:0] PSW_EP_MASK = 32'h0000_4000;
	localparam [31:0] PSW_NP_MASK = 32'h0000_8000;

	localparam [15:0] EXC_CODE_ILLEGAL  = 16'hff90;
	localparam [15:0] EXC_CODE_ZERODIV  = 16'hff80;
	localparam [15:0] EXC_CODE_ADDRTRAP = 16'hffc0;
	localparam [15:0] EXC_CODE_NMI      = 16'hffd0;


	localparam [5:0] OP_MOV_R  = 6'b000000;
	localparam [5:0] OP_ADD_R  = 6'b000001;
	localparam [5:0] OP_SUB_R  = 6'b000010;
	localparam [5:0] OP_CMP_R  = 6'b000011;
	localparam [5:0] OP_SHL_R  = 6'b000100;
	localparam [5:0] OP_SHR_R  = 6'b000101;
	localparam [5:0] OP_JMP    = 6'b000110;
	localparam [5:0] OP_SAR_R  = 6'b000111;
	localparam [5:0] OP_MUL    = 6'b001000;
	localparam [5:0] OP_DIV    = 6'b001001;
	localparam [5:0] OP_MULU   = 6'b001010;
	localparam [5:0] OP_DIVU   = 6'b001011;
	localparam [5:0] OP_OR_R   = 6'b001100;
	localparam [5:0] OP_AND_R  = 6'b001101;
	localparam [5:0] OP_XOR_R  = 6'b001110;
	localparam [5:0] OP_NOT_R  = 6'b001111;
	localparam [5:0] OP_MOV_I  = 6'b010000;
	localparam [5:0] OP_ADD_I  = 6'b010001;
	localparam [5:0] OP_SETF   = 6'b010010;
	localparam [5:0] OP_CMP_I  = 6'b010011;
	localparam [5:0] OP_SHL_I  = 6'b010100;
	localparam [5:0] OP_SHR_I  = 6'b010101;
	localparam [5:0] OP_CLI    = 6'b010110;
	localparam [5:0] OP_TRAP   = 6'b011000;
	localparam [5:0] OP_RETI   = 6'b011001;
	localparam [5:0] OP_HALT   = 6'b011010;
	localparam [5:0] OP_LDSR   = 6'b011100;
	localparam [5:0] OP_STSR   = 6'b011101;
	localparam [5:0] OP_SEI    = 6'b011110;
	localparam [5:0] OP_SAR_I  = 6'b010111;
	localparam [5:0] OP_MOVEA  = 6'b101000;
	localparam [5:0] OP_ADDI   = 6'b101001;
	localparam [5:0] OP_JR     = 6'b101010;
	localparam [5:0] OP_JAL    = 6'b101011;
	localparam [5:0] OP_ORI    = 6'b101100;
	localparam [5:0] OP_ANDI   = 6'b101101;
	localparam [5:0] OP_XORI   = 6'b101110;
	localparam [5:0] OP_MOVHI  = 6'b101111;
	localparam [5:0] OP_LD_B   = 6'b110000;
	localparam [5:0] OP_LD_H   = 6'b110001;
	localparam [5:0] OP_LD_W   = 6'b110011;
	localparam [5:0] OP_ST_B   = 6'b110100;
	localparam [5:0] OP_ST_H   = 6'b110101;
	localparam [5:0] OP_ST_W   = 6'b110111;
	localparam [5:0] OP_IN_B   = 6'b111000;
	localparam [5:0] OP_IN_H   = 6'b111001;
	localparam [5:0] OP_CAXI   = 6'b111010;
	localparam [5:0] OP_IN_W   = 6'b111011;
	localparam [5:0] OP_OUT_B  = 6'b111100;
	localparam [5:0] OP_OUT_H  = 6'b111101;
	localparam [5:0] OP_EXT    = 6'b111110;
	localparam [5:0] OP_BITSTR = 6'b011111;
	localparam [5:0] OP_OUT_W  = 6'b111111;

	localparam [5:0] SUBOP_CMPF  = 6'b000000;
	localparam [5:0] SUBOP_CVTWS = 6'b000010;
	localparam [5:0] SUBOP_CVTSW = 6'b000011;
	localparam [5:0] SUBOP_ADDF  = 6'b000100;
	localparam [5:0] SUBOP_SUBF  = 6'b000101;
	localparam [5:0] SUBOP_MULF  = 6'b000110;
	localparam [5:0] SUBOP_DIVF  = 6'b000111;
	localparam [5:0] SUBOP_XB    = 6'b001000;
	localparam [5:0] SUBOP_XH    = 6'b001001;
	localparam [5:0] SUBOP_REV   = 6'b001010;
	localparam [5:0] SUBOP_TRNCSW = 6'b001011;
	localparam [5:0] SUBOP_MPYHW = 6'b001100;
	localparam [4:0] SUBOP_SCH0BSU = 5'b00000;
	localparam [4:0] SUBOP_SCH0BSD = 5'b00001;
	localparam [4:0] SUBOP_SCH1BSU = 5'b00010;
	localparam [4:0] SUBOP_SCH1BSD = 5'b00011;
	localparam [4:0] SUBOP_ORBSU   = 5'b01000;
	localparam [4:0] SUBOP_ANDBSU  = 5'b01001;
	localparam [4:0] SUBOP_XORBSU  = 5'b01010;
	localparam [4:0] SUBOP_MOVBSU  = 5'b01011;
	localparam [4:0] SUBOP_ORNBSU  = 5'b01100;
	localparam [4:0] SUBOP_ANDNBSU = 5'b01101;
	localparam [4:0] SUBOP_XORNBSU = 5'b01110;
	localparam [4:0] SUBOP_NOTBSU  = 5'b01111;

	localparam [2:0] OP_BCOND  = 3'b100;

	localparam [3:0] MK_NOP    = 4'd0;
	localparam [3:0] MK_ALU    = 4'd1;
	localparam [3:0] MK_BRANCH = 4'd2;
	localparam [3:0] MK_MEM    = 4'd3;
	localparam [3:0] MK_LDSR   = 4'd4;
	localparam [3:0] MK_STSR   = 4'd5;
	localparam [3:0] MK_HALT   = 4'd6;
	localparam [3:0] MK_TRAP   = 4'd7;
	localparam [3:0] MK_RETI   = 4'd8;
	localparam [3:0] MK_LONG   = 4'd9;
	localparam [3:0] MK_CAXI   = 4'd10;
	localparam [3:0] MK_BITSTR = 4'd11;
	localparam [3:0] MK_ILL    = 4'd15;

	localparam [3:0] ALU_PASS_A = 4'd0;
	localparam [3:0] ALU_PASS_B = 4'd1;
	localparam [3:0] ALU_ADD    = 4'd2;
	localparam [3:0] ALU_SUB    = 4'd3;
	localparam [3:0] ALU_OR     = 4'd4;
	localparam [3:0] ALU_AND    = 4'd5;
	localparam [3:0] ALU_XOR    = 4'd6;
	localparam [3:0] ALU_NOT    = 4'd7;
	localparam [3:0] ALU_SHL    = 4'd8;
	localparam [3:0] ALU_SHR    = 4'd9;
	localparam [3:0] ALU_SAR    = 4'd10;
	localparam [3:0] ALU_SETF   = 4'd11;
	localparam [3:0] LONG_CLI   = 4'd0;
	localparam [3:0] LONG_SEI   = 4'd1;
	localparam [3:0] LONG_XB    = 4'd2;
	localparam [3:0] LONG_XH    = 4'd3;
	localparam [3:0] LONG_REV   = 4'd4;
	localparam [3:0] LONG_MPYHW = 4'd5;
	localparam [3:0] LONG_CMPF  = 4'd6;
	localparam [3:0] LONG_CVTWS = 4'd7;
	localparam [3:0] LONG_CVTSW = 4'd8;
	localparam [3:0] LONG_TRNCSW = 4'd9;
	localparam [3:0] LONG_ADDF  = 4'd10;
	localparam [3:0] LONG_SUBF  = 4'd11;
	localparam [3:0] LONG_MUL   = 4'd12;
	localparam [3:0] LONG_DIV   = 4'd13;
	localparam [3:0] LONG_MULU  = 4'd14;
	localparam [3:0] LONG_DIVU  = 4'd15;

	localparam [1:0] SA_REG1 = 2'd1;
	localparam [1:0] SA_REG2 = 2'd2;
	localparam [1:0] SA_PC   = 2'd3;

	localparam [3:0] SB_REG1   = 4'd1;
	localparam [3:0] SB_REG2   = 4'd2;
	localparam [3:0] SB_IMM5S  = 4'd3;
	localparam [3:0] SB_IMM16S = 4'd4;
	localparam [3:0] SB_IMM16Z = 4'd5;
	localparam [3:0] SB_IMM16H = 4'd6;
	localparam [3:0] SB_IMM26S = 4'd7;
	localparam [3:0] SB_IMM5Z  = 4'd8;

	localparam [5:0] UADDR_NOP    = 6'd0;
	localparam [5:0] UADDR_MOV_R  = 6'd1;
	localparam [5:0] UADDR_ADD_R  = 6'd2;
	localparam [5:0] UADDR_SUB_R  = 6'd3;
	localparam [5:0] UADDR_CMP_R  = 6'd4;
	localparam [5:0] UADDR_SHL_R  = 6'd5;
	localparam [5:0] UADDR_SHR_R  = 6'd6;
	localparam [5:0] UADDR_JMP    = 6'd7;
	localparam [5:0] UADDR_SAR_R  = 6'd8;
	localparam [5:0] UADDR_OR_R   = 6'd9;
	localparam [5:0] UADDR_AND_R  = 6'd10;
	localparam [5:0] UADDR_XOR_R  = 6'd11;
	localparam [5:0] UADDR_NOT_R  = 6'd12;
	localparam [5:0] UADDR_MOV_I  = 6'd13;
	localparam [5:0] UADDR_ADD_I  = 6'd14;
	localparam [5:0] UADDR_SETF   = 6'd15;
	localparam [5:0] UADDR_CMP_I  = 6'd16;
	localparam [5:0] UADDR_SHL_I  = 6'd17;
	localparam [5:0] UADDR_SHR_I  = 6'd18;
	localparam [5:0] UADDR_SAR_I  = 6'd19;
	localparam [5:0] UADDR_HALT   = 6'd20;
	localparam [5:0] UADDR_LDSR   = 6'd21;
	localparam [5:0] UADDR_STSR   = 6'd22;
	localparam [5:0] UADDR_BCOND  = 6'd23;
	localparam [5:0] UADDR_MOVEA  = 6'd24;
	localparam [5:0] UADDR_ADDI   = 6'd25;
	localparam [5:0] UADDR_JR     = 6'd26;
	localparam [5:0] UADDR_JAL    = 6'd27;
	localparam [5:0] UADDR_ORI    = 6'd28;
	localparam [5:0] UADDR_ANDI   = 6'd29;
	localparam [5:0] UADDR_XORI   = 6'd30;
	localparam [5:0] UADDR_MOVHI  = 6'd31;
	localparam [5:0] UADDR_MEM_LD_B  = 6'd32;
	localparam [5:0] UADDR_MEM_LD_H  = 6'd33;
	localparam [5:0] UADDR_MEM_LD_W  = 6'd34;
	localparam [5:0] UADDR_MEM_ST_B  = 6'd35;
	localparam [5:0] UADDR_MEM_ST_H  = 6'd36;
	localparam [5:0] UADDR_MEM_ST_W  = 6'd37;
	localparam [5:0] UADDR_MEM_IN_B  = 6'd38;
	localparam [5:0] UADDR_MEM_IN_H  = 6'd39;
	localparam [5:0] UADDR_MEM_IN_W  = 6'd40;
	localparam [5:0] UADDR_MEM_OUT_B = 6'd41;
	localparam [5:0] UADDR_MEM_OUT_H = 6'd42;
	localparam [5:0] UADDR_MEM_OUT_W = 6'd43;
	localparam [5:0] UADDR_TRAP   = 6'd44;
	localparam [5:0] UADDR_RETI   = 6'd45;
	localparam [5:0] UADDR_MUL    = 6'd46;
	localparam [5:0] UADDR_DIV    = 6'd47;
	localparam [5:0] UADDR_MULU   = 6'd48;
	localparam [5:0] UADDR_DIVU   = 6'd49;
	localparam [5:0] UADDR_CLI    = 6'd50;
	localparam [5:0] UADDR_SEI    = 6'd51;
	localparam [5:0] UADDR_XB     = 6'd52;
	localparam [5:0] UADDR_XH     = 6'd53;
	localparam [5:0] UADDR_REV    = 6'd54;
	localparam [5:0] UADDR_MPYHW  = 6'd55;
	localparam [5:0] UADDR_CAXI   = 6'd56;
	localparam [5:0] UADDR_BITSTR = 6'd57;
	localparam [5:0] UADDR_CMPF   = 6'd58;
	localparam [5:0] UADDR_CVTWS  = 6'd59;
	localparam [5:0] UADDR_CVTSW  = 6'd60;
	localparam [5:0] UADDR_FPU    = 6'd61;
	localparam [5:0] UADDR_ILL    = 6'd62;

	localparam [2:0] BS_OP_OR    = 3'd0;
	localparam [2:0] BS_OP_AND   = 3'd1;
	localparam [2:0] BS_OP_XOR   = 3'd2;
	localparam [2:0] BS_OP_MOV   = 3'd3;
	localparam [2:0] BS_OP_ORN   = 3'd4;
	localparam [2:0] BS_OP_ANDN  = 3'd5;
	localparam [2:0] BS_OP_XORN  = 3'd6;
	localparam [2:0] BS_OP_NOT   = 3'd7;
	localparam [2:0] BS_TYPE1    = 3'd0;
	localparam [2:0] BS_TYPE2    = 3'd1;
	localparam [2:0] BS_TYPE3    = 3'd2;
	localparam [2:0] BS_TYPE4    = 3'd3;
	localparam [2:0] BS_TYPE5    = 3'd4;
	localparam [2:0] BS_TYPE6    = 3'd5;
	localparam [2:0] BS_TYPE7    = 3'd6;
	localparam [1:0] BSWAIT_START  = 2'd0;
	localparam [1:0] BSWAIT_RESUME = 2'd1;
	localparam [1:0] BSWAIT_RETIRE = 2'd2;
	localparam [1:0] ABORT_ENGINE_LONG   = 2'd1;
	localparam [1:0] ABORT_ENGINE_BITSTR = 2'd2;

	localparam [2:0] TIMING_LDSR      = 3'd0;
	localparam [2:0] TIMING_STSR      = 3'd1;
	localparam [2:0] TIMING_CAXI      = 3'd2;
	localparam [2:0] TIMING_MEM_LOAD  = 3'd3;
	localparam [2:0] TIMING_MEM_STORE = 3'd4;
	localparam [2:0] TIMING_TRAP      = 3'd5;
	localparam [2:0] TIMING_RETI      = 3'd6;

	// WB producer format: {r26-r30 group flag, single-reg valid, reg[4:0]}.
	localparam [6:0] WB_PRODUCER_BS_GROUP = 7'b1_0_00000;

	localparam [2:0] RETIRE_CLASS_NONE  = 3'd0;
	localparam [2:0] RETIRE_CLASS_OTHER = 3'd1;
	localparam [2:0] RETIRE_CLASS_LOAD  = 3'd2;
	localparam [2:0] RETIRE_CLASS_STORE = 3'd3;
	localparam [2:0] RETIRE_CLASS_LONG  = 3'd4;

	localparam [1:0] ASYNC_EXC_NONE = 2'd0;
	localparam [1:0] ASYNC_EXC_ADDR = 2'd1;
	localparam [1:0] ASYNC_EXC_NMI  = 2'd2;
	localparam [1:0] ASYNC_EXC_IRQ  = 2'd3;
	wire cpu_transient_reset_w = reset_i || savestate_restore_i;

	reg [5:0]  state_q;
	// Remember a retire boundary until the next CE can enter snapshot hold.
	reg        savestate_boundary_pending_q;
	reg [31:0] pc_q;
	reg [31:0] psw_q;
	// One-cycle GPR commit records. One owner applies up to five writes per CE.
	reg [4:0]  gpr_commit_we_v;
	reg [4:0]  gpr_commit_addr0_v;
	reg [4:0]  gpr_commit_addr1_v;
	reg [4:0]  gpr_commit_addr2_v;
	reg [4:0]  gpr_commit_addr3_v;
	reg [4:0]  gpr_commit_addr4_v;
	reg [31:0] gpr_commit_data0_v;
	reg [31:0] gpr_commit_data1_v;
	reg [31:0] gpr_commit_data2_v;
	reg [31:0] gpr_commit_data3_v;
	reg [31:0] gpr_commit_data4_v;
	reg        rf_commit_valid_q;
	reg [4:0]  rf_commit_we_q;
	reg [4:0]  rf_commit_addr0_q;
	reg [4:0]  rf_commit_addr1_q;
	reg [4:0]  rf_commit_addr2_q;
	reg [4:0]  rf_commit_addr3_q;
	reg [4:0]  rf_commit_addr4_q;
	reg [31:0] rf_commit_data0_q;
	reg [31:0] rf_commit_data1_q;
	reg [31:0] rf_commit_data2_q;
	reg [31:0] rf_commit_data3_q;
	reg [31:0] rf_commit_data4_q;
	// A shadow of r26-r30 supplies bit-string and CAXI operands in one cycle.
	reg [4:0]  gpr_r26_shadow_q;
	reg [4:0]  gpr_r27_shadow_q;
	reg [31:0] gpr_r28_shadow_q;
	reg [31:0] gpr_r29_shadow_q;
	reg [31:0] gpr_r30_shadow_q;
	reg        psw_commit_we_v;
	reg [31:0] psw_commit_data_v;
	// One commit site applies system-register, PSW, and exception updates.
	reg        sysreg_write_we_v;
	reg [4:0]  sysreg_write_addr_v;
	reg [31:0] sysreg_write_data_v;
	reg        sysreg_exception_we_v;
	reg        sysreg_exception_save_ei_v;
	reg        sysreg_exception_save_fe_v;
	reg [31:0] sysreg_exception_saved_pc_v;
	reg [31:0] sysreg_exception_saved_psw_v;
	reg [31:0] sysreg_exception_ecr_v;
	reg        sysreg_exception_psw_we_v;
	reg [31:0] sysreg_exception_psw_v;
	reg [31:0] eipc_q;
	reg [31:0] eipsw_q;
	reg [31:0] fepc_q;
	reg [31:0] fepsw_q;
	reg [31:0] ecr_q;
	reg [31:0] adtre_q;
	reg [31:0] sr29_q;
	reg [31:0] sr31_q;
	reg        siz16b_q;
	reg        siz16b_sample_pending_q;

	// Silicon unknown: SIZ16B latch timing is undocumented. Sample it on the first
	// enabled edge after reset.
	always @(posedge clk_i or posedge reset_i) begin
		if (reset_i) begin
			siz16b_q <= 1'b1;
			siz16b_sample_pending_q <= 1'b1;
		end else if (ce_i && siz16b_sample_pending_q) begin
			siz16b_q <= siz16b_i;
			siz16b_sample_pending_q <= 1'b0;
		end
	end

	reg        halted_q;
	reg        illegal_q;
	reg        cache_enable_q;
	reg        cache_enable_pending_q;
	reg        cache_control_write_we_v;
	reg        cache_control_enable_v;
	reg        cache_control_pending_v;
	reg        ic_data_write_valid_q;
	reg [6:0]  ic_data_write_addr_q;
	reg [63:0] ic_data_write_data_q;
	reg        ic_tag_write_valid_q;
	reg [6:0]  ic_tag_write_addr_q;
	reg [31:0] ic_tag_write_data_q;

	reg  [6:0] init_index_q;
	reg  [6:0] clear_index_q;
	reg  [6:0] clear_last_q;

	reg [63:0] cur_line_q;
	reg [31:0] cur_base_q;
	reg        cur_line_valid_q;
	// Tag bits 23:22 independently validate the upper and lower four-byte
	// subblocks. Keep the same information beside each resident line.
	reg [1:0]  cur_line_subvalid_q;
	// The following cache-line entry is always current base plus eight.
	reg [63:0] next_line_q;
	reg [31:0] next_base_q;
	reg        next_line_valid_q;
	reg [1:0]  next_line_subvalid_q;

	reg [31:0] fill_base_q;
	reg [6:0]  fill_index_q;
	reg [63:0] fill_line_q;
	reg [1:0]  fill_half_q;
	reg        fill_target_next_q;
	reg        fill_store_q;
	reg        fill_branch_fetch_q;
	reg [31:0] ifetch_iw_q;

	wire        active_q;
	wire [31:0] active_addr_q;
	wire        active_fetch_q;
	wire        active_write_q;
	wire        active_posted_q;
	wire [1:0]  active_size_q;
	// Read hierarchically by test harnesses even though unused in synthesis.
	wire        active_phase_q;
	wire [31:0] active_wdata_q;
	wire        bus_complete_w;
	wire [31:0] bus_read_data_w;
	wire        bus_posted_ready_w;
	wire        bus_launch_accept_w;
	wire        store_pending_w;
	wire [31:1] bus_a_w;
	wire [3:0]  bus_be_w;
	wire [1:0]  bus_st_w;
	reg         bus_launch_v;
	reg  [31:0] bus_launch_addr_v;
	reg         bus_launch_fetch_v;
	reg         bus_launch_fetch_branch_v;
	reg         bus_launch_write_v;
	reg         bus_launch_posted_v;
	reg         bus_launch_addr_error_v;
	reg  [1:0]  bus_launch_size_v;
	reg  [31:0] bus_launch_wdata_v;

	reg [31:0] exec_pc_q;
	reg [31:0] exec_iw_q;
	reg [5:0]  exec_uop_q;
	reg [31:0] exec_result_q;
	reg        mem_write_q;
	reg        mem_io_q;
	reg        mem_signext_q;
	reg [1:0]  mem_size_q;
	reg [31:0] mem_addr_q;
	reg        mem_addr_error_q;
	reg [31:0] mem_wdata_q;
	reg [4:0]  mem_dest_q;
	reg [15:0] exc_code_q;
	reg [31:0] exc_restore_pc_q;
	reg [1:0]  fatal_index_q;
	reg [31:0] dbg_reg_data_q;
	reg [3:0]  long_kind_q;
	reg [5:0]  long_cycles_q;
	wire        int_engine_busy_w;
	wire        int_engine_done_w;
	wire [31:0] int_engine_result_hi_w;
	wire [31:0] int_engine_result_lo_w;
	wire        int_engine_result_zero_w;
	wire        int_engine_result_sign_w;
	wire        int_engine_result_overflow_w;
	wire        fp_engine_busy_w;
	wire        fp_engine_done_w;
	wire [5:0]  fp_engine_step_w;
	wire [31:0] fp_engine_result_w;
	wire        fp_engine_result_we_w;
	wire [9:0]  fp_engine_psw_mask_w;
	wire [9:0]  fp_engine_psw_data_w;
	wire        fp_engine_exc_valid_w;
	wire [15:0] fp_engine_exc_code_w;
	reg [31:0] long_final_hi_q;
	reg [31:0] long_final_lo_q;
	reg [31:0] long_final_psw_q;
	reg        long_final_hi_we_q;
	reg        long_final_lo_we_q;
	reg        long_final_psw_we_q;
	reg [31:0] long_fpu_result_q;
	reg [31:0] long_fpu_psw_q;
	reg [15:0] long_fpu_exc_code_q;
	reg        long_fpu_result_we_q;
	reg        long_fpu_psw_we_q;
	reg        long_fpu_exc_valid_q;
	reg        chcw_dump_q;
	reg        chcw_data_phase_q;
	reg [6:0]  chcw_index_q;
	reg        chcw_word_q;
	reg [31:0] chcw_sa_q;
	reg [63:0] chcw_line_q;
	reg [31:0] chcw_tag_q;
	reg        caxi_active_q;
	reg [31:0] caxi_addr_q;
	reg        caxi_addr_error_q;
	reg [31:0] caxi_loaded_q;
	reg        caxi_match_q;
	reg [31:0] caxi_store_data_q;
	reg [31:0] caxi_final_reg_q;
	reg [31:0] caxi_final_psw_q;
	reg        caxi_final_reg_we_q;
	reg [2:0]  bs_op_q;
	reg [31:0] bs_src_addr_q;
	reg [31:0] bs_dst_addr_q;
	reg [31:0] bs_len_q;
	reg [4:0]  bs_src_ofs_q;
	reg [4:0]  bs_dst_ofs_q;
	reg        bs_need_src_hi_q;
	reg        bs_src_second_q;
	reg [31:0] bs_src_lo_q;
	reg [31:0] bs_src_hi_q;
	reg [31:0] bs_src_aligned_q;
	reg [31:0] bs_write_mask_q;
	reg [31:0] bs_write_word_q;
	reg [2:0]  bs_type_q;
	reg        bs_search_q;
	reg        bs_down_q;
	reg        bs_search_bit_q;
	reg        bs_first_partial_q;
	reg        bs_last_partial_q;
	reg [31:0] bs_total_words_q;
	reg [31:0] bs_word_index_q;
	reg        bs_seq_active_q;
	reg [31:0] bs_seq_pc_q;
	reg [5:0]  bs_cycles_q;
	reg [1:0]  bs_wait_action_q;
	reg [6:0]  bs_search_result_q;
	reg [2:0]  timing_kind_q;
	reg [5:0]  timing_cycles_q;
	reg [4:0]  timing_regid_q;
	reg [31:0] timing_value_q;
	reg [4:0]  timing_dest_q;
	reg [31:0] reti_restore_pc_q;
	reg [31:0] reti_restore_psw_q;
	reg [1:0]  front_cycles_q;
	// DF tracks one register. WB tracks one register or the r26-r30 group.
	reg [5:0]  hazard_df_producer_q;
	reg [6:0]  hazard_wb_producer_q;
	reg        hazard_df_flags_q;
	reg        hazard_wb_flags_q;
	reg        irq_defer_q;
	reg        cache_irq_pending_q;
	reg [3:0]  cache_irq_level_q;
	reg        nmi_pending_q;
	reg        nmi_prev_q;
	reg        fetch_defer_q;
	reg [1:0]  write_streak_q;
	reg [2:0]  prev_retire_class_q;
	reg [1:0]  prev_retire_size_q;
	reg        prev_retire_io_q;
	reg        store_load_hold_q;
	// One plain LD may overlap the end of a nonconflicting integer long operation.
	reg        long_load_overlap_q;
	reg        long_load_data_valid_q;
	reg [31:0] long_load_data_q;
	reg [31:0] long_load_pc_q;
	reg [31:0] long_load_seq_pc_q;
	reg [31:0] long_load_iw_q;
	// Posted writes (active or queued) still own the bus after retire.
	wire       posted_write_busy_w = (active_q && active_posted_q) || store_pending_w;
	// Operands and metadata latched on phi1 to keep GPR outputs off the CE-side path.
	reg [4:0]  exec_reg2_q;
	reg [4:0]  exec_reg1_q;
	reg [4:0]  exec_trap_vec_q;
	reg [4:0]  exec_bs_subop_q;
	reg [5:0]  exec_ext_subop_q;
	reg [31:0] exec_reg1_val_q;
	reg [31:0] exec_reg2_val_q;
	reg [31:0] exec_seq_pc_q;
	reg [15:0] exec_trace_insn_q;
	reg [31:0] exec_bcond_target_q;
	reg        exec_condition_q;
	reg [31:0] exec_eff_addr_q;
	reg [31:0] exec_imm_q;
	reg [31:0] exec_sys_read_q;
	reg [5:0]  exec_issue_cycles_q;
	reg [5:0]  exec_df_producer_q;
	reg [6:0]  exec_wb_producer_q;
	reg        exec_df_flags_q;
	reg        exec_wb_flags_q;
	reg [31:0] exec_bs_r30_q;
	reg [31:0] exec_bs_r29_q;
	reg [31:0] exec_bs_r28_q;
	reg [4:0]  exec_bs_r27_q;
	reg [4:0]  exec_bs_r26_q;
	reg [31:0] exec_bs_words_total_q;
	reg [31:0] exec_bs_search_words_total_q;
	reg        exec_bs_search_first_partial_q;
	reg        exec_bs_search_last_partial_q;
	reg [2:0]  exec_bs_type_q;
	reg        exec_bs_need_src_hi_q;
	reg [5:0]  exec_bs_start_cycles_q;
	reg [5:0]  exec_bs_zero_cycles_q;
	reg [31:0] bs_search_count_q;
	reg [15:0] rf_issue_half_v;
	wire [4:0] rf_read_addr_a_w = rf_issue_half_v[4:0];
	wire [4:0] rf_read_addr_b_w = halted_q ? dbg_reg_addr_i : rf_issue_half_v[9:5];
`ifndef SYNTHESIS
	// Exclude simulation trace state even when Quartus omits SYNTHESIS.
	// synthesis translate_off
	reg [5:0]  sim_rf_launch_state_q;
	reg [15:0] sim_rf_launch_half_q;
	reg        sim_rf_launch_ce_q;
	reg        sim_rf_launch_phi1_q;

	always @(posedge clk_i or posedge reset_i) begin
		if (reset_i) begin
			sim_rf_launch_state_q <= 6'd0;
			sim_rf_launch_half_q <= 16'd0;
			sim_rf_launch_ce_q <= 1'b0;
			sim_rf_launch_phi1_q <= 1'b0;
		end else begin
			sim_rf_launch_state_q <= state_q;
			sim_rf_launch_half_q <= rf_issue_half_v;
			sim_rf_launch_ce_q <= ce_i;
			sim_rf_launch_phi1_q <= phi1_i;
		end
	end
	// synthesis translate_on
`endif
	wire [31:0] rf_read_data_a_w;
	wire [31:0] rf_read_data_b_w;
	wire        rf_commit_ready_w;
	wire        rf_commit_accept_w;
	wire [2:0]  rf_pending_count_w;
	wire        rf_commit_block_w = rf_commit_valid_q && !rf_commit_ready_w;

	wire [5:0]  exec_ext_subop_raw_w = exec_iw_q[15:10];
	wire [8:0]  exec_disp9_raw_w     = exec_iw_q[24:16];
	wire [31:0] exec_reg1_val_raw_w  = rf_read_data_a_w;
	wire [31:0] exec_reg2_val_raw_w  = rf_read_data_b_w;
	// Capture the selected immediate on phi1 to shorten the CE-side ALU path.
	wire [31:0] exec_imm_raw_w = issue_immediate_fn(exec_uop_q, exec_iw_q);
	// Register condition and timing metadata on phi1.
	wire        exec_condition_raw_w = issue_condition_fn(exec_uop_q, exec_iw_q, psw_q);
	wire [5:0]  exec_issue_cycles_raw_w = issue_cycles_fn(
		exec_uop_q, exec_iw_q, siz16b_q, prev_retire_class_q,
		prev_retire_size_q, prev_retire_io_q, write_streak_q);
	wire        exec_bs_continuation_raw_w =
		bs_seq_active_q &&
		(exec_pc_q == bs_seq_pc_q) &&
		(exec_iw_q[31:26] == OP_BITSTR);
	wire [31:0] exec_bs_resume_r29_raw_w =
		(exec_iw_q[20:19] == 2'b00) ? bs_search_count_q : bs_dst_addr_q;
	// Update the r26-r30 shadow with register-file commit and forward same-edge data.
	reg [4:0] rf_commit_r30_sel_v;
	reg [4:0] rf_commit_r29_sel_v;
	reg [4:0] rf_commit_r28_sel_v;
	reg [4:0] rf_commit_r27_sel_v;
	reg [4:0] rf_commit_r26_sel_v;
	always @* begin
		rf_commit_r30_sel_v = 5'b00000;
		rf_commit_r29_sel_v = 5'b00000;
		rf_commit_r28_sel_v = 5'b00000;
		rf_commit_r27_sel_v = 5'b00000;
		rf_commit_r26_sel_v = 5'b00000;
		if (rf_commit_valid_q) begin
			rf_commit_r30_sel_v = {
				rf_commit_we_q[4] && (rf_commit_addr4_q == 5'd30),
				rf_commit_we_q[3] && (rf_commit_addr3_q == 5'd30),
				rf_commit_we_q[2] && (rf_commit_addr2_q == 5'd30),
				rf_commit_we_q[1] && (rf_commit_addr1_q == 5'd30),
				rf_commit_we_q[0] && (rf_commit_addr0_q == 5'd30)};
			rf_commit_r29_sel_v = {
				rf_commit_we_q[4] && (rf_commit_addr4_q == 5'd29),
				rf_commit_we_q[3] && (rf_commit_addr3_q == 5'd29),
				rf_commit_we_q[2] && (rf_commit_addr2_q == 5'd29),
				rf_commit_we_q[1] && (rf_commit_addr1_q == 5'd29),
				rf_commit_we_q[0] && (rf_commit_addr0_q == 5'd29)};
			rf_commit_r28_sel_v = {
				rf_commit_we_q[4] && (rf_commit_addr4_q == 5'd28),
				rf_commit_we_q[3] && (rf_commit_addr3_q == 5'd28),
				rf_commit_we_q[2] && (rf_commit_addr2_q == 5'd28),
				rf_commit_we_q[1] && (rf_commit_addr1_q == 5'd28),
				rf_commit_we_q[0] && (rf_commit_addr0_q == 5'd28)};
			rf_commit_r27_sel_v = {
				rf_commit_we_q[4] && (rf_commit_addr4_q == 5'd27),
				rf_commit_we_q[3] && (rf_commit_addr3_q == 5'd27),
				rf_commit_we_q[2] && (rf_commit_addr2_q == 5'd27),
				rf_commit_we_q[1] && (rf_commit_addr1_q == 5'd27),
				rf_commit_we_q[0] && (rf_commit_addr0_q == 5'd27)};
			rf_commit_r26_sel_v = {
				rf_commit_we_q[4] && (rf_commit_addr4_q == 5'd26),
				rf_commit_we_q[3] && (rf_commit_addr3_q == 5'd26),
				rf_commit_we_q[2] && (rf_commit_addr2_q == 5'd26),
				rf_commit_we_q[1] && (rf_commit_addr1_q == 5'd26),
				rf_commit_we_q[0] && (rf_commit_addr0_q == 5'd26)};
		end
	end
	wire [4:0] rf_commit_r30_sel_w = rf_commit_r30_sel_v;
	wire [4:0] rf_commit_r29_sel_w = rf_commit_r29_sel_v;
	wire [4:0] rf_commit_r28_sel_w = rf_commit_r28_sel_v;
	wire [4:0] rf_commit_r27_sel_w = rf_commit_r27_sel_v;
	wire [4:0] rf_commit_r26_sel_w = rf_commit_r26_sel_v;
	// Merge duplicate GPR writes, then select data with a parallel mask network.
	wire [31:0] rf_commit_r30_forward_w =
		({32{rf_commit_r30_sel_w[0]}} & rf_commit_data0_q) |
		({32{rf_commit_r30_sel_w[1]}} & rf_commit_data1_q) |
		({32{rf_commit_r30_sel_w[2]}} & rf_commit_data2_q) |
		({32{rf_commit_r30_sel_w[3]}} & rf_commit_data3_q) |
		({32{rf_commit_r30_sel_w[4]}} & rf_commit_data4_q);
	wire [31:0] rf_commit_r29_forward_w =
		({32{rf_commit_r29_sel_w[0]}} & rf_commit_data0_q) |
		({32{rf_commit_r29_sel_w[1]}} & rf_commit_data1_q) |
		({32{rf_commit_r29_sel_w[2]}} & rf_commit_data2_q) |
		({32{rf_commit_r29_sel_w[3]}} & rf_commit_data3_q) |
		({32{rf_commit_r29_sel_w[4]}} & rf_commit_data4_q);
	wire [31:0] rf_commit_r28_forward_w =
		({32{rf_commit_r28_sel_w[0]}} & rf_commit_data0_q) |
		({32{rf_commit_r28_sel_w[1]}} & rf_commit_data1_q) |
		({32{rf_commit_r28_sel_w[2]}} & rf_commit_data2_q) |
		({32{rf_commit_r28_sel_w[3]}} & rf_commit_data3_q) |
		({32{rf_commit_r28_sel_w[4]}} & rf_commit_data4_q);
	wire [4:0] rf_commit_r27_forward_w =
		({5{rf_commit_r27_sel_w[0]}} & rf_commit_data0_q[4:0]) |
		({5{rf_commit_r27_sel_w[1]}} & rf_commit_data1_q[4:0]) |
		({5{rf_commit_r27_sel_w[2]}} & rf_commit_data2_q[4:0]) |
		({5{rf_commit_r27_sel_w[3]}} & rf_commit_data3_q[4:0]) |
		({5{rf_commit_r27_sel_w[4]}} & rf_commit_data4_q[4:0]);
	wire [4:0] rf_commit_r26_forward_w =
		({5{rf_commit_r26_sel_w[0]}} & rf_commit_data0_q[4:0]) |
		({5{rf_commit_r26_sel_w[1]}} & rf_commit_data1_q[4:0]) |
		({5{rf_commit_r26_sel_w[2]}} & rf_commit_data2_q[4:0]) |
		({5{rf_commit_r26_sel_w[3]}} & rf_commit_data3_q[4:0]) |
		({5{rf_commit_r26_sel_w[4]}} & rf_commit_data4_q[4:0]);
	wire [31:0] gpr_r30_visible_w = (|rf_commit_r30_sel_w) ? rf_commit_r30_forward_w : gpr_r30_shadow_q;
	wire [31:0] gpr_r29_visible_w = (|rf_commit_r29_sel_w) ? rf_commit_r29_forward_w : gpr_r29_shadow_q;
	wire [31:0] gpr_r28_visible_w = (|rf_commit_r28_sel_w) ? rf_commit_r28_forward_w : gpr_r28_shadow_q;
	wire [4:0]  gpr_r27_visible_w = (|rf_commit_r27_sel_w) ? rf_commit_r27_forward_w : gpr_r27_shadow_q;
	wire [4:0]  gpr_r26_visible_w = (|rf_commit_r26_sel_w) ? rf_commit_r26_forward_w : gpr_r26_shadow_q;
	wire [31:0] exec_bs_r30_raw_w =
		exec_bs_continuation_raw_w ? bs_src_addr_q : gpr_r30_visible_w;
	wire [31:0] exec_bs_r29_raw_w =
		exec_bs_continuation_raw_w ? exec_bs_resume_r29_raw_w : gpr_r29_visible_w;
	wire [31:0] exec_bs_r28_raw_w =
		exec_bs_continuation_raw_w ? bs_len_q : gpr_r28_visible_w;
	wire [4:0]  exec_bs_r27_raw_w =
		exec_bs_continuation_raw_w ? bs_src_ofs_q : gpr_r27_visible_w;
	wire [4:0]  exec_bs_r26_raw_w =
		exec_bs_continuation_raw_w ? bs_dst_ofs_q : gpr_r26_visible_w;
	wire [31:0] exec_bs_words_total_raw_w =
		bs_word_count_fn(exec_bs_r28_raw_w, exec_bs_r27_raw_w);
	wire [31:0] exec_bs_search_words_total_raw_w =
		bs_search_words_total_fn(exec_bs_r28_raw_w, exec_bs_r27_raw_w, exec_iw_q[16]);
	wire        exec_bs_search_first_partial_raw_w =
		bs_search_first_partial_fn(exec_bs_r27_raw_w, exec_iw_q[16]);
	wire        exec_bs_search_last_partial_raw_w =
		bs_search_last_partial_fn(exec_bs_r28_raw_w, exec_bs_r27_raw_w, exec_iw_q[16]);
	wire [2:0]  exec_bs_type_raw_w =
		bs_arith_type_fn(exec_bs_r28_raw_w, exec_bs_r30_raw_w, exec_bs_r29_raw_w, exec_bs_r27_raw_w, exec_bs_r26_raw_w);
	wire        exec_bs_need_src_hi_raw_w =
		(({1'b0, exec_bs_r27_raw_w} + bs_step_fn(exec_bs_r28_raw_w, exec_bs_r26_raw_w)) > 6'd32);
	wire [5:0]  exec_bs_search_start_cycles_raw_w =
		bs_search_start_cycles_fn(exec_bs_search_words_total_raw_w, exec_bs_search_first_partial_raw_w, exec_iw_q[16]);
	wire [5:0]  exec_bs_search_zero_cycles_raw_w =
		bs_search_zero_cycles_fn(exec_iw_q[16]);
	wire [5:0]  exec_bs_arith_start_cycles_raw_w =
		bs_arith_start_cycles_fn(exec_bs_type_raw_w, siz16b_q);
	wire [5:0]  exec_bs_arith_zero_cycles_raw_w =
		bs_arith_zero_cycles_fn(exec_bs_type_raw_w, siz16b_q);
	wire [31:0] bcond_target_raw_w   = exec_pc_q + sx9_fn(exec_disp9_raw_w);
	wire [31:0] ucode_rom_word_w;
	reg         phi1_seen_q;
	// Register the microcode ROM address at issue and each following step.
	wire [3:0]  ucode_kind_w      = ucode_rom_word_w[3:0];
	wire [3:0]  ucode_alu_op_w    = ucode_rom_word_w[7:4];
	wire [1:0]  ucode_srca_w      = ucode_rom_word_w[9:8];
	wire [3:0]  ucode_srcb_w      = ucode_rom_word_w[13:10];
	wire        ucode_write_gpr_w = ucode_rom_word_w[14];
	wire        ucode_write_psw_w = ucode_rom_word_w[15];
	wire        ucode_write_link_w = ucode_rom_word_w[16];
	wire        ucode_pc_from_result_w = ucode_rom_word_w[17];
	wire        ucode_pc_from_bcond_w  = ucode_rom_word_w[18];
	// Silicon unknown: a taken Bcond to fall-through is unmeasured. Charge the
	// normal three-cycle taken cost.
	wire        ucode_control_redirect_w =
		ucode_pc_from_result_w || (ucode_pc_from_bcond_w && exec_condition_q);
	wire        ucode_mem_write_w = ucode_rom_word_w[19];
	wire        ucode_mem_io_w    = ucode_rom_word_w[20];
	wire [1:0]  ucode_mem_size_w  = ucode_rom_word_w[22:21];
	wire        ucode_mem_signext_w = ucode_rom_word_w[23];
	wire        ucode_end_w       = ucode_rom_word_w[24];
	wire [5:0]  ucode_next_w      = ucode_rom_word_w[30:25];
	wire        ucode_halt_w      = ucode_rom_word_w[31];
	// Simple integer operations share one operand mux and 33-bit adder.
	wire [31:0] exec_src_a_w =
		(ucode_srca_w == SA_REG1) ? exec_reg1_val_q :
		(ucode_srca_w == SA_REG2) ? exec_reg2_val_q :
		(ucode_srca_w == SA_PC)   ? exec_pc_q : 32'd0;
	wire        exec_src_b_imm_w =
		(ucode_srcb_w == SB_IMM5S)  ||
		(ucode_srcb_w == SB_IMM16S) ||
		(ucode_srcb_w == SB_IMM16Z) ||
		(ucode_srcb_w == SB_IMM16H) ||
		(ucode_srcb_w == SB_IMM26S) ||
		(ucode_srcb_w == SB_IMM5Z);
	wire [31:0] exec_src_b_w =
		(ucode_srcb_w == SB_REG1) ? exec_reg1_val_q :
		(ucode_srcb_w == SB_REG2) ? exec_reg2_val_q :
		exec_src_b_imm_w          ? exec_imm_q : 32'd0;
	wire [33:0] exec_addsub_w = alu_addsub_fn(
		exec_src_a_w, exec_src_b_w, (ucode_alu_op_w == ALU_SUB));
	// One five-stage shifter handles right shifts; bit reversal handles SHL.
	wire [32:0] exec_shift_w = barrel_shift_fn(
		exec_src_a_w,
		exec_src_b_w[4:0],
		(ucode_alu_op_w == ALU_SHL),
		(ucode_alu_op_w == ALU_SAR));
	reg [31:0] exec_alu_result_v;
	reg [31:0] exec_alu_psw_v;
	wire [31:0] exec_alu_result_w = exec_alu_result_v;
	wire [31:0] exec_alu_psw_w = exec_alu_psw_v;

	// Simple execute feeds registered commits. Logic keeps CY; math and shifts
	// update Z, S, OV, and CY.
	always @* begin
		exec_alu_result_v = 32'd0;
		exec_alu_psw_v = psw_q;
		case (ucode_alu_op_w)
			ALU_PASS_A: exec_alu_result_v = exec_src_a_w;
			ALU_PASS_B: exec_alu_result_v = exec_src_b_w;

			ALU_ADD,
			ALU_SUB: begin
				exec_alu_result_v = exec_addsub_w[31:0];
				if (ucode_write_psw_w) begin
					exec_alu_psw_v[0] = (exec_addsub_w[31:0] == 32'd0);
					exec_alu_psw_v[1] = exec_addsub_w[31];
					exec_alu_psw_v[2] = exec_addsub_w[33];
					exec_alu_psw_v[3] = exec_addsub_w[32];
				end
			end

			ALU_OR: begin
				exec_alu_result_v = exec_src_a_w | exec_src_b_w;
				if (ucode_write_psw_w) begin
					exec_alu_psw_v[0] = (exec_alu_result_v == 32'd0);
					exec_alu_psw_v[1] = exec_alu_result_v[31];
					exec_alu_psw_v[2] = 1'b0;
				end
			end

			ALU_AND: begin
				exec_alu_result_v = exec_src_a_w & exec_src_b_w;
				if (ucode_write_psw_w) begin
					exec_alu_psw_v[0] = (exec_alu_result_v == 32'd0);
					exec_alu_psw_v[1] = exec_alu_result_v[31];
					exec_alu_psw_v[2] = 1'b0;
				end
			end

			ALU_XOR: begin
				exec_alu_result_v = exec_src_a_w ^ exec_src_b_w;
				if (ucode_write_psw_w) begin
					exec_alu_psw_v[0] = (exec_alu_result_v == 32'd0);
					exec_alu_psw_v[1] = exec_alu_result_v[31];
					exec_alu_psw_v[2] = 1'b0;
				end
			end

			ALU_NOT: begin
				exec_alu_result_v = ~exec_src_a_w;
				if (ucode_write_psw_w) begin
					exec_alu_psw_v[0] = (exec_alu_result_v == 32'd0);
					exec_alu_psw_v[1] = exec_alu_result_v[31];
					exec_alu_psw_v[2] = 1'b0;
				end
			end

			ALU_SHL,
			ALU_SHR,
			ALU_SAR: begin
				exec_alu_result_v = exec_shift_w[31:0];
				if (ucode_write_psw_w) begin
					exec_alu_psw_v[0] = (exec_shift_w[31:0] == 32'd0);
					exec_alu_psw_v[1] = exec_shift_w[31];
					exec_alu_psw_v[2] = 1'b0;
					exec_alu_psw_v[3] = exec_shift_w[32];
				end
			end

			ALU_SETF: exec_alu_result_v = {31'd0, exec_condition_q};

			default: begin
			end
		endcase
	end
	// Align one registered base-plus-displacement result by access size.
	wire [31:0] exec_mem_addr_w = align_addr_fn(exec_eff_addr_q, ucode_mem_size_w);

	wire [31:0] curr_lookup_base_w = {pc_q[31:3], 3'b000};
	wire [6:0]  curr_lookup_index_w = pc_q[9:3];

	wire [6:0]  next_lookup_index_w = next_base_q[9:3];
	// Instruction cache use requires both CHCW.ICE and the ICHEEN pin.
	wire        cache_active_w = cache_enable_q && icheen_i;
	wire        cache_active_or_pending_w =
		(cache_enable_q || cache_enable_pending_q) && icheen_i;
	wire        curr_lookup_access_w = (state_q == STATE_LOOKUP_CUR_REQ) || (state_q == STATE_LOOKUP_CUR_WAIT);
	wire        next_lookup_access_w = (state_q == STATE_LOOKUP_NEXT_REQ) || (state_q == STATE_LOOKUP_NEXT_WAIT);
	wire [31:0] prefetch_lookup_base_w = cur_base_q + 32'd8;
	wire [6:0]  prefetch_lookup_index_w = prefetch_lookup_base_w[9:3];
	wire        prefetch_lookup_access_w =
		cache_active_w &&
		cur_line_valid_q &&
		!next_line_valid_q &&
		((state_q == STATE_FRONT_WAIT) ||
		 (state_q == STATE_UCODE_WAIT) ||
		 (state_q == STATE_EXEC));

	wire [15:0] curr_lookup_first_half_w =
		halfword_from_line_fn(ic_data_q_w, pc_q[2:1]);
	wire        curr_lookup_instr32_w =
		instr_needs_second_half_fn(curr_lookup_first_half_w);
	wire        curr_lookup_subvalid_w =
		pc_q[2] ?
			ic_tag_q_w[23] :
			(ic_tag_q_w[22] &&
			 (!((pc_q[2:1] == 2'd1) && curr_lookup_instr32_w) || ic_tag_q_w[23]));
	wire        curr_lookup_hit_w =
		cache_active_w && curr_lookup_subvalid_w &&
		(ic_tag_q_w[21:0] == pc_q[31:10]);
	// Cross-line instructions always consume the lower half of the next line.
	wire        next_lookup_hit_w =
		cache_active_w && ic_tag_q_w[22] &&
		(ic_tag_q_w[21:0] == next_base_q[31:10]);
	wire        prefetch_lookup_hit_w =
		cache_active_w &&
		(|ic_tag_q_w[23:22]) &&
		(ic_tag_q_w[21:0] == prefetch_lookup_base_w[31:10]);

	wire [63:0] fill_merged_line_w = merge_fill_halfword_fn(
		fill_line_q, fill_half_q, bus_read_data_w[15:0]);
	wire        fill_last_half_w = (fill_half_q == 2'd3);
	wire [31:0] final_fill_tagword_w = {8'd0, 2'b11, fill_base_q[31:10]};
	wire [31:0] line_window_issue_base_w = {exec_seq_pc_q[31:3], 3'b000};
	wire        line_window_issue_from_cur_w =
		cur_line_valid_q && (cur_base_q == line_window_issue_base_w);
	wire        line_window_issue_from_next_w =
		next_line_valid_q && (next_base_q == line_window_issue_base_w);
	wire [63:0] line_window_issue_line_w =
		line_window_issue_from_cur_w ? cur_line_q : next_line_q;
	wire [15:0] line_window_issue_half_w =
		halfword_from_line_fn(line_window_issue_line_w, exec_seq_pc_q[2:1]);
	wire [1:0] line_window_issue_subvalid_w =
		line_window_issue_from_cur_w ? cur_line_subvalid_q : next_line_subvalid_q;
	wire        line_window_issue_cross_w =
		instr_needs_second_half_fn(line_window_issue_half_w) && (exec_seq_pc_q[2:1] == 2'd3);
	wire        line_window_issue_first_valid_w =
		exec_seq_pc_q[2] ? line_window_issue_subvalid_w[1] : line_window_issue_subvalid_w[0];
	wire        line_window_issue_same_line_valid_w =
		!((exec_seq_pc_q[2:1] == 2'd1) &&
		  instr_needs_second_half_fn(line_window_issue_half_w)) ||
		line_window_issue_subvalid_w[1];
	wire        line_window_issue_complete_w =
		line_window_issue_first_valid_w &&
		line_window_issue_same_line_valid_w &&
		(!line_window_issue_cross_w ||
		 (line_window_issue_from_cur_w && next_line_valid_q &&
		  (next_base_q == (line_window_issue_base_w + 32'd8)) &&
		  next_line_subvalid_q[0]));
	wire        line_window_issue_ready_w =
		cache_active_w &&
		(line_window_issue_from_cur_w || line_window_issue_from_next_w) &&
		line_window_issue_complete_w;
	wire [31:0] line_window_issue_iw_w =
		build_instr32_fn(line_window_issue_line_w, next_line_q, exec_seq_pc_q[2:1]);
	wire        memory_successor_address_edge_w =
		((state_q == STATE_MEM_WAIT) && !posted_write_busy_w && bus_complete_w &&
		 !active_write_q &&
		 (exec_issue_cycles_q == 6'd0)) ||
		((state_q == STATE_TIMING_WAIT) && (timing_cycles_q == 6'd1) &&
		 ((timing_kind_q == TIMING_MEM_LOAD) ||
		  (timing_kind_q == TIMING_MEM_STORE)));
	wire        chcw_ram_access_w =
		(state_q == STATE_CHCW_RAM_REQ) ||
		(state_q == STATE_CHCW_RAM_WAIT) ||
		(state_q == STATE_CHCW_RAM_WRITE);
	wire        cache_maintenance_w =
		(state_q == STATE_CACHE_CLEAR) ||
		(state_q == STATE_CHCW_RAM_REQ) ||
		(state_q == STATE_CHCW_RAM_WAIT) ||
		(state_q == STATE_CHCW_RAM_WRITE) ||
		(state_q == STATE_CHCW_BUS_REQ) ||
		(state_q == STATE_CHCW_BUS_WAIT);

	// Register cache writes one CE before RAM and keep lookup on a separate port.
	wire        ic_data_wren_w = ce_i && ic_data_write_valid_q;
	wire        ic_tag_wren_w = ce_i && ic_tag_write_valid_q;

	wire [6:0] ic_data_read_addr_w =
		curr_lookup_access_w              ? curr_lookup_index_w :
		next_lookup_access_w              ? next_lookup_index_w :
		prefetch_lookup_access_w          ? prefetch_lookup_index_w :
		chcw_ram_access_w                  ? chcw_index_q :
		fill_index_q;

	wire [6:0] ic_tag_read_addr_w =
		curr_lookup_access_w              ? curr_lookup_index_w :
		next_lookup_access_w              ? next_lookup_index_w :
		prefetch_lookup_access_w          ? prefetch_lookup_index_w :
		chcw_ram_access_w                  ? chcw_index_q :
		fill_index_q;

	wire [63:0] ic_data_q_w;
	wire [31:0] ic_tag_q_w;
	wire [7:0]  savestate_gpr_rdata_w;
	wire [7:0]  savestate_ic_data_rdata_w;
	wire [7:0]  savestate_ic_tag_rdata_w;
	wire        savestate_gpr_active_w = savestate_mem_active_i &&
		(savestate_mem_addr_i < 11'd128);
	wire        savestate_ic_data_active_w = savestate_mem_active_i &&
		(savestate_mem_addr_i >= 11'd128) &&
		(savestate_mem_addr_i < 11'd1152);
	wire        savestate_ic_tag_active_w = savestate_mem_active_i &&
		(savestate_mem_addr_i >= 11'd1152);
	wire [9:0]  savestate_ic_data_addr_w =
		savestate_mem_addr_i[9:0] - 10'd128;
	wire [8:0]  savestate_ic_tag_addr_w =
		savestate_mem_addr_i[8:0] - 9'd128;

	wire        irq_accept_w   = interrupt_accepted_fn(irq_valid_i, irq_level_i, psw_q);
	wire        held_irq_accept_w = interrupt_accepted_fn(
		cache_irq_pending_q, cache_irq_level_q, psw_q);
	wire        irq_accept_now_w = (held_irq_accept_w || irq_accept_w) && !irq_defer_q;
	wire [3:0]  irq_accept_level_w = held_irq_accept_w ?
		cache_irq_level_q : irq_level_i;
	wire        nmi_request_w  = nmi_pending_q || (nmi_i && !nmi_prev_q);
	wire        nmi_accept_w   = nmi_accepted_fn(nmi_request_w, psw_q);
	// Address traps fire before fetch; interrupts fire at instruction boundaries.
	wire        addr_trap_w    = ((psw_q & PSW_AE_MASK) != 32'd0) && (pc_q == {adtre_q[31:1], 1'b0});
	// Posted writes may outlive retire but still block hold and interrupts.
	wire [1:0]  halted_async_exc_kind_w =
		async_exception_kind_fn(1'b0, nmi_accept_w, !posted_write_busy_w && irq_accept_now_w);
	wire [1:0]  front_async_exc_kind_w =
		async_exception_kind_fn(addr_trap_w, nmi_accept_w, !posted_write_busy_w && irq_accept_now_w);
	wire        resident_sequential_successor_ready_w =
		(front_async_exc_kind_w == ASYNC_EXC_NONE) &&
		(((psw_q & PSW_AE_MASK) == 32'd0) ||
		 (exec_seq_pc_q != {adtre_q[31:1], 1'b0})) &&
		line_window_issue_ready_w &&
		!hldrq_i;
	// Most LDSR forms may keep a resident successor. PSW and CHCW restart fetch;
	// ADTRE uses the value being committed for the next trap check.
	wire        timing_ldsr_next_addr_trap_w =
		((psw_q & PSW_AE_MASK) != 32'd0) &&
		(exec_seq_pc_q == ((timing_regid_q == SYS_ADTRE) ?
			{timing_value_q[31:1], 1'b0} : {adtre_q[31:1], 1'b0}));
	wire        timing_ldsr_resident_successor_ready_w =
		(timing_regid_q != SYS_PSW) &&
		(timing_regid_q != SYS_CHCW) &&
		(front_async_exc_kind_w == ASYNC_EXC_NONE) &&
		!timing_ldsr_next_addr_trap_w &&
		line_window_issue_ready_w &&
		!hldrq_i;
	// Present a resident LDSR/STSR successor's GPR addresses on the terminal edge.
	wire        timing_sysreg_successor_address_edge_w =
		(state_q == STATE_TIMING_WAIT) && (timing_cycles_q == 6'd1) &&
		(((timing_kind_q == TIMING_LDSR) &&
		  timing_ldsr_resident_successor_ready_w) ||
		 ((timing_kind_q == TIMING_STSR) &&
		  resident_sequential_successor_ready_w));
	wire        long_load_overlap_common_w =
		resident_sequential_successor_ready_w &&
		instr_is_plain_load_fn(line_window_issue_iw_w) &&
		long_kind_allows_load_overlap_fn(long_kind_q) &&
		!active_q &&
		!store_pending_w &&
		(front_wait_cycles_fn(
			line_window_issue_iw_w,
			exec_df_producer_q,
			exec_wb_producer_q,
			exec_df_flags_q,
			exec_wb_flags_q,
			1'b0) == 2'd0);
	// Present overlapped LD source IDs one CE before phi1 captures the address.
	wire        long_load_rf_address_w =
		(state_q == STATE_LONG) &&
		((long_cycles_q == 6'd3) || (long_cycles_q == 6'd2)) &&
		long_load_overlap_common_w;
	wire        long_load_capture_w =
		(state_q == STATE_LONG) &&
		(long_cycles_q == 6'd2) &&
		long_load_overlap_common_w &&
		!rf_commit_block_w;
	wire        long_abortable_final_w =
		(state_q == STATE_LONG) &&
		(long_cycles_q == 6'd1) &&
		abortable_engine_fn(ABORT_ENGINE_LONG, long_kind_q);
	wire        bitstr_abortable_final_w =
		(state_q == STATE_BS_TIMING_WAIT) &&
		(bs_cycles_q == 6'd1) &&
		(bs_wait_action_q == BSWAIT_RESUME) &&
		abortable_engine_fn(ABORT_ENGINE_BITSTR, 4'd0);
	wire [1:0]  abort_async_exc_kind_w =
		async_exception_kind_fn(1'b0, nmi_accept_w, !posted_write_busy_w && irq_accept_now_w);
	wire [1:0]  long_async_exc_kind_w =
		long_abortable_final_w ? abort_async_exc_kind_w : ASYNC_EXC_NONE;
	// A retained retire pulse may overlap the already-selected successor. Keep
	// every iterative engine idle on the edge that redirects the parent into
	// checkpoint hold, otherwise that successor has no STATE_LONG finish edge.
	wire        savestate_hold_enter_w = savestate_pause_req_i &&
		(savestate_boundary_pending_q || trace_valid_o ||
		 (halted_q && !active_q && !store_pending_w));
	wire        int_engine_active_kind_w =
		(long_kind_q == LONG_MUL) || (long_kind_q == LONG_MULU) ||
		(long_kind_q == LONG_MPYHW) || (long_kind_q == LONG_DIV) ||
		(long_kind_q == LONG_DIVU) || (long_kind_q == LONG_REV);
	wire        int_engine_launch_kind_w =
		(ucode_alu_op_w == LONG_MUL) || (ucode_alu_op_w == LONG_MULU) ||
		(ucode_alu_op_w == LONG_MPYHW) || (ucode_alu_op_w == LONG_DIV) ||
		(ucode_alu_op_w == LONG_DIVU) || (ucode_alu_op_w == LONG_REV);
	wire        int_engine_start_w =
		(state_q == STATE_EXEC) && !hldrq_i && (ucode_kind_w == MK_LONG) &&
		!savestate_hold_enter_w &&
		int_engine_launch_kind_w && !int_engine_busy_w &&
		!(((ucode_alu_op_w == LONG_DIV) || (ucode_alu_op_w == LONG_DIVU)) &&
		  (exec_reg1_val_q == 32'd0));
	wire        int_engine_kill_w =
		(state_q == STATE_LONG) && int_engine_active_kind_w &&
		(long_async_exc_kind_w != ASYNC_EXC_NONE);
	wire        int_engine_finish_w =
		(state_q == STATE_LONG) && int_engine_active_kind_w &&
		(long_cycles_q == 6'd1) &&
		(long_async_exc_kind_w == ASYNC_EXC_NONE);
	wire        fp_engine_active_kind_w =
		(long_kind_q == LONG_CMPF) || (long_kind_q == LONG_CVTWS) ||
		(long_kind_q == LONG_CVTSW) || (long_kind_q == LONG_TRNCSW) ||
		(long_kind_q == LONG_ADDF);
	wire        fp_engine_launch_kind_w =
		(ucode_alu_op_w == LONG_CMPF) || (ucode_alu_op_w == LONG_CVTWS) ||
		(ucode_alu_op_w == LONG_CVTSW) || (ucode_alu_op_w == LONG_TRNCSW) ||
		(ucode_alu_op_w == LONG_ADDF) || (ucode_alu_op_w == LONG_SUBF);
	wire        fp_engine_start_w =
		(state_q == STATE_EXEC) && !hldrq_i && (ucode_kind_w == MK_LONG) &&
		!savestate_hold_enter_w &&
		fp_engine_launch_kind_w && !fp_engine_busy_w;
	wire        fp_engine_kill_w =
		(state_q == STATE_LONG) && fp_engine_active_kind_w &&
		(long_async_exc_kind_w != ASYNC_EXC_NONE);
	wire        fp_engine_finish_w =
		(state_q == STATE_LONG) && fp_engine_active_kind_w &&
		(long_cycles_q == 6'd1) &&
		(long_async_exc_kind_w == ASYNC_EXC_NONE);
	wire [1:0]  bitstr_async_exc_kind_w =
		bitstr_abortable_final_w ? abort_async_exc_kind_w : ASYNC_EXC_NONE;
	// Decode registered exception data without using live IRQ or bus inputs.
	wire        exc_entry_fatal_w;
	wire        exc_entry_save_ei_w;
	wire        exc_entry_save_fe_w;
	wire [31:0] exc_entry_saved_pc_w;
	wire [31:0] exc_entry_saved_psw_w;
	wire [31:0] exc_entry_next_ecr_w;
	wire        exc_entry_psw_write_w;
	wire [31:0] exc_entry_next_psw_w;
	wire        exc_entry_pc_write_w;
	wire [31:0] exc_handler_w;
	wire        exc_entry_clear_nmi_pending_w;
	wire        exc_entry_clear_halt_w;
	wire        exc_is_nmi_w;
	wire        exc_is_interrupt_w;
	wire        ifetch_uncached_w = !cache_active_or_pending_w;
	wire [5:0]  fetch_restart_state_w = ifetch_uncached_w ?
		STATE_IFETCH_REQ : STATE_LOOKUP_CUR_REQ;

	wire [31:0] mem_read_data_w = mem_read_data_fn(
		active_size_q, mem_signext_q, bus_read_data_w);
	wire [31:0] chcw_bus_addr_w = chcw_bus_addr_fn(
		chcw_sa_q, chcw_index_q, chcw_data_phase_q, chcw_word_q);
	wire [31:0] chcw_bus_wdata_w = chcw_bus_wdata_fn(
		chcw_line_q, chcw_tag_q, chcw_data_phase_q, chcw_word_q);
	wire [5:0]  bs_step_w = bs_step_fn(bs_len_q, bs_dst_ofs_q);
	wire [5:0]  bs_src_sum_w = {1'b0, bs_src_ofs_q} + bs_step_w;
	wire [5:0]  bs_dst_sum_w = {1'b0, bs_dst_ofs_q} + bs_step_w;
	wire [31:0] bs_next_src_addr_w = bs_src_addr_q + {29'd0, bs_src_sum_w[5], 2'b00};
	wire [31:0] bs_next_dst_addr_w = bs_dst_addr_q + {29'd0, bs_dst_sum_w[5], 2'b00};
	wire [4:0]  bs_next_src_ofs_w = bs_src_sum_w[4:0];
	wire [4:0]  bs_next_dst_ofs_w = bs_dst_sum_w[4:0];
	wire [31:0] bs_next_len_w = bs_len_q - {26'd0, bs_step_w};
	wire [5:0]  bs_search_step_w = bs_search_step_fn(bs_len_q, bs_src_ofs_q, bs_down_q);
	wire [31:0] bs_search_partial_len_w = bs_len_q - {26'd0, bs_search_step_w};
	// Bit-string operands live in fixed architectural registers r26-r30.
	wire [31:0] bs_launch_src_addr_w = exec_bs_r30_q;
	wire [31:0] bs_launch_dst_addr_w = exec_bs_r29_q;
	wire [31:0] bs_launch_len_w = exec_bs_r28_q;
	wire [4:0]  bs_launch_src_ofs_w = exec_bs_r27_q;
	wire [4:0]  bs_launch_dst_ofs_w = exec_bs_r26_q;
	wire [5:0]  bs_search_resume_cycles_w =
		bs_search_resume_cycles_fn(bs_first_partial_q, bs_last_partial_q, bs_down_q, bs_total_words_q, bs_word_index_q, siz16b_q);
	wire [5:0]  bs_post_cycles_w =
		bs_arith_resume_cycles_fn(bs_type_q, bs_total_words_q, bs_word_index_q, siz16b_q);
	wire        bs_first_launch_w = !bs_seq_active_q || (bs_seq_pc_q != exec_pc_q);
	wire [63:0] bs_source_align_w = bitstr_source_align_fn(
		bs_src_lo_q,
		bs_src_hi_q,
		bs_src_ofs_q,
		bs_dst_ofs_q,
		bs_step_w);
	wire [31:0] exec_bus_next_pc_w =
		((ucode_kind_w == MK_ALU) && ucode_pc_from_result_w) ?
			{exec_alu_result_w[31:1], 1'b0} :
		((ucode_kind_w == MK_BRANCH) && ucode_pc_from_bcond_w && exec_condition_q) ?
			{exec_bcond_target_q[31:1], 1'b0} : exec_seq_pc_q;
	wire        exec_bus_retire_class_w =
		(ucode_kind_w == MK_NOP) ||
		(ucode_kind_w == MK_ALU) ||
		(ucode_kind_w == MK_BRANCH);
	wire        exec_direct_bus_fetch_w =
		(state_q == STATE_EXEC) &&
		!hldrq_i &&
		exec_bus_retire_class_w &&
		ucode_end_w &&
		!ucode_halt_w &&
		(front_async_exc_kind_w == ASYNC_EXC_NONE) &&
		(((psw_q & PSW_AE_MASK) == 32'd0) ||
		 (exec_bus_next_pc_w != {adtre_q[31:1], 1'b0})) &&
		phi1_seen_q &&
		(fetch_restart_state_w == STATE_IFETCH_REQ);
	// Keep, then discard, the extra fetch word admitted before a halfword JMP flush.
	wire        exec_wrong_path_word_fetch_w =
		exec_direct_bus_fetch_w &&
		(exec_iw_q[31:26] == OP_JMP) &&
		exec_pc_q[1];

	// One arbiter launches requests into the registered bus engine. Posted-store
	// replacement has priority on its legal same-edge handoff.
	task select_bus_launch_task;
		input [31:0] launch_addr;
		input        launch_fetch;
		input        launch_fetch_branch;
		input        launch_write;
		input        launch_posted;
		input [1:0]  launch_size;
		input [31:0] launch_wdata;
		begin
			bus_launch_v = 1'b1;
			bus_launch_addr_v = launch_addr;
			bus_launch_fetch_v = launch_fetch;
			bus_launch_fetch_branch_v = launch_fetch_branch;
			bus_launch_write_v = launch_write;
			bus_launch_posted_v = launch_posted;
			bus_launch_size_v = launch_size;
			bus_launch_wdata_v = launch_wdata;
		end
	endtask

	always @* begin
		bus_launch_v = 1'b0;
		bus_launch_addr_v = 32'd0;
		bus_launch_fetch_v = 1'b0;
		bus_launch_fetch_branch_v = 1'b0;
		bus_launch_write_v = 1'b0;
		bus_launch_posted_v = 1'b0;
		bus_launch_addr_error_v = 1'b0;
		bus_launch_size_v = SIZE_H;
		bus_launch_wdata_v = 32'd0;

		if (posted_write_busy_w && bus_complete_w &&
			(state_q == STATE_MEM_REQ) && !mem_write_q) begin
			select_bus_launch_task(
				mem_addr_q, 1'b0, 1'b0, 1'b0, 1'b0, mem_size_q, 32'd0);
			bus_launch_addr_error_v = mem_addr_error_q;
		end else begin
			case (state_q)
				STATE_IFETCH_REQ: begin
					if (!hldrq_i && !halted_q &&
						(front_async_exc_kind_w == ASYNC_EXC_NONE) && !active_q) begin
						select_bus_launch_task(
							{pc_q[31:1], 1'b0}, 1'b1, 1'b1, 1'b0, 1'b0, SIZE_H, 32'd0);
					end
				end

				STATE_IFETCH2_REQ: begin
					if (!hldrq_i && !active_q) begin
						select_bus_launch_task(
							({pc_q[31:1], 1'b0} + 32'd2),
							1'b1, 1'b0, 1'b0, 1'b0, SIZE_H, 32'd0);
					end
				end

				STATE_FILL_REQ: begin
					if (!hldrq_i && !active_q) begin
						select_bus_launch_task(
							fill_base_q + {29'd0, fill_half_q, 1'b0},
							1'b1, fill_branch_fetch_q && (fill_half_q == 2'd0),
							1'b0, 1'b0, SIZE_H, 32'd0);
					end
				end

				STATE_LONG: begin
					if (long_load_overlap_q && (long_cycles_q == 6'd2) && !active_q) begin
						select_bus_launch_task(
							mem_addr_q, 1'b0, 1'b0, 1'b0, 1'b0, mem_size_q, 32'd0);
						bus_launch_addr_error_v = mem_addr_error_q;
					end
				end

				STATE_EXEC: begin
					if (!hldrq_i && (ucode_kind_w == MK_MEM) &&
						((ucode_mem_write_w && bus_posted_ready_w) ||
						 (!ucode_mem_write_w && !active_q))) begin
						select_bus_launch_task(
							exec_mem_addr_w, 1'b0, 1'b0, ucode_mem_write_w,
							ucode_mem_write_w,
							ucode_mem_size_w,
							ucode_mem_write_w ? exec_reg2_val_q : 32'd0);
						bus_launch_addr_error_v = address_error_fn(
							exec_eff_addr_q, ucode_mem_size_w);
					end else if (exec_wrong_path_word_fetch_w) begin
						select_bus_launch_task(
							({exec_seq_pc_q[31:2], 2'b00} + 32'd4),
							1'b1, 1'b0, 1'b0, 1'b0, SIZE_W, 32'd0);
					end else if (exec_direct_bus_fetch_w) begin
						select_bus_launch_task(
							exec_bus_next_pc_w, 1'b1, 1'b1, 1'b0, 1'b0, SIZE_H, 32'd0);
					end
				end

				STATE_FATAL_REQ: begin
					if (!active_q) begin
						select_bus_launch_task(
							{28'd0, fatal_index_q, 2'b00}, 1'b0, 1'b0, 1'b1,
							1'b0, SIZE_W, fatal_wdata_fn(fatal_index_q, exc_code_q, psw_q, pc_q));
					end
				end

				STATE_CHCW_BUS_REQ: begin
					if (!active_q) begin
						select_bus_launch_task(
							chcw_bus_addr_w, 1'b0, 1'b0, chcw_dump_q,
							1'b0, SIZE_W, chcw_bus_wdata_w);
					end
				end

				STATE_CAXI_REQ: begin
					if (!active_q) begin
						select_bus_launch_task(
							caxi_addr_q, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_W, 32'd0);
						bus_launch_addr_error_v = caxi_addr_error_q;
					end
				end

				STATE_CAXI_STORE_REQ: begin
					if (!active_q) begin
						select_bus_launch_task(
							caxi_addr_q, 1'b0, 1'b0, 1'b1, 1'b0, SIZE_W, caxi_store_data_q);
						bus_launch_addr_error_v = caxi_addr_error_q;
					end
				end

				STATE_BS_SRC_REQ: begin
					if (!active_q) begin
						select_bus_launch_task(
							bs_src_addr_q + (bs_src_second_q ? 32'd4 : 32'd0),
							1'b0, 1'b0, 1'b0, 1'b0, SIZE_W, 32'd0);
					end
				end

				STATE_BS_DST_REQ: begin
					if (!active_q) begin
						select_bus_launch_task(
							bs_dst_addr_q, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_W, 32'd0);
					end
				end

				STATE_BS_WRITE_REQ: begin
					if (!active_q) begin
						select_bus_launch_task(
							bs_dst_addr_q, 1'b0, 1'b0, 1'b1, 1'b0, SIZE_W, bs_write_word_q);
					end
				end

				STATE_MEM_REQ: begin
					if ((mem_write_q && bus_posted_ready_w) ||
						(!mem_write_q && !active_q)) begin
						select_bus_launch_task(
							mem_addr_q, 1'b0, 1'b0, mem_write_q, mem_write_q, mem_size_q,
							mem_write_q ? mem_wdata_q : 32'd0);
						bus_launch_addr_error_v = mem_addr_error_q;
					end
				end

				STATE_MEM_WAIT: begin
					if (!posted_write_busy_w && bus_complete_w && !active_write_q &&
						(exec_issue_cycles_q == 6'd0) &&
						!resident_sequential_successor_ready_w &&
						!irq_accept_now_w && !nmi_accept_w &&
						(fetch_restart_state_w == STATE_IFETCH_REQ)) begin
						select_bus_launch_task(
							exec_seq_pc_q, 1'b1, 1'b1, 1'b0, 1'b0, SIZE_H, 32'd0);
					end
				end

				default: begin
				end
			endcase
		end
	end

	// Present source addresses at issue so RAM operands arrive before phi1.
	always @* begin
		rf_issue_half_v = exec_iw_q[31:16];
		case (state_q)
			STATE_EXEC: begin
				if (line_window_issue_ready_w) begin
					rf_issue_half_v = line_window_issue_half_w;
				end
			end
			STATE_LONG: begin
				// Present an overlapping LD base one phi1 before long-op completion.
				if (long_load_rf_address_w ||
					((long_cycles_q == 6'd1) && line_window_issue_ready_w)) begin
					rf_issue_half_v = line_window_issue_half_w;
				end
			end
			STATE_LONG_LOAD_WAIT: begin
				if ((long_load_data_valid_q || bus_complete_w) &&
					line_window_issue_ready_w) begin
					rf_issue_half_v = line_window_issue_half_w;
				end
			end
			STATE_MEM_REQ: begin
				// Present a posted store's resident successor when the store retires.
				if (bus_launch_accept_w && mem_write_q &&
					(exec_issue_cycles_q == 6'd0) &&
					resident_sequential_successor_ready_w) begin
					rf_issue_half_v = line_window_issue_half_w;
				end
			end
			STATE_MEM_WAIT,
			STATE_TIMING_WAIT: begin
				if ((memory_successor_address_edge_w && line_window_issue_ready_w) ||
					timing_sysreg_successor_address_edge_w) begin
					rf_issue_half_v = line_window_issue_half_w;
				end
			end
			STATE_LOOKUP_CUR_WAIT: begin
				rf_issue_half_v = halfword_from_line_fn(ic_data_q_w, pc_q[2:1]);
			end
			STATE_LOOKUP_NEXT_WAIT: begin
				rf_issue_half_v = halfword_from_line_fn(cur_line_q, pc_q[2:1]);
			end
			STATE_IFETCH_WAIT: begin
				rf_issue_half_v = bus_read_data_w[15:0];
			end
			STATE_IFETCH2_WAIT,
			STATE_IFETCH_ISSUE: begin
				rf_issue_half_v = ifetch_iw_q[31:16];
			end
			STATE_FILL_WAIT: begin
				if (fill_target_next_q) begin
					rf_issue_half_v = halfword_from_line_fn(cur_line_q, pc_q[2:1]);
				end else begin
					rf_issue_half_v = halfword_from_line_fn(fill_merged_line_w, pc_q[2:1]);
				end
			end
			default: begin
			end
		endcase
	end


	task update_retire_history_task;
		input [2:0] retire_class;
		input [1:0] retire_size;
		input       retire_io;
		begin
			prev_retire_class_q <= retire_class;
			prev_retire_size_q <= retire_size;
			prev_retire_io_q <= retire_io;
			store_load_hold_q <= (retire_class == RETIRE_CLASS_STORE);
		end
	endtask

	// Publish the retire trace pulse and refresh the hazard trackers.
	task retire_trace_task;
		input [5:0] df_producer;
		input [6:0] wb_producer;
		input       df_flags;
		input       wb_flags;
		input [1:0] write_streak;
		begin
			trace_valid_o <= 1'b1;
			trace_pc_o <= exec_pc_q;
			trace_insn_o <= exec_trace_insn_q;
			hazard_df_producer_q <= df_producer;
			hazard_wb_producer_q <= wb_producer;
			hazard_df_flags_q <= df_flags;
			hazard_wb_flags_q <= wb_flags;
			write_streak_q <= write_streak;
		end
	endtask

	// Retire a completed store now, or park its residual wait cycles.
	task retire_store_task;
		input [1:0] size;
		input       io;
		begin
			timing_kind_q <= TIMING_MEM_STORE;
			timing_cycles_q <= exec_issue_cycles_q;
			if (exec_issue_cycles_q == 6'd0) begin
				retire_trace_task(6'd0, 7'd0, 1'b0, 1'b0,
					next_write_streak_fn(
						write_streak_q, prev_retire_size_q, prev_retire_io_q,
						size, io));
				update_retire_history_task(RETIRE_CLASS_STORE, size, io);
				pc_q <= exec_seq_pc_q;
				if (resident_sequential_successor_ready_w) begin
					accept_resident_successor_task(
						6'd0, 7'd0, 1'b0, 1'b0, 1'b1);
				end else begin
					state_q <= fetch_restart_state_w;
				end
			end else begin
				state_q <= STATE_TIMING_WAIT;
			end
		end
	endtask

	// Drop both resident cache-line windows.
	task invalidate_line_window_task;
		begin
			cur_line_valid_q <= 1'b0;
			next_line_valid_q <= 1'b0;
			cur_line_subvalid_q <= 2'b00;
			next_line_subvalid_q <= 2'b00;
		end
	endtask

	task accept_resident_successor_task;
		input [5:0] predecessor_df_producer;
		input [6:0] predecessor_wb_producer;
		input       predecessor_df_flags;
		input       predecessor_wb_flags;
		input       predecessor_store_load_hold;
		begin
			accept_issue_task(exec_seq_pc_q, line_window_issue_iw_w,
				predecessor_df_producer, predecessor_wb_producer,
				predecessor_df_flags, predecessor_wb_flags,
				predecessor_store_load_hold);
			if (line_window_issue_from_next_w) begin
				cur_line_q <= next_line_q;
				cur_base_q <= next_base_q;
				cur_line_valid_q <= 1'b1;
				cur_line_subvalid_q <= next_line_subvalid_q;
				next_line_valid_q <= 1'b0;
				next_line_subvalid_q <= 2'b00;
			end
		end
	endtask

	task accept_issue_task;
		input [31:0] issue_pc;
		input [31:0] issue_iw;
		input [5:0]  predecessor_df_producer;
		input [6:0]  predecessor_wb_producer;
		input        predecessor_df_flags;
		input        predecessor_wb_flags;
		input        predecessor_store_load_hold;
		reg [1:0]    issue_wait_v;
		reg [31:0]   canonical_iw_v;
		begin
			canonical_iw_v = instr_needs_second_half_fn(issue_iw[31:16]) ?
				issue_iw : {issue_iw[31:16], 16'd0};
			issue_wait_v = front_wait_cycles_fn(
				canonical_iw_v,
				predecessor_df_producer,
				predecessor_wb_producer,
				predecessor_df_flags,
				predecessor_wb_flags,
				predecessor_store_load_hold);
			exec_pc_q <= {issue_pc[31:1], 1'b0};
			exec_iw_q <= canonical_iw_v;
			exec_uop_q <= decode_uentry_fn(canonical_iw_v);
			front_cycles_q <= issue_wait_v;
			hazard_df_producer_q <= 6'd0;
			hazard_wb_producer_q <= 7'd0;
			hazard_df_flags_q <= 1'b0;
			hazard_wb_flags_q <= 1'b0;
			store_load_hold_q <= 1'b0;
			// Keep RETI interrupt inhibit until the restored instruction issues.
			if (irq_defer_q) begin
				irq_defer_q <= 1'b0;
			end
			if (cache_enable_pending_q) begin
				cache_control_write_we_v = 1'b1;
				cache_control_enable_v = 1'b1;
				cache_control_pending_v = 1'b0;
			end
			if (issue_wait_v != 2'd0) begin
				state_q <= STATE_FRONT_WAIT;
			end else begin
				state_q <= STATE_UCODE_WAIT;
			end
		end
	endtask

	task request_gpr_write_task;
		input [4:0]  write_addr;
		input [31:0] write_data;
		begin
			// Drop writes to hard-wired r0.
			if (write_addr != 5'd0) begin
				// Merge duplicate destinations; the later write wins.
				if (gpr_commit_we_v[0] && (gpr_commit_addr0_v == write_addr)) begin
					gpr_commit_data0_v = write_data;
				end else if (gpr_commit_we_v[1] && (gpr_commit_addr1_v == write_addr)) begin
					gpr_commit_data1_v = write_data;
				end else if (gpr_commit_we_v[2] && (gpr_commit_addr2_v == write_addr)) begin
					gpr_commit_data2_v = write_data;
				end else if (gpr_commit_we_v[3] && (gpr_commit_addr3_v == write_addr)) begin
					gpr_commit_data3_v = write_data;
				end else if (gpr_commit_we_v[4] && (gpr_commit_addr4_v == write_addr)) begin
					gpr_commit_data4_v = write_data;
				end else if (!gpr_commit_we_v[0]) begin
					gpr_commit_we_v[0] = 1'b1;
					gpr_commit_addr0_v = write_addr;
					gpr_commit_data0_v = write_data;
				end else if (!gpr_commit_we_v[1]) begin
					gpr_commit_we_v[1] = 1'b1;
					gpr_commit_addr1_v = write_addr;
					gpr_commit_data1_v = write_data;
				end else if (!gpr_commit_we_v[2]) begin
					gpr_commit_we_v[2] = 1'b1;
					gpr_commit_addr2_v = write_addr;
					gpr_commit_data2_v = write_data;
				end else if (!gpr_commit_we_v[3]) begin
					gpr_commit_we_v[3] = 1'b1;
					gpr_commit_addr3_v = write_addr;
					gpr_commit_data3_v = write_data;
				end else if (!gpr_commit_we_v[4]) begin
					gpr_commit_we_v[4] = 1'b1;
					gpr_commit_addr4_v = write_addr;
					gpr_commit_data4_v = write_data;
				end
// synthesis translate_off
`ifndef SYNTHESIS
				else begin
					$fatal(1, "NECv810 GPR commit record overflow");
				end
`endif
// synthesis translate_on
			end
		end
	endtask

	task request_psw_write_task;
		input [31:0] write_mask;
		input [31:0] write_data;
		reg [31:0] effective_mask_v;
		begin
			effective_mask_v = write_mask & PSW_WRITE_MASK;
			if (effective_mask_v != 32'd0) begin
				// Merge PSW updates in program order; later bits win.
				psw_commit_we_v = 1'b1;
				psw_commit_data_v =
					(psw_commit_data_v & ~effective_mask_v) |
					(write_data & effective_mask_v);
			end
		end
	endtask

	task request_cache_mode_task;
		input requested_enable;
		begin
			if (requested_enable) begin
				if (!cache_enable_q) begin
					cache_control_write_we_v = 1'b1;
					cache_control_enable_v = 1'b0;
					cache_control_pending_v = 1'b1;
				end
			end else begin
				cache_control_write_we_v = 1'b1;
				cache_control_enable_v = 1'b0;
				cache_control_pending_v = 1'b0;
			end
		end
	endtask

	task publish_bitstr_checkpoint_task;
		begin
			request_gpr_write_task(5'd30, bs_src_addr_q);
			request_gpr_write_task(5'd28, bs_len_q);
			request_gpr_write_task(5'd27, {27'd0, bs_src_ofs_q});
			if (bs_search_q) begin
				request_gpr_write_task(5'd29, bs_search_count_q);
			end else begin
				request_gpr_write_task(5'd29, bs_dst_addr_q);
				request_gpr_write_task(5'd26, {27'd0, bs_dst_ofs_q});
			end
		end
	endtask

// synthesis translate_off
`ifndef SYNTHESIS
	// Testbench accessors expose architectural state and update r26-r30 shadows.
	task sim_set_gpr_task;
		input [4:0]  write_addr;
		input [31:0] write_data;
		begin
			u_gpr_file.sim_set_gpr_task(write_addr, write_data);
			case (write_addr)
				5'd26: gpr_r26_shadow_q = write_data[4:0];
				5'd27: gpr_r27_shadow_q = write_data[4:0];
				5'd28: gpr_r28_shadow_q = write_data;
				5'd29: gpr_r29_shadow_q = write_data;
				5'd30: gpr_r30_shadow_q = write_data;
				default: begin
				end
			endcase
		end
	endtask

	function [31:0] sim_read_gpr_fn;
		input [4:0] read_addr;
		begin
			sim_read_gpr_fn = u_gpr_file.sim_read_gpr_fn(read_addr);
		end
	endfunction

	// Test-only retire and exception trace read hierarchically by benches.
	reg         sim_commit_valid_q;
	reg [31:0]  sim_commit_pc_q;
	reg [31:0]  sim_exec_iw_q;
	reg [31:0]  sim_commit_iw_q;
	reg [2:0]   sim_commit_len_q;
	reg         sim_exception_valid_q;
	reg [15:0]  sim_exception_code_q;
	reg [31:0]  sim_exception_handler_q;
	reg [31:0]  sim_exception_restore_pc_q;

	always @(posedge clk_i or posedge reset_i) begin
		if (reset_i) begin
			sim_commit_valid_q <= 1'b0;
			sim_commit_pc_q <= 32'd0;
			sim_exec_iw_q <= 32'd0;
			sim_commit_iw_q <= 32'd0;
			sim_commit_len_q <= 3'd0;
			sim_exception_valid_q <= 1'b0;
			sim_exception_code_q <= 16'd0;
			sim_exception_handler_q <= 32'd0;
			sim_exception_restore_pc_q <= 32'd0;
		end else begin
			sim_commit_valid_q <= 1'b0;
			sim_exception_valid_q <= 1'b0;
			if (ce_i) begin
				sim_exec_iw_q <= exec_iw_q;
			end
			if (trace_valid_o) begin
				sim_commit_valid_q <= 1'b1;
				sim_commit_pc_q <= trace_pc_o;
				sim_commit_iw_q <= sim_exec_iw_q;
				sim_commit_len_q <= instr_needs_second_half_fn(sim_exec_iw_q[31:16]) ? 3'd4 : 3'd2;
			end
			if (ce_i && (state_q == STATE_EXC_ENTER)) begin
				sim_exception_valid_q <= 1'b1;
				sim_exception_code_q <= exc_code_q;
				sim_exception_handler_q <= exc_handler_w;
				sim_exception_restore_pc_q <= exc_restore_pc_q;
			end
		end
	end

`endif
// synthesis translate_on

	necv810_exception_entry u_exception_entry (
		.code_i(exc_code_q),
		.restore_pc_i(exc_restore_pc_q),
		.psw_i(psw_q),
		.ecr_i(ecr_q),
		.fatal_o(exc_entry_fatal_w),
		.save_ei_o(exc_entry_save_ei_w),
		.save_fe_o(exc_entry_save_fe_w),
		.saved_pc_o(exc_entry_saved_pc_w),
		.saved_psw_o(exc_entry_saved_psw_w),
		.next_ecr_o(exc_entry_next_ecr_w),
		.psw_write_o(exc_entry_psw_write_w),
		.next_psw_o(exc_entry_next_psw_w),
		.pc_write_o(exc_entry_pc_write_w),
		.handler_o(exc_handler_w),
		.clear_nmi_pending_o(exc_entry_clear_nmi_pending_w),
		.clear_halt_o(exc_entry_clear_halt_w),
		.is_nmi_o(exc_is_nmi_w),
		.is_interrupt_o(exc_is_interrupt_w)
	);

	// One clocked bus engine owns pins and active transaction state.
	necv810_bus_engine u_bus_engine (
		.clk_i(clk_i),
		.reset_i(cpu_transient_reset_w),
		.clk_en_i(ce_i),
		.launch_i(bus_launch_v),
		.launch_addr_i(bus_launch_addr_v),
		.launch_fetch_i(bus_launch_fetch_v),
		.launch_fetch_branch_i(bus_launch_fetch_branch_v),
		.launch_write_i(bus_launch_write_v),
		.launch_posted_i(bus_launch_posted_v),
		.launch_addr_error_i(bus_launch_addr_error_v),
		.launch_size_i(bus_launch_size_v),
		.launch_wdata_i(bus_launch_wdata_v),
		.ready_i(ready_i),
		.fixed_16_i(siz16b_q),
		.szrq_i(szrq_i),
		.din_i(din_i),
		.idle_addr_i(pc_q[31:1]),
		.launch_ready_o(),
		.posted_ready_o(bus_posted_ready_w),
		.launch_accept_o(bus_launch_accept_w),
		.beat_accept_o(),
		.first_beat_o(),
		.complete_o(bus_complete_w),
		.read_data_o(bus_read_data_w),
		.active_o(active_q),
		.active_addr_o(active_addr_q),
		.active_fetch_o(active_fetch_q),
		.active_write_o(active_write_q),
		.active_posted_o(active_posted_q),
		.posted_pending_o(store_pending_w),
		.active_size_o(active_size_q),
		.active_phase_o(active_phase_q),
		.active_wdata_o(active_wdata_q),
		.first_half_o(),
		.a_o(bus_a_w),
		.dout_o(dout_o),
		.dout_oe_o(dout_oe_o),
		.be_o(bus_be_w),
		.st_o(bus_st_w),
		.da_o(da_o),
		.mrq_o(mrq_o),
		.rw_o(rw_o),
		.bcyst_o(bcyst_o),
		.adrs_err_n_o(adrs_err_n_o),
		.cycle_tag_o(cycle_tag_o)
	);

	necv810_integer_engine u_integer_engine (
		.clk_i(clk_i),
		.reset_i(cpu_transient_reset_w),
		.clk_en_i(ce_i),
		.phi1_i(phi1_i),
		.start_i(int_engine_start_w),
		.kill_i(int_engine_kill_w),
		.finish_i(int_engine_finish_w),
		.kind_i(ucode_alu_op_w),
		.lhs_i(exec_reg2_val_q),
		.rhs_i(exec_reg1_val_q),
		.start_accept_o(),
		.busy_o(int_engine_busy_w),
		.done_o(int_engine_done_w),
		.step_o(),
		.result_hi_o(int_engine_result_hi_w),
		.result_lo_o(int_engine_result_lo_w),
		.result_zero_o(int_engine_result_zero_w),
		.result_sign_o(int_engine_result_sign_w),
		.result_overflow_o(int_engine_result_overflow_w)
	);

	necv810_fp_engine u_fp_engine (
		.clk_i(clk_i),
		.reset_i(cpu_transient_reset_w),
		.clk_en_i(ce_i),
		.phi1_i(phi1_i),
		.start_i(fp_engine_start_w),
		.kill_i(fp_engine_kill_w),
		.finish_i(fp_engine_finish_w),
		.subop_i(exec_ext_subop_q),
		.lhs_i(exec_reg2_val_q),
		.rhs_i(exec_reg1_val_q),
		.start_accept_o(),
		.busy_o(fp_engine_busy_w),
		.done_o(fp_engine_done_w),
		.step_o(fp_engine_step_w),
		.result_o(fp_engine_result_w),
		.result_we_o(fp_engine_result_we_w),
		.psw_mask_o(fp_engine_psw_mask_w),
		.psw_data_o(fp_engine_psw_data_w),
		.exception_valid_o(fp_engine_exc_valid_w),
		.exception_code_o(fp_engine_exc_code_w)
	);
	// OEs reproduce package Hi-Z behavior in TH and reset hold. Internal values
	// remain driven so FPGA logic never depends on tri-states.
	wire package_fixed_16_w = reset_i ? siz16b_i : siz16b_q;
	wire package_bus_drive_w =
		(state_q != STATE_BUS_HOLD) && !(reset_i && hldrq_i);
	assign a_o             = reset_i ?
		{{30{1'b1}}, siz16b_i} : bus_a_w;
	assign be_o            = reset_i ? 4'b1111 : bus_be_w;
	assign st_o            = reset_i ? 2'b11 : bus_st_w;
	assign a_oe_o          = package_bus_drive_w;
	assign dout_lane_oe_o  = (package_bus_drive_w && dout_oe_o) ?
		(package_fixed_16_w ? 4'b0011 : 4'b1111) : 4'b0000;
	assign be_oe_o         = package_bus_drive_w ?
		(package_fixed_16_w ? 4'b0011 : 4'b1111) : 4'b0000;
	assign st_oe_o         = package_bus_drive_w;
	assign da_oe_o         = package_bus_drive_w;
	assign mrq_oe_o        = package_bus_drive_w;
	assign rw_oe_o         = package_bus_drive_w;
	assign bcyst_oe_o      = package_bus_drive_w;
	assign block_o         = caxi_active_q;
	assign hldak_o         = (state_q == STATE_BUS_HOLD);

	assign dbg_reg_data_o = dbg_reg_data_q;
	assign dbg_pc_o       = pc_q;
	assign dbg_psw_o      = psw_q;
	assign halted_o       = halted_q;
	assign illegal_o      = illegal_q;
	assign savestate_pause_ready_o =
		(state_q == STATE_SAVESTATE_HOLD) &&
		!active_q && !store_pending_w &&
		!rf_commit_valid_q && (rf_pending_count_w == 3'd0) &&
		!int_engine_busy_w && !fp_engine_busy_w;

	always @* begin
		savestate_state_rdata_o = 64'd0;
		case (savestate_state_addr_i)
			4'd0: savestate_state_rdata_o = {psw_q, pc_q};
			4'd1: savestate_state_rdata_o = {eipsw_q, eipc_q};
			4'd2: savestate_state_rdata_o = {fepsw_q, fepc_q};
			4'd3: savestate_state_rdata_o = {adtre_q, ecr_q};
			4'd4: savestate_state_rdata_o = {sr31_q, sr29_q};
			4'd5: savestate_state_rdata_o = {
				25'd0,
				cache_irq_level_q,
				cache_irq_pending_q,
				illegal_q,
				long_load_data_valid_q,
				long_load_overlap_q,
				store_load_hold_q,
				hazard_wb_flags_q,
				hazard_df_flags_q,
				hazard_wb_producer_q,
				hazard_df_producer_q,
				prev_retire_io_q,
				prev_retire_size_q,
				prev_retire_class_q,
				write_streak_q,
				fetch_defer_q,
				nmi_prev_q,
				nmi_pending_q,
				irq_defer_q,
				cache_enable_pending_q,
				cache_enable_q,
				halted_q};
			4'd6: savestate_state_rdata_o = {
				22'd0, gpr_r28_shadow_q, gpr_r27_shadow_q, gpr_r26_shadow_q};
			4'd7: savestate_state_rdata_o = {gpr_r30_shadow_q, gpr_r29_shadow_q};
			default: begin
			end
		endcase
	end

	always @* begin
		savestate_mem_rdata_o = 8'd0;
		if (savestate_gpr_active_w) begin
			savestate_mem_rdata_o = savestate_gpr_rdata_w;
		end else if (savestate_ic_data_active_w) begin
			savestate_mem_rdata_o = savestate_ic_data_rdata_w;
		end else if (savestate_ic_tag_active_w) begin
			savestate_mem_rdata_o = savestate_ic_tag_rdata_w;
		end
	end

	NECv810_icache_data_ram u_icache_data_ram (
		.clk_i(clk_i),
		.read_addr_i(ic_data_read_addr_w),
		.write_addr_i(ic_data_write_addr_q),
		.write_en_i(ic_data_wren_w),
		.write_data_i(ic_data_write_data_q),
		.q_o(ic_data_q_w),
		.savestate_active_i(savestate_ic_data_active_w),
		.savestate_addr_i(savestate_ic_data_addr_w),
		.savestate_rden_i(savestate_mem_rden_i),
		.savestate_wren_i(savestate_mem_wren_i),
		.savestate_wdata_i(savestate_mem_wdata_i),
		.savestate_rdata_o(savestate_ic_data_rdata_w)
	);

	NECv810_icache_tag_ram u_icache_tag_ram (
		.clk_i(clk_i),
		.read_addr_i(ic_tag_read_addr_w),
		.write_addr_i(ic_tag_write_addr_q),
		.write_en_i(ic_tag_wren_w),
		.write_data_i(ic_tag_write_data_q),
		.q_o(ic_tag_q_w),
		.savestate_active_i(savestate_ic_tag_active_w),
		.savestate_addr_i(savestate_ic_tag_addr_w),
		.savestate_rden_i(savestate_mem_rden_i),
		.savestate_wren_i(savestate_mem_wren_i),
		.savestate_wdata_i(savestate_mem_wdata_i),
		.savestate_rdata_o(savestate_ic_tag_rdata_w)
	);

	NECv810_ucode_rom u_ucode_rom (
		.clk_i(clk_i),
		.ce_i(ce_i || phi1_i),
		.addr_i(exec_uop_q),
		.q_o(ucode_rom_word_w)
	);

	necv810_regfile u_gpr_file (
		.clk_i(clk_i),
		.reset_i(cpu_transient_reset_w),
		.clk_en_i(1'b1),
		.read_addr_a_i(rf_read_addr_a_w),
		.read_addr_b_i(rf_read_addr_b_w),
		.read_data_a_o(rf_read_data_a_w),
		.read_data_b_o(rf_read_data_b_w),
		.commit_en_i(phi1_i),
		.commit_valid_i(rf_commit_valid_q),
		.commit_we_i(rf_commit_we_q),
		.commit_addr0_i(rf_commit_addr0_q),
		.commit_addr1_i(rf_commit_addr1_q),
		.commit_addr2_i(rf_commit_addr2_q),
		.commit_addr3_i(rf_commit_addr3_q),
		.commit_addr4_i(rf_commit_addr4_q),
		.commit_data0_i(rf_commit_data0_q),
		.commit_data1_i(rf_commit_data1_q),
		.commit_data2_i(rf_commit_data2_q),
		.commit_data3_i(rf_commit_data3_q),
		.commit_data4_i(rf_commit_data4_q),
		.commit_ready_o(rf_commit_ready_w),
		.commit_accept_o(rf_commit_accept_w),
		.pending_count_o(rf_pending_count_w),
		.savestate_active_i(savestate_gpr_active_w),
		.savestate_addr_i(savestate_mem_addr_i[6:0]),
		.savestate_rden_i(savestate_mem_rden_i),
		.savestate_wren_i(savestate_mem_wren_i),
		.savestate_wdata_i(savestate_mem_wdata_i),
		.savestate_rdata_o(savestate_gpr_rdata_w)
	);

	reg [31:0] next_pc_v;
	reg [31:0] next_psw_v;
	reg [31:0] next_gpr_v;
	reg [31:0] next_sys_v;
	reg [63:0] complete_line_v;
	reg [31:0] fetched_iw_v;
	reg [31:0] chcw_write_v;
	reg [11:0] clear_count_v;
	reg        hold_state_v;
	reg [31:0] long32_v;
	reg [6:0]  bs_search_result_v;
	reg        bs_search_found_v;
	reg [5:0]  bs_search_skip_v;
	reg [5:0]  bs_search_advance_v;
	reg [5:0]  bs_search_tail_v;
	reg [31:0] bs_search_next_addr_v;
	reg [4:0]  bs_search_next_ofs_v;
	reg [31:0] bs_search_next_len_v;

	always @(posedge clk_i or posedge cpu_transient_reset_w) begin
		if (cpu_transient_reset_w) begin
			state_q <= STATE_CACHE_INIT;
			savestate_boundary_pending_q <= 1'b0;
			pc_q <= RESET_PC;
			psw_q <= RESET_PSW;
			rf_commit_valid_q <= 1'b0;
			// NEC leaves exception save registers undefined; FPGA startup uses zero.
			eipc_q <= 32'd0;
			eipsw_q <= 32'd0;
			fepc_q <= 32'd0;
			fepsw_q <= 32'd0;
			ecr_q <= 32'h0000_fff0;
			// ADTRE and undocumented registers also start at zero for FPGA repeatability.
			adtre_q <= 32'd0;
			sr29_q <= 32'd0;
			sr31_q <= 32'd0;
			halted_q <= 1'b0;
			illegal_q <= 1'b0;
			// Cache starts disabled until CHCW enables it; ICHEEN is only permission.
			cache_enable_q <= 1'b0;
			cache_enable_pending_q <= 1'b0;
			ic_data_write_valid_q <= 1'b0;
			// Silicon unknown: reset tag behavior is undocumented. Clear all 128 tags
			// before the first fetch.
			ic_tag_write_valid_q <= 1'b1;
			ic_tag_write_addr_q <= 7'd0;
			ic_tag_write_data_q <= 32'd0;
			init_index_q <= 7'd0;
			clear_index_q <= 7'd0;
			clear_last_q <= 7'd0;
			invalidate_line_window_task;
			fill_base_q <= 32'd0;
			fill_index_q <= 7'd0;
			fill_line_q <= 64'd0;
			fill_half_q <= 2'd0;
			fill_target_next_q <= 1'b0;
			fill_store_q <= 1'b0;
			fill_branch_fetch_q <= 1'b1;
			mem_write_q <= 1'b0;
			mem_io_q <= 1'b0;
			mem_signext_q <= 1'b0;
			mem_size_q <= SIZE_H;
			mem_addr_q <= 32'd0;
			mem_addr_error_q <= 1'b0;
			mem_wdata_q <= 32'd0;
			mem_dest_q <= 5'd0;
			exec_pc_q <= 32'd0;
			exec_iw_q <= 32'd0;
			exec_uop_q <= UADDR_NOP;
			exec_result_q <= 32'd0;
			exc_code_q <= 16'd0;
			exc_restore_pc_q <= 32'd0;
			fatal_index_q <= 2'd0;
			dbg_reg_data_q <= 32'd0;
			long_kind_q <= 4'd0;
			long_cycles_q <= 6'd0;
			long_final_hi_we_q <= 1'b0;
			long_final_lo_we_q <= 1'b0;
			long_final_psw_we_q <= 1'b0;
			long_fpu_result_we_q <= 1'b0;
			long_fpu_psw_we_q <= 1'b0;
			long_fpu_exc_valid_q <= 1'b0;
			chcw_dump_q <= 1'b0;
			chcw_data_phase_q <= 1'b1;
			chcw_index_q <= 7'd0;
			chcw_word_q <= 1'b0;
			chcw_sa_q <= 32'd0;
			chcw_line_q <= 64'd0;
			chcw_tag_q <= 32'd0;
			caxi_active_q <= 1'b0;
			caxi_addr_q <= 32'd0;
			caxi_addr_error_q <= 1'b0;
			caxi_loaded_q <= 32'd0;
			caxi_match_q <= 1'b0;
			caxi_store_data_q <= 32'd0;
			caxi_final_reg_q <= 32'd0;
			caxi_final_psw_q <= 32'd0;
			caxi_final_reg_we_q <= 1'b0;
			bs_op_q <= BS_OP_OR;
			bs_src_addr_q <= 32'd0;
			bs_dst_addr_q <= 32'd0;
			bs_len_q <= 32'd0;
			bs_src_ofs_q <= 5'd0;
			bs_dst_ofs_q <= 5'd0;
			bs_need_src_hi_q <= 1'b0;
			bs_src_second_q <= 1'b0;
			bs_src_lo_q <= 32'd0;
			bs_src_hi_q <= 32'd0;
			bs_src_aligned_q <= 32'd0;
			bs_write_mask_q <= 32'd0;
			bs_write_word_q <= 32'd0;
			bs_type_q <= BS_TYPE1;
			bs_search_q <= 1'b0;
			bs_down_q <= 1'b0;
			bs_search_bit_q <= 1'b0;
			bs_first_partial_q <= 1'b0;
			bs_last_partial_q <= 1'b0;
			bs_total_words_q <= 32'd0;
			bs_word_index_q <= 32'd0;
			bs_seq_active_q <= 1'b0;
			bs_seq_pc_q <= 32'd0;
			bs_cycles_q <= 6'd0;
			bs_wait_action_q <= BSWAIT_START;
			bs_search_result_q <= 7'd0;
			timing_kind_q <= TIMING_LDSR;
			timing_cycles_q <= 6'd0;
			timing_regid_q <= 5'd0;
			timing_value_q <= 32'd0;
			timing_dest_q <= 5'd0;
			reti_restore_pc_q <= 32'd0;
			reti_restore_psw_q <= 32'd0;
			front_cycles_q <= 2'd0;
			hazard_df_producer_q <= 6'd0;
			hazard_wb_producer_q <= 7'd0;
			hazard_df_flags_q <= 1'b0;
			hazard_wb_flags_q <= 1'b0;
			prev_retire_class_q <= RETIRE_CLASS_NONE;
			prev_retire_size_q <= SIZE_B;
			prev_retire_io_q <= 1'b0;
			store_load_hold_q <= 1'b0;
			long_load_overlap_q <= 1'b0;
			long_load_data_valid_q <= 1'b0;
			phi1_seen_q <= 1'b0;
			exec_reg2_q <= 5'd0;
			exec_reg1_q <= 5'd0;
			exec_trap_vec_q <= 5'd0;
			exec_bs_subop_q <= 5'd0;
			exec_ext_subop_q <= 6'd0;
			exec_reg1_val_q <= 32'd0;
			exec_reg2_val_q <= 32'd0;
			exec_seq_pc_q <= 32'd0;
			exec_trace_insn_q <= 16'd0;
			exec_bcond_target_q <= 32'd0;
			exec_condition_q <= 1'b0;
			exec_eff_addr_q <= 32'd0;
			exec_imm_q <= 32'd0;
			exec_sys_read_q <= 32'd0;
			exec_issue_cycles_q <= 6'd0;
			exec_df_producer_q <= 6'd0;
			exec_wb_producer_q <= 7'd0;
			exec_df_flags_q <= 1'b0;
			exec_wb_flags_q <= 1'b0;
			exec_bs_r30_q <= 32'd0;
			exec_bs_r29_q <= 32'd0;
			exec_bs_r28_q <= 32'd0;
			exec_bs_r27_q <= 5'd0;
			exec_bs_r26_q <= 5'd0;
			exec_bs_words_total_q <= 32'd0;
			exec_bs_search_words_total_q <= 32'd0;
			exec_bs_search_first_partial_q <= 1'b0;
			exec_bs_search_last_partial_q <= 1'b0;
			exec_bs_type_q <= BS_TYPE1;
			exec_bs_need_src_hi_q <= 1'b0;
			exec_bs_start_cycles_q <= 6'd0;
			exec_bs_zero_cycles_q <= 6'd0;
			bs_search_count_q <= 32'd0;
			irq_defer_q <= 1'b0;
			cache_irq_pending_q <= 1'b0;
			cache_irq_level_q <= 4'd0;
			nmi_pending_q <= 1'b0;
			nmi_prev_q <= 1'b0;
			fetch_defer_q <= 1'b0;
			write_streak_q <= 2'd0;
			trace_valid_o <= 1'b0;
// synthesis translate_off
`ifndef SYNTHESIS
			// Seed undefined GPRs only in simulation for repeatable tests.
			gpr_r26_shadow_q <= 5'd0;
			gpr_r27_shadow_q <= 5'd0;
			gpr_r28_shadow_q <= 32'd0;
			gpr_r29_shadow_q <= 32'd0;
			gpr_r30_shadow_q <= 32'd0;
			for (int gpr_idx = 1; gpr_idx < 32; gpr_idx = gpr_idx + 1) begin
				u_gpr_file.sim_set_gpr_task(gpr_idx[4:0], 32'd0);
			end
`endif
// synthesis translate_on
		end else begin
			if (!savestate_pause_req_i) begin
				savestate_boundary_pending_q <= 1'b0;
			end else if (trace_valid_o) begin
				savestate_boundary_pending_q <= 1'b1;
			end
			if (savestate_state_wren_i) begin
				// Hold the CPU at the snapshot point while scalar state is restored.
				cache_control_write_we_v =
					(savestate_state_addr_i == 4'd5);
				cache_control_enable_v =
					(savestate_state_addr_i == 4'd5) ?
					savestate_state_wdata_i[1] : cache_enable_q;
				cache_control_pending_v =
					(savestate_state_addr_i == 4'd5) ?
					savestate_state_wdata_i[2] : cache_enable_pending_q;
				state_q <= STATE_SAVESTATE_HOLD;
				savestate_boundary_pending_q <= 1'b0;
				trace_valid_o <= 1'b0;
				// Stop reset-time tag clearing before restoring cache tags.
				init_index_q <= 7'd127;
				ic_data_write_valid_q <= 1'b0;
				ic_tag_write_valid_q <= 1'b0;
				invalidate_line_window_task;
				phi1_seen_q <= 1'b0;
				bs_seq_active_q <= 1'b0;
				case (savestate_state_addr_i)
					4'd0: begin
						pc_q <= {savestate_state_wdata_i[31:1], 1'b0};
						psw_q <= savestate_state_wdata_i[63:32] & PSW_WRITE_MASK;
					end
					4'd1: begin
						eipc_q <= {savestate_state_wdata_i[31:1], 1'b0};
						eipsw_q <= savestate_state_wdata_i[63:32] & PSW_WRITE_MASK;
					end
					4'd2: begin
						fepc_q <= {savestate_state_wdata_i[31:1], 1'b0};
						fepsw_q <= savestate_state_wdata_i[63:32] & PSW_WRITE_MASK;
					end
					4'd3: begin
						ecr_q <= savestate_state_wdata_i[31:0];
						adtre_q <= {savestate_state_wdata_i[63:33], 1'b0};
					end
					4'd4: begin
						sr29_q <= savestate_state_wdata_i[31:0];
						sr31_q <= savestate_state_wdata_i[63:32];
					end
					4'd5: begin
						halted_q <= savestate_state_wdata_i[0];
						irq_defer_q <= savestate_state_wdata_i[3];
						nmi_pending_q <= savestate_state_wdata_i[4];
						nmi_prev_q <= savestate_state_wdata_i[5];
						fetch_defer_q <= savestate_state_wdata_i[6];
						write_streak_q <= savestate_state_wdata_i[8:7];
						prev_retire_class_q <= savestate_state_wdata_i[11:9];
						prev_retire_size_q <= savestate_state_wdata_i[13:12];
						prev_retire_io_q <= savestate_state_wdata_i[14];
						hazard_df_producer_q <= savestate_state_wdata_i[20:15];
						hazard_wb_producer_q <= savestate_state_wdata_i[27:21];
						hazard_df_flags_q <= savestate_state_wdata_i[28];
						hazard_wb_flags_q <= savestate_state_wdata_i[29];
						store_load_hold_q <= savestate_state_wdata_i[30];
						long_load_overlap_q <= savestate_state_wdata_i[31];
						long_load_data_valid_q <= savestate_state_wdata_i[32];
						illegal_q <= savestate_state_wdata_i[33];
						cache_irq_pending_q <= savestate_state_wdata_i[34];
						cache_irq_level_q <= savestate_state_wdata_i[38:35];
					end
					4'd6: begin
						gpr_r26_shadow_q <= savestate_state_wdata_i[4:0];
						gpr_r27_shadow_q <= savestate_state_wdata_i[9:5];
						gpr_r28_shadow_q <= savestate_state_wdata_i[41:10];
					end
					4'd7: begin
						gpr_r29_shadow_q <= savestate_state_wdata_i[31:0];
						gpr_r30_shadow_q <= savestate_state_wdata_i[63:32];
					end
					default: begin
					end
				endcase
			end else begin
				trace_valid_o <= 1'b0;
				if (halted_q) begin
					dbg_reg_data_q <= rf_read_data_b_w;
				end
				if (rf_commit_accept_w) begin
					rf_commit_valid_q <= 1'b0;
					// Update the implicit-register shadow with the mirrored RAM commit.
					gpr_r26_shadow_q <= gpr_r26_visible_w;
					gpr_r27_shadow_q <= gpr_r27_visible_w;
					gpr_r28_shadow_q <= gpr_r28_visible_w;
					gpr_r29_shadow_q <= gpr_r29_visible_w;
					gpr_r30_shadow_q <= gpr_r30_visible_w;
				end
				if (phi1_i && !rf_commit_block_w && (state_q == STATE_CAXI_STORE_REQ)) begin
					// Register CAXI store data before the CE-side launch.
					caxi_store_data_q <= caxi_match_q ? gpr_r30_visible_w : caxi_loaded_q;
				end else if (phi1_i && !rf_commit_block_w && (state_q == STATE_TIMING_WAIT) && (timing_kind_q == TIMING_CAXI) && (timing_cycles_q == 6'd1)) begin
					// Precompute CAXI compare and PSW results on phi1.
					long32_v = exec_reg2_val_q - caxi_loaded_q;
					next_psw_v = psw_q;
					next_psw_v[0] = (long32_v == 32'd0);
					next_psw_v[1] = long32_v[31];
					next_psw_v[2] = sub_overflow_fn(exec_reg2_val_q, caxi_loaded_q, long32_v);
					next_psw_v[3] = sub_borrow_fn(exec_reg2_val_q, caxi_loaded_q);
					caxi_final_reg_q <= caxi_loaded_q;
					caxi_final_psw_q <= next_psw_v & PSW_WRITE_MASK;
					caxi_final_reg_we_q <= (exec_reg2_q != 5'd0);
				end else if (phi1_i && !rf_commit_block_w && (state_q == STATE_LONG) && (long_cycles_q == 6'd2)) begin
					if (long_load_capture_w) begin
						long_load_overlap_q <= 1'b1;
						long_load_data_valid_q <= 1'b0;
						long_load_pc_q <= exec_seq_pc_q;
						long_load_seq_pc_q <=
							(exec_seq_pc_q + instr_len_bytes_fn(line_window_issue_iw_w[31:16])) &
							32'hffff_fffe;
						long_load_iw_q <= line_window_issue_iw_w;
						mem_write_q <= 1'b0;
						mem_io_q <= 1'b0;
						mem_signext_q <=
							(line_window_issue_iw_w[31:26] == OP_LD_B) ||
							(line_window_issue_iw_w[31:26] == OP_LD_H);
						mem_size_q <= instr_mem_size_fn(line_window_issue_iw_w);
						mem_addr_q <= align_addr_fn(
							rf_read_data_a_w + sx16_fn(line_window_issue_iw_w[15:0]),
							instr_mem_size_fn(line_window_issue_iw_w));
						mem_addr_error_q <= address_error_fn(
							rf_read_data_a_w + sx16_fn(line_window_issue_iw_w[15:0]),
							instr_mem_size_fn(line_window_issue_iw_w));
						mem_wdata_q <= 32'd0;
						mem_dest_q <= line_window_issue_iw_w[25:21];
					end
				end else if (phi1_i && !rf_commit_block_w && (state_q == STATE_LONG) && (long_cycles_q == 6'd1)) begin
					long_final_hi_q <= 32'd0;
					long_final_lo_q <= 32'd0;
					long_final_psw_q <= psw_q;
					long_final_hi_we_q <= 1'b0;
					long_final_lo_we_q <= 1'b0;
					long_final_psw_we_q <= 1'b0;
					long_fpu_result_q <= 32'd0;
					long_fpu_psw_q <= psw_q;
					long_fpu_exc_code_q <= 16'd0;
					long_fpu_result_we_q <= 1'b0;
					long_fpu_psw_we_q <= 1'b0;
					long_fpu_exc_valid_q <= 1'b0;
					next_psw_v = psw_q;
					if ((long_kind_q == LONG_MUL) || (long_kind_q == LONG_MULU) ||
						(long_kind_q == LONG_DIV) || (long_kind_q == LONG_DIVU)) begin
						// r30 takes the high word or remainder; reg2 takes the result.
						if (int_engine_done_w) begin
							long_final_hi_q <= int_engine_result_hi_w;
							long_final_lo_q <= int_engine_result_lo_w;
							long_final_hi_we_q <= 1'b1;
							long_final_lo_we_q <= (exec_reg2_q != 5'd0);
							next_psw_v[0] = int_engine_result_zero_w;
							next_psw_v[1] = int_engine_result_sign_w;
							next_psw_v[2] = int_engine_result_overflow_w;
							long_final_psw_q <= next_psw_v & PSW_WRITE_MASK;
							long_final_psw_we_q <= 1'b1;
						end
					end else if (long_kind_q == LONG_MPYHW) begin
						if (int_engine_done_w) begin
							long_final_lo_q <= int_engine_result_lo_w;
							long_final_lo_we_q <= (exec_reg2_q != 5'd0);
						end
					end else if (fp_engine_active_kind_w && fp_engine_done_w) begin
						long_fpu_result_q <= fp_engine_result_w;
						long_fpu_result_we_q <=
							fp_engine_result_we_w && (exec_reg2_q != 5'd0);
						next_psw_v[9:0] =
							(psw_q[9:0] & ~fp_engine_psw_mask_w) |
							(fp_engine_psw_data_w & fp_engine_psw_mask_w);
						long_fpu_psw_q <= next_psw_v & PSW_WRITE_MASK;
						long_fpu_psw_we_q <= (fp_engine_psw_mask_w != 10'd0);
						long_fpu_exc_code_q <= fp_engine_exc_code_w;
						long_fpu_exc_valid_q <= fp_engine_exc_valid_w;
					end
`ifndef SYNTHESIS
					if (fp_engine_active_kind_w && !fp_engine_done_w) begin
						$display("FAIL FP engine missed architectural retirement budget subop=%0d step=%0d",
							exec_ext_subop_q, fp_engine_step_w);
						$fatal(1);
					end
`endif
				end else if (phi1_i && !rf_commit_block_w && !hldrq_i &&
					(state_q == STATE_UCODE_WAIT)) begin
					// Count phi1 only while waiting for the current microstep.
					phi1_seen_q <= 1'b1;
					exec_reg2_q <= exec_iw_q[25:21];
					exec_reg1_q <= exec_iw_q[20:16];
					exec_trap_vec_q <= exec_iw_q[20:16];
					exec_bs_subop_q <= exec_iw_q[20:16];
					exec_ext_subop_q <= exec_ext_subop_raw_w;
`ifndef SYNTHESIS
					// Simulation check of physical register-file addresses.
					// synthesis translate_off
					if ((u_gpr_file.read_addr_a_q !== exec_iw_q[20:16]) ||
						(u_gpr_file.read_addr_b_q !== exec_iw_q[25:21])) begin
						$display("FAIL RF operand address mismatch pc=0x%08x iw=0x%08x a=%0d/%0d b=%0d/%0d launch_state=%0d launch_half=0x%04x launch_ce=%0d launch_phi1=%0d",
							exec_pc_q, exec_iw_q,
							u_gpr_file.read_addr_a_q, exec_iw_q[20:16],
							u_gpr_file.read_addr_b_q, exec_iw_q[25:21],
							sim_rf_launch_state_q, sim_rf_launch_half_q,
							sim_rf_launch_ce_q, sim_rf_launch_phi1_q);
						$fatal(1);
					end
					// synthesis translate_on
`endif
					exec_reg1_val_q <= exec_reg1_val_raw_w;
					exec_reg2_val_q <= exec_reg2_val_raw_w;
					exec_seq_pc_q <= (exec_pc_q + instr_len_bytes_fn(exec_iw_q[31:16])) & 32'hffff_fffe;
					exec_trace_insn_q <= exec_iw_q[31:16];
					exec_bcond_target_q <= bcond_target_raw_w;
					exec_condition_q <= exec_condition_raw_w;
					exec_eff_addr_q <= exec_reg1_val_raw_w + sx16_fn(exec_iw_q[15:0]);
					exec_imm_q <= exec_imm_raw_w;
					exec_sys_read_q <= sysreg_read_fn(exec_iw_q[20:16],
						eipc_q, eipsw_q, fepc_q, fepsw_q, ecr_q, psw_q,
						adtre_q, sr29_q, sr31_q,
						cache_enable_q || cache_enable_pending_q);
					exec_issue_cycles_q <= exec_issue_cycles_raw_w;
					// Silicon unknown: use V800/V830 evidence for V810 DF/WB staging.
					exec_df_producer_q <= retire_df_producer_fn(exec_iw_q);
					exec_wb_producer_q <= retire_wb_producer_fn(exec_iw_q);
					exec_df_flags_q <= retire_df_flags_fn(exec_iw_q);
					exec_wb_flags_q <= retire_wb_flags_fn(exec_iw_q);
					exec_bs_r30_q <= exec_bs_r30_raw_w;
					exec_bs_r29_q <= exec_bs_r29_raw_w;
					exec_bs_r28_q <= exec_bs_r28_raw_w;
					exec_bs_r27_q <= exec_bs_r27_raw_w;
					exec_bs_r26_q <= exec_bs_r26_raw_w;
					exec_bs_words_total_q <= exec_bs_words_total_raw_w;
					exec_bs_search_words_total_q <= exec_bs_search_words_total_raw_w;
					exec_bs_search_first_partial_q <= exec_bs_search_first_partial_raw_w;
					exec_bs_search_last_partial_q <= exec_bs_search_last_partial_raw_w;
					exec_bs_type_q <= exec_bs_type_raw_w;
					exec_bs_need_src_hi_q <= exec_bs_need_src_hi_raw_w;
					if (exec_iw_q[20:19] == 2'b00) begin
						exec_bs_start_cycles_q <= exec_bs_search_start_cycles_raw_w;
						exec_bs_zero_cycles_q <= exec_bs_search_zero_cycles_raw_w;
					end else begin
						exec_bs_start_cycles_q <= exec_bs_arith_start_cycles_raw_w;
						exec_bs_zero_cycles_q <= exec_bs_arith_zero_cycles_raw_w;
					end
					state_q <= STATE_EXEC;
				end else if (phi1_i && !rf_commit_block_w && (state_q == STATE_FRONT_WAIT)) begin
					if (front_cycles_q != 2'd0) begin
						if (front_cycles_q == 2'd1) begin
							state_q <= STATE_UCODE_WAIT;
						end
						front_cycles_q <= front_cycles_q - 2'd1;
					end
				end
				if (ce_i) begin
					gpr_commit_we_v = 5'b00000;
					gpr_commit_addr0_v = 5'd0;
					gpr_commit_addr1_v = 5'd0;
					gpr_commit_addr2_v = 5'd0;
					gpr_commit_addr3_v = 5'd0;
					gpr_commit_addr4_v = 5'd0;
					gpr_commit_data0_v = 32'd0;
					gpr_commit_data1_v = 32'd0;
					gpr_commit_data2_v = 32'd0;
					gpr_commit_data3_v = 32'd0;
					gpr_commit_data4_v = 32'd0;
					psw_commit_we_v = 1'b0;
					psw_commit_data_v = psw_q;
					cache_control_write_we_v = 1'b0;
					cache_control_enable_v = cache_enable_q;
					cache_control_pending_v = cache_enable_pending_q;
					ic_data_write_valid_q <= 1'b0;
					ic_tag_write_valid_q <= 1'b0;
					sysreg_write_we_v = 1'b0;
					sysreg_write_addr_v = 5'd0;
					sysreg_write_data_v = 32'd0;
					sysreg_exception_we_v = 1'b0;
					sysreg_exception_save_ei_v = 1'b0;
					sysreg_exception_save_fe_v = 1'b0;
					sysreg_exception_saved_pc_v = 32'd0;
					sysreg_exception_saved_psw_v = 32'd0;
					sysreg_exception_ecr_v = ecr_q;
					sysreg_exception_psw_we_v = 1'b0;
					sysreg_exception_psw_v = psw_q;
					illegal_q <= 1'b0;
					nmi_prev_q <= nmi_i;
					if ((state_q == STATE_CACHE_INIT) ||
						(state_q == STATE_CACHE_CLEAR) ||
						(state_q == STATE_CHCW_RAM_REQ) ||
						(state_q == STATE_CHCW_RAM_WAIT) ||
						(state_q == STATE_CHCW_RAM_WRITE) ||
						(state_q == STATE_CHCW_BUS_REQ) ||
						(state_q == STATE_CHCW_BUS_WAIT)) begin
						invalidate_line_window_task;
					end
					// Read the following cache line while the accepted instruction executes.
					if ((state_q == STATE_EXEC) && prefetch_lookup_access_w) begin
						next_base_q <= prefetch_lookup_base_w;
						if (prefetch_lookup_hit_w) begin
							next_line_q <= ic_data_q_w;
							next_line_valid_q <= 1'b1;
							next_line_subvalid_q <= ic_tag_q_w[23:22];
						end else begin
							next_line_valid_q <= 1'b0;
							next_line_subvalid_q <= 2'b00;
						end
					end
					if (nmi_i && !nmi_prev_q) begin
						nmi_pending_q <= 1'b1;
					end
					// Silicon unknown: latch the first IRQ level accepted during cache work.
					if (cache_maintenance_w && irq_accept_w && !cache_irq_pending_q) begin
						cache_irq_pending_q <= 1'b1;
						cache_irq_level_q <= irq_level_i;
					end
					if (state_q != STATE_UCODE_WAIT) begin
						phi1_seen_q <= 1'b0;
					end
					if (bs_seq_active_q && (state_q == STATE_LOOKUP_CUR_REQ) && (pc_q != bs_seq_pc_q)) begin
						bs_seq_active_q <= 1'b0;
					end
					// Stop at retire, then drain posted bus and register-file writes.
					if (savestate_hold_enter_w) begin
						state_q <= STATE_SAVESTATE_HOLD;
						savestate_boundary_pending_q <= 1'b0;
						invalidate_line_window_task;
						phi1_seen_q <= 1'b0;
						bs_seq_active_q <= 1'b0;
					end else begin
						case (state_q)
							STATE_CACHE_INIT: begin
								if (init_index_q == 7'd127) begin
									state_q <= fetch_restart_state_w;
								end else begin
									init_index_q <= init_index_q + 7'd1;
									ic_tag_write_valid_q <= 1'b1;
									ic_tag_write_addr_q <= init_index_q + 7'd1;
									ic_tag_write_data_q <= 32'd0;
								end
							end

							STATE_LOOKUP_CUR_REQ: begin
								if (fetch_defer_q) begin
									fetch_defer_q <= 1'b0;
								end else if (hldrq_i) begin
									// Do not advance cache lookup while the last posted write drains.
									if (!caxi_active_q && !active_q) begin
										state_q <= STATE_BUS_HOLD;
									end
								end else if (halted_q) begin
									if (halted_async_exc_kind_w != ASYNC_EXC_NONE) begin
										exc_code_q <= async_exception_code_fn(halted_async_exc_kind_w, irq_accept_level_w);
										exc_restore_pc_q <= {pc_q[31:1], 1'b0};
										state_q <= STATE_EXC_ENTER;
									end
								end else if (front_async_exc_kind_w != ASYNC_EXC_NONE) begin
									exc_code_q <= async_exception_code_fn(front_async_exc_kind_w, irq_accept_level_w);
									exc_restore_pc_q <= {pc_q[31:1], 1'b0};
									state_q <= STATE_EXC_ENTER;
								end else begin
									state_q <= STATE_LOOKUP_CUR_WAIT;
								end
							end

							STATE_BUS_HOLD: begin
								if (!hldrq_i) begin
									state_q <= fetch_restart_state_w;
								end
							end

							STATE_FRONT_WAIT: begin
							end

							STATE_LOOKUP_CUR_WAIT: begin
								// Check HLDRQ again after the synchronous cache read.
								if (hldrq_i) begin
									if (!caxi_active_q && !active_q) begin
										state_q <= STATE_BUS_HOLD;
									end
								end else if (curr_lookup_hit_w) begin
									cur_line_q <= ic_data_q_w;
									cur_base_q <= curr_lookup_base_w;
									cur_line_valid_q <= 1'b1;
									cur_line_subvalid_q <= ic_tag_q_w[23:22];
									if (!next_line_valid_q || (next_base_q != (curr_lookup_base_w + 32'd8))) begin
										next_line_valid_q <= 1'b0;
										next_line_subvalid_q <= 2'b00;
									end
									if (!(instr_needs_second_half_fn(halfword_from_line_fn(ic_data_q_w, pc_q[2:1])) && (pc_q[2:1] == 2'd3))) begin
										fetched_iw_v = build_instr32_fn(ic_data_q_w, 64'd0, pc_q[2:1]);
										accept_issue_task(pc_q, fetched_iw_v,
											hazard_df_producer_q, hazard_wb_producer_q,
											hazard_df_flags_q, hazard_wb_flags_q,
											store_load_hold_q);
									end else begin
										next_base_q <= curr_lookup_base_w + 32'd8;
										next_line_valid_q <= 1'b0;
										next_line_subvalid_q <= 2'b00;
										state_q <= STATE_LOOKUP_NEXT_REQ;
									end
								end else if (ifetch_uncached_w) begin
									state_q <= STATE_IFETCH_REQ;
								end else begin
									fill_base_q <= curr_lookup_base_w;
									fill_index_q <= curr_lookup_index_w;
									fill_line_q <= 64'd0;
									fill_half_q <= 2'd0;
									fill_target_next_q <= 1'b0;
									fill_store_q <= cache_active_w;
									fill_branch_fetch_q <= 1'b1;
									state_q <= STATE_FILL_REQ;
								end
							end

							STATE_LOOKUP_NEXT_REQ: begin
								if (hldrq_i) begin
									if (!caxi_active_q && !active_q) begin
										state_q <= STATE_BUS_HOLD;
									end
								end else begin
									state_q <= STATE_LOOKUP_NEXT_WAIT;
								end
							end

							STATE_LOOKUP_NEXT_WAIT: begin
								if (hldrq_i) begin
									if (!caxi_active_q && !active_q) begin
										state_q <= STATE_BUS_HOLD;
									end
								end else if (next_lookup_hit_w) begin
									next_line_q <= ic_data_q_w;
									next_line_valid_q <= 1'b1;
									next_line_subvalid_q <= ic_tag_q_w[23:22];
									fetched_iw_v = build_instr32_fn(cur_line_q, ic_data_q_w, pc_q[2:1]);
									accept_issue_task(pc_q, fetched_iw_v,
										hazard_df_producer_q, hazard_wb_producer_q,
										hazard_df_flags_q, hazard_wb_flags_q,
										store_load_hold_q);
								end else if (ifetch_uncached_w) begin
									state_q <= STATE_IFETCH_REQ;
								end else begin
									fill_base_q <= next_base_q;
									fill_index_q <= next_lookup_index_w;
									fill_line_q <= 64'd0;
									fill_half_q <= 2'd0;
									fill_target_next_q <= 1'b1;
									fill_store_q <= cache_active_w;
									fill_branch_fetch_q <= 1'b0;
									state_q <= STATE_FILL_REQ;
								end
							end

							STATE_IFETCH_REQ: begin
								if (fetch_defer_q) begin
									fetch_defer_q <= 1'b0;
								end
								if (hldrq_i) begin
									if (!caxi_active_q && !active_q) begin
										state_q <= STATE_BUS_HOLD;
									end
								end else if (halted_q) begin
									if (halted_async_exc_kind_w != ASYNC_EXC_NONE) begin
										exc_code_q <= async_exception_code_fn(halted_async_exc_kind_w, irq_accept_level_w);
										exc_restore_pc_q <= {pc_q[31:1], 1'b0};
										state_q <= STATE_EXC_ENTER;
									end
								end else if (front_async_exc_kind_w != ASYNC_EXC_NONE) begin
									exc_code_q <= async_exception_code_fn(front_async_exc_kind_w, irq_accept_level_w);
									exc_restore_pc_q <= {pc_q[31:1], 1'b0};
									state_q <= STATE_EXC_ENTER;
								end else if (!active_q) begin
									state_q <= STATE_IFETCH_WAIT;
								end
							end

							STATE_IFETCH_WAIT: begin
								if (bus_complete_w) begin
									if (hldrq_i && !caxi_active_q) begin
										// Finish this beat, then discard the partial fetch under hold.
										state_q <= STATE_IFETCH_REQ;
									end else if (instr_needs_second_half_fn(bus_read_data_w[15:0])) begin
										// Save the first halfword before starting the next transfer.
										ifetch_iw_q[31:16] <= bus_read_data_w[15:0];
										state_q <= STATE_IFETCH2_REQ;
									end else begin
										ifetch_iw_q <= {bus_read_data_w[15:0], 16'd0};
										state_q <= STATE_IFETCH_ISSUE;
									end
								end
							end

							STATE_IFETCH2_REQ: begin
								if (hldrq_i) begin
									if (!caxi_active_q && !active_q) begin
										state_q <= STATE_BUS_HOLD;
									end
								end else if (!active_q) begin
									state_q <= STATE_IFETCH2_WAIT;
								end
							end

							STATE_IFETCH2_WAIT: begin
								if (bus_complete_w) begin
									if (hldrq_i && !caxi_active_q) begin
										state_q <= STATE_IFETCH_REQ;
									end else begin
										ifetch_iw_q[15:0] <= bus_read_data_w[15:0];
										state_q <= STATE_IFETCH_ISSUE;
									end
								end
							end

							STATE_IFETCH_ISSUE: begin
								if (hldrq_i) begin
									if (!caxi_active_q && !active_q) begin
										state_q <= STATE_BUS_HOLD;
									end
								end else begin
									accept_issue_task(pc_q, ifetch_iw_q,
										hazard_df_producer_q, hazard_wb_producer_q,
										hazard_df_flags_q, hazard_wb_flags_q,
										store_load_hold_q);
								end
							end

							STATE_IFETCH_DISCARD: begin
								if (bus_complete_w) begin
									if (hldrq_i && !caxi_active_q) begin
										state_q <= STATE_BUS_HOLD;
									end else begin
										state_q <= STATE_IFETCH_REQ;
									end
								end
							end

							STATE_FILL_REQ: begin
								if (hldrq_i) begin
									if (!caxi_active_q && !active_q) begin
										state_q <= STATE_BUS_HOLD;
									end
								end else if (!active_q) begin
									state_q <= STATE_FILL_WAIT;
								end
							end

							STATE_FILL_WAIT: begin
								if (bus_complete_w) begin
									complete_line_v = fill_merged_line_w;
									fill_line_q <= complete_line_v;
									if (fill_last_half_w && fill_store_q) begin
										ic_data_write_valid_q <= 1'b1;
										ic_data_write_addr_q <= fill_index_q;
										ic_data_write_data_q <= complete_line_v;
										ic_tag_write_valid_q <= 1'b1;
										ic_tag_write_addr_q <= fill_index_q;
										ic_tag_write_data_q <= final_fill_tagword_w;
									end
									if (hldrq_i && !caxi_active_q) begin
										// Stop the fill and restart lookup after hold release.
										state_q <= fetch_restart_state_w;
									end else if (fill_last_half_w) begin
										if (fill_target_next_q) begin
											next_line_q <= complete_line_v;
											next_base_q <= fill_base_q;
											next_line_valid_q <= 1'b1;
											next_line_subvalid_q <= 2'b11;
											fetched_iw_v = build_instr32_fn(cur_line_q, complete_line_v, pc_q[2:1]);
											accept_issue_task(pc_q, fetched_iw_v,
												hazard_df_producer_q, hazard_wb_producer_q,
												hazard_df_flags_q, hazard_wb_flags_q,
												store_load_hold_q);
										end else begin
											cur_line_q <= complete_line_v;
											cur_base_q <= fill_base_q;
											cur_line_valid_q <= 1'b1;
											cur_line_subvalid_q <= 2'b11;
											if (!next_line_valid_q || (next_base_q != (fill_base_q + 32'd8))) begin
												next_line_valid_q <= 1'b0;
												next_line_subvalid_q <= 2'b00;
											end
											if (instr_needs_second_half_fn(halfword_from_line_fn(complete_line_v, pc_q[2:1])) && (pc_q[2:1] == 2'd3)) begin
												next_base_q <= fill_base_q + 32'd8;
												next_line_valid_q <= 1'b0;
												next_line_subvalid_q <= 2'b00;
												state_q <= STATE_LOOKUP_NEXT_REQ;
											end else begin
												fetched_iw_v = build_instr32_fn(complete_line_v, 64'd0, pc_q[2:1]);
												accept_issue_task(pc_q, fetched_iw_v,
													hazard_df_producer_q, hazard_wb_producer_q,
													hazard_df_flags_q, hazard_wb_flags_q,
													store_load_hold_q);
											end
										end
									end else begin
										fill_half_q <= fill_half_q + 2'd1;
										state_q <= STATE_FILL_REQ;
									end
								end
							end

							STATE_UCODE_WAIT: begin
								// Drop a resident successor if HLDRQ arrives before operand capture.
								if (hldrq_i && !posted_write_busy_w) begin
									state_q <= STATE_BUS_HOLD;
								end
							end

							STATE_LONG: begin
								if (long_async_exc_kind_w != ASYNC_EXC_NONE) begin
									// On DIV exception, drop an overlapped LD and let its read drain.
									long_load_overlap_q <= 1'b0;
									long_load_data_valid_q <= 1'b0;
									exc_code_q <= async_exception_code_fn(long_async_exc_kind_w, irq_accept_level_w);
									exc_restore_pc_q <= {exec_pc_q[31:1], 1'b0};
									state_q <= STATE_EXC_ENTER;
								end else if (long_cycles_q != 6'd0) begin
									if (long_cycles_q == 6'd1) begin
										trace_valid_o <= 1'b1;
										trace_pc_o <= exec_pc_q;
										trace_insn_o <= exec_trace_insn_q;
										hold_state_v = 1'b0;
										if (long_kind_q == LONG_CLI) begin
											next_psw_v = psw_q;
											next_psw_v[12] = 1'b0;
											request_psw_write_task(PSW_WRITE_MASK, next_psw_v);
										end else if (long_kind_q == LONG_SEI) begin
											next_psw_v = psw_q;
											next_psw_v[12] = 1'b1;
											request_psw_write_task(PSW_WRITE_MASK, next_psw_v);
										end else if (long_kind_q == LONG_XB) begin
											request_gpr_write_task(exec_reg2_q, {exec_reg2_val_q[31:16], exec_reg2_val_q[7:0], exec_reg2_val_q[15:8]});
										end else if (long_kind_q == LONG_CMPF) begin
											if (long_fpu_psw_we_q) begin
												request_psw_write_task(PSW_WRITE_MASK, long_fpu_psw_q);
											end
											if (long_fpu_exc_valid_q) begin
												exc_code_q <= long_fpu_exc_code_q;
												exc_restore_pc_q <= {exec_pc_q[31:1], 1'b0};
												hold_state_v = 1'b1;
												trace_valid_o <= 1'b0;
												state_q <= STATE_EXC_ENTER;
											end
										end else if (long_kind_q == LONG_CVTWS) begin
											if (long_fpu_result_we_q) begin
												request_gpr_write_task(exec_reg2_q, long_fpu_result_q);
											end
											if (long_fpu_psw_we_q) begin
												request_psw_write_task(PSW_WRITE_MASK, long_fpu_psw_q);
											end
										end else if ((long_kind_q == LONG_CVTSW) ||
											(long_kind_q == LONG_TRNCSW) ||
											(long_kind_q == LONG_ADDF)) begin
											// CVT.SW, TRNC.SW, and the shared ADDF-family entry
											// commit a result, PSW flags, and a possible trap.
											if (long_fpu_result_we_q) begin
												request_gpr_write_task(exec_reg2_q, long_fpu_result_q);
											end
											if (long_fpu_psw_we_q) begin
												request_psw_write_task(PSW_WRITE_MASK, long_fpu_psw_q);
											end
											if (long_fpu_exc_valid_q) begin
												exc_code_q <= long_fpu_exc_code_q;
												exc_restore_pc_q <= {exec_pc_q[31:1], 1'b0};
												hold_state_v = 1'b1;
												trace_valid_o <= 1'b0;
												state_q <= STATE_EXC_ENTER;
											end
										end else if (long_kind_q == LONG_REV) begin
											if (int_engine_done_w) begin
												request_gpr_write_task(
													exec_reg2_q, int_engine_result_lo_w);
											end
										end else if (long_kind_q == LONG_MPYHW) begin
											if (long_final_lo_we_q) begin
												request_gpr_write_task(exec_reg2_q, long_final_lo_q);
											end
										end else begin
											// MUL, MULU, DIV, and DIVU share one commit shape:
											// r30 high word or remainder, reg2 result, and PSW.
											if (long_final_hi_we_q) begin
												request_gpr_write_task(5'd30, long_final_hi_q);
											end
											if (long_final_lo_we_q) begin
												request_gpr_write_task(exec_reg2_q, long_final_lo_q);
											end
											if (long_final_psw_we_q) begin
												request_psw_write_task(PSW_WRITE_MASK, long_final_psw_q);
											end
										end

											if (!hold_state_v) begin
												pc_q <= exec_seq_pc_q;
												hazard_df_producer_q <= exec_df_producer_q;
												// The retiring commit forwards this result to its successor.
												hazard_wb_producer_q <= 7'd0;
												hazard_df_flags_q <= exec_df_flags_q;
												hazard_wb_flags_q <= exec_wb_flags_q;
												write_streak_q <= 2'd0;
												update_retire_history_task(RETIRE_CLASS_LONG, SIZE_W, 1'b0);
												if (long_load_overlap_q) begin
													// The overlapped LD address launched one clock earlier.
													if (bus_complete_w) begin
														long_load_data_valid_q <= 1'b1;
														long_load_data_q <= mem_read_data_w;
													end
													pc_q <= long_load_pc_q;
													exec_pc_q <= long_load_pc_q;
													exec_iw_q <= long_load_iw_q;
													exec_seq_pc_q <= long_load_seq_pc_q;
													exec_trace_insn_q <= long_load_iw_q[31:16];
													state_q <= STATE_LONG_LOAD_WAIT;
												end else begin
													// Reuse the resident cache window after normal long-op completion.
													if (resident_sequential_successor_ready_w) begin
														accept_resident_successor_task(
															exec_df_producer_q, 7'd0,
															exec_df_flags_q, exec_wb_flags_q,
															1'b0);
													end else begin
														fetch_defer_q <= 1'b1;
														state_q <= fetch_restart_state_w;
													end
												end
											end
									end

									// The enclosing arm already checked long_cycles_q != 0.
									long_cycles_q <= long_cycles_q - 6'd1;
								end
							end

							STATE_LONG_LOAD_WAIT: begin
								if (long_load_data_valid_q || bus_complete_w) begin
									request_gpr_write_task(
										mem_dest_q,
										long_load_data_valid_q ? long_load_data_q : mem_read_data_w);
									retire_trace_task(6'd0, wb_reg_producer_fn(mem_dest_q),
										1'b0, 1'b0, 2'd0);
									update_retire_history_task(RETIRE_CLASS_LOAD, mem_size_q, 1'b0);
									long_load_overlap_q <= 1'b0;
									long_load_data_valid_q <= 1'b0;
									pc_q <= exec_seq_pc_q;
									if (resident_sequential_successor_ready_w) begin
										accept_resident_successor_task(
											6'd0, wb_reg_producer_fn(mem_dest_q),
											1'b0, 1'b0, 1'b0);
									end else begin
										state_q <= fetch_restart_state_w;
									end
								end
							end

							STATE_EXEC: begin
								if (hldrq_i) begin
									hold_state_v = 1'b1;
									if (!posted_write_busy_w) begin
										state_q <= STATE_BUS_HOLD;
									end
								end else begin
									next_pc_v = exec_seq_pc_q;
									next_psw_v = exec_alu_psw_w;
									next_gpr_v = exec_result_q;
									next_sys_v = exec_result_q;
									chcw_write_v = exec_reg2_val_q;
									hold_state_v = 1'b0;

									case (ucode_kind_w)
										MK_NOP: begin
										end
										MK_ALU: begin
											next_gpr_v = exec_alu_result_w;
											if (ucode_pc_from_result_w) begin
												next_pc_v = {exec_alu_result_w[31:1], 1'b0};
											end
										end

										MK_LDSR: begin
											next_sys_v = exec_reg2_val_q;
											if (exec_reg1_q == SYS_CHCW) begin
												// CHCW maintenance runs to completion before interrupts.
												clear_count_v = chcw_write_v[19:8];
												// Hardware accepts ICE+ICC together to clear and enable cache.
												if ((chcw_write_v[0] && !chcw_write_v[4] && !chcw_write_v[5] &&
													(chcw_write_v[31:20] < 12'd128) && (clear_count_v != 12'd0)) ||
													(!chcw_write_v[0] && (chcw_write_v[4] ^ chcw_write_v[5]))) begin
													request_cache_mode_task(chcw_write_v[1]);
													if (chcw_write_v[0]) begin
														clear_index_q <= chcw_write_v[26:20];
														if ((chcw_write_v[31:20] + clear_count_v - 12'd1) >= 12'd128) begin
															clear_last_q <= 7'd127;
														end else begin
															clear_last_q <= chcw_write_v[26:20] + clear_count_v[6:0] - 7'd1;
														end
														ic_tag_write_valid_q <= 1'b1;
														ic_tag_write_addr_q <= chcw_write_v[26:20];
														ic_tag_write_data_q <= 32'd0;
														hold_state_v = 1'b1;
														state_q <= STATE_CACHE_CLEAR;
													end else begin
														chcw_dump_q <= chcw_write_v[4];
														chcw_data_phase_q <= 1'b1;
														chcw_index_q <= 7'd0;
														chcw_word_q <= 1'b0;
														chcw_sa_q <= {chcw_write_v[31:8], 8'd0};
														chcw_line_q <= 64'd0;
														chcw_tag_q <= 32'd0;
														hold_state_v = 1'b1;
														state_q <= chcw_write_v[4] ? STATE_CHCW_RAM_REQ : STATE_CHCW_BUS_REQ;
													end
												end else begin
													timing_kind_q <= TIMING_LDSR;
													timing_cycles_q <= cycles_after_launch_fn(sys_timing_cycles_fn(TIMING_LDSR));
													timing_regid_q <= exec_reg1_q;
													timing_value_q <= chcw_invalid_combination_fn(chcw_write_v) ?
														{30'd0, (cache_enable_q || cache_enable_pending_q), 1'b0} :
														next_sys_v;
													hold_state_v = 1'b1;
													state_q <= STATE_TIMING_WAIT;
												end
											end else begin
												timing_kind_q <= TIMING_LDSR;
												timing_cycles_q <= cycles_after_launch_fn(sys_timing_cycles_fn(TIMING_LDSR));
												timing_regid_q <= exec_reg1_q;
												timing_value_q <= next_sys_v;
												hold_state_v = 1'b1;
												state_q <= STATE_TIMING_WAIT;
											end
										end

										MK_STSR: begin
											timing_kind_q <= TIMING_STSR;
											timing_cycles_q <= cycles_after_launch_fn(
												sys_timing_cycles_fn(TIMING_STSR));
											timing_value_q <= exec_sys_read_q;
											timing_dest_q <= exec_reg2_q;
											hold_state_v = 1'b1;
											state_q <= STATE_TIMING_WAIT;
										end

										MK_BRANCH: begin
											if (ucode_pc_from_bcond_w && exec_condition_q) begin
												next_pc_v = {exec_bcond_target_q[31:1], 1'b0};
											end
										end

										MK_MEM: begin
											mem_write_q <= ucode_mem_write_w;
											mem_io_q <= ucode_mem_io_w;
											mem_signext_q <= ucode_mem_signext_w;
											mem_size_q <= ucode_mem_size_w;
											mem_addr_q <= exec_mem_addr_w;
											mem_addr_error_q <= address_error_fn(
												exec_eff_addr_q, ucode_mem_size_w);
											mem_wdata_q <= exec_reg2_val_q;
											mem_dest_q <= exec_reg2_q;
											hold_state_v = 1'b1;
											if (ucode_mem_write_w) begin
												if (bus_launch_accept_w) begin
													// Post the final store beat to match predecessor-dependent timing.
													retire_store_task(ucode_mem_size_w, ucode_mem_io_w);
												end else begin
													state_q <= STATE_MEM_REQ;
												end
											end else begin
												if (bus_launch_accept_w) begin
													state_q <= STATE_MEM_WAIT;
												end else begin
													state_q <= STATE_MEM_REQ;
												end
											end
										end

										MK_CAXI: begin
											caxi_active_q <= 1'b1;
											caxi_addr_q <= exec_mem_addr_w;
											caxi_addr_error_q <= address_error_fn(exec_eff_addr_q, SIZE_W);
											hold_state_v = 1'b1;
											state_q <= STATE_CAXI_REQ;
										end

										MK_BITSTR: begin
											// Process one bit-string word per step so interrupts may enter between steps.
											bs_type_q <= exec_bs_type_q;
											bs_search_q <= (exec_bs_subop_q[4:3] == 2'b00);
											bs_down_q <= exec_bs_subop_q[0];
											bs_search_bit_q <= exec_bs_subop_q[1];
											bs_first_partial_q <= exec_bs_search_first_partial_q;
											bs_last_partial_q <= exec_bs_search_last_partial_q;
											bs_total_words_q <= exec_bs_words_total_q;
											bs_word_index_q <= 32'd1;
											bs_seq_pc_q <= exec_pc_q;
											if (exec_bs_subop_q[4:3] != 2'b00) begin
												case (exec_bs_subop_q)
													SUBOP_ORBSU:   bs_op_q <= BS_OP_OR;
													SUBOP_ANDBSU:  bs_op_q <= BS_OP_AND;
													SUBOP_XORBSU:  bs_op_q <= BS_OP_XOR;
													SUBOP_MOVBSU:  bs_op_q <= BS_OP_MOV;
													SUBOP_ORNBSU:  bs_op_q <= BS_OP_ORN;
													SUBOP_ANDNBSU: bs_op_q <= BS_OP_ANDN;
													SUBOP_XORNBSU: bs_op_q <= BS_OP_XORN;
													default:       bs_op_q <= BS_OP_NOT;
												endcase
											end
											bs_src_addr_q <= {bs_launch_src_addr_w[31:2], 2'b00};
											bs_dst_addr_q <= {bs_launch_dst_addr_w[31:2], 2'b00};
											bs_len_q <= bs_launch_len_w;
											bs_src_ofs_q <= bs_launch_src_ofs_w;
											bs_dst_ofs_q <= bs_launch_dst_ofs_w;
											bs_search_count_q <= bs_launch_dst_addr_w;
											if (exec_bs_subop_q[4:3] == 2'b00) begin
												bs_total_words_q <= exec_bs_search_words_total_q;
												bs_need_src_hi_q <= 1'b0;
												request_psw_write_task(PSW_Z_MASK, PSW_Z_MASK);
											end else begin
												bs_need_src_hi_q <= exec_bs_need_src_hi_q;
											end
											bs_src_second_q <= 1'b0;
											bs_src_lo_q <= 32'd0;
											bs_src_hi_q <= 32'd0;
											bs_src_aligned_q <= 32'd0;
											bs_write_mask_q <= 32'd0;
											bs_write_word_q <= 32'd0;
											if (bs_launch_len_w == 32'd0) begin
												// Publish zero-length normalization atomically at retire.
												bs_seq_active_q <= 1'b0;
												bs_cycles_q <= exec_bs_zero_cycles_q;
												bs_wait_action_q <= BSWAIT_RETIRE;
												hold_state_v = 1'b1;
												state_q <= STATE_BS_TIMING_WAIT;
											end else if (bs_first_launch_w && (exec_bs_start_cycles_q != 6'd0)) begin
												bs_seq_active_q <= 1'b1;
												bs_cycles_q <= exec_bs_start_cycles_q;
												bs_wait_action_q <= BSWAIT_START;
												hold_state_v = 1'b1;
												state_q <= STATE_BS_TIMING_WAIT;
											end else begin
												bs_seq_active_q <= 1'b1;
												hold_state_v = 1'b1;
												state_q <= STATE_BS_SRC_REQ;
											end
										end

										MK_HALT: begin
											if (ucode_halt_w) begin
												if (halted_async_exc_kind_w != ASYNC_EXC_NONE) begin
													exc_code_q <= async_exception_code_fn(halted_async_exc_kind_w, irq_accept_level_w);
													exc_restore_pc_q <= {exec_seq_pc_q[31:1], 1'b0};
													hold_state_v = 1'b1;
													state_q <= STATE_EXC_ENTER;
												end else begin
													halted_q <= 1'b1;
													fetch_defer_q <= 1'b1;
												end
											end
										end

										MK_TRAP: begin
											exc_code_q <= 16'hffa0 + {11'd0, exec_trap_vec_q};
											exc_restore_pc_q <= {next_pc_v[31:1], 1'b0};
											// TRAP waits for its documented 15 cycles before entry.
											timing_kind_q <= TIMING_TRAP;
											timing_cycles_q <= cycles_after_launch_fn(sys_timing_cycles_fn(TIMING_TRAP));
											hold_state_v = 1'b1;
											state_q <= STATE_TIMING_WAIT;
										end

										MK_RETI: begin
											// RETI waits 10 cycles, then commits the saved PC and PSW.
											if ((psw_q & PSW_NP_MASK) != 32'd0) begin
												reti_restore_pc_q <= {fepc_q[31:1], 1'b0};
												reti_restore_psw_q <= fepsw_q & PSW_WRITE_MASK;
											end else begin
												reti_restore_pc_q <= {eipc_q[31:1], 1'b0};
												reti_restore_psw_q <= eipsw_q & PSW_WRITE_MASK;
											end
											// Clear hazard masks before the RETI wait.
											hazard_df_producer_q <= 6'd0;
											hazard_wb_producer_q <= 7'd0;
											hazard_df_flags_q <= 1'b0;
											hazard_wb_flags_q <= 1'b0;
											irq_defer_q <= 1'b1;
											fetch_defer_q <= 1'b1;
											halted_q <= 1'b0;
											write_streak_q <= 2'd0;
											timing_kind_q <= TIMING_RETI;
											timing_cycles_q <= cycles_after_launch_fn(sys_timing_cycles_fn(TIMING_RETI));
											hold_state_v = 1'b1;
											state_q <= STATE_TIMING_WAIT;
										end

										MK_LONG: begin
											case (ucode_alu_op_w)
												// Fixed-count long operations launch with their table cycles.
												LONG_CLI,
												LONG_SEI,
												LONG_XB,
												LONG_REV,
												LONG_MPYHW,
												LONG_MUL,
												LONG_MULU: begin
													long_kind_q <= ucode_alu_op_w;
													long_cycles_q <= cycles_after_launch_fn(long_issue_cycles_fn(ucode_alu_op_w));
													hold_state_v = 1'b1;
													state_q <= STATE_LONG;
												end

												LONG_XH: begin
													// XH uses normal retire forwarding to its resident successor.
													request_gpr_write_task(exec_reg2_q, {exec_reg2_val_q[15:0], exec_reg2_val_q[31:16]});
												end

												// Floating-point launches carry issue-computed cycles.
												LONG_CMPF,
												LONG_CVTWS: begin
													long_kind_q <= ucode_alu_op_w;
													long_cycles_q <= cycles_after_launch_fn(exec_issue_cycles_q);
													hold_state_v = 1'b1;
													state_q <= STATE_LONG;
												end

												LONG_CVTSW,
												LONG_TRNCSW: begin
													long_kind_q <= (exec_ext_subop_q == SUBOP_TRNCSW) ? LONG_TRNCSW : LONG_CVTSW;
													long_cycles_q <= cycles_after_launch_fn(exec_issue_cycles_q);
													hold_state_v = 1'b1;
													state_q <= STATE_LONG;
												end

												LONG_ADDF,
												LONG_SUBF: begin
													long_kind_q <= LONG_ADDF;
													long_cycles_q <= cycles_after_launch_fn(exec_issue_cycles_q);
													hold_state_v = 1'b1;
													state_q <= STATE_LONG;
												end

												LONG_DIV,
												LONG_DIVU: begin
													if (exec_reg1_val_q == 32'd0) begin
														exc_code_q <= EXC_CODE_ZERODIV;
														exc_restore_pc_q <= {exec_pc_q[31:1], 1'b0};
														hold_state_v = 1'b1;
														state_q <= STATE_EXC_ENTER;
													end else begin
														long_kind_q <= ucode_alu_op_w;
														long_cycles_q <= cycles_after_launch_fn(long_issue_cycles_fn(ucode_alu_op_w));
														hold_state_v = 1'b1;
														state_q <= STATE_LONG;
													end
												end

												default: begin
													exc_code_q <= EXC_CODE_ILLEGAL;
													exc_restore_pc_q <= {exec_pc_q[31:1], 1'b0};
													hold_state_v = 1'b1;
													state_q <= STATE_EXC_ENTER;
												end
											endcase
										end

										// MK_ILL and unmapped kinds raise the illegal-opcode trap.
										default: begin
											illegal_q <= 1'b1;
											exc_code_q <= EXC_CODE_ILLEGAL;
											exc_restore_pc_q <= {exec_pc_q[31:1], 1'b0};
											hold_state_v = 1'b1;
											state_q <= STATE_EXC_ENTER;
										end
									endcase

									if (!hold_state_v) begin
										if (ucode_write_gpr_w) begin
											request_gpr_write_task(exec_reg2_q, next_gpr_v);
										end

										if (ucode_write_link_w) begin
											request_gpr_write_task(5'd31, exec_seq_pc_q);
										end

										if (ucode_write_psw_w) begin
											request_psw_write_task(PSW_WRITE_MASK, next_psw_v);
										end

										if (ucode_end_w) begin
											retire_trace_task(exec_df_producer_q, exec_wb_producer_q,
												exec_df_flags_q, exec_wb_flags_q, 2'd0);
											update_retire_history_task(RETIRE_CLASS_OTHER, SIZE_H, 1'b0);
											pc_q <= {next_pc_v[31:1], 1'b0};
											// Admit a resident successor at retire and forward its operands.
											if (!ucode_halt_w &&
												!ucode_control_redirect_w &&
												(front_async_exc_kind_w == ASYNC_EXC_NONE) &&
												(((psw_q & PSW_AE_MASK) == 32'd0) ||
												 (next_pc_v[31:1] != adtre_q[31:1])) &&
												({next_pc_v[31:1], 1'b0} == exec_seq_pc_q) &&
												phi1_seen_q &&
												line_window_issue_ready_w &&
												!hldrq_i) begin
												accept_issue_task(exec_seq_pc_q, line_window_issue_iw_w,
													exec_df_producer_q, exec_wb_producer_q,
													exec_df_flags_q, exec_wb_flags_q,
													1'b0);
												if (line_window_issue_from_next_w) begin
													cur_line_q <= next_line_q;
													cur_base_q <= next_base_q;
													cur_line_valid_q <= 1'b1;
													cur_line_subvalid_q <= next_line_subvalid_q;
													next_line_valid_q <= 1'b0;
													next_line_subvalid_q <= 2'b00;
												end
											end else if (!ucode_halt_w &&
												(front_async_exc_kind_w == ASYNC_EXC_NONE) &&
												(((psw_q & PSW_AE_MASK) == 32'd0) ||
												 (next_pc_v[31:1] != adtre_q[31:1])) &&
												phi1_seen_q &&
												(fetch_restart_state_w == STATE_IFETCH_REQ)) begin
												if (exec_wrong_path_word_fetch_w) begin
													state_q <= STATE_IFETCH_DISCARD;
												end else begin
													state_q <= STATE_IFETCH_WAIT;
												end
											end else begin
												state_q <= fetch_restart_state_w;
											end
										end else begin
											exec_result_q <= exec_alu_result_w;
											exec_uop_q <= ucode_next_w;
											state_q <= STATE_UCODE_WAIT;
										end
									end
								end
							end

							STATE_EXC_ENTER: begin
								// Silicon unknown: exception entry cycle count is unpublished. Commit
								// the decoded plan, then use normal cache and fetch timing.
								if (exc_entry_fatal_w) begin
									if (!exc_is_interrupt_w && (exec_iw_q[31:26] == OP_TRAP)) begin
										trace_valid_o <= 1'b1;
										trace_pc_o <= exec_pc_q;
										trace_insn_o <= exec_trace_insn_q;
									end
									fatal_index_q <= 2'd0;
									state_q <= STATE_FATAL_REQ;
								end else begin
									sysreg_exception_we_v = 1'b1;
									sysreg_exception_save_ei_v = exc_entry_save_ei_w;
									sysreg_exception_save_fe_v = exc_entry_save_fe_w;
									sysreg_exception_saved_pc_v = exc_entry_saved_pc_w;
									sysreg_exception_saved_psw_v = exc_entry_saved_psw_w;
									sysreg_exception_ecr_v = exc_entry_next_ecr_w;
									sysreg_exception_psw_we_v = exc_entry_psw_write_w;
									sysreg_exception_psw_v = exc_entry_next_psw_w;
									if (exc_entry_pc_write_w) begin
										pc_q <= exc_handler_w;
									end
									if (exc_entry_clear_halt_w) begin
										halted_q <= 1'b0;
									end
									if (exc_entry_clear_nmi_pending_w) begin
										nmi_pending_q <= 1'b0;
									end
									if (exc_is_interrupt_w && held_irq_accept_w) begin
										cache_irq_pending_q <= 1'b0;
									end
									if (!exc_is_interrupt_w && (exec_iw_q[31:26] == OP_TRAP)) begin
										trace_valid_o <= 1'b1;
										trace_pc_o <= exec_pc_q;
										trace_insn_o <= exec_trace_insn_q;
									end
									hazard_df_producer_q <= 6'd0;
									hazard_wb_producer_q <= 7'd0;
									hazard_df_flags_q <= 1'b0;
									hazard_wb_flags_q <= 1'b0;
									store_load_hold_q <= 1'b0;
									write_streak_q <= 2'd0;
									fetch_defer_q <= 1'b1;
									state_q <= fetch_restart_state_w;
								end
							end

							STATE_FATAL_REQ: begin
								if (!active_q) begin
									state_q <= STATE_FATAL_WAIT;
								end
							end

							STATE_FATAL_WAIT: begin
								if (bus_complete_w) begin
									if (fatal_index_q == 2'd2) begin
										halted_q <= 1'b1;
										state_q <= fetch_restart_state_w;
									end else begin
										fatal_index_q <= fatal_index_q + 2'd1;
										state_q <= STATE_FATAL_REQ;
									end
								end
							end

							STATE_CACHE_CLEAR: begin
								if (clear_index_q == clear_last_q) begin
									retire_trace_task(6'd0, 7'd0, 1'b0, 1'b0, 2'd0);
									pc_q <= exec_seq_pc_q;
									state_q <= fetch_restart_state_w;
								end else begin
									clear_index_q <= clear_index_q + 7'd1;
									ic_tag_write_valid_q <= 1'b1;
									ic_tag_write_addr_q <= clear_index_q + 7'd1;
									ic_tag_write_data_q <= 32'd0;
								end
							end

							// A CHCW dump or restore walks 128 eight-byte lines, then 128 tags.
							STATE_CHCW_RAM_REQ: begin
								state_q <= STATE_CHCW_RAM_WAIT;
							end

							STATE_CHCW_RAM_WAIT: begin
								if (chcw_data_phase_q) begin
									chcw_line_q <= ic_data_q_w;
								end else begin
									chcw_tag_q <= ic_tag_q_w;
								end
								state_q <= STATE_CHCW_BUS_REQ;
							end

							STATE_CHCW_BUS_REQ: begin
								if (!active_q) begin
									state_q <= STATE_CHCW_BUS_WAIT;
								end
							end

							STATE_CHCW_BUS_WAIT: begin
								if (bus_complete_w) begin
									if (active_write_q) begin
										if (chcw_data_phase_q) begin
											if (!chcw_word_q) begin
												chcw_word_q <= 1'b1;
												state_q <= STATE_CHCW_BUS_REQ;
											end else begin
												chcw_word_q <= 1'b0;
												if (chcw_index_q == 7'd127) begin
													chcw_data_phase_q <= 1'b0;
													chcw_index_q <= 7'd0;
												end else begin
													chcw_index_q <= chcw_index_q + 7'd1;
												end
												state_q <= STATE_CHCW_RAM_REQ;
											end
										end else begin
											if (chcw_index_q == 7'd127) begin
												retire_trace_task(6'd0, 7'd0,
													1'b0, 1'b0, 2'd0);
												pc_q <= exec_seq_pc_q;
												state_q <= fetch_restart_state_w;
											end else begin
												chcw_index_q <= chcw_index_q + 7'd1;
												state_q <= STATE_CHCW_RAM_REQ;
											end
										end
									end else begin
										if (chcw_data_phase_q) begin
											if (!chcw_word_q) begin
												chcw_line_q[31:0] <= bus_read_data_w;
												chcw_word_q <= 1'b1;
												state_q <= STATE_CHCW_BUS_REQ;
											end else begin
												chcw_line_q[63:32] <= bus_read_data_w;
												chcw_word_q <= 1'b0;
												ic_data_write_valid_q <= 1'b1;
												ic_data_write_addr_q <= chcw_index_q;
												ic_data_write_data_q <=
													{bus_read_data_w, chcw_line_q[31:0]};
												state_q <= STATE_CHCW_RAM_WRITE;
											end
										end else begin
											chcw_tag_q <= bus_read_data_w;
											ic_tag_write_valid_q <= 1'b1;
											ic_tag_write_addr_q <= chcw_index_q;
											ic_tag_write_data_q <= bus_read_data_w;
											state_q <= STATE_CHCW_RAM_WRITE;
										end
									end
								end
							end

							STATE_CHCW_RAM_WRITE: begin
								if (chcw_data_phase_q) begin
									if (chcw_index_q == 7'd127) begin
										chcw_data_phase_q <= 1'b0;
										chcw_index_q <= 7'd0;
									end else begin
										chcw_index_q <= chcw_index_q + 7'd1;
									end
									state_q <= STATE_CHCW_BUS_REQ;
								end else begin
									if (chcw_index_q == 7'd127) begin
										retire_trace_task(6'd0, 7'd0, 1'b0, 1'b0, 2'd0);
										pc_q <= exec_seq_pc_q;
										state_q <= fetch_restart_state_w;
									end else begin
										chcw_index_q <= chcw_index_q + 7'd1;
										state_q <= STATE_CHCW_BUS_REQ;
									end
								end
							end

							STATE_CAXI_REQ: begin
								if (!active_q) begin
									state_q <= STATE_CAXI_WAIT;
								end
							end

							STATE_CAXI_WAIT: begin
								if (bus_complete_w) begin
									caxi_loaded_q <= bus_read_data_w;
									caxi_match_q <= (exec_reg2_val_q == bus_read_data_w);
									state_q <= STATE_CAXI_STORE_REQ;
								end
							end

							STATE_CAXI_STORE_REQ: begin
								if (!active_q) begin
									state_q <= STATE_CAXI_STORE_WAIT;
								end
							end

							STATE_CAXI_STORE_WAIT: begin
								if (bus_complete_w) begin
									timing_kind_q <= TIMING_CAXI;
									timing_cycles_q <= siz16b_q ? 6'd19 : 6'd13;
									state_q <= STATE_TIMING_WAIT;
								end
							end

							STATE_BS_SRC_REQ: begin
								if (!active_q) begin
									state_q <= STATE_BS_SRC_WAIT;
								end
							end

							STATE_BS_SRC_WAIT: begin
								if (bus_complete_w) begin
									if (!bs_src_second_q) begin
										bs_src_lo_q <= bus_read_data_w;
										if (bs_need_src_hi_q) begin
											bs_src_second_q <= 1'b1;
											state_q <= STATE_BS_SRC_REQ;
										end else if (bs_search_q) begin
											// Combinational match-any check; the priority encoder registers
											// its result later in STATE_BS_SEARCH_SCAN.
											bs_search_found_v = bs_search_match_any_fn(
												bus_read_data_w,
												bs_src_ofs_q,
												bs_search_step_w,
												bs_search_bit_q,
												bs_down_q);
											if (!bs_search_found_v &&
												(((bs_search_partial_len_w != 32'd0) && (bs_search_resume_cycles_w == 6'd0)) ||
												 ((bs_search_partial_len_w == 32'd0) &&
												  (bs_search_complete_cycles_fn(bs_total_words_q, bs_down_q, siz16b_q, 1'b0, 5'd0) == 6'd0)))) begin
												// A zero-tail miss advances the fixed full-step checkpoint directly.
												bs_search_next_addr_v = bs_search_addr_advance_fn(bs_src_addr_q, bs_src_ofs_q, bs_search_step_w, bs_down_q);
												bs_search_next_ofs_v = bs_search_ofs_advance_fn(bs_src_ofs_q, bs_search_step_w, bs_down_q);
												bs_src_addr_q <= bs_search_next_addr_v;
												bs_src_ofs_q <= bs_search_next_ofs_v;
												bs_len_q <= bs_search_partial_len_w;
												bs_search_count_q <= bs_search_count_q + {26'd0, bs_search_step_w};
												request_psw_write_task(PSW_Z_MASK, PSW_Z_MASK);
												if (bs_search_partial_len_w != 32'd0) begin
													bs_seq_active_q <= 1'b1;
													bs_word_index_q <= bs_word_index_q + 32'd1;
													bs_wait_action_q <= BSWAIT_RESUME;
													bs_cycles_q <= 6'd0;
													state_q <= STATE_LOOKUP_CUR_REQ;
												end else begin
													bs_seq_active_q <= 1'b0;
													bs_wait_action_q <= BSWAIT_RETIRE;
													bs_cycles_q <= 6'd0;
													// Publish the computed checkpoint on this retire edge.
													request_gpr_write_task(5'd30, bs_search_next_addr_v);
													request_gpr_write_task(5'd29, bs_search_count_q + {26'd0, bs_search_step_w});
													request_gpr_write_task(5'd28, bs_search_partial_len_w);
													request_gpr_write_task(5'd27, {27'd0, bs_search_next_ofs_v});
													retire_trace_task(6'd0, WB_PRODUCER_BS_GROUP,
														1'b0, 1'b1, 2'd0);
													update_retire_history_task(RETIRE_CLASS_LONG, SIZE_W, 1'b0);
													fetch_defer_q <= 1'b1;
													pc_q <= exec_seq_pc_q;
													state_q <= fetch_restart_state_w;
												end
											end else if (bs_search_found_v) begin
												state_q <= STATE_BS_SEARCH_SCAN;
											end else begin
												bs_search_result_q <= {1'b0, bs_search_step_w};
												state_q <= STATE_BS_SEARCH_COMMIT;
											end
										end else begin
											bs_src_hi_q <= 32'd0;
											state_q <= STATE_BS_DST_REQ;
										end
									end else begin
										bs_src_hi_q <= bus_read_data_w;
										bs_src_second_q <= 1'b0;
										state_q <= STATE_BS_DST_REQ;
									end
								end
							end

							STATE_BS_SEARCH_SCAN: begin
								// Register the balanced priority-encoder result before checkpoint math.
								bs_search_result_q <= bs_search_result_fn(
									bs_src_lo_q,
									bs_src_ofs_q,
									bs_search_step_w,
									bs_search_bit_q,
									bs_down_q);
								state_q <= STATE_BS_SEARCH_COMMIT;
							end

							STATE_BS_SEARCH_COMMIT: begin
								// Use the registered search result and adjust the existing timing tail.
								bs_search_result_v = bs_search_result_q;
								bs_search_found_v = bs_search_result_v[6];
								bs_search_skip_v = bs_search_result_v[5:0];
								bs_search_advance_v = bs_search_found_v ? (bs_search_skip_v + 6'd1) : bs_search_step_w;
								bs_search_next_addr_v = bs_search_addr_advance_fn(bs_src_addr_q, bs_src_ofs_q, bs_search_advance_v, bs_down_q);
								bs_search_next_ofs_v = bs_search_ofs_advance_fn(bs_src_ofs_q, bs_search_advance_v, bs_down_q);
								bs_search_next_len_v = bs_len_q - {26'd0, bs_search_advance_v};
								bs_src_addr_q <= bs_search_next_addr_v;
								bs_src_ofs_q <= bs_search_next_ofs_v;
								bs_len_q <= bs_search_next_len_v;
								if (bs_search_found_v) begin
									bs_search_count_q <= bs_search_count_q + {26'd0, bs_search_skip_v};
									request_psw_write_task(PSW_Z_MASK, 32'd0);
									bs_seq_active_q <= 1'b0;
									bs_wait_action_q <= BSWAIT_RETIRE;
									bs_search_tail_v = bs_search_complete_cycles_fn(
										bs_total_words_q,
										bs_down_q,
										siz16b_q,
										1'b1,
										bs_search_skip_v[4:0]);
									bs_cycles_q <= bs_search_tail_v - 6'd2;
									state_q <= STATE_BS_TIMING_WAIT;
								end else begin
									bs_search_count_q <= bs_search_count_q + {26'd0, bs_search_step_w};
									request_psw_write_task(PSW_Z_MASK, PSW_Z_MASK);
									if (bs_search_partial_len_w != 32'd0) begin
										bs_seq_active_q <= 1'b1;
										bs_word_index_q <= bs_word_index_q + 32'd1;
										bs_wait_action_q <= BSWAIT_RESUME;
										bs_cycles_q <= bs_search_resume_cycles_w - 6'd1;
										state_q <= STATE_BS_TIMING_WAIT;
									end else begin
										bs_seq_active_q <= 1'b0;
										bs_wait_action_q <= BSWAIT_RETIRE;
										bs_search_tail_v = bs_search_complete_cycles_fn(
											bs_total_words_q,
											bs_down_q,
											siz16b_q,
											1'b0,
											bs_search_skip_v[4:0]);
										bs_cycles_q <= bs_search_tail_v - 6'd1;
										state_q <= STATE_BS_TIMING_WAIT;
									end
								end
							end

							STATE_BS_DST_REQ: begin
								if (!active_q) begin
									// Finish source alignment while launching the destination read.
									bs_src_aligned_q <= bs_source_align_w[31:0];
									bs_write_mask_q <= bs_source_align_w[63:32];
									state_q <= STATE_BS_DST_WAIT;
								end
							end

							STATE_BS_DST_WAIT: begin
								if (bus_complete_w) begin
									bs_write_word_q <= bitstr_merge_aligned_fn(
										bs_op_q,
										bs_src_aligned_q,
										bus_read_data_w,
										bs_write_mask_q);
									state_q <= STATE_BS_WRITE_REQ;
								end
							end

							STATE_BS_WRITE_REQ: begin
								if (!active_q) begin
									state_q <= STATE_BS_WRITE_WAIT;
								end
							end

							STATE_BS_WRITE_WAIT: begin
								if (bus_complete_w) begin
									bs_src_addr_q <= bs_next_src_addr_w;
									bs_dst_addr_q <= bs_next_dst_addr_w;
									bs_len_q <= bs_next_len_w;
									bs_src_ofs_q <= bs_next_src_ofs_w;
									bs_dst_ofs_q <= bs_next_dst_ofs_w;
									bs_seq_active_q <= (bs_next_len_w != 32'd0);
									if (bs_next_len_w != 32'd0) begin
										bs_word_index_q <= bs_word_index_q + 32'd1;
									end
									bs_wait_action_q <= (bs_next_len_w == 32'd0) ? BSWAIT_RETIRE : BSWAIT_RESUME;
									bs_cycles_q <= (bs_post_cycles_w == 6'd0) ? 6'd1 : bs_post_cycles_w;
									state_q <= STATE_BS_TIMING_WAIT;
								end
							end

							STATE_BS_TIMING_WAIT: begin
								if (bs_cycles_q != 6'd0) begin
									if (bs_cycles_q == 6'd1) begin
										if (bitstr_async_exc_kind_w != ASYNC_EXC_NONE) begin
											// Publish final r26-r30 checkpoint state at bit-string completion.
											publish_bitstr_checkpoint_task();
											bs_seq_active_q <= 1'b0;
											exc_code_q <= async_exception_code_fn(bitstr_async_exc_kind_w, irq_accept_level_w);
											exc_restore_pc_q <= {exec_pc_q[31:1], 1'b0};
											state_q <= STATE_EXC_ENTER;
										end else begin
											case (bs_wait_action_q)
												BSWAIT_START: state_q <= STATE_BS_SRC_REQ;
												// Resume through normal fetch so pending interrupts see a boundary.
												BSWAIT_RESUME: begin
													fetch_defer_q <= 1'b1;
													state_q <= fetch_restart_state_w;
												end
												default: begin
													publish_bitstr_checkpoint_task();
													bs_seq_active_q <= 1'b0;
													retire_trace_task(6'd0, WB_PRODUCER_BS_GROUP,
														1'b0, 1'b1, 2'd0);
													update_retire_history_task(RETIRE_CLASS_LONG, SIZE_W, 1'b0);
													fetch_defer_q <= 1'b1;
													pc_q <= exec_seq_pc_q;
													state_q <= fetch_restart_state_w;
												end
											endcase
										end
									end
									bs_cycles_q <= bs_cycles_q - 6'd1;
								end
							end

							STATE_TIMING_WAIT: begin
								if (timing_cycles_q != 6'd0) begin
									if (timing_cycles_q == 6'd1) begin
										case (timing_kind_q)
											TIMING_LDSR: begin
												case (timing_regid_q)
													SYS_EIPC,
													SYS_EIPSW,
													SYS_FEPC,
													SYS_FEPSW,
													SYS_PSW,
													SYS_ADTRE,
													SYS_SR29,
													SYS_SR31: begin
														sysreg_write_we_v = 1'b1;
														sysreg_write_addr_v = timing_regid_q;
														sysreg_write_data_v = timing_value_q;
													end
													SYS_CHCW: begin
														request_cache_mode_task(timing_value_q[1]);
													end
													SYS_ECR,
													SYS_PIR,
													SYS_TKCW,
													SYS_SR30: begin
														// Ignore LDSR writes to read-only system registers.
													end
													default: begin end
												endcase
												retire_trace_task(6'd0, 7'd0,
													1'b0, 1'b0, 2'd0);
												update_retire_history_task(RETIRE_CLASS_OTHER, SIZE_H, 1'b0);
												pc_q <= exec_seq_pc_q;
												if (timing_ldsr_resident_successor_ready_w) begin
													accept_resident_successor_task(
														6'd0, 7'd0, 1'b0, 1'b0, 1'b0);
												end else begin
													fetch_defer_q <= 1'b1;
													state_q <= fetch_restart_state_w;
												end
											end

											TIMING_STSR: begin
												request_gpr_write_task(timing_dest_q, timing_value_q);
												retire_trace_task(6'd0, wb_reg_producer_fn(timing_dest_q),
													1'b0, 1'b0, 2'd0);
												update_retire_history_task(RETIRE_CLASS_OTHER, SIZE_H, 1'b0);
												pc_q <= exec_seq_pc_q;
												if (resident_sequential_successor_ready_w) begin
													accept_resident_successor_task(
														6'd0, wb_reg_producer_fn(timing_dest_q),
														1'b0, 1'b0, 1'b0);
												end else begin
													fetch_defer_q <= 1'b1;
													state_q <= fetch_restart_state_w;
												end
											end

											TIMING_MEM_LOAD: begin
												// Interrupts may discard a completed LD before writeback; IN is atomic.
												if (!mem_io_q &&
													(abort_async_exc_kind_w != ASYNC_EXC_NONE)) begin
													exc_code_q <= async_exception_code_fn(
														abort_async_exc_kind_w, irq_accept_level_w);
													exc_restore_pc_q <= {exec_pc_q[31:1], 1'b0};
													state_q <= STATE_EXC_ENTER;
												end else begin
													request_gpr_write_task(timing_dest_q, timing_value_q);
													retire_trace_task(6'd0, wb_reg_producer_fn(timing_dest_q),
														1'b0, 1'b0, 2'd0);
													update_retire_history_task(RETIRE_CLASS_LOAD,
														instr_mem_size_fn(exec_iw_q),
														instr_is_io_family_fn(exec_iw_q));
													pc_q <= exec_seq_pc_q;
													if (resident_sequential_successor_ready_w) begin
														accept_resident_successor_task(
															6'd0, wb_reg_producer_fn(timing_dest_q),
															1'b0, 1'b0, 1'b0);
													end else begin
														state_q <= fetch_restart_state_w;
													end
												end
											end

											TIMING_MEM_STORE: begin
												retire_trace_task(6'd0, 7'd0, 1'b0, 1'b0,
													next_write_streak_fn(
														write_streak_q, prev_retire_size_q, prev_retire_io_q,
														instr_mem_size_fn(exec_iw_q),
														instr_is_io_family_fn(exec_iw_q)));
												update_retire_history_task(RETIRE_CLASS_STORE,
													instr_mem_size_fn(exec_iw_q),
													instr_is_io_family_fn(exec_iw_q));
												pc_q <= exec_seq_pc_q;
												if (resident_sequential_successor_ready_w) begin
													accept_resident_successor_task(
														6'd0, 7'd0, 1'b0, 1'b0, 1'b1);
												end else begin
													state_q <= fetch_restart_state_w;
												end
											end

											TIMING_TRAP: begin
												// Enter the exception after the TRAP timing wait.
												state_q <= STATE_EXC_ENTER;
											end

											TIMING_RETI: begin
												trace_valid_o <= 1'b1;
												trace_pc_o <= exec_pc_q;
												trace_insn_o <= exec_trace_insn_q;
												update_retire_history_task(RETIRE_CLASS_OTHER, SIZE_H, 1'b0);
												pc_q <= reti_restore_pc_q;
												request_psw_write_task(
													PSW_WRITE_MASK, reti_restore_psw_q);
												state_q <= fetch_restart_state_w;
											end

											// TIMING_CAXI completion.
											default: begin
												caxi_active_q <= 1'b0;
												request_psw_write_task(PSW_WRITE_MASK, caxi_final_psw_q);
												if (caxi_final_reg_we_q) begin
													request_gpr_write_task(exec_reg2_q, caxi_final_reg_q);
												end
												retire_trace_task(6'd0, wb_reg_producer_fn(exec_reg2_q),
													1'b0, 1'b1, 2'd0);
												update_retire_history_task(RETIRE_CLASS_OTHER, SIZE_W, 1'b0);
												pc_q <= exec_seq_pc_q;
												state_q <= fetch_restart_state_w;
											end
										endcase
									end
									timing_cycles_q <= timing_cycles_q - 6'd1;
								end
							end

							STATE_MEM_REQ: begin
								if (bus_launch_accept_w) begin
									if (mem_write_q) begin
										retire_store_task(mem_size_q, mem_io_q);
									end else begin
										state_q <= STATE_MEM_WAIT;
									end
								end
							end

							STATE_MEM_WAIT: begin
								if (!posted_write_busy_w && bus_complete_w) begin
									if (active_write_q) begin
										retire_store_task(active_size_q, mem_io_q);
									end else begin
										timing_kind_q <= TIMING_MEM_LOAD;
										timing_cycles_q <= exec_issue_cycles_q;
										timing_value_q <= mem_read_data_w;
										timing_dest_q <= mem_dest_q;
										if (exec_issue_cycles_q == 6'd0) begin
											if (!mem_io_q &&
												(abort_async_exc_kind_w != ASYNC_EXC_NONE)) begin
												exc_code_q <= async_exception_code_fn(
													abort_async_exc_kind_w, irq_accept_level_w);
												exc_restore_pc_q <= {exec_pc_q[31:1], 1'b0};
												state_q <= STATE_EXC_ENTER;
											end else begin
												request_gpr_write_task(mem_dest_q, mem_read_data_w);
												retire_trace_task(6'd0,
													wb_reg_producer_fn(mem_dest_q),
													1'b0, 1'b0, 2'd0);
												update_retire_history_task(
													RETIRE_CLASS_LOAD, active_size_q, mem_io_q);
												pc_q <= exec_seq_pc_q;
												if (resident_sequential_successor_ready_w) begin
													accept_resident_successor_task(
														6'd0, wb_reg_producer_fn(mem_dest_q),
														1'b0, 1'b0, 1'b0);
												end else if (!irq_accept_now_w && !nmi_accept_w &&
													(fetch_restart_state_w == STATE_IFETCH_REQ)) begin
													state_q <= STATE_IFETCH_WAIT;
												end else begin
													state_q <= fetch_restart_state_w;
												end
											end
										end else begin
											state_q <= STATE_TIMING_WAIT;
										end
									end
								end
							end

							STATE_SAVESTATE_HOLD: begin
								if (!savestate_pause_req_i) begin
									state_q <= fetch_restart_state_w;
									invalidate_line_window_task;
									phi1_seen_q <= 1'b0;
								end
							end

							default: begin
								state_q <= STATE_CACHE_INIT;
							end
						endcase
					end

					if (sysreg_write_we_v) begin
						case (sysreg_write_addr_v)
							SYS_EIPC:  eipc_q <= {sysreg_write_data_v[31:1], 1'b0};
							SYS_EIPSW: eipsw_q <= sysreg_write_data_v & PSW_WRITE_MASK;
							SYS_FEPC:  fepc_q <= {sysreg_write_data_v[31:1], 1'b0};
							SYS_FEPSW: fepsw_q <= sysreg_write_data_v & PSW_WRITE_MASK;
							SYS_PSW:   request_psw_write_task(PSW_WRITE_MASK, sysreg_write_data_v);
							SYS_ADTRE: adtre_q <= {sysreg_write_data_v[31:1], 1'b0};
							SYS_SR29:  sr29_q <= sysreg_write_data_v;
							SYS_SR31:  sr31_q <= sysreg_write_data_v;
							default: begin end
						endcase
					end
					if (sysreg_exception_we_v) begin
						ecr_q <= sysreg_exception_ecr_v;
						if (sysreg_exception_save_fe_v) begin
							fepc_q <= sysreg_exception_saved_pc_v;
							fepsw_q <= sysreg_exception_saved_psw_v;
						end else if (sysreg_exception_save_ei_v) begin
							eipc_q <= sysreg_exception_saved_pc_v;
							eipsw_q <= sysreg_exception_saved_psw_v;
						end
						if (sysreg_exception_psw_we_v) begin
							request_psw_write_task(
								PSW_WRITE_MASK, sysreg_exception_psw_v);
						end
					end
					if (gpr_commit_we_v != 5'b00000) begin
// synthesis translate_off
`ifndef SYNTHESIS
						if (rf_commit_valid_q && !rf_commit_accept_w) begin
							$fatal(1, "NECv810 unaccepted GPR transaction overwrite");
						end
`endif
// synthesis translate_on
						rf_commit_valid_q <= 1'b1;
						rf_commit_we_q <= gpr_commit_we_v;
						rf_commit_addr0_q <= gpr_commit_addr0_v;
						rf_commit_addr1_q <= gpr_commit_addr1_v;
						rf_commit_addr2_q <= gpr_commit_addr2_v;
						rf_commit_addr3_q <= gpr_commit_addr3_v;
						rf_commit_addr4_q <= gpr_commit_addr4_v;
						rf_commit_data0_q <= gpr_commit_data0_v;
						rf_commit_data1_q <= gpr_commit_data1_v;
						rf_commit_data2_q <= gpr_commit_data2_v;
						rf_commit_data3_q <= gpr_commit_data3_v;
						rf_commit_data4_q <= gpr_commit_data4_v;
					end
					if (psw_commit_we_v) begin
						psw_q <= psw_commit_data_v & PSW_WRITE_MASK;
					end
				end

			end

			// One commit mux owns cache mode for CHCW and snapshot restore.
			if (cache_control_write_we_v) begin
				cache_enable_q <= cache_control_enable_v;
				cache_enable_pending_q <= cache_control_pending_v;
			end
		end
	end

	function [15:0] halfword_from_line_fn;
		input [63:0] line;
		input [1:0]  offset;
		begin
			case (offset)
				2'd0: halfword_from_line_fn = line[63:48];
				2'd1: halfword_from_line_fn = line[47:32];
				2'd2: halfword_from_line_fn = line[31:16];
				default: halfword_from_line_fn = line[15:0];
			endcase
		end
	endfunction

	function [63:0] merge_fill_halfword_fn;
		input [63:0] line;
		input [1:0]  index;
		input [15:0] value;
		begin
			merge_fill_halfword_fn = line;
			case (index)
				2'd0: merge_fill_halfword_fn[63:48] = value;
				2'd1: merge_fill_halfword_fn[47:32] = value;
				2'd2: merge_fill_halfword_fn[31:16] = value;
				default: merge_fill_halfword_fn[15:0] = value;
			endcase
		end
	endfunction

	function [31:0] build_instr32_fn;
		input [63:0] line0;
		input [63:0] line1;
		input [1:0]  offset;
		begin
			case (offset)
				2'd0: build_instr32_fn = {line0[63:48], line0[47:32]};
				2'd1: build_instr32_fn = {line0[47:32], line0[31:16]};
				2'd2: build_instr32_fn = {line0[31:16], line0[15:0]};
				default: build_instr32_fn = {line0[15:0], line1[63:48]};
			endcase
		end
	endfunction

	function instr_needs_second_half_fn;
		input [15:0] iw;
		begin
			instr_needs_second_half_fn = (iw[15:13] == 3'b101) || (iw[15:13] == 3'b110) || (iw[15:13] == 3'b111);
		end
	endfunction

	function [31:0] mem_read_data_fn;
		input [1:0]  size;
		input        signext;
		input [31:0] data;
		begin
			case (size)
				SIZE_B: mem_read_data_fn = signext ?
					{{24{data[7]}}, data[7:0]} : {24'd0, data[7:0]};
				SIZE_W: mem_read_data_fn = data;
				default: mem_read_data_fn = signext ?
					{{16{data[15]}}, data[15:0]} : {16'd0, data[15:0]};
			endcase
		end
	endfunction

	function address_error_fn;
		input [31:0] addr;
		input [1:0]  size;
		begin
			case (size)
				SIZE_H: address_error_fn = addr[0];
				SIZE_W: address_error_fn = |addr[1:0];
				default: address_error_fn = 1'b0;
			endcase
		end
	endfunction

	function chcw_invalid_combination_fn;
		input [31:0] command;
		begin
			// Hardware proves ICE+ICC clear and enable together. Other combined
			// maintenance commands are unmeasured and rejected.
			chcw_invalid_combination_fn =
				(command[1] && (command[4] || command[5])) ||
				(command[0] && command[4]) ||
				(command[0] && command[5]) ||
				(command[4] && command[5]);
		end
	endfunction

	function [31:0] align_addr_fn;
		input [31:0] addr;
		input [1:0]  size;
		begin
			case (size)
				SIZE_H: align_addr_fn = {addr[31:1], 1'b0};
				SIZE_W: align_addr_fn = {addr[31:2], 2'b00};
				default: align_addr_fn = addr;
			endcase
		end
	endfunction

	function [33:0] alu_addsub_fn;
		input [31:0] lhs;
		input [31:0] rhs;
		input subtract;
		reg [32:0] sum_v;
		begin
			sum_v = {1'b0, lhs} +
				{1'b0, (rhs ^ {32{subtract}})} +
				{32'd0, subtract};
			alu_addsub_fn[31:0] = sum_v[31:0];
			alu_addsub_fn[32] = subtract ? ~sum_v[32] : sum_v[32];
			alu_addsub_fn[33] =
				(~(lhs[31] ^ (rhs[31] ^ subtract))) &
				(lhs[31] ^ sum_v[31]);
		end
	endfunction

	function [31:0] reverse32_fn;
		input [31:0] value;
		begin
			reverse32_fn = {
				value[0],  value[1],  value[2],  value[3],
				value[4],  value[5],  value[6],  value[7],
				value[8],  value[9],  value[10], value[11],
				value[12], value[13], value[14], value[15],
				value[16], value[17], value[18], value[19],
				value[20], value[21], value[22], value[23],
				value[24], value[25], value[26], value[27],
				value[28], value[29], value[30], value[31]
			};
		end
	endfunction

	function [32:0] barrel_shift_fn;
		input [31:0] value;
		input [4:0] amount;
		input left;
		input arithmetic;
		reg fill_v;
		reg [32:0] stage0_v;
		reg [32:0] stage1_v;
		reg [32:0] stage2_v;
		reg [32:0] stage4_v;
		reg [32:0] stage8_v;
		reg [32:0] stage16_v;
		reg [31:0] ordered_result_v;
		begin
			fill_v = arithmetic & value[31];
			stage0_v = left ? {reverse32_fn(value), 1'b0} : {value, 1'b0};
			stage1_v = amount[0] ? {fill_v, stage0_v[32:1]} : stage0_v;
			stage2_v = amount[1] ? {{2{fill_v}}, stage1_v[32:2]} : stage1_v;
			stage4_v = amount[2] ? {{4{fill_v}}, stage2_v[32:4]} : stage2_v;
			stage8_v = amount[3] ? {{8{fill_v}}, stage4_v[32:8]} : stage4_v;
			stage16_v = amount[4] ? {{16{fill_v}}, stage8_v[32:16]} : stage8_v;
			ordered_result_v = stage16_v[32:1];
			barrel_shift_fn[31:0] = left ?
				reverse32_fn(ordered_result_v) : ordered_result_v;
			barrel_shift_fn[32] = stage16_v[0];
		end
	endfunction

	function sub_borrow_fn;
		input [31:0] lhs;
		input [31:0] rhs;
		begin
			sub_borrow_fn = (lhs < rhs);
		end
	endfunction

	function sub_overflow_fn;
		input [31:0] lhs;
		input [31:0] rhs;
		input [31:0] result;
		begin
			sub_overflow_fn = (lhs[31] ^ rhs[31]) & (lhs[31] ^ result[31]);
		end
	endfunction

	function [31:0] sx5_fn;
		input [4:0] imm5;
		begin
			sx5_fn = {{27{imm5[4]}}, imm5};
		end
	endfunction

	function [31:0] sx9_fn;
		input [8:0] imm9;
		begin
			sx9_fn = {{23{imm9[8]}}, imm9};
		end
	endfunction

	function [31:0] sx16_fn;
		input [15:0] imm16;
		begin
			sx16_fn = {{16{imm16[15]}}, imm16};
		end
	endfunction

	function [31:0] sx26_fn;
		input [25:0] imm26;
		begin
			sx26_fn = {{6{imm26[25]}}, imm26};
		end
	endfunction

	function [31:0] issue_immediate_fn;
		input [5:0]  uentry;
		input [31:0] iw;
		begin
			case (uentry)
				UADDR_MOV_I,
				UADDR_ADD_I,
				UADDR_CMP_I: issue_immediate_fn = sx5_fn(iw[20:16]);

				UADDR_SHL_I,
				UADDR_SHR_I,
				UADDR_SAR_I: issue_immediate_fn = {27'd0, iw[20:16]};

				UADDR_MOVEA,
				UADDR_ADDI,
				UADDR_MEM_LD_B,
				UADDR_MEM_LD_H,
				UADDR_MEM_LD_W,
				UADDR_MEM_ST_B,
				UADDR_MEM_ST_H,
				UADDR_MEM_ST_W,
				UADDR_MEM_IN_B,
				UADDR_MEM_IN_H,
				UADDR_MEM_IN_W,
				UADDR_MEM_OUT_B,
				UADDR_MEM_OUT_H,
				UADDR_MEM_OUT_W,
				UADDR_CAXI: issue_immediate_fn = sx16_fn(iw[15:0]);

				UADDR_ORI,
				UADDR_ANDI,
				UADDR_XORI: issue_immediate_fn = {16'd0, iw[15:0]};

				UADDR_MOVHI: issue_immediate_fn = {iw[15:0], 16'd0};

				UADDR_JR,
				UADDR_JAL: issue_immediate_fn = sx26_fn(iw[25:0]);

				default: issue_immediate_fn = 32'd0;
			endcase
		end
	endfunction

	function [31:0] chcw_bus_addr_fn;
		input [31:0] sa;
		input [6:0]  index;
		input        data_phase;
		input        word_sel;
		begin
			if (data_phase) begin
				chcw_bus_addr_fn = sa + {22'd0, index, 3'b000} + {29'd0, word_sel, 2'b00};
			end else begin
				chcw_bus_addr_fn = sa + 32'd1024 + {23'd0, index, 2'b00};
			end
		end
	endfunction

	function [31:0] chcw_bus_wdata_fn;
		input [63:0] line;
		input [31:0] tag;
		input        data_phase;
		input        word_sel;
		begin
			if (data_phase) begin
				chcw_bus_wdata_fn = word_sel ? line[63:32] : line[31:0];
			end else begin
				chcw_bus_wdata_fn = tag;
			end
		end
	endfunction

	function [5:0] bs_step_fn;
		input [31:0] len;
		input [4:0]  dst_ofs;
		reg [5:0] avail_v;
		begin
			avail_v = 6'd32 - {1'b0, dst_ofs};
			if (len == 32'd0) begin
				bs_step_fn = 6'd0;
			end else if (len < {26'd0, avail_v}) begin
				bs_step_fn = len[5:0];
			end else begin
				bs_step_fn = avail_v;
			end
		end
	endfunction

	function [5:0] bs_search_step_fn;
		input [31:0] len;
		input [4:0]  src_ofs;
		input        down;
		reg [5:0] avail_v;
		begin
			if (down) begin
				avail_v = {1'b0, src_ofs} + 6'd1;
			end else begin
				avail_v = 6'd32 - {1'b0, src_ofs};
			end
			if (len == 32'd0) begin
				bs_search_step_fn = 6'd0;
			end else if (len < {26'd0, avail_v}) begin
				bs_search_step_fn = len[5:0];
			end else begin
				bs_search_step_fn = avail_v;
			end
		end
	endfunction

	function [31:0] bs_word_count_fn;
		input [31:0] len;
		input [4:0]  ofs;
		reg [32:0] span_v;
		begin
			span_v = 33'd0;
			if (len == 32'd0) begin
				bs_word_count_fn = 32'd0;
			end else begin
				span_v = {1'b0, len} + {28'd0, ofs};
				bs_word_count_fn = {4'd0, span_v[32:5]} + ((span_v[4:0] != 5'd0) ? 32'd1 : 32'd0);
			end
		end
	endfunction

	function [31:0] bs_search_words_total_fn;
		input [31:0] len;
		input [4:0]  ofs;
		input        down;
		reg [31:0] first_bits_v;
		reg [31:0] remain_v;
		begin
			first_bits_v = 32'd0;
			remain_v = 32'd0;
			if (len == 32'd0) begin
				bs_search_words_total_fn = 32'd0;
			end else begin
				first_bits_v = down ? ({27'd0, ofs} + 32'd1) : (32'd32 - {27'd0, ofs});
				if (len <= first_bits_v) begin
					bs_search_words_total_fn = 32'd1;
				end else begin
					remain_v = len - first_bits_v;
					bs_search_words_total_fn = 32'd1 + {5'd0, remain_v[31:5]} + ((remain_v[4:0] != 5'd0) ? 32'd1 : 32'd0);
				end
			end
		end
	endfunction

	function bs_search_first_partial_fn;
		input [4:0] ofs;
		input       down;
		begin
			bs_search_first_partial_fn = down ? (ofs != 5'd31) : (ofs != 5'd0);
		end
	endfunction

	function bs_search_last_partial_fn;
		input [31:0] len;
		input [4:0]  ofs;
		input        down;
		reg [31:0] first_bits_v;
		reg [31:0] remain_v;
		begin
			first_bits_v = 32'd0;
			remain_v = 32'd0;
			if (len == 32'd0) begin
				bs_search_last_partial_fn = 1'b0;
			end else begin
				first_bits_v = down ? ({27'd0, ofs} + 32'd1) : (32'd32 - {27'd0, ofs});
				if (len <= first_bits_v) begin
					bs_search_last_partial_fn = (len != first_bits_v);
				end else begin
					remain_v = len - first_bits_v;
					bs_search_last_partial_fn = (remain_v[4:0] != 5'd0);
				end
			end
		end
	endfunction

	function [2:0] bs_arith_type_fn;
		input [31:0] len;
		input [31:0] src_addr;
		input [31:0] dst_addr;
		input [4:0]  src_ofs;
		input [4:0]  dst_ofs;
		reg [31:0] src_words_v;
		reg [31:0] dst_words_v;
		reg [5:0]  end_sum_v;
		begin
			src_words_v = 32'd0;
			dst_words_v = 32'd0;
			end_sum_v = 6'd0;
			if (len == 32'd0) begin
				bs_arith_type_fn = BS_TYPE6;
			end else begin
				src_words_v = bs_word_count_fn(len, src_ofs);
				dst_words_v = bs_word_count_fn(len, dst_ofs);
				if ((src_addr == dst_addr) && (src_words_v == 32'd1) && (dst_words_v == 32'd1) && (src_ofs > dst_ofs)) begin
					bs_arith_type_fn = BS_TYPE7;
				end else if (src_ofs == dst_ofs) begin
					end_sum_v = {1'b0, src_ofs} + len[5:0];
					bs_arith_type_fn = (end_sum_v[4:0] == 5'd0) ? BS_TYPE1 : BS_TYPE2;
				end else if (src_words_v == dst_words_v) begin
					bs_arith_type_fn = (dst_ofs == 5'd0) ? BS_TYPE3 : BS_TYPE5;
				end else begin
					bs_arith_type_fn = BS_TYPE4;
				end
			end
		end
	endfunction

	function [5:0] bs_arith_start_cycles_fn;
		input [2:0] bs_type;
		input       siz16b;
		begin
			// Adjust waits so complete bit-string timing matches NEC table 5-13.
			case (bs_type)
				BS_TYPE1: bs_arith_start_cycles_fn = siz16b ? 6'd27 : 6'd24;
				BS_TYPE2: bs_arith_start_cycles_fn = siz16b ? 6'd27 : 6'd24;
				BS_TYPE3: bs_arith_start_cycles_fn = siz16b ? 6'd32 : 6'd29;
				BS_TYPE4: bs_arith_start_cycles_fn = siz16b ? 6'd30 : 6'd31;
				BS_TYPE5: bs_arith_start_cycles_fn = siz16b ? 6'd27 : 6'd24;
				BS_TYPE7: bs_arith_start_cycles_fn = siz16b ? 6'd32 : 6'd29;
				default:  bs_arith_start_cycles_fn = siz16b ? 6'd19 : 6'd13;
			endcase
		end
	endfunction

	function [5:0] bs_arith_zero_cycles_fn;
		input [2:0] bs_type;
		input       siz16b;
		begin
			case (bs_type)
				BS_TYPE6: bs_arith_zero_cycles_fn = siz16b ? 6'd19 : 6'd13;
				BS_TYPE7: bs_arith_zero_cycles_fn = siz16b ? 6'd42 : 6'd36;
				default:  bs_arith_zero_cycles_fn = 6'd0;
			endcase
		end
	endfunction

	function [5:0] bs_arith_resume_cycles_fn;
		input [2:0]  bs_type;
		input [31:0] total_words;
		input [31:0] word_index;
		input        siz16b;
		begin
			if (total_words <= word_index) begin
				bs_arith_resume_cycles_fn = 6'd0;
			end else if (word_index == 32'd1) begin
				case (bs_type)
					BS_TYPE1: bs_arith_resume_cycles_fn = siz16b ? 6'd12 : 6'd6;
					BS_TYPE2: bs_arith_resume_cycles_fn = siz16b ? 6'd14 : 6'd7;
					BS_TYPE3,
					BS_TYPE5: bs_arith_resume_cycles_fn = siz16b ? 6'd16 : 6'd8;
					BS_TYPE4: bs_arith_resume_cycles_fn = siz16b ? 6'd6 : 6'd3;
					default:  bs_arith_resume_cycles_fn = 6'd0;
				endcase
			end else begin
				case (bs_type)
					BS_TYPE1,
					BS_TYPE2: bs_arith_resume_cycles_fn = siz16b ? 6'd8 : 6'd4;
					BS_TYPE3,
					BS_TYPE4: bs_arith_resume_cycles_fn = siz16b ? 6'd4 : 6'd2;
					BS_TYPE5: bs_arith_resume_cycles_fn = siz16b ? 6'd6 : 6'd3;
					default:  bs_arith_resume_cycles_fn = 6'd0;
				endcase
			end
		end
	endfunction

	function [5:0] bs_search_zero_cycles_fn;
		input down;
		begin
			bs_search_zero_cycles_fn = down ? 6'd15 : 6'd13;
		end
	endfunction

	function [5:0] bs_search_start_cycles_fn;
		input [31:0] total_words;
		input        first_partial;
		input        down;
		begin
			// Search startup timing depends on direction and first-word alignment.
			if (total_words <= 32'd1) begin
				bs_search_start_cycles_fn = down ? 6'd25 : 6'd28;
			end else if (down) begin
				bs_search_start_cycles_fn = first_partial ? 6'd30 : 6'd42;
			end else begin
				bs_search_start_cycles_fn = first_partial ? 6'd27 : 6'd37;
			end
		end
	endfunction

	function [5:0] bs_search_resume_cycles_fn;
		input        first_partial;
		input        last_partial;
		input        down;
		input [31:0] total_words;
		input [31:0] word_index;
		input        siz16b;
		begin
			if ((total_words <= 32'd1) || (total_words <= word_index)) begin
				bs_search_resume_cycles_fn = 6'd0;
			end else if (word_index == 32'd1) begin
				bs_search_resume_cycles_fn = first_partial ?
					(siz16b ? 6'd29 : 6'd23) :
					(siz16b ? 6'd4 : 6'd2);
			end else if ((word_index + 32'd1) == total_words) begin
				if (down) begin
					bs_search_resume_cycles_fn = last_partial ? 6'd0 : (siz16b ? 6'd4 : 6'd2);
				end else begin
					bs_search_resume_cycles_fn = last_partial ? (siz16b ? 6'd4 : 6'd2) : 6'd0;
				end
			end else begin
				bs_search_resume_cycles_fn = siz16b ? 6'd4 : 6'd2;
			end
		end
	endfunction

	function [5:0] bs_search_complete_cycles_fn;
		input [31:0] total_words;
		input        down;
		input        siz16b;
		input        found;
		input [4:0]  skip_bits;
		begin
			if (found) begin
				bs_search_complete_cycles_fn =
					(siz16b ? 6'd5 : 6'd3) + {1'b0, skip_bits[4:1]};
			end else if ((total_words == 32'd1) && down) begin
				bs_search_complete_cycles_fn = siz16b ? 6'd4 : 6'd2;
			end else begin
				bs_search_complete_cycles_fn = 6'd0;
			end
		end
	endfunction

	function [31:0] bs_search_ordered_word_fn;
		input [31:0] word;
		input [4:0]  ofs;
		input        down;
		begin
			if (down) begin
				bs_search_ordered_word_fn = {
					word[0],  word[1],  word[2],  word[3],
					word[4],  word[5],  word[6],  word[7],
					word[8],  word[9],  word[10], word[11],
					word[12], word[13], word[14], word[15],
					word[16], word[17], word[18], word[19],
					word[20], word[21], word[22], word[23],
					word[24], word[25], word[26], word[27],
					word[28], word[29], word[30], word[31]
				} >> (5'd31 - ofs);
			end else begin
				bs_search_ordered_word_fn = word >> ofs;
			end
		end
	endfunction

	function bs_search_match_any_fn;
		input [31:0] word;
		input [4:0]  ofs;
		input [5:0]  step;
		input        search_bit;
		input        down;
		reg [31:0] ordered_v;
		begin
			ordered_v = bs_search_ordered_word_fn(word, ofs, down);
			bs_search_match_any_fn = |((search_bit ? ordered_v : ~ordered_v) & bit_mask32_fn(step));
		end
	endfunction

	function [6:0] bs_search_result_fn;
		input [31:0] word;
		input [4:0]  ofs;
		input [5:0]  step;
		input        search_bit;
		input        down;
		reg [31:0] ordered_v;
		reg [31:0] matches_v;
		reg [15:0] level16_v;
		reg [7:0]  level8_v;
		reg [3:0]  level4_v;
		reg [1:0]  level2_v;
		reg [4:0]  index_v;
		reg        found_v;
		begin
			// Reverse wiring as needed so a five-level tree always searches from bit zero.
			ordered_v = bs_search_ordered_word_fn(word, ofs, down);
			matches_v = (search_bit ? ordered_v : ~ordered_v) & bit_mask32_fn(step);
			found_v = |matches_v;
			index_v = 5'd0;
			if (|matches_v[15:0]) begin
				level16_v = matches_v[15:0];
			end else begin
				index_v[4] = 1'b1;
				level16_v = matches_v[31:16];
			end
			if (|level16_v[7:0]) begin
				level8_v = level16_v[7:0];
			end else begin
				index_v[3] = 1'b1;
				level8_v = level16_v[15:8];
			end
			if (|level8_v[3:0]) begin
				level4_v = level8_v[3:0];
			end else begin
				index_v[2] = 1'b1;
				level4_v = level8_v[7:4];
			end
			if (|level4_v[1:0]) begin
				level2_v = level4_v[1:0];
			end else begin
				index_v[1] = 1'b1;
				level2_v = level4_v[3:2];
			end
			index_v[0] = !level2_v[0];
			bs_search_result_fn = found_v ? {1'b1, 1'b0, index_v} : {1'b0, step};
		end
	endfunction

	function [31:0] bs_search_addr_advance_fn;
		input [31:0] addr;
		input [4:0]  ofs;
		input [5:0]  bits;
		input        down;
		reg [6:0] sum_v;
		begin
			sum_v = 7'd0;
			if (down) begin
				if (bits > {1'b0, ofs}) begin
					bs_search_addr_advance_fn = addr - 32'd4;
				end else begin
					bs_search_addr_advance_fn = addr;
				end
			end else begin
				sum_v = {2'b00, ofs} + {1'b0, bits};
				bs_search_addr_advance_fn = addr + {29'd0, sum_v[5], 2'b00};
			end
		end
	endfunction

	function [4:0] bs_search_ofs_advance_fn;
		input [4:0] ofs;
		input [5:0] bits;
		input       down;
		reg [6:0] sum_v;
		begin
			sum_v = 7'd0;
			if (down) begin
				if (bits > {1'b0, ofs}) begin
					bs_search_ofs_advance_fn = 5'd31;
				end else begin
					bs_search_ofs_advance_fn = ofs - bits[4:0];
				end
			end else begin
				sum_v = {2'b00, ofs} + {1'b0, bits};
				bs_search_ofs_advance_fn = sum_v[4:0];
			end
		end
	endfunction

	function [31:0] bit_mask32_fn;
		input [5:0] bits;
		begin
			if (bits == 6'd0) begin
				bit_mask32_fn = 32'd0;
			end else if (bits >= 6'd32) begin
				bit_mask32_fn = 32'hffff_ffff;
			end else begin
				bit_mask32_fn = (32'h0000_0001 << bits) - 32'd1;
			end
		end
	endfunction

	function [31:0] extract_bits32_fn;
		input [31:0] lo_word;
		input [31:0] hi_word;
		input [4:0]  ofs;
		input [5:0]  bits;
		reg [63:0] window_v;
		reg [63:0] shifted_v;
		begin
			window_v = {hi_word, lo_word};
			shifted_v = window_v >> ofs;
			extract_bits32_fn = shifted_v[31:0] & bit_mask32_fn(bits);
		end
	endfunction

	function [63:0] bitstr_source_align_fn;
		input [31:0] src_lo;
		input [31:0] src_hi;
		input [4:0]  src_ofs;
		input [4:0]  dst_ofs;
		input [5:0]  bits;
		reg [31:0] mask_v;
		reg [31:0] write_mask_v;
		reg [31:0] src_bits_v;
		reg [31:0] src_aligned_v;
		begin
			mask_v = bit_mask32_fn(bits);
			write_mask_v = mask_v << dst_ofs;
			src_bits_v = extract_bits32_fn(src_lo, src_hi, src_ofs, bits);
			src_aligned_v = (src_bits_v << dst_ofs) & write_mask_v;
			bitstr_source_align_fn = {write_mask_v, src_aligned_v};
		end
	endfunction

	function [31:0] bitstr_merge_aligned_fn;
		input [2:0]  op;
		input [31:0] src_aligned;
		input [31:0] dst_word;
		input [31:0] write_mask;
		reg [31:0] src_not_v;
		begin
			src_not_v = (~src_aligned) & write_mask;
			case (op)
				BS_OP_OR:   bitstr_merge_aligned_fn = dst_word | src_aligned;
				BS_OP_AND:  bitstr_merge_aligned_fn = dst_word & (~write_mask | src_aligned);
				BS_OP_XOR:  bitstr_merge_aligned_fn = dst_word ^ src_aligned;
				BS_OP_MOV:  bitstr_merge_aligned_fn = (dst_word & ~write_mask) | src_aligned;
				BS_OP_ORN:  bitstr_merge_aligned_fn = dst_word | src_not_v;
				BS_OP_ANDN: bitstr_merge_aligned_fn = dst_word & (~write_mask | src_not_v);
				BS_OP_XORN: bitstr_merge_aligned_fn = dst_word ^ src_not_v;
				default:    bitstr_merge_aligned_fn = (dst_word & ~write_mask) | src_not_v; // BS_OP_NOT
			endcase
		end
	endfunction

	function [5:0] reg_producer_fn;
		input [4:0] regid;
		begin
			if (regid == 5'd0) begin
				reg_producer_fn = 6'd0;
			end else begin
				reg_producer_fn = {1'b1, regid};
			end
		end
	endfunction

	function [6:0] wb_reg_producer_fn;
		input [4:0] regid;
		begin
			wb_reg_producer_fn = {1'b0, reg_producer_fn(regid)};
		end
	endfunction

	function instr_is_load_family_fn;
		input [31:0] iw;
		reg [5:0] op_v;
		begin
			op_v = iw[31:26];
			case (op_v)
				OP_LD_B,
				OP_LD_H,
				OP_LD_W,
				OP_IN_B,
				OP_IN_H,
				OP_IN_W: instr_is_load_family_fn = 1'b1;
				default: instr_is_load_family_fn = 1'b0;
			endcase
		end
	endfunction

	function instr_uses_memory_base_fn;
		input [5:0] op;
		begin
			case (op)
				OP_LD_B,
				OP_LD_H,
				OP_LD_W,
				OP_ST_B,
				OP_ST_H,
				OP_ST_W,
				OP_IN_B,
				OP_IN_H,
				OP_IN_W,
				OP_OUT_B,
				OP_OUT_H,
				OP_OUT_W,
				OP_CAXI: instr_uses_memory_base_fn = 1'b1;
				default: instr_uses_memory_base_fn = 1'b0;
			endcase
		end
	endfunction

	function instr_is_io_family_fn;
		input [31:0] iw;
		reg [5:0] op_v;
		begin
			op_v = iw[31:26];
			case (op_v)
				OP_IN_B,
				OP_IN_H,
				OP_IN_W,
				OP_OUT_B,
				OP_OUT_H,
				OP_OUT_W: instr_is_io_family_fn = 1'b1;
				default: instr_is_io_family_fn = 1'b0;
			endcase
		end
	endfunction

	function [1:0] instr_mem_size_fn;
		input [31:0] iw;
		reg [5:0] op_v;
		begin
			op_v = iw[31:26];
			case (op_v)
				OP_LD_H,
				OP_ST_H,
				OP_IN_H,
				OP_OUT_H: instr_mem_size_fn = SIZE_H;

				OP_LD_W,
				OP_ST_W,
				OP_IN_W,
				OP_OUT_W,
				OP_CAXI: instr_mem_size_fn = SIZE_W;

				default: instr_mem_size_fn = SIZE_B;
			endcase
		end
	endfunction

	function [5:0] long_issue_cycles_fn;
		input [3:0] long_kind;
		begin
			case (long_kind)
				LONG_CLI,
				LONG_SEI:   long_issue_cycles_fn = 6'd12;
				LONG_XB:    long_issue_cycles_fn = 6'd6;
				LONG_REV:   long_issue_cycles_fn = 6'd22;
				LONG_MPYHW: long_issue_cycles_fn = 6'd9;
				LONG_MUL,
				LONG_MULU:  long_issue_cycles_fn = 6'd13;
				LONG_DIV:   long_issue_cycles_fn = 6'd38;
				LONG_DIVU:  long_issue_cycles_fn = 6'd36;
				default:    long_issue_cycles_fn = 6'd0;
			endcase
		end
	endfunction

	function [5:0] cycles_after_launch_fn;
		input [5:0] total_cycles;
		begin
			// STATE_EXEC is cycle one; later states count the remaining clocks.
			cycles_after_launch_fn =
				(total_cycles == 6'd0) ? 6'd0 : total_cycles - 6'd1;
		end
	endfunction

	function abortable_engine_fn;
		input [1:0] engine;
		input [3:0] long_kind;
		begin
			case (engine)
				ABORT_ENGINE_BITSTR: abortable_engine_fn = 1'b1;
				ABORT_ENGINE_LONG: begin
					case (long_kind)
						LONG_DIV,
						LONG_DIVU,
						LONG_CMPF,
						LONG_CVTWS,
						LONG_CVTSW,
						LONG_TRNCSW,
						LONG_ADDF: abortable_engine_fn = 1'b1;
						default:   abortable_engine_fn = 1'b0;
					endcase
				end
				default: abortable_engine_fn = 1'b0;
			endcase
		end
	endfunction

	function [5:0] fp_issue_cycles_fn;
		input [3:0] long_kind;
		input [5:0] ext_subop;
		begin
			// Silicon unknown: use Cycle Test totals where NEC gives only a range.
			// TRNC.SW and SUBF/MULF/DIVF arrive on the shared CVTSW/ADDF entries
			// and are told apart by ext_subop.
			case (long_kind)
				LONG_CMPF:  fp_issue_cycles_fn = 6'd7;
				LONG_CVTWS: fp_issue_cycles_fn = 6'd8;
				LONG_CVTSW: fp_issue_cycles_fn = (ext_subop == SUBOP_TRNCSW) ? 6'd13 : 6'd14;
				LONG_ADDF: begin
					case (ext_subop)
						SUBOP_SUBF,
						SUBOP_MULF: fp_issue_cycles_fn = 6'd26;
						SUBOP_DIVF: fp_issue_cycles_fn = 6'd44;
						default:    fp_issue_cycles_fn = 6'd22;
					endcase
				end
				default: fp_issue_cycles_fn = 6'd0;
			endcase
		end
	endfunction

	function [5:0] sys_timing_cycles_fn;
		input [2:0] timing_kind;
		begin
			case (timing_kind)
				TIMING_LDSR,
				TIMING_STSR: sys_timing_cycles_fn = 6'd8;
				TIMING_TRAP: sys_timing_cycles_fn = 6'd15;
				TIMING_RETI: sys_timing_cycles_fn = 6'd10;
				default:     sys_timing_cycles_fn = 6'd0;
			endcase
		end
	endfunction

	function [5:0] mem_load_tail_cycles_fn;
		input [31:0] iw;
		input        siz16b;
		input [2:0]  prev_class;
		input [1:0]  prev_size;
		input        prev_io;
		reg [5:0] op_v;
		begin
			op_v = iw[31:26];
			// Silicon unknown: treat every nonconflicting long operation as NEC's
			// "many cycles" one-cycle LD overlap case. This table adds only the
			// remaining table 5-11 wait after MEM_WAIT.
			case (op_v)
				OP_LD_B,
				OP_LD_H: begin
					if (prev_class == RETIRE_CLASS_LONG) begin
						mem_load_tail_cycles_fn = 6'd0;
					end else if ((prev_class == RETIRE_CLASS_LOAD) && !prev_io &&
						(prev_size != 2'b11)) begin
						mem_load_tail_cycles_fn = 6'd0;
					end else begin
						mem_load_tail_cycles_fn = 6'd1;
					end
				end

				OP_LD_W: begin
					if (prev_class == RETIRE_CLASS_LONG) begin
						mem_load_tail_cycles_fn = 6'd0;
					end else if ((prev_class == RETIRE_CLASS_LOAD) && !prev_io &&
						(prev_size != 2'b11)) begin
						mem_load_tail_cycles_fn = siz16b ? 6'd1 : 6'd0;
					end else begin
						mem_load_tail_cycles_fn = siz16b ? 6'd2 : 6'd0;
					end
				end

				OP_IN_B,
				OP_IN_H: mem_load_tail_cycles_fn = 6'd1;

				OP_IN_W: mem_load_tail_cycles_fn = siz16b ? 6'd2 : 6'd0;

				default: mem_load_tail_cycles_fn = 6'd0;
			endcase
		end
	endfunction

	function instr_is_plain_load_fn;
		input [31:0] iw;
		reg [5:0] op_v;
		begin
			op_v = iw[31:26];
			case (op_v)
				OP_LD_B,
				OP_LD_H,
				OP_LD_W: instr_is_plain_load_fn = 1'b1;
				default: instr_is_plain_load_fn = 1'b0;
			endcase
		end
	endfunction

	function long_kind_allows_load_overlap_fn;
		input [3:0] long_kind;
		begin
			// Do not overlap a load with floating-point work that may trap late.
			case (long_kind)
				LONG_MUL,
				LONG_MULU,
				LONG_DIV,
				LONG_DIVU,
				LONG_MPYHW,
				LONG_REV,
				LONG_XB: long_kind_allows_load_overlap_fn = 1'b1;
				default: long_kind_allows_load_overlap_fn = 1'b0;
			endcase
		end
	endfunction

	function [1:0] next_write_streak_fn;
		input [1:0] streak;
		input [1:0] prev_size;
		input       prev_io;
		input [1:0] cur_size;
		input       cur_io;
		begin
			if ((streak == 2'd0) || (prev_size != cur_size) ||
				(prev_io != cur_io)) begin
				next_write_streak_fn = 2'd1;
			end else begin
				next_write_streak_fn = 2'd2;
			end
		end
	endfunction

	function [5:0] mem_store_tail_cycles_fn;
		input [31:0] iw;
		input        siz16b;
		input [1:0]  streak;
		input [1:0]  prev_size;
		input        prev_io;
		reg [1:0]    cur_size_v;
		begin
			// Table 5-11 adds wait cycles to consecutive stores of the same family.
			cur_size_v = instr_mem_size_fn(iw);
			if ((streak == 2'd2) && (prev_size == cur_size_v) &&
				(prev_io == instr_is_io_family_fn(iw))) begin
				if (cur_size_v == SIZE_W) begin
					mem_store_tail_cycles_fn = siz16b ? 6'd3 : 6'd1;
				end else begin
					mem_store_tail_cycles_fn = 6'd1;
				end
			end else begin
				mem_store_tail_cycles_fn = 6'd0;
			end
		end
	endfunction

	function [5:0] issue_cycles_fn;
		input [5:0]  uentry;
		input [31:0] iw;
		input        siz16b;
		input [2:0]  prev_class;
		input [1:0]  prev_size;
		input        prev_io;
		input [1:0]  write_streak;
		begin
			case (uentry)
				UADDR_MEM_LD_B,
				UADDR_MEM_LD_H,
				UADDR_MEM_LD_W,
				UADDR_MEM_IN_B,
				UADDR_MEM_IN_H,
				UADDR_MEM_IN_W: issue_cycles_fn =
					mem_load_tail_cycles_fn(iw, siz16b, prev_class, prev_size, prev_io);

				UADDR_MEM_ST_B,
				UADDR_MEM_ST_H,
				UADDR_MEM_ST_W,
				UADDR_MEM_OUT_B,
				UADDR_MEM_OUT_H,
				UADDR_MEM_OUT_W: issue_cycles_fn =
					mem_store_tail_cycles_fn(iw, siz16b, write_streak, prev_size, prev_io);

				UADDR_CMPF: issue_cycles_fn = fp_issue_cycles_fn(LONG_CMPF, iw[15:10]);
				UADDR_CVTWS: issue_cycles_fn = fp_issue_cycles_fn(LONG_CVTWS, iw[15:10]);
				UADDR_CVTSW: issue_cycles_fn = fp_issue_cycles_fn(LONG_CVTSW, iw[15:10]);
				UADDR_FPU: issue_cycles_fn = fp_issue_cycles_fn(LONG_ADDF, iw[15:10]);
				default: issue_cycles_fn = 6'd0;
			endcase
		end
	endfunction

	function instr_flag_consumer_fn;
		input [31:0] iw;
		reg [5:0] op_v;
		begin
			op_v = iw[31:26];
			instr_flag_consumer_fn = (iw[31:29] == OP_BCOND) || (op_v == OP_SETF);
		end
	endfunction

	function reg_in_bitstr_group_fn;
		input [4:0] regid;
		begin
			case (regid)
				5'd26,
				5'd27,
				5'd28,
				5'd29,
				5'd30: reg_in_bitstr_group_fn = 1'b1;
				default: reg_in_bitstr_group_fn = 1'b0;
			endcase
		end
	endfunction

	// Read class is {r26-r30, r30, reg2, reg1} for hazard checks.
	function [3:0] instr_read_class_fn;
		input [31:0] iw;
		reg [5:0] op_v;
		reg [5:0] subop_v;
		begin
			op_v = iw[31:26];
			subop_v = iw[15:10];
			// Bcond opcodes (6'b100xxx) are unmapped here and fall to the default.
			case (op_v)
				OP_MOV_R,
				OP_NOT_R,
				OP_JMP: instr_read_class_fn = 4'b0001;

				OP_ADD_R,
				OP_SUB_R,
				OP_CMP_R,
				OP_SHL_R,
				OP_SHR_R,
				OP_SAR_R,
				OP_MUL,
				OP_DIV,
				OP_MULU,
				OP_DIVU,
				OP_OR_R,
				OP_AND_R,
				OP_XOR_R: instr_read_class_fn = 4'b0011;

				OP_ADD_I,
				OP_CMP_I,
				OP_SHL_I,
				OP_SHR_I,
				OP_SAR_I,
				OP_LDSR: instr_read_class_fn = 4'b0010;

				OP_MOVEA,
				OP_ADDI,
				OP_ORI,
				OP_ANDI,
				OP_XORI,
				OP_MOVHI,
				OP_LD_B,
				OP_LD_H,
				OP_LD_W,
				OP_IN_B,
				OP_IN_H,
				OP_IN_W: instr_read_class_fn = 4'b0001;

				OP_ST_B,
				OP_ST_H,
				OP_ST_W,
				OP_OUT_B,
				OP_OUT_H,
				OP_OUT_W: instr_read_class_fn = 4'b0011;

				OP_CAXI: instr_read_class_fn = 4'b0111;

				OP_BITSTR: instr_read_class_fn = 4'b1000;

				OP_EXT: begin
					case (subop_v)
						SUBOP_CMPF,
						SUBOP_ADDF,
						SUBOP_SUBF,
						SUBOP_MULF,
						SUBOP_DIVF,
						SUBOP_MPYHW: instr_read_class_fn = 4'b0011;

						SUBOP_CVTWS,
						SUBOP_CVTSW,
						SUBOP_TRNCSW,
						SUBOP_REV: instr_read_class_fn = 4'b0001;

						SUBOP_XB,
						SUBOP_XH: instr_read_class_fn = 4'b0010;

						default: instr_read_class_fn = 4'b0000;
					endcase
				end

				default: instr_read_class_fn = 4'b0000;
			endcase
		end
	endfunction

	function read_class_reg_match_fn;
		input [3:0] read_class;
		input [4:0] reg1;
		input [4:0] reg2;
		input [4:0] producer_reg;
		begin
			read_class_reg_match_fn =
				(producer_reg != 5'd0) &&
				((read_class[0] && (reg1 == producer_reg)) ||
				 (read_class[1] && (reg2 == producer_reg)) ||
				 (read_class[2] && (producer_reg == 5'd30)) ||
				 (read_class[3] && reg_in_bitstr_group_fn(producer_reg)));
		end
	endfunction

	function read_class_bitstr_match_fn;
		input [3:0] read_class;
		input [4:0] reg1;
		input [4:0] reg2;
		begin
			read_class_bitstr_match_fn =
				(read_class[0] && reg_in_bitstr_group_fn(reg1)) ||
				(read_class[1] && reg_in_bitstr_group_fn(reg2)) ||
				read_class[2] || read_class[3];
		end
	endfunction

	function [5:0] retire_df_producer_fn;
		input [31:0] iw;
		reg [5:0] op_v;
		begin
			op_v = iw[31:26];
			retire_df_producer_fn = 6'd0;
			if (iw[31:29] == OP_BCOND) begin
				retire_df_producer_fn = 6'd0;
			end else begin
				case (op_v)
					// One-cycle integer results forward to EX but still interlock load bases.
					OP_MOV_R,
					OP_ADD_R,
					OP_SUB_R,
					OP_OR_R,
					OP_AND_R,
					OP_XOR_R,
					OP_NOT_R,
					OP_MOV_I,
					OP_ADD_I,
					OP_SETF,
					OP_MOVEA,
					OP_ADDI,
					OP_ORI,
					OP_ANDI,
					OP_XORI,
					OP_MOVHI: retire_df_producer_fn = reg_producer_fn(iw[25:21]);

					// Silicon unknown: use V830 DF shift forwarding and retain WB tracking.
					OP_SHL_R,
					OP_SHR_R,
					OP_SAR_R,
					OP_SHL_I,
					OP_SHR_I,
					OP_SAR_I: retire_df_producer_fn = reg_producer_fn(iw[25:21]);

					// Silicon unknown: use the V800-family MUL/DIV DF/WB split.
					OP_MUL,
					OP_MULU,
					OP_DIV,
					OP_DIVU: retire_df_producer_fn = reg_producer_fn(5'd30);

					default: retire_df_producer_fn = 6'd0;
				endcase
			end
		end
	endfunction

	function [6:0] retire_wb_producer_fn;
		input [31:0] iw;
		reg [5:0] op_v;
		reg [5:0] subop_v;
		begin
			op_v = iw[31:26];
			subop_v = iw[15:10];
			retire_wb_producer_fn = 7'd0;
			if (iw[31:29] == OP_BCOND) begin
				retire_wb_producer_fn = 7'd0;
			end else begin
				case (op_v)
					// Silicon unknown: keep unmeasured late results in the WB class.
					OP_SHL_R,
					OP_SHR_R,
					OP_SAR_R,
					OP_SHL_I,
					OP_SHR_I,
					OP_SAR_I,
					OP_STSR,
					OP_LD_B,
					OP_LD_H,
					OP_LD_W,
					OP_IN_B,
					OP_IN_H,
					OP_IN_W,
					OP_CAXI: retire_wb_producer_fn = wb_reg_producer_fn(iw[25:21]);

					// Keep long-op destinations tagged until retire forwards the result.
					OP_MUL,
					OP_DIV,
					OP_MULU,
					OP_DIVU: retire_wb_producer_fn = wb_reg_producer_fn(iw[25:21]);

					OP_BITSTR: retire_wb_producer_fn = 7'b1_0_00000;

					OP_EXT: begin
						case (subop_v)
							SUBOP_CVTWS,
							SUBOP_CVTSW,
							SUBOP_TRNCSW,
							SUBOP_ADDF,
							SUBOP_SUBF,
							SUBOP_MULF,
							SUBOP_DIVF,
							SUBOP_XB,
							SUBOP_REV,
							SUBOP_MPYHW: retire_wb_producer_fn = wb_reg_producer_fn(iw[25:21]);

							// XH uses normal one-cycle retire forwarding.
							SUBOP_XH: retire_wb_producer_fn = 7'd0;

							default: retire_wb_producer_fn = 7'd0;
						endcase
					end

					default: retire_wb_producer_fn = 7'd0;
				endcase
			end
		end
	endfunction

	function retire_df_flags_fn;
		input [31:0] iw;
		reg [5:0] op_v;
		begin
			op_v = iw[31:26];
			// Bcond opcodes (6'b100xxx) are unmapped here and fall to the default.
			case (op_v)
				// Silicon unknown: use V800/V830 DF timing for MUL/DIV flags.
				OP_MUL,
				OP_DIV,
				OP_MULU,
				OP_DIVU: retire_df_flags_fn = 1'b1;

				default: retire_df_flags_fn = 1'b0;
			endcase
		end
	endfunction

	function retire_wb_flags_fn;
		input [31:0] iw;
		reg [5:0] op_v;
		reg [5:0] subop_v;
		begin
			op_v = iw[31:26];
			subop_v = iw[15:10];
			// Bcond opcodes (6'b100xxx) are unmapped here and fall to the default.
			case (op_v)
				// Silicon unknown: keep other late flag producers in WB.
				OP_SHL_R,
				OP_SHR_R,
				OP_SAR_R,
				OP_OR_R,
				OP_AND_R,
				OP_XOR_R,
				OP_NOT_R,
				OP_SHL_I,
				OP_SHR_I,
				OP_SAR_I,
				OP_ORI,
				OP_ANDI,
				OP_XORI,
				OP_CAXI,
				OP_BITSTR: retire_wb_flags_fn = 1'b1;

				OP_EXT: begin
					case (subop_v)
						SUBOP_CMPF,
						SUBOP_CVTWS,
						SUBOP_CVTSW,
						SUBOP_TRNCSW,
						SUBOP_ADDF,
						SUBOP_SUBF,
						SUBOP_MULF,
						SUBOP_DIVF: retire_wb_flags_fn = 1'b1;

						default: retire_wb_flags_fn = 1'b0;
					endcase
				end

				default: retire_wb_flags_fn = 1'b0;
			endcase
		end
	endfunction

	function [1:0] front_wait_cycles_fn;
		input [31:0] iw;
		input [5:0]  hazard_df_producer;
		input [6:0]  hazard_wb_producer;
		input        hazard_df_flags;
		input        hazard_wb_flags;
		input        store_load_hold;
		reg [3:0] read_class_v;
		reg [5:0] op_v;
		reg       df_match_v;
		reg       wb_match_v;
		reg       memory_base_match_v;
		begin
			op_v = iw[31:26];
			read_class_v = instr_read_class_fn(iw);
			df_match_v = hazard_df_producer[5] &&
				read_class_reg_match_fn(read_class_v, iw[20:16], iw[25:21], hazard_df_producer[4:0]);
			wb_match_v =
				(hazard_wb_producer[5] &&
				 read_class_reg_match_fn(read_class_v, iw[20:16], iw[25:21], hazard_wb_producer[4:0])) ||
				(hazard_wb_producer[6] &&
				 read_class_bitstr_match_fn(read_class_v, iw[20:16], iw[25:21]));
			memory_base_match_v =
				hazard_df_producer[5] &&
				instr_uses_memory_base_fn(op_v) &&
				(iw[20:16] == hazard_df_producer[4:0]);
			// Arithmetic flags are EX-ready; late flags, memory-base matches,
			// and WB-only matches all need the same two-cycle hold.
			if ((instr_flag_consumer_fn(iw) && (hazard_df_flags || hazard_wb_flags)) ||
				memory_base_match_v ||
				(wb_match_v && !df_match_v && (op_v != OP_DIV) && (op_v != OP_DIVU))) begin
				front_wait_cycles_fn = 2'd2;
			end else if (store_load_hold && instr_is_load_family_fn(iw)) begin
				front_wait_cycles_fn = 2'd1;
			end else begin
				front_wait_cycles_fn = 2'd0;
			end
		end
	endfunction

	function [31:0] chcw_readback_fn;
		input cache_enable;
		begin
			// CHCW reads back only ICE; all other fields are zero.
			chcw_readback_fn = {30'd0, cache_enable, 1'b0};
		end
	endfunction

	function [31:0] sysreg_read_fn;
		input [4:0] regid;
		input [31:0] eipc;
		input [31:0] eipsw;
		input [31:0] fepc;
		input [31:0] fepsw;
		input [31:0] ecr;
		input [31:0] psw;
		input [31:0] adtre;
		input [31:0] sr29;
		input [31:0] sr31;
		input        cache_enable;
		begin
			case (regid)
				SYS_EIPC:  sysreg_read_fn = eipc;
				SYS_EIPSW: sysreg_read_fn = eipsw;
				SYS_FEPC:  sysreg_read_fn = fepc;
				SYS_FEPSW: sysreg_read_fn = fepsw;
				SYS_ECR:   sysreg_read_fn = ecr;
				SYS_PSW:   sysreg_read_fn = psw;
				SYS_PIR:   sysreg_read_fn = PIR_VALUE;
				SYS_TKCW:  sysreg_read_fn = TKCW_VALUE;
				SYS_CHCW:  sysreg_read_fn = chcw_readback_fn(cache_enable);
				SYS_ADTRE: sysreg_read_fn = adtre;
				SYS_SR29:  sysreg_read_fn = sr29;
				SYS_SR30:  sysreg_read_fn = SR30_VALUE;
				SYS_SR31:  sysreg_read_fn = sr31[31] ? (~sr31 + 32'd1) : sr31;
				default:   sysreg_read_fn = 32'd0;
			endcase
		end
	endfunction

	function [5:0] decode_uentry_fn;
		input [31:0] iw;
		begin
			// Silicon unknown: ignore unused instruction fields even when nonzero.
			if (iw[31:29] == OP_BCOND) begin
				decode_uentry_fn = UADDR_BCOND;
			end else begin
				case (iw[31:26])
					OP_MOV_R:  decode_uentry_fn = UADDR_MOV_R;
					OP_ADD_R:  decode_uentry_fn = UADDR_ADD_R;
					OP_SUB_R:  decode_uentry_fn = UADDR_SUB_R;
					OP_CMP_R:  decode_uentry_fn = UADDR_CMP_R;
					OP_SHL_R:  decode_uentry_fn = UADDR_SHL_R;
					OP_SHR_R:  decode_uentry_fn = UADDR_SHR_R;
					OP_JMP:    decode_uentry_fn = UADDR_JMP;
					OP_SAR_R:  decode_uentry_fn = UADDR_SAR_R;
					OP_MUL:    decode_uentry_fn = UADDR_MUL;
					OP_DIV:    decode_uentry_fn = UADDR_DIV;
					OP_MULU:   decode_uentry_fn = UADDR_MULU;
					OP_DIVU:   decode_uentry_fn = UADDR_DIVU;
					OP_OR_R:   decode_uentry_fn = UADDR_OR_R;
					OP_AND_R:  decode_uentry_fn = UADDR_AND_R;
					OP_XOR_R:  decode_uentry_fn = UADDR_XOR_R;
					OP_NOT_R:  decode_uentry_fn = UADDR_NOT_R;
					OP_MOV_I:  decode_uentry_fn = UADDR_MOV_I;
					OP_ADD_I:  decode_uentry_fn = UADDR_ADD_I;
					OP_SETF:   decode_uentry_fn = UADDR_SETF;
					OP_CMP_I:  decode_uentry_fn = UADDR_CMP_I;
					OP_SHL_I:  decode_uentry_fn = UADDR_SHL_I;
					OP_SHR_I:  decode_uentry_fn = UADDR_SHR_I;
					OP_CLI:    decode_uentry_fn = UADDR_CLI;
					OP_SAR_I:  decode_uentry_fn = UADDR_SAR_I;
					OP_TRAP:   decode_uentry_fn = UADDR_TRAP;
					OP_RETI:   decode_uentry_fn = UADDR_RETI;
					OP_HALT:   decode_uentry_fn = UADDR_HALT;
					OP_LDSR:   decode_uentry_fn = UADDR_LDSR;
					OP_STSR:   decode_uentry_fn = UADDR_STSR;
					OP_SEI:    decode_uentry_fn = UADDR_SEI;
					OP_BITSTR: begin
						// Bit-string subop is iw[20:16] in the packed fetch word.
						case (iw[20:16])
							SUBOP_SCH0BSU,
							SUBOP_SCH0BSD,
							SUBOP_SCH1BSU,
							SUBOP_SCH1BSD,
							SUBOP_ORBSU,
							SUBOP_ANDBSU,
							SUBOP_XORBSU,
							SUBOP_MOVBSU,
							SUBOP_ORNBSU,
							SUBOP_ANDNBSU,
							SUBOP_XORNBSU,
							SUBOP_NOTBSU: decode_uentry_fn = UADDR_BITSTR;
							default:      decode_uentry_fn = UADDR_ILL;
						endcase
					end
					OP_MOVEA:  decode_uentry_fn = UADDR_MOVEA;
					OP_ADDI:   decode_uentry_fn = UADDR_ADDI;
					OP_JR:     decode_uentry_fn = UADDR_JR;
					OP_JAL:    decode_uentry_fn = UADDR_JAL;
					OP_ORI:    decode_uentry_fn = UADDR_ORI;
					OP_ANDI:   decode_uentry_fn = UADDR_ANDI;
					OP_XORI:   decode_uentry_fn = UADDR_XORI;
					OP_MOVHI:  decode_uentry_fn = UADDR_MOVHI;
					OP_LD_B:   decode_uentry_fn = UADDR_MEM_LD_B;
					OP_LD_H:   decode_uentry_fn = UADDR_MEM_LD_H;
					OP_LD_W:   decode_uentry_fn = UADDR_MEM_LD_W;
					OP_ST_B:   decode_uentry_fn = UADDR_MEM_ST_B;
					OP_ST_H:   decode_uentry_fn = UADDR_MEM_ST_H;
					OP_ST_W:   decode_uentry_fn = UADDR_MEM_ST_W;
					OP_IN_B:   decode_uentry_fn = UADDR_MEM_IN_B;
					OP_IN_H:   decode_uentry_fn = UADDR_MEM_IN_H;
					OP_CAXI:   decode_uentry_fn = UADDR_CAXI;
					OP_IN_W:   decode_uentry_fn = UADDR_MEM_IN_W;
					OP_OUT_B:  decode_uentry_fn = UADDR_MEM_OUT_B;
					OP_OUT_H:  decode_uentry_fn = UADDR_MEM_OUT_H;
					OP_EXT: begin
						case (iw[15:10])
							SUBOP_CMPF:  decode_uentry_fn = UADDR_CMPF;
							SUBOP_CVTWS: decode_uentry_fn = UADDR_CVTWS;
							SUBOP_CVTSW,
							SUBOP_TRNCSW: decode_uentry_fn = UADDR_CVTSW;
							SUBOP_ADDF,
							SUBOP_SUBF,
							SUBOP_MULF,
							SUBOP_DIVF: decode_uentry_fn = UADDR_FPU;
							SUBOP_XB:    decode_uentry_fn = UADDR_XB;
							SUBOP_XH:    decode_uentry_fn = UADDR_XH;
							SUBOP_REV:   decode_uentry_fn = UADDR_REV;
							SUBOP_MPYHW: decode_uentry_fn = UADDR_MPYHW;
							default:     decode_uentry_fn = UADDR_ILL;
						endcase
					end
					OP_OUT_W:  decode_uentry_fn = UADDR_MEM_OUT_W;
					default:   decode_uentry_fn = UADDR_ILL;
				endcase
			end
		end
	endfunction

	function interrupt_accepted_fn;
		input       irq_valid;
		input [3:0] irq_level;
		input [31:0] psw;
		begin
			interrupt_accepted_fn =
				irq_valid &&
				((psw & PSW_ID_MASK) == 32'd0) &&
				((psw & PSW_EP_MASK) == 32'd0) &&
				((psw & PSW_NP_MASK) == 32'd0) &&
				(psw_interrupt_level_fn(psw) <= irq_level);
		end
	endfunction

	function nmi_accepted_fn;
		input        nmi_valid;
		input [31:0] psw;
		begin
			nmi_accepted_fn =
				nmi_valid &&
				((psw & PSW_NP_MASK) == 32'd0);
		end
	endfunction

	function [1:0] async_exception_kind_fn;
		input addr_trap;
		input nmi_accept;
		input irq_accept;
		begin
			if (nmi_accept) begin
				async_exception_kind_fn = ASYNC_EXC_NMI;
			end else if (irq_accept) begin
				async_exception_kind_fn = ASYNC_EXC_IRQ;
			end else if (addr_trap) begin
				async_exception_kind_fn = ASYNC_EXC_ADDR;
			end else begin
				async_exception_kind_fn = ASYNC_EXC_NONE;
			end
		end
	endfunction

	function [15:0] async_exception_code_fn;
		input [1:0] kind;
		input [3:0] irq_level;
		begin
			case (kind)
				ASYNC_EXC_ADDR: async_exception_code_fn = EXC_CODE_ADDRTRAP;
				ASYNC_EXC_NMI:  async_exception_code_fn = EXC_CODE_NMI;
				ASYNC_EXC_IRQ:  async_exception_code_fn = irq_code_fn(irq_level);
				default:        async_exception_code_fn = 16'd0;
			endcase
		end
	endfunction

	function [31:0] fatal_wdata_fn;
		input [1:0]  index;
		input [15:0] exc_code;
		input [31:0] psw;
		input [31:0] pc;
		begin
			case (index)
				2'd0: fatal_wdata_fn = {16'hffff, exc_code};
				2'd1: fatal_wdata_fn = psw;
				default: fatal_wdata_fn = pc;
			endcase
		end
	endfunction

	function [3:0] psw_interrupt_level_fn;
		input [31:0] psw;
		begin
			psw_interrupt_level_fn = psw[19:16];
		end
	endfunction

	function [15:0] irq_code_fn;
		input [3:0] irq_level;
		begin
			irq_code_fn = 16'hfe00 + {8'd0, irq_level, 4'b0000};
		end
	endfunction

	function [31:0] instr_len_bytes_fn;
		input [15:0] iw;
		begin
			instr_len_bytes_fn = instr_needs_second_half_fn(iw) ? 32'd4 : 32'd2;
		end
	endfunction

	function branch_taken_fn;
		input [3:0] cond;
		input [31:0] psw;
		reg zf;
		reg sf;
		reg ovf;
		reg cyf;
		begin
			zf = psw[0];
			sf = psw[1];
			ovf = psw[2];
			cyf = psw[3];
			case (cond)
				4'd0: branch_taken_fn = ovf;
				4'd1: branch_taken_fn = cyf;
				4'd2: branch_taken_fn = zf;
				4'd3: branch_taken_fn = cyf | zf;
				4'd4: branch_taken_fn = sf;
				4'd5: branch_taken_fn = 1'b1;
				4'd6: branch_taken_fn = ovf ^ sf;
				4'd7: branch_taken_fn = (ovf ^ sf) | zf;
				4'd8: branch_taken_fn = !ovf;
				4'd9: branch_taken_fn = !cyf;
				4'd10: branch_taken_fn = !zf;
				4'd11: branch_taken_fn = !(cyf | zf);
				4'd12: branch_taken_fn = !sf;
				4'd13: branch_taken_fn = 1'b0;
				4'd14: branch_taken_fn = !(ovf ^ sf);
				default: branch_taken_fn = !((ovf ^ sf) | zf);
			endcase
		end
	endfunction

	function issue_condition_fn;
		input [5:0]  uentry;
		input [31:0] iw;
		input [31:0] psw;
		begin
			case (uentry)
				UADDR_BCOND: issue_condition_fn = branch_taken_fn(iw[28:25], psw);
				UADDR_SETF: issue_condition_fn = branch_taken_fn(iw[19:16], psw);
				default: issue_condition_fn = 1'b0;
			endcase
		end
	endfunction

endmodule

module NECv810_icache_data_ram
(
	input  wire        clk_i,
	input  wire [6:0]  read_addr_i,
	input  wire [6:0]  write_addr_i,
	input  wire        write_en_i,
	input  wire [63:0] write_data_i,
	output wire [63:0] q_o,
	input  wire        savestate_active_i,
	input  wire [9:0]  savestate_addr_i,
	input  wire        savestate_rden_i,
	input  wire        savestate_wren_i,
	input  wire [7:0]  savestate_wdata_i,
	output reg  [7:0]  savestate_rdata_o
);
	wire [63:0] ram_q_w;
	reg [63:0] savestate_merged_data_v;

	assign q_o = ram_q_w;

	// Byte-lane select within the addressed 64-bit cache line.
	always @* begin
		savestate_rdata_o = savestate_rden_i ?
			ram_q_w[{savestate_addr_i[2:0], 3'b000} +: 8] : 8'd0;
		savestate_merged_data_v = ram_q_w;
		savestate_merged_data_v[{savestate_addr_i[2:0], 3'b000} +: 8] =
			savestate_wdata_i;
	end

	cache_ram_dp
	#(
		.ADDR_WIDTH(7),
		.DATA_WIDTH(64)
	)
	u_icache_data
	(
		.clk_i(clk_i),
		.addr_a_i(savestate_active_i ? savestate_addr_i[9:3] : read_addr_i),
		.wren_a_i(1'b0),
		.wdata_a_i(64'd0),
		.q_a_o(ram_q_w),
		.addr_b_i(savestate_active_i ? savestate_addr_i[9:3] : write_addr_i),
		.wren_b_i(savestate_active_i ? savestate_wren_i : write_en_i),
		.wdata_b_i(savestate_active_i ? savestate_merged_data_v : write_data_i),
		.q_b_o()
	);

endmodule

module NECv810_icache_tag_ram
(
	input  wire        clk_i,
	input  wire [6:0]  read_addr_i,
	input  wire [6:0]  write_addr_i,
	input  wire        write_en_i,
	input  wire [31:0] write_data_i,
	output wire [31:0] q_o,
	input  wire        savestate_active_i,
	input  wire [8:0]  savestate_addr_i,
	input  wire        savestate_rden_i,
	input  wire        savestate_wren_i,
	input  wire [7:0]  savestate_wdata_i,
	output reg  [7:0]  savestate_rdata_o
);
	wire [31:0] ram_q_w;
	reg [31:0] savestate_merged_data_v;

	assign q_o = ram_q_w;

	// Byte-lane select within the addressed 32-bit tag word.
	always @* begin
		savestate_rdata_o = savestate_rden_i ?
			ram_q_w[{savestate_addr_i[1:0], 3'b000} +: 8] : 8'd0;
		savestate_merged_data_v = ram_q_w;
		savestate_merged_data_v[{savestate_addr_i[1:0], 3'b000} +: 8] =
			savestate_wdata_i;
	end

	cache_ram_dp
	#(
		.ADDR_WIDTH(7),
		.DATA_WIDTH(32)
	)
	u_icache_tag
	(
		.clk_i(clk_i),
		.addr_a_i(savestate_active_i ? savestate_addr_i[8:2] : read_addr_i),
		.wren_a_i(1'b0),
		.wdata_a_i(32'd0),
		.q_a_o(ram_q_w),
		.addr_b_i(savestate_active_i ? savestate_addr_i[8:2] : write_addr_i),
		.wren_b_i(savestate_active_i ? savestate_wren_i : write_en_i),
		.wdata_b_i(savestate_active_i ? savestate_merged_data_v : write_data_i),
		.q_b_o()
	);

endmodule

// altera message_off 10030
module NECv810_ucode_rom
(
	input  wire        clk_i,
	input  wire        ce_i,
	input  wire [5:0]  addr_i,
	output reg  [31:0] q_o
);

	localparam [3:0] MK_NOP    = 4'd0;
	localparam [3:0] MK_ALU    = 4'd1;
	localparam [3:0] MK_BRANCH = 4'd2;
	localparam [3:0] MK_MEM    = 4'd3;
	localparam [3:0] MK_LDSR   = 4'd4;
	localparam [3:0] MK_STSR   = 4'd5;
	localparam [3:0] MK_HALT   = 4'd6;
	localparam [3:0] MK_TRAP   = 4'd7;
	localparam [3:0] MK_RETI   = 4'd8;
	localparam [3:0] MK_LONG   = 4'd9;
	localparam [3:0] MK_CAXI   = 4'd10;
	localparam [3:0] MK_BITSTR = 4'd11;
	localparam [3:0] MK_ILL    = 4'd15;

	localparam [3:0] ALU_PASS_A = 4'd0;
	localparam [3:0] ALU_PASS_B = 4'd1;
	localparam [3:0] ALU_ADD    = 4'd2;
	localparam [3:0] ALU_SUB    = 4'd3;
	localparam [3:0] ALU_OR     = 4'd4;
	localparam [3:0] ALU_AND    = 4'd5;
	localparam [3:0] ALU_XOR    = 4'd6;
	localparam [3:0] ALU_NOT    = 4'd7;
	localparam [3:0] ALU_SHL    = 4'd8;
	localparam [3:0] ALU_SHR    = 4'd9;
	localparam [3:0] ALU_SAR    = 4'd10;
	localparam [3:0] ALU_SETF   = 4'd11;
	localparam [3:0] LONG_CLI   = 4'd0;
	localparam [3:0] LONG_SEI   = 4'd1;
	localparam [3:0] LONG_XB    = 4'd2;
	localparam [3:0] LONG_XH    = 4'd3;
	localparam [3:0] LONG_REV   = 4'd4;
	localparam [3:0] LONG_MPYHW = 4'd5;
	localparam [3:0] LONG_CMPF  = 4'd6;
	localparam [3:0] LONG_CVTWS = 4'd7;
	localparam [3:0] LONG_CVTSW = 4'd8;
	// 4'd9 (TRNCSW) and 4'd11 (SUBF) exist in the parent's LONG_* encoding but
	// never appear in ROM entries; CVTSW and ADDF are their shared entries.
	localparam [3:0] LONG_ADDF  = 4'd10;
	localparam [3:0] LONG_MUL   = 4'd12;
	localparam [3:0] LONG_DIV   = 4'd13;
	localparam [3:0] LONG_MULU  = 4'd14;
	localparam [3:0] LONG_DIVU  = 4'd15;

	localparam [1:0] SA_ZERO = 2'd0;
	localparam [1:0] SA_REG1 = 2'd1;
	localparam [1:0] SA_REG2 = 2'd2;
	localparam [1:0] SA_PC   = 2'd3;

	localparam [3:0] SB_ZERO   = 4'd0;
	localparam [3:0] SB_REG1   = 4'd1;
	// 4'd2 (SB_REG2) exists in the parent's encoding but no ROM entry uses it.
	localparam [3:0] SB_IMM5S  = 4'd3;
	localparam [3:0] SB_IMM16S = 4'd4;
	localparam [3:0] SB_IMM16Z = 4'd5;
	localparam [3:0] SB_IMM16H = 4'd6;
	localparam [3:0] SB_IMM26S = 4'd7;
	localparam [3:0] SB_IMM5Z  = 4'd8;

	localparam [1:0] SIZE_B = 2'b00;
	localparam [1:0] SIZE_H = 2'b01;
	localparam [1:0] SIZE_W = 2'b10;

	function [31:0] pack_ucode_fn;
		input [3:0] kind;
		input [3:0] alu_op;
		input [1:0] srca;
		input [3:0] srcb;
		input       write_gpr;
		input       write_psw;
		input       write_link;
		input       pc_from_result;
		input       pc_from_bcond;
		input       mem_write;
		input       mem_io;
		input [1:0] mem_size;
		input       mem_signext;
		input       end_uop;
		input [5:0] next_addr;
		input       halt_uop;
		begin
			pack_ucode_fn = 32'd0;
			pack_ucode_fn[3:0] = kind;
			pack_ucode_fn[7:4] = alu_op;
			pack_ucode_fn[9:8] = srca;
			pack_ucode_fn[13:10] = srcb;
			pack_ucode_fn[14] = write_gpr;
			pack_ucode_fn[15] = write_psw;
			pack_ucode_fn[16] = write_link;
			pack_ucode_fn[17] = pc_from_result;
			pack_ucode_fn[18] = pc_from_bcond;
			pack_ucode_fn[19] = mem_write;
			pack_ucode_fn[20] = mem_io;
			pack_ucode_fn[22:21] = mem_size;
			pack_ucode_fn[23] = mem_signext;
			pack_ucode_fn[24] = end_uop;
			pack_ucode_fn[30:25] = next_addr;
			pack_ucode_fn[31] = halt_uop;
		end
	endfunction

	(* romstyle = "M10K" *) reg [31:0] rom_q [0:63];
	integer ucode_idx;

	initial begin
		for (ucode_idx = 0; ucode_idx < 64; ucode_idx = ucode_idx + 1) begin
			rom_q[ucode_idx] = pack_ucode_fn(MK_ILL, ALU_PASS_A, SA_ZERO, SB_ZERO, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0, 1'b0); // Unmapped opcode.
		end

		// pack_ucode_fn fields, in order:
		// kind, alu_op, srca, srcb,
		// write_gpr, write_psw, write_link, pc_from_result, pc_from_bcond,
		// mem_write, mem_io, mem_size, mem_signext,
		// end_uop, next_addr, halt_uop.
		rom_q[6'd0]  = pack_ucode_fn(MK_NOP,    ALU_PASS_A, SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // NOP
		rom_q[6'd1]  = pack_ucode_fn(MK_ALU,    ALU_PASS_A, SA_REG1, SB_ZERO,   1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // MOV r1, r2
		rom_q[6'd2]  = pack_ucode_fn(MK_ALU,    ALU_ADD,    SA_REG2, SB_REG1,   1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // ADD r1, r2
		rom_q[6'd3]  = pack_ucode_fn(MK_ALU,    ALU_SUB,    SA_REG2, SB_REG1,   1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // SUB r1, r2
		rom_q[6'd4]  = pack_ucode_fn(MK_ALU,    ALU_SUB,    SA_REG2, SB_REG1,   1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // CMP r1, r2
		rom_q[6'd5]  = pack_ucode_fn(MK_ALU,    ALU_SHL,    SA_REG2, SB_REG1,   1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // SHL r1, r2
		rom_q[6'd6]  = pack_ucode_fn(MK_ALU,    ALU_SHR,    SA_REG2, SB_REG1,   1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // SHR r1, r2
		rom_q[6'd7]  = pack_ucode_fn(MK_ALU,    ALU_PASS_A, SA_REG1, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // JMP [r1]
		rom_q[6'd8]  = pack_ucode_fn(MK_ALU,    ALU_SAR,    SA_REG2, SB_REG1,   1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // SAR r1, r2
		rom_q[6'd9]  = pack_ucode_fn(MK_ALU,    ALU_OR,     SA_REG2, SB_REG1,   1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // OR r1, r2
		rom_q[6'd10] = pack_ucode_fn(MK_ALU,    ALU_AND,    SA_REG2, SB_REG1,   1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // AND r1, r2
		rom_q[6'd11] = pack_ucode_fn(MK_ALU,    ALU_XOR,    SA_REG2, SB_REG1,   1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // XOR r1, r2
		rom_q[6'd12] = pack_ucode_fn(MK_ALU,    ALU_NOT,    SA_REG1, SB_ZERO,   1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // NOT r1, r2
		rom_q[6'd13] = pack_ucode_fn(MK_ALU,    ALU_PASS_B, SA_ZERO, SB_IMM5S,  1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // MOV imm5, r2
		rom_q[6'd14] = pack_ucode_fn(MK_ALU,    ALU_ADD,    SA_REG2, SB_IMM5S,  1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // ADD imm5, r2
		rom_q[6'd15] = pack_ucode_fn(MK_ALU,    ALU_SETF,   SA_ZERO, SB_ZERO,   1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // SETF cond, r2
		rom_q[6'd16] = pack_ucode_fn(MK_ALU,    ALU_SUB,    SA_REG2, SB_IMM5S,  1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // CMP imm5, r2
		rom_q[6'd17] = pack_ucode_fn(MK_ALU,    ALU_SHL,    SA_REG2, SB_IMM5Z,  1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // SHL imm5, r2
		rom_q[6'd18] = pack_ucode_fn(MK_ALU,    ALU_SHR,    SA_REG2, SB_IMM5Z,  1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // SHR imm5, r2
		rom_q[6'd19] = pack_ucode_fn(MK_ALU,    ALU_SAR,    SA_REG2, SB_IMM5Z,  1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // SAR imm5, r2
		rom_q[6'd20] = pack_ucode_fn(MK_HALT,   ALU_PASS_A, SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b1); // HALT
		rom_q[6'd21] = pack_ucode_fn(MK_LDSR,   ALU_PASS_A, SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // LDSR
		rom_q[6'd22] = pack_ucode_fn(MK_STSR,   ALU_PASS_A, SA_ZERO, SB_ZERO,   1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // STSR
		rom_q[6'd23] = pack_ucode_fn(MK_BRANCH, ALU_PASS_A, SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // Bcond
		rom_q[6'd24] = pack_ucode_fn(MK_ALU,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // MOVEA
		rom_q[6'd25] = pack_ucode_fn(MK_ALU,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // ADDI
		rom_q[6'd26] = pack_ucode_fn(MK_ALU,    ALU_ADD,    SA_PC,   SB_IMM26S, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // JR
		rom_q[6'd27] = pack_ucode_fn(MK_ALU,    ALU_ADD,    SA_PC,   SB_IMM26S, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // JAL
		rom_q[6'd28] = pack_ucode_fn(MK_ALU,    ALU_OR,     SA_REG1, SB_IMM16Z, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // ORI
		rom_q[6'd29] = pack_ucode_fn(MK_ALU,    ALU_AND,    SA_REG1, SB_IMM16Z, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // ANDI
		rom_q[6'd30] = pack_ucode_fn(MK_ALU,    ALU_XOR,    SA_REG1, SB_IMM16Z, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // XORI
		rom_q[6'd31] = pack_ucode_fn(MK_ALU,    ALU_ADD,    SA_REG1, SB_IMM16H, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // MOVHI
		rom_q[6'd32] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_B, 1'b1, 1'b1, 6'd0,  1'b0); // LD.B
		rom_q[6'd33] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b1, 1'b1, 6'd0,  1'b0); // LD.H
		rom_q[6'd34] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_W, 1'b0, 1'b1, 6'd0,  1'b0); // LD.W
		rom_q[6'd35] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, SIZE_B, 1'b0, 1'b1, 6'd0,  1'b0); // ST.B
		rom_q[6'd36] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // ST.H
		rom_q[6'd37] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, SIZE_W, 1'b0, 1'b1, 6'd0,  1'b0); // ST.W
		rom_q[6'd38] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, SIZE_B, 1'b0, 1'b1, 6'd0,  1'b0); // IN.B
		rom_q[6'd39] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // IN.H
		rom_q[6'd40] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, SIZE_W, 1'b0, 1'b1, 6'd0,  1'b0); // IN.W
		rom_q[6'd41] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, SIZE_B, 1'b0, 1'b1, 6'd0,  1'b0); // OUT.B
		rom_q[6'd42] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // OUT.H
		rom_q[6'd43] = pack_ucode_fn(MK_MEM,    ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, SIZE_W, 1'b0, 1'b1, 6'd0,  1'b0); // OUT.W
		rom_q[6'd44] = pack_ucode_fn(MK_TRAP,   ALU_PASS_A, SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // TRAP
		rom_q[6'd45] = pack_ucode_fn(MK_RETI,   ALU_PASS_A, SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // RETI
		rom_q[6'd46] = pack_ucode_fn(MK_LONG,   LONG_MUL,   SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // MUL
		rom_q[6'd47] = pack_ucode_fn(MK_LONG,   LONG_DIV,   SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // DIV
		rom_q[6'd48] = pack_ucode_fn(MK_LONG,   LONG_MULU,  SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // MULU
		rom_q[6'd49] = pack_ucode_fn(MK_LONG,   LONG_DIVU,  SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // DIVU
		rom_q[6'd50] = pack_ucode_fn(MK_LONG,   LONG_CLI,   SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // CLI
		rom_q[6'd51] = pack_ucode_fn(MK_LONG,   LONG_SEI,   SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // SEI
		rom_q[6'd52] = pack_ucode_fn(MK_LONG,   LONG_XB,    SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // XB
		rom_q[6'd53] = pack_ucode_fn(MK_LONG,   LONG_XH,    SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // XH
		rom_q[6'd54] = pack_ucode_fn(MK_LONG,   LONG_REV,   SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // REV
		rom_q[6'd55] = pack_ucode_fn(MK_LONG,   LONG_MPYHW, SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // MPYHW
		rom_q[6'd56] = pack_ucode_fn(MK_CAXI,   ALU_ADD,    SA_REG1, SB_IMM16S, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_W, 1'b0, 1'b1, 6'd0,  1'b0); // CAXI
		rom_q[6'd57] = pack_ucode_fn(MK_BITSTR, ALU_PASS_A, SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_W, 1'b0, 1'b1, 6'd0,  1'b0); // Bit-string family
		rom_q[6'd58] = pack_ucode_fn(MK_LONG,   LONG_CMPF,  SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // CMPF.S
		rom_q[6'd59] = pack_ucode_fn(MK_LONG,   LONG_CVTWS, SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // CVT.WS
		rom_q[6'd60] = pack_ucode_fn(MK_LONG,   LONG_CVTSW, SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // CVT.SW / TRNC.SW shared entry
		rom_q[6'd61] = pack_ucode_fn(MK_LONG,   LONG_ADDF,  SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // ADDF.S / SUBF.S / MULF.S / DIVF.S shared entry
		rom_q[6'd62] = pack_ucode_fn(MK_ILL,    ALU_PASS_A, SA_ZERO, SB_ZERO,   1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, SIZE_H, 1'b0, 1'b1, 6'd0,  1'b0); // Illegal-op sentinel.
	end

	always @(posedge clk_i) begin
		if (ce_i) begin
			q_o <= rom_q[addr_i];
		end
	end

endmodule
// altera message_on 10030
