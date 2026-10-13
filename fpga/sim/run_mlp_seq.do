vlib work
vcom -work work src/full_adder.vhd
vcom -work work src/adder_n.vhd
vcom -work work src/mult_su.vhd
vcom -work work src/relu_shift_sat.vhd
vcom -work work src/comparator_gt.vhd
vcom -work work fpga/src/mlp_params.vhd
vcom -work work fpga/src/weights_rom.vhd
vcom -work work fpga/src/reg_n.vhd
vcom -work work fpga/src/mlp_seq.vhd
vcom -work work fpga/sim/mlp_seq_tb.vhd

vsim work.mlp_seq_tb

configure list -usestrobe 1 -strobestart {24900 ns} -strobeperiod {25000 ns}
add list -notrigger -radix decimal  /mlp_seq_tb/image_no
add list -notrigger -radix unsigned /mlp_seq_tb/digit
add list -notrigger -radix unsigned /mlp_seq_tb/expected
add list -notrigger -radix unsigned /mlp_seq_tb/true_label
add list -notrigger -radix binary   /mlp_seq_tb/match
add list -notrigger -radix hex      /mlp_seq_tb/dut/hid
add list -notrigger -radix decimal  /mlp_seq_tb/dut/best

run 9000 us
write list fpga/sim/results_seq.lst
echo "Results written to fpga/sim/results_seq.lst"
