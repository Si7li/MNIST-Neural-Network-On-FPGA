# Explanations

Notes on parts of the project that needed explaining.

---

## Demo

![Demo: the FPGA recognising handwritten digits](assets/demo.gif)

---

## 1. What is an adder tree?

An **adder tree** adds up many numbers by **adding them in pairs, then adding those results in pairs, and so on**, until one sum is left. It works like a sports tournament bracket.

### Why the neuron needs one

Each neuron in layer 1 has to add 64 products: `p0 + p1 + p2 + … + p63`.
An adder (`adder_n`) only adds **two** numbers at a time, so several adders have to be connected together. There are two ways to do it.

### Option 1: a chain

Each adder adds one more number to the running total:

```
p0 ─┐
p1 ─┴─[+]─┐
p2 ───────┴─[+]─┐
p3 ─────────────┴─[+]─┐
p4 ───────────────────┴─[+]─ ... ─[+]─► sum
                                 (63 adders in a row)
```

- **Adders:** 63
- **Depth:** 63 adders deep. The signal must ripple through all 63, one after another, before the answer is ready.

### Option 2: a tree

Add in pairs at every level:

```
p0 ─┐
p1 ─┴[+]─┐
p2 ─┐    ├[+]─┐
p3 ─┴[+]─┘    │
p4 ─┐         ├[+]─► sum
p5 ─┴[+]─┐    │
p6 ─┐    ├[+]─┘
p7 ─┴[+]─┘
level: 1   2    3
```

That's 8 inputs. For 64 inputs, the levels look like this:

| Level | Additions | Results left |
|---|---|---|
| 1 | 32 | 32 |
| 2 | 16 | 16 |
| 3 | 8 | 8 |
| 4 | 4 | 4 |
| 5 | 2 | 2 |
| 6 | 1 | **1 = the sum** |

- **Adders:** 32 + 16 + 8 + 4 + 2 + 1 = **63**, the same as the chain.
- **Depth:** only **6** adders deep.

### Why use a tree?

It uses **the same number of adders but is about 10× shallower** (6 levels instead of 63).

The design has no clock, but signals still take real time to pass through gates. That's the **propagation delay**. The answer is only ready once the signal has gone through the deepest path. With a chain, that's 63 adders in a row; with a tree, it's 6. The tree is much faster, and in simulation it also settles in fewer delta cycles.

### Details for this design

- **Odd counts:** if a level has an odd number of values, the extra one passes straight through to the next level. That's what `argmax10` does with digit 9, which skips levels 2 and 3.
- **Width:** each addition can make the result one bit bigger. The simplest approach is to sign-extend every product to the full accumulator width at the start (15 bits for layer 1, 19 bits for layer 2) and use that width throughout. The Python analysis showed the final sum can never exceed those widths.
- **Bias:** it can be added with one extra adder at the end. Or it can go into the tree as a 65th input, using the same 6 levels plus one pass-through.

The chain approach is already used in this project: `mult_su` sums its 4 or 8 partial products with a chain. That's fine there because the chain is short. With 64 inputs, the tree makes a big difference.

---

## 2. Why do we need a comparator?

You need it to **pick the answer**. The network's last layer doesn't output a digit. It outputs **10 scores**, one for each digit 0–9, and the predicted digit is the one with the **largest score**.

Example (made-up numbers, to show the idea):

| Digit | 0 | 1 | 2 | 3 | 4 | 5 | 6 | **7** | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| Score | −8120 | 1544 | −310 | 2210 | −4980 | 760 | −6030 | **9415** | 1102 | 3377 |

The answer is **7**. Finding "which one is biggest" is called **argmax**, and the only way hardware can find the biggest is to **compare numbers two at a time**. That's what a comparator does: it answers "is a > b?" with a single bit.

### How argmax uses it

`argmax10` is a tournament, the same shape as the adder tree:

```
0 ─┐
1 ─┴[cmp]─┐
2 ─┐      ├[cmp]─┐
3 ─┴[cmp]─┘      ├[cmp]─┐
4 ─┐             │      │
5 ─┴[cmp]─┐      │      ├[cmp]─► winning digit
6 ─┐      ├[cmp]─┘      │
7 ─┴[cmp]─┘             │
8 ─┐                    │
9 ─┴[cmp]───────────────┘
```

Each match (`max2`) uses one comparator to decide the winner, then passes on the winner's **score** (for the next comparison) and its **index** (the digit number). With 10 players, that takes **9 comparators**.

On a tie, the lower digit wins. The Python model uses the same rule, so the hardware and Python always agree.

### Why the XOR network didn't need one

XOR has **one** output neuron, and you only had to ask "is the sum > 0?". That's a comparison against zero, which you can answer just by looking at the **sign bit**, with no subtraction. Here, the **10 outputs compete against each other**, so you have to compare two arbitrary numbers. That needs a real comparator.

### How the comparator works

To check a > b, it computes **b − a** and looks at the sign bit: if b − a is negative, then a > b.

The subtraction reuses `adder_n`:

  b − a = b + (NOT a) + 1

That's why the adder needed a **carry-in** port: the "+1" goes in through the carry-in.

The comparator works with **one extra bit** so the subtraction can't overflow. Without it, comparing a very large positive number with a very large negative one could wrap around and give the wrong sign.

### Why not softmax?

In Python, networks often finish with **softmax**, which turns the scores into probabilities. Softmax never changes **which score is largest**, so the biggest score always gets the biggest probability. For simply picking the digit, softmax is unnecessary. Skipping it saves a lot of hardware, because it needs exponentials and division.

---

## 3. The neural network (PyTorch)

The network is defined in `python/model.py` as a PyTorch class called `DigitsMLP`. MLP stands for **multilayer perceptron**: layers of neurons where every neuron is connected to every input of its layer.

### Structure

```
                 fc1                         fc2
 64 pixels ──► (hidden layer) ──► ReLU ──► (output layer) ──► 10 scores
  0..15        32 neurons                  10 neurons         one per digit 0-9
```

| Layer | PyTorch | Weights | Biases | Parameters |
|---|---|---|---|---|
| Hidden | `nn.Linear(64, 32)` | 64 × 32 = 2,048 | 32 | 2,080 |
| Activation | `nn.ReLU()` | – | – | 0 |
| Output | `nn.Linear(32, 10)` | 32 × 10 = 320 | 10 | 330 |
| **Total** | | | | **2,410** |

- **`nn.Linear(64, 32)`** is a layer of 32 neurons. Each one computes `Σ input × weight + bias` over the 64 inputs, exactly like the XOR neuron but with 64 inputs instead of 2.
- **`nn.ReLU()`** is the activation: negative values become 0, positive values pass through unchanged. It plays the same role as the step function in the XOR network.
- The output layer has **no activation**. Its 10 numbers are scores, and the predicted digit is the one with the largest score (see section 2).

### The code

```python
class DigitsMLP(nn.Module):
    def __init__(self, n_in=64, n_hidden=32, n_out=10):
        super().__init__()
        self.fc1 = nn.Linear(n_in, n_hidden)   # hidden layer
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(n_hidden, n_out)  # output layer

    def forward(self, x):
        h = self.relu(self.fc1(x))  # hidden activations, shape (batch, 32)
        return self.fc2(h)          # scores,             shape (batch, 10)
```

- **`__init__`** creates the layers. PyTorch fills their weights with small random numbers.
- **`forward`** says how data flows through the layers. PyTorch calls it whenever you write `model(x)`.
- **`batch`** means several images at once: `x` has shape (batch, 64), one row per image.

`numpy_params()` takes the trained weights out of PyTorch for quantization. PyTorch stores each layer's weights as (outputs, inputs), so it **transposes** them to (inputs, outputs). Then `W1[i][j]` is the weight from pixel `i` to hidden neuron `j`, the same layout the hardware uses.

---

## 4. What happens in the training phase?

### File structure

| File | Job |
|---|---|
| `python/data.py` | Load the digits dataset, clamp pixels to 4 bits, split into training and test sets |
| `python/model.py` | The network (`DigitsMLP`), see section 3 |
| `python/train.py` | The training loop (`train`) and prediction (`predict`) |
| `python/quantize.py` | Converting weights to 8-bit integers, and the bit-exact hardware model |
| `python/train_quantize.py` | **The main script**: runs every step in order, prints a report, saves the results |

Run everything with:

```
.venv/bin/python python/train_quantize.py
```

It takes about 7 seconds on the CPU. A fixed seed (`SEED = 0`) makes every run produce exactly the same weights.

### Part 1: Training (floating point)

#### 1. Load the data (`data.py`, `load_data`)

- `load_digits()` from scikit-learn gives **1,797 images** of handwritten digits. Each is 8×8 = 64 pixels, with values from 0 (white) to 16 (black), plus the correct label (0–9). scikit-learn is only used for the dataset; the network itself is PyTorch.
- Each pixel is **clamped to 15**, so it fits in 4 bits. This changes only the one value 16.
- The images are split **80% for training** (1,437 images) and **20% for testing** (360 images). The network **never sees the test images during training**; they only measure how well it works on new images.
- The split is **stratified**: each digit appears in the same proportion in both sets.

`to_tensor()` divides the pixels by 16 (range 0 to 0.94) and converts them to a PyTorch tensor. Training works better with small inputs. 16 is used rather than 15 because it's a power of two (2⁴), which the hardware can absorb into the biases (step 5).

#### 2. Create the network

`model = DigitsMLP()` creates the network with **random** starting weights (section 3).

#### 3. Train it (`train.py`, `train`)

Training repeats these 5 steps for every **batch** of 64 images:

