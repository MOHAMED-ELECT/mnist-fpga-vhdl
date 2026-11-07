GHDL    = ghdl
STD     = --std=08
WORKDIR = work

RTL = rtl/counter.vhd
TB  = tb/tb_counter.vhd

.PHONY: test wave clean

test:
	mkdir -p $(WORKDIR)
	$(GHDL) -a $(STD) --workdir=$(WORKDIR) $(RTL) $(TB)
	$(GHDL) -e $(STD) --workdir=$(WORKDIR) tb_counter
	$(GHDL) -r $(STD) --workdir=$(WORKDIR) tb_counter --wave=$(WORKDIR)/counter.ghw

wave: test
	gtkwave $(WORKDIR)/counter.ghw

clean:
	rm -rf $(WORKDIR) *.o *.cf
