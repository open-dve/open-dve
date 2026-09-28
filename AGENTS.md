# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, etc.) when working with code in this repository.

## What this repo is

`open-dve` is a UVM/SystemVerilog verification framework ("Open Design Verification Environment") that unifies testbench compilation, running, and regression across multiple agents/VIPs (APB, AHB, AXI, PCIe, NVMe, MPHY, UNIPRO, UFS — per the roadmap in `README.md`; several are still placeholders). Its content lives under `odve/` (this repo is consumed as the `odve` git submodule by downstream repos such as `amba-axi`, where it's checked out at `<downstream>/odve`).

Targets Mentor/Siemens **Questa/ModelSim** (`vlog`/`vsim`/`vmap`/`vlib`) as the primary simulator, with **Verilator** as a supported second simulator via `make ... VERILATOR=1` (legacy spelling `VERI=1`). Both are expected to pass before commit/push — see the `vrf-workflow` skill. After any `.sv` edit, run `make lint` first — the fast front-of-build check on either path: under Questa it is the analyze (`vlog`) steps without elaboration (`LINT_CMD` in `common.mk`); under `VERILATOR=1` it is `verilator --lint-only` over the same filelist, reporting syntax/type errors in seconds without the multi-minute C++ build (full output in `work/<variant>/lint.log`). Then do the real `make all`. See `README.md` for toolchain prerequisites (make, python3, bash, readlink; Verilator runs from a container, needing only docker or podman — run `script/verilator-docker/setup.sh` once to fetch the image).

## Commands

All commands assume a Bash shell (Git Bash on Windows) with `make`, `python3`, `readlink`, and Questa/ModelSim's `vsim` on `PATH`.

### Build and run an agent's verification environment (example: APB)

```bash
cd odve/comp/agents/apb/vrf/work/run
source sourceme
make aclean all run
```

- `sourceme` exports `ODVE`, the agent-specific path var (e.g. `ODVE_APB`), and `PROJ` as absolute paths, then sources `script/source/common_sourceme`, which sets `ODVE_UVM` (defaults to the vendored `uvm/uvm-1.1d/`; `uvm/1800.2-2020-2.0/` is available but commented out) and locates `MS_HOME` from `vsim` on `PATH`.
- `make all` runs `prework preuvm auvm uvm_dpi predut adut pretb atb elib` — compiles UVM, DUT, and TB into **separate Questa libraries** (`build/uvm`, `build/dut`, `build/tb`), then `elib` maps them into `default__run/`. It does **not** elaborate: the `elab` (`vopt`) target is defined but unused, so elaboration only happens inside `vsim` at `make run`.
- `make run` invokes `vsim tb.$(TOP) ... +UVM_TESTNAME=$(TESTNAME)` (default `TESTNAME=base_test`; override with `make TESTNAME=<name> run`), under a `TIMEOUT`-minute wall-clock cap (default 180, `script/common/run.mk`; `TIMEOUT=0` disables) and with a seed that is random per run unless `SEED=<n>` is given (also `run.mk`: `vsim -sv_seed` / `+verilator+seed+`, recorded in `run.log` as `*** ODVE_SEED: <n>`; `-ropts="SEED=<n>"` pins a regression, `-exer` prints the `Repro` command with the failing seed). `make run GUI=1` hands the session to an interactive vsim — no cap, no `-batch`, no auto-`quit`. A run killed on the clock gets `*** ODVE_TIMEOUT: ...` appended to its `run.log`, because such a log otherwise ends without a UVM report summary (or empty) and would give no reason.
- `make clean`/`make aclean` remove build artifacts; `make rclean` removes `*__run` result directories.
- `make ... FCOV=1` adds functional coverage (`script/common/cov.mk`): the `acov` step generates the coverage classes from the covergroups written in the sources (`` `ifdef ODVE_COV_NATIVE `` blocks + `` `odve_cov_create ``/`` `odve_cov_sample `` macros), and each run writes `<RUN_DIR>/cov.dump`. `make ... CCOV=1` turns on the simulator's code coverage (Verilator `--coverage` → `coverage.dat` per run; Questa `-cover`/`-coverage`, which ModelSim Starter refuses). `make cov [CCOV=1]` merges everything under the work dir into `cov/index.html`. All off by default; see `odve/doc/fcov-plan.md` and `comp/common/README`.
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
- executes jobs in parallel via `jobrunner.py` (`-max_jobs`/`-j`, default 4), printing each run's status line and `run.log` the moment that run finishes, then a summary table once all are done.

Each run's verdict comes from its own `<RUN_DIR>/run.log` (`runlog.py`): make must exit 0, the UVM report summary must be present, and `UVM_ERROR`/`UVM_FATAL` must both be 0; the last `UVM_ERROR`/`UVM_FATAL` message line is shown next to a failure. Every run gets `RUN_OPTS+=+UVM_MAX_QUIT_COUNT=1` (stop at the first UVM error) — `RUN_OPTS` is the Makefiles' run-switch variable, reaching `vsim` and the Verilator binary alike — unless the list entry or `-ropts` already carries `+UVM_MAX_QUIT_COUNT`, in which case that value is used instead. Other UVM plusargs go the same way: `-ropts="RUN_OPTS+=+UVM_VERBOSITY=UVM_HIGH"`. Because `RUN_OPTS` arrives on the make command line, agent Makefiles must add their own switches with `override RUN_OPTS += ...` (as `-batch` is), or make discards them. `-cov` builds and runs with `FCOV=1` and then writes `cov/index.html` (functional coverage, per-bin test attribution, holes) next to the run dirs, printing `functional cov: NN% (x/y bins)`; `-ccov` adds `CCOV=1` (Verilator code coverage into `cov/code/`; fails on ModelSim Starter by licence). `-quiet` prints only status lines; `-tail N` trims each log; `-exer` ("extract errors") re-reads every failed run's log after the summary and prints a block per failure:

```
TestName: apb_read (read_test)
ErrorMsg: UVM_FATAL @ 0: reporter [INVTST] Requested test ... not found.
Cmd     : make run RUN_DIR=apb_read TESTNAME=read_test RUN_OPTS+=+UVM_MAX_QUIT_COUNT=1
Log     : .../work/run/apb_read/run.log
```

`ErrorMsg` is the `ODVE_TIMEOUT` marker for a run killed on the clock, else the last `UVM_ERROR`/`UVM_FATAL` message, else the last tool-level error line. Per-run make variables reach the runner through `-ropts` too, e.g. `-ropts="TIMEOUT=30"`, or per entry in the list.

`script/regress/example.list` and `script/regress/comp.cfg` are references for the list/config format. Any `work/<variant>` folder has its own `regress.py`/`sourceme`, so the list name doesn't need to match the folder — e.g. `apb`'s `work/rlist/submit.list` (pre-push regression, run as `./regress.py submit` from `work/run` or `work/mini`) sits alongside `mini.list`.

## Architecture

### Repo layout (under `odve/`)

- `comp/agents/<protocol>/` — one UVM agent per protocol: `apb`, `axi`, `ahb`, `jtag`, `spi`, `uart`. **`apb` is the complete reference implementation** (agent + DUT + env/scoreboard + tests + coverage) to copy patterns from when building out another agent.
- `comp/common/` — shared base classes (`base/odve_common_base_item.sv`), macros (`macro/odve_macro.sv`: `` `odve_rand ``, `` `odve_cov_create ``, `` `odve_cov_sample ``) and the functional-coverage runtime (`cov/odve_cov_pkg.sv`: package-static counter store + base class of the generated groups; `cov/odve_cov_final.sv`: the `final` dump). See `comp/common/README`.
- `script/common/common.mk` — the single shared Make include behind every agent's `vrf/work/*/Makefile`. Defines the `prework/preuvm/auvm/predut/adut/pretb/atb/elib/run/clean/rclean/aclean` targets and the `FL_TB`/`FL_UVM`/`FL_DUT`/`TOP`/`TESTNAME`/`RUN_DIR`/`COMP_DIR` variables.
- `script/source/common_sourceme` — sets `ODVE_UVM`, locates the Questa install (`MS_HOME`) from `vsim` on `PATH` plus its bundled gcc (`MS_GCC_PATH`: MinGW on Windows, `gcc-*-linux` on Linux), and points `VERILATOR_ROOT` at the containerised Verilator in `script/verilator-docker/` (preset `VERILATOR_ROOT` yourself to use a native install instead).
- `script/verilator-docker/` — containerised Verilator: `setup.sh` (one-time image fetch, with OS/engine detection and an offline `--load` path) and `bin/verilator` (docker/podman shim used as `$VERILATOR_ROOT/bin/verilator`).
- `script/regress/` — the regression runner: `regress.py` (entry point), `readlist.py` (parses `*.list` files), `list2json.py` (converts parsed runs to job commands), `jobrunner.py` (parallel job execution), `list2json.py`.
- `script/cov/` — coverage tooling, standard library only: `covgen.py` (`scan` at build time under `FCOV=1`; `merge`/`report`/`codecov`/`analyze`/`export`/`env` after runs) over `covlib/` (model, filelist reader, covergroup-subset parser, generator, dump merge, UCIS-XML writer, lcov parser/renderer, reports; unit tests in `covlib/tests/`). Design and phases: `odve/doc/fcov-plan.md`.
- `script/schedule/`, `script/pdf/pdf2req/` — scheduling and requirements-doc tooling (early/placeholder).
- `svunit/svunit-3.38.1/` — vendored SVUnit for unit tests of SystemVerilog units outside a UVM testbench; `script/common/ut.mk` gives any `ut/` folder (`*_unit_test.sv` + `svunit.f`) a `make ut [VERILATOR=1]` target; `comp/common/cov/ut/` tests the coverage runtime this way.
- `uvm/` — vendored UVM library sources: `uvm-1.1d` (default, per `common_sourceme`) and `1800.2-2020-2.0` (available, not default). Used instead of relying on a simulator-provided UVM.
- `vip/` — placeholders for larger VIPs (`pcie`, `nvme`) mentioned in the README's roadmap; not yet implemented.

### Per-agent structure (the scaffold's layout; `apb` is the complete reference)

- `intf/` — the SystemVerilog interface (`odve_<proto>_if.sv`): signals as plain `logic` inside, `clk`/`rst_n` as ports; the DUT is wired to its members from `top`.
- `src/item/` — the sequence item + `odve_<proto>_item_pkg.sv`. No `rand`/constraints: values come from `user_randomize()` (plain `$urandom`), reached through `` `odve_rand(item) ``.
- `src/agent/` — `odve_<proto>_cfg.sv`, `odve_<proto>_sqr.sv`, `odve_<proto>_agent.sv`, `odve_<proto>_agent_pkg.sv`, with `mon/`, `mst/`, `slv/` for the monitor and the master/slave drivers. `cfg.role` selects master or slave; a slave is either autonomous (memory in its driver) or reactive (a slave sequencer with a request fifo and a responding sequence that owns the memory) — see `apb` (`+apb_slave=dut|mem|seq`). The agent package is also where the agent's **covergroup** lives (`` `ifdef ODVE_COV_NATIVE `` block at package scope, sampled by the monitor with `` `odve_cov_sample ``).
- `seq/` — sequences on the item plus `odve_<proto>_seq_lib_pkg.sv`.
- `list/` — compile filelists: `agent.f` (interface + item + agent packages, with `+incdir`s), `item.f`, `seq.f`.
- `reg/` — register-layer artifacts (scaffolding only).
- `vrf/` — the agent's own standalone verification environment:
  - `dut/dut.sv` — a minimal DUT (for `apb`: an APB3 slave register file).
  - `tb/top.sv` — clock/reset, the interface, the DUT, `odve_cov_final` under `ODVE_FCOV`, `uvm_config_db` of the `vif`, `run_test`.
  - `tb/env/` — `env.sv` (agent + `cc` + `scb`), `scb.sv` (reference model / checks), `cc.sv`, `env_pkg.sv`.
  - `tb/tests/` — `base_test.sv` (builds the env, `run_seq()` helper) plus scenario tests, aggregated by `test_pkg.sv`.
  - `list/fl_tb.f`, `fl_dut.f`, `fl_uvm.f` — per compile step; `fl_tb.f` lists the coverage runtime **before** `-f list/agent.f` because the monitor names `odve_cov_pkg::`.
  - `work/` — `common/` (shared Makefile + `Makefile.veri` + sourceme), `run/`, `mini/`, `rlist/*.list`.

New source files must be added to the correct `list/*.f` (agent) or `vrf/list/fl_*.f` (TB) — compilation is filelist-driven, not directory-scanned.

`apb` follows this layout and is the reference to copy patterns from. `axi` is a stub. When adding a **new** protocol agent, use the `vrf-new-agent` skill (`.claude/skills/vrf-new-agent/`), which scaffolds a working skeleton via `scripts/new_agent.sh <proto>` instead of hand-copying an existing agent.

### Compilation model

Questa compilation is split into separate libraries per layer — `uvm`, `dut`, `tb` — then elaborated and simulated in one step (`vsim tb.$(TOP) -L dut ...` at `make run`). This is why a new file is invisible to the build until it's added to the right filelist.

The UVM DPI library (`uvm_dpi.cc` → `build/uvm_dpi.o` → `uvm_dpi.dll`/`.so`, loaded by `vsim -sv_lib`) is built by `common.mk` with ModelSim's own gcc (`MS_GCC_PATH`) as a 32-bit object, since ModelSim Starter is 32-bit. `HOST_OS` picks the branch: `UVM_DPI_MODE=MS_WIN32` on Windows (links `win32aloem/mtipli.dll`), `MS_LINUX32` on Linux (`-m32`, links `linuxaloem/libmtipli.so`). `make uvm_dpi_o` / `make uvm_dpi` build the object / shared lib on their own; Verilator ignores all of this and compiles `uvm_dpi.cc` straight into `Vtop` (`Makefile.veri`).

### Environment variable conventions

- `ODVE` — absolute path to this framework's root (`odve/` inside this repo, or `<downstream>/odve/odve` when consumed as a submodule).
- `ODVE_<PROTO>` (e.g. `ODVE_APB`, `ODVE_AXI`) — absolute path to that protocol's agent directory, used inside its own filelists via `${ODVE_<PROTO>}/...`.
- `ODVE_UVM` — path to the vendored UVM library in use.
- `PROJ` — absolute path to the current agent, used as the default `VRF` base (`$(PROJ)/vrf`) in `common.mk`.

All of these are set by the relevant `sourceme` script — always `source sourceme` before running `make` in a `work/` directory.

## Consumers

Downstream repos (e.g. `amba-axi`) pull this repo in as a `odve` git submodule and build their own agent on top of `comp/common/` and `script/`. When changing shared scripts (`script/common/common.mk`, `script/source/common_sourceme`, `script/regress/*`), check for impact across all agents in `comp/agents/`, not just the one you're editing.
