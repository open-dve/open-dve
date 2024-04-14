.PHONY: all run clean

BIN=Vtop
PROJ=$(shell readlink -f ../../../)
TB=$(PROJ)/vrf/tb
DUT=$(PROJ)/vrf/dut
#VERILATOR_ROOT=/c/cygwin64/home/viktor/verilator/verilator
#UVM_HOME?=$(PROJ)/uvm

export PROJ
#export DUT
#export UVM_HOME

NPROC=4

BUILD_OPTS = \
	--timescale 1ns/1ps \
	--cc \
	--binary \
	--timing \
	-O3 \
	-j $(NPROC) \
	-o $(BIN)

clean:
	rm -rf obj_dir

all:
	$(VERILATOR_ROOT)/bin/verilator $(BUILD_OPTS) -F $(TB)/list/flist.f

run:
	./obj_dir/$(BIN)

version:
	$(VERILATOR_ROOT)/bin/verilator --version