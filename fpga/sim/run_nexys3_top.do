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
vcom -work work fpga/src/bits_pkg.vhd
vcom -work work fpga/src/uart_rx.vhd
vcom -work work fpga/src/uart_tx.vhd
vcom -work work fpga/src/hidden_tx.vhd
vcom -work work fpga/src/frame_rx.vhd
vcom -work work fpga/src/seg7.vhd
vcom -work work fpga/src/nexys3_top.vhd
vcom -work work fpga/sim/nexys3_top_tb.vhd

vsim work.nexys3_top_tb

configure list -usestrobe 1 -strobestart {127800 ns} -strobeperiod {128000 ns}
add list -notrigger -radix decimal  /nexys3_top_tb/image_no
add list -notrigger -radix binary   /nexys3_top_tb/led
add list -notrigger -radix binary   /nexys3_top_tb/seg
add list -notrigger -radix binary   /nexys3_top_tb/an

vcd file fpga/sim/top_txd.vcd
vcd add /nexys3_top_tb/txd

run 2738000 ns
write list fpga/sim/results_top.lst
vcd flush
echo "Results written to fpga/sim/results_top.lst and fpga/sim/top_txd.vcd"
