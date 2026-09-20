import json
import re

class list2json:
    def __init__(self):
        self.data = {}

    def convert2j (self, list):
        """`run_name : make vars...` per line, in list order. A name may appear
        only once: it becomes RUN_DIR, so two entries sharing it would write
        the same run.log."""
        for line in list :
            name, sep, opts = line.partition(":")
            name = name.strip()
            if not sep or not name:
                raise ValueError(f"malformed list entry (expected 'name : opts'): {line!r}")
            if name in self.data:
                raise ValueError(f"duplicate run name {name!r} in list")
            self.data[name] = {"cmd" : opts.strip()}
        return self.data

    @staticmethod
    def run_dir(name, opts):
        """Directory a run writes its run.log to: RUN_DIR from the entry's own
        opts if it sets one, else the entry name (what gencmd passes)."""
        m = re.search(r"(?:^|\s)RUN_DIR=(\S+)", opts)
        return m.group(1).strip("'\"") if m else name

    def gencmd (self, data, ropts="", default_plusargs=""):
        """Build one `make run` command per run in the list. `ropts` holds extra
        make variables applied to every job (e.g. "VERILATOR=1" to drive the
        list against Verilator instead of Questa). `default_plusargs` are
        appended as RUN_OPTS+=... -- the Makefiles' run-switch variable, which
        reaches vsim and the Verilator binary alike -- but only those whose
        +KEY the entry's own opts and `ropts` don't already carry, so a user's
        setting replaces the default instead of sitting next to it."""
        cmds = []
        ropts = (ropts or "").strip()
        for run in data :
            cmd=f'make run RUN_DIR={run} {data[run]["cmd"]}'
            given = data[run]["cmd"] + " " + ropts
            for plusarg in (default_plusargs or "").split():
                key = plusarg.split("=", 1)[0]
                if key not in given:
                    cmd=f'{cmd} RUN_OPTS+={plusarg}'
            if ropts:
                cmd=f'{cmd} {ropts}'
            cmds.append(cmd)
        return cmds
