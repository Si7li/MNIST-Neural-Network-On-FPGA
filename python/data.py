import numpy as np
import torch
from sklearn.datasets import load_digits
from sklearn.model_selection import train_test_split

PIXEL_MAX = 15
INPUT_SCALE = 16


def load_data(seed, test_size=0.2):
    digits = load_digits()
    X = np.minimum(digits.data, PIXEL_MAX).astype(np.int64)
    y = digits.target
    X_tr, X_te, y_tr, y_te, _, idx_te = train_test_split(
        X, y, np.arange(len(y)),
        test_size=test_size, stratify=y, random_state=seed,
    )
    return X_tr, X_te, y_tr, y_te, idx_te


def to_tensor(X):
    return torch.tensor(X / INPUT_SCALE, dtype=torch.float32)
