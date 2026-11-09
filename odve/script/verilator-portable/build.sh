#!/bin/bash
# Build the portable Verilator bundle on a host WITH internet (Linux x86_64, no root):
#
#   build.sh [--version V] [--out DIR] [--work DIR] [--keep] [--no-test]
#
#   --version V   Verilator version to bundle (default: VERILATOR_VER in bundle.lock)
#   --out DIR     where the tarball goes (default: bundle/ next to this script, gitignored)
#   --work DIR    scratch area for the conda env and tools (default ~/.cache/odve-verilator-build)
#   --keep        keep the conda env after packing (default: removed, the tarball is the product)
#   --no-test     skip the install.sh dry run on the fresh tarball
#
# What it does (also documented in README.md):
#   1. gets micromamba (one static binary, ~/.local/bin) if neither it nor conda/mamba is present
#   2. creates a conda-forge env with the packages in bundle.lock: verilator, cxx-compiler (gcc,
#      g++, binutils), make, sysroot_linux-64=<SYSROOT_VER>, which pull in perl and python
#   3. installs conda-pack into a second tiny env and packs the first one into a relocatable
#      tar.gz (conda-pack records every path that embeds the build prefix; install.sh rewrites
#      them on the target with the bundled python - no conda needed there), leaving out man/info/
#      doc pages, locales, python's test suite and tk, the sanitizer runtimes, the Objective-C
#      front ends and gcc's plugin headers
#   4. writes <asset>.sha256 and installs the result into <work>/verify as a smoke test
set -e
here=$(cd "$(dirname "$0")" && pwd -P)
. "$here/bundle.lock"

out=$here/bundle
work=${ODVE_VERILATOR_BUILD:-$HOME/.cache/odve-verilator-build}
keep=0
test=1
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERILATOR_VER=$2; shift 2;;
    --out) out=$2; shift 2;;
    --work) work=$2; shift 2;;
    --keep) keep=1; shift;;
    --no-test) test=0; shift;;
    -h|--help) sed -n 2,10p "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "build.sh: unknown option $1" >&2; exit 2;;
  esac
done
# re-derive the names when --version overrode the lock
. <(sed -e "s/^VERILATOR_VER=.*/VERILATOR_VER=$VERILATOR_VER/" "$here/bundle.lock")

ok()   { printf '[ ok ] %s\n' "$*"; }
info() { printf '[info] %s\n' "$*"; }
err()  { printf '[fail] %s\n' "$*" >&2; }

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *) err "build.sh makes the $BUNDLE_ARCH bundle and must run on Linux x86_64"; exit 1;;
esac
mkdir -p "$work" "$out"
env=$work/env-$VERILATOR_VER
tools=$work/tools

# ---------------------------------------------------------------- 1. micromamba
mm=
for c in micromamba mamba conda; do command -v $c >/dev/null 2>&1 && { mm=$(command -v $c); break; }; done
if [ -z "$mm" ]; then
  mm=$HOME/.local/bin/micromamba
  if [ ! -x "$mm" ]; then
    info "fetching micromamba into $mm"
    mkdir -p "$(dirname "$mm")"
    curl -fsSL -o "$mm" https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-linux-64
    chmod +x "$mm"
  fi
fi
ok "package manager: $mm ($("$mm" --version 2>/dev/null | head -1))"

# ---------------------------------------------------------------- 2. the env
if [ -x "$env/bin/verilator_bin" ]; then
  ok "env already present: $env"
else
  rm -rf "$env"
  info "creating $env with: $CONDA_PKGS"
  # shellcheck disable=SC2086
  "$mm" create -y -q -p "$env" -c conda-forge --override-channels $CONDA_PKGS
fi
got=$(PATH="$env/bin:$PATH" VERILATOR_ROOT="$env/share/verilator" "$env/share/verilator/bin/verilator" --version | awk '{print $2}')
[ "$got" = "$VERILATOR_VER" ] || { err "env has Verilator $got, wanted $VERILATOR_VER"; exit 1; }
ok "Verilator $got, $(PATH="$env/bin:$PATH" x86_64-conda-linux-gnu-c++ --version | head -1)"

