# Functional coverage without covergroups — design and implementation plan

Status: **plan, not yet implemented** (2026-09-27). Owner: open-dve maintainers.

## 1. Goal

A functional-coverage flow that is part of `comp/common/`, works identically on
the two simulators this framework targets — **Verilator** and the **free
ModelSim Starter Edition** — is reusable by every agent/VIP and downstream
project, is fully open (no licensed tool anywhere in the path), stores the
result in a standard, mergeable database, records **which test hit which
bin**, and produces **HTML reports** — all from a machine that may have no
internet access.

## 2. What the tools can actually do (measured on 2026-09-27)

Both claims the plan started from — "the free ModelSim has code coverage" and
"Verilator has no covergroups" — turned out to be wrong, so this table is the
ground the design stands on.

| | ModelSim Starter 20.1.1 | Verilator 5.052 |
| --- | --- | --- |
| code coverage | **no**: `vsim -coverage` → `This product is not licensed for Code Coverage`; the `vcover` binary is not even shipped | **yes**: `--coverage` (line/toggle/user); `verilator_coverage --write-info` → lcov `.info` → `genhtml` |
| `covergroup` | **no**: `vlog` compiles it, `vsim` then refuses to load the design — `Unable to checkout verification license ... covergroup is only supported with QuestaSim` | **collection yes**: `iff`, `ignore_bins`, `illegal_bins`, transition, wildcard, `option.at_least`, `cross`, `sample(args)` all compile and their bins land in `coverage.dat` with hit counts. **Queries no**: `get_coverage()` returns 0.0, per-coverpoint `get_coverage()` is `Unsupported` |
| database / merge | nothing (no UCDB without a licence) | its own `.dat`; `verilator_coverage -write` merges |

Consequences:

1. A single `covergroup` anywhere in the compiled sources stops ModelSim
   Starter from loading the design. The common library therefore **must not
   contain covergroups** (this is also the rule in `comp/agents/README.md`);
   Verilator's native covergroups are at most an `ifdef VERILATOR`
   cross-check, never the primary path.
2. "Merge the collector's toggle coverage with code coverage in ModelSim" is
   impossible on the free edition — there is no code coverage to merge into.
   It stays possible on a licensed Questa and costs nothing to keep open
   (§6.2), but the flow cannot depend on it.
3. The only portable path is **our own collection → a text dump → Python**.

The database/report layer exists already: **pyucis 0.2.0** (Apache-2.0,
Python API to the Accellera UCIS data model). Verified: it reads a simple
YAML (`covergroups → instances → coverpoints → bins{name,count}`, plus
`crosses`, `ignorebins`, `illegalbins`, `atleast`), converts it to **UCIS
XML** (the standard interchange format), and renders `txt`, `json` and a
**single-file interactive HTML** report; two databases merged through the
Python API (`ucis.merge.DbMerger`) summed their counts correctly. Caveats
found: the CLI `merge` sub-command is broken in 0.2.0 (`UnimplError`), and
its Verilator `coverage.dat` importer did not pick up covergroup bins. So
pyucis is used for **export and reporting**, while merging and test
attribution are ours (§5.4).

## 3. Design decisions

### 3.1 Collector, not covergroups (idea A) — kept, with changes

The coverage model is **bins as counters in a module** (`odve_cov_collector`),
driven through a SystemVerilog interface. Why this shape:

- needs nothing from the simulator: works on Starter, on Verilator, on
  anything;
- bins are signals, so a Verilator FST/VCD shows *when* a bin was first hit —
  something covergroups never give you;
- it is the only shape that survives **emulation**: the counters can live in
  the synthesizable part and be read back over a bus (`comp/agents/README.md`
  asks agents to run on HW accelerators).

Changes to the original sketch:

| Original idea | Decision | Reason |
| --- | --- | --- |
| interface = wires or an APB-like bus | a SystemVerilog **interface with a task**: `odve_cov_if.sample(pid, bin)` — zero-time call from UVM through a virtual interface. An APB adapter with the same address layout is an *optional* emulation path (§8, phase 6) | a bus protocol costs cycles and logic that simulation does not need |
| register = covergroup, bit = bin, value→bin done by wiring registers | value→bin is a **generic function driven by tables** (§3.4); the module only sees bin indices and counts | keeps the RTL constant-size and simulator-agnostic; one description drives class, module and report |
| 32-bit hit counter per bin | **`COVCNT=1` by default: one packed bit per bin** (hit / not hit). `COVCNT=32` stores 32-bit saturating counters, needed only for `at_least > 1` and for hit-count analysis | a bit vector is the smallest possible state and is all a "covered" verdict needs |
| crosses derived later by a script | crosses are counted **in the same sample call** as their coverpoints (`xbin = bin_a * NB_b + bin_b`) | a cross needs the fact of *simultaneous* sampling; separate counters cannot reconstruct it |
| — | transition bins keep `prev_bin` per coverpoint in the module; illegal bins raise `uvm_error` at sample time (option: count only) | covergroup semantics people expect |

