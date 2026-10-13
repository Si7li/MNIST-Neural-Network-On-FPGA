import re
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).parent.parent
RESULTS = ROOT / "sim" / "results.lst"
PARAMS = Path(__file__).parent / "out" / "quant_params.npz"
HIDDEN_W = 8


def read_list(path):
    names, rows = [], []
    for line in path.read_text().splitlines():
        parts = line.split()
        if parts and parts[0].isdigit() and len(parts) > 1 and parts[1].startswith("+"):
            rows.append(parts[2:])
        elif not rows:
            names += [(m.start(), m.group()) for m in re.finditer(r"/\S+", line)]
    return [name.split("/")[-1] for _, name in sorted(names)], rows


def hidden_values(hex_text, n_hidden):
    v = int(hex_text, 16)
    return [(v >> (HIDDEN_W * j)) & (2 ** HIDDEN_W - 1) for j in range(n_hidden)]


def main():
    results = Path(sys.argv[1]) if len(sys.argv) > 1 else RESULTS
    if not results.exists():
        sys.exit(f"{results} not found: run the ModelSim .do script first")

    p = np.load(PARAMS)
    expected, labels = p["expected_pred"], p["y_test"]
    exp_hidden, exp_scores = p["expected_hidden"], p["expected_acc2"]
    n_images, n_hidden = exp_hidden.shape
    names, rows = read_list(results)
    col = {name: c for c, name in enumerate(names)}

    vhdl, hid_err, score_err, checked_internal = {}, [], [], []
    for row in rows:
        n = int(row[col["image_no"]])
        if not 0 <= n < n_images:
            continue
        vhdl[n] = int(row[col["digit"]])
        bad_hid = bad_score = False
        if "hid" in col:
            bad_hid = hidden_values(row[col["hid"]], n_hidden) != list(exp_hidden[n])
        if "acc(0)" in col:
            got = [int(row[col[f"acc({k})"]]) for k in range(exp_scores.shape[1])]
            bad_score = got != list(exp_scores[n])
        if "best" in col:
            bad_score = int(row[col["best"]]) != exp_scores[n].max()
        if "hid" in col or "acc(0)" in col or "best" in col:
            checked_internal.append(n)
        if bad_hid:
            hid_err.append(n)
        if bad_score:
            score_err.append(n)

    missing = [n for n in range(n_images) if n not in vhdl]
    if missing:
        print(f"WARNING: {len(missing)} images missing from the results "
              f"(first: {missing[:5]}). Did the simulation run long enough?")

    checked = [n for n in range(n_images) if n in vhdl]
    differ = [n for n in checked if vhdl[n] != expected[n]]
    correct = [n for n in checked if vhdl[n] == labels[n]]
    wrong = [n for n in checked if vhdl[n] != labels[n]]
    python_correct = int(np.sum(expected == labels))

    print(f"Images checked:          {len(checked)} / {n_images}")
    print(f"VHDL matches Python:     {len(checked) - len(differ)} / {len(checked)}")
    if checked_internal:
        what = []
        if "hid" in col:
            what.append(f"hidden values {len(checked_internal) - len(hid_err)}")
        if "acc(0)" in col or "best" in col:
            what.append(f"scores {len(checked_internal) - len(score_err)}")
        print(f"Internal values match:   {' / '.join(what)}  (of {len(checked_internal)} images)")
    print(f"VHDL accuracy:           {len(correct)} / {len(checked)}"
          f" = {len(correct) / len(checked):.2%}")
    print(f"Python accuracy:         {python_correct} / {n_images}"
          f" = {python_correct / n_images:.2%}")

    if differ:
        print("\nImages where VHDL and Python DISAGREE (image: python -> vhdl):")
        print("  " + ", ".join(f"{n}: {expected[n]}->{vhdl[n]}" for n in differ))
    if hid_err or score_err:
        print(f"\nInternal mismatches: hidden values on images {hid_err[:10]}, "
              f"scores on images {score_err[:10]}")

    print("\nNetwork mistakes (image: true label -> predicted):")
    print("  " + ", ".join(f"{n}: {labels[n]}->{vhdl[n]}" for n in wrong))


if __name__ == "__main__":
    main()
