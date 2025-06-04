

# vhdl files
FILES = source/*
VHDLEX = .vhd

# testbench
TESTBENCHPATH = testbench/${TESTBENCHFILE}$(VHDLEX)
TESTBENCHFILE = ${TESTBENCH}_tb

#GHDL CONFIG
GHDL_CMD = ghdl
GHDL_FLAGS  = --ieee=synopsys --warn-no-vital-generic

SIMDIR = simulation
STOP_TIME = 500ns

# Simulation break condition
GHDL_SIM_OPT = --stop-time=$(STOP_TIME)
VCDFILE = ${SIMDIR}/${TESTBENCHFILE}.vcdgz

WAVEFORM_VIEWER = gtkwave

.PHONY: clean

all: clean compile run view

compile:
ifeq ($(strip $(TESTBENCH)),)
		@echo "TESTBENCH not set. Use TESTBENCH=<value> to set it."
			@exit 1
endif

	@mkdir -p simulation
	@$(GHDL_CMD) -i $(GHDL_FLAGS) --workdir=simulation --work=work $(TESTBENCHPATH) $(FILES)
	@$(GHDL_CMD) -m  $(GHDL_FLAGS) --workdir=simulation --work=work $(TESTBENCHFILE)



run:
	@$(GHDL_CMD) -r $(GHDL_FLAGS) --workdir=simulation --work=work $(TESTBENCHFILE) --vcdgz=$(VCDFILE) $(GHDL_SIM_OPT)

view:
	@gunzip --stdout $(SIMDIR)/$(TESTBENCHFILE).vcdgz | $(WAVEFORM_VIEWER) --vcd
	@rm $(TESTBENCHFILE)
	@rm e~$(TESTBENCHFILE).o

clean:
	@rm -rf $(SIMDIR)