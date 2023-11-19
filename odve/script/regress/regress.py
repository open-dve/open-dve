#!python
import sys
import argparse
import json
import os


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
    parser.add_argument("-max_jobs", "--max_jobs", help="Output JSON file")
    parser.add_argument("-no_comp", "--no_comp", help="Config JSON file")

    args = parser.parse_args()

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

    jc = JobRunner(maxj)
    comp_jobs = ["make clean all"]
    results=jc.run_jobs(comp_jobs)
    print (results)

    #jr = JobRunner(maxj) 
    #results=jr.run_jobs(cmdsl)
    #print (results)


if __name__ == "__main__":
    main()    