# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

The imported `AGENTS.md` is the primary guide (repo purpose, commands, per-agent layout, env vars). Two project skills carry the operational detail and should be invoked, not paraphrased: `vrf-workflow` (compile/run/regress on both simulators; mandatory gate before commit and push of any `.sv`/`.f`/Makefile change) and `vrf-new-agent` (scaffold a new protocol agent via `scripts/new_agent.sh`). What follows are facts verified against the current Makefiles that the guide and skills gloss over or get wrong.

## Build model — what each target really does

- **Questa `make all` does not elaborate.** `ALL_CMD = prework preuvm auvm uvm_dpi predut adut pretb atb elib`; `elib` only creates `default__run/` and `vmap`s `work/tb/dut/uvm` into it. The `elab` (`vopt`) target exists in `script/common/common.mk` but nothing invokes it (and its recipe is broken — the `-l elab.log` line is not continued). Elaboration happens inside `vsim` during `make run`, so a Questa change is only proven by `make all run TESTNAME=<t>`, not by `make all`.
- `make lint` (Questa) = `LINT_CMD` = `ALL_CMD` minus `uvm_dpi` and `elib`. `make lint VERILATOR=1` = `verilator --lint-only` over `vrf/list/fl.f` (output in `work/<variant>/lint.log`).
- `VERILATOR=1` (or legacy `VERI=1`) makes `work/<variant>/Makefile` include `../common/Makefile.veri` instead of `../common/Makefile`; the two paths share nothing but `vrf/list/`. Verilator `make all` elaborates and compiles C++ into `obj_dir/Vtop` (minutes); `run` execs it and fails on nonzero `UVM_ERROR`/`UVM_FATAL` in `run.log`.
- Verilator support is per-agent: needs both `vrf/work/common/Makefile.veri` and `vrf/list/fl.f` (a flattened `-f` list of `fl_uvm.f`/`fl_dut.f`/`fl_tb.f`). Today only `apb` (UVM) and `uart` (plain SV, `ALL_CMD` overridden to skip UVM) have it.
- The Questa UVM DPI library is built from `uvm/uvm-1.1d/src/dpi/uvm_dpi.cc` by `common.mk` with the gcc ModelSim ships (`MS_GCC_PATH`, set by `common_sourceme`), never the host's: ModelSim Starter is 32-bit on both OSes. `HOST_OS` (`$(OS)`=`Windows_NT`, else `uname -s`) selects `UVM_DPI_MODE`: `MS_WIN32` → `uvm_dpi.dll` + `win32aloem/mtipli.dll` (MinGW gcc on `PATH`); `MS_LINUX32` → `uvm_dpi.so`, `-m32`, `-lmtipli` from `linuxaloem/` (`gcc-*-linux`, deliberately not on `PATH` so it doesn't shadow the g++ Verilator builds with). `make uvm_dpi_o` builds just `build/uvm_dpi.o` (a real file target, rebuilt only when a dpi source changes); `make uvm_dpi` links the shared lib, which `make run` loads via `-sv_lib`.
- `LINT_CMD` is derived from `ALL_CMD` (minus `uvm_dpi`/`elib`), so an agent that overrides `ALL_CMD` (uart) lints the same layers it builds.
- **Every `make run` is capped at `TIMEOUT` minutes** (default 180) by `script/common/timeout.mk`, included by `common.mk` and by each `Makefile.veri` so both simulator paths share it. `TIMEOUT=0` (or empty, or no `timeout` binary) means no cap; `GUI=1` also lifts it and switches vsim to interactive (`-gui`, `-batch`/`-c` filtered out of `RUN_OPTS`, no `quit` in `RUN_DO`). A killed run is `timeout`'s exit 124/137, and since such a log has no UVM summary — often nothing at all, when the kill lands during startup — the recipe appends `*** ODVE_TIMEOUT: killed after N min ...` to `run.log` (`CHECK_TIMEOUT`, or `CHECK_TIMEOUT_NOLOG` where the run keeps no log). That marker is the only reason such a run has, so don't remove it.

## Agent state (as of the current tree)

