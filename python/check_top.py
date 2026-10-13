import re
from pathlib import Path

import numpy as np

from check_results import read_list
from export_top_testbench import BIT_NS

ROOT = Path(__file__).parent.parent
RESULTS = ROOT / "fpga" / "sim" / "results_top.lst"
TXD_VCD = ROOT / "fpga" / "sim" / "top_txd.vcd"
PARAMS = Path(__file__).parent / "out" / "quant_params.npz"

SEGMENTS = ["1000000", "1111001", "0100100", "0110000", "0011001",
            "0010010", "0000010", "1111000", "0000000", "0010000"]
DASH = "0111111"
HEADER, FOOTER = 0xA5, 0x5A


def txd_changes(path):
    text = path.read_text()
    unit = re.search(r"\$timescale\s+(\d+)\s*(\w+)", text)
    scale_ns = int(unit.group(1)) * {"ps": 1e-3, "ns": 1, "us": 1e3}[unit.group(2)]
    code = re.search(r"\$var\s+\w+\s+\d+\s+(\S+)\s+txd", text).group(1)
    changes, t = [], 0
    for token in text.split("$enddefinitions")[1].split():
        if token.startswith("#"):
            t = int(token[1:]) * scale_ns
        elif token[1:] == code and token[0] in "01":
            changes.append((t, int(token[0])))
    return changes


def uart_decode(changes):
    def level_at(t):
        level = 1
        for ct, cl in changes:
            if ct > t:
                break
            level = cl
        return level

    out, t_end = [], -1
    for t, level in changes:
        if level == 0 and t >= t_end:
            bits = [level_at(t + (b + 1.5) * BIT_NS) for b in range(8)]
            out.append(sum(bit << b for b, bit in enumerate(bits)))
            t_end = t + 9.5 * BIT_NS
    return out


def packets(data):
    found, i = [], 0
    while i + 34 <= len(data):
        if data[i] == HEADER and data[i + 33] == FOOTER:
            found.append(data[i + 1:i + 33])
            i += 34
        else:
            i += 1
    return found


def main():
    p = np.load(PARAMS)
    expected, exp_hidden = p["expected_pred"], p["expected_hidden"]
    names, rows = read_list(RESULTS)
    col = {name: c for c, name in enumerate(names)}

    problems, images, shown = [], 0, []
    for row in rows:
        n = int(row[col["image_no"]])
        led, seg, an = row[col["led"]], row[col["seg"]], row[col["an"]]
        if n < 0:
            if seg != DASH or led[0] != "0":
                problems.append(f"warm-up: display {seg}, LEDs {led} (expected '-' and valid off)")
            continue
        images += 1
        want = int(expected[n])
        got = int(led[4:], 2)
        shown.append(str(SEGMENTS.index(seg)) if seg in SEGMENTS else "?")
        if got != want or led[0] != "1" or seg != SEGMENTS[want] or an != "1110":
            problems.append(f"image {n}: expected {want}, got LEDs {led}, display {seg}, an {an}")

    data = uart_decode(txd_changes(TXD_VCD))
    got_packets = packets(data)
    hidden_ok = (len(got_packets) == images and
                 all(list(pk) == list(exp_hidden[n]) for n, pk in enumerate(got_packets)))

    print(f"Slots checked:        warm-up + {images} images")
    print(f"Display showed:       {''.join(shown)}")
    print(f"Expected:             {''.join(str(int(d)) for d in expected[:images])}")
    print(f"Display and LEDs:     {'OK' if not problems else f'{len(problems)} problems'}")
    print(f"Bytes sent on txd:    {len(data)} = {len(got_packets)} packets of 34 bytes"
          f" (expected {images} packets, {images * 34} bytes)")
    print(f"Hidden values sent:   {'OK, all match' if hidden_ok else 'MISMATCH'}")
    for line in problems[:10]:
        print("  " + line)
    if not hidden_ok:
        for n, pk in enumerate(got_packets[:images]):
            if list(pk) != list(exp_hidden[n]):
                print(f"  image {n}: sent {list(pk)[:8]}... expected {list(exp_hidden[n])[:8]}...")
                break


if __name__ == "__main__":
    main()
