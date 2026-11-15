+incdir+${ODVE_UVM}/src/
+incdir+${ODVE}/comp/common/macro/
+incdir+${ODVE}/comp/agents/i2s/vrf/tb/env/
+incdir+${ODVE}/comp/agents/i2s/vrf/tb/tests/

// functional coverage runtime, first: the agent's monitor names odve_cov_pkg::
// (compiles to nothing without FCOV=1, see script/common/cov.mk)
${ODVE}/comp/common/cov/odve_cov_pkg.sv
${ODVE}/comp/common/cov/odve_cov_final.sv

// random numbers: the same for the same +SEED on every simulator (comp/common/rand);
// before the agent, whose item and drivers draw from odve_rand streams
${ODVE}/comp/common/rand/odve_rand_pkg.sv

-f ${ODVE}/comp/agents/i2s/list/agent.f
-f ${ODVE}/comp/agents/i2s/list/seq.f

${ODVE}/comp/agents/i2s/vrf/tb/dut_cfg_if.sv
${ODVE}/comp/agents/i2s/vrf/tb/env/env_pkg.sv
${ODVE}/comp/agents/i2s/vrf/tb/tests/test_pkg.sv

${ODVE}/comp/agents/i2s/vrf/tb/top.sv
