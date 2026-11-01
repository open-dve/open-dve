---
name: sv-navigate
description: Navigate Verilog/SystemVerilog code through the odve-index MCP (ctags + slang over the real filelists) instead of reading files - where a symbol is defined, who references it, what a file declares, the elaborated DUT instance tree, the UVM component tree, what a filelist compiles. Use it BEFORE opening any .sv/.svh file to answer "where is X", "who uses X", "what is in this file", "how is the testbench built", "which list compiles this", and after creating or editing .sv/.svh/.f files to keep the index current (index_update). Applies in this repo and in every repo that carries odve as a submodule.
---

# Navigating SystemVerilog with the odve-index MCP

The index answers from a SQLite database built by `odve/script/index/odve_index.py`:
Universal Ctags over every HDL file (instant, tolerant of code that does not
compile) and pyslang over each **unit** = an agent's `vrf/list/fl.f` elaborated
with its `sourceme` environment (definitions, references, instances, class
bases, `type_id::create` edges). Design: `odve/doc/index-plan.md`.

## Rule

1. **Query first, read second.** Reading a whole `.sv` file to find something
   is the last resort. Read source only at the lines a query points to
   (`code_at`) or when a tool answers with `error`.
2. **Never read `uvm/`** sources to learn a UVM class: `sym_members`,
   `class_info`, `sym_def` know them.
3. After you write or edit `.sv/.svh/.f` files, the index is updated by the
   PostToolUse hook (Claude Code) - with another agent, call
   `index_update(paths=[...])`. An answer with `stale: [...]` or
   `dirty_units` means the index lags: call `index_update` and retry.
4. If the MCP is not listed (`/mcp`), fall back to the CLI from a shell:
   `odve/script/index/odve_index.py query <tool> key=value ...` - same answers.

## Recipes

| Question | Tools, in order |
| --- | --- |
| Where is `X` defined? | `sym_def(name)` → `code_at(file, line)` for the declaration text |
| Who uses `X`? | `sym_refs(name)` (grouped by file; `kind=call` for calls; `file=` picks the declaration when the name exists in several classes) |
| What is in this file? | `sym_outline(path)` - classes, methods, properties with line ranges; `depth=3` adds locals |
| What does class `C` have / extend / create? | `class_info(name)` (base chain, derived, creates, created_by, methods, properties); `sym_members(name)` for any scope |
| How is the testbench built? | `tb_tree(unit)` - from the `uvm_test` classes down through every `type_id::create("name")`; `root_class=` to start elsewhere |
| What does the DUT look like? | `hier_tree(unit, depth)` → `hier_instance(path)` for parameters and port connections; `hier_of_module(def)` for all instances of a module |
| What does this filelist compile, with which incdirs/defines? | `fl_list()` → `fl_resolve(filelist)` |
| Is this file compiled at all, by which lists? | `fl_of_file(path)` (`listed: false` = add it to a `list/*.f` or `vrf/list/fl_*.f`) |
| What does this file depend on? | `file_deps(path)` - includes, included-by, the definitions it references |
| Does the unit even elaborate? | `diag(unit)` - slang errors/warnings, advisory (the simulators are the gate; `UsedBeforeDeclared` is slang being stricter than Questa) |
| Is the index current? | `index_status()` - units, ages, stale count, tools |

A typical change: `sym_def` → `sym_refs` (every caller to adapt) →
`code_at` on each → edit → the hook re-indexes → `sym_refs` again to confirm.

## When a tool returns `error`

Each error carries a `fallback`. The ladder is: `sym_find(prefix=true)` →
`sym_outline(path)` → `code_at(path, line, context)` ranges → the file itself
(only now). `semantic: false` on a hit means only ctags saw it: the file is
in no elaborated unit (`fl_of_file` says which) or the unit failed
(`index_status`, `diag`).

## Keeping the index

- First time in a clone: `odve/script/index/setup.sh` (venv with pyslang,
  ctags; offline: `--release` or `--bundle <tarball>`, see
  `script/index/README.md`) then `odve/script/index/odve_index.py build`.
- A new agent (`vrf-new-agent`) or a new `.f`: `index_update(paths=[<agent dir>])`
  or `odve_index.py build` - units are discovered from `vrf/list/fl.f`.
- Elaboration of a unit takes 0.3 s (apb) to ~12 s (pcie-v); `index_update`
  runs it in-process when quick, in the background otherwise (`elab_mode`).
