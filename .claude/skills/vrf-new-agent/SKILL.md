---
name: vrf-new-agent
description: Scaffold a brand-new UVM verification agent (protocol block) under odve/comp/agents/ so it follows the framework's standard folder structure, file/class naming convention, and Makefile targets (make atb/adut/auvm/elab/all/run). Use this whenever the user asks to add, create, start, or bootstrap a new agent/block/VIP for a protocol (e.g. "add an ahb agent", "start the jtag agent", "create a new agent for spi") — do not hand-build the directory tree from scratch or copy an existing agent wholesale, since the existing agents (apb, axi) are inconsistent with each other and apb references a common-component base class that doesn't exist in this repo.
---

# Scaffolding a new odve agent

Every agent in `odve/comp/agents/` is supposed to look the same, but today they don't: `apb` extends `ocdve_common_component`/`ocdve_common_driver`/`ocdve_common_monitor` from an `ocdve_common_pkg` that **doesn't exist anywhere in the repo** (grep for it — it's a dangling reference, apb doesn't currently compile), uses a flat `src/` with a top-level `item/`, and has several copy-paste bugs (`slave_driver.sv`'s tasks are defined under the wrong class name, a class named `oocdve_apb_seq_item` with a stray `o`, a `puvm_phase` typo). `axi` instead extends plain UVM base classes (`uvm_agent`/`uvm_driver`/`uvm_monitor`/`uvm_sequencer`) with no common-component layer, and nests `item/` and `mst/slv/mon/` under `src/agent/`.

**`axi`'s pattern is the one to standardize on going forward** — it's self-consistent and doesn't depend on missing framework code. Do not copy `apb`'s structure or its `ocdve_`-prefixed naming for new agents.

## Use the scaffold script, don't hand-build the tree

```bash
cd <path to open-dve repo root>          # the dir containing odve/comp/agents
.claude/skills/vrf-new-agent/scripts/new_agent.sh <proto>
```

`<proto>` is the lowercase protocol name (`spi`, `jtag`, `uart2`, ...) and becomes the directory name under `odve/comp/agents/<proto>/`. The script is idempotent-safe (refuses to run if the target directory already exists) and generates the **complete, working skeleton**:

- `intf/odve_<proto>_if.sv` — interface stub (clk/rst_n only; protocol signals are a TODO).
- `src/item/odve_<proto>_item.sv` + `odve_<proto>_item_pkg.sv`.
- `src/agent/odve_<proto>_cfg.sv`, `odve_<proto>_sqr.sv`, `odve_<proto>_agent.sv`, `odve_<proto>_agent_pkg.sv`, plus `mon/odve_<proto>_mon.sv`, `mst/odve_<proto>_mst_drv_base.sv`, `slv/odve_<proto>_slv_drv.sv` — all extending plain `uvm_*` base classes, wired together (agent creates/connects sqr+drv+mon, gets `cfg` via `uvm_config_db`) so it's a real, buildable starting point, not just empty files.
- `list/agent.f`, `item.f`, `seq.f` — compile filelists already pointing at the generated files.
- `vrf/dut/dut.sv`, `vrf/list/fl_{tb,dut,uvm}.f`, `vrf/tb/{top.sv,env/*,tests/*}` — a working standalone TB (env with `cc`/`scb` placeholders, `base_test`/`simple_test`) modeled on `axi`'s clean version (with `axi`'s one bug — `endclass : envi` instead of `endclass : env` — fixed).
- `vrf/work/{common,run,mini,check}/{Makefile,sourceme,regress.py}` and `vrf/work/rlist/{mini,check,submit}.list` — the standard build/run/regress workspace, using the same `readlink -f "../../../../../../"` depth as `apb`'s (correct because the new agent sits at the same directory depth).

This determinism matters: the trickiest thing to get right by hand is the `sourceme` relative-path depth (`ODVE=$(readlink -f "../../../../../../")`), which silently points at the wrong directory if any nesting level is off. The script gets it right every time because the generated tree is always the same depth.

## After scaffolding

1. Fill in the interface (`intf/odve_<proto>_if.sv`) with the protocol's real signals.
2. Fill in the item (`src/item/odve_<proto>_item.sv`) with real transaction fields.
3. Implement the driver/monitor logic marked `// TODO`.
4. Any new `.sv` file must be added to the relevant `list/*.f` or `vrf/list/fl_*.f` — compilation in this framework is filelist-driven, not directory-scanned, so a file that exists on disk but isn't listed is silently never compiled.
5. Use the **vrf-workflow** skill to compile and run (`cd odve/comp/agents/<proto>/vrf/work/run && source sourceme && make aclean all run`), and again before committing/pushing (analyze/compile checks, then `./regress.py submit`).

## Naming convention reference (for manual edits too, not just scaffolding)

- Files and classes: `odve_<proto>_<role>.sv` containing `class odve_<proto>_<role>`. Package files: `odve_<proto>_<group>_pkg.sv` containing `package odve_<proto>_<group>_pkg` (spelled out fully — don't abbreviate to typos like `agant`, and don't use the `ocdve_` prefix apb has).
- Directory roles mirror `axi`: `intf/` (interface), `src/item/` (sequence item + its pkg), `src/agent/` (cfg, sqr, agent, agent_pkg) with `mon/`, `mst/`, `slv/` subfolders for monitor/master-driver/slave-driver, `seq/` (sequences, once they exist), `list/` (agent-only filelists), `vrf/` (standalone TB: `dut/`, `list/`, `tb/{env,tests}`, `work/{common,run,mini,check}` + `rlist/*.list`).
- Make targets are consistent across every agent because every `work/<variant>/Makefile` just `include`s `work/common/Makefile`, which `include`s the single shared `${ODVE}/script/common/common.mk`. Never redefine `atb`/`adut`/`auvm`/`elab`/`all`/`run` per agent — override variables (`FL_TB`, `TESTNAME`, etc.) in `work/common/Makefile` instead. See the `vrf-workflow` skill for what each target does.
