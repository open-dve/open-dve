#!/bin/bash
# Scaffold a new odve UVM agent under comp/agents/<proto>, following the
# axi agent's structure/naming convention (plain uvm_agent/uvm_driver/
# uvm_monitor/uvm_sequencer — no ocdve_common_* layer).
#
# Usage: run from the open-dve repo root:
#   .claude/skills/vrf-new-agent/scripts/new_agent.sh <proto>
# e.g.:
#   .claude/skills/vrf-new-agent/scripts/new_agent.sh spi
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <proto_lowercase>" >&2
    exit 1
fi

PROTO="$1"
if ! [[ "$PROTO" =~ ^[a-z][a-z0-9_]*$ ]]; then
    echo "Error: <proto> must be lowercase, start with a letter (e.g. spi, ahb, uart2)" >&2
    exit 1
fi
PROTO_UPPER=$(echo "$PROTO" | tr '[:lower:]' '[:upper:]')

if [ ! -d "odve/comp/agents" ]; then
    echo "Error: run this from the open-dve repo root (odve/comp/agents not found here)" >&2
    exit 1
fi

AGENT="odve/comp/agents/$PROTO"
if [ -e "$AGENT" ]; then
    echo "Error: $AGENT already exists — pick a new protocol name or remove it first" >&2
    exit 1
fi

echo "Scaffolding new agent '$PROTO' at $AGENT"

mkdir -p "$AGENT"/{intf,list,src/item,src/agent/mst,src/agent/slv,src/agent/mon,seq,reg}
mkdir -p "$AGENT"/vrf/{dut,list,tb/env,tb/tests,work/{common,run,mini,check,rlist}}

# ---------------------------------------------------------------------------
# intf/
# ---------------------------------------------------------------------------
cat > "$AGENT/intf/odve_${PROTO}_if.sv" <<EOF
interface odve_${PROTO}_if #(
    parameter int unsigned ADDR_W = 32,
    parameter int unsigned DATA_W = 32
) (
    input logic clk,
    input logic rst_n
);
    // TODO: add ${PROTO_UPPER} protocol signals here

endinterface
EOF

