"""
gen_vectors.py
Genere des vecteurs de test (aleatoires + cas limites) pour les 3 briques
VHDL de l'etape 2 (mac_unit, relu_requant, argmax), avec les resultats
attendus calcules en Python avec la meme arithmetique entiere que le
materiel devra reproduire.

Usage :
    python3 python/gen_vectors.py
"""

import os

import numpy as np

PROJECT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
VECTORS_DIR = os.path.join(PROJECT_ROOT, "data", "vectors")

N_RANDOM = 1200
SEED = 1234


def write_lines(path, lines):
    with open(path, "w") as f:
        for line in lines:
            f.write(line + "\n")


# ------------------------------------------------------------- mac_unit --

def gen_mac_vectors(rng):
    lines = []
    edge_wx = [(-128, -128), (-128, 127), (127, -128), (127, 127),
               (0, 0), (0, 127), (-128, 0), (1, -1), (-1, 1)]
    edge_bias = [0, 1_000_000, -1_000_000]
    for w, x in edge_wx:
        for bias in edge_bias:
            expected = bias + w * x
            lines.append(f"{w} {x} {bias} {expected}")

    for _ in range(N_RANDOM):
        w = int(rng.integers(-128, 128))
        x = int(rng.integers(-128, 128))
        bias = int(rng.integers(-1_000_000, 1_000_000))
        expected = bias + w * x
        lines.append(f"{w} {x} {bias} {expected}")

    write_lines(os.path.join(VECTORS_DIR, "mac_vectors.txt"), lines)
    print(f"mac_vectors.txt : {len(lines)} vecteurs")


# --------------------------------------------------------- relu_requant --

def relu_requant_ref(acc, m, s):
    val = (acc * m) >> s
    return max(0, min(127, val))


def gen_relu_vectors(rng):
    lines = []
    edge_acc = [0, 1, -1, 2**31 - 1, -(2**31), 12_700_000, -12_700_000]
    edge_m = [0, 1, 32768, 65535]
    edge_s = [0, 15, 27, 31]
    for acc in edge_acc:
        for m in edge_m:
            for s in edge_s:
                expected = relu_requant_ref(acc, m, s)
                lines.append(f"{acc} {m} {s} {expected}")

    for _ in range(N_RANDOM):
        acc = int(rng.integers(-20_000_000, 20_000_000))
        m = int(rng.integers(0, 65536))
        s = int(rng.integers(0, 32))
        expected = relu_requant_ref(acc, m, s)
        lines.append(f"{acc} {m} {s} {expected}")

    write_lines(os.path.join(VECTORS_DIR, "relu_vectors.txt"), lines)
    print(f"relu_vectors.txt : {len(lines)} vecteurs")


# -------------------------------------------------------------- argmax --

def argmax_ref(scores):
    return int(np.argmax(scores))


def gen_argmax_vectors(rng):
    lines = []
    ties = [
        [0] * 10,
        [5] * 10,
        [-1] * 10,
        [100, 100, 99, 98, 97, 96, 95, 94, 93, 92],
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 9],
        [-5, -4, -3, -2, -1, 0, 1, 2, 3, 3],
    ]
    for scores in ties:
        expected = argmax_ref(scores)
        lines.append(" ".join(str(v) for v in scores) + f" {expected}")

    for _ in range(N_RANDOM):
        scores = rng.integers(-2_000_000, 2_000_000, size=10).tolist()
        expected = argmax_ref(scores)
        lines.append(" ".join(str(v) for v in scores) + f" {expected}")

    write_lines(os.path.join(VECTORS_DIR, "argmax_vectors.txt"), lines)
    print(f"argmax_vectors.txt : {len(lines)} vecteurs")


def main():
    os.makedirs(VECTORS_DIR, exist_ok=True)
    rng = np.random.default_rng(SEED)
    gen_mac_vectors(rng)
    gen_relu_vectors(rng)
    gen_argmax_vectors(rng)
    print(f"Vecteurs ecrits dans {VECTORS_DIR}")


if __name__ == "__main__":
    main()