- `apb`: the only agent with a full UVM `vrf/`. Its `vrf/tb/tests/test_pkg.sv` includes **only `read_test`** (`write_test.sv`/`simple_test.sv` exist on disk but aren't included; there is no `base_test.sv`). `common.mk`'s default `TESTNAME=base_test` therefore fails — run `make run TESTNAME=read_test`. `top.sv` hardcodes `run_test("read_test")` for the Verilator no-`TESTNAME` case. `vrf/tb/env/env_pkg.sv` is empty.
- `apb`'s `src/` (`ocdve_apb_*` classes extending the nonexistent `ocdve_common_pkg`) is **not compiled by its own `vrf/`**: `list/agent.f` lists only `intf/apb_if.sv`. Adding `src/` to a filelist will break the build until those base classes exist.
- `axi`: has `intf/`, `src/`, `tb/` but no `vrf/work` — cannot be built with the standard flow. `ahb`, `jtag`, `spi`: README-only placeholders.
- `uart`: non-UVM; `vrf/work/common/Makefile` overrides `ALL_CMD`, `elib`, `prerun`, `run` to drop the `uvm` library and DPI. Only `work/run` exists (no `mini`/`rlist`).
- `vrf/work/rlist/*.list` for `apb` currently contains a single `read_test` entry in both `mini.list` and `submit.list`.

## Regression runner

`./regress.py <list> [-j N] [-no_comp] [-ropts="VAR=1 ..."] [-quiet] [-tail N] [-exer]` from any `work/<variant>/`. `-ropts` is appended to both the compile make and every run make, so `-ropts="VERILATOR=1"` builds and runs the same simulator. Regression run dirs are named after the list entry (`apb_read/`), not `<TESTNAME>__run/`. Verdicts are read from each run's `run.log` (`script/regress/runlog.py`), not make's exit code; logs stream as each job finishes and a summary table closes the run. Runs stop at the first UVM error: `regress.py` appends `RUN_OPTS+=+UVM_MAX_QUIT_COUNT=1` to each run unless the entry or `-ropts` already sets `+UVM_MAX_QUIT_COUNT`. Any UVM plusarg goes through `-ropts="RUN_OPTS+=..."`; there is no dedicated flag. Since `RUN_OPTS` comes from the command line, agent Makefiles must use `override RUN_OPTS += ...` for their own switches (`-batch`), or make silently drops them and vsim opens the GUI. `runlog.py` reads the `ODVE_TIMEOUT` marker before anything else (a truncated log's missing summary is a symptom, not the cause) and reports it as the verdict reason. `-exer` re-reads each failed run's log after the summary and prints `TestName:` / `ErrorMsg:` / `Cmd:` / `Log:` per failure, where `ErrorMsg` is the timeout marker, else the last `UVM_ERROR`/`UVM_FATAL` message, else the last `** Error`/`** Fatal`/`%Error` line.

## Environment setup

- `common_sourceme` derives `MS_HOME` from `vsim` on `PATH` (empty, silently, if absent — then every Questa target fails with empty paths; say Questa is unavailable rather than guessing).
- `VERILATOR_ROOT` resolution order: preset by you → `script/verilator-docker/native.env` (written by `setup.sh --native` or `--portable`, gitignored) → the container shim `script/verilator-docker/` (docker/podman/apptainer, pinned via `ODVE_CONTAINER_ENGINE`). `setup.sh --check` reports which is active.
- `ODVE_SVUNIT` points at the vendored `svunit/svunit-3.38.1/` for a planned per-unit `vrf/work/ut` flow; no agent uses it yet.

## Conventions

- Commit subjects use a `[+]` (add) / `[~]` (change) / `[-]` (remove) prefix; work happens on `feature/*`, `fix/*`, `docs/*` branches merged into `develop` via PR.
- `comp/agents/README.md` sets agent requirements that matter when writing SV: no `randomize()` (use `$urandom` — ModelSim SE has no constraint solver), no functional covergroups (code coverage only), and keep constructs Verilator-compatible.
- Never redefine `atb`/`adut`/`auvm`/`all`/`run` in a per-agent Makefile; override variables (`FL_*`, `ALL_CMD`, `TESTNAME`, `RUN_OPTS`) in `vrf/work/common/Makefile` and put framework-wide changes in `script/common/common.mk`.
