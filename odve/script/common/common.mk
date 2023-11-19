.PHONY: clean all run auvm atb adut elab gcov

PROJ ?=`pwd`

VRF ?=$(PROJ)/vrf
###DEfines
DEF_OPTS=

###RUN options
DEFAULT_RUN_DIR ?= default__run

ifndef RUN_DIR
RUN_DIR = $(TESTNAME)__run
endif

RUN_PATH=$(PWD)/$(RUN_DIR)

RUN_OPTS +=

MK_RUN_OPTS+=+UVM_TESTNAME=$(TESTNAME)
#MK_RUN_OPTS+=-sv_lib ${ODVE_UVM}/src/dpi

###COMPILE options
ifndef FL_TB 
	FL_TB=$(VRF)/list/fl_tb.f
endif

ifndef FL_UVM
	FL_UVM=$(VRF)/list/fl_uvm.f
endif

ifndef FL_DUT
	FL_DUT=$(VRF)/list/fl_dut.f
endif

COMP_DIR=build

COMP_OPTS+=

ifndef TOP
	TOP=top
endif 


###COVERAGE options
COV_OPTS+=

ifndef TESTNAME
TESTNAME=base_test
endif 

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

#GCC 
GCC=gcc

DPI_C_PATH +=
INC_PATH += 
ROOT_INC_META := /* /*/* /*/*/*
INC_ALL_PATH = $(addprefix $(INC_PATH), $(ROOT_INC_META))

DPI_C_INC_DIRS = $(foreach d, $(DPI_C_PATH),   $(wildcard $(d)/.))
DPI_C_INC_DIRS = $(foreach d, $(INC_ALL_PATH), $(wildcard $(d)/.))

SRCS =  $(foreach d, $(DPI_C_PATH), $(wildcard $(d)/*.c) )
SRCS += $(foreach d, $(DPI_C_PATH), $(wildcard $(d)/*.cpp) )
SRCS += $(foreach d, $(DPI_C_PATH), $(wildcard $(d)/*.cc) )

INCLUDE =  -I$(MS_GCC_PATH)/include
INCLUDE += $(foreach d, $(DPI_C_IN_DIRS), -I$(d))
INCLUDE += -I$(BUILD_PATH)

C_DEFS += 
CFLAGS = -fPIC -Wall $(INCLUDE) $(C_DEFS)

OBJS  = $(SRCS:%.c=%.o) $(SRCS:%.cpp=%.o)
O_OBJS= $(foreach d, $(SIM_DIR) $(wildcard $(d)/*.o))


mkdir_run : 
	[ ! -d $(RUN_DIR) ] && mkdir $(RUN_DIR);

clean : 
	rm -rf ./modelsim.ini ; \
	rm -rf ./work; \
	rm -rf $(COMP_DIR)

rclean :  
	rm -rf ./*__run

aclean : clean rclean 

prework : 
	[ ! -d $(COMP_DIR) ] && mkdir $(COMP_DIR); \
	cd $(COMP_DIR); \
	mkdir tb ; \
	vlib work; \
	vmap work work; \


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
	-f $(FL_UVM) 

adut :  
	cd $(COMP_DIR) ;\
	vlog -reportprogress 300 -work dut -sv -covercells -cover sbcefx3 \
	-f $(FL_DUT)

atb : 
	cd $(COMP_DIR) ;\
	vlog -reportprogress 300 -work tb -sv -covercells -cover sbcefx3 \
	-f $(FL_TB) \
	-L dut -L uvm

elab : 
	cd $(COMP_DIR); \
	vopt $(TOP) tb_pkg_name -o $(TOP)_o \
	-work tb \
	-L dut -L uvm
	-l elab.log

all : prework preuvm auvm predut adut pretb atb erun

erun : 
	[ ! -d $(DEFAULT_RUN_DIR) ] && mkdir $(DEFAULT_RUN_DIR)
	cp -r -n $(COMP_DIR)/modelsim.ini $(DEFAULT_RUN_DIR); \
	cd $(DEFAULT_RUN_DIR); \
	vmap work ./../$(COMP_DIR)/work ;\
	vmap tb   ./../$(COMP_DIR)/tb   ;\
	vmap dut  ./../$(COMP_DIR)/dut  ;\
	vmap uvm  ./../$(COMP_DIR)/uvm  ;


prerun : mkdir_run
	cp -r -n $(DEFAULT_RUN_DIR)/modelsim.ini $(RUN_DIR); \


run : prerun
	cd $(RUN_DIR); \
	vsim tb.$(TOP) \
		$(RUN_OPTS) \
		$(MK_RUN_OPTS) \
		-l run.log \
		-do "run; quit;"

dpi_c : mkdir_run $(OBJS) so co

%.o : %.c
	$(GCC) -c $(CFLAGS) $< -o $(RUN_DIR)/$(notdir $@)
	 
%.o : %.cpp
	$(GCC) -c $(CFLAGS) $< -o $(RUN_DIR)/$(notdir $@)

#shared obj
so : 
	$(GCC) -shared  $(CFLAGS) -o $(RUN_DIR)/$(DPI_SO).so $(O_OBJS)
#clean obj
co : 
	rm -rf $(RUN_DIR)/*.o


echo_% :
	@echo '$*=$($*)'

