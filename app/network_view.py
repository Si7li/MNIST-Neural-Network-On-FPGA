import numpy as np
import tkinter as tk

WIDTH, HEIGHT = 560, 480
CELL = 24
GRID_X, GRID_Y = 16, (HEIGHT - 8 * CELL) // 2
HID_X = (300, 336)
HID_Y0, HID_DY, HID_R = 26, 27, 10
OUT_X, OUT_Y0, OUT_DY, OUT_R = 500, 62, 40, 13
STEP_MS = 22

BG = "#1e1f22"
NODE_OFF = "#2b2d31"
OUTLINE = "#4a4d55"
TEXT = "#e3e5e8"
MUTED = "#9aa0a6"
FLOW = (79, 140, 255)
HOT = (255, 176, 0)
FOCUS = "#3d7eff"
FAINT = "#26282c"


def mix(a, b, t):
    t = min(max(t, 0.0), 1.0)
    r, g, bl = (int(x + (y - x) * t) for x, y in zip(a, b))
    return f"#{r:02x}{g:02x}{bl:02x}"


def rgb(c):
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


class NetworkView:
    def __init__(self, parent, status_label=None):
        self.canvas = tk.Canvas(parent, width=WIDTH, height=HEIGHT, bg=BG, highlightthickness=0)
        self.status = status_label
        self.pixels = np.zeros(64, dtype=np.int64)
        self.hidden = None
        self.connected = False
        self.replay_job = None
        self.lines = []
        self.draw_static()
        self.refresh()

    def grid(self, **kw):
        self.canvas.grid(**kw)

    def hid_pos(self, j):
        return HID_X[j // 16], HID_Y0 + (j % 16) * HID_DY

    def out_pos(self, k):
        return OUT_X, OUT_Y0 + k * OUT_DY

    def cell_center(self, i):
        return GRID_X + (i % 8) * CELL + CELL / 2, GRID_Y + (i // 8) * CELL + CELL / 2

    def draw_static(self):
        c = self.canvas
        c.create_text(GRID_X, GRID_Y - 30, text="INPUT", anchor="w", fill=MUTED, font=("TkDefaultFont", 10, "bold"))
        c.create_text(GRID_X, GRID_Y - 14, text="64 pixels sent to the FPGA", anchor="w", fill=MUTED, font=("TkDefaultFont", 9))
        c.create_text(318, 8, text="HIDDEN  32 neurons (from the FPGA)", fill=MUTED, font=("TkDefaultFont", 10, "bold"))
        c.create_text(OUT_X, 22, text="OUTPUT", fill=MUTED, font=("TkDefaultFont", 10, "bold"))
        c.create_text(OUT_X, 38, text="10 digits", fill=MUTED, font=("TkDefaultFont", 9))
        c.create_text(OUT_X, HEIGHT - 16, text="answer: on the board", fill=MUTED, font=("TkDefaultFont", 9))

        self.out_lines = [[c.create_line(self.hid_pos(j)[0] + HID_R, self.hid_pos(j)[1],
                                         OUT_X - OUT_R, self.out_pos(k)[1], fill=FAINT)
                           for j in range(32)] for k in range(10)]
        self.cells = [c.create_rectangle(GRID_X + (i % 8) * CELL, GRID_Y + (i // 8) * CELL,
                                         GRID_X + (i % 8 + 1) * CELL, GRID_Y + (i // 8 + 1) * CELL,
                                         fill="#000000", outline=NODE_OFF) for i in range(64)]
        self.focus_box = c.create_rectangle(0, 0, 0, 0, outline=FOCUS, width=3, state="hidden")
        self.hid = []
        for j in range(32):
            x, y = self.hid_pos(j)
            self.hid.append(c.create_oval(x - HID_R, y - HID_R, x + HID_R, y + HID_R,
                                          fill=NODE_OFF, outline=OUTLINE))
        self.out = []
        for k in range(10):
            x, y = self.out_pos(k)
            self.out.append(c.create_oval(x - OUT_R, y - OUT_R, x + OUT_R, y + OUT_R,
                                          fill=NODE_OFF, outline=OUTLINE, width=2))
            c.create_text(x, y, text=str(k), fill=TEXT, font=("TkDefaultFont", 11, "bold"))

    def say(self, text):
        if self.status is not None:
            self.status.config(text=text)

    def clear_lines(self):
        for line in self.lines:
            self.canvas.delete(line)
        self.lines = []

    def line(self, x0, y0, x1, y1, strength):
        line = self.canvas.create_line(x0, y0, x1, y1, width=1 + 3 * strength,
                                       fill=mix(rgb(BG), FLOW, 0.25 + 0.75 * strength))
        self.canvas.tag_lower(line)
        self.lines.append(line)

    def paint_pixels(self):
        for cell, v in zip(self.cells, self.pixels):
            shade = int(v) * 255 // 15
            self.canvas.itemconfig(cell, fill=f"#{shade:02x}{shade:02x}{shade:02x}")

    def paint_hidden(self):
        if self.hidden is None:
            for node in self.hid:
                self.canvas.itemconfig(node, fill=NODE_OFF)
            return
        top = max(int(self.hidden.max()), 1)
        for node, v in zip(self.hid, self.hidden):
            self.canvas.itemconfig(node, fill=mix(rgb(NODE_OFF), HOT, v / top))

    def reset_marks(self):
        self.canvas.itemconfig(self.focus_box, state="hidden")
        for node in self.hid:
            self.canvas.itemconfig(node, outline=OUTLINE, width=1)
        for node in self.out:
            self.canvas.itemconfig(node, outline=OUTLINE)
        for row in self.out_lines:
            for line in row:
                self.canvas.itemconfig(line, fill=FAINT, width=1)

    def show(self, pixels):
        self.pixels = np.asarray(pixels, dtype=np.int64)
        if not self.pixels.any():
            self.hidden = None
        self.refresh()

    def set_hidden(self, values):
        self.hidden = None if values is None else np.asarray(values, dtype=np.int64)
        self.refresh()

    def set_connected(self, connected):
        self.connected = connected
        if not connected:
            self.hidden = None
        self.refresh()

    def refresh(self):
        if self.replay_job is not None:
            return
        self.reset_marks()
        self.clear_lines()
        self.paint_pixels()
        self.paint_hidden()
        if self.hidden is not None:
            top = max(int(self.hidden.max()), 1)
            for j, v in enumerate(self.hidden):
                if v > 0:
                    hx, hy = self.hid_pos(j)
                    self.line(GRID_X + 8 * CELL, GRID_Y + 4 * CELL, hx - HID_R, hy, v / top)
                    for k in range(10):
                        self.canvas.itemconfig(self.out_lines[k][j], width=1 + 2 * v / top,
                                               fill=mix(rgb(BG), FLOW, 0.2 + 0.6 * v / top))
        if not self.connected:
            self.say("Connect the board: the hidden neurons show the values the FPGA computes.")
        elif not self.pixels.any():
            self.say("Draw a digit: the FPGA will send back its 32 hidden values.")
        elif self.hidden is None:
            self.say("Waiting for the FPGA's hidden values...")
        else:
            active = int((self.hidden > 0).sum())
            self.say(f"From the FPGA: {active} of 32 hidden neurons active "
                     f"(brighter = larger value, max {int(self.hidden.max())}).")

    def replay(self):
        if not self.pixels.any():
            self.say("Draw a digit first.")
            return
        self.stop_replay()
        self.step = 0
        self.replay_job = self.canvas.after(0, self.tick)

    def stop_replay(self):
        if self.replay_job is not None:
            self.canvas.after_cancel(self.replay_job)
            self.replay_job = None

    def tick(self):
        s = self.step
        self.clear_lines()
        if s == 0:
            self.reset_marks()
            for node in self.hid:
                self.canvas.itemconfig(node, fill=NODE_OFF, outline=FOCUS)
            self.say("Step 1/99  LOAD: all 32 MACs start with their bias.")
        elif s <= 64:
            i = s - 1
            x0, y0 = GRID_X + (i % 8) * CELL, GRID_Y + (i // 8) * CELL
            self.canvas.coords(self.focus_box, x0, y0, x0 + CELL, y0 + CELL)
            self.canvas.itemconfig(self.focus_box, state="normal")
            if self.pixels[i] > 0:
                cx, cy = self.cell_center(i)
                for j in range(32):
                    hx, hy = self.hid_pos(j)
                    self.line(cx + CELL / 2, cy, hx - HID_R, hy, self.pixels[i] / 15)
            what = (f"value {self.pixels[i]}, sent to all 32 MACs at once"
                    if self.pixels[i] else "value 0, adds nothing")
            self.say(f"Step {s + 1}/99  LAYER 1: pixel {i} (row {i // 8}, col {i % 8}), {what}.")
        elif s == 65:
            self.reset_marks()
            self.paint_hidden()
            if self.hidden is None:
                self.say("Step 66/99  FIN1: ReLU and >> 5 give the 32 hidden values. "
                         "Connect the board to see the values the FPGA computes.")
            else:
                active = int((self.hidden > 0).sum())
                self.say(f"Step 66/99  FIN1: ReLU (negative -> 0) and >> 5. These are the values "
                         f"the FPGA computed: {active} neurons active, {32 - active} off.")
        elif s <= 97:
            j = s - 66
            for row in self.out_lines:
                for line in row:
                    self.canvas.itemconfig(line, fill=FAINT, width=1)
            self.canvas.itemconfig(self.hid[j], outline=FOCUS, width=3)
            if j > 0:
                self.canvas.itemconfig(self.hid[j - 1], outline=OUTLINE, width=1)
            sends = self.hidden is None or self.hidden[j] > 0
            for k in range(10):
                self.canvas.itemconfig(self.out[k], outline=FOCUS if sends else OUTLINE)
                if sends:
                    self.canvas.itemconfig(self.out_lines[k][j], fill=FOCUS, width=2)
            value = "" if self.hidden is None else f" (value {self.hidden[j]})"
            self.say(f"Step {s + 1}/99  LAYER 2: hidden value {j}{value} goes to MACs 0-9 "
                     f"(one per digit).")
        else:
            self.replay_job = None
            self.refresh()
            for node in self.out:
                self.canvas.itemconfig(node, outline=FOCUS)
            self.say("Step 99/99  FIN2: argmax picks the largest of the 10 scores. "
                     "The answer is on the board's display.")
            return
        self.step += 1
        self.replay_job = self.canvas.after(STEP_MS, self.tick)
