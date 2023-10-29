.PHONY: clean all run auvm atb adut elab gcov

PROJ=`pwd`

###DEfines
DEF_OPTS=

###RUN options
RUN_OPTS+=

###COMPILE options
ifndef FILELIST_TB 
FILELIST_TB=$(VRF)/list/list.f
endif

FILELIST_DUT=

COMP_DIR=build

COMP_OPTS+=


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

prep : 
	mkdir $(COMP_DIR) 
	vlib $(COMP_DIR) 
	vmap work $(COMP_DIR)


atb : prep
	vlog -reportprogress 300 -work work -sv -covercells -cover sbcefx3 -f $(FILELIST_TB)

all : prep atb 


run : 
	vsim $(COMP_DIR)/opt1 -sverilog 

 

