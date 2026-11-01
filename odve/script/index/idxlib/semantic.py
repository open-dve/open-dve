"""Layer 2: pyslang over one unit = (filelist, top, env) - the files the
simulators compile, elaborated the way they elaborate them
(doc/index-plan.md 3.3). One AST visit fills symbols, refs, instances,
classes, creates and diags for the unit; the whole thing is seconds
(0.3 s apb, 2.4 s pcie-v measured), so an update re-elaborates the unit.

Needs pyslang (pinned in requirements.lock); the caller checks
repo.have_pyslang() and records status no_pyslang otherwise."""
import os
import re
import time

from . import repo

SKIP_KINDS = {"Root", "CompilationUnit", "TransparentMember", "StatementBlock", "Instance", "InstanceBody",
              "InstanceArray", "Unknown", "Attribute", "ExplicitImport", "WildcardImport", "DeferredMember",
              "EmptyMember", "Scalar", "Predefined", "PackedArray", "FixedSizeUnpackedArray", "DynamicArray",
              "AssociativeArray", "Queue", "PackedStruct", "UnpackedStruct", "PackedUnion", "UnpackedUnion",
              "Enum", "Void", "Null", "CHandle", "String", "Event", "ErrorType", "ForwardingTypedef",
              "Iterator", "ConstraintBlock", "Genvar", "ElabSystemTask", "TimingPath", "PulseStyle",
              "Specparam", "AssertionPort", "LetDecl", "ConfigBlock", "CheckerInstance", "CheckerInstanceBody",
              "RandSeqProduction", "Checker", "NetAlias", "DPIOpenArray", "PatternVar", "ClassDefinition"}
KIND_MAP = {"Package": "package", "ClassType": "class", "Variable": "variable", "ClassProperty": "property",
            "Net": "net", "Port": "port", "InterfacePort": "port", "MultiPort": "port", "Parameter": "parameter",
            "TypeParameter": "typeparam", "TypeAlias": "typedef", "EnumValue": "enum", "Modport": "modport",
            "CovergroupType": "covergroup", "Coverpoint": "coverpoint", "CoverCross": "cross",
            "GenerateBlock": "generate", "GenerateBlockArray": "generate", "FormalArgument": "argument",
            "ClockingBlock": "clocking", "Sequence": "sequence", "Property": "property_decl",
            "UninstantiatedDef": "instance", "MethodPrototype": "prototype", "Definition": "module"}
CREATE_RE = re.compile(r"([A-Za-z_]\w*)\s*(?:#\s*\(.*?\))?\s*::\s*type_id\s*::\s*create\s*\(\s*(?:\"([^\"]*)\"|([^,)]*))", re.S)