### 3.2 UCIS (idea B) — used for the database format, not written from SV

The standard is **UCIS** (Accellera 1.0, 2012): a C API, an XML interchange
format and a data model; the tool's internal database is not specified. Free
tools do not implement the API, and we do not need it — the value is the
**XML interchange format**: an open, standard database that pyucis reads and
writes today and that commercial tools can import later. Writing UCIS XML
straight from SystemVerilog is rejected (verbose, history nodes, brittle);
the simulator writes a minimal line-based dump (§4.2) and Python converts.

**So: A for collection, B for the database. Not either/or.**

### 3.3 Names and addresses: names never enter the simulator

Only integer IDs travel through SV; every name lives in a map generated from a
single source of truth (§4.1). Address = ID:

```
bin address  = { pid[15:0], bin[15:0] }        widths are generator parameters
flat index   = P_BASE[pid] + bin                 index into the collector memory
pid 0 / bin 0xFFFF are reserved (invalid)        so a wrong ID is detectable
cross        = a point of its own; its bins are the product of its members
```

Alternatives considered and why they lost:

- *self-describing dump* (module registers names at time 0 with `$fwrite`):
  strings in SV, names duplicated in code, no emulation path;
- *hierarchical generate names* (`g_apb_rd.p_len.b_len_1.hit`) so a licensed
  tool's toggle report reads naturally: kept only as a **naming convention**
  for signals inside the generated class/interface — free, and useless on
  Starter.

### 3.4 Keeping generated code small (ModelSim Starter throttles above ~10k lines)

- the collector is **one parameterised module**: a memory of counters
  (`bit [W-1:0] cnt [0:N-1]`, or a packed `bit [N-1:0]` when `COVCNT=1`) plus
  `prev_bin[NP]` for transitions — its size does not depend on the model;
- bin definitions are **data, not code**: per-point tables
  `BIN_LO[]`, `BIN_HI[]`, `BIN_KIND[]` (value / range / wildcard / transition /
  ignore / illegal) as `localparam` arrays, and a single generic
  `value2bin(pid, value)` that scans that point's table. No generated `case`
  statements, no per-bin `generate` blocks;
- names, descriptions and source locations are in `covmap.json` only;
- the generated `sample(len, addr)` class methods are one line each (pack
  values, call the interface).

### 3.5 Nothing is collected unless asked (`FCOV=1` / `CCOV=1`)

Both are make variables in `script/common/cov.mk` (exists today, empty),
included by `common.mk` and by each `Makefile.veri` exactly like `run.mk`:

| Variable | Compile | Run |
| --- | --- | --- |
| `FCOV=1` | `+define+ODVE_FCOV +define+ODVE_COVCNT=$(COVCNT)`; the collector and the generated packages are on the filelist only under this define (``ifdef`` in the TB / a conditional `-f` in `fl_tb.f`); the sampling macro expands to nothing otherwise | `+odve_cov_dump=<RUN_DIR>/cov.dump +odve_cov_test=$(TESTNAME) +odve_cov_every=$(COVEVERY)` |
| `CCOV=1` | Verilator: `--coverage`; Questa: `-cover sbcefx3 -covercells` (today these vlog flags are passed **unconditionally** — they move under `CCOV=1`) | Verilator: `coverage.dat` per run; Questa: `-coverage` + `coverage save -onexit`, which on Starter fails loudly with the licence error — that is correct behaviour, not something to hide |
| `COVCNT=1\|32` | counter width, default 1 | — |
| `COVEVERY=N` | — | checkpoint dump every N samples, default 1 000 000; `0` = only at the end |

With `FCOV=1` the build gains one step before analysis: target `covgen`
(in `cov.mk`, a prerequisite of `atb` and of the Verilator `all`) runs
`covgen.py scan` over the filelists and writes `$(COMP_DIR)/cov/odve_cov_gen.svh`
+ `covmap.json`; `odve_cov_pkg.sv` includes that `.svh` under `ODVE_FCOV`
(`+incdir+$(COMP_DIR)/cov`). The step **never fails the build** on a model
problem (§4.1): it always writes a valid include, replacing anything it
could not understand by a stub and a warning.

Default build stays exactly as today: no defines, no collector, no coverage
flags. `regress.py -cov` adds `FCOV=1` to `-ropts` and runs the report step.

