// SMBus runs on the i2c agent: its interface and packages first
-f ${ODVE}/comp/agents/i2c/list/agent.f
-f ${ODVE}/comp/agents/i2c/list/seq.f
+incdir+${ODVE}/comp/common/macro
+incdir+${ODVE}/comp/agents/smbus/src/item
+incdir+${ODVE}/comp/agents/smbus/src/agent
+incdir+${ODVE}/comp/agents/smbus/src/agent/mon
+incdir+${ODVE}/comp/agents/smbus/src/agent/mst
+incdir+${ODVE}/comp/agents/smbus/src/agent/slv
${ODVE}/comp/agents/smbus/intf/odve_smbus_if.sv
${ODVE}/comp/agents/smbus/src/item/odve_smbus_item_pkg.sv
${ODVE}/comp/agents/smbus/src/agent/odve_smbus_agent_pkg.sv
