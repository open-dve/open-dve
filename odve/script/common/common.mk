.PHONY: clean all run auvm atb adut elab gcov

PROJ=`pwd`

###DEfines
DEF_OPTS=

###RUN options
RUN_OPTS+=

###COMPILE options
ifndef FILELIST_TB 
	FILELIST_TB=$(VRF)/list/tb_flist.f
endif

ifndef FILELIST_UVM
	FILELIST_UVM=$(VRF)/list/uvm_flist.f
endif

ifndef FILELIST_DUT
	FILELIST_UVM=$(VRF)/list/dut_flist.f
endif

COMP_DIR=build

COMP_OPTS+=

ifndef TOP
	TOP=top
endif 


###COVERAGE options
COV_OPTS+=

TESTNAME=

###CONFIGURATION
DUMP=

DUMP_TRAN=

COV=

UVM= 

### Command variable to have ovverdide possibilltuties
COMP_CMD=

RUN_CMD=

COV_CMD=

###QST specific 
VANLZD=vlogan
VLOG=vlog
VSIM=vsim



clean : 
	rm -rf ./modelsim.ini
	rm -rf ./work
	rm -rf $(COMP_DIR)

prep_tb : 
	[ ! -d $(COMP_DIR) ] && mkdir $(COMP_DIR) 
	cd $(COMP_DIR)
	mkdir tb 
	vlib tb 
	vmap tb tb 

prep_uvm :
	[ ! -d $(COMP_DIR) ] && mkdir $(COMP_DIR) 
	cd $(COMP_DIR)
	mkdir uvm
	vlib uvm
	vmap uvm uvm 

prep_dut :
	[ ! -d $(COMP_DIR) ] && mkdir $(COMP_DIR) 
	cd $(COMP_DIR)
	mkdir dut
	vlib dut
	vmap dut dut 

auvm :  
	vlog -reportprogress 300 -work uvm -sv -covercells -cover sbcefx3 -f $(FILELIST_UVM)

adut :  
	vlog -reportprogress 300 -work uvm -sv -covercells -cover sbcefx3 -f $(FILELIST_DUT)

atb : 
	vlog -reportprogress 300 -work tb -sv -covercells -cover sbcefx3 -f $(FILELIST_TB)

all : prep_tb atb 


run : 
	vsim $(COMP_DIR).$(TOP) $(RUN_OPTS) -do "run; quit;"

 echo_%:
	@echo '$*=$($*)'