# glibc floor: every package must accept 2.17 (the sysroot pin makes compiled models do the same)
bad=$(grep -ho '"__glibc >=[0-9.]*' "$env"/conda-meta/*.json | sed 's/.*>=//' | sort -uV | tail -1)
[ "$(printf '%s\n' "$bad" "$SYSROOT_VER" | sort -V | tail -1)" = "$SYSROOT_VER" ] \
  || { err "a package needs glibc >= $bad, above the $SYSROOT_VER floor (grep __glibc $env/conda-meta/*.json)"; exit 1; }

# ---------------------------------------------------------------- manifest + installer inside the bundle
pkgver() { ls "$env/conda-meta/$1-"[0-9]*.json | head -1 | sed "s|.*/$1-||; s|-[^-]*\.json$||"; }
{
  echo "name=$BUNDLE_NAME"
  echo "built=$(date +%F) on $(uname -s)-$(uname -m), glibc floor $SYSROOT_VER"
  echo "verilator=$(pkgver verilator)"
  echo "gcc=$(pkgver gcc)"
  echo "binutils=$(pkgver binutils_impl_linux-64)"
  echo "make=$(pkgver make)"
  echo "perl=$(pkgver perl)"
  echo "python=$(pkgver python)"
  echo "sysroot=$(pkgver sysroot_linux-64) (kernel headers $(pkgver kernel-headers_linux-64))"
  echo "source=conda-forge, packed with conda-pack; relocate with: bin/python bin/conda-unpack (install.sh does it)"
  echo "use=source env.sh  ->  VERILATOR_ROOT=<here>/share/verilator, PATH=<here>/bin"
  echo "packages:"
  ls "$env/conda-meta"/*.json | sed 's|.*/||; s|\.json$||; s|^|  |'
} > "$env/BUNDLE.txt"
cp "$here/install.sh" "$env/install.sh"
chmod +x "$env/install.sh"

# ---------------------------------------------------------------- 3. conda-pack
if [ ! -x "$tools/bin/conda-pack" ]; then
  info "installing conda-pack into $tools"
  "$mm" create -y -q -p "$tools" -c conda-forge --override-channels conda-pack
fi
asset=$out/$BUNDLE_ASSET
rm -f "$asset"
info "packing $env -> $asset"
"$tools/bin/conda-pack" -p "$env" -o "$asset" --arcroot "$BUNDLE_NAME" --n-threads -1 -q \
  --exclude 'man/*' --exclude 'share/man/*' --exclude 'share/info/*' --exclude 'share/doc/*' \
  --exclude 'share/locale/*' --exclude 'share/gtk-doc/*' \
  --exclude 'lib/python3*/test/*' --exclude 'lib/python3*/idlelib/*' --exclude 'lib/python3*/tkinter/*' \
  --exclude 'lib/tk8*/*' --exclude 'lib/tcl8*/*' --exclude '*.pyc' \
  --exclude 'lib/libasan*' --exclude 'lib/libtsan*' --exclude 'lib/liblsan*' --exclude 'lib/libubsan*' --exclude 'lib/libhwasan*' \
  --exclude 'lib/gcc/*/*/lib*san*.a' --exclude 'lib/gcc/*/*/plugin/*' \
  --exclude 'libexec/gcc/*/*/cc1obj' --exclude 'libexec/gcc/*/*/cc1objplus'
(cd "$out" && sha256sum "$BUNDLE_ASSET" > "$BUNDLE_ASSET.sha256")
ok "$asset ($(du -h "$asset" | cut -f1)), $(cat "$asset.sha256" | cut -c1-16)..."

# ---------------------------------------------------------------- 4. smoke test
if [ "$test" = 1 ]; then
  rm -rf "$work/verify"
  info "smoke test: install.sh --prefix $work/verify --no-odve (minimal PATH)"
  env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
    bash "$here/install.sh" --prefix "$work/verify" --no-odve "$asset" || { err "smoke test failed"; exit 1; }
  rm -rf "$work/verify"
fi
[ "$keep" = 1 ] || { rm -rf "$env"; info "removed $env (--keep keeps it)"; }
cat <<EOF

Done: $asset
      $asset.sha256
Upload:  $here/release.py --upload            (GITHUB_TOKEN or --token-file; tag $RELEASE_TAG)
Install: $here/install.sh $asset   or, on the target, install.sh --release
EOF
