# Coverage switches (doc/fcov-plan.md 3.5), shared by both simulator paths:
# common.mk (Questa) and each agent's Makefile.veri (Verilator) include this
# file like run.mk. Nothing here is active unless asked for, so the default
# build is exactly what it was before coverage existed.
#
#   make all run FCOV=1                functional coverage: collector compiled in, dump per run
#   make all run FCOV=1 COVCNT=32      32-bit hit counters instead of one bit per bin
#   make all run FCOV=1 COVEVERY=100000   checkpoint the dump every N hits (0 = only at the end)
#   ./regress.py submit -ropts="FCOV=1"   the same through a regression
#
# With FCOV=1 the build gains the `acov` step (added to ALL_CMD before the TB
# analysis): it fills $(COV_DIR) with the generated coverage files that
# odve_cov_pkg.sv includes. PHASE-0 SPIKE: acov copies hand-written stand-ins
# from $(COV_SRC_DIR); phase 1 replaces the copy with `covgen.py scan`.
#
# CCOV=1 (tool code coverage) is reserved for phase 3 of the plan.

FCOV     ?=
CCOV     ?=
COVCNT   ?= 1
COVEVERY ?= 1000000

# generated coverage files, relative to the work dir (no trailing comments on
# assignments: make keeps the blanks before a '#' as part of the value)
COMP_DIR    ?= build
COV_DIR     ?= $(COMP_DIR)/cov
COV_SRC_DIR ?= $(VRF)/tb/cov/gen.spike

COV_DEFS     =
COV_RUN_OPTS =
COV_ALL_CMD  =
ifeq ($(FCOV),1)
    # Compile: the runtime package and the generated group classes are all
    # guarded by ODVE_FCOV, so without it they compile to nothing. The incdir
    # is absolute because vlog runs from inside $(COMP_DIR).
    COV_DEFS     = +define+ODVE_FCOV +define+ODVE_COVCNT=$(COVCNT) +incdir+$(CURDIR)/$(COV_DIR)
    # Run (cwd is RUN_DIR on both paths, so the dump lands next to run.log).
    COV_RUN_OPTS = +odve_cov_dump=cov.dump +odve_cov_test=$(TESTNAME) +odve_cov_every=$(COVEVERY)
    COV_ALL_CMD  = acov
endif

.PHONY: acov
acov :
	mkdir -p $(COV_DIR)
	cp $(COV_SRC_DIR)/odve_cov_gen.svh $(COV_SRC_DIR)/*.map.json $(COV_DIR)/
