+incdir+${ODVE_UVM}/src/
+incdir+${ODVE}/comp/common/macro/
+incdir+${ODVE}/comp/agents/smbus/vrf/tb/env/
+incdir+${ODVE}/comp/agents/smbus/vrf/tb/tests/

// functional coverage runtime, first: the agents' monitors name odve_cov_pkg::
// (compiles to nothing without FCOV=1, see script/common/cov.mk)
${ODVE}/comp/common/cov/odve_cov_pkg.sv
${ODVE}/comp/common/cov/odve_cov_final.sv

// random numbers: the same for the same +SEED on every simulator (comp/common/rand)
${ODVE}/comp/common/rand/odve_rand_pkg.sv

// the smbus agent pulls in the i2c agent (its transport) through its agent.f
-f ${ODVE}/comp/agents/smbus/list/agent.f
-f ${ODVE}/comp/agents/smbus/list/seq.f

${ODVE}/comp/agents/smbus/vrf/tb/env/env_pkg.sv
${ODVE}/comp/agents/smbus/vrf/tb/tests/test_pkg.sv

${ODVE}/comp/agents/smbus/vrf/tb/top.sv
