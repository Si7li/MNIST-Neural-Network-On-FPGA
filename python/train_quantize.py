import json
from pathlib import Path

import numpy as np
import torch

from data import load_data
from model import DigitsMLP
from quantize import (choose_shift, frac_bits_for, hardware_widths,
                      hw_forward, quantize, signed_bits)
from train import TrainConfig, predict, train

SEED = 0
OUT_DIR = Path(__file__).parent / "out"


def main():
    OUT_DIR.mkdir(exist_ok=True)
    torch.manual_seed(SEED)

    X_tr, X_te, y_tr, y_te, idx_te = load_data(seed=SEED)
    print(f"Data: {len(y_tr)} training images, {len(y_te)} test images")

    model = DigitsMLP()
    print("Training:")
    train(model, X_tr, y_tr, TrainConfig(seed=SEED))
    float_pred = predict(model, X_te)
    float_acc = np.mean(float_pred == y_te)
    W1, b1, W2, b2 = model.numpy_params()

    n1, n2 = frac_bits_for(W1), frac_bits_for(W2)
    s1, shift_table = choose_shift(X_tr, y_tr, W1, b1, W2, b2, n1, n2)
    w1q, b1q, w2q, b2q = quantize(W1, b1, W2, b2, n1, n2, s1)

    acc1, h, acc2, q_pred = hw_forward(X_te, w1q, b1q, w2q, b2q, s1)
    q_acc = np.mean(q_pred == y_te)
    agree = np.mean(q_pred == float_pred)
    top2 = np.sort(acc2, axis=1)[:, -2:]
    ties = int(np.sum(top2[:, 0] == top2[:, 1]))

    s1_q17, _ = choose_shift(X_tr, y_tr, W1, b1, W2, b2, 7, 7)
    _, _, _, p17 = hw_forward(X_te, *quantize(W1, b1, W2, b2, 7, 7, s1_q17),
                              s1_q17)
    acc_q17 = np.mean(p17 == y_te)
    clipped_q17 = int(np.sum(np.abs(np.round(W1 * 128)) > 127)
                      + np.sum(np.abs(np.round(W2 * 128)) > 127))

    widths = hardware_widths(w1q, b1q, w2q, b2q)
    X_all = np.concatenate([X_tr, X_te])
    acc1_all, h_all, acc2_all, _ = hw_forward(X_all, w1q, b1q, w2q, b2q, s1)

    summary = {
        "float_test_accuracy": float(float_acc),
        "quantized_test_accuracy": float(q_acc),
        "quantized_vs_float_agreement": float(agree),
        "forced_Q1.7_accuracy": float(acc_q17),
        "forced_Q1.7_clipped_weights": clipped_q17,
        "max_abs_W1": float(np.abs(W1).max()),
        "max_abs_W2": float(np.abs(W2).max()),
        "N1": n1, "W1_format": f"Q{8 - n1}.{n1}",
        "N2": n2, "W2_format": f"Q{8 - n2}.{n2}",
        "S1": s1,
        **widths,
        "acc1_bits_dataset": signed_bits(acc1_all.min(), acc1_all.max()),
        "acc2_bits_dataset": signed_bits(acc2_all.min(), acc2_all.max()),
        "hidden_saturated_fraction": float(np.mean(
            np.maximum(acc1_all, 0) >> s1 > 255)),
        "hidden_max_value": int(h_all.max()),
        "test_images": int(len(y_te)),
        "test_ties_in_argmax": ties,
    }

    print()
    print(f"Float accuracy (test, {len(y_te)} images): {float_acc:.2%}")
    print(f"Quantized accuracy (bit-exact model):     {q_acc:.2%}")
    print(f"Quantized agrees with float on:           {agree:.2%}")
    print(f"  with forced Q1.7 weights:               {acc_q17:.2%}"
          f"  ({clipped_q17} weights clipped)")
    print()
    print(f"max |W1| = {np.abs(W1).max():.3f} -> {summary['W1_format']}")
    print(f"max |W2| = {np.abs(W2).max():.3f} -> {summary['W2_format']}")
    print(f"Layer-1 shift S1 = {s1}")
    print()
    print("Layer-1 shift vs training accuracy / hidden saturation:")
    for s, a, sat in shift_table:
        mark = "  <- chosen" if s == s1 else ""
        print(f"  S1={s:2d}  acc={a:.2%}  saturated={sat:.2%}{mark}")
    print()
    print("Widths (bits, signed):")
    for k in ["product1_bits", "bias1_bits", "acc1_bits_worst_case",
              "acc1_bits_dataset", "product2_bits", "bias2_bits",
              "acc2_bits_worst_case", "acc2_bits_dataset"]:
        print(f"  {k:24s} {summary[k]}")
    print(f"  hidden max value         {summary['hidden_max_value']}"
          f" (saturated {summary['hidden_saturated_fraction']:.2%})")
    print(f"  argmax ties on test set  {ties}")

    torch.save(model.state_dict(), OUT_DIR / "model.pt")
    np.savez(
        OUT_DIR / "quant_params.npz",
        w1q=w1q, b1q=b1q, w2q=w2q, b2q=b2q, n1=n1, n2=n2, s1=s1,
        X_test=X_te, y_test=y_te, idx_test=idx_te,
        expected_pred=q_pred, expected_hidden=h, expected_acc2=acc2,
    )
    (OUT_DIR / "summary.json").write_text(json.dumps(summary, indent=2))
    print(f"\nSaved model.pt, quant_params.npz and summary.json in {OUT_DIR}")


if __name__ == "__main__":
    main()
