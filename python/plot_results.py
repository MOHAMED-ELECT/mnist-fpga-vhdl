"""
plot_results.py
Trace les graphiques de l'etape 5 (parallelisme) a partir de
results/results.csv (ecrit par scripts/run_sweep.sh) : cycles par image et
latence a 100 MHz en fonction de N_MAC, en echelles logarithmiques (meme
presentation que la Figure 7 du plan), avec la courbe theorique
[ceil(32/N)*784 + ceil(10/N)*32] en comparaison.

Usage :
    python3 python/plot_results.py
Genere : results/cycles_vs_n_mac.png (a inserer dans le README).
"""

import csv
import os

import matplotlib.pyplot as plt

PROJECT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RESULTS_CSV = os.path.join(PROJECT_ROOT, "results", "results.csv")
OUT_PNG = os.path.join(PROJECT_ROOT, "results", "cycles_vs_n_mac.png")

N_IN_L1, N_HIDDEN_L1, N_OUT_L2 = 784, 32, 10


def theoretical_cycles(n_mac):
    """Estimation theorique de la Figure 7 du plan : sans latence de
    pipeline ni de memoire, juste le compte pur de cycles MAC."""
    import math
    return (math.ceil(N_HIDDEN_L1 / n_mac) * N_IN_L1 +
            math.ceil(N_OUT_L2 / n_mac) * N_HIDDEN_L1)


def main():
    if not os.path.exists(RESULTS_CSV):
        raise SystemExit(
            f"{RESULTS_CSV} introuvable. Lance d'abord scripts/run_sweep.sh.")

    n_values, cycles, latences = [], [], []
    with open(RESULTS_CSV) as f:
        reader = csv.DictReader(f)
        for row in reader:
            n_values.append(int(row["N"]))
            cycles.append(int(row["cycles"]))
            latences.append(float(row["latence_us_100MHz"]))

    theo = [theoretical_cycles(n) for n in n_values]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.5))

    ax1.plot(n_values, cycles, "o-", color="#1f6feb", label="simulation (mesure)")
    ax1.plot(n_values, theo, "o--", color="#8b949e", label="estimation theorique (Fig. 7)")
    ax1.set_xscale("log", base=2)
    ax1.set_yscale("log")
    ax1.set_xlabel("nombre N de MAC en parallele")
    ax1.set_ylabel("cycles d'horloge par image")
    ax1.set_title("Cycles par image (echelles logarithmiques)")
    ax1.set_xticks(n_values)
    ax1.set_xticklabels([str(n) for n in n_values])
    ax1.grid(True, which="both", alpha=0.3)
    ax1.legend()
    for n, c in zip(n_values, cycles):
        ax1.annotate(f"{c}", (n, c), textcoords="offset points",
                     xytext=(0, 8), ha="center", fontsize=8)

    ax2.plot(n_values, latences, "o-", color="#da3633")
    ax2.set_xscale("log", base=2)
    ax2.set_yscale("log")
    ax2.set_xlabel("nombre N de MAC en parallele")
    ax2.set_ylabel("latence par image (us, a 100 MHz)")
    ax2.set_title("Latence par image")
    ax2.set_xticks(n_values)
    ax2.set_xticklabels([str(n) for n in n_values])
    ax2.grid(True, which="both", alpha=0.3)
    for n, l in zip(n_values, latences):
        ax2.annotate(f"{l:.1f}", (n, l), textcoords="offset points",
                     xytext=(0, 8), ha="center", fontsize=8)

    fig.suptitle("Etape 5 : compromis vitesse / parallelisme (N unites MAC)")
    fig.tight_layout()
    fig.savefig(OUT_PNG, dpi=150)
    print(f"Graphique enregistre dans {OUT_PNG}")


if __name__ == "__main__":
    main()
