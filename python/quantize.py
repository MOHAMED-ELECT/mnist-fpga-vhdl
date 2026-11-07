"""
quantize.py
Quantifie le MLP entraine (data/weights_float.npz) en INT8 symetrique par
couche, calcule le multiplicateur entier (M1, S1) qui remet a l'echelle la
couche 1 apres le ReLU, et sauvegarde le tout dans data/weights_int.npz.

C'est ici que se fige la regle d'arrondi/decalage que le circuit VHDL devra
reproduire a l'identique (voir le piege de l'etape 1 dans le plan).

Usage :
    python3 python/quantize.py
"""

import os

import numpy as np

from train_mlp import load_mnist, relu

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")

N_CALIB = 2000  # images utilisees pour estimer l'amplitude de la couche cachee


def quantize_multiplier(real_multiplier, mult_bits=16, max_shift=31):
    """Approxime real_multiplier (float > 0) par M / 2**S, avec M un entier
    tenant sur `mult_bits` bits non signes. On choisit le plus grand S
    possible : c'est celui qui donne le plus de precision."""
    assert real_multiplier > 0, "le multiplicateur doit etre strictement positif"
    max_M = (1 << mult_bits) - 1
    for S in range(max_shift, -1, -1):
        M = round(real_multiplier * (1 << S))
        if 0 < M <= max_M:
            return M, S
    raise ValueError(f"impossible de representer le multiplicateur {real_multiplier}")


def quantize_weights(W, n_bits=8):
    """Quantification symetrique par couche. Renvoie (W_q int8, scale float)."""
    max_abs = np.abs(W).max()
    qmax = (1 << (n_bits - 1)) - 1  # 127 pour 8 bits
    scale = max_abs / qmax if max_abs > 0 else 1.0
    W_q = np.round(W / scale).clip(-qmax, qmax).astype(np.int8)
    return W_q, scale


def main():
    float_path = os.path.join(DATA_DIR, "weights_float.npz")
    d = np.load(float_path)
    W1, b1, W2, b2 = d["W1"], d["b1"], d["W2"], d["b2"]

    # --- echelle des entrees ---------------------------------------------
    # Les pixels sont normalises en [0,1] cote Python puis convertis en
    # entiers [0,127] avant d'entrer dans le circuit (voir image_ram).
    s_x = 1.0 / 127.0

    # --- couche 1 : poids et biais ----------------------------------------
    W1_q, s_w1 = quantize_weights(W1)
    b1_q = np.round(b1 / (s_x * s_w1)).astype(np.int32)

    # --- calibration : amplitude des activations cachees -------------------
    # On estime s_h (echelle de la couche cachee) a partir d'un passage
    # flottant sur des images de calibration (issues du jeu d'entrainement).
    print("Chargement de MNIST pour la calibration...")
    x_train, _y_train, _x_test, _y_test = load_mnist()
    calib = x_train[:N_CALIB]
    h_float = relu(calib @ W1 + b1)
    max_h = float(h_float.max())
    s_h = max_h / 127.0 if max_h > 0 else 1.0

    real_mult1 = (s_x * s_w1) / s_h
    M1, S1 = quantize_multiplier(real_mult1)

    # --- couche 2 : poids et biais (scores gardes en 32 bits, pas de ReLU) -
    W2_q, s_w2 = quantize_weights(W2)
    b2_q = np.round(b2 / (s_h * s_w2)).astype(np.int32)

    out_path = os.path.join(DATA_DIR, "weights_int.npz")
    np.savez(
        out_path,
        W1_q=W1_q, b1_q=b1_q, M1=np.int64(M1), S1=np.int64(S1),
        W2_q=W2_q, b2_q=b2_q,
        s_x=s_x, s_w1=s_w1, s_h=s_h, s_w2=s_w2,
    )

    print(f"s_x={s_x:.6f}  s_w1={s_w1:.6f}  s_h={s_h:.6f}  s_w2={s_w2:.6f}")
    print(f"M1={M1}  S1={S1}  "
          f"(multiplicateur approxime {M1/2**S1:.6f} vs reel {real_mult1:.6f})")
    print(f"Poids quantifies sauvegardes dans {out_path}")


if __name__ == "__main__":
    main()
