from dataclasses import dataclass

import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader, TensorDataset

from data import to_tensor


@dataclass
class TrainConfig:
    epochs: int = 200
    batch_size: int = 64
    lr: float = 1e-3
    weight_decay: float = 1e-4
    seed: int = 0
    log_every: int = 25


def train(model, X, y, cfg):
    dataset = TensorDataset(to_tensor(X), torch.tensor(y, dtype=torch.long))
    loader = DataLoader(dataset, batch_size=cfg.batch_size, shuffle=True,
                        generator=torch.Generator().manual_seed(cfg.seed))

    loss_fn = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=cfg.lr,
                                 weight_decay=cfg.weight_decay)

    for epoch in range(1, cfg.epochs + 1):
        model.train()
        total_loss = 0.0
        for xb, yb in loader:
            optimizer.zero_grad()
            scores = model(xb)
            loss = loss_fn(scores, yb)
            loss.backward()
            optimizer.step()
            total_loss += loss.item() * len(xb)

        if epoch == 1 or epoch % cfg.log_every == 0:
            acc = np.mean(predict(model, X) == y)
            print(f"  epoch {epoch:3d}  loss={total_loss / len(X):.4f}"
                  f"  train acc={acc:.2%}")


def predict(model, X):
    model.eval()
    with torch.no_grad():
        return model(to_tensor(X)).argmax(dim=1).numpy()
