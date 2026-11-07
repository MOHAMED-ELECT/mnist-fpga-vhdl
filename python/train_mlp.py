"""
train_mlp.py
Entraine un MLP 784-32-10 sur MNIST, en NumPy pur (aucune dependance a
PyTorch necessaire). Sauvegarde les poids flottants dans
data/weights_float.npz, consommes ensuite par quantize.py.

Usage :
    python3 python/train_mlp.py
"""

import gzip
import os
import urllib.request

import numpy as np

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
RAW_DIR = os.path.join(DATA_DIR, "mnist_raw")

# Miroirs essayes dans l'ordre (le premier est celui utilise par torchvision
# depuis que le site original de Yann LeCun est moins fiable).
MIRRORS = [
    "https://ossci-datasets.s3.amazonaws.com/mnist/",
    "http://yann.lecun.com/exdb/mnist/",
]

FILES = {
    "train_images": "train-images-idx3-ubyte.gz",
    "train_labels": "train-labels-idx1-ubyte.gz",
    "test_images": "t10k-images-idx3-ubyte.gz",
    "test_labels": "t10k-labels-idx1-ubyte.gz",
}


# --------------------------------------------------------------- donnees --

def _download(fname):
    path = os.path.join(RAW_DIR, fname)
    if os.path.exists(path):
        return path
    os.makedirs(RAW_DIR, exist_ok=True)
    last_err = None
    for mirror in MIRRORS:
        url = mirror + fname
        try:
            print(f"Telechargement de {url} ...")
            urllib.request.urlretrieve(url, path)
            return path
        except Exception as e:  # noqa: BLE001
            last_err = e
            print(f"  echec ({e}), on essaie le miroir suivant.")
    raise RuntimeError(f"Impossible de telecharger {fname} : {last_err}")


def _read_idx_images(path):
    with gzip.open(path, "rb") as f:
        magic = int.from_bytes(f.read(4), "big")
        assert magic == 2051, f"magic number inattendu: {magic}"
        n = int.from_bytes(f.read(4), "big")
        rows = int.from_bytes(f.read(4), "big")
        cols = int.from_bytes(f.read(4), "big")
        data = np.frombuffer(f.read(), dtype=np.uint8)
        return data.reshape(n, rows * cols)


def _read_idx_labels(path):
    with gzip.open(path, "rb") as f:
        magic = int.from_bytes(f.read(4), "big")
        assert magic == 2049, f"magic number inattendu: {magic}"
        _n = int.from_bytes(f.read(4), "big")
        return np.frombuffer(f.read(), dtype=np.uint8)


def load_mnist():
    """Renvoie (x_train, y_train, x_test, y_test). Images en float32 [0,1],
    forme (N, 784). Labels en int64, forme (N,)."""
    paths = {k: _download(v) for k, v in FILES.items()}
    x_train = _read_idx_images(paths["train_images"]).astype(np.float32) / 255.0
    y_train = _read_idx_labels(paths["train_labels"]).astype(np.int64)
    x_test = _read_idx_images(paths["test_images"]).astype(np.float32) / 255.0
    y_test = _read_idx_labels(paths["test_labels"]).astype(np.int64)
    return x_train, y_train, x_test, y_test


# ----------------------------------------------------------------- reseau --

def relu(z):
    return np.maximum(z, 0.0)


def softmax(z):
    z = z - z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)


def forward(x, W1, b1, W2, b2):
    h = relu(x @ W1 + b1)
    scores = h @ W2 + b2
    return h, scores


def accuracy(x, y, W1, b1, W2, b2):
    _, scores = forward(x, W1, b1, W2, b2)
    preds = scores.argmax(axis=1)
    return float((preds == y).mean())


def train(x_train, y_train, x_test, y_test, hidden=32, epochs=15,
          batch_size=128, lr=0.1, seed=0):
    rng = np.random.default_rng(seed)
    n_in, n_hidden, n_out = x_train.shape[1], hidden, 10

    # Initialisation He, adaptee aux couches ReLU.
    W1 = rng.normal(0, np.sqrt(2.0 / n_in), size=(n_in, n_hidden)).astype(np.float32)
    b1 = np.zeros(n_hidden, dtype=np.float32)
    W2 = rng.normal(0, np.sqrt(2.0 / n_hidden), size=(n_hidden, n_out)).astype(np.float32)
    b2 = np.zeros(n_out, dtype=np.float32)

    n = x_train.shape[0]
    y_onehot = np.eye(n_out, dtype=np.float32)[y_train]

    for epoch in range(1, epochs + 1):
        perm = rng.permutation(n)
        for start in range(0, n, batch_size):
            idx = perm[start:start + batch_size]
            xb, yb = x_train[idx], y_onehot[idx]

            # forward
            z1 = xb @ W1 + b1
            h = relu(z1)
            z2 = h @ W2 + b2
            p = softmax(z2)

            # backward (cross-entropy + softmax combinees)
            m = xb.shape[0]
            dz2 = (p - yb) / m
            dW2 = h.T @ dz2
            db2 = dz2.sum(axis=0)

            dh = dz2 @ W2.T
            dz1 = dh * (z1 > 0)
            dW1 = xb.T @ dz1
            db1 = dz1.sum(axis=0)

            W2 -= lr * dW2
            b2 -= lr * db2
            W1 -= lr * dW1
            b1 -= lr * db1

        train_acc = accuracy(x_train, y_train, W1, b1, W2, b2)
        test_acc = accuracy(x_test, y_test, W1, b1, W2, b2)
        print(f"epoch {epoch:2d}/{epochs}  train={train_acc*100:5.2f}%  test={test_acc*100:5.2f}%")

    return W1, b1, W2, b2


def main():
    print("Chargement de MNIST (telechargement au premier lancement)...")
    x_train, y_train, x_test, y_test = load_mnist()
    print(f"  train: {x_train.shape}, test: {x_test.shape}")

    W1, b1, W2, b2 = train(x_train, y_train, x_test, y_test)

    final_acc = accuracy(x_test, y_test, W1, b1, W2, b2)
    print(f"\nPrecision finale (flottant) sur le test set : {final_acc*100:.2f}%")

    os.makedirs(DATA_DIR, exist_ok=True)
    out_path = os.path.join(DATA_DIR, "weights_float.npz")
    np.savez(out_path, W1=W1, b1=b1, W2=W2, b2=b2, test_accuracy=final_acc)
    print(f"Poids sauvegardes dans {out_path}")


if __name__ == "__main__":
    main()
