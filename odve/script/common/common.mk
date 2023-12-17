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
GCC=g++

DPI_C_PATH +=
INC_PATH   += 
ROOT_INC_META := #/* /*/* /*/*/*
INC_ALL_PATH = $(addprefix $(INC_PATH), $(ROOT_INC_META))

DPI_C_INC_DIRS  = $(foreach d, $(DPI_C_PATH),   $(wildcard $(d)/.))
DPI_C_INC_DIRS += $(foreach d, $(INC_ALL_PATH), $(wildcard $(d)/.))

SRCS += $(foreach d, $(DPI_C_PATH), $(wildcard $(d)/*.c) )
SRCS += $(foreach d, $(DPI_C_PATH), $(wildcard $(d)/*.cpp) )
SRCS += $(foreach d, $(DPI_C_PATH), $(wildcard $(d)/*.cc) )

INCLUDE += -I$(MS_HOME)/include
INCLUDE += $(foreach d, $(DPI_C_INC_DIRS), -I$(d))
INCLUDE += -I$(COMP_DIR)

C_DEFS += 
CFLAGS = -fPIC -Wall $(INCLUDE) $(C_DEFS)

OBJS  = $(SRCS:%.c=%.o) $(SRCS:%.cpp=%.o)
O_OBJS= $(foreach d, $(RUN_DIR), $(wildcard $(d)/*.o))


mkdir_run :
	[ ! -d $(RUN_DIR) ] && mkdir $(RUN_DIR) || exit 0;


UVM_DPI_SRC += $(ODVE_UVM)/src/dpi/uvm_dpi.cc

UVM_DPI_INC += -I$(ODVE_UVM)/src/dpi -I$(MS_HOME)/include 

#-L$(MS_HOME)/modelsim_lib

UVM_C_DEFS  += -DQUESTA

UVM_CFLAGS   = $(UVM_DPI_INC) $(UVM_C_DEFS)

UVM_DPI_RECOMPILE ?= 1

UVM_DPI_MODE ?= MS_WIN32

ifeq ($(UVM_DPI_RECOMPILE), 1) 
	ifeq ($(UVM_DPI_MODE), MS_WIN32)
		UVM_DPI_TARG    = uvm_dpi_o uvm_dpi_so
		UVM_DPI_OBJ     = uvm_dpi.o
		UVM_DPI_SHARED  = uvm_dpi.dll
	endif
endif  

UVM_DPI_C_RUN_OPTS = -sv_lib ./../$(COMP_DIR)/uvm_dpi

uvm_dpi : $(UVM_DPI_TARG) 

uvm_dpi_o : 
	$(GCC) -c $(UVM_CFLAGS) $(UVM_DPI_SRC) -o $(COMP_DIR)/$(UVM_DPI_OBJ) ; 

uvm_dpi_so : 
	$(GCC) -shared $(COMP_DIR)/$(UVM_DPI_OBJ) -o $(COMP_DIR)/$(UVM_DPI_SHARED) $(MS_HOME)/win32aloem/mtipli.dll 


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
	-f $(FL_UVM) \


#	+define+UVM_CMDLINE_NO_DPI \
#	+define+UVM_REGEX_NO_DPI \
	
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

all : prework preuvm auvm uvm_dpi predut adut pretb atb elib 

elib : 
	[ ! -d $(DEFAULT_RUN_DIR) ] && mkdir $(DEFAULT_RUN_DIR); \
	cp -r -n $(COMP_DIR)/modelsim.ini $(DEFAULT_RUN_DIR); \
	cd $(DEFAULT_RUN_DIR); \
	vmap work ./../$(COMP_DIR)/work ;\
	vmap tb   ./../$(COMP_DIR)/tb   ;\
	vmap dut  ./../$(COMP_DIR)/dut  ;\
	vmap uvm  ./../$(COMP_DIR)/uvm  ;


prerun : mkdir_run
	cp -r -n $(DEFAULT_RUN_DIR)/modelsim.ini $(RUN_DIR); \
	cp -r -n $(COMP_DIR)/$(UVM_DPI_SHARED) $(RUN_DIR); \
	
#cp -r -n $(COMP_DIR)/uvm_dpi.so $(RUN_DIR); \


run : prerun 
	cd $(RUN_DIR); \
	vsim tb.$(TOP) \
		$(RUN_OPTS) \
		$(UVM_DPI_C_RUN_OPTS) \
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

