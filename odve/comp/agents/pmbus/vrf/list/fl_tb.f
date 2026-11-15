+incdir+${ODVE_UVM}/src/
+incdir+${ODVE}/comp/common/macro/
+incdir+${ODVE}/comp/agents/pmbus/vrf/tb/env/
+incdir+${ODVE}/comp/agents/pmbus/vrf/tb/tests/

// functional coverage runtime, first: the agents' monitors name odve_cov_pkg::
// (compiles to nothing without FCOV=1, see script/common/cov.mk)
${ODVE}/comp/common/cov/odve_cov_pkg.sv
${ODVE}/comp/common/cov/odve_cov_final.sv

// random numbers: the same for the same +SEED on every simulator (comp/common/rand)
${ODVE}/comp/common/rand/odve_rand_pkg.sv

// the pmbus agent pulls in the smbus and i2c agents (its transport) through its agent.f
-f ${ODVE}/comp/agents/pmbus/list/agent.f
-f ${ODVE}/comp/agents/pmbus/list/seq.f

${ODVE}/comp/agents/pmbus/vrf/tb/env/env_pkg.sv
${ODVE}/comp/agents/pmbus/vrf/tb/tests/test_pkg.sv

${ODVE}/comp/agents/pmbus/vrf/tb/top.sv
