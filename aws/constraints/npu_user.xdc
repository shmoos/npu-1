# Additive to the pinned shell/example constraints. Do not create a second
# clk_main_a0 clock or false-path the datapath to conceal timing failures.
# HDL ASYNC_REG marks reset-release synchronizers. Memory ram_style is in RTL.
# The shell owns clock period, partition pins, placement region and I/O delays.
# Inspect report_clocks and report_timing_summary for the ACTUAL shell recipe.
# Target: timing-clean at the shell's clk_main_a0 frequency; no achieved Fmax claim.
