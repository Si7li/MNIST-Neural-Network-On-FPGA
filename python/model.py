import torch
from torch import nn


class DigitsMLP(nn.Module):
    def __init__(self, n_in=64, n_hidden=32, n_out=10):
        super().__init__()
        self.fc1 = nn.Linear(n_in, n_hidden)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(n_hidden, n_out)

    def forward(self, x):
        h = self.relu(self.fc1(x))
        return self.fc2(h)

    def numpy_params(self):
        W1 = self.fc1.weight.detach().numpy().T
        b1 = self.fc1.bias.detach().numpy()
        W2 = self.fc2.weight.detach().numpy().T
        b2 = self.fc2.bias.detach().numpy()
        return W1, b1, W2, b2