# ---------------------------------------------------------------------------
# src/item/
# ---------------------------------------------------------------------------
cat > "$AGENT/src/item/odve_${PROTO}_item.sv" <<EOF
class odve_${PROTO}_item extends uvm_sequence_item;
    \`uvm_object_utils(odve_${PROTO}_item)

    // TODO: add transaction fields here

    function new(string name = "odve_${PROTO}_item");
        super.new(name);
    endfunction
endclass
EOF

cat > "$AGENT/src/item/odve_${PROTO}_item_pkg.sv" <<EOF
\`ifndef ODVE_${PROTO_UPPER}_ITEM_PKG
\`define ODVE_${PROTO_UPPER}_ITEM_PKG
package odve_${PROTO}_item_pkg;
    \`include "uvm_macros.svh"
    import uvm_pkg::*;
    \`include "odve_${PROTO}_item.sv"
endpackage
\`endif
EOF

# ---------------------------------------------------------------------------
# src/agent/
# ---------------------------------------------------------------------------
cat > "$AGENT/src/agent/odve_${PROTO}_cfg.sv" <<EOF
class odve_${PROTO}_cfg extends uvm_object;
    \`uvm_object_utils(odve_${PROTO}_cfg)

    bit is_master = 1;
    virtual odve_${PROTO}_if vif;

    function new(string name = "odve_${PROTO}_cfg");
        super.new(name);
    endfunction
endclass
EOF

cat > "$AGENT/src/agent/odve_${PROTO}_sqr.sv" <<EOF
class odve_${PROTO}_sqr extends uvm_sequencer #(odve_${PROTO}_item);
    \`uvm_component_utils(odve_${PROTO}_sqr)

    function new(string name = "odve_${PROTO}_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
EOF

cat > "$AGENT/src/agent/mon/odve_${PROTO}_mon.sv" <<EOF
class odve_${PROTO}_mon extends uvm_monitor;
    \`uvm_component_utils(odve_${PROTO}_mon)

    uvm_analysis_port #(odve_${PROTO}_item) item_collected_port;
    virtual odve_${PROTO}_if vif;

    function new(string name = "odve_${PROTO}_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_collected_port = new("item_collected_port", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        // TODO: sample vif and item_collected_port.write(tr) per transaction
    endtask
endclass
EOF

cat > "$AGENT/src/agent/mst/odve_${PROTO}_mst_drv_base.sv" <<EOF
class odve_${PROTO}_mst_drv_base extends uvm_driver #(odve_${PROTO}_item);
    \`uvm_component_utils(odve_${PROTO}_mst_drv_base)

    virtual odve_${PROTO}_if vif;

    function new(string name = "odve_${PROTO}_mst_drv_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            // TODO: drive vif from req
            seq_item_port.item_done();
        end
    endtask
endclass
EOF

cat > "$AGENT/src/agent/slv/odve_${PROTO}_slv_drv.sv" <<EOF
class odve_${PROTO}_slv_drv extends uvm_driver #(odve_${PROTO}_item);
    \`uvm_component_utils(odve_${PROTO}_slv_drv)

    virtual odve_${PROTO}_if vif;

    function new(string name = "odve_${PROTO}_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            // TODO: respond on vif per req
            seq_item_port.item_done();
        end
    endtask
endclass
EOF

cat > "$AGENT/src/agent/odve_${PROTO}_agent.sv" <<EOF
class odve_${PROTO}_agent extends uvm_agent;
    \`uvm_component_utils(odve_${PROTO}_agent)

    odve_${PROTO}_cfg          cfg;
    odve_${PROTO}_sqr          sqr;
    odve_${PROTO}_mon          mon;
    odve_${PROTO}_mst_drv_base drv;

    function new(string name = "odve_${PROTO}_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(odve_${PROTO}_cfg)::get(this, "", "cfg", cfg)) begin
            \`uvm_fatal(get_name(), "No config object")
        end
        mon = odve_${PROTO}_mon::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = odve_${PROTO}_sqr::type_id::create("sqr", this);
            drv = odve_${PROTO}_mst_drv_base::type_id::create("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        mon.vif = cfg.vif;
        if (get_is_active() == UVM_ACTIVE) begin
            drv.vif = cfg.vif;
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction
endclass
EOF

cat > "$AGENT/src/agent/odve_${PROTO}_agent_pkg.sv" <<EOF
\`ifndef ODVE_${PROTO_UPPER}_AGENT_PKG
\`define ODVE_${PROTO_UPPER}_AGENT_PKG
package odve_${PROTO}_agent_pkg;
    \`include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_${PROTO}_item_pkg::*;

    \`include "odve_${PROTO}_cfg.sv"
    \`include "mon/odve_${PROTO}_mon.sv"
    \`include "mst/odve_${PROTO}_mst_drv_base.sv"
    \`include "slv/odve_${PROTO}_slv_drv.sv"
    \`include "odve_${PROTO}_sqr.sv"
    \`include "odve_${PROTO}_agent.sv"
endpackage
\`endif
EOF

# ---------------------------------------------------------------------------
# list/ (agent compile filelists)
# ---------------------------------------------------------------------------
cat > "$AGENT/list/agent.f" <<EOF
+incdir+\${ODVE}/comp/agents/${PROTO}/src/item
+incdir+\${ODVE}/comp/agents/${PROTO}/src/agent
+incdir+\${ODVE}/comp/agents/${PROTO}/src/agent/mon
+incdir+\${ODVE}/comp/agents/${PROTO}/src/agent/mst
+incdir+\${ODVE}/comp/agents/${PROTO}/src/agent/slv
\${ODVE}/comp/agents/${PROTO}/intf/odve_${PROTO}_if.sv
\${ODVE}/comp/agents/${PROTO}/src/item/odve_${PROTO}_item_pkg.sv
\${ODVE}/comp/agents/${PROTO}/src/agent/odve_${PROTO}_agent_pkg.sv
EOF

cat > "$AGENT/list/item.f" <<EOF
+incdir+\${ODVE}/comp/agents/${PROTO}/src/item
\${ODVE}/comp/agents/${PROTO}/src/item/odve_${PROTO}_item_pkg.sv
EOF

: > "$AGENT/list/seq.f"

# ---------------------------------------------------------------------------
# vrf/dut, vrf/list
# ---------------------------------------------------------------------------
cat > "$AGENT/vrf/dut/dut.sv" <<EOF
module dut (
    input clk, rst
);

    initial repeat (1) \$display ("Hi from DUT");
endmodule
EOF

cat > "$AGENT/vrf/list/fl_tb.f" <<EOF
-f \${ODVE}/comp/agents/${PROTO}/list/agent.f

+incdir+\${ODVE_UVM}/src/
+incdir+\${ODVE}/comp/agents/${PROTO}/vrf/tb/env/

\${ODVE}/comp/agents/${PROTO}/vrf/tb/env/env_pkg.sv
\${ODVE}/comp/agents/${PROTO}/vrf/tb/tests/test_pkg.sv

\${ODVE}/comp/agents/${PROTO}/vrf/tb/top.sv
EOF

cat > "$AGENT/vrf/list/fl_dut.f" <<EOF
\${ODVE}/comp/agents/${PROTO}/vrf/dut/dut.sv
EOF

cat > "$AGENT/vrf/list/fl_uvm.f" <<EOF
+incdir+\${ODVE_UVM}/src/
\${ODVE_UVM}/src/uvm_macros.svh
\${ODVE_UVM}/src/uvm_pkg.sv
EOF

# ---------------------------------------------------------------------------
# vrf/tb/env
# ---------------------------------------------------------------------------
cat > "$AGENT/vrf/tb/env/cc.sv" <<'EOF'
class cc extends uvm_component;
    `uvm_component_utils(cc)

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
    endfunction
endclass : cc
EOF

