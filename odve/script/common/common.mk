
.PHONY clean all run auvm atb adut elab gcov

PROJ=`pwd`

###DEfines
DEF_OPTS=

###RUN options
RUN_OPTS+=

###COMPILE options
COMP_DIR=

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
	rm -rf $(COMP_DIR)


all : auvm adut atb elab


run : 
	vsim $(COMP_DIR)/opt1 -sverilog 

 