## 4. Formats

### 4.1 Coverage model — written in the SystemVerilog source, in covergroup syntax

The model lives **next to the code that samples it**, as a real covergroup in
standard syntax — no separate description file to keep in sync, nothing new
to learn, and the same text compiles natively where covergroups are
available. Two macros connect it to the portable path:

```systemverilog
// monitor / scoreboard / env - wherever the values are known
`ifdef ODVE_COV_NATIVE                      // licensed Questa, Verilator cross-check: the real thing
  covergroup apb_cg with function sample(int len, bit dir);
    cp_len: coverpoint len { bins one = {1}; bins some = {[2:4]}; bins big[] = {8, 16};
                             ignore_bins zero = {0}; illegal_bins bad = {[256:$]};
                             option.at_least = 1; }
    cp_dir: coverpoint dir iff (enabled);
    x_len_dir: cross cp_len, cp_dir;
  endgroup
`endif
`odve_cov_create(apb_cg)                    // the group object, named apb_cg_i
...
`odve_cov_sample(apb_cg, item.len, item.dir)   // positional = the sample() arguments
```

| mode | `` `odve_cov_create(apb_cg) `` expands to | `` `odve_cov_sample(apb_cg, a, b) `` |
| --- | --- | --- |
| default (no `FCOV`) | nothing | nothing — no collector, no cost |
| `FCOV=1` | `odve_cov_apb_cg apb_cg_i = new("apb_cg", this);` — the generated class | `apb_cg_i.sample(a, b)` |
| `ODVE_COV_NATIVE` | `apb_cg apb_cg_i = new();` — the covergroup itself | `apb_cg_i.sample(a, b)` |

Why an `` `ifdef `` block and not the body as a macro argument (the original
idea, `` `odve_cov_create(apb_cg, covergroup ... endgroup) ``): measured on
both tools, the preprocessor splits the body at the top-level comma of
`cross cp_len, cp_dir;` — Verilator: `Define passed too many arguments`,
vlog: `number of actual arguments (3) are not equal to the number of formal
arguments (2)` — and it does so even when the macro expands to nothing,
because arguments are parsed before expansion. The block form is clean on
both, and the compilers never see the body unless asked to.

**`covgen.py scan`** (the pre-compile step, §3.5) reads every file on the
filelists, finds the `ODVE_COV_NATIVE` blocks and the `create`/`sample`
macros, parses the covergroups and generates, per group:

- class `odve_cov_<name>` extending `odve_cov_group`, with `sample(<the
  declared arguments>)`; the IDs, the bin tables and `value2bin` of §3.4;
- the collector parameters and `covmap.json` (ID → name/kind/range,
  file:line, the covergroup source text for the report, model hash).

Supported subset in the first version (everything is standard SV, so a
model that passes here also compiles natively):

- `covergroup <name> with function sample(<typed args>)` — explicit
  sampling is required; clocking-event covergroups (`@(posedge clk)`) are
  not supported (warned);
- `coverpoint <arg> [iff (<arg>)]` where the expression is a sample argument;
- `bins b = { values, [lo:hi], ... }`, `bins b[] = { ... }` (one bin per
  value/range, named `b[value]` as Questa/Verilator do), `wildcard bins`,
  `ignore_bins`, `illegal_bins`, `default`;
- transition bins `bins t = (a => b => c)` (single sequence, no `[*n]`);
- `option.at_least`, `option.weight`;
- `cross a, b[, c]` with `ignore_bins x = binsof(a.b1) && binsof(b.b2)`.

Anything else — `with` clauses, `intersect`, repetition, expressions in
coverpoints, per-instance options — makes the whole group **unsupported**:
`scan` prints `[ODVE_COV] warning: covergroup apb_cg (file:line) skipped:
unsupported 'binsof ... intersect'`, generates a **stub** class whose
`sample()` does nothing (and warns once at run time), and exits 0. A
`sample` macro naming a group with no `create` gets a stub the same way.
The build is never broken by the coverage model; a script crash also leaves
a valid (empty) include behind, written first. Groups that are supported are
still collected, so partial models degrade gracefully.

Several instances of a component mean several objects of the same group
type: each registers its `get_full_name()` with `odve_cov_server` at
construction and gets an instance id; the dump carries `# inst <id> <path>`
lines and an instance column, so reports have both the per-type (merged)
and per-instance view that UCIS models.

A YAML form of the same model (`covgen.py gen model.yaml`) stays available
as an **optional** input for coverage that has no natural SV home (system
level, testplan-driven), and `scan --emit-yaml` writes the parsed model out
in it for inspection — both feed the same internal model object.

