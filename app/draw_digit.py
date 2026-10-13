import argparse

import numpy as np
import tkinter as tk
from tkinter import ttk

from network_view import NetworkView
from preprocess import frame_bytes, strokes_to_pixels

BAUD = 115200
CANVAS = 480
PEN = 22
UPDATE_MS = 60
POLL_MS = 20
PACKET_LEN = 34
HEADER, FOOTER = 0xA5, 0x5A

BG = "#1e1f22"
PANEL = "#2b2d31"
HOVER = "#3a3d43"
ACCENT = "#3d7eff"
TEXT = "#e3e5e8"
MUTED = "#9aa0a6"
GOOD = "#57d18b"
BAD = "#ff6b6b"
INK = "#f5f5f5"
PAPER = "#000000"
FONT = ("TkDefaultFont", 13)


def serial_ports():
    try:
        from serial.tools import list_ports
    except ImportError:
        return []
    found = [p.device for p in list_ports.comports()]
    return sorted(found, key=lambda d: (0 if "ttyUSB" in d else 1, d))


class App:
    def __init__(self, root, port=None):
        self.root = root
        self.serial = None
        self.strokes = []
        self.last_sent = None
        self.update_pending = False
        self.pixels = np.zeros(64, dtype=np.int64)
        self.received = bytearray()
        self.packets = 0
        root.title("Draw a digit for the Nexys 3")
        root.resizable(False, False)
        self.dark_theme()
        self.build()
        self.refresh_ports(port)
        if port:
            self.toggle_connection()
        self.root.after(POLL_MS, self.poll)

    def dark_theme(self):
        self.root.configure(bg=BG)
        style = ttk.Style(self.root)
        style.theme_use("clam")
        style.configure(".", background=BG, foreground=TEXT, font=FONT)
        style.configure("Title.TLabel", font=(FONT[0], 16, "bold"))
        style.configure("Status.TLabel", foreground=MUTED, font=(FONT[0], 12))
        style.configure("TButton", background=PANEL, foreground=TEXT, borderwidth=0,
                        focusthickness=0, padding=(14, 9))
        style.map("TButton", background=[("pressed", ACCENT), ("active", HOVER)])
        style.configure("TCombobox", fieldbackground=PANEL, background=PANEL,
                        foreground=TEXT, arrowcolor=TEXT, bordercolor=PANEL,
                        lightcolor=PANEL, darkcolor=PANEL, padding=7)
        style.map("TCombobox", fieldbackground=[("readonly", PANEL)],
                  background=[("active", HOVER)])
        self.root.option_add("*TCombobox*Listbox.background", PANEL)
        self.root.option_add("*TCombobox*Listbox.foreground", TEXT)
        self.root.option_add("*TCombobox*Listbox.selectBackground", ACCENT)
        self.root.option_add("*TCombobox*Listbox.font", FONT)

    def build(self):
        frame = ttk.Frame(self.root, padding=20)
        frame.grid()
        ttk.Label(frame, text="Draw a digit", style="Title.TLabel").grid(
            row=0, column=0, columnspan=4, sticky="w")
        ttk.Label(frame, text="Fill the box from top to bottom.", foreground=MUTED).grid(
            row=1, column=0, columnspan=4, sticky="w")
        self.canvas = tk.Canvas(frame, width=CANVAS, height=CANVAS, bg=PAPER,
                                highlightthickness=2, highlightbackground=HOVER,
                                cursor="crosshair")
        self.canvas.grid(row=2, column=0, columnspan=4, pady=12)
        self.canvas.bind("<ButtonPress-1>", self.pen_down)
        self.canvas.bind("<B1-Motion>", self.pen_move)
        self.canvas.bind("<ButtonRelease-1>", self.pen_up)
        ttk.Button(frame, text="Clear  (c)", command=self.clear).grid(
            row=3, column=0, columnspan=4, sticky="we")
        self.root.bind("c", lambda e: self.clear())
        self.root.bind("<Escape>", lambda e: self.clear())

        ttk.Label(frame, text="Port").grid(row=4, column=0, sticky="w", pady=(16, 0))
        self.port_box = ttk.Combobox(frame, width=16, font=FONT)
        self.port_box.grid(row=4, column=1, sticky="we", padx=8, pady=(16, 0))
        ttk.Button(frame, text="Refresh", command=self.refresh_ports).grid(
            row=4, column=2, sticky="we", pady=(16, 0))
        self.connect_button = ttk.Button(frame, text="Connect", command=self.toggle_connection)
        self.connect_button.grid(row=4, column=3, sticky="we", padx=(8, 0), pady=(16, 0))
        self.status = ttk.Label(frame, text="Not connected.", style="Status.TLabel")
        self.status.grid(row=5, column=0, columnspan=4, sticky="w", pady=(10, 0))
        frame.columnconfigure(1, weight=1)

        side = ttk.Frame(frame, padding=(28, 0, 0, 0))
        side.grid(row=0, column=4, rowspan=6, sticky="n")
        ttk.Label(side, text="The network", style="Title.TLabel").grid(sticky="w")
        ttk.Label(side, text="64 pixels -> 32 hidden neurons -> 10 digits",
                  foreground=MUTED).grid(sticky="w")
        net_status = ttk.Label(side, style="Status.TLabel", wraplength=540, justify="left")
        self.network = NetworkView(side, net_status)
        self.network.grid(sticky="w", pady=12)
        ttk.Button(side, text="\u25b6  Show how the FPGA computes it",
                   command=self.network.replay).grid(sticky="we")
        net_status.grid(sticky="w", pady=(10, 0))

    def pen_down(self, event):
        self.strokes.append([(event.x, event.y)])
        r = PEN / 2
        self.canvas.create_oval(event.x - r, event.y - r, event.x + r, event.y + r,
                                fill=INK, outline="")
        self.schedule_update()

    def pen_move(self, event):
        x0, y0 = self.strokes[-1][-1]
        self.strokes[-1].append((event.x, event.y))
        self.canvas.create_line(x0, y0, event.x, event.y, width=PEN, fill=INK,
                                capstyle=tk.ROUND, joinstyle=tk.ROUND)
        self.schedule_update()

    def pen_up(self, event):
        self.schedule_update()

    def clear(self):
        self.strokes = []
        self.canvas.delete("all")
        self.update()

    def schedule_update(self):
        if not self.update_pending:
            self.update_pending = True
            self.root.after(UPDATE_MS, self.update)

    def update(self):
        self.update_pending = False
        self.pixels, _ = strokes_to_pixels(self.strokes)
        self.network.show(self.pixels)
        self.send()

    def send(self):
        if self.serial is None or not self.strokes:
            return
        if np.array_equal(self.pixels, self.last_sent):
            return
        try:
            self.serial.write(frame_bytes(self.pixels))
            self.last_sent = self.pixels
        except Exception as err:
            self.disconnect(f"Lost the board: {err}")

    def poll(self):
        if self.serial is not None:
            try:
                self.received += self.serial.read(self.serial.in_waiting or 0)
            except Exception as err:
                self.disconnect(f"Lost the board: {err}")
            latest = None
            while len(self.received) >= PACKET_LEN:
                if self.received[0] == HEADER and self.received[PACKET_LEN - 1] == FOOTER:
                    latest = list(self.received[1:PACKET_LEN - 1])
                    del self.received[:PACKET_LEN]
                    self.packets += 1
                else:
                    del self.received[0]
            if latest is not None and self.strokes:
                self.network.set_hidden(latest)
        self.root.after(POLL_MS, self.poll)

    def refresh_ports(self, preferred=None):
        ports = serial_ports()
        self.port_box["values"] = ports
        if preferred:
            self.port_box.set(preferred)
        elif ports and not self.port_box.get():
            self.port_box.set(ports[0])

    def toggle_connection(self):
        if self.serial is not None:
            self.disconnect("Not connected.")
            return
        device = self.port_box.get().strip()
        if not device:
            self.show("No serial port found: is the board's UART cable plugged in?", BAD)
            return
        try:
            import serial
            self.serial = serial.Serial(device, BAUD, timeout=0)
        except ImportError:
            self.show("pyserial is missing: .venv/bin/pip install pyserial", BAD)
            return
        except PermissionError:
            self.show(f"No permission for {device}: add yourself to the "
                      "'uucp' group, then log out and in.", BAD)
            return
        except Exception as err:
            self.show(f"Could not open {device}: {err}", BAD)
            return
        self.connect_button.config(text="Disconnect")
        self.show(f"Connected to {device}: the digit appears on the 7-segment display.", GOOD)
        self.serial.reset_input_buffer()
        self.received.clear()
        self.last_sent = None
        self.network.set_connected(True)
        self.send()

    def show(self, message, color=MUTED):
        self.status.config(text=message, foreground=color)

    def disconnect(self, message):
        if self.serial is not None:
            self.serial.close()
        self.serial = None
        self.connect_button.config(text="Connect")
        self.network.set_connected(False)
        self.show(message, BAD if message.startswith("Lost") else MUTED)


def main():
    parser = argparse.ArgumentParser(description="Draw a digit with the mouse; the Nexys 3 board shows the answer on its 7-segment display.")
    parser.add_argument("--port", help="serial port of the board, e.g. /dev/ttyUSB0")
    args = parser.parse_args()
    root = tk.Tk()
    App(root, args.port)
    root.mainloop()


if __name__ == "__main__":
    main()
