#!/usr/bin/env bash
# run_demo.sh -- lance la demo en une seule commande (etape 7 du plan).
#
# Usage :
#   demo/run_demo.sh              # image de test au hasard
#   demo/run_demo.sh --index 42   # image precise

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$REPO_ROOT"
python3 demo/demo.py "$@"
