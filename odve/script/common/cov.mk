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
# CCOV=1 (tool code coverage) is reserved for phase 3 of the plan.

FCOV     ?=
CCOV     ?=
COVCNT   ?= 1
COVEVERY ?= 1000000

COV_DEFS     =
COV_RUN_OPTS =
ifeq ($(FCOV),1)
    # Compile: the collector, the base package and the generated group classes
    # are all guarded by ODVE_FCOV, so without it they compile to nothing.
    COV_DEFS     = +define+ODVE_FCOV +define+ODVE_COVCNT=$(COVCNT)
    # Run (cwd is RUN_DIR on both paths, so the dump lands next to run.log).
    COV_RUN_OPTS = +odve_cov_dump=cov.dump +odve_cov_test=$(TESTNAME) +odve_cov_every=$(COVEVERY)
endif
