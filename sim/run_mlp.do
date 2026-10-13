vlib work
vcom -work work src/full_adder.vhd
vcom -work work src/adder_n.vhd
vcom -work work src/mult_su.vhd
vcom -work work src/relu_shift_sat.vhd
vcom -work work src/comparator_gt.vhd
vcom -work work src/adder_tree.vhd
vcom -work work src/weights_pkg.vhd
vcom -work work src/max2.vhd
vcom -work work src/argmax10.vhd
vcom -work work src/neuron_n.vhd
vcom -work work src/mlp_digits.vhd
vcom -work work src/mlp_digits_tb.vhd

vsim work.mlp_digits_tb

configure list -usestrobe 1 -strobestart {5 ns} -strobeperiod {10 ns}
add list -notrigger -radix decimal  /mlp_digits_tb/image_no
add list -notrigger -radix unsigned /mlp_digits_tb/digit
add list -notrigger -radix unsigned /mlp_digits_tb/expected
add list -notrigger -radix unsigned /mlp_digits_tb/true_label
add list -notrigger -radix binary   /mlp_digits_tb/match

run 3600 ns
write list sim/results.lst
echo "Results written to sim/results.lst"
