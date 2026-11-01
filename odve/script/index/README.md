# script/index - the code index (ctags + slang) and its MCP server

A queryable index of a Verilog/SystemVerilog repository for agents and
humans: where a symbol is defined, who references it, what a file declares,
the elaborated instance tree of each testbench, the UVM component tree, what
a filelist compiles. Design and measurements: `doc/index-plan.md`. Linux.

```
script/index/
  odve_index.py      CLI: build | update | elab | status | units | query <tool> | hook | serve
  mcp_server.py      the `odve-index` MCP server (19 tools), stdio, standard library only
  mcp-server.sh      launcher for .mcp.json / Codex: finds the repo root and the venv
  mcp_stdlib.py      the minimal MCP transport (same as pcie-spec/kb)
  setup.sh           one-time tools: venv with pyslang (requirements.lock), Universal Ctags;
                     --bundle/--release installs the portable bundle offline
  release.py         builds the portable bundle (wheels for CPython 3.12 + pip + ctags, sha256
                     manifest) from tools.lock/requirements.lock; --upload attaches it to a GitHub release
  tools.lock         pinned versions: Python tag, pip, ctags build + sha256, the release URL
  bundle/            the bundle itself (8 MB tarball + .sha256), tracked in git: a fresh clone
                     sets up with no network; setup.sh uses it by default on Python 3.12
  idxlib/            repo.py (root, units, filelists, tools), tags.py (ctags), semantic.py (pyslang),
                     build.py (build/update/elab), queries.py (the tools), db.py (schema)
  tests/             python3 -m unittest discover -s tests   (11 tests; semantic ones need pyslang)
```

## Setup (once per clone)

```bash
odve/script/index/setup.sh            # -> <root>/.odve-index/{venv,tools}; --check to see what is active
odve/script/index/odve_index.py build # units from every comp/agents/*/vrf/list/fl.f, tags, elaboration
odve/script/index/odve_index.py units
```

`setup.sh` makes a venv with `pyslang==12.1.0` + `nanobind-backend==1.0.0`
(uv if present, else venv+pip; `--wheels DIR` offline) and gets a Universal
Ctags when none is on PATH (conda-forge via micromamba if present, else the
pinned static build from `ctags-nightly-build`, sha256-checked; `--tools DIR`
offline). Nothing is vendored in git. Without pyslang the tag layer and every
query still work; units report `no_pyslang`. Without ctags only files of
elaborated units are known.

### Portable bundle (no network, no pip on the target)

```bash
odve/script/index/setup.sh                        # Python 3.12: installs from bundle/ in git, no network
odve/script/index/setup.sh --online               # ignore the in-repo bundle (PyPI, conda-forge/ctags download)
odve/script/index/setup.sh --bundle <tarball|dir|URL> [--python python3.12]   # another bundle
odve/script/index/setup.sh --release              # fetch the bundle pinned in tools.lock (RELEASE_URL)
odve/script/index/release.py                      # rebuild bundle/odve-index-tools-<ver>-cp312-linux-x86_64.tar.gz
odve/script/index/release.py --check <tarball>    # verify its MANIFEST.sha256
```

The bundle holds the wheels (pyslang abi3, nanobind-backend cp312, pip) and
the ctags static build with a manifest; Python itself is not in it. It is
built for **CPython 3.12** (any patch level, 3.12.1 included - the
nanobind-backend wheel is per minor) on linux x86_64 with glibc >= 2.27, and
`setup.sh --bundle` refuses a different interpreter (pass `--python`). The
target needs only python3.12 with its `venv` module (no `ensurepip`: the venv
is made `--without-pip` and pip is installed from its own wheel), bash, tar,
xz. `release.py` is standard library only: wheels are resolved through the
PyPI JSON API for cp312/manylinux and verified against PyPI's sha256, ctags
against the sha256 in `tools.lock`; the tarball is byte-reproducible (fixed
mtimes/owners, no gzip timestamp), so a rebuild without a version bump is a
no-op in git. `release.py --upload` creates the GitHub release
`index-tools-<ver>` in `RELEASE_REPO` (token from `$GITHUB_TOKEN` or
`--token-file`; `--replace` to re-attach). Bumping a tool: edit
`tools.lock`/`requirements.lock`, bump `RELEASE_VER`, `release.py` (writes
the new tarball into `bundle/`; delete the old one), commit, `--upload`.

The root is `ODVE_INDEX_ROOT`, else the nearest ancestor of the cwd with
`.odve-index/`, else the nearest `.git`. In a consumer repository that is the
consumer's root: one index covers its agents and the odve submodule's.

## The layers

