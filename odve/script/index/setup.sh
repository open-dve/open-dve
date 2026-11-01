#!/bin/bash
# One-time setup of the code-index tools for a repository (Linux):
#   script/index/setup.sh [--root DIR] [--python PY] [--bundle FILE|DIR|URL | --release | --wheels DIR --tools DIR]
#                         [--check] [--ctags-only|--pyslang-only]
#
# Into <root>/.odve-index/ (gitignored):
#   venv/            Python venv with pyslang pinned by requirements.lock (uv if present, else venv+pip)
#   tools/           Universal Ctags when none is on PATH: conda-forge via micromamba if present,
#                    else the pinned static build from universal-ctags/ctags-nightly-build
# --bundle X     the portable bundle made by release.py (tarball, its unpacked directory, or a
#                URL): wheels + pip + ctags, no network and no pip needed on this host
# --release      download the bundle pinned in tools.lock (RELEASE_URL) and use it as --bundle
# --wheels DIR   install pyslang from wheel files in DIR (offline; pip or uv needed)
# --tools DIR    take uctags-*.tar.xz from DIR instead of downloading (offline)
# --python PY    the interpreter for the venv (default python3; the bundle is for one minor, 3.12)
# --check        report what is active and exit (0 when both layers are usable)
#
# Nothing here is needed for the tag layer if a Universal Ctags >= 6.0 with
# the SystemVerilog parser is already on PATH; nothing is needed for the
# queries at all - setup only adds the tools that build the index.
set -e
here=$(cd "$(dirname "$0")" && pwd -P)
. "$here/tools.lock"
root=
wheels=
tools_dir=
bundle=
check=0
only=
py=python3
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root=$2; shift 2;;
    --wheels) wheels=$2; shift 2;;
    --tools) tools_dir=$2; shift 2;;
    --bundle) bundle=$2; shift 2;;
    --release) bundle=$RELEASE_URL; shift;;
    --python) py=$2; shift 2;;
    --check) check=1; shift;;
    --ctags-only) only=ctags; shift;;
    --pyslang-only) only=pyslang; shift;;
    -h|--help) sed -n 2,20p "$0"; exit 0;;
    *) echo "setup.sh: unknown option $1" >&2; exit 2;;
  esac
done
command -v "$py" >/dev/null 2>&1 || { echo "setup.sh: python not found: $py" >&2; exit 1; }
if [ -z "$root" ]; then
  root=$(ODVE_INDEX_NO_REEXEC=1 "$py" -c "import sys; sys.path.insert(0, '$here'); from idxlib import repo; print(repo.find_root())")
fi
idx="$root/.odve-index"
mkdir -p "$idx"

# ---------------------------------------------------------------- bundle (release.py)
if [ -n "$bundle" ]; then
  case "$bundle" in
    http://*|https://*)
      mkdir -p "$idx/bundle"
      f="$idx/bundle/$(basename "$bundle")"
      echo "setup.sh: downloading $bundle"
      curl -sSfL -o "$f" "$bundle"
      bundle=$f;;
  esac
  if [ -f "$bundle" ]; then
    mkdir -p "$idx/bundle"
    tar -xzf "$bundle" -C "$idx/bundle"
    bundle="$idx/bundle/$(tar -tzf "$bundle" | head -1 | cut -d/ -f1)"
  fi
  [ -f "$bundle/MANIFEST.sha256" ] || { echo "setup.sh: not a bundle (no MANIFEST.sha256): $bundle" >&2; exit 1; }
  (cd "$bundle" && sha256sum --quiet -c MANIFEST.sha256) || { echo "setup.sh: bundle manifest mismatch in $bundle" >&2; exit 1; }
  bpy=$(sed -n 's/^python=//p' "$bundle/VERSION")
  hpy=$("$py" -c 'import sys; print("cp%d%d" % sys.version_info[:2])')
  if [ "$bpy" != "$hpy" ]; then
    echo "setup.sh: bundle is for $bpy, $py is $hpy - pass --python python3.${bpy#cp3}" >&2
    exit 1
  fi
  wheels="$bundle/wheels"
  tools_dir="$bundle/tools"
  echo "setup.sh: using bundle $(sed -n 's/^version=//p' "$bundle/VERSION") from $bundle"
fi

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
  if [ -x "$idx/venv/bin/python" ]; then echo "$idx/venv/bin/python"; else command -v "$py"; fi
}

if [ "$check" = 1 ]; then
  status "$(py_for_status)"; exit $?
fi

# ---------------------------------------------------------------- pyslang
if [ "$only" != ctags ]; then
  if [ ! -x "$idx/venv/bin/python" ]; then
    pyv=$("$py" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
    case "$pyv" in 3.11|3.12|3.13|3.14) ;; *) echo "setup.sh: pyslang needs Python >= 3.11, $py is $pyv" >&2; exit 1;; esac
    if [ -n "$bundle" ]; then
      "$py" -m venv --without-pip "$idx/venv"      # pip comes from the bundle; ensurepip may be absent
    elif command -v uv >/dev/null 2>&1; then
      uv venv -q "$idx/venv" -p "$py"
    elif "$py" -c 'import ensurepip' 2>/dev/null; then
      "$py" -m venv "$idx/venv"
    else
      echo "setup.sh: $py has no ensurepip and uv is not installed - use --bundle/--release, or install python3-venv/uv" >&2
      exit 1
    fi
  fi
  if ! "$idx/venv/bin/python" -c 'import pyslang' 2>/dev/null; then
    if [ -n "$wheels" ]; then
      pipargs="--no-index --find-links $wheels"
    else
      pipargs=
    fi
    vpy="$idx/venv/bin/python"
    if [ -n "$bundle" ]; then
      pipwhl=$(ls "$wheels"/pip-*.whl | head -1)
      "$vpy" "$pipwhl/pip" install -q $pipargs pip -r "$here/requirements.lock"   # pip run from its wheel, installs itself too
    elif command -v uv >/dev/null 2>&1; then
      uv pip install -q -p "$vpy" $pipargs -r "$here/requirements.lock"
    else
      "$vpy" -m pip install -q $pipargs -r "$here/requirements.lock"
    fi
  fi
fi

# ---------------------------------------------------------------- ctags
if [ "$only" != pyslang ]; then
  have=$(ODVE_INDEX_NO_REEXEC=1 "$py" -c "import sys; sys.path.insert(0, '$here'); from idxlib import repo; print(repo.find_ctags('$root') or '')")
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
