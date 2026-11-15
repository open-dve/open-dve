// PMBus runs on the smbus agent (which runs on the i2c agent): their packages first
-f ${ODVE}/comp/agents/smbus/list/agent.f
-f ${ODVE}/comp/agents/smbus/list/seq.f
+incdir+${ODVE}/comp/common/macro
+incdir+${ODVE}/comp/agents/pmbus/src/item
+incdir+${ODVE}/comp/agents/pmbus/src/agent
+incdir+${ODVE}/comp/agents/pmbus/src/agent/mon
+incdir+${ODVE}/comp/agents/pmbus/src/agent/mst
+incdir+${ODVE}/comp/agents/pmbus/src/agent/slv
${ODVE}/comp/agents/pmbus/src/item/odve_pmbus_item_pkg.sv
${ODVE}/comp/agents/pmbus/src/agent/odve_pmbus_agent_pkg.sv