### 4.2 Run dump — `<RUN_DIR>/cov.dump`

```
# odve-cov 1
# model apb_cov hash 3f9a2c1e
# test read_test run apb_read seed 1 sim verilator covcnt 1
# samples 48213 checkpoint 3 final 1
1 0 1
1 2 1
3 5 3
```

`pid bin count`, **non-zero bins only**; `count` is 1 in `COVCNT=1` mode.
The header carries the test name, run name, seed and simulator — that is
where per-test attribution comes from. Written by the collector:

- at `final` (normal end), and
- as a **checkpoint every `COVEVERY` samples** (§7). A rewrite in place would
  lose both old and new data if the kill lands mid-write, and a rename
  (`$system("mv")`) is not portable — so checkpoints **alternate between
  `cov.dump.0` and `cov.dump.1`**, each ending with a `# end <seq>` line.
  `covgen.py` takes the file with the highest sequence number whose last line
  is that marker; a file without it is truncated and ignored. The `final`
  dump goes to `cov.dump` itself, which wins when present.

### 4.3 Merged database — `cov.db.json` (ours) + `cov.xml` (UCIS)

`cov.db.json` is what the reports read: per bin `count` and the **list of
tests that hit it**, per test its hit set, unique bins and contribution, the
model map, and the run headers. `cov.xml` is the same data exported through
pyucis (UCIS XML, history node per test) for interoperability; `cov.yaml`
(pyucis YAML) is emitted alongside for readability.

## 5. Components

### 5.1 `comp/common/cov/` (SystemVerilog)

| File | Contents |
| --- | --- |
| `odve_cov_if.sv` | interface: `task sample(int pid, int bin)`, `task sample_x(int xpid, int xbin)`, `task reset()`, `function int hits(pid, bin)`; carries the plusargs |
| `odve_cov_collector.sv` | the parameterised counter memory, `prev_bin[]`, saturation, checkpoint counter, `final` dump — generic, never edited per model |
| `odve_cov_pkg.sv` | base class `odve_cov_group` (holds the vif, `value2bin` call, illegal → `uvm_error`, `sample_x` for crosses, `covcnt` awareness); `odve_cov_server` singleton (vif registry keyed by model name, dump path from `+odve_cov_dump`) |
| `../macro/odve_macro.sv` | ``odve_cov_create(name)`` and ``odve_cov_sample(name, args...)`` with the three expansions of §4.1 (`sample` takes up to 8 positional arguments via macro defaults) |
| `$(COMP_DIR)/cov/odve_cov_gen.svh` | **generated** by `covgen.py scan` at build time, included by `odve_cov_pkg.sv` under `ODVE_FCOV`; never committed |
| `ut/` | **svunit** tests of the collector (svunit is vendored and so far unused — first real consumer): counting, saturation, transition, cross index, checkpoint/final dump, reserved IDs |

### 5.2 `script/cov/covgen.py` — one tool, sub-commands

```
covgen.py scan     -f <filelist>... -o <dir> [--emit-yaml]   pre-compile: parse covergroups from the sources,
                                                       generate odve_cov_gen.svh + covmap.json; stubs + warnings
                                                       for unsupported groups, never a non-zero exit on model errors
covgen.py gen      <model.yaml> -o <dir>              same output from the optional YAML form
covgen.py check    <covmap.json> <dump>...            hash/version/truncation checks
covgen.py merge    <covmap.json> <dump>... -o cov.db.json   sum counts, per-bin test lists, per-test stats
covgen.py report   cov.db.json -o <dir> [--code-cov <lcov.info>|<coverage.dat>]
                                                       html (functional, + attribution page) / txt / json;
                                                       code-coverage HTML via genhtml when given; index.html
covgen.py analyze  cov.db.json [--holes] [--unique-per-test] [--min-tests] [--illegal]
covgen.py export   cov.db.json --format ucis-xml|pyucis-yaml|lcov
covgen.py env      --check | --setup                  the offline environment (§9)
```

`scan` needs a filelist reader (nested `-f`, `+incdir+`, `${VAR}` expansion —
the same rules `vlog`/`verilator` apply) and a small recursive-descent parser
for the covergroup subset above; both are ours, standard library only.

Pure Python 3.9+. Third-party: `pyyaml`, `pyucis` (pinned); `jinja2` only if
the own HTML pages grow beyond string templates. Any of them missing must
degrade gracefully: `merge`/`analyze`/`txt` work with the standard library
alone, `export`/`html` say what is missing and how to run `covgen.py env`.

### 5.3 Make and regression integration

