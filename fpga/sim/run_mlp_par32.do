vlib work
vcom -work work src/full_adder.vhd
vcom -work work src/adder_n.vhd
vcom -work work src/mult_su.vhd
vcom -work work src/relu_shift_sat.vhd
vcom -work work src/comparator_gt.vhd
vcom -work work fpga/src/mlp_params.vhd
vcom -work work fpga/src/reg_n.vhd
vcom -work work src/max2.vhd
vcom -work work src/argmax10.vhd
vcom -work work fpga/src/weights_rom32.vhd
vcom -work work fpga/src/mac_unit.vhd
vcom -work work fpga/src/mlp_par32.vhd
vcom -work work fpga/sim/mlp_par32_tb.vhd

vsim work.mlp_par32_tb

configure list -usestrobe 1 -strobestart {1900 ns} -strobeperiod {2000 ns}
add list -notrigger -radix decimal  /mlp_par32_tb/image_no
add list -notrigger -radix unsigned /mlp_par32_tb/digit
add list -notrigger -radix unsigned /mlp_par32_tb/expected
add list -notrigger -radix unsigned /mlp_par32_tb/true_label
add list -notrigger -radix binary   /mlp_par32_tb/match
add list -notrigger -radix hex      /mlp_par32_tb/dut/hid
add list -notrigger -radix decimal  /mlp_par32_tb/dut/acc(0)
add list -notrigger -radix decimal  /mlp_par32_tb/dut/acc(1)
add list -notrigger -radix decimal  /mlp_par32_tb/dut/acc(2)
add list -notrigger -radix decimal  /mlp_par32_tb/dut/acc(3)
add list -notrigger -radix decimal  /mlp_par32_tb/dut/acc(4)
add list -notrigger -radix decimal  /mlp_par32_tb/dut/acc(5)
add list -notrigger -radix decimal  /mlp_par32_tb/dut/acc(6)
add list -notrigger -radix decimal  /mlp_par32_tb/dut/acc(7)
add list -notrigger -radix decimal  /mlp_par32_tb/dut/acc(8)
add list -notrigger -radix decimal  /mlp_par32_tb/dut/acc(9)

run 720 us
write list fpga/sim/results_par32.lst
echo "Results written to fpga/sim/results_par32.lst"
