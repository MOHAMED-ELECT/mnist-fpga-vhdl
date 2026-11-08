"""
gen_vhdl_pkg.py
Genere rtl/weights_pkg.vhd a partir des poids quantifies
(data/weights_int.npz, produit par python/quantize.py).

GENERE AUTOMATIQUEMENT rtl/weights_pkg.vhd : ne pas modifier ce fichier a
la main, relancer ce script a la place.

Usage :
    python3 python/gen_vhdl_pkg.py
"""

import os

import numpy as np

PROJECT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DATA_DIR = os.path.join(PROJECT_ROOT, "data")
OUT_PATH = os.path.join(PROJECT_ROOT, "rtl", "weights_pkg.vhd")


def format_array(values, per_line=16):
    parts = [str(int(v)) for v in values]
    lines = []
    for i in range(0, len(parts), per_line):
        lines.append(", ".join(parts[i:i + per_line]))
    return ",\n    ".join(lines)


def main():
    d = np.load(os.path.join(DATA_DIR, "weights_int.npz"))
    W1_q = d["W1_q"]  # (N_IN, N_HIDDEN)
    b1_q = d["b1_q"]  # (N_HIDDEN,)
    W2_q = d["W2_q"]  # (N_HIDDEN, N_OUT)
    b2_q = d["b2_q"]  # (N_OUT,)
    M1 = int(d["M1"])
    S1 = int(d["S1"])

    n_in, n_hidden = W1_q.shape
    n_hidden2, n_out = W2_q.shape
    assert n_hidden == n_hidden2, "incoherence entre W1 et W2"

    # Aplatissement ligne-major (C order) : flat[i*n_hidden + j] = W[i, j].
    # C'est l'ordre que controller_fsm.vhd suppose pour adresser les ROM.
    w1_flat = W1_q.flatten(order="C")
    w2_flat = W2_q.flatten(order="C")

    with open(OUT_PATH, "w") as f:
        f.write("-- weights_pkg.vhd\n")
        f.write("-- GENERE AUTOMATIQUEMENT par python/gen_vhdl_pkg.py -- ne pas modifier a la main.\n")
        f.write(f"-- Reseau {n_in}-{n_hidden}-{n_out}, genere a partir de data/weights_int.npz\n\n")
        f.write("package weights_pkg is\n\n")

        f.write(f"  constant N_IN     : integer := {n_in};\n")
        f.write(f"  constant N_HIDDEN : integer := {n_hidden};\n")
        f.write(f"  constant N_OUT    : integer := {n_out};\n")
        f.write(f"  constant M1_CONST : integer := {M1};\n")
        f.write(f"  constant S1_CONST : integer := {S1};\n\n")

        f.write(f"  type w1_array_t is array (0 to {n_in * n_hidden - 1}) of integer range -128 to 127;\n")
        f.write(f"  type b1_array_t is array (0 to {n_hidden - 1}) of integer range -2147483648 to 2147483647;\n")
        f.write(f"  type w2_array_t is array (0 to {n_hidden * n_out - 1}) of integer range -128 to 127;\n")
        f.write(f"  type b2_array_t is array (0 to {n_out - 1}) of integer range -2147483648 to 2147483647;\n\n")

        f.write("  -- W1_ROM(i*N_HIDDEN + j) = poids entre l'entree i et le neurone cache j\n")
        f.write(f"  constant W1_ROM : w1_array_t := (\n    {format_array(w1_flat)}\n  );\n\n")

        f.write(f"  constant B1_ROM : b1_array_t := (\n    {format_array(b1_q)}\n  );\n\n")

        f.write("  -- W2_ROM(j*N_OUT + k) = poids entre le neurone cache j et la sortie k\n")
        f.write(f"  constant W2_ROM : w2_array_t := (\n    {format_array(w2_flat)}\n  );\n\n")

        f.write(f"  constant B2_ROM : b2_array_t := (\n    {format_array(b2_q)}\n  );\n\n")

        f.write("end package weights_pkg;\n")

    print(f"Package VHDL genere : {OUT_PATH}")
    print(f"  N_IN={n_in}  N_HIDDEN={n_hidden}  N_OUT={n_out}  M1={M1}  S1={S1}")


if __name__ == "__main__":
    main()