cat > "$AGENT/vrf/tb/env/scb.sv" <<'EOF'
class scb extends uvm_component;
    `uvm_component_utils(scb)

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
    endfunction
endclass : scb
EOF

cat > "$AGENT/vrf/tb/env/env.sv" <<'EOF'
class env extends uvm_env;
    `uvm_component_utils(env)
    cc  cc_o;
    scb scb_o;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cc_o  = cc::type_id::create("cc_o", this);
        scb_o = scb::type_id::create("scb_o", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
    endfunction
endclass : env
EOF

cat > "$AGENT/vrf/tb/env/env_pkg.sv" <<'EOF'
package env_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;

    `include "cc.sv"
    `include "scb.sv"
    `include "env.sv"
endpackage : env_pkg
EOF

# ---------------------------------------------------------------------------
# vrf/tb/tests
# ---------------------------------------------------------------------------
cat > "$AGENT/vrf/tb/tests/base_test.sv" <<'EOF'
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    env env_o;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_o = env::type_id::create("env_o", this);
    endfunction : build_phase
endclass : base_test
EOF

cat > "$AGENT/vrf/tb/tests/simple_test.sv" <<'EOF'
class simple_test extends base_test;
    `uvm_component_utils(simple_test)

    function new(string name = "simple_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        `uvm_info(get_name(), "RUN SIMPLE TEST", UVM_NONE)
    endtask : run_phase
endclass : simple_test
EOF

cat > "$AGENT/vrf/tb/tests/test_pkg.sv" <<'EOF'
`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "simple_test.sv"
endpackage

`endif
EOF

cat > "$AGENT/vrf/tb/top.sv" <<EOF
module top;
    import uvm_pkg::*;
    import test_pkg::*;

    odve_${PROTO}_if odve_${PROTO}_if ();

    initial repeat (1) \$display ("Hello From TB");
    initial begin
        uvm_config_db #(uvm_object_wrapper)::set(null, "*", "uvm_test_top", simple_test::type_id::get());
        run_test("simple_test");
    end
endmodule
EOF

# ---------------------------------------------------------------------------
# vrf/work/{common,run,mini,check}
# ---------------------------------------------------------------------------
cat > "$AGENT/vrf/work/common/sourceme" <<'EOF'
#!/bin/bash
export ODVE=$(readlink -f "../../../../../../")
source $ODVE/script/source/common_sourceme
EOF

cat > "$AGENT/vrf/work/common/Makefile" <<'EOF'
#Please go to this folder to edit local regression settings.

DEF=

RUN_OPTS += -batch

COMP_OPTS+=

COV_OPTS+=

MAKE_RUN_OPTS+=

TESTNAME?=simple_test

DUMP=

DUMP_TRAN=

COV=

UVM=

COMP_CMD=

RUN_CMD=

COV_CMD=

include ${ODVE}/script/common/common.mk
EOF

for variant in run check mini; do
    cat > "$AGENT/vrf/work/$variant/sourceme" <<'EOF'
#!/bin/bash
source ./../common/sourceme
EOF
    cat > "$AGENT/vrf/work/$variant/Makefile" <<'EOF'
#Please go to common folder to edit local regression settings.
include ./../common/Makefile
EOF
    cat > "$AGENT/vrf/work/$variant/regress.py" <<'EOF'
#!python
import subprocess
import sys
import os
odve=os.environ["ODVE"]
subprocess.call(["python", f"{odve}/script/regress/regress.py"] + sys.argv[1:])
EOF
    chmod +x "$AGENT/vrf/work/$variant/sourceme" "$AGENT/vrf/work/$variant/regress.py"
done
chmod +x "$AGENT/vrf/work/common/sourceme"

# ---------------------------------------------------------------------------
# vrf/work/rlist
# ---------------------------------------------------------------------------
for list in mini check submit; do
    cat > "$AGENT/vrf/work/rlist/$list.list" <<'EOF'
run_name1 : TESTNAME=simple_test COMP_DIR=d1
EOF
done

# ---------------------------------------------------------------------------
# READMEs
# ---------------------------------------------------------------------------
cat > "$AGENT/README" <<EOF
# odve ${PROTO_UPPER} agent

TODO: describe the ${PROTO_UPPER} agent (scaffolded by vrf-new-agent).
EOF

cat > "$AGENT/vrf/README.md" <<'EOF'
# How to run compilation

```bash
source sourceme
make clean
make all
make run
#or
make clean all run
```

## TB Folder structure
- dut - example DUT for compilation
- tb  - example TB with agent instantiation and DUT connection
- work - folder to build/run simulation and regression
- list - TB filelists (fl_tb.f, fl_dut.f, fl_uvm.f)
EOF

echo "Done. Created:"
find "$AGENT" -type f | sort

cat <<EOF

Next steps:
1. Fill in odve_${PROTO}_if.sv with real ${PROTO_UPPER} signals.
2. Fill in odve_${PROTO}_item.sv with real transaction fields.
3. Implement the driver(s)/monitor logic (marked TODO).
4. If you add more .sv files, add them to list/*.f or vrf/list/fl_*.f — compilation is filelist-driven, not directory-scanned.
5. Compile/run with the vrf-workflow skill: cd odve/comp/agents/${PROTO}/vrf/work/run && source sourceme && make aclean all run.
EOF
