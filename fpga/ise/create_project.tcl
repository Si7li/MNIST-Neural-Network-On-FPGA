project new nexys3_digits.xise

project set family "Spartan6"
project set device "xc6slx16"
project set package "csg324"
project set speed "-2"
project set "Preferred Language" "VHDL"

xfile add "../../src/full_adder.vhd"
xfile add "../../src/adder_n.vhd"
xfile add "../../src/mult_su.vhd"
xfile add "../../src/relu_shift_sat.vhd"
xfile add "../../src/comparator_gt.vhd"
xfile add "../../fpga/src/mlp_params.vhd"
xfile add "../../fpga/src/reg_n.vhd"
xfile add "../../src/max2.vhd"
xfile add "../../src/argmax10.vhd"
xfile add "../../fpga/src/weights_rom32.vhd"
xfile add "../../fpga/src/mac_unit.vhd"
xfile add "../../fpga/src/mlp_par32.vhd"
xfile add "../../fpga/src/bits_pkg.vhd"
xfile add "../../fpga/src/uart_rx.vhd"
xfile add "../../fpga/src/uart_tx.vhd"
xfile add "../../fpga/src/hidden_tx.vhd"
xfile add "../../fpga/src/frame_rx.vhd"
xfile add "../../fpga/src/seg7.vhd"
xfile add "../../fpga/src/nexys3_top.vhd"

xfile add "../nexys3.ucf"

project set top "structural" "nexys3_top"
project save
project close

project open nexys3_digits.xise
project set "FPGA Start-Up Clock" "JTAG Clock" -process "Generate Programming File"
puts "FPGA Start-Up Clock: [project get "FPGA Start-Up Clock" -process "Generate Programming File"]"
project save
project close