class Extractor:
    def __init__(self, root, unit, env, cfg=None):
        self.root, self.unit, self.env, self.cfg = root, unit, env, cfg
        self.symbols = {}        # key -> row dict (dedup across instance bodies)
        self.sym_rows = []
        self.refs = []           # (decl_key, file, line, col, kind, via_macro)
        self.instances = []
        self.classes = []
        self.creates = []
        self.diags = []
        self.stats = {}

    # ---------------------------------------------------------- locations
    def loc(self, sl):
        """(repo-relative file, line, col, via_macro) of a SourceLocation,
        macro locations mapped to their expansion site."""
        sm = self.sm
        via = None
        try:
            n = 0
            while sm.isMacroLoc(sl) and n < 16:
                if via is None:
                    via = sm.getMacroName(sl) or None
                sl = sm.getExpansionLoc(sl)
                n += 1
            fn = sm.getFileName(sl)
            if not fn:
                return None
            return (self._rel(fn), sm.getLineNumber(sl), sm.getColumnNumber(sl), via)
        except Exception:
            return None

    def _rel(self, fn):
        p = os.path.abspath(fn)
        if p.startswith(self.root + os.sep):
            return repo.rel(self.root, p)
        return p.replace(os.sep, "/")

    def end_line(self, sym):
        try:
            sx = sym.syntax
            if sx is None:
                return None
            l = self.loc(sx.sourceRange.end)
            return l[1] if l else None
        except Exception:
            return None

    # ---------------------------------------------------------- the visit
    def run(self):
        from pyslang import driver, ast, DiagnosticSeverity
        self.ast = ast
        fl = repo.absp(self.root, self.unit["filelist"]) if not os.path.isabs(self.unit["filelist"]) else self.unit["filelist"]
        saved = dict(os.environ)
        os.environ.update(self.env)
        try:
            d = driver.Driver()
            d.addStandardArgs()
            opts = driver.CommandLineOptions()
            opts.expandEnvVars = True
            opts.supportsComments = True
            top = self.unit.get("top") or "top"
            t0 = time.time()
            if not d.parseCommandLine(f'slang -f "{fl}" --top {top}', opts):
                raise RuntimeError("parseCommandLine failed")
            if not d.processOptions():
                raise RuntimeError("processOptions failed (missing files?)")
            d.parseAllSources()
            self.stats["parse_s"] = time.time() - t0
            t1 = time.time()
            comp = d.createCompilation()
            root = comp.getRoot()
            diags = comp.getAllDiagnostics()        # forces full elaboration
            self.stats["elab_s"] = time.time() - t1
        finally:
            os.environ.clear()
            os.environ.update(saved)
        self.sm = d.sourceManager
        self.comp = comp
        eng = d.diagEngine
        n_err = n_warn = 0
        for dg in diags:
            sev = str(eng.getSeverity(dg.code, dg.location)).split(".")[-1]
            if sev in ("Ignored", "Note"):
                continue
            l = self.loc(dg.location)
            if sev in ("Error", "Fatal"):
                n_err += 1
            else:
                n_warn += 1
            if l:
                code = str(dg.code)
                code = code[len("DiagCode("):-1] if code.startswith("DiagCode(") else code
                self.diags.append((sev.lower(), code, l[0], l[1], eng.getMessage(dg.code)[:300]))
        self.stats["n_errors"], self.stats["n_warnings"] = n_err, n_warn

        t2 = time.time()
        self.count = 0
        root.visit(self.on_node)
        for dsym in comp.getDefinitions():             # modules never instantiated still get a row
            self.add_symbol(dsym, force_kind=self._def_kind(dsym))
        self.stats["visit_s"] = time.time() - t2
        self.stats["node_count"] = self.count
        self.resolve()

    def _def_kind(self, dsym):
        try:
            k = str(dsym.definitionKind).split(".")[-1].lower()
            return {"module": "module", "interface": "interface", "program": "program"}.get(k, "module")
        except Exception:
            return "module"

    def on_node(self, node):
        self.count += 1
        ast = self.ast
        if isinstance(node, ast.InstanceSymbol):
            self.add_instance(node)
            return
        if isinstance(node, ast.Symbol):
            if isinstance(node, ast.ClassType):
                self.add_class(node)
            self.add_symbol(node)
            return
        if isinstance(node, (ast.NamedValueExpression, ast.HierarchicalValueExpression)):
            try:
                s = node.symbol
                sl = node.sourceRange.start
            except Exception:
                return
            if s is None:
                return
            self.add_ref(s, sl, "use")
            return
        if isinstance(node, ast.MemberAccessExpression):        # cfg.nregs: the member is a reference too
            try:
                s = node.member
                sl = node.sourceRange.start
            except Exception:
                return
            if s is not None:
                self.add_ref(s, sl, "use")
            return
        if isinstance(node, ast.NewClassExpression):
            try:
                t = node.type
                if isinstance(t, ast.ClassType):
                    self.add_ref(t, node.sourceRange.start, "new")
            except Exception:
                pass
            return
        if isinstance(node, ast.CallExpression):
            try:
                if node.isSystemCall:
                    return
                sub = node.subroutine
                sl = node.sourceRange.start
            except Exception:
                return
            if sub is not None:
                self.add_ref(sub, sl, "call")
                try:
                    if node.subroutineName == "create":
                        self.add_create(node, sl)
                except Exception:
                    pass

    # ---------------------------------------------------------- rows
    def sym_key(self, sym):
        l = self.loc(sym.location)
        if not l:
            return None, None
        return (l[0], l[1], l[2], sym.name), l

    def add_symbol(self, sym, force_kind=None):
        kind = force_kind
        if kind is None:
            k = str(sym.kind).split(".")[-1]
            if k in SKIP_KINDS:
                return
            if k == "Subroutine":
                try:
                    kind = "task" if "Task" in str(sym.subroutineKind) else "function"
                except Exception:
                    kind = "function"
            else:
                kind = KIND_MAP.get(k, k.lower())
        name = sym.name
        if not name or name in ("this", "super"):
            return
        key, l = self.sym_key(sym)
        if key is None or key in self.symbols:
            return
        try:
            qual = sym.hierarchicalPath
        except Exception:
            qual = name
        parent = qual.rsplit(".", 1)[0] if "." in qual else (qual.rsplit("::", 1)[0] if "::" in qual else None)
        decl = self.decl_text(l[0], l[1])
        row = {"unit": self.unit["name"], "name": name, "kind": kind, "file": l[0], "line": l[1], "col": l[2],
               "end_line": self.end_line(sym), "qualified": qual, "parent": parent, "decl": decl, "via_macro": l[3]}
        self.symbols[key] = row
        self.sym_rows.append(row)
        if kind in ("variable", "property", "argument", "port", "parameter"):
            self.add_type_ref(sym, l)

    _text_cache = {}

    def decl_text(self, file, line):
        lines = self._lines(file)
        if lines and 0 < line <= len(lines):
            return lines[line - 1].strip()[:200]
        return None

    def _lines(self, file):
        if file not in self._text_cache:
            p = repo.absp(self.root, file) if not os.path.isabs(file) else file
            try:
                with open(p, encoding="utf-8", errors="replace") as f:
                    self._text_cache[file] = f.read().splitlines()
            except OSError:
                self._text_cache[file] = None
        return self._text_cache[file]

    def add_ref(self, sym, sl, kind):
        key, _ = self.sym_key(sym)
        if key is None:
            return
        use = self.loc(sl)
        if not use:
            return
        if repo.is_library(use[0], self.cfg) and repo.is_library(key[0], self.cfg):
            return                       # the library's own internals: nobody asks, and it is most of the rows
        self.refs.append((key, use[0], use[1], use[2], kind, use[3]))

    def add_type_ref(self, sym, l):
        """A declaration `C x;` references the class C."""
        try:
            t = sym.type
            if t is None:
                return
            t = t.canonicalType if hasattr(t, "canonicalType") else t
            if isinstance(t, self.ast.ClassType):
                self.add_ref(t, sym.location, "type")
        except Exception:
            pass

    def add_class(self, node):
        l = self.loc(node.location)
        if not l:
            return
        try:
            base = node.baseClass
            base = base.name if base is not None else None
        except Exception:
            base = None
        pkg = None
        try:
            q = node.hierarchicalPath
            if "::" in q:
                pkg = q.split("::")[0]
        except Exception:
            pass
        self.classes.append({"unit": self.unit["name"], "name": node.name, "package": pkg, "base": base,
                             "file": l[0], "line": l[1], "end_line": self.end_line(node)})

    def add_instance(self, node):
        try:
            path = node.hierarchicalPath
            dfn = node.definition
            dl = self.loc(dfn.location)
            il = self.loc(node.location)
        except Exception:
            return
        if path.startswith("$"):            # $unit-level pseudo instances of uninstantiated definitions
            return
        parent = path.rsplit(".", 1)[0] if "." in path else None
        params, conns = [], []
        try:
            for m in node.body:
                k = str(m.kind).split(".")[-1]
                if k == "Parameter":
                    try:
                        params.append(f"{m.name}={m.value}")
                    except Exception:
                        params.append(m.name)
        except Exception:
            pass
        try:
            for pc in node.portConnections:
                try:
                    e = pc.expression
                    txt = str(e.syntax).strip() if e is not None and e.syntax is not None else ""
                except Exception:
                    txt = ""
                conns.append(f"{pc.port.name}({txt[:60]})")
        except Exception:
            pass
        self.instances.append({"unit": self.unit["name"], "path": path, "parent": parent, "inst_name": node.name,
                               "definition": dfn.name, "def_kind": self._def_kind(dfn),
                               "def_file": dl[0] if dl else None, "def_line": dl[1] if dl else None,
                               "file": il[0] if il else None, "line": il[1] if il else None,
                               "params": ", ".join(params)[:500], "conns": ", ".join(conns)[:2000]})

    def add_create(self, node, sl):
        try:
            text = str(node.syntax)
        except Exception:
            return
        m = CREATE_RE.search(text)
        if not m:
            return
        use = self.loc(sl)
        if not use:
            return
        self.creates.append({"unit": self.unit["name"], "created": m.group(1),
                             "inst_name": m.group(2) if m.group(2) is not None else (m.group(3) or "").strip()[:80],
                             "file": use[0], "line": use[1], "in_class": None, "in_method": None})

    # ---------------------------------------------------------- post
    def resolve(self):
        """Enclosing class/method of each create by line ranges."""
        by_file = {}
        for r in self.sym_rows:
            if r["kind"] in ("class", "function", "task") and r["end_line"]:
                by_file.setdefault(r["file"], []).append(r)
        for c in self.creates:
            best_c = best_m = None
            for r in by_file.get(c["file"], []):
                if r["line"] <= c["line"] <= r["end_line"]:
                    if r["kind"] == "class" and (best_c is None or r["end_line"] - r["line"] < best_c["end_line"] - best_c["line"]):
                        best_c = r
                    if r["kind"] != "class" and (best_m is None or r["end_line"] - r["line"] < best_m["end_line"] - best_m["line"]):
                        best_m = r
            c["in_class"] = best_c["name"] if best_c else None
            c["in_method"] = best_m["name"] if best_m else None


