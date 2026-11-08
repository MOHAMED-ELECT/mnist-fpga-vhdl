# Architecture

## 1. Vue d'ensemble

Réseau MLP 784 → 32 → 10 (MNIST, pixels 28×28 aplatis), quantifié en INT8,
calculé couche par couche par un unique moteur générique (`layer_engine`,
réutilisé pour les deux couches avec des tailles différentes via les
génériques `N_IN`/`N_HIDDEN`).

```
                              mlp_top.vhd
  ┌──────────────────────────────────────────────────────────────────┐
  │                                                                    │
  │   pix_data[7:0] ──we,addr──▶ image_ram (784×8, lecture synchrone) │
  │                                        │                          │
  │                                        ▼                          │
  │   weight_rom(w1,b1) ──▶┌─────────────────────────┐                │
  │                        │   layer_engine #1         │                │
  │   start ──────────────▶│   N_IN=784, N_HIDDEN=32   │─▶ act_ram(32×8)│
  │                        │   (controller_fsm +       │                │
  │                        │    mac_unit + relu_requant)│               │
  │                        └─────────────────────────┘                │
  │                                        │                          │
  │   weight_rom(w2,b2) ──▶┌─────────────────────────┐                │
  │                        │   layer_engine #2          │               │
  │                        │   N_IN=32, N_HIDDEN=10      │─▶ out_data_raw│
  │                        │   (scores bruts, pas de    │   (10 scores) │
  │                        │    ReLU en sortie)          │              │
  │                        └─────────────────────────┘                │
  │                                        │                          │
  │                                        ▼                          │
  │                                   argmax.vhd                      │
  │                                        │                          │
  │   busy, done ◀── séquenceur interne    ▼                          │
  │                  (TOP_IDLE/WAIT1/WAIT2/DONE)   digit[3:0]          │
  └──────────────────────────────────────────────────────────────────┘
```

Interface officielle (section 3.6 du plan) : `clk`, `rst`, `pix_we`,
`pix_addr`, `pix_data`, `start`, `busy`, `done`, `digit`. Le port
`scores_debug` (10 scores bruts) n'existe que pour la vérification
(comparaison bit-exacte avec le modèle Python dans `tb_mlp_top.vhd`) — il
est retiré de l'interface synthétisée via l'enveloppe `mlp_top_synth.vhd`
(voir [`results/synth_report.txt`](../results/synth_report.txt), piège
"port de debug qui explose le nombre de broches").

## 2. Le contrôleur d'une couche (`controller_fsm.vhd`)

Machine à états qui parcourt les `N_HIDDEN` neurones et, pour chacun, les
`N_IN` entrées :

| État | Rôle |
|---|---|
| `IDLE` | Attend `start`. |
| `LOAD_BIAS` | Présente l'adresse du biais du neurone courant. |
| `LOAD_BIAS_WAIT` | Le biais est valide → charge l'accumulateur (`mac_clear`) ; précharge déjà l'adresse de l'entrée `i=0`. |
| `MAC_LOOP` | Applique le produit poids×entrée pour `i` (données préchargées au cycle précédent) **et, simultanément, précharge déjà l'adresse de `i+1`**. Boucle tant que `i < N_IN-1`. |
| `REQUANT` | `relu_requant` est combinatoire, son résultat est déjà valide. |
| `WRITE_ACT` | Écrit l'activation du neurone dans `act_ram`. |
| `NEXT_NEURON` | Passe au neurone suivant, ou `DONE_ST` si c'était le dernier. |
| `DONE_ST` | Impulsion `done`. |

### Le piège évité : mémoire synchrone et pipelining

Les mémoires (ROM/RAM) sont à **lecture synchrone** : la donnée à une
adresse n'est valide qu'un cycle *après* avoir présenté cette adresse. Une
implémentation naïve ferait donc 2 cycles par MAC (1 pour adresser, 1 pour
calculer), ce qui donnerait 1568 cycles pour la couche 1 au lieu des 784
visés par la Figure 5 du plan. `MAC_LOOP` évite ça en **préchargeant
l'adresse `i+1` pendant qu'il applique le produit pour `i`** : la boucle
dure alors exactement `N_IN` cycles.

