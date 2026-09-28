# Settings shared by the `run` target of BOTH simulator paths - common.mk for
# Questa, each agent's Makefile.veri for Verilator. They live here rather than
# in common.mk because Makefile.veri is a separate entry point and cannot
# include common.mk: the two define the same target names (all, run, clean,
# rclean, aclean, lint). Anything both paths must agree on belongs here; today
# that is the wall-clock limit (so a hung simulation cannot stall a regression
# forever), the GUI switch, and what vsim is told to do.
#
#   make run                 # limit: TIMEOUT minutes (default below)
#   make run TIMEOUT=30      # 30 minutes
#   make run TIMEOUT=0       # no limit
#   make run GUI=1           # interactive vsim: no limit, no -batch, no auto-quit
#
# TIMEOUT is an ordinary make variable, so a regression passes it through
# -ropts ("TIMEOUT=30") and a list entry can set it per run.
#
#   make run                 # a fresh random seed, printed and written to run.log
#   make run SEED=101        # this seed (a list entry or -ropts="SEED=101" too)
#
# SEED is the simulation seed. It is random for every `make run` unless
# given, so each run of a regression gets its own and no test is forever run
# with one value - "passes at seed 1" is not "passes". Both simulators are
# told it natively (vsim -sv_seed, +verilator+seed+) so $urandom follows it,
# and it is written to run.log as "*** ODVE_SEED: <n>", which regress.py
# reads back onto its status lines and into the -exer report with the
# command that reproduces the run. An agent that keys its own randomness on
# a plusarg (pcie-v's +PCIEV_SEED) derives that from $(SEED) in its Makefile.

TIMEOUT ?= 180

# 1..2^31-2: what Verilator accepts (0 would mean "pick one"), and Questa
# takes any 32-bit value. An environment or command-line SEED counts as given.
ifeq ($(origin SEED),undefined)
    SEED := $(shell od -An -N4 -tu4 /dev/urandom 2>/dev/null | awk '{print ($$1 % 2147483646) + 1}')
    ifeq ($(strip $(SEED)),)
        SEED := $(shell date +%s)
    endif
    SEED_NOTE = seed $(SEED) (random; reproduce with SEED=$(SEED))
else
    SEED_NOTE = seed $(SEED) (given)
endif
SEED_MSG = *** ODVE_SEED: $(SEED)

# GUI=1 is a human watching the simulator: killing it on a clock would be
# wrong, and the run is not being harvested by a regression anyway.
GUI ?=

HAVE_TIMEOUT := $(shell command -v timeout >/dev/null 2>&1 && echo 1)

TIMEOUT_CMD  =
TIMEOUT_NOTE =
ifeq ($(GUI),1)
    TIMEOUT_NOTE = GUI=1: no run time limit
else ifeq ($(strip $(TIMEOUT)),)
    TIMEOUT_NOTE = TIMEOUT empty: no run time limit
else ifeq ($(strip $(TIMEOUT)),0)
    TIMEOUT_NOTE = TIMEOUT=0: no run time limit
else ifneq ($(HAVE_TIMEOUT),1)
    TIMEOUT_NOTE = no 'timeout' on PATH: TIMEOUT=$(TIMEOUT) NOT enforced
else
    # -k: if the simulator ignores the TERM, SIGKILL follows 10s later.
    TIMEOUT_CMD = timeout -k 10s $(strip $(TIMEOUT))m
endif

# A simulation cut short mid-run leaves no UVM report summary in its log, and
# a kill during startup can leave the log empty altogether - so the log alone
# would give no reason. This line is appended to it, and runlog.py turns it
# into the run's verdict reason.
TIMEOUT_MSG = *** ODVE_TIMEOUT: killed after $(strip $(TIMEOUT)) min (TIMEOUT=$(strip $(TIMEOUT))) - simulation did not finish

# Put right after the simulator call in a recipe, as one shell line:
#   cd $(RUN_DIR); $(TIMEOUT_CMD) vsim ... ; $(CHECK_TIMEOUT)
# It also appends the seed marker, after the simulator so that vsim -l (which
# starts run.log afresh) cannot lose it, and so it is there whether the run
# finished or was killed. 124 = GNU timeout expired, 137 = SIGKILL after the
# -k grace period.
CHECK_TIMEOUT = rc=$$?; echo "$(SEED_MSG)" | tee -a run.log; if [ $$rc -eq 124 ] || [ $$rc -eq 137 ]; then echo "$(TIMEOUT_MSG)" | tee -a run.log; fi; exit $$rc

# Same, for a run that keeps no run.log of its own (uart under Verilator):
# report on stdout only instead of dropping a stray log in the work folder.
CHECK_TIMEOUT_NOLOG = rc=$$?; echo "$(SEED_MSG)"; if [ $$rc -eq 124 ] || [ $$rc -eq 137 ]; then echo "$(TIMEOUT_MSG)"; fi; exit $$rc
