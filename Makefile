GHDL    = ghdl
STD     = --std=08
WORKDIR = work

RTL = rtl/counter.vhd
TB  = tb/tb_counter.vhd

UNIT_RTL = rtl/mac_unit.vhd rtl/relu_requant.vhd rtl/argmax.vhd
UNIT_TB  = tb/tb_mac_unit.vhd tb/tb_relu_requant.vhd tb/tb_argmax.vhd

.PHONY: test wave clean vectors test_units

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

clean:
	rm -rf $(WORKDIR) *.o *.cf
