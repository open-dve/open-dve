.PHONY: clean all run auvm atb adut elab gcov lint

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

# Shared run settings (TIMEOUT, GUI, RUN_DO) - also included by the Verilator
# path's Makefile.veri, which cannot include this file.
include $(dir $(lastword $(MAKEFILE_LIST)))run.mk

# What vsim is told to do. GUI=1 hands the session to the user: keep the
# simulator open (no `quit`) and drop the -batch that the agent Makefile
# forces for regressions, so the GUI can actually come up.
RUN_DO ?= run -all; quit;
ifeq ($(GUI),1)
    RUN_DO = run -all;
    override RUN_OPTS := $(filter-out -batch -c,$(RUN_OPTS)) -gui
endif

# Simulator run switches and plusargs. Given on the make command line by
# regress lists (RUN_OPTS+='+arg=1') and by regress.py (+UVM_MAX_QUIT_COUNT),
# so an agent Makefile must add its own with `override RUN_OPTS += ...`, or
# make drops the makefile's value in favour of the command line's.
RUN_OPTS +=

MK_RUN_OPTS+=+UVM_TESTNAME=$(TESTNAME) \
-L dut 
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


###UVM DPI. Questa loads it at run time (-sv_lib); Verilator instead links
# the same source straight into Vtop (Makefile.veri). ModelSim Starter is a
# 32-bit tool on both OSes, so the library must be 32-bit too, built with the
# gcc ModelSim ships (MS_GCC_PATH, from common_sourceme) rather than the
# host's. Two branches, picked by HOST_OS:
#   MS_WIN32   Windows (Git Bash): uvm_dpi.dll, linked with win32aloem/mtipli.dll
#   MS_LINUX32 Linux:              uvm_dpi.so, -m32, linked with linuxaloem/libmtipli.so
# Override UVM_DPI_MODE on the command line to force one.
ifeq ($(OS),Windows_NT)
HOST_OS ?= windows
else
HOST_OS ?= $(shell uname -s | tr A-Z a-z)
endif

UVM_DPI_SRC += $(ODVE_UVM)/src/dpi/uvm_dpi.cc
# uvm_dpi.cc #includes the other dpi sources, so the object depends on all of them
UVM_DPI_DEPS = $(wildcard $(ODVE_UVM)/src/dpi/*.c $(ODVE_UVM)/src/dpi/*.cc $(ODVE_UVM)/src/dpi/*.h)

UVM_DPI_INC += -I$(ODVE_UVM)/src/dpi -I$(MS_HOME)/include 

UVM_C_DEFS  += -DQUESTA

UVM_CFLAGS   = $(UVM_DPI_INC) $(UVM_C_DEFS)

UVM_DPI_RECOMPILE ?= 1

ifeq ($(HOST_OS), windows)
UVM_DPI_MODE ?= MS_WIN32
else
UVM_DPI_MODE ?= MS_LINUX32
endif

UVM_DPI_OBJ = uvm_dpi.o
ifeq ($(UVM_DPI_MODE), MS_WIN32)
UVM_DPI_GCC    ?= $(GCC)
UVM_DPI_SHARED  = uvm_dpi.dll
UVM_DPI_CFLAGS  =
UVM_DPI_LDFLAGS = -shared
UVM_DPI_LIBS    = $(MS_HOME)/win32aloem/mtipli.dll
else ifeq ($(UVM_DPI_MODE), MS_LINUX32)
UVM_DPI_GCC    ?= $(if $(MS_GCC_PATH),$(MS_GCC_PATH)/bin/g++,$(GCC))
UVM_DPI_SHARED  = uvm_dpi.so
UVM_DPI_CFLAGS  = -m32 -fPIC
UVM_DPI_LDFLAGS = -m32 -shared
UVM_DPI_LIBS    = -L$(MS_HOME)/linuxaloem -lmtipli
else
$(error unknown UVM_DPI_MODE '$(UVM_DPI_MODE)' (MS_WIN32 or MS_LINUX32))
endif

ifeq ($(UVM_DPI_RECOMPILE), 1) 
UVM_DPI_TARG    = uvm_dpi_so
endif  

UVM_DPI_C_RUN_OPTS = -sv_lib ./../$(COMP_DIR)/uvm_dpi

.PHONY: uvm_dpi uvm_dpi_o uvm_dpi_so
uvm_dpi : $(UVM_DPI_TARG) 

# The object is a real file target: rebuilt only when a dpi source changed.
$(COMP_DIR)/$(UVM_DPI_OBJ) : $(UVM_DPI_SRC) $(UVM_DPI_DEPS)
	[ -d $(COMP_DIR) ] || mkdir $(COMP_DIR)
	$(UVM_DPI_GCC) -c $(UVM_DPI_CFLAGS) $(UVM_CFLAGS) $(UVM_DPI_SRC) -o $@

uvm_dpi_o : $(COMP_DIR)/$(UVM_DPI_OBJ)

$(COMP_DIR)/$(UVM_DPI_SHARED) : $(COMP_DIR)/$(UVM_DPI_OBJ)
	$(UVM_DPI_GCC) $(UVM_DPI_LDFLAGS) $< -o $@ $(UVM_DPI_LIBS)

uvm_dpi_so : $(COMP_DIR)/$(UVM_DPI_SHARED)


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

ALL_CMD ?= prework preuvm auvm uvm_dpi predut adut pretb atb elib
all :  $(ALL_CMD)

# `make lint` is the fast front-of-build check on every path, whatever tool is
# behind it. Questa has no separate linter, so its analyze steps stand in:
# everything in ALL_CMD except the DPI build and the elaboration. Under
# VERILATOR=1 the agent's Makefile.veri provides the same target as
# `verilator --lint-only`.
# Derived from ALL_CMD so an agent that trims ALL_CMD (uart: no UVM layer)
# gets a matching lint instead of a vlog run over a filelist it doesn't have.
LINT_CMD ?= $(filter-out uvm_dpi elib,$(ALL_CMD))
lint : $(LINT_CMD)

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
	@echo "run: $(if $(TIMEOUT_CMD),time limit $(strip $(TIMEOUT)) min,$(TIMEOUT_NOTE))"
	cd $(RUN_DIR); \
	$(TIMEOUT_CMD) vsim tb.$(TOP) \
		$(RUN_OPTS) \
		$(UVM_DPI_C_RUN_OPTS) \
		$(MK_RUN_OPTS) \
		-l run.log \
		-do "$(RUN_DO)"; \
	$(CHECK_TIMEOUT)

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