```python
optimizer.zero_grad()           # 1. clear old gradients
scores = model(xb)              # 2. forward pass
loss = loss_fn(scores, yb)      # 3. measure the error
loss.backward()                 # 4. backpropagation
optimizer.step()                # 5. nudge every weight
```

1. **Clear old gradients.** PyTorch adds gradients together by default, so they're reset before each batch.
2. **Forward pass.** Run the 64 images through the network to get 10 scores per image.
3. **Measure the error.** `CrossEntropyLoss` turns the scores into probabilities (softmax) and measures how far they are from the correct answer. The result is one number, the **loss**: lower is better. Softmax is only used here, during training. The hardware doesn't need it (see section 2).
4. **Backpropagation.** `loss.backward()` works out, for each of the 2,410 weights and biases, which direction to change it to reduce the loss. These are the **gradients**.
5. **Update the weights.** The **Adam** optimizer moves every weight a small step in that direction.

One pass over all 1,437 training images (23 batches) is an **epoch**. Training runs for 200 epochs.

The settings are in `TrainConfig`:

| Setting | Value | Meaning |
|---|---|---|
| `epochs` | 200 | passes over the whole training set |
| `batch_size` | 64 | images per weight update |
| `lr` | 0.001 | learning rate: how big each weight update is |
| `weight_decay` | 0.0001 | a small pull towards 0, which keeps weights small. That reduces overfitting and helps the weights fit in 8 bits. |
| `seed` | 0 | makes the shuffling repeatable |

The training prints its progress. The loss goes down and the accuracy goes up:

| Epoch | Loss | Training accuracy |
|---|---|---|
| 1 | 2.28 | 23% (close to guessing) |
| 25 | 0.23 | 95% |
| 100 | 0.052 | 99.4% |
| 200 | 0.018 | 99.9% |

**Result: 97.50% accuracy on the 360 test images** (`predict` picks the largest score for each image).

### Part 2: Quantization (decimals → 8-bit integers)

The hardware can't store 0.83716..., so every number has to become an integer. This is all in `quantize.py`.

#### 4. Convert the weights to Q2.6 (`frac_bits_for`, `quantize`)

- Multiply each weight by **2⁶ = 64** and round. For example, 0.837 × 64 = 53.6, which rounds to **54**, stored as `00110110`.
- **Why 6 fractional bits?** The largest weights are 1.117 (layer 1) and 1.796 (layer 2). With 7 fractional bits (Q1.7), 1.796 × 128 = 230, which doesn't fit in 8 bits (maximum 127). With 6 bits, 1.796 × 64 = 115, which fits. So **Q2.6** is the most precise format that holds every weight without clipping.
- For comparison, the script also tests forced Q1.7: 22 weights get clipped, but the test accuracy stays at 97.50%. So Q1.7 would also work for this network. Q2.6 is used because it doesn't change any weight.

#### 5. Scale the biases to match (`quantize`)

In hardware, a bias is added to the sum of products, so it must be in the **same units** as that sum.

- **Layer 1:** the weights are ×64, and the hardware uses integer pixels (0–15) instead of pixel/16, which is another ×16. So **b1 is multiplied by 64 × 16 = 2¹⁰**.
- **Layer 2:** the same idea, also accounting for the shift in the next step. That works out to **b2 × 2¹¹**.

#### 6. Choose the shift between layers (`choose_shift`)

The layer-1 sums are large numbers (up to 15 bits), but layer 2 expects 8-bit inputs (0–255). So each hidden value is **shifted right**, which divides it by a power of 2. The script tries every shift from 0 to 20 on the **training** images:

| Shift | Training accuracy | Hidden values clipped at 255 |
|---|---|---|
| 3 | 98.75% | 41% |
| 4 | 99.86% | 2.6% |
| **5** | **99.93%** | **0%** ← chosen |
| 9 | 99.79% | 0% |
| 12 | 29% | 0%, but the values are too small to tell digits apart |

It picks **5**: the best accuracy, with no clipping. Only training data is used to make this choice, so the test result stays an honest measure.

#### 7. Check the bit-exact model (`hw_forward`)

`hw_forward()` computes the network using **integers only, exactly as the hardware will**: multiply, add, ReLU, shift right by 5, clip at 255, multiply, add, and pick the largest (with the lowest index winning a tie).

**Result: 97.50%, and the same prediction as the float network on all 360 test images.** Quantizing to 8 bits cost nothing.

This model is the **reference**. Later, the VHDL must produce exactly the same output on every image.

#### 8. Work out the hardware widths (`hardware_widths`)

