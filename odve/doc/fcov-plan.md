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

Default build stays exactly as today: no defines, no collector, no coverage
flags. `regress.py -cov` adds `FCOV=1` to `-ropts` and runs the report step.

## 4. Formats

### 4.1 Coverage model — `cov/<block>_cov.yaml` (single source of truth)

```yaml
model: apb_cov                # becomes the covergroup type name
version: 1
points:
  - name: len                 # coverpoint
    type: int
    bins:
      - {name: len_1,   value: 1}
      - {name: len_2_4, range: [2, 4]}
      - {name: len_max, value: 255, at_least: 2}
      - {name: len_pow2, auto: [8, 16, 32, 64]}   # one bin per value
      - {name: up, transition: [1, 2, 4]}         # 1 => 2 => 4
    ignore:  [{name: len_0, value: 0}]
    illegal: [{name: len_bad, range: [256, 4095]}]
  - name: addr
    bins:
      - {name: lo, range: [0x0000, 0x7FFF]}
      - {name: hi, range: [0x8000, 0xFFFF]}
  - name: dir
    bins: [{name: rd, value: 0}, {name: wr, value: 1}]
crosses:
  - name: len_x_dir
    points: [len, dir]
    ignore: [{len: len_max, dir: rd}]  # cross filter by bin names
sample:                                 # signature of the generated sample()
  args: [len, addr, dir]
```

`covgen.py gen` produces, from this file:

- `odve_cov_<model>_pkg.sv` — IDs (`localparam int P_LEN = 1; ...`), the bin
  tables, `value2bin`, and class `odve_cov_<model>` extending
  `odve_cov_group` with `sample(int len, int addr, int dir)`;
- collector parameters (`NP`, `N`, `P_BASE[]`, `P_NBINS[]`);
- `covmap.json` — ID → name/kind/range/source line, cross composition, model
  hash (sha256 of the YAML) that every dump carries, so a stale map is
  detected instead of producing a wrong report.

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
| `../macro/odve_macro.sv` | ``odve_cov_sample(grp, args...)`` → expands to `grp.sample(args)` under `ODVE_FCOV`, to nothing otherwise |
| `ut/` | **svunit** tests of the collector (svunit is vendored and so far unused — first real consumer): counting, saturation, transition, cross index, checkpoint/final dump, reserved IDs |

### 5.2 `script/cov/covgen.py` — one tool, sub-commands

```
covgen.py gen      <model.yaml> -o <dir>              SV package + collector params + covmap.json
covgen.py check    <covmap.json> <dump>...            hash/version/truncation checks
covgen.py merge    <covmap.json> <dump>... -o cov.db.json   sum counts, per-bin test lists, per-test stats
covgen.py report   cov.db.json -o <dir> [--code-cov <lcov.info>|<coverage.dat>]
                                                       html (functional, + attribution page) / txt / json;
                                                       code-coverage HTML via genhtml when given; index.html
covgen.py analyze  cov.db.json [--holes] [--unique-per-test] [--min-tests] [--illegal]
covgen.py export   cov.db.json --format ucis-xml|pyucis-yaml|lcov
covgen.py env      --check | --setup                  the offline environment (§9)
```

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
| **2. Generator** | `covgen.py gen` + model YAML format (§4.1), `covmap.json`, hash | pytest on the generator; generated package lints on both simulators; a model with every bin kind |
| **3. Post-sim** | `merge`, `check`, `report`, `analyze`, `export`; `cov.mk`; `regress.py -cov` and the summary line | pytest with synthetic dumps; regression on both simulators producing `cov/index.html` |
| **4. Pilot** | `apb_cov.yaml`, collector in the apb env, `sample()` from monitor/scoreboard | `./regress.py submit -cov` on both simulators; attribution page shows `read_test` |
| **5. Docs & scaffold** | `comp/common/README`, `AGENTS.md`/`CLAUDE.md`, `vrf-workflow` skill section, `new_agent.sh` emits a `<proto>_cov.yaml` skeleton | scaffold a throwaway agent, build with `FCOV=1` |
| **6. Later** | APB adapter for emulation (same address layout); `ifdef VERILATOR` covergroup cross-check; trends across regressions; testplan mapping (`pyucis testplan`) | — |

Phases 1–3 can proceed in parallel after the spike; 4 needs all three.

## 9. Portability and offline release

The target environment may have no internet, so the release must carry
everything `covgen.py` needs — the same idea as `verilator-docker/prebuilt/`:

- `script/cov/requirements.txt` — pinned versions (`pyucis`, `pyyaml`, and
  their transitive dependencies, resolved once);
- `script/cov/pack.sh` (maintainers, online): `pip download` of every wheel
  for the supported targets (pure-Python wheels cover all; any binary wheel
  is downloaded for `manylinux_x86_64` **and** `win_amd64`), plus the lcov
  tarball (pure Perl) for `genhtml`, into `script/cov/prebuilt/`, committed;
- `covgen.py env --setup` (users, offline): creates `script/cov/.venv` with
  the host's `python3` and installs `--no-index --find-links prebuilt/`,
  writes `cov.env` next to it, which `common_sourceme` sources like
  `native.env`; `env --check` reports what is missing;
- everything else is the standard library; `merge`/`txt` never need the venv.

Python ≥ 3.9 is already a prerequisite of the framework. On Windows the flow
is Python-only, so it should just work — to be verified once, like the rest.

## 10. Risks and open questions

- **pyucis maturity**: broken CLI merge, YAML writer unimplemented, Verilator
  importer incomplete. Mitigation: use it through its Python API only, pin the
  version, keep `merge`/`txt` independent of it, and keep the door open for an
  own HTML renderer if its report stops being enough.
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
