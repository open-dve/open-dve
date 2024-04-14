#PROJ=`pwd`

DEF=

RUN_OPTS += -batch

#FL_TB=$(ODVE)/comp/agents/apb/vrf/list/fl_tb.f
#FL_UVM=$(ODVE)/comp/agents/apb/vrf/list/fl_uvm.f
#FL_DUT=$(ODVE)/comp/agents/apb/vrf/list/fl_dut.f

#DPI_C_PATH=$(ODVE_UVM)/src/dpi

#UVM_DPI_SRC=$(ODVE_UVM)/src/dpi/uvm_dpi.cc

#UVM_INC=-I$(ODVE_UVM)/src/dpi -I$(MS_HOME)/include

COMP_OPTS+=

COV_OPTS+=

MAKE_RUN_OPTS+=

TESTNAME=

DUMP=

DUMP_TRAN=

COV=

UVM= 

COMP_CMD=

RUN_CMD=

COV_CMD=

ALL_CMD=prework predut adut pretb atb elib

include ${ODVE}/script/common/common.mk

elib : 
	[ ! -d $(DEFAULT_RUN_DIR) ] && mkdir $(DEFAULT_RUN_DIR); \
	cp -r -n $(COMP_DIR)/modelsim.ini $(DEFAULT_RUN_DIR); \
	cd $(DEFAULT_RUN_DIR); \
	vmap work ./../$(COMP_DIR)/work ;\
	vmap tb   ./../$(COMP_DIR)/tb   ;\
	vmap dut  ./../$(COMP_DIR)/dut  ;


prerun : mkdir_run
	cp -r -n $(DEFAULT_RUN_DIR)/modelsim.ini $(RUN_DIR); \
	
run : prerun 
	cd $(RUN_DIR); \
	vsim tb.$(TOP) \
		$(RUN_OPTS) \
		$(MK_RUN_OPTS) \
		-l run.log \
		-do "run -all; quit;"