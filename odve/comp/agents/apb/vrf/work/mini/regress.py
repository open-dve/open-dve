#!python
import subprocess
import sys
import os
odve=os.environ["ODVE"]
sys.exit(subprocess.call(["python", f"{odve}/script/regress/regress.py"] + sys.argv[1:]))
