"""
export_hex.py
Exporte les poids quantifies et un jeu d'images de test en fichiers texte
hexadecimaux dans data/. Ces fichiers seront consommes par gen_vhdl_pkg.py
(etape 3, qui generera rtl/weights_pkg.vhd) et par le testbench
tb_mlp_top.vhd (etape 4).

Usage :
    python3 python/export_hex.py
"""

import os

import numpy as np

from train_mlp import load_mnist
from golden_model import load_quantized, quantize_image, infer

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")

N_TEST_IMAGES = 1000


def write_hex(path, values, hex_digits):
    """Ecrit une valeur entiere signee par ligne, en complement a deux sur
    `hex_digits` chiffres hexadecimaux (8 bits -> 2 chiffres, 32 bits -> 8)."""
    mask = (1 << (hex_digits * 4)) - 1
    with open(path, "w") as f:
        for v in values:
            f.write(f"{int(v) & mask:0{hex_digits}x}\n")


def main():
    params = load_quantized()

    os.makedirs(DATA_DIR, exist_ok=True)
    write_hex(os.path.join(DATA_DIR, "w1.hex"), params["W1_q"].flatten(order="C"), 2)
    write_hex(os.path.join(DATA_DIR, "b1.hex"), params["b1_q"], 8)
    write_hex(os.path.join(DATA_DIR, "w2.hex"), params["W2_q"].flatten(order="C"), 2)
    write_hex(os.path.join(DATA_DIR, "b2.hex"), params["b2_q"], 8)
    print("Poids exportes : data/w1.hex, data/b1.hex, data/w2.hex, data/b2.hex")
    print(f"  M1={params['M1']}  S1={params['S1']}  "
          f"(a reporter dans le package VHDL a l'etape 3)")

    # --- images de test + sorties de reference ----------------------------
    print(f"Chargement de MNIST pour exporter {N_TEST_IMAGES} images de test...")
    _x_train, _y_train, x_test, y_test = load_mnist()
    x_test, y_test = x_test[:N_TEST_IMAGES], y_test[:N_TEST_IMAGES]

    images_path = os.path.join(DATA_DIR, "test_images.hex")
    outputs_path = os.path.join(DATA_DIR, "golden_outputs.txt")

    n_correct = 0
    with open(images_path, "w") as fimg, open(outputs_path, "w") as fout:
        fout.write("# image_index label predicted score0 score1 ... score9\n")
        for i in range(N_TEST_IMAGES):
            x_q = quantize_image(x_test[i])
            for v in x_q:
                fimg.write(f"{int(v):02x}\n")

            digit, scores = infer(x_q, params)
            if digit == y_test[i]:
                n_correct += 1
            scores_str = " ".join(str(int(s)) for s in scores)
            fout.write(f"{i} {int(y_test[i])} {digit} {scores_str}\n")

    accuracy_int8 = n_correct / N_TEST_IMAGES
    print(f"Precision INT8 (modele de reference) sur {N_TEST_IMAGES} images : "
          f"{accuracy_int8*100:.2f}%")
    print(f"Images exportees : {images_path}")
    print(f"Sorties de reference exportees : {outputs_path}")


if __name__ == "__main__":
    main()
