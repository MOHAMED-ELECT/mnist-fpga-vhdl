GHDL    = ghdl
STD     = --std=08
WORKDIR = work

RTL = rtl/counter.vhd
TB  = tb/tb_counter.vhd

UNIT_RTL = rtl/mac_unit.vhd rtl/relu_requant.vhd rtl/argmax.vhd
UNIT_TB  = tb/tb_mac_unit.vhd tb/tb_relu_requant.vhd tb/tb_argmax.vhd

LAYER1_RTL = rtl/weights_pkg.vhd rtl/mac_unit.vhd rtl/relu_requant.vhd rtl/argmax.vhd \
             rtl/image_ram.vhd rtl/act_ram.vhd rtl/weight_rom.vhd \
             rtl/controller_fsm.vhd rtl/layer_engine.vhd
LAYER1_TB  = tb/tb_layer1.vhd

TOP_RTL = rtl/weights_pkg.vhd rtl/mac_unit.vhd rtl/relu_requant.vhd rtl/argmax.vhd \
          rtl/image_ram.vhd rtl/act_ram.vhd rtl/weight_rom.vhd \
          rtl/controller_fsm.vhd rtl/layer_engine.vhd rtl/mlp_top.vhd
TOP_TB  = tb/tb_mlp_top.vhd

# Chemin ou le paquet apt "ghdl" (backend mcode) installe ses bibliotheques
# std/ieee precompilees. UNIQUEMENT necessaire si ton plugin yosys-ghdl vient
# d'un paquet apt separe du paquet "ghdl" (ex. Ubuntu 24.04+, paquet
# "yosys-plugin-ghdl") : dans ce cas, sans cette variable, la synthese
# echoue avec "error: cannot find \"std\" library". Verifier le bon chemin
# avec : dpkg -L ghdl-mcode | grep vhdl/std (ou dpkg -L ghdl).
#
# Avec l'OSS CAD Suite (https://github.com/YosysHQ/oss-cad-suite-build,
# necessaire sur Ubuntu < 23.10 ou tout systeme sans le paquet apt
# "yosys-plugin-ghdl") : le plugin et sa bibliotheque GHDL sont deja
# assortis et se trouvent l'un l'autre tout seuls -- laisse cette variable
# VIDE (ex. "make synth GHDL_PLUGIN_PREFIX=") pour ne rien forcer.
GHDL_PLUGIN_PREFIX = /usr/lib/ghdl/mcode/vhdl

.PHONY: test wave clean vectors test_units weights_pkg layer1_ref test_layer1 \
        sim_fast sim_full synth synth_timing ci

test:
	mkdir -p $(WORKDIR)
	$(GHDL) -a $(STD) --workdir=$(WORKDIR) $(RTL) $(TB)
	$(GHDL) -e $(STD) --workdir=$(WORKDIR) tb_counter
	$(GHDL) -r $(STD) --workdir=$(WORKDIR) tb_counter --wave=$(WORKDIR)/counter.ghw

wave: test
	gtkwave $(WORKDIR)/counter.ghw

vectors:
	python3 python/gen_vectors.py

test_units: vectors
	mkdir -p $(WORKDIR)
	$(GHDL) -a $(STD) --workdir=$(WORKDIR) $(UNIT_RTL) $(UNIT_TB)
	$(GHDL) -e $(STD) --workdir=$(WORKDIR) tb_mac_unit
	$(GHDL) -e $(STD) --workdir=$(WORKDIR) tb_relu_requant
	$(GHDL) -e $(STD) --workdir=$(WORKDIR) tb_argmax
	@echo "=== tb_mac_unit ==="
	$(GHDL) -r $(STD) --workdir=$(WORKDIR) tb_mac_unit
	@echo "=== tb_relu_requant ==="
	$(GHDL) -r $(STD) --workdir=$(WORKDIR) tb_relu_requant
	@echo "=== tb_argmax ==="
	$(GHDL) -r $(STD) --workdir=$(WORKDIR) tb_argmax

weights_pkg:
	python3 python/gen_vhdl_pkg.py

layer1_ref:
	python3 python/export_layer1_ref.py

test_layer1: weights_pkg layer1_ref
	mkdir -p $(WORKDIR)
	$(GHDL) -a $(STD) --workdir=$(WORKDIR) $(LAYER1_RTL) $(LAYER1_TB)
	$(GHDL) -e $(STD) --workdir=$(WORKDIR) tb_layer1
	$(GHDL) -r $(STD) --workdir=$(WORKDIR) tb_layer1

sim_fast:
	mkdir -p $(WORKDIR)
	$(GHDL) -a $(STD) --workdir=$(WORKDIR) $(TOP_RTL) $(TOP_TB)
	$(GHDL) -e $(STD) --workdir=$(WORKDIR) tb_mlp_top
	$(GHDL) -r $(STD) --workdir=$(WORKDIR) tb_mlp_top -gN_IMAGES=50

sim_full:
	mkdir -p $(WORKDIR)
	$(GHDL) -a $(STD) --workdir=$(WORKDIR) $(TOP_RTL) $(TOP_TB)
	$(GHDL) -e $(STD) --workdir=$(WORKDIR) tb_mlp_top
	$(GHDL) -r $(STD) --workdir=$(WORKDIR) tb_mlp_top -gN_IMAGES=1000

synth:
	mkdir -p results
	$(if $(GHDL_PLUGIN_PREFIX),GHDL_PREFIX=$(GHDL_PLUGIN_PREFIX)) yosys -m ghdl synth/synth.ys | tee results/synth_report_raw.txt

# place-and-route (nextpnr-ecp5) : donne la Fmax reelle et le chemin
# critique, ce que "stat" seul (cible "synth" ci-dessus) ne donne pas.
# DEVICE=25k par defaut (voir synth/synth.ys : les poids tiennent large
# sur ce modele pour N=1 MAC). Necessite results/mlp_top_synth.json,
# donc "make synth" doit avoir ete lance avant.
DEVICE = --25k

# NOTE : ces deux cibles ecrivent des LOGS BRUTS (results/*_raw.txt,
# plusieurs Mo), utiles pour deboguer en detail mais pas pour etre lus
# directement. results/synth_report.txt (sans suffixe "_raw"), lui, est
# un resume ecrit a la main a partir de ces logs et commite dans le depot
# -- ce n'est PAS ce que ces cibles generent, et elles ne l'ecrasent pas.
synth_timing: synth
	nextpnr-ecp5 $(DEVICE) --json results/mlp_top_synth.json --freq 100 \
		--timing-allow-fail 2>&1 | tee results/synth_timing_raw.txt

# suite rapide (quelques minutes) lancee par la CI (.github/workflows/ci.yml) :
# unites de base (mac_unit/relu_requant/argmax, vecteurs generes localement)
# + reseau complet sur un petit echantillon (sim_fast, 50 images, utilise
# directement rtl/weights_pkg.vhd et data/*.hex deja commites dans le
# depot). "test_layer1" est volontairement exclu de la CI : sa cible
# "layer1_ref" retelecharge MNIST a chaque fois (python/train_mlp.py,
# pas de cache commite), ce qui rendrait la CI plus lente et dependante du
# reseau sans ajouter de couverture utile (sim_fast teste deja la couche 1
# A L'INTERIEUR du reseau complet). "make test_layer1" reste disponible en
# local. make sim_full (1000 images) et scripts/run_sweep.sh sont aussi
# exclus : trop longs pour une CI a chaque commit.
ci: test_units sim_fast

clean:
	rm -rf $(WORKDIR) *.o *.cf
