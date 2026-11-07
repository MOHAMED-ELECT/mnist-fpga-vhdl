"""
golden_model.py
Inference entiere bit-exacte : c'est LA reference que le circuit VHDL devra
reproduire a l'identique (0 ecart). Aucune virgule flottante n'est utilisee
dans ce fichier - uniquement des entiers, comme le fera le materiel.

Usage (auto-test) :
    python3 python/golden_model.py
"""

import os

import numpy as np

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")


def load_quantized(path=None):
    path = path or os.path.join(DATA_DIR, "weights_int.npz")
    d = np.load(path)
    return {
        "W1_q": d["W1_q"].astype(np.int64),
        "b1_q": d["b1_q"].astype(np.int64),
        "M1": int(d["M1"]),
        "S1": int(d["S1"]),
        "W2_q": d["W2_q"].astype(np.int64),
        "b2_q": d["b2_q"].astype(np.int64),
    }


def quantize_image(img_float_0_1):
    """Convertit une image flottante [0,1] (784,) en entiers [0,127], comme
    le fera le testbench avant d'ecrire les pixels dans image_ram."""
    return np.round(np.clip(img_float_0_1, 0, 1) * 127).astype(np.int64)


def infer(x_q, params):
    """x_q : vecteur d'entiers (784,) dans [0,127].
    Renvoie (digit, scores) ou `scores` est un vecteur de 10 entiers, chacun
    tenant sur 32 bits signes en materiel (ici en int64 cote Python, par
    confort, mais les valeurs restent dans la plage 32 bits)."""
    W1_q, b1_q = params["W1_q"], params["b1_q"]
    M1, S1 = params["M1"], params["S1"]
    W2_q, b2_q = params["W2_q"], params["b2_q"]

    # --- couche 1 : MAC (exact en entiers), puis ReLU + remise a l'echelle --
    acc1 = x_q @ W1_q + b1_q                     # int64, aucune perte
    h_q = np.clip((acc1 * M1) >> S1, 0, 127)     # borne basse 0 = ReLU, borne haute 127 = saturation

    # --- couche 2 : MAC, scores gardes en entiers (pas de ReLU/requant) -----
    scores = h_q @ W2_q + b2_q

    digit = int(np.argmax(scores))
    return digit, scores


def main():
    """Auto-test : verifie que l'inference tourne et est deterministe."""
    params = load_quantized()
    rng = np.random.default_rng(0)
    x_q = rng.integers(0, 128, size=784)
    d1, s1 = infer(x_q, params)
    d2, s2 = infer(x_q, params)
    assert d1 == d2 and np.array_equal(s1, s2), \
        "le modele de reference n'est pas deterministe !"
    print(f"Test de determinisme OK. Exemple : chiffre predit = {d1}")
    print(f"Scores : {s1.tolist()}")


if __name__ == "__main__":
    main()
