#!python
import sys
import argparse
import json
import os
import re


def job_failed(result):
    """A job's result string counts as failed if the process itself exited non-zero
    (compile error, tool crash, ...), or -- since `vsim -batch` exits 0 even when the
    simulated test hit UVM_ERROR/UVM_FATAL -- if its UVM report summary shows either
    non-zero. A result with no UVM summary at all (e.g. the compile job, or vsim never
    got that far) is judged on return code alone."""
    if "Return code: 0" not in result:
        return True
    for sev in ("UVM_ERROR", "UVM_FATAL"):
        m = re.search(sev + r"\s*:\s*(\d+)", result)
        if m and int(m.group(1)) > 0:
            return True
    return False


odve_name="ODVE"
if odve_name in os.environ:
    odve=os.environ[odve_name]
    print ( f"ODVE variable is ({odve})")
else : 
    print ( f"ODVE is not defined")
    exit (1)

lib_path=f"{odve}/script/regress/"
sys.path.append(lib_path)
#local python classes
from readlist  import readlist
from list2json import list2json
from jobrunner import JobRunner

tlist=''
maxj=4
cwd=os.getcwd()
cmdsj = {}
cmdsl = []
def main():
    parser = argparse.ArgumentParser(description="Regression runner script by regress list")
    parser.add_argument("top_list", help="Regression list name")
    parser.add_argument("-opts", "--opts", help="Output JSON file")
    parser.add_argument("-max_jobs", "--max_jobs", type=int, default=4, help="Max parallel jobs")
    parser.add_argument("-no_comp", "--no_comp", action="store_true", help="Skip the compile step and run the list against the existing build")

    args = parser.parse_args()
    maxj = args.max_jobs

    tlist=f"{cwd}/../rlist/{args.top_list}.list"
    print (f"file.list is : {tlist}")

    rf = readlist(f"{tlist}")
    rf.readfile()
    rf.printline()

    l2j = list2json ()
    cmdsj = l2j.convert2j(rf.getlines())
    print(json.dumps(cmdsj, indent=4))
    cmdsl = l2j.gencmd(cmdsj)
    print (cmdsl)

    if not args.no_comp:
        jc = JobRunner(maxj)
        comp_jobs = ["make clean all"]
        results=jc.run_jobs(comp_jobs)
        print (results)
        if any(job_failed(r) for r in results):
            print("Compile failed (see output above) -- aborting regression run.")
            exit(1)

    jr = JobRunner(maxj)
    results=jr.run_jobs(cmdsl)
    print (results)
    if any(job_failed(r) for r in results):
        print("One or more regression runs failed (see output above).")
        exit(1)


if __name__ == "__main__":
    main()    