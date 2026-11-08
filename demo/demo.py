#!/usr/bin/env python3
"""
demo.py -- demo de l'etape 7 : "n'importe qui comprend en 20 secondes".

Choisit une image de test MNIST (au hasard, ou par --index), l'affiche en
ASCII art dans le terminal, l'ecrit dans data/demo_image.hex, lance GHDL
sur tb/tb_demo.vhd (le circuit VHDL reel, via l'interface officielle de
mlp_top_synth), relit le resultat que le testbench a ecrit dans
results/demo_result.txt, et affiche la prediction finale.

Usage :
    python3 demo/demo.py              # image au hasard
    python3 demo/demo.py --index 42   # image precise (0..999)
"""

import argparse
import os
import random
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(REPO_ROOT, "data")
RESULTS_DIR = os.path.join(REPO_ROOT, "results")

IMAGES_HEX = os.path.join(DATA_DIR, "test_images.hex")
GOLDEN_TXT = os.path.join(DATA_DIR, "golden_outputs.txt")
DEMO_IMAGE_HEX = os.path.join(DATA_DIR, "demo_image.hex")
DEMO_RESULT_TXT = os.path.join(RESULTS_DIR, "demo_result.txt")

N_IN = 784
IMG_SIDE = 28
CLK_PERIOD_NS = 10  # doit rester coherent avec CLK_PERIOD dans tb_demo.vhd
FMAX_MHZ = 50.37     # Fmax reelle mesuree a l'etape 6 (results/synth_report.txt)

RAMP = " .:-=+*#%@"  # rampe de 10 niveaux, du plus clair au plus fonce


def banner(text):
    line = "=" * 60
    print(f"\n{line}\n  {text}\n{line}\n")


def count_test_images():
    with open(IMAGES_HEX) as f:
        n_lines = sum(1 for _ in f)
    return n_lines // N_IN


def load_image_pixels(index):
    """Relit les 784 lignes hexadecimales de l'image `index` directement
    dans data/test_images.hex (ecrit par python/export_hex.py a l'etape 1),
    sans dependre d'un rechargement de MNIST."""
    with open(IMAGES_HEX) as f:
        lines = f.readlines()
    start = index * N_IN
    chunk = lines[start:start + N_IN]
    if len(chunk) != N_IN:
        raise ValueError(
            f"Image #{index} introuvable dans {IMAGES_HEX} "
            f"({count_test_images()} images disponibles)."
        )
    return [int(line.strip(), 16) for line in chunk]


def load_label(index):
    """Relit le label reel (2e colonne) depuis data/golden_outputs.txt."""
    with open(GOLDEN_TXT) as f:
        next(f)  # en-tete
        for line in f:
            fields = line.split()
            if int(fields[0]) == index:
                return int(fields[1])
    return None


def render_ascii(pixels):
    rows = []
    for r in range(IMG_SIDE):
        row_chars = []
        for c in range(IMG_SIDE):
            v = pixels[r * IMG_SIDE + c]
            level = min(len(RAMP) - 1, v * len(RAMP) // 128)
            row_chars.append(RAMP[level] * 2)  # double largeur (police non carree)
        rows.append("".join(row_chars))
    return "\n".join("  " + row for row in rows)


def write_demo_image_hex(pixels):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(DEMO_IMAGE_HEX, "w") as f:
        for v in pixels:
            f.write(f"{v & 0xff:02x}\n")


def run_ghdl():
    """Compile et simule tb_demo.vhd (meme circuit que la synthese :
    mlp_top_synth). Equivalent independant des cibles du Makefile, pour
    que la demo reste une commande unique et autonome."""
    os.makedirs(os.path.join(REPO_ROOT, "work"), exist_ok=True)
    os.makedirs(RESULTS_DIR, exist_ok=True)

    rtl_files = [
        "rtl/weights_pkg.vhd", "rtl/mac_unit.vhd", "rtl/relu_requant.vhd",
        "rtl/argmax.vhd", "rtl/image_ram.vhd", "rtl/act_ram.vhd",
        "rtl/weight_rom.vhd", "rtl/controller_fsm.vhd", "rtl/layer_engine.vhd",
        "rtl/mlp_top.vhd", "rtl/mlp_top_synth.vhd", "tb/tb_demo.vhd",
    ]

    def run(cmd):
        result = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
        if result.returncode != 0:
            sys.stderr.write(result.stdout)
            sys.stderr.write(result.stderr)
            raise RuntimeError(f"Echec de la commande : {' '.join(cmd)}")

    print("Compilation du circuit VHDL (GHDL)...")
    run(["ghdl", "-a", "--std=08", "--workdir=work"] + rtl_files)
    run(["ghdl", "-e", "--std=08", "--workdir=work", "tb_demo"])

    print("Simulation de l'inference...")
    run(["ghdl", "-r", "--std=08", "--workdir=work", "tb_demo"])


def read_result():
    with open(DEMO_RESULT_TXT) as f:
        digit_str, cycles_str = f.read().split()
    return int(digit_str), int(cycles_str)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--index", type=int, default=None,
                         help="indice de l'image de test a utiliser (0..N-1). "
                              "Par defaut : une image au hasard.")
    args = parser.parse_args()

    banner("Reconnaissance de chiffres manuscrits -- accelerateur VHDL")

    n_available = count_test_images()
    index = args.index if args.index is not None else random.randrange(n_available)
    print(f"Image de test choisie : #{index} / {n_available}")

    pixels = load_image_pixels(index)
    label = load_label(index)

    print(f"\nChiffre reel (label MNIST) : {label}\n")
    print(render_ascii(pixels))

    write_demo_image_hex(pixels)
    print(f"\nImage ecrite dans {os.path.relpath(DEMO_IMAGE_HEX, REPO_ROOT)}")

    try:
        run_ghdl()
    except FileNotFoundError:
        print("\nErreur : la commande 'ghdl' est introuvable. "
              "Installe GHDL (voir README.md) puis relance la demo.")
        sys.exit(1)
    except RuntimeError as e:
        print(f"\nErreur pendant la simulation : {e}")
        sys.exit(1)

    digit, cycles = read_result()
    latency_us = cycles / FMAX_MHZ

    banner("Resultat")
    verdict = "CORRECT" if digit == label else "DIFFERENT du label attendu"
    print(f"  >>> Prediction du circuit : {digit}")
    print(f"      en {cycles:,} cycles d'horloge".replace(",", " "))
    print(f"      soit ~{latency_us:.1f} us a {FMAX_MHZ} MHz "
          f"(Fmax reelle mesuree a l'etape 6)")
    print(f"      chiffre reel attendu : {label}  ->  {verdict}\n")


if __name__ == "__main__":
    main()
