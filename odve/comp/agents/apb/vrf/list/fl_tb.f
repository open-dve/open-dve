+incdir+${ODVE_UVM}/src/
+incdir+${ODVE}/comp/common/macro/
+incdir+${ODVE}/comp/agents/apb/vrf/tb/env/
+incdir+${ODVE}/comp/agents/apb/vrf/tb/tests/

// functional coverage runtime, first: the agent's monitor names odve_cov_pkg::
// (compiles to nothing without FCOV=1, see script/common/cov.mk)
${ODVE}/comp/common/cov/odve_cov_pkg.sv
${ODVE}/comp/common/cov/odve_cov_final.sv
${ODVE}/comp/common/cov/odve_cov_emu_feed.sv

-f ${ODVE}/comp/agents/apb/list/agent.f
-f ${ODVE}/comp/agents/apb/list/seq.f

${ODVE}/comp/agents/apb/vrf/tb/env/env_pkg.sv
${ODVE}/comp/agents/apb/vrf/tb/tests/test_pkg.sv

${ODVE}/comp/agents/apb/vrf/tb/top.sv
