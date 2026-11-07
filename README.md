# Accélérateur de réseau de neurones MNIST en VHDL

Reconnaissance de chiffres manuscrits (MNIST) réalisée en VHDL, 100 % simulée
(GHDL + GTKWave), avec un modèle Python de référence (golden model) et une
synthèse Yosys pour mesurer LUT, mémoires et fréquence maximale.

Projet mené en 8 étapes, du modèle Python jusqu'à la démo publique. Aucune
carte FPGA nécessaire.

## Statut

🚧 **Étape 0** : mise en place de l'environnement et premier circuit de test
(compteur 8 bits) simulé de bout en bout.

## Reproduire

```
make test     # compile et simule le compteur de test
make wave     # ouvre GTKWave sur la simulation
```

## Arborescence (cible)

```
mnist-fpga-vhdl/
├── README.md
├── Makefile
├── python/      entraînement, quantification, modèle de référence
├── rtl/         circuit (VHDL-2008)
├── tb/          testbenches
├── data/        poids et images de test (.hex)
├── scripts/     mesures et automatisation
├── synth/       synthèse Yosys
├── demo/        démo finale
├── docs/        schémas, chronogrammes
└── results/     résultats mesurés (CSV, rapport de synthèse)
```

## Plan du projet

Projet en 8 étapes : mise en place, modèle Python + quantification INT8,
briques VHDL (MAC, ReLU, argmax), mémoires + contrôleur, réseau complet
validé sur 1000 images, exploration du parallélisme, synthèse + CI, démo
et publication.
