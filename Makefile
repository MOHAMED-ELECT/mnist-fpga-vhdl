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

.PHONY: test wave clean vectors test_units weights_pkg layer1_ref test_layer1 sim_fast sim_full

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

clean:
	rm -rf $(WORKDIR) *.o *.cf
