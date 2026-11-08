"""
export_layer1_ref.py
Calcule les 32 activations cachees de reference (couche 1 seule) pour les
10 premieres images de test (deja exportees dans data/test_images.hex par
export_hex.py), via le modele de reference. Sert a valider layer_engine.vhd
independamment du reste du reseau (etape 3, tb_layer1.vhd).

Usage :
    python3 python/export_layer1_ref.py
"""

import os

from golden_model import load_quantized, quantize_image, infer_with_hidden
from train_mlp import load_mnist

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
N_IMAGES = 10


def main():
    params = load_quantized()
    _x_train, _y_train, x_test, _y_test = load_mnist()

    out_path = os.path.join(DATA_DIR, "layer1_golden_h.txt")
    with open(out_path, "w") as f:
        for i in range(N_IMAGES):
            x_q = quantize_image(x_test[i])
            h_q, _digit, _scores = infer_with_hidden(x_q, params)
            for v in h_q:
                f.write(f"{int(v)}\n")

    print(f"Reference couche 1 ({N_IMAGES} images x 32 activations) "
          f"exportee dans {out_path}")


if __name__ == "__main__":
    main()
