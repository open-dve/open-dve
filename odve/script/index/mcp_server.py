#!/usr/bin/env python3
"""The `odve-index` MCP server: the code index of a Verilog/SystemVerilog
repository as tools (doc/index-plan.md 3.5). Started by mcp-server.sh
(which picks the venv Python and the repository root); every tool is a
function of idxlib/queries.py, so the CLI `odve_index.py query <tool>`
gives the same answers from a shell.

Answers are compact JSON. Every answer carries `stale` (files whose content
changed since they were indexed) and, when a unit is dirty, `dirty_units`
with the hint to call index_update. A tool that cannot answer returns
{"error": ..., "fallback": "<what to do with raw code instead>"}."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from idxlib import repo, build, queries          # noqa: E402
from idxlib.db import connect                    # noqa: E402
from mcp_stdlib import MCPServer                 # noqa: E402

ROOT = repo.find_root(os.environ.get("ODVE_INDEX_ROOT") or os.getcwd())

INSTRUCTIONS = """Code index of this SystemVerilog repository (ctags + slang over the real filelists).
Navigate with these tools instead of reading source: sym_find/sym_def (where is X), sym_refs (who uses X),
sym_outline (what is in a file), sym_members, hier_tree/hier_instance (elaborated DUT/TB instance tree),
tb_tree/class_info (UVM component tree from type_id::create and class bases), fl_list/fl_resolve/fl_of_file
(what a filelist compiles), file_deps, code_at (the lines around a location). After editing or creating
.sv/.svh/.f files call index_update(paths) (Claude Code's hook does it for you). Read a whole file only when
a tool answers with an error."""

srv = MCPServer("odve-index", INSTRUCTIONS)


def _j(obj):
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"), default=str)


def _con():
    con = connect(ROOT)
    return con


def _q(fn, *args, **kw):
    con = _con()
    try:
        return _j(fn(con, ROOT, *args, **kw))
    finally:
        con.close()


@srv.tool()
def index_status() -> str:
    """Units (filelist + top) and their status, row counts, stale file count, which tools are available, last log entries."""
    return _q(queries.index_status)


@srv.tool()
def index_update(paths: list[str], note: str = "", elab: str = "auto") -> str:
    """Tell the index what changed: re-tag the given files/directories now, dirty and re-elaborate their units (elab: auto | sync | background | none). Call it after writing .sv/.svh/.f files; `note` is logged."""
    return _j(build.update(ROOT, [p if os.path.isabs(p) else os.path.join(ROOT, p) for p in paths], elab=elab, note=note or None))


@srv.tool()
def index_rebuild(units: list[str] | None = None, elab: bool = True) -> str:
    """Full rebuild: rediscover units and filelists, rehash and retag every file, elaborate the units (all, or the named ones)."""
    return _j(build.build(ROOT, units=units, elab=elab))


@srv.tool()
def fl_list() -> str:
    """Every filelist (.f) known: kind, agent, file count, nested lists, the units built from it."""
    return _q(queries.fl_list)


@srv.tool()
def fl_resolve(filelist: str, with_defines: bool = True) -> str:
    """The compile view of a filelist: ordered source files, incdirs, defines, nested -f lists and the files they `include - without reading .f files by hand."""
    return _q(queries.fl_resolve, filelist, with_defines)


@srv.tool()
def fl_of_file(path: str) -> str:
    """Which filelists (and units) compile this file, and at what position; listed=false means no list compiles it."""
    return _q(queries.fl_of_file, path)


@srv.tool()
def sym_find(name: str, kind: str = "", prefix: bool = False, unit: str = "", limit: int = 50) -> str:
    """Definitions by exact name (or prefix): file:line, kind (module, interface, package, class, function, task, variable, property, port, parameter, typedef, enum, covergroup, ...), scope, one-line declaration. semantic=false marks a ctags-only hit."""
    return _q(queries.sym_find, name, kind or None, prefix, unit or None, limit)


@srv.tool()
def sym_def(name: str, scope: str = "") -> str:
    """The one definition of a name (scope narrows: a package, class or module name), plus other candidates."""
    return _q(queries.sym_def, name, scope or None)


@srv.tool()
def sym_refs(name: str, kind: str = "", file: str = "", limit: int = 200) -> str:
    """Every reference to a symbol, grouped by file with lines and kind (use | call); via_macro names the macro when the use is inside one. `file` picks the declaration when the name is declared in several files."""
    return _q(queries.sym_refs, name, None, kind or None, file or None, limit)


@srv.tool()
def sym_outline(path: str, depth: int = 2) -> str:
    """The declarations of a file in order with line ranges (modules, classes, methods, properties, ports) - use this instead of reading the file."""
    return _q(queries.sym_outline, path, depth)


@srv.tool()
def sym_members(name: str) -> str:
    """Members of a class, package, module or interface: properties, methods, ports, parameters, typedefs with lines."""
    return _q(queries.sym_members, name)


@srv.tool()
def hier_tree(unit: str = "", root: str = "", depth: int = 3) -> str:
    """The elaborated instance tree of a unit (default: the first ok unit): path, module/interface, definition location, parameters; `root` starts at an instance path."""
    return _q(queries.hier_tree, unit or None, root or None, depth)


@srv.tool()
def hier_instance(path: str, unit: str = "") -> str:
    """One instance by hierarchical path (top.dut_i): definition, parent, children, parameters, port connections."""
    return _q(queries.hier_instance, path, unit or None)


@srv.tool()
def hier_of_module(definition: str) -> str:
    """Every instance path of a module or interface definition, across units."""
    return _q(queries.hier_of_module, definition)


@srv.tool()
def tb_tree(unit: str = "", root_class: str = "", depth: int = 6) -> str:
    """The UVM component tree as the code declares it: from the test classes (or root_class) down through every X::type_id::create("name") with the instance names and the creating method."""
    return _q(queries.tb_tree, unit or None, root_class or None, depth)


@srv.tool()
def class_info(name: str) -> str:
    """A class: base chain, derived classes, package, what it creates and who creates it, methods and properties."""
    return _q(queries.class_info, name)


@srv.tool()
def file_deps(path: str) -> str:
    """What a file depends on and who depends on it: includes, included-by, packages used, the definitions it references, the filelists that compile it."""
    return _q(queries.file_deps, path)


@srv.tool()
def diag(unit: str = "", file: str = "", severity: str = "", limit: int = 100) -> str:
    """slang diagnostics (error | warning) of a unit or file - advisory; the simulators remain the gate."""
    return _q(queries.diag, unit or None, file or None, severity or None, limit)


@srv.tool()
def code_at(path: str, line: int, context: int = 8, end_line: int = 0) -> str:
    """The numbered source lines around a location (or a line range) - the way to look at code a query pointed to, instead of opening the file."""
    return _q(queries.code_at, path, line, context, end_line or None)


if __name__ == "__main__":
    srv.run()
