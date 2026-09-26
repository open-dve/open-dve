# Per-run wall-clock limit, shared by both simulator paths (common.mk for
# Questa, each agent's Makefile.veri for Verilator) so a hung simulation
# cannot stall a regression forever.
#
#   make run                 # limit: TIMEOUT minutes (default below)
#   make run TIMEOUT=30      # 30 minutes
#   make run TIMEOUT=0       # no limit
#   make run GUI=1           # interactive vsim: no limit, no -batch, no auto-quit
#
# TIMEOUT is an ordinary make variable, so a regression passes it through
# -ropts ("TIMEOUT=30") and a list entry can set it per run.

TIMEOUT ?= 180

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
# 124 = GNU timeout expired, 137 = SIGKILL after the -k grace period.
CHECK_TIMEOUT = rc=$$?; if [ $$rc -eq 124 ] || [ $$rc -eq 137 ]; then echo "$(TIMEOUT_MSG)" | tee -a run.log; fi; exit $$rc

# Same, for a run that keeps no run.log of its own (uart under Verilator):
# report on stdout only instead of dropping a stray log in the work folder.
CHECK_TIMEOUT_NOLOG = rc=$$?; if [ $$rc -eq 124 ] || [ $$rc -eq 137 ]; then echo "$(TIMEOUT_MSG)"; fi; exit $$rc
