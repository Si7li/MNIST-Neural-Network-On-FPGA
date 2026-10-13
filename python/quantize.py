import numpy as np

from data import PIXEL_MAX

INPUT_SHIFT = 4
HIDDEN_MAX = 255


def signed_bits(lo, hi):
    n = 1
    while not (-(2 ** (n - 1)) <= lo and hi <= 2 ** (n - 1) - 1):
        n += 1
    return n


def frac_bits_for(w):
    n = 0
    while np.max(np.abs(np.round(w * 2 ** (n + 1)))) <= 127:
        n += 1
    while np.max(np.abs(np.round(w * 2 ** n))) > 127:
        n -= 1
    return n


def quantize(W1, b1, W2, b2, n1, n2, s1):
    w1q = np.clip(np.round(W1 * 2 ** n1), -128, 127).astype(np.int64)
    b1q = np.round(b1 * 2 ** (n1 + INPUT_SHIFT)).astype(np.int64)
    w2q = np.clip(np.round(W2 * 2 ** n2), -128, 127).astype(np.int64)
    b2q = np.round(b2 * 2.0 ** (n2 + n1 + INPUT_SHIFT - s1)).astype(np.int64)
    return w1q, b1q, w2q, b2q


def hw_forward(x, w1q, b1q, w2q, b2q, s1):
    acc1 = x @ w1q + b1q
    h = np.minimum(np.maximum(acc1, 0) >> s1, HIDDEN_MAX)
    acc2 = h @ w2q + b2q
    pred = np.argmax(acc2, axis=1)
    return acc1, h, acc2, pred


def choose_shift(X, y, W1, b1, W2, b2, n1, n2):
    rows = []
    for s1 in range(0, 21):
        q = quantize(W1, b1, W2, b2, n1, n2, s1)
        acc1, _, _, pred = hw_forward(X, *q, s1)
        sat = np.mean(np.maximum(acc1, 0) >> s1 > HIDDEN_MAX)
        rows.append((s1, np.mean(pred == y), sat))
    best = max(rows, key=lambda r: (r[1], -r[2], -r[0]))
    return best[0], rows


def hardware_widths(w1q, b1q, w2q, b2q):
    acc1_hi = (np.maximum(w1q, 0).sum(0) * PIXEL_MAX + b1q).max()
    acc1_lo = (np.minimum(w1q, 0).sum(0) * PIXEL_MAX + b1q).min()
    acc2_hi = (np.maximum(w2q, 0).sum(0) * HIDDEN_MAX + b2q).max()
    acc2_lo = (np.minimum(w2q, 0).sum(0) * HIDDEN_MAX + b2q).min()
    return {
        "product1_bits": signed_bits(-128 * PIXEL_MAX, 127 * PIXEL_MAX),
        "bias1_bits": signed_bits(b1q.min(), b1q.max()),
        "acc1_bits_worst_case": signed_bits(acc1_lo, acc1_hi),
        "product2_bits": signed_bits(-128 * HIDDEN_MAX, 127 * HIDDEN_MAX),
        "bias2_bits": signed_bits(b2q.min(), b2q.max()),
        "acc2_bits_worst_case": signed_bits(acc2_lo, acc2_hi),
    }
