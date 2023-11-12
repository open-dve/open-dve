.PHONY: clean all run auvm atb adut elab gcov

PROJ=`pwd`

###DEfines
DEF_OPTS=

###RUN options
RUN_OPTS +=
MK_RUN_OPTS+=+UVM_TESTNAME=$(TESTNAME)
###COMPILE options
ifndef FILELIST_TB 
	FILELIST_TB=$(VRF)/list/tb_flist.f
endif

ifndef FILELIST_UVM
	FILELIST_UVM=$(VRF)/list/uvm_flist.f
endif

ifndef FILELIST_DUT
	FILELIST_DUT=$(VRF)/list/dut_flist.f
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
VAN=vlog
VLOG=vlog
VSIM=vsim



clean : 
	rm -rf ./modelsim.ini ; \
	rm -rf ./work; \
	rm -rf $(COMP_DIR)

pretb : 
	[ ! -d $(COMP_DIR) ] && mkdir $(COMP_DIR); \
	cd $(COMP_DIR); \
	mkdir tb ; \
	vlib tb ; \
	vmap tb tb 

preuvm :
	[ ! -d $(COMP_DIR) ] && mkdir $(COMP_DIR) ; \
	cd $(COMP_DIR) ; \
	mkdir uvm; \
	vlib uvm; \
	vmap uvm uvm 

predut :
	[ ! -d $(COMP_DIR) ] && mkdir $(COMP_DIR) ; \
	cd $(COMP_DIR) ; \
	mkdir dut; \
	vlib dut; \
	vmap dut dut 

auvm :  
	cd $(COMP_DIR) ;\
	vlog -reportprogress 300 -work uvm -sv -covercells -cover sbcefx3 \
	+define+UVM_CMDLINE_NO_DPI \
	+define+UVM_REGEX_NO_DPI \
	-f $(FILELIST_UVM) 

adut :  
	cd $(COMP_DIR) ;\
	vlog -reportprogress 300 -work dut -sv -covercells -cover sbcefx3 -f $(FILELIST_DUT)

atb : 
	cd $(COMP_DIR) ;\
	vlog -reportprogress 300 -work tb -sv -covercells -cover sbcefx3 -f $(FILELIST_TB) \
	-L dut -L uvm

all : preuvm auvm predut adut pretb atb 


run : 
	cd $(COMP_DIR); \
	vsim tb.$(TOP) \
		$(RUN_OPTS) \
		$(MK_RUN_OPTS) \
		-do "run; quit;"

 echo_%:
	@echo '$*=$($*)'

