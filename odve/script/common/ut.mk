# Unit tests with the vendored SVUnit (svunit/svunit-3.38.1), on either
# simulator. Any ut/ folder holding *_unit_test.sv files and a svunit.f
# (the sources under test, with their +define+/+incdir+; buildSVUnit picks
# a file of exactly that name up by itself) gets:
#
#   make ut                 # ModelSim/Questa (vsim on PATH)
#   make ut VERILATOR=1     # Verilator
#   make ut UT_ARGS="+x=1"  # extra simulator run arguments (plusargs)
#   make ut UT_FILTER=<testcase>.<test>   # run a subset
#   make utclean
#
# runSVUnit finds the *_unit_test.sv files, generates the test suite and
# runner (into $(UT_OUT), where it also runs), compiles everything with
# svunit.f and runs it; $(UT_OUT)/ut.log is the full output, run.log the
# simulator's. The verdict is the runner's own line "[testrunner]: PASSED",
# not the tool's exit code (vsim exits 0 on failures).
UT_SIM    := $(if $(filter 1,$(VERILATOR)$(VERI)),verilator,modelsim)
UT_OUT    ?= work_$(UT_SIM)
UT_ARGS   ?=
UT_FILTER ?=
UT_CARGS_verilator = --timing --timescale 1ns/1ps -Wno-fatal
UT_CARGS_modelsim  = -sv
UT_RARGS_verilator =
UT_RARGS_modelsim  = -batch   # as the agents' RUN_OPTS: plain `vsim -c` fails on ModelSim Starter (licensing check)

.PHONY: ut utclean
ut :
	mkdir -p $(UT_OUT)
	runSVUnit -s $(UT_SIM) -o $(UT_OUT) -c "$(UT_CARGS_$(UT_SIM))" \
		$(if $(strip $(UT_RARGS_$(UT_SIM)) $(UT_ARGS)),-r "$(strip $(UT_RARGS_$(UT_SIM)) $(UT_ARGS))",) \
		$(if $(UT_FILTER),--filter $(UT_FILTER),) 2>&1 | tee $(UT_OUT)/ut.log; \
	if grep -qE "\[testrunner\]: PASSED" $(UT_OUT)/ut.log; then echo "ut: PASSED ($(UT_SIM))"; \
	else echo "ut: FAILED ($(UT_SIM)) - see $(UT_OUT)/ut.log"; exit 1; fi

utclean :
	rm -rf work_modelsim work_verilator