- `cov.mk`: the variables of §3.5; `make cov` = merge + report for the dumps
  under the current work dir; `make covhtml` opens nothing, just builds.
- `regress.py -cov`: adds `FCOV=1` to both compile and run `-ropts`, then
  after the summary table runs `covgen.py merge` + `report` into
  `work/<variant>/cov/` and prints one line, `functional cov: 63.2% (57/90
  bins, 3 illegal hits)`, plus the `cov/index.html` path. `-exer` gets the
  illegal-bin hits of a failed run in its `ErrorMsg` when that is the reason.
- A run killed by `TIMEOUT` (`run.mk`) still contributes its last checkpoint;
  the report marks such tests as *partial*.

### 5.4 Merging and test attribution (ours, not pyucis)

`merge` sums counts per bin across dumps and records the set of tests per bin
and the set of bins per test. From that: bins hit by exactly one test
(the test is irreplaceable), tests that add no new bin (candidates to drop
from `mini`), and the minimal test set covering the current hits (greedy).
pyucis then gets the merged counts and one history node per test for the XML.

## 6. Reports

### 6.1 Functional

`report` produces, in `cov/`:

- `cov.html` — pyucis single-file interactive report (verified working) —
  covergroup → coverpoint → bin percentages;
- `attribution.html` — ours: per bin the tests that hit it; per test its
  unique bins and contribution; the holes list; illegal hits with test names
  — the "which test covered which bit" view pyucis cannot give;
- `cov.txt`, `cov.json` for CI and for `regress.py`'s one-line summary;
- `index.html` linking everything, including code coverage when present.

### 6.2 Code coverage, where it exists

- Verilator (`CCOV=1`): `verilator_coverage --write-info` on the per-run
  `coverage.dat` files → `genhtml` → `cov/code/`; `index.html` links it.
- Licensed Questa: not in scope of this plan, but nothing here prevents the
  usual `vcover` flow, and the signal-naming convention (§3.3) makes the
  collector's toggle report readable there.
- ModelSim Starter: none, by licence. The report says so instead of showing an
  empty section.

Functional and code coverage are merged **at report level** (index + summary
JSON), not in one database: their formats and their availability differ per
simulator.

## 7. Memory and robustness

State kept in the simulator is **only the counters** — there is no event log,
so the footprint is constant and small:

| bins | `COVCNT=1` (packed bits) | `COVCNT=32` | `prev_bin` |
| --- | --- | --- | --- |
| 10 000 | 1.25 KB | 40 KB | 2 B × points |
| 100 000 | 12.5 KB | 400 KB | |
| 1 000 000 | 125 KB | 4 MB | |

(Verilator stores these exactly; ModelSim's unpacked arrays cost more per
element, which is why the 1-bit mode is a packed vector.) A "dump every 10 MB"
rule is therefore not needed: nothing accumulates.

What *does* need periodic dumping is **losing everything on a kill**: neither
Verilator nor ModelSim runs `final` when the process is killed by `TIMEOUT`
(`run.mk`, SIGTERM/SIGKILL) or crashes. Hence the checkpoint every
`COVEVERY` samples (default 1 000 000): rewriting a dump of 100k non-zero
bins is ~2.5 MB and milliseconds; the sample counter is deterministic and
needs no wall-clock/DPI. A time-based trigger (`$time`) can be added later;
wall-clock would need DPI and is not worth it.

Sampling cost: one function call and one table scan per point (bins per point
are few; a binary search over sorted ranges is a later optimisation), one
memory increment. No strings, no dynamic allocation.

## 8. Implementation phases

| Phase | Deliverable | Verified by |
| --- | --- | --- |
| **0. Spike** | hand-written collector for `apb` (2 points + 1 cross), `final` + checkpoint dump, 40-line converter, pyucis HTML | runs on both simulators; Verilator overhead measured; `final` under `$finish` from UVM confirmed on both; kill-by-`TIMEOUT` leaves a usable checkpoint |
| **1. Core** | `comp/common/cov/` (§5.1), macro, svunit tests | `make lint` and `make all run` on both simulators for apb with `FCOV=1` and without |
| **2. Parser + generator** | `covgen.py scan` (filelist reader, covergroup-subset parser, stub/warning policy) and `gen` (YAML form), `covmap.json`, hash; the `covgen` make target | pytest on parser and generator (every supported construct, and one unsupported per rule → stub + warning + exit 0); the generated package lints on both simulators; the same source compiled with `ODVE_COV_NATIVE` under Verilator as a cross-check |
| **3. Post-sim** | `merge`, `check`, `report`, `analyze`, `export`; `cov.mk`; `regress.py -cov` and the summary line | pytest with synthetic dumps; regression on both simulators producing `cov/index.html` |
| **4. Pilot** | `apb_cov.yaml`, collector in the apb env, `sample()` from monitor/scoreboard | `./regress.py submit -cov` on both simulators; attribution page shows `read_test` |
| **5. Docs & scaffold** | `comp/common/README`, `AGENTS.md`/`CLAUDE.md`, `vrf-workflow` skill section, `new_agent.sh` emits a `<proto>_cov.yaml` skeleton | scaffold a throwaway agent, build with `FCOV=1` |
| **6. Later** | APB adapter for emulation (same address layout); `ifdef VERILATOR` covergroup cross-check; trends across regressions; testplan mapping (`pyucis testplan`) | — |

