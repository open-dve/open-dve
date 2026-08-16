import json

class list2json:
    def __init__(self):
        self.data = {}

    def convert2j (self, list):
        for line in list :
            parts = line.split(":")
            self.data[parts[0]] = {"cmd" : parts[1]}
        return self.data

    def gencmd (self, data, ropts=""):
        """Build one `make run` command per run in the list. `ropts` holds extra
        make variables applied to every job (e.g. "VERILATOR=1" to drive the
        list against Verilator instead of Questa)."""
        cmds = []
        ropts = (ropts or "").strip()
        for run in data :
            cmd=f'make run RUN_DIR={run} {data[run]["cmd"]}'
            if ropts:
                cmd=f'{cmd} {ropts}'
            cmds.append(cmd)
        return cmds