- **Tags** (`tags` table): `ctags --output-format=json` over every file any
  filelist compiles plus every git-tracked HDL file (walk when not a git
  repo), minus `excludes` (`/docs/`, `/work/`, `/build/`, `/obj_dir/`, ...).
  Per-file re-tag on change: milliseconds. Tolerates code that does not
  compile; blind to macros and hierarchy.
- **Units** (`units`, `filelists`, `fl_entries`): one per
  `comp/agents/<proto>/vrf/list/fl.f` found under the root (`odve:<proto>`
  for the submodule's), `top` from `vrf/work/common/Makefile` (`TOP`, default
  `top`), environment from the agent's `vrf/work/run/sourceme` run in a
  subshell (`ODVE*`, `PROJ`). More units: `.odve-index/config.json`
  `{"units": [{"name": ..., "filelist": ..., "top": ..., "sourceme": ...}]}`.
- **Semantics** (`symbols`, `refs`, `instances`, `classes`, `creates`,
  `diags`): pyslang `Driver` on the unit's `.f` as it is (`-f` nesting,
  `+incdir+`, `+define+`, `${VAR}`), one AST visit. References come from
  named-value, member-access, call, `new` and declared-type expressions;
  locations inside macros are mapped to the expansion site with `via_macro`
  (so `` `uvm_component_utils `` members sit on the class line). References
  between two library files (`library_paths`, default UVM and svunit) are
  not stored - they were most of the rows and nobody asks for them.
  `type_id::create("name", this)` calls become `creates` edges with the
  enclosing class/method by line range: the UVM tree as the code declares it.
  Measured: apb + UVM 1.1d 1.9 s (11 k symbols), pcie-v (341 k lines) 12 s
  (53 k symbols, 255 k refs); the whole pcie-vip repo 22 s, 127 MB.
- Units are elaborated as the plain build (no `FCOV=1`/`+define+` variants);
  a `.vlt` on the Verilator list is passed to slang and yields a diagnostic,
  nothing else. slang is stricter than Questa (`UsedBeforeDeclared`, ...):
  `status=errors` is advisory, the simulators remain the gate.

## Keeping it current

- `odve_index.py update <paths>` (or the MCP `index_update`): rehash, re-tag,
  re-resolve changed `.f`, mark the units that compile those files dirty and
  elaborate them - in-process when their last build took < 6 s, else detached
  in the background (`.odve-index/elab.log`, lock in `elab.lock`).
- The PostToolUse hook in `.claude/settings.json` calls `odve_index.py hook`
  after every Edit/Write of a `.sv/.svh/.v/.vh/.f` file: re-tag now,
  elaborate in the background, never fails the edit.
- Every answer carries `stale` (files whose content changed since indexing,
  by mtime/size then sha1) and `dirty_units`; `index_status` counts them.
  A branch switch shows up the same way.

## Tools

`index_status`, `index_update(paths, note, elab)`, `index_rebuild(units)`,
`fl_list`, `fl_resolve(filelist)`, `fl_of_file(path)`, `sym_find(name, kind,
prefix, unit)`, `sym_def(name, scope)`, `sym_refs(name, kind, file)`,
`sym_outline(path, depth)`, `sym_members(name)`, `hier_tree(unit, root,
depth)`, `hier_instance(path)`, `hier_of_module(definition)`,
`tb_tree(unit, root_class)`, `class_info(name)`, `file_deps(path)`,
`diag(unit, file, severity)`, `code_at(path, line, context, end_line)`.
Each is also `odve_index.py query <tool> key=value ...`. Errors come as
`{"error": ..., "fallback": ...}`; `semantic: false` marks a ctags-only hit.

## Using it from a consumer repository

With odve as the submodule `odve/` (its content at `odve/odve/`):

```json
// <consumer>/.mcp.json
{"mcpServers": {"odve-index": {"type": "stdio", "command": "odve/odve/script/index/mcp-server.sh", "args": [], "env": {}}}}
```

```json
// <consumer>/.claude/settings.json (hooks)
{"hooks": {"PostToolUse": [{"matcher": "Edit|Write|MultiEdit", "hooks": [{"type": "command",
  "command": "\"$CLAUDE_PROJECT_DIR/odve/odve/script/index/odve_index.py\" --root \"$CLAUDE_PROJECT_DIR\" hook", "timeout": 60}]}]}}
```

```toml
# Codex: .codex/config.toml (or ~/.codex/config.toml)
[mcp_servers.odve-index]
command = "odve/odve/script/index/mcp-server.sh"
```

Then `odve/odve/script/index/setup.sh && odve/odve/script/index/odve_index.py build`,
add `.odve-index/` to `.gitignore`, and copy the two skills
(`.claude/skills/sv-navigate`, `sv-raw-review`) or point to odve's. Codex
has no hooks: its rule is to call `index_update` after writing files.