Chronogramme (exemple réduit à `N_IN=3` pour tenir sur une seule figure ;
le vrai circuit fait la même chose sur 784 puis 32 cycles) :

```json
{
  "signal": [
    { "name": "clk",      "wave": "p........" },
    { "name": "state",    "wave": "=.=.=.=.=.=.=.=.", "data": ["IDLE","LOAD_BIAS","LOAD_BIAS_WAIT","MAC_LOOP i=0","MAC_LOOP i=1","MAC_LOOP i=2","REQUANT","WRITE_ACT"] },
    { "name": "in_addr (adresse préchargée)", "wave": "x.=.=.=.x.......", "data": ["0","1","2"] },
    { "name": "mac_en (applique le produit)", "wave": "0..1.1.1.0......" },
    { "name": "mac_clear",                    "wave": "0.10.............", "node": "" }
  ],
  "edge": [],
  "head": { "text": "controller_fsm — pipelining adresse/calcul (N_IN=3)" }
}
```

> Colle ce JSON dans l'éditeur [wavedrom.com/editor.html](https://wavedrom.com/editor.html)
> pour voir le rendu graphique. Point clé : à chaque cycle `MAC_LOOP`,
> `in_addr` porte déjà l'adresse de l'entrée *suivante* pendant que
> `mac_en` applique le produit de l'entrée *courante* — aucun cycle n'est
> perdu à "juste adresser".

## 3. Parallélisme spatial (`mac_array.vhd`, étape 5)

`rtl/mac_array.vhd` généralise `layer_engine` à **N unités MAC en
parallèle** (générique `N_MAC`), pilotées par `controller_fsm_n.vhd` :

```
                    mac_array.vhd (N_MAC voies)
  weight_rom_n (N_MAC ports de lecture simultanés : w1(0..N-1), b1(0..N-1))
        │           │           │                 │
        ▼           ▼           ▼                 ▼
  ┌──────────┐┌──────────┐┌──────────┐     ┌──────────┐
  │ mac_unit │ │ mac_unit │ │ mac_unit │ ... │ mac_unit │   N_MAC voies
  │  lane 0  │ │  lane 1  │ │  lane 2  │     │ lane N-1 │
  └──────────┘└──────────┘└──────────┘     └──────────┘
        │           │           │                 │
        └───────────┴─────┬─────┴─────────────────┘
                     mux (sel_lane)
                           │
                           ▼
                 relu_requant (UN SEUL bloc,
                 partagé entre les N voies pour
                 ne pas dupliquer son multiplieur)
```

Les N voies calculent **le même indice d'entrée `i`** en parallèle, mais
pour N neurones de sortie différents — d'où les ports N-larges de
`weight_rom_n` (chaque voie a besoin de lire son propre poids au même
cycle). C'est précisément ce qui limite le parallélisme en pratique : un
bloc mémoire physique ECP5 (DP16KD) n'a que 2 ports, donc au-delà de 2
voies le contenu de la ROM doit être dupliqué dans plusieurs blocs. Voir
[`results/synth_report.txt`](../results/synth_report.txt) section 3 pour
les chiffres réels (N=8 tient tout juste sur un plus gros FPGA, N=32 ne
tient sur aucun modèle ECP5-U).

## 4. Capture GTKWave

Le plan demande une vraie capture d'écran GTKWave dans `docs/`. Cet
environnement de développement n'a pas d'interface graphique, donc cette
capture n'a pas pu être prise automatiquement — à faire une fois en local :

```bash
make test       # ou toute autre cible qui génère un .ghw, ex. :
# ghdl -r --std=08 --workdir=work tb_mlp_top -gN_IMAGES=5 --wave=work/mlp_top.ghw
gtkwave work/mlp_top.ghw
```

Dans GTKWave, ajoute les signaux `state`, `i`, `j`, `mac_en`, `digit` et
`done` à la vue, lance la simulation sur quelques images, puis exporte une
capture (`File → Grab`, ou simplement une capture d'écran) sous
`docs/gtkwave_capture.png`. Référence-la ensuite ici :

```markdown
![Capture GTKWave](gtkwave_capture.png)
```
