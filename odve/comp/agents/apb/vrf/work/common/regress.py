#!python
import subprocess
import sys
import os
odve=os.environ["ODVE"]
subprocess.call(["python", f"{odve}/script/regress/regress.py"] + sys.argv[1:])
