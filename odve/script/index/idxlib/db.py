"""The index database: one SQLite file per repository root,
<root>/.odve-index/index.db (doc/index-plan.md 3.1). Standard library only."""
import json
import os
import sqlite3
import time

SCHEMA_VERSION = 1

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);

CREATE TABLE IF NOT EXISTS files (
    path TEXT PRIMARY KEY,          -- repo-relative, '/' separated
    sha1 TEXT, mtime REAL, size INTEGER,
    lang TEXT,                      -- sv | v | f | other
    listed INTEGER DEFAULT 0,       -- in at least one filelist
    tagged_at REAL, elab_at REAL
);

CREATE TABLE IF NOT EXISTS filelists (
    path TEXT PRIMARY KEY, kind TEXT, agent TEXT, env TEXT,   -- env: json of the ODVE*/PROJ snapshot
    resolved_at REAL
);
CREATE TABLE IF NOT EXISTS fl_entries (
    filelist TEXT, ordinal INTEGER, kind TEXT, value TEXT,    -- kind: file | incdir | define | nested_f
    PRIMARY KEY (filelist, ordinal)
);
CREATE INDEX IF NOT EXISTS fl_entries_value ON fl_entries (value);

CREATE TABLE IF NOT EXISTS units (
    name TEXT PRIMARY KEY, filelist TEXT, top TEXT, agent TEXT, sourceme TEXT,
    status TEXT,                    -- ok | errors | dirty | no_pyslang | failed
    parse_s REAL, elab_s REAL, visit_s REAL, node_count INTEGER,
    n_errors INTEGER, n_warnings INTEGER, built_at REAL, message TEXT
);

CREATE TABLE IF NOT EXISTS tags (
    name TEXT, kind TEXT, file TEXT, line INTEGER, end_line INTEGER,
    scope TEXT, scope_kind TEXT, signature TEXT, typeref TEXT, inherits TEXT
);
CREATE INDEX IF NOT EXISTS tags_name ON tags (name);
CREATE INDEX IF NOT EXISTS tags_file ON tags (file);

CREATE TABLE IF NOT EXISTS symbols (
    id INTEGER PRIMARY KEY, unit TEXT, name TEXT, kind TEXT,
    file TEXT, line INTEGER, col INTEGER, end_line INTEGER,
    qualified TEXT, parent TEXT, decl TEXT, via_macro TEXT
);
CREATE INDEX IF NOT EXISTS symbols_name ON symbols (name);
CREATE INDEX IF NOT EXISTS symbols_file ON symbols (file, line);
CREATE INDEX IF NOT EXISTS symbols_unit ON symbols (unit);

CREATE TABLE IF NOT EXISTS refs (
    symbol_id INTEGER, unit TEXT, file TEXT, line INTEGER, col INTEGER, kind TEXT, via_macro TEXT
);
CREATE INDEX IF NOT EXISTS refs_symbol ON refs (symbol_id);
CREATE INDEX IF NOT EXISTS refs_file ON refs (file, line);
CREATE INDEX IF NOT EXISTS refs_unit ON refs (unit);

CREATE TABLE IF NOT EXISTS instances (
    unit TEXT, path TEXT, parent TEXT, inst_name TEXT, definition TEXT, def_kind TEXT,
    def_file TEXT, def_line INTEGER, file TEXT, line INTEGER, params TEXT, conns TEXT,
    PRIMARY KEY (unit, path)
);
CREATE INDEX IF NOT EXISTS instances_def ON instances (definition);

CREATE TABLE IF NOT EXISTS classes (
    unit TEXT, name TEXT, package TEXT, base TEXT, file TEXT, line INTEGER, end_line INTEGER,
    PRIMARY KEY (unit, name, file, line)
);
CREATE INDEX IF NOT EXISTS classes_name ON classes (name);
CREATE INDEX IF NOT EXISTS classes_base ON classes (base);

CREATE TABLE IF NOT EXISTS creates (
    unit TEXT, in_class TEXT, in_method TEXT, created TEXT, inst_name TEXT, file TEXT, line INTEGER
);
CREATE INDEX IF NOT EXISTS creates_in ON creates (in_class);
CREATE INDEX IF NOT EXISTS creates_created ON creates (created);

CREATE TABLE IF NOT EXISTS includes (file TEXT, included TEXT, line INTEGER, unit TEXT);
CREATE INDEX IF NOT EXISTS includes_file ON includes (file);
CREATE INDEX IF NOT EXISTS includes_inc ON includes (included);

CREATE TABLE IF NOT EXISTS diags (unit TEXT, severity TEXT, code TEXT, file TEXT, line INTEGER, message TEXT);
CREATE INDEX IF NOT EXISTS diags_unit ON diags (unit);

CREATE TABLE IF NOT EXISTS log (at REAL, what TEXT, detail TEXT);
"""


def db_path(root):
    return os.path.join(root, ".odve-index", "index.db")


def connect(root, create=True):
    """Open the index of `root`; create the directory, schema and WAL mode
    on first use. Returns a sqlite3.Connection with Row rows."""
    path = db_path(root)
    if not create and not os.path.exists(path):
        return None
    os.makedirs(os.path.dirname(path), exist_ok=True)
    con = sqlite3.connect(path, timeout=30)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA synchronous=NORMAL")
    con.executescript(SCHEMA)
    v = con.execute("SELECT value FROM meta WHERE key='schema'").fetchone()
    if v is None:
        con.execute("INSERT INTO meta VALUES ('schema', ?)", (str(SCHEMA_VERSION),))
        con.execute("INSERT OR REPLACE INTO meta VALUES ('root', ?)", (root,))
        con.commit()
    return con


def log(con, what, detail=""):
    con.execute("INSERT INTO log VALUES (?, ?, ?)", (time.time(), what, detail if isinstance(detail, str) else json.dumps(detail)))


def rows(cur):
    return [dict(r) for r in cur.fetchall()]
