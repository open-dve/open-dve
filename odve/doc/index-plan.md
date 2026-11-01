# Code index for Verilog / SystemVerilog — investigation and plan

Status: **implemented for Linux** (decision 2026-11-01: Linux only, Windows
later) - phases 0-5 of §4 are in `script/index/` (see its README); phase 6
(slang-server editor config, LSP lane) and 7 are open. Measurements dated
2026-11-01, made on this host (Linux, Python 3.12, no root) against `apb`
and the downstream `pcie-vip` repo; §4 carries the results.

## 1. Goal

A fast, queryable index of an SV codebase that agents (Claude Code, Codex)
use **instead of reading source**: where a symbol is defined, who references
it, the elaborated DUT hierarchy, the testbench (UVM) hierarchy, what a
filelist compiles. Two layers, as the handoff proposes — Universal Ctags for
instant lookup over code that need not compile, slang for semantics over the
real filelists — both behind one MCP server, so a consumer repo that pulls
`odve` in as a submodule gets the tools, the scripts, the server and the
rules for free. Agents are told to go through the MCP first and to read raw
code only where a query points, or when a query fails; code an agent writes
must land in the index without a full re-index, through the agent saying
what it changed. Everything required lives in `odve`.

## 2. What was measured

### 2.1 Tools

| Tool | Version | Availability | Verdict |
| --- | --- | --- | --- |
| **Universal Ctags** | 6.2.0 | conda-forge (`micromamba create -c conda-forge universal-ctags`, works here); nightly static builds from `universal-ctags/ctags-nightly-build` for linux x86_64/aarch64 (1.7 MB `.tar.xz`) and macOS; Windows builds from `universal-ctags/ctags-win32`; not on this host by default | SystemVerilog parser has 31 kinds (module, interface, class, package, task, function, typedef, port, register, instance, define, covergroup, constraint, modport, …). Whole tree (`comp/`, `uvm-1.1d`, `svunit`; 250 k lines) → **0.3 s, 44 k tags**, JSON output. Blind to macros (`` `uvm_component_utils `` is a `define` in UVM, never expanded), no hierarchy, no references. |
| **pyslang** | 12.1.0 (2026-10-25) | PyPI, `abi3` wheels for Python ≥ 3.11: linux x86_64 4.6 MB, win_amd64 3.4 MB, linux aarch64, macOS; sdist 2 MB; installed here with `uv` into a scratch venv in seconds | `pyslang.driver.Driver` takes **our `.f` files as they are** (`-f`, nested `-f`, `+incdir+`, `+define+`, `${VAR}` expansion, `//` comments). apb + UVM 1.1d (`vrf/list/fl.f`, 250 k lines): parse 0.07 s, elaborate 0.01 s, full AST visit 0.19 s over 215 k nodes, **0 errors / 4 warnings**. pcie-v (341 k lines + UVM, 28 trees): parse 0.24 s, elaborate 0.05 s, visit 1.26 s over 1.56 M nodes, 26 instances, **2.4 s wall** including interpreter start. Gives: definitions with file:line, `NamedValueExpression.symbol` (reference → declaration, 40 k in apb), `InstanceSymbol.hierarchicalPath` + `definition`, `ClassType.baseClass`, call expressions, macro-expansion locations (`SourceManager.getExpansionLoc`), diagnostics. |
| **slang-server** | 0.3.1 (2026-10-19), MIT | GitHub release binaries: linux x64 5.0 MB, windows x64 3.1 MB, macOS 7.6 MB, arm64 variants; also Mason (Neovim) and the VS Code extension | LSP: diagnostics, hover, definition, references, rename, completion, inlay hints, `documentSymbol`. Config `.slang/server.json` (workspace, in git) + `.slang/local/server.json` (gitignored): `flags` (e.g. `-f tools/slang.f`), `build` (the `.f` to open), `builds`/`buildPattern` (globs, or a command that prints `.f` content), `index` (dirs/excludeDirs), `incdirs`, `env` (for `${ODVE}`-style paths). The HDL features — set top/filelist, browse the elaborated hierarchy, pick an instance — are VS Code commands; no LSP method for them is documented. The binary download could not be executed in this session (sandbox policy); nothing below depends on it. |
| Verible, tree-sitter/ast-grep, svls, veridian | — | — | Optional. Verible's kythe extractor only matters without a clean filelist, which every odve agent has. ast-grep structural queries are a later nicety. svls/veridian: skip, as the handoff says. |

### 2.2 What already exists to reuse

- `pcie-spec/kb/mcp_stdlib.py` (115 lines): a **stdlib-only MCP stdio
  server** (JSON-RPC 2.0, `initialize`/`tools/list`/`tools/call`, schemas
  derived from Python signatures) with a `mcp-server.sh` launcher that
  resolves the repo root from its own location, because `.mcp.json` expands
  only environment variables. Consumers already wire MCP servers this way
  (`pcie-vip/.mcp.json`, `amba-axi/.mcp.json`).
- `odve/script/cov/covlib/filelist.py`: the `.f` reader (nested `-f`,
  `+incdir+`, `+define+`, env vars, `` `include `` following) used by
  `covgen.py scan` — the filelist layer of the index starts from it.
- `odve/script/verilator-docker/setup.sh`: the pattern for external tools —
  fetch a pinned release once, `--check`, offline `--load`, nothing in git.
- `pcie-vip/.claude/hooks/{gate_commit.py,guard_rlist.py}` with
  `settings.json`: PreToolUse hooks in Python that gate `git commit` and
  guard list edits — the shape for the index hooks.

### 2.3 Consequences for the design

1. **A semantic re-index is seconds, not minutes**, at every scale this
   project has (0.3 s apb, 2.4 s pcie-v). Incrementality is therefore not
   "re-parse one file inside an elaboration" (pyslang cannot) but
   "re-elaborate only the units that contain the changed file, in the
   background, while the tag layer is already current". The unit is the
   filelist, which bounds the cost by construction.
2. **The filelist is the truth.** Both layers index the files the simulators
   compile — `vrf/list/fl*.f`, `list/agent.f` — not a directory scan, so
   vendored duplicates (`uvm-1.1d/docs/html/src/` holds a second copy of
   every UVM source: ctags found `uvm_component_utils` there) and dead files
   never pollute a result. Files outside every filelist are still tagged
   (git-tracked `*.sv*`), marked `unlisted`.
3. **slang-server is the editor layer, not the agent layer.** Its hierarchy
   features are not reachable over LSP, and an agent's definition/references
   queries are answered from the SQLite tables faster than through a spawned
   LSP round trip. The server gets a generated config so that a human in VS
   Code or Neovim sees the same filelists; an LSP lane in the MCP is optional
   and degrades to "not installed, use `sym_*`".
4. **Agents report *what changed*, not *what the index should contain*.**
   A tool that let an agent write symbol rows would drift from the code the
   moment the agent is wrong; a tool that takes paths and re-derives is as
   cheap (ms for tags, seconds for semantics) and cannot lie. "Put the info
   into the DB directly" is therefore `index_update(paths)` plus a hook that
   calls it on every Edit/Write — the agent's edit *is* the notification.

## 3. Architecture

```
                 .f filelists (vrf/list, list/)  +  sourceme env
                          │
   ┌──────────────────────┼────────────────────────────┐
   │ script/index/odve_index.py  (stdlib; pyslang optional)
   │   filelists  → units (fl, top, env, defines, ordered files)
   │   ctags      → tags          (per file, ms)          layer 1
   │   pyslang    → symbols, refs, instances, classes,    layer 2
   │                creates, diags (per unit, seconds)
   │   hashes     → files (path, sha1, mtime, unit membership, stale)
   └──────────────────────┼────────────────────────────┘
                          ▼
             <repo>/.odve-index/index.db   (SQLite, gitignored)
                          │
        ┌─────────────────┼──────────────────┐
        ▼                 ▼                  ▼
  mcp_server.py      odve_index.py CLI    .slang/server.json
  (stdlib MCP,       (same queries,        (generated; slang-server
   .mcp.json)         shell fallback)       for editors; LSP lane optional)
```

### 3.1 The database (`.odve-index/index.db`)

One SQLite file per repository root (the consumer's root when odve is a
submodule; the index covers odve's own agents too, since the consumer's
filelists reach into `odve/odve/...`). WAL mode, a lock file for writers.

| Table | Columns (abridged) | Source |
| --- | --- | --- |
| `files` | path (repo-relative, `/`), sha1, mtime, size, lang, `listed` (in ≥ 1 filelist), `tagged_at`, `elab_at` | hashing |
| `filelists` | path, kind (`fl`, `agent`, `seq`, `item`, `other`), env snapshot (`ODVE`, `ODVE_<PROTO>`, `PROJ`, `ODVE_UVM`) | `covlib.filelist` |
| `fl_entries` | filelist, ordinal, kind (`file`, `incdir`, `define`, `nested_f`, `flag`), value (expanded) | `covlib.filelist` |
| `units` | id, filelist, top, status (`ok`, `errors`, `dirty`, `no_pyslang`), parse_s, elab_s, node_count, built_at | `odve_index.py elab` |
| `tags` | name, kind, file, line, end_line, scope, scope_kind, signature, extras (`q` qualified) | ctags JSON |
| `symbols` | id, unit, name, kind (`module`, `interface`, `package`, `class`, `function`, `task`, `variable`, `net`, `port`, `parameter`, `typedef`, `enum_member`, `property`, `modport`, `covergroup`, …), file, line, col, parent_symbol, qualified name, decl_text (one line) | pyslang `Symbol` |
| `refs` | symbol_id, file, line, col, kind (`read`, `write`, `call`, `instantiate`, `import`, `extends`, `type`), via_macro (name or NULL) | `NamedValueExpression`, `HierarchicalValueExpression`, `CallExpression`, port connections, `ClassType.baseClass`, macro expansion loc |
| `instances` | unit, path (`top.dut_i`), parent_path, inst_name, definition (`dut`), def_file, def_line, params (text), is_interface | `InstanceSymbol` |
| `classes` | unit, name, package, base, file, line, is_virtual, is_param | `ClassType` |
| `creates` | unit, in_class, in_method, created_class, inst_name (the string literal), file, line | `X::type_id::create("name", this)` from the call's syntax (`node.type` only gives `uvm_component_registry::T`; the concrete class and the name come from the source text — tested) |
| `includes` | file, included_file, line | `SourceManager.getIncludedFrom`, ctags |
| `diags` | unit, severity, code, file, line, message | `Compilation.getAllDiagnostics` |

Sizes: apb ≈ 215 k nodes → ~60 k rows; pcie-v ≈ 1.56 M nodes → ~400 k rows,
tens of MB. Not a concern.

### 3.2 Layer 1 — tags

`ctags --languages=SystemVerilog,Verilog --langmap=SystemVerilog:+.svh
--extras=+q --fields=+nKSzZ --output-format=json -L <files>` over the file
set = union of all filelists ∪ git-tracked `*.sv/*.svh/*.v/*.vh`, minus
exclusions (`**/docs/**`, `work/*/build`, `obj_dir`, …; configurable).
Per-file re-tag on change (`-o - file`), milliseconds. Tags are what
`sym_find` answers from when no unit covers a file (unlisted code, code
that does not compile yet, a half-written agent).

### 3.3 Layer 2 — semantics per unit

A unit = (filelist, top, env). `odve_index.py elab <unit>` runs
`Driver.parseCommandLine("slang -f <fl> --top <top> ...")` with the env
from the agent's `sourceme` (the indexer sources it in a subshell and
captures `ODVE*`/`PROJ`), then one `root.visit(lookup_table)` keyed by node
kinds (the C++ side filters, Python sees only the kinds we store), filling
the tables above in one transaction per unit. Macro locations collapse to
the expansion site with `via_macro` set, so a reference inside
`` `uvm_component_utils `` is attributed to the class line that uses the
macro, not to `uvm_object_defines.svh`.

Unit discovery: every `vrf/list/fl.f` (flat, Verilator-style — exists for
every scaffolded agent) is a unit with `top` from the agent's Makefile
(`TOP`, default `top`); Questa-only agents get a synthetic flat list
(`fl_uvm.f` + `fl_dut.f` + `fl_tb.f`). Consumers can add units in
`.odve-index/units.json`.

Diagnostics are stored, never enforced: slang is stricter than Questa in
places and the simulators remain the gate (`vrf-workflow`). A unit with
errors still yields what elaborated (slang recovers), status `errors`.

### 3.4 Layer 3 — editor: slang-server

`odve_index.py slang-config` writes `.slang/server.json` for the repo:
`flags: "-f .odve-index/slang.f"` (a generated flat list of every unit, or
the chosen one), `env` from the sourceme snapshot, `index.dirs` = the
directories of listed files, `excludeDirs` for build output. A human then
gets hover/definition/references in VS Code/Neovim over the same files the
agent's index covers. Optional MCP lane: `lsp_definition`/`lsp_references`/
`lsp_hover` through a stdlib LSP client (Content-Length framing over stdio)
when `slang-server` is on PATH or in `.odve-index/tools/`; otherwise the
tool returns `{"error": "slang-server not installed", "use": "sym_def"}`.
This lane is phase 6 and can be dropped without loss for agents.

### 3.5 The MCP server

`odve/script/index/mcp_server.py` on a copy of `mcp_stdlib.py`
(`mcp` package optional, as in pcie-spec); launcher `mcp-server.sh`
resolves the repo root (the first ancestor with `.odve-index/` or `.git`)
and the venv/tools. Registration:

- Claude Code — consumer `.mcp.json`:
  `{"mcpServers": {"odve-index": {"type": "stdio", "command": "odve/odve/script/index/mcp-server.sh"}}}`
  (odve's own repo: `odve/script/index/mcp-server.sh`).
- Codex — `~/.codex/config.toml` / project `.codex/config.toml`:
  `[mcp_servers.odve-index] command = "odve/odve/script/index/mcp-server.sh"`.

Tools (all return compact JSON; every result carries `stale: [files]` when a
file's hash no longer matches the index, and `unit_status`):

| Tool | Arguments | Answers |
| --- | --- | --- |
| `index_status` | — | units, their status/age, counts, tool availability (ctags, pyslang, slang-server), what is stale |
| `index_update` | `paths[]`, `note?` | re-tag the files now; mark their units dirty and re-elaborate them (synchronously if ≤ 5 s expected, else in the background; the answer says which); `note` is stored in `log` — this is the "agent tells what it changed" entry point |
| `index_rebuild` | `units?` | full rebuild |
| `fl_list` | — | every filelist with kind, agent, size, nested lists |
| `fl_resolve` | `filelist`, `with_defines?` | ordered files, incdirs, defines — the compile view of a list without reading `.f` files by hand |
| `fl_of_file` | `path` | which filelists (and units) compile this file, and in what position |
| `sym_find` | `name`, `kind?`, `prefix?`, `unit?`, `limit?` | definitions by exact name or prefix: file:line, kind, scope, one-line declaration (tags + symbols merged, semantic rows first) |
| `sym_def` | `name`, `scope?` | the one definition (or the candidates), with `decl_text` |
| `sym_refs` | `name` or `symbol_id`, `kind?`, `file?`, `limit?` | references grouped by file with line and ref kind; `via_macro` when inside a macro |
| `sym_outline` | `path` | the file's declarations in order (modules, classes, methods, properties) with line ranges — the replacement for `cat file.sv` |
| `sym_members` | `name` | members of a class/package/module/interface: properties, methods, ports, parameters, with lines |
| `hier_tree` | `unit`, `root?`, `depth?` | the elaborated instance tree (path, definition, file:line, parameters) |
| `hier_instance` | `path` | one instance: definition, parent, children, port connections |
| `hier_of_module` | `definition` | every instance path of a module/interface across units |
| `tb_tree` | `unit`, `root_class?` | the UVM component tree as the code declares it: `creates` edges from `build_phase`s with instance names, plus the sequence classes started where visible |
| `class_info` | `name` | base chain, derived classes, package, factory registration, `creates` in and of it |
| `file_deps` | `path` | includes, imports, packages used, who includes it |
| `diag` | `unit`, `file?`, `severity?` | slang diagnostics for a unit/file (advisory) |
| `code_at` | `path`, `line`, `context?` | the lines around a location (so the agent never opens the whole file) |

Error convention: `{"error": "<what>", "fallback": "<the raw-code step to
take>"}` — e.g. `sym_def` on a name only ctags knows returns the tag with
`"semantic": false`; on a dirty unit the answer includes
`"stale": true, "hint": "index_update"`.

### 3.6 Incremental updates and agent-written code

1. **Hook** (`odve/script/index/hooks/post_edit.py`, registered in
   `.claude/settings.json` as `PostToolUse` on `Edit|Write|MultiEdit`): for
   a `.sv/.svh/.v/.vh/.f` path, run `odve_index.py update <path>` — re-tag
   (ms), rehash, mark units dirty, start a detached re-elaboration with a
   lock (a second edit while one runs queues one more). Never blocks the
   agent: exit 0 always, output on stderr.
2. **Tool** `index_update(paths, note)` for agents without hooks (Codex) and
   for bulk changes (a scaffolded agent: pass the directory).
3. **Staleness** by content hash on every query: a stale row is still
   returned (usually still right) but flagged, with `index_update` as the
   hint. A git checkout/branch switch is caught the same way; `index_status`
   lists what is stale, `index_update` with no paths refreshes everything
   stale.
4. **Filelist edits** (`.f`) re-resolve the list and re-elaborate its units;
   a new file that is in no list is tagged and reported `unlisted` — the
   usual mistake the `vrf-workflow` skill warns about becomes visible.
5. Elaboration runs with the env of the unit's `sourceme`; the snapshot is
   stored, and `index_status` warns when the live env differs.

### 3.7 Rules and skills for the agents

- `AGENTS.md`/`CLAUDE.md` rule (odve and the consumer template): *navigate
  SystemVerilog through the `odve-index` MCP (`sym_*`, `hier_*`, `tb_tree`,
  `fl_*`); read source only at the lines a result points to (`code_at`) or
  when a tool returns `error`; after writing or editing `.sv`/`.f` files,
  the hook updates the index — with Codex, call `index_update`.*
- Skill `sv-navigate` (`.claude/skills/sv-navigate/SKILL.md`): the query
  recipes (definition → references → hierarchy; "what does this filelist
  compile"; "who creates this component"; "what runs in `run_phase`"), the
  fallback ladder when a tool errors (tags → outline → `code_at` ranges →
  the file), and how to keep the index current.
- Skill `sv-raw-review`: rules for raw code when it is unavoidable — start
  from `sym_outline`, read ranges not files, never read `uvm/` sources (ask
  `sym_def`/`sym_members` for UVM classes), follow filelists not
  directories, report `index_status` staleness in the answer.
- Enforcement, soft: a `PreToolUse` hook on `Read`/`Bash` that warns (not
  blocks) when a `.sv` file of more than N lines, or anything under
  `uvm/`, is read while the index is fresh — the message names the tool to
  use. Blocking is a later decision; hooks cannot tell whether the MCP was
  tried first.

### 3.8 Portability — what lives in the repo

In git: `script/index/` (indexer, MCP server, stdlib MCP transport, hooks,
`setup.sh`, `requirements.lock` with `pyslang==12.1.0`, unit tests),
`doc/index-plan.md`, the skills, the `.mcp.json`/Codex snippets, a
`.slang/server.json` template. Not in git, fetched once by
`script/index/setup.sh` into `.odve-index/tools/` and `.odve-index/venv/`:

| Component | How `setup.sh` gets it | Offline | Without it |
| --- | --- | --- | --- |
| pyslang 12.1.0 | `uv` if present else `python3 -m venv` + `pip`, pinned | `--wheels <dir>` with the two wheels (8 MB for linux + windows) | tags-only index; `sym_refs`/`hier_*`/`tb_tree` answer `no_pyslang` |
| Universal Ctags ≥ 6.0 | system `ctags` on PATH if it is Universal and knows SystemVerilog; else conda-forge via `micromamba` if present; else the nightly static `.tar.xz` (linux/macOS) or `ctags-win32` zip, pinned by date and sha256 | `--tools <dir>` | semantic-only index; unlisted files invisible |
| slang-server 0.3.1 | `--editor`: release archive per platform, pinned, sha256 | same | no editor lane |

`setup.sh --check` prints the active tool per layer, the same style as
`verilator-docker/setup.sh --check`. `setup.sh --bundle out.tar` writes the
offline bundle for an air-gapped host. Decision for the user (§6): wheels in
git would make the index work on a fresh clone with no network at the cost
of 8 MB in history, which is what the coverage work decided against; the
plan assumes fetch + lock + bundle unless told otherwise.

Windows: out of scope for now (decided 2026-11-01). The tools have Windows
binaries and the code keeps paths repo-relative with `/`, so it is a
`setup.sh` port and a verification, not a redesign.

## 4. Implementation phases

| Phase | Deliverable | Verified by |
| --- | --- | --- |
| **0. Spike** (½ day) | the session's probes turned into `odve_index.py build` for apb: tags + one unit into SQLite, `sym_def`/`sym_refs`/`hier_tree`/`tb_tree` as CLI queries | numbers in §2 reproduced from the DB; `tb_tree` shows env → agt/agt_s/scb_o/cc_o, agt → mon/drv/sqr, with the instance names from `create("…")` |
| **1. Core** | `script/index/`: filelist units (on `covlib.filelist`), ctags layer, file hashing, SQLite schema + migrations, CLI (`build`, `update`, `status`, `query <tool> …`), `setup.sh` (pyslang venv, ctags), unit tests (stdlib `unittest`, synthetic `.f` + `.sv`) | `make index` in `odve/` builds apb + uart + the scaffold agent; `setup.sh --check` on a clone without tools reports degraded mode and the CLI still answers from tags |
| **2. Semantics** | pyslang extraction: symbols, refs (incl. macro attribution), instances, classes, creates, includes, diags; unit status; background re-elab with lock | apb: every reference of `cfg`/`vif`/`nregs` found with declaration lines (cf. probe: 40/54/5); pcie-v: build < 5 s, 26 instances; `sym_refs` of a UVM base-class method lists odve overrides |
| **3. MCP** | `mcp_server.py` + `mcp_stdlib.py` + `mcp-server.sh`, the tool set of §3.5, `.mcp.json` in odve, consumer snippet + Codex snippet in `AGENTS.md` | Claude Code lists the tools (`/mcp`); a scripted JSON-RPC session (unit test) exercises every tool; token measurement: answer "where is `odve_apb_cfg.nregs` used" with the MCP vs. with Grep/Read |
| **4. Incremental** | `index_update`, the PostToolUse hook, staleness on every query, `.f` edit handling, `units.json` for consumers | edit `odve_apb_mon.sv` through Claude Code → `sym_outline` reflects it within a second, `sym_refs` after the background elab; switch branches → `index_status` lists stale files |
| **5. Rules & skills** | `sv-navigate`, `sv-raw-review`, the `AGENTS.md`/`CLAUDE.md` rule, the soft warning hook; `vrf-new-agent` scaffold registers the new agent's unit | a fresh session asked three navigation questions uses the MCP and reads no file wholesale (transcript check); pcie-vip adopted: `.mcp.json` + hook, index built, questions answered |
| **6. Editor** | `slang-config` generator, `.slang/server.json` template, `setup.sh --editor`, optional `lsp_*` lane | VS Code with the slang extension resolves `odve_cov_pkg::odve_cov_store` across the apb filelist; `lsp_definition` agrees with `sym_def` on 20 samples |
| **7. Later** | ast-grep structural queries (`always_ff` without reset, `$display` in agents), Verible kythe for filelist-less trees, index of `rlist` tests → which test starts which sequence, query log analytics | — |

Phases 1–3 are one PR each; 0 is a branch that becomes 1.

### Results (2026-11-01)

Phases 0–5 landed in one PR (`feature/code-index`). Verified: `build` on
odve (2 units, 47 k tags, apb 1.9 s: 11 k symbols, 1.2 k references after
dropping library-internal ones, 4 instances, `tb_tree` base_test → env →
cc/cfg/agt/agt_s/scb → mon/drv/sqr with the `create("…")` names); on
pcie-vip as a consumer (4 units incl. the submodule's, 22 s, 127 MB,
`pcie-v` 53 k symbols / 255 k refs / 22 instances / 698 test classes under
`uvm_test`, 32 advisory slang errors); the MCP over JSON-RPC (19 tools);
`update` after an edit: stale → re-tag → sync elaboration 2 s, the hook
path detaches it; 8 unit tests on a synthetic agent. Changes against the
plan: references also come from member access, `new` and declared types
(a class otherwise had zero references); library-internal references are
not stored; the soft warning hook on raw reads is not implemented (the
rule lives in `AGENTS.md` and the skills); `covgen.py check`-style
staleness is per answer (`stale`, `dirty_units`), not a command.

## 5. Risks

- **pyslang API churn**: 12.x reorganised the package into `driver`/`ast`/
  `syntax` submodules (older docs show flat names). Pin the version; wrap
  the few calls used (`Driver`, `visit`, `SourceManager`) in one module.
- **slang strictness**: vendor code Questa accepts may error in slang; the
  compilation still elaborates most of it, the status says `errors`, the
  simulators stay the gate. UVM 1.1d compiled clean (0 errors).
- **Macro blindness of tags** (`` `uvm_*_utils ``, `` `odve_cov_create ``):
  covered by the semantic layer; `sym_find` says `"semantic": false` when
  only a tag answered.
- **Concurrency**: hooks and background elaboration write while the MCP
  reads — SQLite WAL + a writer lock; a query during a rebuild sees the old
  rows plus `rebuilding: true`.
- **Very large consumer designs** (vendor IP, millions of lines): a unit per
  filelist keeps each elaboration bounded; if one unit is still too slow,
  split by `-f` sub-lists or exclude the IP from semantics (tags only).
- **Hook cost**: the PostToolUse hook returns in milliseconds (tags) and
  defers elaboration; `timeout` set regardless.

## 6. Decisions for the user

1. Binaries/wheels: fetch + lock + offline bundle (assumed) vs. 8 MB of
   wheels in git.
2. Windows: supported by design, verified later (no Windows host here).
3. Index location: `<repo-root>/.odve-index/` (assumed) — one DB per
   consumer repo, including the odve submodule's agents.
4. Enforcement: warn (assumed) vs. block raw reads of large `.sv` files
   when the index is fresh.
5. Order: phases 0–3 first (the index and the MCP), 4–5 next, 6 when an
   editor user asks.
