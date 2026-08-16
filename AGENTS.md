# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, etc.) when working with code in this repository.

## What this repo is

`open-dve` is a UVM/SystemVerilog verification framework ("Open Design Verification Environment") that unifies testbench compilation, running, and regression across multiple agents/VIPs (APB, AHB, AXI, PCIe, NVMe, MPHY, UNIPRO, UFS — per the roadmap in `README.md`; several are still placeholders). Its content lives under `odve/` (this repo is consumed as the `odve` git submodule by downstream repos such as `amba-axi`, where it's checked out at `<downstream>/odve`).

Targets Mentor/Siemens **Questa/ModelSim** (`vlog`/`vsim`/`vmap`/`vlib`) as the primary simulator, with **Verilator** as a supported second simulator via `make ... VERILATOR=1` (legacy spelling `VERI=1`). Both are expected to pass before commit/push — see the `vrf-workflow` skill. See `README.md` for toolchain prerequisites (make, python3, bash, readlink; Verilator runs from a container, needing only docker or podman — run `script/verilator-docker/setup.sh` once to fetch the image).

## Commands

All commands assume a Bash shell (Git Bash on Windows) with `make`, `python3`, `readlink`, and Questa/ModelSim's `vsim` on `PATH`.

### Build and run an agent's verification environment (example: APB)

```bash
cd odve/comp/agents/apb/vrf/work/run
source sourceme
make aclean all run
```

- `sourceme` exports `ODVE`, the agent-specific path var (e.g. `ODVE_APB`), and `PROJ` as absolute paths, then sources `script/source/common_sourceme`, which sets `ODVE_UVM` (defaults to the vendored `uvm/uvm-1.1d/`; `uvm/1800.2-2020-2.0/` is available but commented out) and locates `MS_HOME` from `vsim` on `PATH`.
- `make all` runs `prework preuvm auvm uvm_dpi predut adut pretb atb elib` — compiles UVM, DUT, and TB into **separate Questa libraries** (`work/uvm`, `work/dut`, `work/tb`), then elaborates with `vopt ... -L dut -L uvm`.
- `make run` invokes `vsim tb.$(TOP) ... +UVM_TESTNAME=$(TESTNAME)` (default `TESTNAME=base_test`; override with `make TESTNAME=<name> run`).
- `make clean`/`make aclean` remove build artifacts; `make rclean` removes `*__run` result directories.
- Each agent's `vrf/work/<variant>/Makefile` (`run`, `check`, `mini`, `common`) `include`s `work/common/Makefile`, which includes the single shared `script/common/common.mk` used by every agent. Prefer changing `script/common/common.mk` for framework-wide build/run behavior, and an agent's `work/common/Makefile` for agent-local overrides.

### Run a regression list

```bash
cd odve/comp/agents/apb/vrf/work/<variant>   # e.g. mini
source sourceme
./regress.py <list-name>                     # reads ../rlist/<list-name>.list
```

`regress.py` (per-agent copy, thin wrapper) forwards to `script/regress/regress.py`, which:
- parses `../rlist/<list-name>.list` via `readlist.py` (each line names a run with `TESTNAME`/`COMP_DIR`/`RUN_OPTS` overrides, e.g. `run_name1 : TESTNAME=t1 COMP_DIR=d2 RUN_OPTS+='+arg1=1'`),
- converts it to job commands via `list2json.py`,
- executes jobs in parallel via `jobrunner.py` (`-max_jobs`, default 4).

`script/regress/example.list` and `script/regress/comp.cfg` are references for the list/config format. Any `work/<variant>` folder has its own `regress.py`/`sourceme`, so the list name doesn't need to match the folder — e.g. `apb`'s `work/rlist/submit.list` (pre-push regression, run as `./regress.py submit` from `work/run` or `work/mini`) sits alongside `mini.list`.

## Architecture

### Repo layout (under `odve/`)

- `comp/agents/<protocol>/` — one UVM agent per protocol: `apb`, `axi`, `ahb`, `jtag`, `spi`, `uart`. **`apb` is the most complete and is the best reference implementation** to copy patterns from when building out another agent.
- `comp/common/` — shared base classes (`base/odve_common_base_item.sv`) and macros (`macro/odve_macro.sv`, e.g. `` `odve_rand(obj) `` calls `obj.user_randomize()`).
- `script/common/common.mk` — the single shared Make include behind every agent's `vrf/work/*/Makefile`. Defines the `prework/preuvm/auvm/predut/adut/pretb/atb/elib/run/clean/rclean/aclean` targets and the `FL_TB`/`FL_UVM`/`FL_DUT`/`TOP`/`TESTNAME`/`RUN_DIR`/`COMP_DIR` variables.
- `script/source/common_sourceme` — sets `ODVE_UVM`, locates the Questa install (`MS_HOME`) from `vsim` on `PATH`, and points `VERILATOR_ROOT` at the containerised Verilator in `script/verilator-docker/` (preset `VERILATOR_ROOT` yourself to use a native install instead).
- `script/verilator-docker/` — containerised Verilator: `setup.sh` (one-time image fetch, with OS/engine detection and an offline `--load` path) and `bin/verilator` (docker/podman shim used as `$VERILATOR_ROOT/bin/verilator`).
- `script/regress/` — the regression runner: `regress.py` (entry point), `readlist.py` (parses `*.list` files), `list2json.py` (converts parsed runs to job commands), `jobrunner.py` (parallel job execution), `list2json.py`.
- `script/schedule/`, `script/pdf/pdf2req/` — scheduling and requirements-doc tooling (early/placeholder).
- `uvm/` — vendored UVM library sources: `uvm-1.1d` (default, per `common_sourceme`) and `1800.2-2020-2.0` (available, not default). Used instead of relying on a simulator-provided UVM.
- `vip/` — placeholders for larger VIPs (`pcie`, `nvme`) mentioned in the README's roadmap; not yet implemented.

### Per-agent structure (same shape in every `comp/agents/<protocol>/`, most complete in `apb`)

- `intf/` — SystemVerilog interface(s) (e.g. `odve_apb_if.sv`, plus a plain `apb_if.sv`).
- `src/` — the UVM component sources: `<proto>_agent.sv`, `<proto>_agent_cfg.sv`, `<proto>_agent_pkg.sv` (aggregates `` `include ``s), `<proto>_driver_base.sv` + master/slave driver specializations, `<proto>_monitor.sv`.
- `item/` — the sequence item class(es) (e.g. `ocdve_apb_seq_item.sv`).
- `seq/` — reusable sequences built on the item (e.g. `odve_apb_read_seq.sv`, `odve_apb_write_seq.sv`) plus a `seq_lib_pkg.sv` aggregator.
- `reg/` — register-layer artifacts (scaffolding only in most agents).
- `list/` — compile filelists for the agent itself: `agent.f` (full agent incl. `+incdir`s), `item.f` (item package only), `seq.f`.
- `vrf/` — the agent's own standalone verification environment used to test it in isolation:
  - `dut/dut.sv` — a minimal example DUT.
  - `tb/top.sv` — top module; sets the default UVM test via `uvm_config_db` and calls `run_test`.
  - `tb/env/` — `env.sv` (top-level `uvm_env`), `cc.sv` (connectivity/config component), `scb.sv` (scoreboard), `env_pkg.sv`.
  - `tb/tests/` — `base_test.sv` plus scenario tests (`read_test.sv`, `write_test.sv`, `simple_test.sv`), aggregated by `test_pkg.sv`.
  - `list/fl_tb.f`, `fl_dut.f`, `fl_uvm.f` — separate filelists per compile step (TB, DUT, UVM), referenced by `common.mk`'s `FL_TB`/`FL_DUT`/`FL_UVM`.
  - `work/` — the build/run/regress workspace: `common/` (shared Makefile+sourceme — edit here for shared settings), `run/`, `mini/` (thin variant wrappers), `rlist/*.list` (named regression run definitions).

New source files must be added to the correct `list/*.f` (agent) or `vrf/list/fl_*.f` (TB) — compilation is filelist-driven, not directory-scanned.

`apb` and `axi` currently disagree on structure/base classes (see the `vrf-new-agent` skill for the details and why `axi`'s plain-`uvm_*` pattern, not `apb`'s, is canonical going forward). When adding a **new** protocol agent, use the `vrf-new-agent` skill (`.claude/skills/vrf-new-agent/`), which scaffolds a working skeleton via `scripts/new_agent.sh <proto>` instead of hand-copying an existing agent.

### Compilation model

Questa compilation is split into separate libraries per layer — `uvm`, `dut`, `tb` — then linked at elaboration (`vopt ... -L dut -L uvm`) and simulated (`vsim tb.$(TOP) ...`). This is why a new file is invisible to the build until it's added to the right filelist.

### Environment variable conventions

- `ODVE` — absolute path to this framework's root (`odve/` inside this repo, or `<downstream>/odve/odve` when consumed as a submodule).
- `ODVE_<PROTO>` (e.g. `ODVE_APB`, `ODVE_AXI`) — absolute path to that protocol's agent directory, used inside its own filelists via `${ODVE_<PROTO>}/...`.
- `ODVE_UVM` — path to the vendored UVM library in use.
- `PROJ` — absolute path to the current agent, used as the default `VRF` base (`$(PROJ)/vrf`) in `common.mk`.

All of these are set by the relevant `sourceme` script — always `source sourceme` before running `make` in a `work/` directory.

## Consumers

Downstream repos (e.g. `amba-axi`) pull this repo in as a `odve` git submodule and build their own agent on top of `comp/common/` and `script/`. When changing shared scripts (`script/common/common.mk`, `script/source/common_sourceme`, `script/regress/*`), check for impact across all agents in `comp/agents/`, not just the one you're editing.
