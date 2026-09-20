#!/usr/bin/env python3
import subprocess
import sys
import os
odve=os.environ["ODVE"]
sys.exit(subprocess.call([sys.executable, f"{odve}/script/regress/regress.py"] + sys.argv[1:]))
