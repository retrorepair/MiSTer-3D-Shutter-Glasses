derive_pll_clocks
derive_clock_uncertainty

# Core-specific constraints.

# Runtime ROM and cartridge-SRAM transactions remain stable while READY is low.
# clk_ram (120 MHz) is 3x clk_sys (40 MHz) from the same PLL, so the domains are
# phase-aligned. The first capture bank (meta) is allowed to miss the edge
# immediately following a 40 MHz launch; the second stage (sync) resolves the
# crossing. Control (req/tag) and payload now share this two-stage depth, so
# only a settled bundle reaches the protected SDRAM controller. All paths after
# this bank keep ordinary 120 MHz single-cycle timing.
set cart_runtime_capture_regs [get_registers {
	*|vb_cart_sdram:u_sdram|read_req_ram_meta_q
	*|vb_cart_sdram:u_sdram|read_tag_ram_meta_q
	*|vb_cart_sdram:u_sdram|read_addr_ram_meta_q[*]
	*|vb_cart_sdram:u_sdram|sram_req_ram_meta_q
	*|vb_cart_sdram:u_sdram|sram_we_ram_meta_q
	*|vb_cart_sdram:u_sdram|sram_addr_ram_meta_q[*]
	*|vb_cart_sdram:u_sdram|sram_data_ram_meta_q[*]
	*|vb_cart_sdram:u_sdram|sram_be_ram_meta_q[*]
	*|vb_cart_sdram:u_sdram|sram_lane_ram_meta_q
	*|vb_cart_sdram:u_sdram|sram_tag_ram_meta_q
}]

if {[get_collection_size $cart_runtime_capture_regs] == 0} {
	post_message -type error "No cartridge runtime input capture registers matched"
}

set_max_delay 10.000 -to $cart_runtime_capture_regs

# SDRAM pin timing (the generated SDRAM_CLK pin clock, command/address/write
# launch, and DDIO DQ capture) lives with the controller in rtl/Mem/sdram.sdc,
# which files.qip reads after this file. Only the wrapper-to-core crossings
# below belong to the integration.

# ROM and SRAM responses are held in complete tagged bundles until the 40 MHz
# side captures them. Their short register-to-register publication paths retain
# the real 5 ns related-clock setup requirement.
set cart_runtime_response_src_regs [get_registers {
	*|read_hold_valid_ram_q
	*|read_hold_tag_ram_q
	*|read_hold_data_ram_q[*]
	*|sram_access_hold_valid_ram_q
	*|sram_access_hold_tag_ram_q
	*|sram_data_hold_valid_ram_q
	*|sram_data_hold_tag_ram_q
	*|sram_data_hold_ram_q[*]
}]
set cart_runtime_response_dst_regs [get_registers {
	*|read_data_valid_sys_q
	*|read_data_tag_sys_q
	*|read_data_sys_q[*]
	*|sram_access_valid_sys_q
	*|sram_access_tag_sys_q
	*|sram_data_valid_sys_q
	*|sram_data_tag_sys_q
	*|sram_data_sys_q[*]
}]

if {[get_collection_size $cart_runtime_response_src_regs] == 0} {
	post_message -type error "No restored cartridge response sources matched"
}
if {[get_collection_size $cart_runtime_response_dst_regs] == 0} {
	post_message -type error "No restored 40 MHz cartridge response registers matched"
}

set_max_delay 5.000 \
	-from $cart_runtime_response_src_regs \
	-to $cart_runtime_response_dst_regs
