#!/bin/bash
# One-time setup of the code-index tools for a repository (Linux):
#   script/index/setup.sh [--root DIR] [--wheels DIR] [--tools DIR] [--check] [--ctags-only|--pyslang-only]
#
# Into <root>/.odve-index/ (gitignored):
#   venv/            Python venv with pyslang pinned by requirements.lock (uv if present, else venv+pip)
#   tools/           Universal Ctags when none is on PATH: conda-forge via micromamba if present,
#                    else the pinned static build from universal-ctags/ctags-nightly-build
# --wheels DIR   install pyslang from wheel files in DIR (offline)
# --tools DIR    take uctags-*.tar.xz from DIR instead of downloading (offline)
# --check        report what is active and exit (0 when both layers are usable)
#
# Nothing here is needed for the tag layer if a Universal Ctags >= 6.0 with
# the SystemVerilog parser is already on PATH; nothing is needed for the
# queries at all - setup only adds the tools that build the index.
set -e
here=$(cd "$(dirname "$0")" && pwd -P)
root=
wheels=
tools_dir=
check=0
only=
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root=$2; shift 2;;
    --wheels) wheels=$2; shift 2;;
    --tools) tools_dir=$2; shift 2;;
    --check) check=1; shift;;
    --ctags-only) only=ctags; shift;;
    --pyslang-only) only=pyslang; shift;;
    -h|--help) sed -n 2,16p "$0"; exit 0;;
    *) echo "setup.sh: unknown option $1" >&2; exit 2;;
  esac
done
if [ -z "$root" ]; then
  root=$(ODVE_INDEX_NO_REEXEC=1 python3 -c "import sys; sys.path.insert(0, '$here'); from idxlib import repo; print(repo.find_root())")
fi
idx="$root/.odve-index"
mkdir -p "$idx"

CTAGS_VER=2026.10.08
CTAGS_TAG='2026.10.08%2B82494361bb3e7d4f7cf1d2bdc0d0e9001c926e45'
CTAGS_SHA=e149d4f774cca9d6b657453f22fce97b94a5b691afaaa50f56f8564794839f87
CTAGS_URL="https://github.com/universal-ctags/ctags-nightly-build/releases/download/${CTAGS_TAG}/uctags-${CTAGS_VER}-linux-x86_64.release.tar.xz"

status() {
  ODVE_INDEX_NO_REEXEC=1 "$1" - "$root" "$here" <<'PY'
import sys
root, here = sys.argv[1], sys.argv[2]
sys.path.insert(0, here)
from idxlib import repo
st = repo.tool_status(root)
print(f"root     : {root}")
print(f"ctags    : {st['ctags'] or 'NOT FOUND (tag layer off)'}")
print(f"python   : {sys.executable}")
print(f"pyslang  : {st.get('pyslang_version') or 'NOT IMPORTABLE (semantic layer off)'}")
sys.exit(0 if st['ctags'] and st['pyslang'] else 1)
PY
}

py_for_status() {
  if [ -x "$idx/venv/bin/python" ]; then echo "$idx/venv/bin/python"; else command -v python3; fi
}

if [ "$check" = 1 ]; then
  status "$(py_for_status)"; exit $?
fi

# ---------------------------------------------------------------- pyslang
if [ "$only" != ctags ]; then
  if [ ! -x "$idx/venv/bin/python" ]; then
    pyv=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
    case "$pyv" in 3.11|3.12|3.13|3.14) ;; *) echo "setup.sh: pyslang needs Python >= 3.11, python3 is $pyv" >&2; exit 1;; esac
    if command -v uv >/dev/null 2>&1; then
      uv venv -q "$idx/venv" -p python3
    else
      python3 -m venv "$idx/venv"
    fi
  fi
  if ! "$idx/venv/bin/python" -c 'import pyslang' 2>/dev/null; then
    if [ -n "$wheels" ]; then
      pipargs="--no-index --find-links $wheels"
    else
      pipargs=
    fi
    if command -v uv >/dev/null 2>&1; then
      uv pip install -q -p "$idx/venv/bin/python" $pipargs -r "$here/requirements.lock"
    else
      "$idx/venv/bin/python" -m pip install -q $pipargs -r "$here/requirements.lock"
    fi
  fi
fi

# ---------------------------------------------------------------- ctags
if [ "$only" != pyslang ]; then
  have=$(ODVE_INDEX_NO_REEXEC=1 python3 -c "import sys; sys.path.insert(0, '$here'); from idxlib import repo; print(repo.find_ctags('$root') or '')")
  if [ -z "$have" ]; then
    mkdir -p "$idx/tools"
    if [ -n "$tools_dir" ] && ls "$tools_dir"/uctags-*linux-x86_64*.tar.xz >/dev/null 2>&1; then
      tarball=$(ls "$tools_dir"/uctags-*linux-x86_64*.tar.xz | head -1)
    elif command -v micromamba >/dev/null 2>&1 || command -v mamba >/dev/null 2>&1 || command -v conda >/dev/null 2>&1; then
      mm=$(command -v micromamba || command -v mamba || command -v conda)
      echo "setup.sh: installing universal-ctags from conda-forge into $idx/tools/ctags-env"
      "$mm" create -y -q -p "$idx/tools/ctags-env" -c conda-forge universal-ctags >/dev/null
      tarball=
    else
      tarball="$idx/tools/uctags.tar.xz"
      echo "setup.sh: downloading Universal Ctags $CTAGS_VER (static linux x86_64)"
      curl -sSL -o "$tarball" "$CTAGS_URL"
    fi
    if [ -n "$tarball" ]; then
      echo "$CTAGS_SHA  $tarball" | sha256sum -c - >/dev/null || { echo "setup.sh: checksum mismatch for $tarball" >&2; exit 1; }
      tar -xJf "$tarball" -C "$idx/tools"
      mkdir -p "$idx/tools/bin"
      ln -sf "$(ls -d "$idx"/tools/uctags-*linux-x86_64*/bin/ctags | head -1)" "$idx/tools/bin/ctags"
    fi
  fi
fi

status "$(py_for_status)"
