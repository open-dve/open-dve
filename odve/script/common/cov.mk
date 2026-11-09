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
# analysis): `covgen.py scan` reads the sources on $(COV_SCAN_FL), parses the
# covergroups in their `ifdef ODVE_COV_NATIVE blocks and fills $(COV_DIR) with
# odve_cov_gen.svh, odve_cov_gen_classes.svh and covmap.json, which
# odve_cov_pkg.sv includes. It never fails the build because of the model: an
# unsupported covergroup becomes a stub plus a warning.
#
# CCOV=1 turns on the simulator's own code coverage: Verilator builds with
# --coverage and every run writes coverage.dat next to run.log; Questa
# analyses with -cover sbcefx3 -covercells and simulates with -coverage,
# saving cov.ucdb - which ModelSim Starter refuses ("not licensed for Code
# Coverage"), loudly, as it should. Without CCOV=1 no coverage flag reaches
# any tool.
#
#   make cov            merge every dump under this work dir and write cov/index.html
#                       (add CCOV=1 to include the Verilator coverage.dat files)

FCOV     ?=
CCOV     ?=
COVCNT   ?= 1
COVEVERY ?= 1000000

# generated coverage files, relative to the work dir (no trailing comments on
# assignments: make keeps the blanks before a '#' as part of the value)
COMP_DIR    ?= build
COV_DIR     ?= $(COMP_DIR)/cov
COV_SCAN_FL ?= $(VRF)/list/fl_tb.f
COV_MODEL   ?= $(notdir $(PROJ))
COVGEN      ?= $(ODVE)/script/cov/covgen.py
PYTHON      ?= python3

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

CCOV_VLOG_OPTS  =
CCOV_BUILD_OPTS =
CCOV_RUN_OPTS   =
RUN_DO_CCOV     =
ifeq ($(CCOV),1)
    CCOV_VLOG_OPTS  = -cover sbcefx3 -covercells
    CCOV_BUILD_OPTS = --coverage
    CCOV_RUN_OPTS   = -coverage
    RUN_DO_CCOV     = coverage save -onexit cov.ucdb;
endif

# Reports over everything under the current work dir: each run directory
# holding a cov.dump (final or checkpoint) contributes, and with CCOV=1 the
# coverage.dat files too.
# `cov` regenerates covmap.json first (acov is a sub-second scan): a `make
# clean` in between would otherwise have taken it away; a model that changed
# since the dumps were written is reported by merge as a hash mismatch.
COV_OUT ?= cov
.PHONY: cov
cov : acov
	mkdir -p $(COV_OUT)
	$(PYTHON) $(COVGEN) merge $(COV_DIR)/covmap.json $$(ls -d */cov.dump* 2>/dev/null | xargs -n1 dirname | sort -u) -o $(COV_OUT)/cov.db.json
	$(PYTHON) $(COVGEN) report $(COV_OUT)/cov.db.json -o $(COV_OUT) -q $(if $(filter 1,$(CCOV)),--code-cov $$(ls */coverage.dat 2>/dev/null),)

.PHONY: acov
acov :
	$(PYTHON) $(COVGEN) scan $(addprefix -f ,$(COV_SCAN_FL)) -o $(COV_DIR) --model $(COV_MODEL)