Phases 1–3 can proceed in parallel after the spike; 4 needs all three.

## 8a. Phase 0 — spike results (2026-09-27)

Branch `feature/fcov-spike`. Hand-written collector + base package
(`comp/common/cov/`), a generated-style group class and map for `apb`
(`vrf/tb/cov/`), `cov.mk`, and `covgen.py merge`/`report`. Everything below
was run on this host, both simulators.

| Check | ModelSim Starter | Verilator 5.052 |
| --- | --- | --- |
| `make aclean all run FCOV=1` | OK, `UVM_ERROR 0` | OK, `UVM_ERROR 0` |
| `final` dump under UVM's `$finish` | written, 9/14 bins as the pattern predicts | identical dump |
| kill by `TIMEOUT` (0.02 min, `COVEVERY=1000`) | `final` skipped, checkpoints `cov.dump.0/1` (`# end 34/35`), merge takes 35 | same, merge takes checkpoint 699 |
| default build (no `FCOV`) `./regress.py submit` | PASS, build flags unchanged | PASS |
| `./regress.py submit -ropts="FCOV=1"` | PASS + complete dump | PASS + complete dump |
| `make lint` with and without `FCOV=1` | 0 errors | 0 errors |
| merge Questa + Verilator dumps → `cov.txt`, `attribution.html`, pyucis `cov.yaml` → `cov.xml` + `cov.html` | 64.3%, per-bin test lists, holes marked | |

Sampling cost (Verilator, 2 000 000 iterations of a `#1` loop, 3 runs each):
2.48 s without `FCOV`, 3.83 s with `FCOV=1` — 5.5 M `hit()` calls, 2 M
`sample()` calls each doing two table lookups and a cross: **~0.25 µs per
hit, ~0.7 µs per `sample()`**. Checkpoints every 100 000 hits (55 of them)
added 0.02 s. The relative figure looks large only because the loop body is
a bare `#1`; per transaction in a real TB it is noise.

Deviations from the design above, all kept for phase 1:

- **no interface at all**: the store (counters, `hit()`, dump, checkpoints) is
  package-static (`odve_cov_pkg::odve_cov_store`) — a plain static call from
  the group, no virtual interface, no `uvm_config_db`. The one thing a
  package cannot hold by the LRM is a `final` block, so `odve_cov_final` (a
  three-line module, one instance in top under `ODVE_FCOV`) writes the last
  dump. The emulation variant (phase 6) becomes a second store behind the
  same static API;
- **`sample` keeps its natural form**, `` `odve_cov_sample(cg, item.len, item.dir) ``:
  the macro accepts up to 8 values and fills the unused positions with the
  sentinel `odve_cov_pkg::NA`; a generated `sample()` declares its spare
  formals with that default, so the call is always complete and a value in
  a spare position is reported as an arity error (verified: `UVM_ERROR ...
  sample() called with an argument in position 3, but the covergroup
  declares fewer`);
- the `acov` step joins `ALL_CMD` only under `FCOV=1` and fills `$(COV_DIR)`
  (`build/cov`, `+incdir` absolute because vlog runs inside `build/`); for
  the spike it copies the hand-written stand-ins from `vrf/tb/cov/gen.spike/`,
  phase 1 replaces the copy with `covgen.py scan`;
- bin tables as `longint` dynamic arrays passed by `ref` to one generic
  `find_bin()` work on both tools — the "tables, not code" approach of §3.4
  holds;
- two tool traps met on the way: a comment beginning with `// Verilator ...`
  is parsed by Verilator as a pragma, and a trailing `# comment` on a make
  assignment leaves the blanks before it in the value.

### Phase 1 — done (2026-09-28, PR #16)

