#!/bin/bash
# Install the portable Verilator bundle: Verilator + g++ + make + perl in one folder.
# No root, no network, no docker, no Python/pip/conda needed on this host (bash, tar, gzip only).
#
#   install.sh [options] [TARBALL | URL | --release]
#
#   TARBALL        odve-verilator-<ver>-linux-x86_64.tar.gz made by build.sh (default:
#                  bundle/<asset> next to this script when present; or, when this script
#                  sits inside an unpacked bundle, that bundle in place)
#   URL            http(s) URL of the tarball (curl or wget)
#   --release      the URL pinned in bundle.lock (RELEASE_URL)
#   --prefix DIR   where to install (default $ODVE_VERILATOR_PREFIX, else $HOME/opt/<bundle name>)
#   --odve DIR     the odve/ root whose script/verilator-docker/native.env to write (default: the
#                  checkout this script lives in; --no-odve writes none)
#   --no-test      skip the compile-and-run check of a tiny design
#   --force        re-extract over an existing prefix
#
# Afterwards:  source <prefix>/env.sh   (or, in odve, just `source sourceme` in any work dir)
set -e
here=$(cd "$(dirname "$0")" && pwd -P)
[ -r "$here/bundle.lock" ] && . "$here/bundle.lock"

src=
prefix=${ODVE_VERILATOR_PREFIX:-}
odve=auto
test=1
force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) prefix=$2; shift 2;;
    --odve) odve=$2; shift 2;;
    --no-odve) odve=; shift;;
    --release) [ -n "${RELEASE_URL:-}" ] || { echo "install.sh: --release needs bundle.lock next to this script" >&2; exit 2; }
               src=$RELEASE_URL; shift;;
    --no-test) test=0; shift;;
    --force) force=1; shift;;
    -h|--help) sed -n 2,19p "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    -*) echo "install.sh: unknown option $1" >&2; exit 2;;
    *) src=$1; shift;;
  esac
done

ok()   { printf '[ ok ] %s\n' "$*"; }
info() { printf '[info] %s\n' "$*"; }
err()  { printf '[fail] %s\n' "$*" >&2; }

# ---------------------------------------------------------------- host checks
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *) err "this bundle is for Linux x86_64, this host is $(uname -s)-$(uname -m)"; exit 1;;
esac
glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')
if [ -n "$glibc" ] && [ "$(printf '%s\n' "${SYSROOT_VER:-2.17}" "$glibc" | sort -V | head -1)" != "${SYSROOT_VER:-2.17}" ]; then
  err "host glibc is $glibc, the bundle needs >= ${SYSROOT_VER:-2.17}"; exit 1
fi
for t in tar gzip; do command -v $t >/dev/null 2>&1 || { err "$t not found on PATH"; exit 1; }; done

# ---------------------------------------------------------------- locate the bundle
inplace=0
if [ -z "$src" ]; then
  if [ -x "$here/bin/conda-unpack" ] && [ -d "$here/share/verilator" ]; then
    inplace=1; prefix=${prefix:-$here}
  elif [ -n "${BUNDLE_ASSET:-}" ] && [ -f "$here/bundle/$BUNDLE_ASSET" ]; then
    src=$here/bundle/$BUNDLE_ASSET
  else
    err "no bundle given and none at ${here}/bundle/${BUNDLE_ASSET:-<asset>}"
    info "pass the tarball, a URL, or --release (build one on an online host with build.sh)"; exit 2
  fi
