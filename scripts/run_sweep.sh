#!/usr/bin/env bash
# run_sweep.sh
# Etape 5 : simule mlp_top_n.vhd pour N_MAC = 1, 2, 4, 8, 16, 32, verifie
# que chaque variante donne toujours 0 ecart avec le modele de reference,
# mesure le nombre de cycles moyen par image (start->done, hors
# chargement des pixels) et ecrit le resultat dans results/results.csv.
#
# Les colonnes LUT / memoires / Fmax restent vides a cette etape (elles
# viennent de la synthese, etape 6) : le script les remplit a "N/A".
#
# Usage :
#   scripts/run_sweep.sh [N_IMAGES]
#
# N_IMAGES (defaut 20) : nombre d'images testees par variante. Le but ici
# est de reconfirmer "0 ecart" et de mesurer les cycles pour CHAQUE
# architecture, pas de recalculer la precision globale (deja validee sur
# 1000 images a l'etape 4) -- un echantillon modeste suffit et garde le
# balayage des 6 variantes rapide.
#
# Prerequis : data/weights_int.npz (etape 1), rtl/weights_pkg.vhd (etape
# 3, make weights_pkg), data/test_images.hex et data/golden_outputs.txt
# (etape 1, python/export_hex.py) doivent deja exister.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

N_IMAGES="${1:-20}"
GHDL=ghdl
STD=--std=08
WORKDIR=work

N_VALUES=(1 2 4 8 16 32)

RTL_COMMON=(
  rtl/weights_pkg.vhd
  rtl/parallel_pkg.vhd
  rtl/mac_unit.vhd
  rtl/relu_requant.vhd
  rtl/argmax.vhd
  rtl/image_ram.vhd
  rtl/act_ram.vhd
  rtl/weight_rom_n.vhd
  rtl/controller_fsm_n.vhd
  rtl/mac_array.vhd
  rtl/mlp_top_n.vhd
)
TB=tb/tb_mlp_top_n.vhd

for f in rtl/weights_pkg.vhd data/test_images.hex data/golden_outputs.txt; do
  if [ ! -f "$f" ]; then
    echo "ERREUR : $f est manquant. Lance d'abord :" >&2
    echo "  make weights_pkg   (genere rtl/weights_pkg.vhd depuis data/weights_int.npz)" >&2
    echo "  python3 python/export_hex.py   (genere data/test_images.hex et data/golden_outputs.txt)" >&2
    exit 1
  fi
done

mkdir -p "$WORKDIR" results

echo "Analyse (une seule fois, independante de N_MAC)..."
$GHDL -a $STD --workdir=$WORKDIR "${RTL_COMMON[@]}" "$TB"
$GHDL -e $STD --workdir=$WORKDIR tb_mlp_top_n

echo "N,cycles,latence_us_100MHz,LUT,memoires,Fmax_MHz" > results/results.csv

echo ""
echo "N_MAC | cycles/image | latence @100MHz | ecarts"
echo "------+--------------+------------------+-------"

for N in "${N_VALUES[@]}"; do
  OUT=$($GHDL -r $STD --workdir=$WORKDIR tb_mlp_top_n -gN_MAC="$N" -gN_IMAGES="$N_IMAGES" 2>&1 || true)

  LINE=$(echo "$OUT" | grep "RESULAT" || true)
  if [ -z "$LINE" ]; then
    echo "ERREUR : pas de ligne RESULAT pour N_MAC=$N. Sortie complete :" >&2
    echo "$OUT" >&2
    exit 1
  fi

  CYCLES=$(echo "$LINE" | grep -oE "CYCLES_AVG=[0-9]+" | cut -d= -f2)
  SCORE_FAIL=$(echo "$LINE" | grep -oE "SCORE_FAIL=[0-9]+" | cut -d= -f2)
  DIGIT_FAIL=$(echo "$LINE" | grep -oE "DIGIT_FAIL=[0-9]+" | cut -d= -f2)

  if [ "$SCORE_FAIL" != "0" ] || [ "$DIGIT_FAIL" != "0" ]; then
    echo "ERREUR : N_MAC=$N ne reproduit pas le modele de reference" >&2
    echo "  (score_fail=$SCORE_FAIL, digit_fail=$DIGIT_FAIL). Arret du balayage." >&2
    echo "$OUT" >&2
    exit 1
  fi

  LATENCE_US=$(python3 -c "print(f'{$CYCLES * 0.01:.2f}')")

  printf "%5s | %12s | %13s us | OK (0 ecart)\n" "$N" "$CYCLES" "$LATENCE_US"
  echo "$N,$CYCLES,$LATENCE_US,N/A,N/A,N/A" >> results/results.csv
done

echo ""
echo "Termine : results/results.csv ecrit ($N_IMAGES images testees par variante)."
echo "Les colonnes LUT/memoires/Fmax seront completees a l'etape 6 (synthese)."