`covgen.py scan` replaced the hand-written stand-ins: the covergroup text
lives in the source (`ifdef ODVE_COV_NATIVE` block at package scope, as in
§4.1), `acov` parses it at build time and generates the class, the tables and
`covmap.json`. Delivered: `script/cov/covlib` (model, filelist reader with
`include expansion, covergroup-subset parser, generator; 34 unittest cases),
the runtime lookups `find_bin()` (value/range, wildcard, default) and
`find_trans()`, the stub policy end to end (a missing or unsupported group
builds, warns once at run time and is listed as skipped in the report), and
`merge`/`report` on covmap v2 (ignored cross bins out of the totals,
`at_least` decides "covered").

Verified on both simulators with apb's two covergroups — the second one
exercising transition, wildcard, default, `iff` and a cross filter: identical
dumps, **21/29 bins = 72.4 % exactly as hand-computed** (cp_tr 5/5, cp_w 2/3,
cp_en 2/2, x_w_en 3/5), default and `FCOV=1` `submit` PASS on both.

Not delivered from the phase-1 list: svunit tests of `odve_cov_store` — they
need the `vrf/work/ut` flow, which does not exist yet (tracked with phase 3).

### Phase 3 — done (2026-09-28)

`regress.py -cov` / `-ccov`, `make cov`, `covgen.py report` with the own
single-file `cov.html` (groups, bins, test attribution, holes, greedy minimal
test set, runs), `cov.xml` (own UCIS writer), `cov.yaml`, `index.html`;
`codecov` for Verilator's `coverage.dat` through `verilator_coverage
--write-info` and an own lcov renderer (`cov/code/`, UVM/std excluded by
default); `analyze --holes --tests --min`; `export`; `env`. `CCOV=1` moved
the formerly always-on `-cover sbcefx3 -covercells` under a switch and adds
`--coverage` / `-coverage`. Verified on both simulators: apb `submit -cov`
72.4 % on both, `-cov -ccov` on Verilator adds code coverage (lines 89.3 %,
167/187 over the six TB files), `-ccov` on ModelSim Starter fails the run
with the licence error, visible through `-exer`; default gates unchanged.
Left for later: illegal-hit counts in the store (today they are `UVM_ERROR`s
in the logs only), a time-based checkpoint trigger, and the svunit tests.

### Phase 4 — done (2026-09-28)

The pilot needed real traffic, and apb had none: its `src/` was a dead
draft. It is now a real agent in the scaffold's layout — APB3 interface,
item with `user_randomize()`, master driver, monitor, sequencer, sequences
(read / write / mixed, out-of-range addresses optional), an APB3 slave DUT
(16 registers, a wait state every third transfer, `pslverr` out of range),
an env with a scoreboard (register-file model) and three tests. The
covergroup `odve_apb_cg` (direction, address incl. out-of-range, `pslverr`,
direction transitions, direction × error cross) is declared **in the
agent's package** and sampled by its monitor — coverage travels with the
reusable component. `submit -cov`: 29/29 bins = 100 % on both simulators,
attribution per test, `analyze --min` shows `read_test` adds no bin over
`rw_test` + `write_test`. Found on the way: the repo's `` `odve_rand ``
macro was defined with a space before its parameter list (a macro without
parameters), unusable until now — fixed.

Follow-up (same day): the agent got a **slave role** with two modes —
autonomous (memory in the driver) and reactive (slave sequencer with a
request fifo, memory in the responding sequence `odve_apb_slv_mem_seq`) —
selectable per run with `+apb_slave=dut|mem|seq`; `submit` runs `rw_test`
against all three slaves, 100 % on both simulators. One trap: a component
named `req_fifo` under a `uvm_sequencer` collides with UVM 1.1d's own
`m_req_fifo` instance name (`CLDEXT` fatal).
Native mode (licensed tools compiling the blocks as covergroups) stays phase
6: it needs generated wrappers with the covergroup's own arity, and the
covergroup type is declared after `odve_cov_pkg` in compilation order.

### Phase 6a — unit tests of the runtime, done (2026-09-28)

The plan's phase-1 line item "svunit tests" needed a flow that did not
exist. Now: `script/common/ut.mk` turns any `ut/` folder holding
`*_unit_test.sv` and a `svunit.f` into `make ut` / `make ut VERILATOR=1`
(runSVUnit from the vendored SVUnit; `common_sourceme` exports
`SVUNIT_INSTALL` and puts its `bin` on `PATH`). `comp/common/cov/ut/` runs
nine tests over `odve_cov_store` (count, saturation at `COVCNT=4`,
out-of-range index → error and no write), `find_bin` (values, ranges,
ignore before coverage rows, illegal, wildcard care masks, default),
`find_trans` (a 3-deep history against two sequences), the dump (checkpoint
alternation `.1`/`.0` with `# end <seq>`, the final file line by line, no
files without `+odve_cov_dump`) and `init()`'s plusargs — 9/9 on both
simulators. To build the runtime without a UVM library it reports through
`` `ODVE_COV_ERR``/`` `ODVE_COV_WARN`` (`uvm_error`/`uvm_warning`, or
`$display` under `+define+ODVE_COV_NO_UVM`) and counts errors in
`odve_cov_pkg::odve_cov_errors`, which is what the tests assert on.
Found on the way: the vendored svunit scripts were not executable; plain
`vsim -c` fails with `Licensing failure` on ModelSim Starter here (the
agents already use `-batch` for that reason — `ut.mk` does too); Verilator
5.052 rejects two `foreach (x[i])` loops in different out-of-class methods
of `svunit_testsuite` (`Duplicate declaration of VARSCOPE ...
i__Vloopsize`) — one loop index renamed, marked `// odve:`.

### Phase 6b — emulation backend, done (2026-09-28)

`comp/common/cov/odve_cov_emu.sv`: the store's flat bin layout as
synthesizable logic — N saturating W-bit counters, a sample port (one index
per cycle), APB3 readback: counters at `4*i`, `NSAMPLES`/`N`/`W`/`CTRL` at
`0xFFF0..0xFFFC` (top of a 64 KiB window, so N can grow without moving
them; `CTRL` bit0 freeze, bit1 clear), `pslverr` elsewhere, writes to
counters ignored, no wait states. Host software on an emulator reads it
into the same `cov.dump` format; `covgen.py` needs no change (`# backend
emu` in the header is just another key). In simulation the apb TB puts the
block on the bus as a fourth slave (`+apb_slave=cov`), `odve_cov_emu_feed`
mirrors every `hit()` of the package store onto the sample port, and
`odve_apb_cov_emu_seq` — the readback as host software would do it —
compares every counter and `NSAMPLES` with the store and writes the run's
dump from the hardware; `cov_emu_test` is in `submit`, 200 samples / 29
bins / 0 mismatches on both simulators, and the merged coverage stays at
100 %. Found on the way: a sample hits several bins (five in apb), so the
one-per-clock port lags the traffic and the readback must poll the feed
queue empty before freezing — a fixed number of "drain" reads lost 116 of
200 samples. In an emulation build the feed is absent and synthesizable
monitors drive the port; that mapping (monitor → bin index tables) is not
built here.

Left in phase 6: native mode (c), to be scoped when a licensed simulator is
at hand.

## 9. Portability and offline release

Decided in phase 3, after measuring: `pyucis` drags in ~40 packages and
18 MB of wheels, six of them binary (lxml, cryptography, pydantic-core, ...),
per platform — vendoring that for offline hosts is not worth it for an XML
writer and an HTML page. So **`covgen.py` and `covlib` use the standard
library only** (Python ≥ 3.9): the UCIS 1.0 XML is written by our own
`covlib/ucisxml.py` (same element structure pyucis produces), the HTML by
`covlib/report.py` and `covlib/lcov.py` (the lcov `.info` renderer replaces
`genhtml`, so no Perl either). `pyucis` stays optional: when present
(`--pyucis` / `PYUCIS`), `report` adds its `cov_pyucis.html`. Nothing to
install, nothing to pack: `covgen.py env` reports what the host provides
(Python, `verilator_coverage` for `CCOV=1`, `pyucis` if any).

## 10. Risks and open questions

- **pyucis maturity**: broken CLI merge, YAML writer unimplemented, Verilator
  importer incomplete. Mitigation: use it through its Python API only, pin the
  version, keep `merge`/`txt` independent of it, and keep the door open for an
  own HTML renderer if its report stops being enough.
- **Parser subset**: the covergroup grammar is large; the first version
  covers the constructs of §4.1 and refuses the rest loudly. The stub policy
  keeps builds green, but a refused group is *silently absent* from the
  report unless the warning is read — `scan` therefore also writes the list
  of skipped groups into `covmap.json` and the HTML shows it.
- **`final` and checkpoint semantics on Starter**: `$fwrite` in `final` and
  file rewrite performance to be confirmed in the spike.
- **Huge crosses**: bins = product of members; the generator warns above a
  threshold and refuses above a hard limit, both configurable.
- **Sampling from several components at once**: the interface task is
  reentrant per call; no ordering issue since there is no protocol.
- **Model evolution**: a changed YAML changes the hash; old dumps are rejected
  by `check` — acceptable (re-run), but a rename-only change could be mapped
  by ID later.
- **Open**: should `FCOV=1` be on by default in `submit`? (Proposal: yes for
  `submit`, off for `run`/`mini`; decide after the pilot shows the overhead.)
