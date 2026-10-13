# Handwritten Digit Recognition on an FPGA

A small neural network that recognises handwritten digits, written in VHDL and running on a Digilent **Nexys 3** board (Xilinx Spartan-6). You draw a digit with the mouse on your PC, the image is sent to the FPGA over UART, and the board shows the predicted digit on its 7-segment display.

![Demo: drawing a digit on the PC and the FPGA recognising it](assets/demo.gif)

## Highlights

- **Network:** fully connected MLP, 64 → 32 (ReLU) → 10, 2,410 parameters
- **Accuracy:** 97.5 % on 360 test images, the same before and after 8-bit quantization
- **Bit-exact:** the VHDL gives exactly the same answer as the Python model on every test image
- **Fast:** one image is classified in 99 clock cycles (about 8 µs)
- **No IP cores:** adders, multipliers, comparators and the UART are built from scratch. The design uses no block RAM and no DSP slices.

## How it works

```
 PC (Python app)                         Nexys 3 FPGA
┌─────────────────┐   UART 115200   ┌───────────────────────────────────────────────┐
│ draw a digit    │ ──────────────► │ uart_rx → frame_rx → mlp_par32 → seg7 / LEDs  │
│ downscale 8×8   │   65 bytes      │                          │                    │
│ show hidden     │ ◄────────────── │                    hidden_tx                  │
│ layer activity  │   34 bytes      └───────────────────────────────────────────────┘
└─────────────────┘
```

1. **Training (Python / PyTorch):** the MLP is trained on the scikit-learn *digits* dataset (1,797 images of 8×8 pixels, 0–15 grey levels).
2. **Quantization:** weights become 8-bit signed fixed point (Q2.6), and the hidden layer is shifted by 5 bits so it fits in 8 bits. A bit-exact integer model checks that the accuracy doesn't drop.
3. **Export:** Python scripts generate the VHDL weight ROMs, constants and testbenches from the trained model.
4. **Hardware:** `mlp_par32` uses 32 multiply-accumulate units, one per hidden neuron. Layer 1 takes 64 cycles, one pixel per cycle. MACs 0–9 are then reused for layer 2 (32 cycles), and a comparator tree picks the digit with the highest score.
5. **PC app:** a Tkinter app lets you draw a digit, sends it to the board, and shows the hidden-layer values the FPGA sends back.

The repository also has a purely combinational version of the same network (`src/mlp_digits.vhd`), with every neuron built as separate hardware and no clock.

### The network

| Layer | Neurons | Inputs per neuron | Weights | Biases |
|---|---|---|---|---|
| Hidden (ReLU) | 32 | 64 pixels (4-bit) | 2,048 | 32 |
| Output | 10 | 32 hidden values (8-bit) | 320 | 10 |
| **Total** | **42** | | **2,368** | **42** |

### FPGA resources (XC6SLX16-2CSG324)

| Resource | Used | Available | |
|---|---|---|---|
| Slice LUTs | 7,840 | 9,112 | 86 % |
| Slice registers | 1,755 | 18,224 | 9 % |
| Block RAM / DSP48 | 0 | 32 / 32 | 0 % |

The board clock is 100 MHz. The network core runs on a clock enable at 12.5 MHz.

## Repository layout

```
src/             Combinational network and shared building blocks
                 (full adder, adder, multiplier, adder tree, ReLU, comparator, argmax)
fpga/src/        FPGA design: MAC units, weight ROMs, UART, frame receiver, 7-segment, top level
fpga/nexys3.ucf  Pin and timing constraints for the Nexys 3
fpga/ise/        ISE project script and the ready-to-use bitstream (nexys3_top.bit)
fpga/sim/        Testbenches and ModelSim scripts for the FPGA design
sim/             ModelSim script for the combinational design
python/          Training, quantization, VHDL export and result checking
app/             PC app: draw a digit and send it to the board
assets/          Demo GIF
```

## Getting started

### Requirements

- Digilent Nexys 3 board and a micro-USB cable (UART port)
- Python 3 with `torch`, `numpy`, `scikit-learn`, `pyserial` and Tkinter
- To rebuild: Xilinx ISE 14.7 and ModelSim (the Intel FPGA Starter Edition works)

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 1. Program the board

The bitstream is included, so you don't need ISE for this step. Use Digilent Adept:

```bash
djtgcfg prog -d Nexys3 -i 0 -f fpga/ise/nexys3_top.bit
```

Or use iMPACT from ISE.

### 2. Run the app

Connect the board's UART USB port, then:

```bash
python app/draw_digit.py --port /dev/ttyUSB0
```

Draw a digit in the window. The board shows the prediction on the 7-segment display.

| Board I/O | Meaning |
|---|---|
| 7-segment display | predicted digit |
| LD0–LD3 | predicted digit in binary |
| LD6 | receiving an image |
| LD7 | result valid |
| BTNS (center button) | reset |

## Rebuilding from scratch

### Retrain and regenerate the VHDL

```bash
cd python
python train_quantize.py       # train, quantize, save out/quant_params.npz (about 7 s on CPU)
python export_vhdl.py          # src/weights_pkg.vhd
python export_rom.py           # fpga/src/mlp_params.vhd, weights_rom.vhd, weights_rom32.vhd
python export_testbench.py     # src/mlp_digits_tb.vhd
python export_seq_testbench.py # fpga/sim/mlp_seq_tb.vhd, mlp_par32_tb.vhd
python export_top_testbench.py # fpga/sim/nexys3_top_tb.vhd
```

A fixed seed makes every run produce the same weights.

### Simulate

Run these from the repository root:

```bash
vsim -c -do "do sim/run_mlp.do; quit -f"                 # combinational design
python python/check_results.py                           # compare with the Python model

vsim -c -do "do fpga/sim/run_nexys3_top.do; quit -f"     # full FPGA design, including the UART
python python/check_top.py
```

### Build the bitstream

```bash
cd fpga/ise
xtclsh create_project.tcl
```

Then open `nexys3_digits.xise` in ISE and run **Generate Programming File**.