def store(con, ex):
    """Replace the unit's semantic rows with the extractor's."""
    u = ex.unit["name"]
    for t in ("symbols", "refs", "instances", "classes", "creates", "diags"):
        con.execute(f"DELETE FROM {t} WHERE unit = ?", (u,))
    ids = {}
    cur = con.cursor()
    for key, r in ex.symbols.items():
        cur.execute("INSERT INTO symbols (unit,name,kind,file,line,col,end_line,qualified,parent,decl,via_macro) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    (r["unit"], r["name"], r["kind"], r["file"], r["line"], r["col"], r["end_line"], r["qualified"], r["parent"], r["decl"], r["via_macro"]))
        ids[key] = cur.lastrowid
    rows = []
    for key, file, line, col, kind, via in ex.refs:
        sid = ids.get(key)
        if sid is None:
            continue
        rows.append((sid, u, file, line, col, kind, via))
    cur.executemany("INSERT INTO refs VALUES (?,?,?,?,?,?,?)", rows)
    cur.executemany("INSERT OR REPLACE INTO instances VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                    [(i["unit"], i["path"], i["parent"], i["inst_name"], i["definition"], i["def_kind"], i["def_file"], i["def_line"], i["file"], i["line"], i["params"], i["conns"]) for i in ex.instances])
    cur.executemany("INSERT OR REPLACE INTO classes VALUES (?,?,?,?,?,?,?)",
                    [(c["unit"], c["name"], c["package"], c["base"], c["file"], c["line"], c["end_line"]) for c in ex.classes])
    cur.executemany("INSERT INTO creates VALUES (?,?,?,?,?,?,?)",
                    [(c["unit"], c["in_class"], c["in_method"], c["created"], c["inst_name"], c["file"], c["line"]) for c in ex.creates])
    cur.executemany("INSERT INTO diags VALUES (?,?,?,?,?,?)", [(u,) + d for d in ex.diags])
    return {"symbols": len(ex.symbols), "refs": len(rows), "instances": len(ex.instances), "classes": len(ex.classes),
            "creates": len(ex.creates), "diags": len(ex.diags)}