For each neuron, the script calculates the **largest and smallest sum that any possible input** could produce (not just the dataset's images), and from that the number of bits needed:

- Layer-1 accumulator: **15 bits**
- Layer-2 accumulator: **19 bits**

This guarantees the adders can never overflow.

#### 9. Save the results

| File | Contents |
|---|---|
| `python/out/model.pt` | the trained PyTorch network (float weights) |
| `python/out/quant_params.npz` | the integer weights and biases, the shift, the 360 test images, and the expected outputs for each of them |
| `python/out/summary.json` | all the numbers above |

### In one sentence

We trained the network in PyTorch, converted every weight to an 8-bit integer without losing any accuracy, worked out the exact bit widths the hardware needs, and saved a reference model the VHDL will be checked against.

---

## 5. Important code to understand the training

A reading guide, ordered from most to least important. If you only read three parts, read **①, ② and ③**.

| # | Where | What | Importance |
|---|---|---|---|
| ① | `model.py`: `DigitsMLP` | the network's structure | ⭐⭐⭐ |
| ② | `train.py`: `train` | the training loop | ⭐⭐⭐ |
| ③ | `quantize.py`: `hw_forward` | the network as the hardware computes it | ⭐⭐⭐ |
| ④ | `quantize.py`: `quantize` | decimals → 8-bit integers | ⭐⭐ |
| ⑤ | `quantize.py`: `frac_bits_for` | why Q2.6 | ⭐⭐ |
| ⑥ | `quantize.py`: `choose_shift` | why shift by 5 | ⭐⭐ |
| ⑦ | `quantize.py`: `hardware_widths` | why 15 and 19 bits | ⭐⭐ |
| – | `data.py`, `train_quantize.py` | loading data, running the steps in order, printing, saving | ⭐ |

### ① `DigitsMLP`: the network

Explained in section 3. The key line is `forward`: `fc1 → ReLU → fc2`.

### ② `train`: the training loop

```python
loader = DataLoader(dataset, batch_size=cfg.batch_size, shuffle=True, ...)
loss_fn = nn.CrossEntropyLoss()
optimizer = torch.optim.Adam(model.parameters(), lr=cfg.lr,
                             weight_decay=cfg.weight_decay)

for epoch in range(1, cfg.epochs + 1):
    for xb, yb in loader:
        optimizer.zero_grad()
        scores = model(xb)
        loss = loss_fn(scores, yb)
        loss.backward()
        optimizer.step()
```

- **`DataLoader`** splits the training images into batches of 64 and shuffles them every epoch, so the network doesn't see them in the same order each time.
- **`loss_fn`** measures the error, and **`optimizer`** updates the weights.
- **The two loops:** the outer loop is the 200 epochs; the inner loop is the 23 batches in each epoch. The 5 steps inside are explained in section 4, step 3.

### ③ `hw_forward`: the network as the hardware computes it

This is the most important function to understand, because **it's exactly what the VHDL will do**:

```python
def hw_forward(x, w1q, b1q, w2q, b2q, s1):
    acc1 = x @ w1q + b1q
    h = np.minimum(np.maximum(acc1, 0) >> s1, HIDDEN_MAX)
    acc2 = h @ w2q + b2q
    pred = np.argmax(acc2, axis=1)
    return acc1, h, acc2, pred
```

| Python | Meaning | VHDL block |
|---|---|---|
| `x @ w1q` | `@` is matrix multiplication: for each hidden neuron, compute Σ pixel × weight over all 64 pixels | 64 × `mult_su` + adder tree |
| `+ b1q` | add the bias | `adder_n` |
| `np.maximum(acc1, 0)` | ReLU: negative values become 0 | `relu_shift_sat` |
| `>> s1` | shift right by 5 bits (divide by 32) | `relu_shift_sat` (wiring) |
| `np.minimum(…, HIDDEN_MAX)` | saturate: clip at 255 | `relu_shift_sat` |
| `h @ w2q + b2q` | the same steps for layer 2 | 32 × `mult_su` + adder tree + `adder_n` |
| `np.argmax(…, axis=1)` | the index of the largest of the 10 scores; ties go to the first | `argmax10` |

Compare it with `DigitsMLP.forward` in ①: it's the same network (fc1 → ReLU → fc2 → pick the largest), but with integers, plus the shift and clipping that 8-bit hardware needs.

### ④ `quantize`: decimals → integers

```python
w1q = np.clip(np.round(W1 * 2 ** n1), -128, 127)
b1q = np.round(b1 * 2 ** (n1 + INPUT_SHIFT))
w2q = np.clip(np.round(W2 * 2 ** n2), -128, 127)
b2q = np.round(b2 * 2.0 ** (n2 + n1 + INPUT_SHIFT - s1))
```

- **Weights:** multiply by 2⁶ = 64, round, and keep within the 8-bit range. For example, 0.837 becomes 54.
- **Biases:** a bias is added to a sum of products, so it's scaled by the same factor as that sum:
  - `n1` (6): from the weight scaling
  - `INPUT_SHIFT` (4): because the hardware uses pixels 0–15 instead of pixel/16 (16 = 2⁴)
  - `− s1`: in layer 2, the shift between layers divides the hidden values by 2⁵

So b1 is multiplied by 2¹⁰ and b2 by 2¹¹. The biases aren't limited to 8 bits; they use 10 bits.

### ⑤ `frac_bits_for`: choosing the Q format

```python
n = 0
while np.max(np.abs(np.round(w * 2 ** (n + 1)))) <= 127:
    n += 1
```

- This keeps adding fractional bits **while the largest weight still fits in 127**.
- For layer 2, the largest weight is 1.796: ×64 gives 115, which fits; ×128 gives 230, which doesn't. So n = 6, which is **Q2.6**.

### ⑥ `choose_shift`: choosing the shift between layers

```python
for s1 in range(0, 21):
    q = quantize(W1, b1, W2, b2, n1, n2, s1)
    acc1, _, _, pred = hw_forward(X, *q, s1)
    sat = np.mean(np.maximum(acc1, 0) >> s1 > HIDDEN_MAX)
    rows.append((s1, np.mean(pred == y), sat))
best = max(rows, key=lambda r: (r[1], -r[2], -r[0]))
```

- It **tries every shift from 0 to 20** and runs the integer network on the **training** images each time.
- For each shift, it records the accuracy and the fraction of hidden values clipped at 255.
- The `key=` line picks the best: **highest accuracy first, then least clipping, then the smallest shift**. The result is 5.

### ⑦ `hardware_widths`: bit widths

```python
acc1_hi = (np.maximum(w1q, 0).sum(0) * PIXEL_MAX + b1q).max()
acc1_lo = (np.minimum(w1q, 0).sum(0) * PIXEL_MAX + b1q).min()
```

- **Largest possible sum:** every pixel at 15 where the weight is positive and 0 where it's negative. So it's (sum of the positive weights) × 15 + bias.
- **Smallest possible sum:** the reverse, (sum of the negative weights) × 15 + bias.
- `signed_bits(lo, hi)` then counts how many bits that range needs: **15**. Layer 2 is calculated the same way, with 255 as the largest input, giving **19**.

This is why the adders can never overflow, **for any input**, not just the dataset's images.

**Tip:** to see what's happening, add a temporary `print()` in `train_quantize.py`. For example, `print(W1[:3, :3])` after `model.numpy_params()` and `print(w1q[:3, :3])` after `quantize(...)`. You'll see the same weights before and after quantization.

---

## 6. Why does each neuron have multiple weights?

Each neuron has **one weight per input**. A weight says how much one particular input matters to that neuron, and in which direction.

### You've already seen this in the XOR network

Each XOR neuron had **2 inputs, so 2 weights** (plus 1 bias):

```vhdl
hidden0 : generic map (W0 => 2, W1 => 2, B => -1)   -- W0 for input a, W1 for input b
```

```
a ──(W0)──┐
          ├──► Σ + B ──► output
b ──(W1)──┘
```

The digits network works the same way, with more inputs:

| Neuron | Number of inputs | Number of weights | Bias |
|---|---|---|---|
| XOR neuron | 2 (a, b) | 2 | 1 |
| Hidden neuron (layer 1) | 64 (every pixel) | **64** | 1 |
| Output neuron (layer 2) | 32 (every hidden neuron) | **32** | 1 |

Each neuron is **connected to every input** of its layer, and every connection has its own weight. This is called a **fully connected** layer, which is what `nn.Linear` means in PyTorch.

### Why each input needs its own weight

A neuron computes:

  sum = pixel₀ × w₀ + pixel₁ × w₁ + … + pixel₆₃ × w₆₃ + bias

Each weight decides what its pixel contributes:

| Weight | Meaning |
|---|---|
| large positive | "if this pixel is dark, push me **up**" |
| large negative | "if this pixel is dark, push me **down**" |
| close to 0 | "I don't care about this pixel" |

**Suppose instead that a neuron had only one weight for all its inputs.** Every pixel would count the same, so the neuron could only measure **how much ink** is in the image, not **where** it is. A "1" and a "7" can have the same amount of ink. You can only tell them apart by **which** pixels are dark. Giving each pixel its own weight is what lets a neuron react to shapes.

### A useful way to picture it

A hidden neuron's 64 weights form an **8×8 picture of their own**, laid out the same way as the image. That's why `weights_pkg.vhd` shows them as 8 lines of 8. Roughly:

```
weights of one hidden neuron        an input image of a "0"
 0  -8 -25  27  25  -5   0  -7       .  .  █  █  █  .  .  .
 0  -8  -3  17  -8   7  22  -2       .  █  .  .  .  █  .  .
 ...                                 ...
```

The neuron multiplies each pixel by the weight in the same position and adds everything up. If the dark pixels land on **positive** weights, the sum is large and the neuron "fires". If they land on **negative** weights, the sum is small and ReLU outputs 0. So each hidden neuron is like a **stencil** that looks for one pattern. Different neurons learn different stencils, and so the 32 neurons see 32 different features.

The output neurons do the same thing one level up. Each digit's neuron has **32 weights, one per hidden feature**: "features 3 and 12 are evidence for a 0, feature 1 is evidence against it".

### Counting them

```
Layer 1:  32 neurons × 64 weights = 2,048 weights  +  32 biases
Layer 2:  10 neurons × 32 weights =   320 weights  +  10 biases
                                    ───────────────────────────
                                    2,368 weights  +  42 biases  = 2,410 parameters
```

Each neuron has **many weights** (one per input) but **only one bias**. The bias doesn't belong to any input. It shifts the neuron's threshold, the same job `B` did in the XOR network.

In hardware, every weight means **one multiplier**. That's why each hidden neuron is built from 64 multipliers (and each output neuron from 32) feeding an adder tree.

---

## 7. How do we do multiple multiplications?

**All at the same time, each with its own multiplier.** The design is purely combinational: there's no clock, so you can't reuse one multiplier for several products one after another. Instead, **every weight gets its own physical multiplier**, and all of them work at once.

### In one neuron

A hidden neuron has 64 inputs, so it contains **64 copies of `mult_su`**, side by side:

```
pixel 0  ──► [ mult_su × W(0)  ] ──► product 0  ─┐
pixel 1  ──► [ mult_su × W(1)  ] ──► product 1  ─┤
pixel 2  ──► [ mult_su × W(2)  ] ──► product 2  ─┤
  ...              ...                 ...       ├──► adder tree ──► sum
pixel 63 ──► [ mult_su × W(63) ] ──► product 63 ─┤
                                       bias B ───┘
```

All 64 multipliers calculate **simultaneously**. As soon as the pixels arrive, all 64 products appear together, and the adder tree combines them.

### How you write 64 multipliers without typing 64 blocks

You use a **`for … generate`** loop, the same tool that places the 8 full adders inside `adder_n`. The loop runs **when the design is built**, not while it's working, and it **places one copy** of the block for each value of `i`:

This is the real code from `src/neuron_n.vhd`:

```vhdl
mults : for i in 0 to N-1 generate
  m : entity work.mult_su
    generic map (WA => WEIGHT_W, WB => IN_W)
    port map (a => W(W'low + i),                     -- this input's weight (a constant from weights_pkg)
              b => x((i+1)*IN_W-1 downto i*IN_W),    -- this input's pixel
              p => prod(i));                          -- this input's product
  ...
end generate;
```

- **`W(W'low + i)`** is weight number `i`. `W'low` is the first index of the weight list (normally 0); writing it this way means the code works however the list is numbered.
- **`x((i+1)*IN_W-1 downto i*IN_W)`** picks input number `i` out of one long bit vector. All 64 pixels arrive side by side in `x`, 4 bits each: pixel 0 is bits 3–0, pixel 1 is bits 7–4, and so on.

With `N = 64`, this produces 64 separate multipliers named `mults(0).m`, `mults(1).m`, … `mults(63).m`. In ModelSim, you'll see each one in the design hierarchy.

### In the whole network

The same idea applies at every level, with generate loops inside generate loops:

| Level | Copies | Multipliers |
|---|---|---|
| One hidden neuron | 64 inputs | 64 |
| Layer 1 | 32 neurons × 64 | **2,048** |
| One output neuron | 32 inputs | 32 |
| Layer 2 | 10 neurons × 32 | **320** |
| **Whole network** | | **2,368 multipliers, all working at once** |

That's one multiplier per weight, which matches the 2,368 weights in `weights_pkg.vhd` exactly.

### Inside each multiplier

Each `mult_su` does its own small multiplication using the **shift-and-add** method. For a 4-bit pixel:

```
weight × pixel = (weight × bit0) + (weight × bit1, shifted 1) + (weight × bit2, shifted 2) + (weight × bit3, shifted 3)
```

That's 4 partial products (AND gates), added together with 3 adders. So it's **multiplications built from additions, built from full adders, built from gates**, all running at the same time.

### The alternative (and why we're not using it)

A **sequential** design would have just 1 multiplier (or a few) and a **clock**. On each clock tick, it would multiply one pixel by one weight and add the result to a running total, so one neuron would take 64 ticks.

| | Combinational (our design) | Sequential |
|---|---|---|
| Multipliers | 2,368 | 1 to a few |
| Clock / process | none | needed |
| Time for an answer | one pass through the gates | thousands of clock ticks |
| Size | very large | small |

We chose combinational because the project rules say **no clock and no process**. The cost is size, which is why the simulation is big. If the design were synthesized, Quartus would shrink it considerably, because each weight is a constant: multiplying by a constant needs fewer gates, and a weight of 0 removes the multiplier entirely. (352 of the layer-1 weights are 0.)

---

## 8. What does `max2.vhd` do?

`max2` is **one match in a tournament**. It takes two competitors, each a **score** and a **digit number**, decides which score is bigger, and passes the **winner** on. `argmax10` connects 9 of them in a bracket to find the digit with the highest score.

### Its inputs and outputs

```
           ┌──────────────────────────┐
a_val ────►│                          │
a_idx ────►│                          ├───► val   (winner's score)
           │          max2            │
b_val ────►│                          ├───► idx   (winner's digit number)
b_idx ────►│                          │
           └──────────────────────────┘
```

| Port | Width | Meaning |
|---|---|---|
| `a_val`, `b_val` | `W` bits (19) | the two scores being compared |
| `a_idx`, `b_idx` | 4 bits | which digit each score belongs to (0–9) |
| `val` | `W` bits | the winner's score |
| `idx` | 4 bits | the winner's digit number |

### How it works

It's just a **comparator plus two multiplexers**:

```
                 ┌──────────────┐
b_val ──────────►│ comparator_gt│
a_val ──────────►│  b_val >     ├──► b_wins (1 bit)
                 │  a_val ?     │         │
                 └──────────────┘         │ selects
                                          ▼
a_val ─┐                            a_idx ─┐
       ├─[mux]──► val                      ├─[mux]──► idx
b_val ─┘                            b_idx ─┘
```

**Step 1: compare**

```vhdl
cmp : entity work.comparator_gt
  port map (a => b_val, b => a_val, gt => b_wins);
```

This asks: **"is b's score strictly greater than a's?"** The answer is one bit, `b_wins`. Note that the inputs are passed **swapped** (`a => b_val, b => a_val`) because the comparator computes "a > b", and here we want "b > a".

**Step 2: choose**

```vhdl
val <= b_val when b_wins = '1' else a_val;
idx <= b_idx when b_wins = '1' else a_idx;
```

These are two **multiplexers**, which act as switches. If b won, pass b's score and number; otherwise pass a's.

### An example

| | Score | Digit |
|---|---|---|
| a | 1544 | 1 |
| b | 2210 | 3 |

1. The comparator asks "is 2210 > 1544?" Yes, so `b_wins = '1'`.
2. The multiplexers pass b on: `val = 2210`, `idx = 3`.

### Why it passes on two things

- **The score (`val`)** is needed for the **next** match. The winner has to compete again in the next round, so its score must travel with it.
- **The digit number (`idx`)** is what you need at the **end**. The network's answer is not the highest score itself (say 9415), but **which digit** had it (say 7). If only the scores travelled through the bracket, you'd know how high the winning score was but not whose it was.

### Ties: why "strictly greater"

If both scores are equal, "b > a" is false, so **a wins**. In `argmax10`, `a` is always the side with the **lower** digit numbers, so **on a tie, the lower digit wins**. The Python model uses the same rule (`np.argmax` returns the first maximum). That matters, because the hardware has to agree with Python on **every** image, including ties. There are no ties in the current test set, but the rule guarantees agreement if one ever happens.

### Where it's used: `argmax10`

`argmax10` places **9 `max2` blocks** in 4 rounds:

```
round 1           round 2         round 3        round 4
0 ─┐
1 ─┴[max2]─┐
2 ─┐       ├[max2]─┐
3 ─┴[max2]─┘       ├[max2]─┐
4 ─┐               │       │
5 ─┴[max2]─┐       │       ├[max2]──► idx = predicted digit
6 ─┐       ├[max2]─┘       │
7 ─┴[max2]─┘               │
8 ─┐                       │
9 ─┴[max2]─────────────────┘   (8/9's winner gets a bye until the final)
```

10 competitors need **9 matches**, because each match eliminates exactly one. Only the final `idx` is used, and that's the network's answer.

### Where it sits in the whole design

```
full_adder → adder_n → comparator_gt → max2 → argmax10 → (the network's output)
```

---

## 9. How does the design work without a clock?

The network has **no memory**. It never needs to remember anything between steps, so it never needs a clock to say *when* to remember.

### What a clock is actually for

A clock is a signal that ticks: 0, 1, 0, 1, … It controls **flip-flops (registers)**, the circuit elements that **store** a value. On each tick, every flip-flop captures its input and holds it until the next tick.

You need that when a circuit has to:

- **do things in order**: step 1, then step 2, then step 3
- **reuse hardware**: the same multiplier for pixel 0, then pixel 1, then pixel 2…
- **remember** a result: a running total, a counter, a state

In VHDL, a clocked design looks like this:

```vhdl
process (clk)
begin
  if rising_edge(clk) then
    total <= total + product;   -- remember the new total until the next tick
  end if;
end process;
```

This design has **none of this**: no `clk` signal, no `rising_edge`, no process, no flip-flops.

### What we do instead: combinational logic

A **combinational** circuit is just gates wired together. Its output depends **only on its current inputs**, like a light switch circuit: flip the switch, and the light changes, with nothing stored.

The network is one huge combinational circuit:

```
pixels ──► gates ──► gates ──► gates ──► ... ──► gates ──► digit
           (multipliers, adder trees, ReLU, multipliers, adder trees, argmax)
```

When the pixels change, the change **flows through the gates** like water through pipes. After a short time, the right digit appears at the output. Nothing has to be stored along the way, because:

| A clocked design needs… | This design does instead… |
|---|---|
| to reuse 1 multiplier 2,368 times, one per tick | **2,368 separate multipliers**, all working at once |
| a register to hold the running total | an **adder tree** that adds everything in one pass |
| a register to hold the hidden values | the hidden values are just **wires** from layer 1 to layer 2 |
| a state machine to know "which step am I on" | there are no steps; **everything happens at once** |

That's the trade-off from section 7: **we replaced time with space.** A clocked design does a little work per tick over many ticks. This one builds enough hardware to do all the work at once.

### You can see this in every file

Every line in the design is one of two things.

**1. Concurrent assignments**, which describe gates:

```vhdl
s    <= a xor b xor cin;                       -- full_adder.vhd
cout <= (a and b) or (cin and (a xor b));
```

These lines are **always active**. They aren't instructions that run once; they describe wires and gates that permanently connect the inputs to the output.

**2. Instances inside `generate` loops**, which place copies of blocks:

```vhdl
mults : for i in 0 to N-1 generate
  m : entity work.mult_su ...
```

The loop **runs once, when the design is built**, placing 64 multipliers. It doesn't run while the circuit is working.

There's no `process`, so there's nothing that runs step by step and nothing that waits for a clock.

### Doesn't layer 2 need to wait for layer 1 to finish?

No. **Layer 2 doesn't wait for layer 1. It's always calculating, using whatever layer 1 is outputting at that moment.**

The outputs of layer 1 are **physically wired** to the inputs of layer 2. There's no switch between them, and nothing that says "go". So when a new image arrives:

```
time ───────────────────────────────────────────────────────────────────►

pixels   │ new image ─────────────────────────────────────────────────────
layer 1  │ ~~~~~~ changing, wrong values ~~~~~~│ correct, stable ─────────
layer 2  │ ~~~~~~~~~~~~~~~~ changing, wrong values ~~~~~~~~~│ correct ─────
digit    │ ~~~~~~~~~~~~~~~~~~~~~~~~~ changing ~~~~~~~~~~~~~~~~~~~│ correct ─
                                                                 ▲
                                               answer is ready from here
```

1. The new pixels start flowing into layer 1. While its adders are still working, **layer 1's outputs flicker through wrong, half-finished values**.
2. Layer 2 sees those wrong values and **calculates with them**, producing wrong scores. That's fine: nothing stores them, so they do no harm.
3. Every time layer 1's output changes, layer 2 automatically recalculates, because it's just gates.
4. Eventually layer 1 **settles** on its correct values and stops changing.
5. Shortly after, layer 2 settles too, because its inputs have stopped changing. Then argmax settles, and the digit is correct.

It works like a **spreadsheet**: when you change a cell, every cell that depends on it updates automatically, and every cell that depends on *those* updates after them. Nobody presses "now calculate the next column".

So the layers don't need to be told when to start. **The total time is simply the time for layer 1 to settle plus the time for layer 2 to settle (plus argmax).** All that matters is that **whoever reads the final `digit` waits long enough**.

**In simulation**, ModelSim handles this ordering automatically. Whenever a signal changes, it re-evaluates every gate that uses it, in a series of zero-time steps called **delta cycles**. This is the same thing that happened in the XOR network, where `y` changed 6 delta cycles after the input. In the digits network, there are many more delta cycles, but they all happen within the same instant of simulation time. That's why the testbench just applies an image and waits 10 ns: by then, everything has long settled.

**In a real chip**, gates have real delays, so the wait is real time: the **propagation delay** of the slowest path:

```
multiplier → 7-level adder tree → ReLU → multiplier → 6-level adder tree → 4 comparators
```

Each adder is a ripple-carry chain of full adders, so this is a long path. Until it finishes, the output may **flicker** through wrong values (glitches), like the brief `y = 1` glitch in the XOR network at 40 ns. Once everything settles, the output is correct and stays that way as long as the inputs don't change.

### When you *would* need a clock

| Situation | Why a clock is needed |
|---|---|
| Reusing one multiplier for many products | something has to say "now the next pixel", and store the running total |
| Starting a new image before the previous one has finished (**pipelining**) | registers between the layers keep the two images' values apart |
| Reading the answer automatically, in a real system | something has to say "the answer is ready now". In practice, a register at the output that samples `digit` once per clock tick, with a clock period longer than the propagation delay. |

None of these apply here. The testbench plays the role of "whoever reads the answer", and it simply waits 10 ns per image.

### The honest trade-offs

| Without a clock (this design) | With a clock |
|---|---|
| ✅ simple to reason about: no timing, no states | ❌ needs a controller (state machine) |
| ✅ one answer as soon as signals settle | ❌ thousands of ticks per image |
| ❌ **huge**: 2,368 multipliers, 1.7 million simulation statements | ✅ small: 1 to a few multipliers |
| ❌ long propagation delay through the whole chain | ✅ short paths between registers, so a fast clock |
| ❌ glitches while it settles | ✅ outputs only change on ticks |

For this project, **no clock** was a requirement, and it works: the network gives the right answers. Real chips usually use clocks for designs this size, because combinational logic gets very large and slow once you have thousands of operations.

---

## 10. Is each layer built separately, or is one layer reused?

**Each layer is built separately, and both layers exist at the same time.** Nothing is ever reused, reconfigured or swapped. Layer 1 and layer 2 are two different groups of hardware sitting side by side, permanently wired together.

### One design, many copies

There's only **one neuron file** (`neuron_n.vhd`), so it can look as if one neuron is reused. But a VHDL entity is a **blueprint**, not a piece of hardware. Every time you instantiate it, you build **a new, separate copy** from the blueprint, with its own weights and size:

```
neuron_n.vhd (the blueprint, written once)
      │
      ├──► layer1(0).n   : 64 inputs, weights W1(0),  bias B1(0)   ┐
      ├──► layer1(1).n   : 64 inputs, weights W1(1),  bias B1(1)   │ layer 1:
      │      ...                                                   │ 32 copies
      ├──► layer1(31).n  : 64 inputs, weights W1(31), bias B1(31)  ┘
      │
      ├──► layer2(0).n   : 32 inputs, weights W2(0),  bias B2(0)   ┐ layer 2:
      │      ...                                                   │ 10 copies
      └──► layer2(9).n   : 32 inputs, weights W2(9),  bias B2(9)   ┘
```

It's like **one house plan used to build 42 houses**. Each house is real, and they all stand at the same time. Some are bigger (64 inputs) and some smaller (32 inputs), because the plan has adjustable settings: the **generics**.

### Where this happens in `mlp_digits.vhd`

```vhdl
layer1 : for j in 0 to N_HIDDEN-1 generate          -- builds 32 neurons
  n : entity work.neuron_n
    generic map (N => N_IN, ..., W => W1(j), B => B1(j))
    port map (x => pixels, acc => acc1(j));
  ...
end generate;

layer2 : for k in 0 to N_OUT-1 generate              -- builds 10 MORE neurons
  n : entity work.neuron_n
    generic map (N => N_HIDDEN, ..., W => W2(k), B => B2(k))
    port map (x => h, acc => s(...));
end generate;
```

- The `layer1` loop builds 32 neurons and the `layer2` loop builds 10 **more**. That's 42 in total, all present at once.
- **The output becomes the input through a wire, not a change of structure.** Layer 1 writes its results onto the signal `h`, and layer 2's neurons are connected to `h` (`port map (x => h, ...)`). That one signal **is** the connection between the layers.

You can see this in ModelSim: load the design and open the **sim / Structure** tab. Under the network you'll find `layer1(0)` through `layer1(31)` and `layer2(0)` through `layer2(9)`, each with its own `n` neuron inside.

### Why the weights and structure can't change while it runs

**Generics are fixed when the design is built** (elaboration), before the simulation starts, just like when a chip is manufactured. After that:

- A neuron's **number of inputs can't change**: its 64 multipliers are physical hardware.
- Its **weights can't change**: they're constants built into the logic.

So "build one layer, use it, then change its weights and size" **isn't possible** in this design.

### Reusing one layer is a real technique, but it needs a clock

Reusing the same hardware for layer 1 and then layer 2 is called **time-multiplexing** (or layer reuse). It's how many real neural-network chips save space. It would need:

| Part | Why |
|---|---|
| **Memory (ROM)** for the weights | the weights must change between layers, so they can't be fixed constants |
| **Registers** to hold layer 1's outputs | layer 1's results must survive while the same hardware is busy computing layer 2 |
| **A clock and a controller** (state machine) | something has to say "now compute layer 1", "now save the results", "now load layer 2's weights" |

That's the **sequential** design this project decided against, because the rules say **no clock and no process**. In this design, there's nothing to "switch" between layers, so both layers simply exist side by side and the data flows from one to the other.

| | This design | Layer reuse |
|---|---|---|
| Layers | 2 separate groups of hardware | 1 group, reused |
| Neurons built | 42 | as few as 32 (the bigger layer) |
| Weights | constants, built in | loaded from memory per layer |
| Layer 1 → layer 2 | a wire (`h`) | registers + a controller |
| Clock | none | needed |

---

## 11. Which is better: this design, or reusing one layer?

It depends on what "better" means. **For this project, this design is the right one.** For a real chip at this size, **reusing hardware is usually better**. But reusing one layer for both layers saves surprisingly little; the real savings come from taking the idea further.

### For this project: this design

- The rules say **no clock and no process**. Layer reuse **needs** a clock, registers and a controller, so it isn't allowed.
- This design **works** and matches Python exactly.

### In general: it's a trade-off

There are really **three** options, not two:

| | **A. This design** (fully parallel, no clock) | **B. Reuse one layer** | **C. Reuse multipliers** (one multiply-accumulate unit per neuron) |
|---|---|---|---|
| How it works | 42 neurons, all at once | 32 neurons; compute layer 1, save the results, reload the weights, compute layer 2 | 32 neurons, each with **1 multiplier** that handles one input per clock tick |
| Multipliers | 2,368 | **2,048** (32 neurons × 64 inputs) | **32** |
| Clock needed | no | yes | yes |
| Weight storage | built into the logic | memory (ROM) | memory (ROM) |
| Time per image | one propagation delay | 2 passes + switching | about **96 clock ticks** (64 + 32) |
| Complexity | simple | medium: controller + registers | medium: controller + registers + accumulators |

#### Why reusing one layer saves only about 13%

In option B, the shared layer still has to be big enough for **layer 1**: 32 neurons with 64 inputs each, which is **2,048 multipliers**. All you save are layer 2's 320 multipliers. That's because layer 2 is much **smaller** than layer 1, so reusing layer 1's hardware for it doesn't save much.

The **big** saving comes from option C: reusing each neuron's **multiplier** across its inputs. Instead of 64 multipliers working at once, one multiplier works 64 times, adding each product to a running total. That cuts the design from 2,368 multipliers to **32**, about **74 times fewer**. Real neural-network chips do something like this, usually with many such units working in parallel.

### Which is "better" for what

| Goal | Best choice | Why |
|---|---|---|
| **Fewest gates / fits on a small FPGA** | C | about 74× fewer multipliers |
| **Answer as soon as possible (lowest latency)** | A, in principle | no clock ticks, only gate delays. But its long ripple-carry chains make that delay large in practice. |
| **Most images per second** | A **with registers added between stages** (pipelining) | every layer works on a different image at the same time |
| **Simplest design, no timing logic** | A | no controller, no registers, no states |
| **Bigger networks** | C | A grows with the number of weights; C grows much more slowly |
| **Fits this project's rules** | **A** | it's the only one without a clock |

### Bottom line

- **For this assignment:** this design. It follows the rules, and it works.
- **For a real product:** reusing multipliers (option C) would almost always win. A design with 2,368 multipliers is unusually large for an FPGA, which is why ModelSim warned about the size.
- **Reusing hardware is the right instinct.** Engineers do reuse hardware across layers. It just pays off most when the reuse also covers the inputs, not only the layers.

**Summary for the report:** *"We chose a fully combinational design because the project required no clock. It is simple and computes the answer in one pass, but it needs one multiplier per weight (2,368). A clocked design that reuses one multiplier per neuron would need only 32 multipliers, at the cost of about 96 clock cycles per image."*

---

## 12. What is a multiplier?

A multiplier is a **circuit that multiplies two binary numbers**. In hardware there's no "×" operation available, only gates. So a multiplier is built from things that already exist: **AND gates and adders**. It does long multiplication, the same method taught in school, but in binary.

### Long multiplication, in decimal first

```
      23
   ×  12
   ─────
      46    ← 23 × 2
     23     ← 23 × 1, shifted one place left
   ─────
     276    ← add them up
```

You multiply by **one digit at a time**, **shift** each result, then **add** everything.

### The same thing in binary is much simpler

In binary, each digit of the second number is **0 or 1**, so each row is either:

- **0** (multiplying by 0), or
- **the first number itself** (multiplying by 1).

There's no real multiplying left to do: "number × one bit" is just **AND gates**. If the bit is 1, the number passes through; if it's 0, you get all zeros.

**Example: 6 × 5**

```
          0110      (6)
        × 0101      (5)
        ──────
          0110      ← bit 0 of 5 is 1 → copy 6
         0000       ← bit 1 is 0 → zeros, shifted 1
        0110        ← bit 2 is 1 → copy 6, shifted 2
       0000         ← bit 3 is 0 → zeros, shifted 3
       ───────
       0011110      = 30 ✓
```

So a binary multiplier is:

1. **AND gates** make the rows (called **partial products**): one row per bit of the second number.
2. **Wiring** shifts each row left. Shifting is free; it's just which wire goes where.
3. **Adders** sum all the rows.

```
 a ──┬─[AND b0]────────────────────┐
     ├─[AND b1]── shift 1 ──┐      │
     ├─[AND b2]── shift 2 ──┼─[+]──┼─[+]──► product
     └─[AND b3]── shift 3 ──┘      │
                                   └──...
```

### This project's multiplier: `mult_su.vhd`

It multiplies a **signed** weight (it can be negative) by an **unsigned** pixel (0–15). That's what the "su" in the name stands for. It uses exactly the method above:

```vhdl
-- Partial product i: a_ext shifted left by i, kept only if b(i) = 1
pp(i)(j) <= a_ext(j-i) and b(i);       -- AND gates + shift (wiring)

-- Sum them
add : entity work.adder_n ...           -- adders
```

**The negative weight trick:** before making the rows, the weight is **sign-extended** (its sign bit is copied into the extra bits on the left). Then two's complement arithmetic gives the right answer automatically.

**Example: weight −3 × pixel 5**

```
weight −3, sign-extended to 12 bits:   111111111101
pixel 5 = 0101: rows for bits 0 and 2

    111111111101      ← bit 0 = 1 → copy the weight
  + 111111110100      ← bit 2 = 1 → copy, shifted 2
  ──────────────
  1 111111110001      ← the extra 13th bit is dropped
    111111110001      = −15 ✓
```

### How big it is

| Multiplier | Rows | AND gates | Full adders | Gates (roughly) |
|---|---|---|---|---|
| 8-bit weight × 4-bit pixel (layer 1) | 4 | 48 | 3 adders × 12 bits = 36 | **~230** |
| 8-bit weight × 8-bit hidden value (layer 2) | 8 | 128 | 7 adders × 16 bits = 112 | **~690** |

(A full adder is about 5 gates: 2 XOR, 2 AND and 1 OR, from `full_adder.vhd`.)

That's why **2,368 of them** make the combinational design so large, and why the FPGA version shares just **one**.

### Multiplying by a constant is cheaper

When the weight is **fixed**, as in the combinational design, the synthesis tool knows which bits are 1 and can remove the rest. For example, a weight of 27 = `00011011`:

```
pixel × 27 = pixel×16 + pixel×8 + pixel×2 + pixel×1
```

That needs **no AND gates**, only 3 adders of the shifted pixel. A weight of **0** needs **nothing at all**. That shrinking is lost when the weights come from memory instead of being constants.

### Related terms

| Term | Meaning |
|---|---|
| **Partial product** | one row of the long multiplication (a AND one bit of b) |
| **Array multiplier** | this design: rows added one after another (`architecture array_mult`) |
| **MAC (multiply-accumulate)** | a multiplier + an adder + a register: `total = total + a × b`, one product per clock tick. The FPGA version is built around one MAC. |
| **DSP block** | a ready-made fast multiplier inside the FPGA (the XC6LX16 has 32). This project **doesn't** use them, because the arithmetic must be built from our own gates. |

---

## 13. What about negative numbers and fractions?

Both are handled with the **same multiplier**. For signs, you prepare the numbers a little differently. For fractions, the circuit doesn't change at all; you only keep track of **where the binary point is**.

### Part 1: Signed numbers (negative values)

Negative numbers are stored in **two's complement**: the leftmost bit has a **negative** weight. In 4 bits:

```
bit weights:   −8   4   2   1
    1101   =   −8 + 4 + 0 + 1  =  −3
    0101   =    0 + 4 + 0 + 1  =   5
```

#### Case 1: signed × unsigned (what this network does)

**Sign-extend the signed number, then multiply normally.** This is what `mult_su` does (see the −3 × 5 = −15 example in section 12). Sign extension means copying the sign bit to the left:

```
−3 in 4 bits:            1101
−3 in 8 bits:        11111101     ← extra 1s copied from the sign bit, still −3
```

Then each row (a copy of the extended weight) is correctly negative, and adding the rows gives the correct negative result.

#### Case 2: signed × signed (both can be negative)

Now the **multiplier's** sign bit also has a negative weight, so its row must be **subtracted**, not added. There are two common ways to handle this.

**Method A: subtract the last row.**
Example: −3 × −2, where −2 = `1110` = −8 + 4 + 2:

```
row for bit 1 (+2):   −3 × 2  =  −6
row for bit 2 (+4):   −3 × 4  = −12
row for bit 3 (−8):  −(−3 × 8) = +24    ← sign bit: SUBTRACT this row
                               ─────
                                  6 ✓
```

In hardware, "subtract" means: invert the bits and add 1. That's the same trick `comparator_gt` uses with `cin = '1'`.

**Method B: sign-extend both numbers to double width, multiply as unsigned, keep the low bits.**

```
−3 → 11111101,  −2 → 11111110  (8 bits each)
253 × 254 = 64,262 → keep the low 8 bits → 00000110 = 6 ✓
```

This is simple, but it wastes gates (an 8×8 multiplier for a 4×4 job). Optimized designs such as **Baugh-Wooley** or **Booth** multipliers handle signs more efficiently.

**This network never needs signed × signed.** Only the **weights** are negative. **Pixels** (0–15) and **hidden values** (after ReLU, 0–255) are **never** negative. That's why `mult_su` only has to deal with the easy case: one row per bit of the unsigned input, no subtracted row.

#### A third method: sign-magnitude

Store a sign bit and a size separately. Multiply the sizes as unsigned numbers; the result's sign is **sign_a XOR sign_b** (negative × negative = positive). It's easy to understand, but adding sign-magnitude numbers is awkward, so hardware almost always uses two's complement.

### Part 2: Fractional numbers (fixed point)

**The hardware never sees fractions.** A fixed-point number is just an **integer with an agreed scale**. In Q2.6, the integer is divided by 2⁶ = 64:

```
Q2.6 bits:  00011011  =  27 (as an integer)  →  27 / 64  =  0.421875 (as a value)
```

#### The rule: fractional bits add up

When you multiply two fixed-point numbers, **multiply the integers normally** and **add the fractional bits**:

  **Q a.b × Q c.d = Q (a+c).(b+d)**

**Example: 0.75 × 0.5, both Q2.6**

```
0.75 → 0.75 × 64 = 48        0.5 → 0.5 × 64 = 32
integer multiply:  48 × 32 = 1,536
fractional bits:   6 + 6 = 12  →  1,536 / 2¹² = 1,536 / 4,096 = 0.375 ✓
```

To return to Q2.6, **shift right by 6** (drop the 6 extra fractional bits): 1,536 >> 6 = 24 → 24 / 64 = 0.375 ✓. Shifting is just wiring, so it's free.

#### In this network

| Step | Numbers | Fractional bits |
|---|---|---|
| pixel | integer 0–15 | 0 |
| weight | Q2.6 | 6 |
| **product = pixel × weight** | | **0 + 6 = 6** |
| sum of 64 products + bias | the bias was scaled to the same 6 bits (×2⁶, plus ×2⁴ for the /16 input scaling) | same scale |
| hidden value | **shift right by 5**, the free rescaling step | |
| weight × hidden | Q2.6 × hidden | adds 6 more |

A real example from the weights: weight `00011011` (27, which means 0.42) × pixel 13:

```
integer: 27 × 13 = 351      value: 351 / 64 = 5.48   (= 0.421875 × 13 ✓)
```

That's why choosing **power-of-two scales** in training mattered: every rescaling becomes a **shift (wiring)**, never a division.

#### What you lose when you drop bits

When you shift right, the dropped bits are lost:

- **Truncation** (what this design does, `>> 5`): just drop them. It always rounds **down**.
- **Rounding**: add half a step first (here 2⁴ = 16), then shift. It's more accurate, but costs one extra adder.

The Python model uses **exactly the same truncation**, so the hardware and Python still agree bit-for-bit, and the quantization step showed it cost no accuracy.

#### And floating point?

Floating point (like Python's `float`) stores a **mantissa and an exponent** separately. Multiplying means multiplying the mantissas, adding the exponents, then renormalizing. That's **many times more hardware**, which is why hardware neural networks almost always use fixed point, as this one does.

### Summary

| Situation | What the hardware does |
|---|---|
| signed × unsigned | sign-extend the signed number, then multiply normally (**this design**) |
| signed × signed | subtract the sign bit's row, or sign-extend both and keep the low bits, or use Booth/Baugh-Wooley |
| fractional (fixed point) | **the same integer multiplier**; fractional bits add up, and shifting (wiring) moves the binary point back |
| floating point | separate mantissa and exponent hardware. Much bigger, and not used here. |

---

## 14. Does the FPGA version (one shared MAC) still have two layers?

**Yes.** The FPGA version computes **exactly the same network**: 64 → 32 → 10, both layers, the same weights and the same answers. The difference is **how the layers exist**:

- In the combinational design, each layer is **a separate piece of hardware**: 32 neurons, then 10 neurons, side by side.
- In the FPGA version, the layers are **steps in time**. One small "worker" (the MAC, multiply-accumulate unit) calculates every neuron of layer 1, one after another, then every neuron of layer 2.

It's the idea of reusing hardware (section 11) taken to the extreme: instead of reusing one *layer*, it reuses one *multiplier* for everything.

### What it does, step by step

```
Layer 1: for each hidden neuron j = 0 .. 31:
            total = bias B1(j)
            for each pixel i = 0 .. 63:
                total = total + pixel(i) × W1(j)(i)      ← 1 clock tick each
            hidden(j) = relu_shift_sat(total)            ← stored in a register

Layer 2: for each digit k = 0 .. 9:
            total = bias B2(k)
            for each hidden value j = 0 .. 31:
                total = total + hidden(j) × W2(k)(j)     ← 1 clock tick each
            if total > best_score:                       ← running argmax
                best_score = total,  digit = k

Show digit on the 7-segment display
```

### The hardware

```
                       ┌─────────────────────────────┐
 pixels (64 regs) ──┐  │                             │
                    ├─►│  MAC: mult_su + adder_n     │──► relu_shift_sat ──► hidden (32 regs) ──┐
 hidden (32 regs) ──┘  │  total = total + x × w      │                                          │
         ▲             │                             │──► comparator_gt ──► best_score, digit ──► 7-seg
         └─────────────┤                             │
                       └──────────────▲──────────────┘
                                      │ w
                          weights ROM (layer 1 + layer 2)
                                      ▲
                                      │ address
                          controller (counters: which layer, which neuron, which input)
```

| Part | What it holds or does |
|---|---|
| **64 pixel registers** | the image received over UART |
| **1 MAC** (`mult_su` + `adder_n` + an accumulator register) | the only arithmetic: one product per tick |
| **Weights ROM** | all 2,410 weights and biases, **both layers in one memory** |
| **32 hidden registers** (32 × 8 bits) | the output of layer 1, kept while layer 2 runs. **This is what makes it two layers**: layer 2 reads from here. |
| **Controller** | counters that say "layer 1 or 2, which neuron, which input". It picks the right ROM address and the right input (pixel or hidden value). |
| **comparator_gt** + best-score register | the argmax, done one digit at a time |

### How the layers connect

| | Combinational design | FPGA version (one MAC) |
|---|---|---|
| Layer 1 | 32 neurons of hardware | the same MAC, ticks 1 to about 2,080 |
| Between layers | a **wire** (`h`) | **32 registers** that store the hidden values |
| Layer 2 | 10 more neurons of hardware | the same MAC, ticks about 2,081 to 2,410 |
| Argmax | 9 comparators in a tree | 1 comparator, checked after each digit |
| Who decides the order | nobody (the signals just flow) | the controller |

In the combinational design, the layers are separated in **space**. In the FPGA version, they're separated in **time**, and the hidden registers are the bridge: layer 1 writes them, and layer 2 reads them.

### About one clock tick per parameter

```
Layer 1: 32 neurons × (64 weights + 1 bias) = 2,080 ticks
Layer 2: 10 neurons × (32 weights + 1 bias) =   330 ticks
                                              ───────────
                                               2,410 ticks  ≈ 24 µs at 100 MHz
```

That's **2,410, the number of parameters**: the MAC handles one weight (or bias) per tick. A few extra ticks are needed for starting and switching between neurons, but the total is still around 24 µs.

---

## 15. The structure of the neural network

### The whole network

```
   INPUT                    HIDDEN LAYER                  OUTPUT LAYER                ANSWER
   8x8 image = 64 pixels    32 neurons + ReLU             10 neurons, one per digit

   ┌───────────┐                                                                
   │ ▫ ▫ ▪ ■ ■ │  x0  ──┐     ┌──────────┐                ┌──────────┐            
   │ ▫ ▪ ▫ ▫ ■ │  x1  ──┤     │ neuron 0 ├─ ReLU ─ h0 ──┐ │ digit 0  ├─ score 0 ─┐
   │ ▫ ▫ ▫ ▪ ■ │  x2  ──┤     ├──────────┤               ├─┤──────────┤           │
   │ ▫ ▫ ▪ ■ ▫ │   .    ├─────┤ neuron 1 ├─ ReLU ─ h1 ──┤ │ digit 1  ├─ score 1 ─┤   ┌────────┐
   │ ▫ ▫ ■ ▫ ▫ │   .    │ all │    .     │               │ │    .     │           ├──►│ argmax ├──► digit
   │ ▫ ▪ ■ ▫ ▫ │   .    │ to  │    .     │      .        ├─┤    .     │     .     │   │ (the   │    (0-9)
   │ ▫ ■ ▪ ▫ ▫ │   .    │ all │    .     │      .        │ │    .     │     .     │   │ largest│
   │ ▫ ■ ▫ ▫ ▫ │  x63 ──┘     │ neuron 31├─ ReLU ─ h31 ─┘ │ digit 9  ├─ score 9 ─┘   │ score) │
   └───────────┘              └──────────┘                 └──────────┘               └────────┘
    64 inputs              each neuron: 64 weights        each neuron: 32 weights
    (0..15 each)                       + 1 bias                       + 1 bias
```

**"All to all"** means the layers are **fully connected**: every pixel goes into every hidden neuron, and every hidden value goes into every output neuron. That's 64 × 32 connections into the hidden layer and 32 × 10 into the output layer, each with its own weight (see section 6).

### Inside one neuron

Every neuron, in both layers, does the same thing:

```
   x0 ──── × w0 ──┐
   x1 ──── × w1 ──┤
   x2 ──── × w2 ──┼──►  Σ  ──►  + bias  ──►  (hidden layer only:  ReLU, then shift >> 5)  ──►  output
    .        .    │    add
   xN ──── × wN ──┘    everything
```

- **× w**: each input is multiplied by its own weight (`mult_su`)
- **Σ**: all the products are added up (an adder tree in the combinational design, or an accumulator in the FPGA version)
- **+ bias**: shifts the neuron's threshold
- **ReLU** (hidden layer only): negative sums become 0
- **>> 5** (hidden layer only): divides by 32 so the hidden value fits in 8 bits (0..255)

### The numbers, step by step

```
 pixel            weight            product           sum of 64 + bias          hidden value
 0..15     ×    -128..127    =     12 bits     ──►      15 bits         ──►  ReLU, >> 5, max 255  ──►  0..255
 (4 bits)       (8 bits, Q2.6)                                                                         (8 bits)

 hidden value     weight            product           sum of 32 + bias          score             digit
 0..255     ×   -128..127    =     16 bits     ──►      19 bits         ──►  argmax of 10 scores  ──►  0..9
 (8 bits)       (8 bits, Q2.6)                                                                        (4 bits)
```

The weights actually learned are in −69..72 (layer 1) and −115..66 (layer 2). Divided by 64 (Q2.6), that's about −1.8 to +1.1 as real numbers.

### The size

| Layer | Neurons | Inputs per neuron | Weights | Biases | Parameters |
|---|---|---|---|---|---|
| Hidden | 32 | 64 | 2,048 | 32 | 2,080 |
| Output | 10 | 32 | 320 | 10 | 330 |
| **Total** | **42** | | **2,368** | **42** | **2,410** |

One hidden neuron (number 24) is "dead": training left all its weights and its bias at 0, so it always outputs 0. The network effectively uses 31 hidden neurons.

### The same network in the three hardware versions

| | Combinational (course design) | FPGA, 32 MACs (on the board) | FPGA, 1 MAC (fallback) |
|---|---|---|---|
| Hidden layer | 32 neurons of hardware, all at once | **32 MACs**, one per hidden neuron; one pixel per clock tick (64 ticks) | 1 MAC, one weight per tick |
| Output layer | 10 more neurons of hardware | MACs 0–9 reused; one hidden value per tick (32 ticks) | the same MAC |
| Between the layers | wires | 32 registers (the hidden values) | 32 registers |
| Argmax | a tree of 9 comparators | the same tree of 9 comparators | 1 comparator, one digit at a time |
| Time per image | one pass through the gates | 99 ticks ≈ 8 µs (network at 12.5 MHz) | 2,452 ticks |

The network (its structure and weights) is **identical** in all three versions, and all three give bit-for-bit the same answers as the Python model on the 360 test images. Only the way the hardware is organized differs.

---

## 16. What is `weights_rom32.vhd`, and why are its lines so long?

`weights_rom32.vhd` is the **memory holding all the trained weights** for the 32-MAC FPGA version. Its lines are long because **each line holds 32 weights side by side**: all the weights the 32 MACs need for one clock tick.

### Why the weights are stored in wide rows

In the 32-MAC design, **all 32 hidden neurons work at the same time**. On each clock tick, one pixel goes to all 32 MACs at once, and **each MAC needs its own weight for that pixel**:

```
tick 20:  pixel 20 ──┬──► MAC 0   needs W1(0)(20)
                     ├──► MAC 1   needs W1(1)(20)
                     ├──► MAC 2   needs W1(2)(20)
                     │      ...
                     └──► MAC 31  needs W1(31)(20)
```

So for each pixel, the ROM has to deliver **32 weights in one read**. Each weight is 8 bits, so **one row = 32 × 8 = 256 bits**.

### What's in the file

It contains two ROMs:

| ROM | Address | Rows | Bits per row | Holds |
|---|---|---|---|---|
| `rom_l1` | pixel number (0–63) | **64** | **256** (32 weights × 8 bits) | layer 1: for each pixel, its weight into each of the 32 hidden neurons |
| `rom_l2` | hidden value number (0–31) | **32** | **80** (10 weights × 8 bits) | layer 2: for each hidden value, its weight into each of the 10 digits |

### How to read one row

Here's row 20 of `rom_l1` (pixel 20), whose last 32 bits are:

```
... 00011011  00100001  00011111  00000101
    neuron 3  neuron 2  neuron 1  neuron 0     ← neuron 0 is on the RIGHT
       27        33        31         5
```

Each group of 8 bits is one weight, in two's complement. **Neuron 0's weight is the rightmost 8 bits** (bits 7–0), neuron 1's is the next 8 (bits 15–8), and so on up to neuron 31 on the far left (bits 255–248). In the VHDL, MAC `j` takes its slice like this:

```vhdl
w1_row((j+1)*WEIGHT_W-1 downto j*WEIGHT_W)     -- bits 8j+7 downto 8j
```

### It's not more data, just a different shape

| | One-MAC version (`weights_rom.vhd`) | 32-MAC version (`weights_rom32.vhd`) |
|---|---|---|
| Shape | **2,368 rows × 8 bits** (one weight per row) | **64 rows × 256 bits** + **32 rows × 80 bits** |
| Total | 18,944 bits | 16,384 + 2,560 = **18,944 bits** |
| Weights per read | 1 (one MAC) | 32 (or 10) for 32 MACs at once |

It's **the same 2,368 weights**, just arranged differently. The one-MAC version reads one weight per tick, so it uses narrow rows. The 32-MAC version reads 32 per tick, so it uses wide rows. That's also why `weights_rom32.vhd` is a much shorter file (133 lines) than `weights_rom.vhd` (about 2,400 lines), even though it holds the same numbers.

### How it becomes hardware

Each ROM is written as a `with … select` lookup table. On the FPGA, it becomes logic, not a block of memory: `rom_l1` has a 6-bit address (64 rows), and one Spartan-6 LUT is exactly a 6-input lookup table, so **each of the 256 output bits fits in one LUT**. The whole layer-1 ROM is therefore about 256 LUTs.

Like `weights_pkg.vhd`, the file is **generated** by `python/export_rom.py` from the trained weights, so don't edit it by hand. If you retrain, rerun the script.

---

## 17. The output-layer weights and the biases (FPGA version)

### The output-layer weights: `rom_l2`

The output-layer weights are the **second ROM** in `weights_rom32.vhd`. It works exactly like the layer-1 ROM, just smaller.

During layer 2, **one hidden value per clock tick** goes to MACs 0–9 (one MAC per digit), and each needs its own weight for that hidden value:

```
tick 3 of layer 2:  hidden value 3 ──┬──► MAC 0 (digit 0)  needs W2(0)(3)
                                     ├──► MAC 1 (digit 1)  needs W2(1)(3)
                                     │      ...
                                     └──► MAC 9 (digit 9)  needs W2(9)(3)
```

So each row holds **10 weights × 8 bits = 80 bits**, and there's **one row per hidden value**: **32 rows**.

| | `rom_l1` (hidden layer) | `rom_l2` (output layer) |
|---|---|---|
| Address | pixel number (0–63) | hidden value number (0–31) |
| Rows | 64 | **32** |
| Weights per row | 32 (one per hidden neuron) | **10 (one per digit)** |
| Bits per row | 256 | **80** |
| Total | 2,048 weights | **320 weights** |
| Weights actually learned | −69 to 72 | **−115 to 66** |

**A real row, hidden value 3:**

```
11101000 11001000 00100011 11000111 11001010 11110110 11100001 01000001 00011110 00111011
 digit 9  digit 8  digit 7  digit 6  digit 5  digit 4  digit 3  digit 2  digit 1  digit 0
   -24      -56      35      -57      -54      -10      -31      65       30       59
```

As in `rom_l1`, **digit 0 is on the right** (bits 7–0) and digit 9 on the left (bits 79–72).

**What this row means:** when **hidden neuron 3** is active (a high value), it

- **pushes up** digits **2** (+65), **0** (+59), **7** (+35) and **1** (+30)
- **pushes down** digits **6** (−57), **8** (−56), **5** (−54), **3** (−31), **9** (−24) and **4** (−10)

So hidden neuron 3 has learned a feature that looks like a 0, 2, 7 or 1, and unlike a 6, 8 or 5. Every hidden neuron has a row like this, and the digit with the most "votes" in total wins the argmax.

**How it's connected** (`mlp_par32.vhd`):

```vhdl
rom2 : entity work.rom_l2 port map (j => i(HADDR_W-1 downto 0), w => w2_row);
```

The **same input counter `i`** addresses both ROMs. In layer 1 it counts pixels 0–63 (6 bits). In layer 2 it counts hidden values 0–31, and only its lower 5 bits (`HADDR_W = 5`) go to `rom_l2`.

```vhdl
w(j) <= w2_row((j+1)*WEIGHT_W-1 downto j*WEIGHT_W) when is_mac2 = '1' else
        w1_row((j+1)*WEIGHT_W-1 downto j*WEIGHT_W);
```

Each of MACs 0–9 has a **multiplexer** that picks its weight from `rom_l2` during layer 2 (`is_mac2 = '1'`) and from `rom_l1` during layer 1. MACs 10–31 aren't used in layer 2, so they only connect to `rom_l1`.

### The biases: constants, not a ROM

The biases **aren't in the ROM file at all**. They're **constants** in `fpga/src/mlp_params.vhd`:

```vhdl
type bias_array is array (natural range <>) of std_logic_vector(ACC_W-1 downto 0);
constant B1 : bias_array(0 to N_HIDDEN-1) := (
  "0000000000000000100",  -- neuron 0: 4
  "1111111111111111111",  -- neuron 1: -1
  "0000000000001111010",  -- neuron 2: 122
  ...
constant B2 : bias_array(0 to N_OUT-1) := (
  "0000000000101011011",  -- digit 0: 347
  "1111111111100001010",  -- digit 1: -246
  ...
```

| | Count | Stored width | Values actually learned |
|---|---|---|---|
| `B1` (hidden layer) | 32, one per hidden neuron | **19 bits** | −17 to 440 |
| `B2` (output layer) | 10, one per digit | **19 bits** | −246 to 347 |

**Why 19 bits, when the values only need 10?** The bias goes straight into the **19-bit accumulator**, so it's stored already **sign-extended** to 19 bits. The extra bits on the left are copies of the sign bit: 0s for positive biases, 1s for negative (−1 is all 1s). No extra hardware is needed to widen it.

**What the values mean:** like the weights, they're integers with a scale (section 4, step 5):

| | Scale | Example |
|---|---|---|
| `B1` | × 2¹⁰ = 1,024 | neuron 2: 122 → real bias 122 / 1,024 ≈ **0.12** |
| `B2` | × 2¹¹ = 2,048 | digit 0: 347 → real bias 347 / 2,048 ≈ **0.17** |

A positive bias makes a neuron fire more easily; a negative one makes it harder. For example, digit 1 has a bias of **−246**: the network needs a bit more evidence before it answers "1".

### Why the weights are in a ROM but the biases are constants

Each neuron has **fixed** weights and a **fixed** bias: hidden neuron 5, for example, owns **64 weights** (one per pixel) and **1 bias**, and none of them ever change after training.

```
Neuron 5:   W(5)(0)   W(5)(1)   W(5)(2)   ...   W(5)(63)      B(5)
               12        -8        40      ...       3          29
            └──────────────── 64 weights ─────────────────┘   1 bias
```

(The numbers are illustrative.)

But in the FPGA, pixels arrive **one per clock tick**, so MAC 5 can only multiply **one pixel by one weight** per tick:

```
tick 1:   pixel 0  ×  W(5)(0)    ← needs weight #0
tick 2:   pixel 1  ×  W(5)(1)    ← needs weight #1
...
tick 64:  pixel 63 ×  W(5)(63)   ← needs weight #63
```

The weights don't change, but MAC 5 needs **a different one of its 64 weights on each tick**, so something has to **pick the right one** each time ("it's tick 20, so give me weight #20"). **That picking is what the ROM does.** The bias is **only one number**, so there's **nothing to pick**: it's just wired in.

**The rule:** when one piece of hardware has to use **different numbers at different times**, a ROM picks the right one. When it always uses **the same number**, it's just a constant.

You can see the rule at work in all three versions:

| Design | Pixels arrive… | Weights | Bias |
|---|---|---|---|
| Combinational | all at once (64 multipliers per neuron, each always using the same weight) | **constants** | constant |
| FPGA, 32 MACs | one per tick (1 multiplier per neuron) | **ROM** (pick one per tick) | constant |
| FPGA, 1 MAC | one per tick, and one neuron after another | **ROM** | **ROM** (the one MAC computes all 42 neurons, so its bias changes too: `bias_rom`) |

**The one small exception:** MACs 0–9 in the 32-MAC version have **two** fixed biases, one for their layer-1 neuron and one for their layer-2 digit. So they get a 2-way switch (a multiplexer) instead of a ROM:

```vhdl
bias(j) <= B2(j) when is_fin1 = '1' else B1(j);   -- MACs 0..9
bias(j) <= B1(j);                                 -- MACs 10..31 (layer 1 only)
```

### When is the bias added? First, not last

The neuron's formula is:

  **output = (w₀·x₀ + w₁·x₁ + … + w₆₃·x₆₃) + b**

The formula adds b **after** the sum. The FPGA adds it **first**, by starting the accumulator at b instead of 0. Addition doesn't care about order, so the result is identical.

**Example** with 2 inputs: w = (2, 3), x = (1, 4), b = 5

| b last (the formula) | b first (the FPGA) |
|---|---|
| 0 + 2·1 = 2 | **5** + 2·1 = 7 |
| 2 + 3·4 = 14 | 7 + 3·4 = 19 |
| 14 **+ 5** = **19** | = **19** |

Both give **19**, because everything is **integer** arithmetic with nothing rounded in between.

**Why the hardware does it first:** adding b at the end would need an extra step after the 64 multiplications. Starting at b uses the **same adder** that's already there for the products, so it costs nothing extra:

```
LOAD:      acc = b                ← "load" the bias (instead of 0)
tick 1:    acc = acc + w₀·x₀
tick 2:    acc = acc + w₁·x₁
...
tick 64:   acc = acc + w₆₃·x₆₃    → acc = b + Σ wᵢ·xᵢ  ✓ same as Σ wᵢ·xᵢ + b
```

| State | What the MACs load |
|---|---|
| **LOAD** (start of layer 1) | all 32 MACs load `B1(j)` |
| **FIN1** (between the layers) | MACs 0–9 load `B2(k)`, the digit biases, ready for layer 2 |

In the **combinational** design, the bias is added as **one more input to the adder tree**: all 64 products and b go into the tree together and get added in pairs. So b isn't "last" there either, and the answer is again the same.
