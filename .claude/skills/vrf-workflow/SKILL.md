---
name: vrf-workflow
description: Compile and simulate UVM/SystemVerilog agent code with Questa/ModelSim after editing files under odve/comp/agents/*/src, intf, item, seq, or vrf, and gate git commit/push on it. Use this proactively any time you modify, add, or remove a .sv file under odve/comp/agents/ (agent sources, interfaces, sequences, testbench env/tests, DUT) to confirm the change still compiles and the relevant test(s) still pass — do not report SystemVerilog edits as done without running this. ALWAYS use this before running `git commit` (analyze + compile must be clean) or `git push` (submit regression must be clean) on SystemVerilog changes in this repo. Also use when the user asks to "compile", "run a test", "check compilation", "run regression", or "run submit/check/mini" for an agent. Also applies if editing shared framework code under odve/script or odve/comp/common — re-run this for at least one agent (e.g. apb) to confirm the shared change didn't break the build.
---

# VRF compile / run / regress workflow

This repo's verification agents are Questa/ModelSim UVM environments where **compilation is filelist-driven, not directory-scanned**. Editing or adding a `.sv` file is not enough by itself — you must also (a) make sure it's referenced by the right filelist if it's new, and (b) actually run the build to know whether it compiles. There is no separate "syntax check" step; compiling *is* the check.

## 0. Find the right agent and work folder

Each agent lives at `odve/comp/agents/<agent>/` (`apb` is the most complete and currently the only one with a working `vrf/` environment set up — check before assuming another agent like `ahb`/`jtag`/`spi`/`uart` has one yet). Its standalone verification environment is `odve/comp/agents/<agent>/vrf/`, and the build/run/regress workspace is `odve/comp/agents/<agent>/vrf/work/<variant>/`, where `<variant>` is one of:

- `run/` — everyday compile + simulate loop while iterating on code.
- `check/` or `submit/` — full regression, run before pushing.
- `mini/` — a smaller/faster regression subset.
- `common/` — not run directly; holds the shared `Makefile`/`sourceme` the other variants include.

If a change is only in `odve/script/` or `odve/comp/common/` (shared framework code, not agent-specific), still run this workflow for at least one agent afterward — those files are `include`d by every agent's build.

## 1. Source the environment (once per shell)

```bash
cd odve/comp/agents/<agent>/vrf/work/<variant>
source sourceme
```

This exports `ODVE`, `ODVE_<AGENT>`, and `PROJ` as absolute paths and pulls in `odve/script/source/common_sourceme` (sets `ODVE_UVM`, locates `MS_HOME` from `vsim` on `PATH`). If `vsim` isn't on `PATH` in this environment, `sourceme`/`make` will fail early — tell the user Questa/ModelSim isn't available rather than guessing at results.

## 2. Compile

```bash
make all
```

This runs `prework preuvm auvm uvm_dpi predut adut pretb atb elib` — compiles UVM, DUT, and TB into separate Questa libraries (`vlog`), then elaborates (`vopt`). **Read the actual output**, don't assume success from exit code alone: each `vlog`/`vopt` step prints a summary line like `Errors: 0, Warnings: 2` — any nonzero error count is a real compile failure to fix before moving on.

`auvm`/`adut`/`atb` are Questa's **analyze** steps — they run `vlog` (which "analyzes" HDL into a library) for the UVM, DUT, and TB layers respectively, and can be run individually if you only touched one layer (e.g. `make atb` after a testbench-only change). `elib`/`elab` is the separate **elaborate** step (`vopt`) that links the analyzed libraries together. A source file can analyze cleanly on its own yet still fail to elaborate (e.g. a missing class reference across packages) — `make all` (or the narrower `make <layer> elib`) is what proves both, so don't treat "analyze passed" alone as "compilation is ok."

If you added or removed a source file (not just edited an existing one), first check it's listed in the right filelist — otherwise it silently won't be compiled (or `vlog` will complain about a missing file):
- Agent-side files (`src/`, `item/`, `seq/`, `intf/`) → `odve/comp/agents/<agent>/list/*.f` (`agent.f`, `item.f`, `seq.f`).
- Testbench-side files (`vrf/tb/`, `vrf/dut/`) → `odve/comp/agents/<agent>/vrf/list/fl_tb.f` or `fl_dut.f`.

If you changed the interface used elsewhere or touched shared framework code (`odve/script/common/common.mk`, `odve/comp/common/`), run a clean rebuild instead of an incremental one:

```bash
make aclean all
```

## 3. Run a specific test

```bash
make TESTNAME=<test_name> run
```

`<test_name>` is a UVM test class from `vrf/tb/tests/` (e.g. `read_test`, `write_test`, `simple_test`; default is `base_test`). This invokes `vsim` with `+UVM_TESTNAME=$(TESTNAME)` and writes `run.log` under the run directory (`$(TESTNAME)__run/` by default). **Check the log's UVM report summary** (the `UVM_ERROR :` / `UVM_FATAL :` counts near the end) — a test can finish without a Questa error yet still have failed inside UVM.

Combine compile + run in one step during iteration:

```bash
make aclean all run TESTNAME=<test_name>
```

## 4. Run the full regression before pushing

Every `work/<variant>` folder (`run/`, `mini/`, and `check/` where it exists) has its own `regress.py`/`sourceme` — you don't need a dedicated folder per list name, the list name is just an argument:

```bash
cd odve/comp/agents/<agent>/vrf/work/run   # any variant folder works
source sourceme
./regress.py submit
```

`regress.py <name>` reads `work/rlist/<name>.list` (each line names a run with its own `TESTNAME`/`COMP_DIR`/`RUN_OPTS` overrides) and drives `odve/script/regress/regress.py`, which runs the jobs in parallel (default up to 4 at once). `submit` is the pre-push regression list (`work/rlist/submit.list`, alongside `mini.list`); confirm which list name the user means if unclear, and don't invent a new list name without checking `work/rlist/` first.

If a change touched `odve/script/regress/` itself (`regress.py`, `readlist.py`, `list2json.py`, `jobrunner.py`), test it against a real agent's `rlist/*.list` (e.g. `apb`) rather than reasoning about it in the abstract.

## 5. Gate on git commit and push

This is a hard sequence, not a suggestion — SystemVerilog changes are silently broken far more often than software changes, because there's no compiler running in the editor and no type system catching mistakes until `vlog` runs. Never skip a step because "it's a small change." This applies to changes under `odve/comp/agents/` and to shared framework changes under `odve/script/` or `odve/comp/common/` (verify against a real agent, e.g. `apb`).

**Before `git commit`** (any commit touching `.sv`/`.f`/`Makefile` files):
1. Run analyze on whatever layer(s) changed — `make atb` for testbench-only edits, `make adut` for DUT edits, `make auvm` if UVM library config changed, or just `make auvm adut atb` for all three. Fix every nonzero `Errors:` count.
2. Run `make all` (which includes `elib`) to confirm it elaborates too — analyze-clean doesn't mean elaborate-clean (see step 2). Only commit once this is clean.

**Before `git push`**:
3. Run the `submit` regression (step 4 above): `./regress.py submit` from a `work/<variant>` folder. Read the results for every job in the list, not just the last one — confirm each ran and passed (no `UVM_ERROR`/`UVM_FATAL`, no Questa `Errors:` > 0). If any job fails, fix it and re-run the full list before pushing; don't push on a partial regression.

If asked to commit/push and you haven't just run this sequence in the current conversation, run it first — don't rely on an earlier compile from before the latest edits.

## After running

Summarize what you ran (compile-only vs. specific test vs. regression), the pass/fail result from the log, and — if it failed — quote the specific error/UVM_ERROR lines rather than just saying "it failed." If compilation or simulation couldn't run at all (e.g. `vsim` missing), say so explicitly instead of reporting success.
