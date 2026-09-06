---
name: vrf-workflow
description: Compile and simulate UVM/SystemVerilog agent code with BOTH Questa/ModelSim and Verilator after editing files under odve/comp/agents/*/src, intf, item, seq, or vrf, and gate git commit/push on both. Use this proactively any time you modify, add, or remove a .sv file under odve/comp/agents/ (agent sources, interfaces, sequences, testbench env/tests, DUT) to confirm the change still compiles and the relevant test(s) still pass — do not report SystemVerilog edits as done without running this. ALWAYS use this before running `git commit` (analyze + compile must be clean on both simulators) or `git push` (submit regression must be clean on both simulators) on SystemVerilog changes in this repo. Also use when the user asks to "compile", "run a test", "check compilation", "run regression", or "run submit/check/mini" for an agent. Also applies if editing shared framework code under odve/script or odve/comp/common — re-run this for at least one agent (e.g. apb) to confirm the shared change didn't break the build.
---

# VRF compile / run / regress workflow

This repo's verification agents are UVM environments where **compilation is filelist-driven, not directory-scanned**. Editing or adding a `.sv` file is not enough by itself — you must also (a) make sure it's referenced by the right filelist if it's new, and (b) actually run the build to know whether it compiles. `make lint` (Questa: analyze only; `VERILATOR=1`: `verilator --lint-only`) is the fast first check, but it stops short of elaboration/C++ — only a real compile proves the change builds.

**Two simulators are supported and both must be checked.** Questa/ModelSim is the primary simulator; Verilator runs the same filelists via `VERILATOR=1`. They disagree often — Verilator is stricter (it has already caught real bugs Questa accepted, e.g. interface ports with no direction, and missing `+incdir+` for a package's own includes), while Questa supports constructs Verilator does not. **A change that compiles on one can fail on the other, so passing one is not evidence about the other.**

## 0. Find the right agent and work folder

Each agent lives at `odve/comp/agents/<agent>/` (`apb` is the most complete and currently the only one with a full `vrf/` UVM environment — check before assuming another agent like `ahb`/`jtag`/`spi`/`uart` has one). Its standalone verification environment is `odve/comp/agents/<agent>/vrf/`, and the build/run/regress workspace is `odve/comp/agents/<agent>/vrf/work/<variant>/`, where `<variant>` is one of:

- `run/` — everyday compile + simulate loop while iterating on code.
- `check/` or `submit/` — full regression, run before pushing.
- `mini/` — a smaller/faster regression subset.
- `common/` — not run directly; holds the shared `Makefile`/`Makefile.veri`/`sourceme` the other variants include.

If a change is only in `odve/script/` or `odve/comp/common/` (shared framework code, not agent-specific), still run this workflow for at least one agent afterward — those files are `include`d by every agent's build.

### Does this agent support Verilator?

Verilator support is per-agent, not automatic. An agent has it only if **both** exist:

- `vrf/work/common/Makefile.veri` — the Verilator build rules, and
- `vrf/list/fl.f` — the single flattened filelist Verilator consumes (Questa uses the separate `fl_uvm.f`/`fl_dut.f`/`fl_tb.f`).

Today that's `apb` (full UVM) and `uart` (non-UVM). If an agent lacks them, say so plainly rather than reporting a Verilator pass that never ran — and don't hand-roll a one-off `verilator` invocation as a substitute, since it won't match what the Makefile does.

## 1. Source the environment (once per shell)

```bash
cd odve/comp/agents/<agent>/vrf/work/<variant>
source sourceme
```

Exports `ODVE`, `ODVE_<AGENT>`, `PROJ`, and pulls in `odve/script/source/common_sourceme` (sets `ODVE_UVM`, locates `MS_HOME` from `vsim` on `PATH`, and points `VERILATOR_ROOT` at the containerised Verilator in `odve/script/verilator-docker/`).

**Verilator prerequisite:** one of three installs, all managed by `odve/script/verilator-docker/setup.sh` (`--check` reports which is active): the container image (docker/podman/apptainer), `--native` (conda-forge under `$HOME`, no root), or `--portable` (the tarball vendored in `prebuilt/`, no root, no network). A native/portable install writes `native.env`, which `sourceme` picks up automatically. If `make ... VERILATOR=1` complains, run `setup.sh --check` first and follow what it says.

**Questa prerequisite:** `vsim` on `PATH`. If it isn't, say Questa isn't available rather than guessing at results.

### Know which simulators actually work *in this environment* before promising both

Check, don't assume — and report per-simulator rather than collapsing to one verdict:

- **WSL:** Verilator works. Questa often does **not**, even when `vsim` resolves: a Windows ModelSim binary cannot read WSL paths, and the build dies with `Failed to open -f file "/mnt/c/..."`. Questa needs Windows-native `C:/...` paths, i.e. run it from **Git Bash on Windows**, not WSL.
- **Git Bash on Windows:** Questa works. Verilator works if Docker Desktop is running.
- **Native Linux:** Verilator works; Questa works if a Linux Questa is installed.

If you can only run one simulator, run it, then **explicitly state that the other was not verified and why**. Never imply both passed when only one ran.

## 2. Compile

**Questa:**
```bash
make all
```
Runs `prework preuvm auvm uvm_dpi predut adut pretb atb elib` — compiles UVM, DUT and TB into separate Questa libraries (`vlog`), then elaborates (`vopt`). **Read the actual output**; each `vlog`/`vopt` step prints `Errors: N, Warnings: M` and any nonzero error count is a real failure.

`make lint` runs just the analyze steps for all three layers (`LINT_CMD` in `common.mk`: `ALL_CMD` minus `uvm_dpi` and `elib`) — the Questa counterpart of the Verilator lint below, and the quickest first check after an edit. `auvm`/`adut`/`atb` are those **analyze** steps (`vlog`) for the UVM, DUT and TB layers, runnable individually if you only touched one layer (e.g. `make atb` after a testbench-only edit). `elib`/`elab` is the separate **elaborate** step (`vopt`) that links them. A file can analyze cleanly yet fail to elaborate (e.g. a missing cross-package class reference), so don't treat "analyze passed" as "compilation is ok."

**Verilator — lint first, then build:**
```bash
make lint VERILATOR=1       # seconds: parse + elaborate only, no C++
make all VERILATOR=1        # minutes: the real build (VERI=1 is an equivalent legacy spelling)
```
`make lint` is `verilator --lint-only` over the same `fl.f` and the same warning policy as `all`, so it is exactly the front half of the build: a typo, an undeclared identifier, a missing `+incdir+`, a width or port mismatch all surface here in a few seconds. The terminal prints each `%Error` block and a `lint: N error(s), M warning(s)` line; the full output is in `work/<variant>/lint.log`. **Loop on lint until it reports 0 errors before spending minutes on `make all`** — but a clean lint is not a passing build (nothing is compiled or run), so it never replaces the steps below.

`make all VERILATOR=1` is one step: elaborates and compiles the generated C++ into `obj_dir/Vtop`. It is slower than Questa (several minutes — it compiles all of UVM through g++), so expect the wait and don't kill it early. Warnings are non-fatal by design (`-Wno-fatal`), because the vendored UVM 1.1d and the existing TB trip width/pin warnings that are not worth failing on — so **read the output for `%Error:` lines specifically**; a nonzero exit is the reliable signal.

If you added or removed a source file (not just edited one), check it's in the right filelist or it silently won't compile:
- Agent-side (`src/`, `item/`, `seq/`, `intf/`) → `odve/comp/agents/<agent>/list/*.f`.
- Testbench-side (`vrf/tb/`, `vrf/dut/`) → `vrf/list/fl_tb.f` / `fl_dut.f`.
- **And for Verilator:** confirm `vrf/list/fl.f` still pulls in the filelist you changed — it's a separate entry point, so a file added only to `fl_tb.f` is picked up by both, but a restructure of the `fl_*.f` files can silently drop Verilator coverage.

After interface changes or shared-framework edits (`script/common/common.mk`, `comp/common/`), rebuild clean rather than incrementally:

```bash
make aclean all              # Questa
make aclean all VERILATOR=1  # Verilator
```

## 3. Run a specific test

```bash
make TESTNAME=<test_name> run                # Questa
make TESTNAME=<test_name> run VERILATOR=1    # Verilator
```

`<test_name>` is a UVM test class from `vrf/tb/tests/` (default under Questa is `base_test`). Both paths pass `+UVM_TESTNAME=<name>` and write `run.log` into a per-test run directory (`<TESTNAME>__run/`, or `RUN_DIR` if set).

**Check the UVM report summary in the log** (`UVM_ERROR :` / `UVM_FATAL :` near the end) — a test can exit 0 at the tool level and still have failed inside UVM. The Verilator `run` target additionally greps the log and fails the make target on nonzero `UVM_ERROR`/`UVM_FATAL`, but confirm the numbers yourself rather than trusting exit code alone.

**Watch for the silent-wrong-test trap.** With no `TESTNAME`, the Verilator path runs whatever `top.sv`'s `run_test()` call hardcodes rather than a named test. So a run can look green while exercising something other than what you asked for. Confirm the log's `Running test <name>...` line matches the test you intended — if you passed a `TESTNAME` and the log names a different test, treat it as a failure, not a pass.

Combine compile + run while iterating:

```bash
make aclean all run TESTNAME=<test_name>                # Questa
make aclean all run TESTNAME=<test_name> VERILATOR=1    # Verilator
```

## 4. Run the full regression before pushing — on both simulators

Every `work/<variant>` folder has its own `regress.py`/`sourceme`; the list name is just an argument:

```bash
cd odve/comp/agents/<agent>/vrf/work/run
source sourceme

./regress.py submit                        # Questa
./regress.py submit -ropts="VERILATOR=1"   # Verilator, same list
```

`-ropts` appends make variables to **both** the compile job and every run job, so the list is built and run with the same simulator. (Omitting it from the compile would build with Questa and run with Verilator.) Anything else make accepts works too, e.g. `-ropts="VERILATOR=1 NPROC=8"`.

`regress.py <name>` reads `work/rlist/<name>.list` (each line names a run with its own `TESTNAME`/`COMP_DIR`/`RUN_OPTS` overrides) and drives `odve/script/regress/regress.py`, running jobs in parallel (default 4, `-max_jobs` to change). `submit` is the pre-push list; confirm which list the user means if unclear, and check `work/rlist/` before inventing a name. `-no_comp` reuses an existing build — useful when iterating, but never for the final pre-push run.

Read the per-job results, not just the exit code: `regress.py` fails the run if any job returns nonzero **or** reports `UVM_ERROR`/`UVM_FATAL`, and prints each job's captured output. Confirm every job in the list actually ran.

Regression output lands in `RUN_DIR` named after the list entry (e.g. `apb_read/`), not `<TESTNAME>__run/`.

If you changed `odve/script/regress/` itself (`regress.py`, `readlist.py`, `list2json.py`, `jobrunner.py`), exercise it against a real list (e.g. `apb`'s `submit`) **under both simulators**, since `-ropts` and the command construction affect both.

## 5. Gate on git commit and push

A hard sequence, not a suggestion — SystemVerilog breaks silently far more often than software, because nothing checks it until `vlog`/`verilator` runs. Never skip a step because "it's a small change." Applies to `odve/comp/agents/` and to shared framework changes under `odve/script/` or `odve/comp/common/` (verify against a real agent, e.g. `apb`).

**Before `git commit`** (any commit touching `.sv`/`.f`/`Makefile`/regress scripts):
1. Questa: analyze the changed layer(s) — `make atb` / `make adut` / `make auvm`, or `make auvm adut atb`. Fix every nonzero `Errors:` count.
2. Questa: `make all` (includes `elib`) to prove it elaborates too.
3. Verilator: `make lint VERILATOR=1` until 0 errors, then `make all VERILATOR=1` — for any agent that supports it (see §0). This is the step most likely to surface a real defect, since Verilator is the stricter of the two; lint gets you the verdict in seconds, `all` proves it.

**Before `git push`**:
4. `./regress.py submit` (Questa) **and** `./regress.py submit -ropts="VERILATOR=1"` (Verilator). Both must be clean. Fix and re-run the **full** list on both before pushing; never push on a partial regression or on one simulator's result alone.

If a simulator genuinely cannot run in the current environment (see §1), do not silently skip it — run what you can, and tell the user which simulator went unverified and why, so they can run it where it works before merging.

If asked to commit/push and you haven't just run this sequence in the current conversation, run it first — don't rely on a compile from before the latest edits.

## After running

Summarize **per simulator**: what you ran (compile-only vs. specific test vs. regression) and the pass/fail result from the log. If something failed, quote the specific `%Error:` / `Errors: N` / `UVM_ERROR` lines rather than saying "it failed." If a simulator couldn't run at all, say so explicitly instead of reporting success or quietly omitting it.
