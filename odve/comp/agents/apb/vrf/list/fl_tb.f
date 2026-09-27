-f ${ODVE}/comp/agents/apb/list/agent.f

+incdir+${ODVE_UVM}/src/
+incdir+${ODVE}/comp/agents/apb/vrf/tb/tests/

// functional coverage (compiles to nothing without FCOV=1, see script/common/cov.mk)
+incdir+${ODVE}/comp/common/macro/
+incdir+${ODVE}/comp/common/cov/
+incdir+${ODVE}/comp/agents/apb/vrf/tb/cov/
${ODVE}/comp/common/cov/odve_cov_if.sv
${ODVE}/comp/common/cov/odve_cov_pkg.sv

${ODVE}/comp/agents/apb/vrf/tb/tests/test_pkg.sv

${ODVE}/comp/agents/apb/vrf/tb/top.sv