fi
if [ "$inplace" = 0 ]; then
  case "$src" in
    http://*|https://*)
      dl=${TMPDIR:-/tmp}/$(basename "$src")
      info "downloading $src"
      if command -v curl >/dev/null 2>&1; then curl -sSfL -o "$dl" "$src"
      elif command -v wget >/dev/null 2>&1; then wget -q -O "$dl" "$src"
      else err "neither curl nor wget found"; exit 1; fi
      src=$dl;;
  esac
  [ -f "$src" ] || { err "not a file: $src"; exit 1; }
  if [ -f "$src.sha256" ] && command -v sha256sum >/dev/null 2>&1; then
    (cd "$(dirname "$src")" && sha256sum --quiet -c "$(basename "$src").sha256") || { err "sha256 mismatch for $src"; exit 1; }
    ok "sha256 verified"
  fi
  top=$(tar -tzf "$src" 2>/dev/null | head -1 | cut -d/ -f1)
  [ -n "$top" ] || { err "cannot list $src (not a .tar.gz?)"; exit 1; }
  prefix=${prefix:-$HOME/opt/$top}
  if [ -x "$prefix/bin/verilator_bin" ] && [ "$force" = 0 ]; then
    ok "already installed in $prefix (--force to re-extract)"
  else
    info "extracting $(basename "$src") ($(du -h "$src" | cut -f1)) into $prefix"
    mkdir -p "$prefix"
    tar -xzf "$src" -C "$prefix" --strip-components=1
    # the files carry the path they were built under; rewrite it to $prefix (uses the bundled python)
    "$prefix/bin/python" "$prefix/bin/conda-unpack"
    ok "relocated to $prefix"
  fi
fi
[ -x "$prefix/bin/verilator_bin" ] || { err "no bin/verilator_bin under $prefix"; exit 1; }

# ---------------------------------------------------------------- env.sh
vroot=$prefix/share/verilator
cat > "$prefix/env.sh" <<EOF
# Portable Verilator bundle - source this file:  . $prefix/env.sh
# (odve users: script/verilator-docker/native.env has the same two lines and sourceme loads it)
export VERILATOR_ROOT="$vroot"
export PATH="$prefix/bin:\$PATH"
EOF
export VERILATOR_ROOT=$vroot PATH="$prefix/bin:$PATH"
hash -r

ver=$(verilator --version 2>&1 | head -1) || { err "verilator does not start: $ver"; exit 1; }
ok "$ver"
ok "$(x86_64-conda-linux-gnu-c++ --version | head -1)"
ok "$(make --version | head -1), $(perl -e 'print "perl $^V"')"
[ -f "$prefix/BUNDLE.txt" ] && info "bundle: $(sed -n 's/^name=//p' "$prefix/BUNDLE.txt") built $(sed -n 's/^built=//p' "$prefix/BUNDLE.txt")"

# ---------------------------------------------------------------- compile + run check
if [ "$test" = 1 ]; then
  t=$(mktemp -d "${TMPDIR:-/tmp}/odve-verilator-test.XXXXXX")
  cat > "$t/top.sv" <<'EOF'
module top;
  int i;
  initial begin
    for (i = 0; i < 3; i++) #1 $display("tick %0d at %0t", i, $time);
    $display("ODVE_VERILATOR_OK");
    $finish;
  end
endmodule
EOF
  info "building and running a test design in $t (about 10 s)"
  if (cd "$t" && verilator --binary --timing -Wno-fatal top.sv > build.log 2>&1 && ./obj_dir/Vtop > run.log 2>&1 && grep -q ODVE_VERILATOR_OK run.log); then
    ok "test design built with the bundled g++ and ran (glibc symbols <= ${SYSROOT_VER:-2.17})"
    rm -rf "$t"
  else
    err "test design failed - see $t/build.log and $t/run.log"; exit 1
  fi
fi

# ---------------------------------------------------------------- odve integration
if [ "$odve" = auto ]; then
  if [ -f "$here/../verilator-docker/setup.sh" ]; then odve=$(cd "$here/../.." && pwd -P); else odve=; fi
fi
if [ -n "$odve" ]; then
  nenv=$odve/script/verilator-docker/native.env
  [ -d "$(dirname "$nenv")" ] || { err "$odve is not an odve root (no script/verilator-docker/)"; exit 1; }
  cat > "$nenv" <<EOF
# Written by script/verilator-portable/install.sh on $(date +%F). common_sourceme sources this
# when VERILATOR_ROOT is not already set. Delete it to go back to containers.
export VERILATOR_ROOT="$vroot"
export PATH="$prefix/bin:\$PATH"
EOF
  ok "wrote $nenv"
  cat <<EOF

Next:
  cd $odve/comp/agents/apb/vrf/work/run
  source sourceme          # picks up native.env
  make clean all run VERILATOR=1 TESTNAME=rw_test
EOF
else
  cat <<EOF

Next:  . $prefix/env.sh      (then verilator, g++ = x86_64-conda-linux-gnu-c++, make are on PATH)
EOF
fi
