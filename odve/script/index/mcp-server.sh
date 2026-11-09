#!/bin/sh
# Launch the odve-index MCP server (script/index/mcp_server.py).
#
# .mcp.json cannot name the repository root portably (Claude Code expands
# only environment variables there), so the root is found at run time: the
# nearest ancestor of the current directory holding .odve-index/, else the
# nearest .git - the same rule odve_index.py uses (ODVE_INDEX_ROOT overrides).
# The Python is the root's .odve-index/venv (pyslang, made by setup.sh) when
# it exists, else python3: the tag layer and every query work without
# pyslang, only elaboration needs it.
set -e
here=$(cd "$(dirname "$0")" && pwd -P)
root=${ODVE_INDEX_ROOT:-}
if [ -z "$root" ]; then
  d=$(pwd -P)
  git_root=
  while [ "$d" != "/" ]; do
    if [ -d "$d/.odve-index" ]; then root=$d; break; fi
    if [ -z "$git_root" ] && [ -e "$d/.git" ]; then git_root=$d; fi
    d=$(dirname "$d")
  done
  root=${root:-${git_root:-$(pwd -P)}}
fi
export ODVE_INDEX_ROOT="$root"
py="$root/.odve-index/venv/bin/python"
[ -x "$py" ] || py=$(command -v python3 || command -v python)
exec "$py" "$here/mcp_server.py"
