#!/usr/bin/env bash
# One-time setup for the containerised Verilator used by `make ... VERILATOR=1`.
#
# Detects the host OS and container engine, installs the engine if asked,
# then pulls (or loads, for offline hosts) the Verilator image.
#
#   ./setup.sh                     check environment + pull the image
#   ./setup.sh --check             check only, change nothing
#   ./setup.sh --install-engine    also install a container engine if missing (default: podman)
#   ./setup.sh --install-engine --engine apptainer   install Apptainer instead of podman
#   ./setup.sh --load <tarball>    load image from a file instead of pulling
#   ./setup.sh --image <ref>       use a different image than the default
#   ./setup.sh --native            no container at all: install Verilator from
#                                  conda-forge under $HOME (no root needed)
#   ./setup.sh --portable          no container, no download: unpack the prebuilt
#                                  Verilator vendored in prebuilt/ for this OS/arch
#   ./setup.sh --pack-portable     maintainers: rebuild prebuilt/ from a --native install
#
# Exit codes: 0 ok, 1 environment not usable, 2 bad usage.
set -euo pipefail

IMAGE="${VERILATOR_DOCKER_IMAGE:-verilator/verilator:latest}"
MODE=pull
LOAD_FILE=""
INSTALL_ENGINE=0
ENGINE_CHOICE="podman"   # which engine --install-engine installs: podman | apptainer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_PREFIX="${ODVE_VERILATOR_NATIVE_PREFIX:-$HOME/opt/verilator-conda}"
NATIVE_ENV="$SCRIPT_DIR/native.env"
PREBUILT_DIR="$SCRIPT_DIR/prebuilt"
MAMBA_BIN="$HOME/.local/bin/micromamba"
export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-$HOME/micromamba}"

RED=''; GRN=''; YLW=''; BLD=''; RST=''
if [ -t 1 ]; then
    RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'
fi
ok()   { printf '%s[ ok ]%s %s\n'   "$GRN" "$RST" "$*"; }
info() { printf '%s[info]%s %s\n'   ""     ""     "$*"; }
warn() { printf '%s[warn]%s %s\n'   "$YLW" "$RST" "$*"; }
err()  { printf '%s[fail]%s %s\n'   "$RED" "$RST" "$*" >&2; }
hdr()  { printf '\n%s== %s ==%s\n'  "$BLD" "$*" "$RST"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --check)          MODE=check ;;
        --native)         MODE=native ;;
        --portable)       MODE=portable ;;
        --pack-portable)  MODE=pack ;;
        --install-engine) INSTALL_ENGINE=1 ;;
        --engine)         ENGINE_CHOICE="${2:-}"; shift
                          case "$ENGINE_CHOICE" in
                              podman|apptainer) ;;
                              *) err "unsupported --engine: $ENGINE_CHOICE (use podman or apptainer)"; exit 2 ;;
                          esac ;;
        --load)           MODE=load; LOAD_FILE="${2:-}"; shift
                          [ -n "$LOAD_FILE" ] || { err "--load needs a file"; exit 2; } ;;
        --image)          IMAGE="${2:-}"; shift
                          [ -n "$IMAGE" ] || { err "--image needs a value"; exit 2; } ;;
        -h|--help)        sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)                err "unknown option: $1 (try --help)"; exit 2 ;;
    esac
    shift
done

# ---------------------------------------------------------------- OS detection

OS_KIND=unknown       # wsl | linux | windows | macos
OS_PRETTY="$(uname -s -r 2>/dev/null || echo unknown)"
DISTRO=""
PKG=""                # apt | dnf | yum | pacman | zypper

detect_os() {
    case "$(uname -s)" in
        Linux)
            if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
                OS_KIND=wsl
            else
                OS_KIND=linux
            fi
            if [ -r /etc/os-release ]; then
                # shellcheck disable=SC1091
                DISTRO="$(. /etc/os-release && echo "${PRETTY_NAME:-$NAME}")"
            fi
            for c in apt-get dnf yum pacman zypper; do
                if command -v "$c" >/dev/null 2>&1; then
                    case "$c" in apt-get) PKG=apt ;; *) PKG="$c" ;; esac
                    break
                fi
            done
            ;;
        Darwin)                      OS_KIND=macos ;;
        MINGW*|MSYS*|CYGWIN*)        OS_KIND=windows ;;
    esac
}

detect_os

hdr "Host"
case "$OS_KIND" in
    wsl)
        ok "WSL detected${WSL_DISTRO_NAME:+ (distro: $WSL_DISTRO_NAME)}"
        [ -n "$DISTRO" ] && info "$DISTRO"
        info "kernel: $OS_PRETTY"
        info "Either Docker Desktop with WSL integration, or an engine installed"
        info "inside this distro, will work."
        ;;
    linux)
        ok "Native Linux detected"
        [ -n "$DISTRO" ] && info "$DISTRO"
        info "kernel: $OS_PRETTY"
        ;;
    windows)
        ok "Windows shell detected (Git Bash / MSYS / Cygwin)"
        info "$OS_PRETTY"
        warn "Paths are translated by MSYS; if the build cannot find files, run"
        warn "this flow from WSL instead - that is the better-tested path here."
        ;;
    macos)
        ok "macOS detected ($OS_PRETTY)"
        ;;
    *)
        warn "Unrecognised OS: $OS_PRETTY - continuing, but you are off the tested path."
        ;;
esac

# ------------------------------------------------- native (no-container) path

# Ubuntu 23.10+ ships kernel.apparmor_restrict_unprivileged_userns=1, which
# stops an unprivileged process writing its own uid_map - the one thing
# rootless podman and Apptainer both need. Only root can lift it, so on such
# a host the no-root route is a native Verilator from conda-forge under $HOME.
userns_ok() { unshare -U -r true >/dev/null 2>&1; }

warn_userns_blocked() {
    warn "This host blocks unprivileged user namespaces ('unshare -U -r' fails;"
    warn "kernel.apparmor_restrict_unprivileged_userns=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo '?')),"
    warn "so rootless podman/Apptainer cannot run here without root. Docker's root"
    warn "daemon is unaffected. With no root at all, use:  ./setup.sh --native"
}

install_native() {
    hdr "Native Verilator (conda-forge, no root)"
    local arch
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64)   arch=linux-64 ;;
        Linux-aarch64)  arch=linux-aarch64 ;;
        Darwin-x86_64)  arch=osx-64 ;;
        Darwin-arm64)   arch=osx-arm64 ;;
        *) err "--native supports Linux and macOS only (got $(uname -s)-$(uname -m))."; return 1 ;;
    esac

    local mm
    if command -v micromamba >/dev/null 2>&1; then
        mm="$(command -v micromamba)"
    elif [ -x "$MAMBA_BIN" ]; then
        mm="$MAMBA_BIN"
    else
        info "Fetching micromamba (single static binary) into $MAMBA_BIN..."
        mkdir -p "$(dirname "$MAMBA_BIN")"
        curl -fsSL -o "$MAMBA_BIN" \
            "https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-$arch" \
            || { err "Download failed - no internet?"; return 1; }
        chmod +x "$MAMBA_BIN"
        mm="$MAMBA_BIN"
    fi
    ok "micromamba $("$mm" --version 2>/dev/null | head -1)  ($mm)"

    # cxx-compiler is not optional: conda-forge's verilated.mk hardcodes
    # CXX/LINK/AR to conda's own toolchain names (x86_64-conda-linux-gnu-c++),
    # so the generated C++ will not build against the system g++ alone.
    if [ -x "$NATIVE_PREFIX/share/verilator/bin/verilator" ]; then
        ok "Verilator env already present: $NATIVE_PREFIX"
    else
        info "Creating $NATIVE_PREFIX with verilator + cxx-compiler (a few hundred MB, one time)..."
        "$mm" create -y -q -p "$NATIVE_PREFIX" -c conda-forge verilator cxx-compiler \
            || { err "micromamba create failed."; return 1; }
    fi
    if ! ls "$NATIVE_PREFIX"/bin/*-conda-*-c++ >/dev/null 2>&1; then
        info "Adding cxx-compiler to the existing env..."
        "$mm" install -y -q -p "$NATIVE_PREFIX" -c conda-forge cxx-compiler \
            || { err "micromamba install failed."; return 1; }
    fi

    local root="$NATIVE_PREFIX/share/verilator" ver
    ver="$(PATH="$NATIVE_PREFIX/bin:$PATH" VERILATOR_ROOT="$root" "$root/bin/verilator" --version 2>&1 | head -1)" \
        || { err "Installed, but 'verilator --version' failed: $ver"; return 1; }
    ok "Works: $ver"

    cat > "$NATIVE_ENV" <<EOF
# Written by setup.sh --native on $(date +%F). common_sourceme sources this
# when VERILATOR_ROOT is not already set. Delete it to go back to containers.
export VERILATOR_ROOT="$root"
export PATH="$NATIVE_PREFIX/bin:\$PATH"
EOF
    ok "Wrote $NATIVE_ENV"

    hdr "Next steps"
    cat <<EOF
  cd \$ODVE/comp/agents/apb/vrf/work/run
  source sourceme          # picks up native.env automatically
  make clean all run VERILATOR=1
EOF
    info "Prefix: $NATIVE_PREFIX  (set ODVE_VERILATOR_NATIVE_PREFIX before --native to change it)"
}

# ------------------------------------------- portable (vendored prebuilt) path
#
# prebuilt/ carries a relocatable tarball made by --pack-portable from a
# --native install: bin/ (perl launcher + verilator_bin), include/ (with
# verilated.mk rewritten to plain g++/ar), lib/ (the libstdc++/libgcc_s the
# binary was linked against, found through its $ORIGIN/../lib RPATH). The
# host needs only perl, tar/xz and a g++ >= 10; nothing is downloaded and
# nothing needs root.

host_tag() { echo "$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"; }

pack_portable() {
    hdr "Packing a portable Verilator from $NATIVE_PREFIX"
    local root="$NATIVE_PREFIX/share/verilator"
    [ -x "$root/bin/verilator" ] || { err "No native install at $NATIVE_PREFIX - run --native first."; return 1; }
    local ver name stage dst f b lib
    ver="$(PATH="$NATIVE_PREFIX/bin:$PATH" VERILATOR_ROOT="$root" "$root/bin/verilator" --version 2>/dev/null | awk '{print $2}')"
    [ -n "$ver" ] || { err "Could not read the Verilator version."; return 1; }
    name="verilator-$ver-$(host_tag)"
    stage="$(mktemp -d)"; dst="$stage/$name"
    mkdir -p "$dst/bin" "$dst/lib"

    cp -a "$root/include" "$dst/"
    # share/verilator/bin mixes real perl tools with 3-line shims that exec
    # ../../../bin/<name>; take the real file either way, drop what has none.
    for f in "$root"/bin/*; do
        b="$(basename "$f")"
        if grep -q 'relpath = "../../../bin"' "$f" 2>/dev/null; then
            if [ -f "$NATIVE_PREFIX/bin/$b" ]; then cp "$NATIVE_PREFIX/bin/$b" "$dst/bin/$b"
            else info "skipping $b (shim with no real binary)"; fi
        else
            cp "$f" "$dst/bin/$b"
        fi
    done
    # the launcher takes its root as bin/<relpath>; in this flat layout that is ..
    sed -i 's|^my \$verilator_pkgdatadir_relpath = .*|my $verilator_pkgdatadir_relpath = "..";|' "$dst/bin/verilator"
    grep -q 'relpath = "\.\.";' "$dst/bin/verilator" || { err "Could not patch the launcher's root path."; return 1; }
    # conda's verilated.mk names conda's own toolchain; the host g++ builds the model
    sed -i -e 's|^AR = .*|AR = ar|' -e 's|^CXX = .*|CXX = g++|' -e 's|^LINK = .*|LINK = g++|' \
           -e 's|^CFG_CXX_VERSION = .*|CFG_CXX_VERSION = "host g++ (portable build)"|' "$dst/include/verilated.mk"
    # shared libs the binary resolves inside the env travel with it
    for lib in $(ldd "$dst/bin/verilator_bin" | awk -v p="$NATIVE_PREFIX" 'index($3,p)==1 {print $3}'); do
        cp -L "$lib" "$dst/lib/"
    done
    if command -v strip >/dev/null 2>&1; then
        strip "$dst/bin/verilator_bin" "$dst"/lib/*.so* 2>/dev/null || true
    fi
    cat > "$dst/PORTABLE.txt" <<EOF
Verilator $ver, portable build for $(host_tag), packed $(date +%F) by setup.sh --pack-portable
from a conda-forge install. Host needs: perl, g++ >= 10 (compiles the generated model), glibc >= 2.17.
Use: export VERILATOR_ROOT=<this directory>   (setup.sh --portable does this via native.env)
EOF
    mkdir -p "$PREBUILT_DIR"
    rm -f "$PREBUILT_DIR"/verilator-*-"$(host_tag)".tar.xz
    tar -C "$stage" -cJf "$PREBUILT_DIR/$name.tar.xz" "$name"
    rm -rf "$stage"
    ok "Wrote $PREBUILT_DIR/$name.tar.xz ($(du -h "$PREBUILT_DIR/$name.tar.xz" | cut -f1))"
    info "Commit it; any clone on $(host_tag) can then run: ./setup.sh --portable"
}

unpack_portable() {
    hdr "Portable Verilator (vendored in prebuilt/, no download, no root)"
    local tgz name dest ver
    tgz="$(ls "$PREBUILT_DIR"/verilator-*-"$(host_tag)".tar.xz 2>/dev/null | sort -V | tail -1 || true)"
    if [ -z "$tgz" ]; then
        err "No prebuilt for $(host_tag) in $PREBUILT_DIR."
        if ls "$PREBUILT_DIR"/*.tar.xz >/dev/null 2>&1; then
            ls "$PREBUILT_DIR"/*.tar.xz | sed 's/^/  have: /'
        else
            info "Build one with: ./setup.sh --native && ./setup.sh --pack-portable"
        fi
        return 1
    fi
    command -v perl >/dev/null 2>&1 || { err "perl is required by the verilator launcher."; return 1; }
    if command -v g++ >/dev/null 2>&1; then
        ok "host g++: $(g++ --version | head -1)"
    else
        warn "No g++ on PATH - 'verilator' itself will run, but the generated model cannot be compiled."
    fi
    name="$(basename "$tgz" .tar.xz)"; dest="$PREBUILT_DIR/$name"
    if [ -x "$dest/bin/verilator_bin" ]; then
        ok "Already unpacked: $dest"
    else
        info "Unpacking $(basename "$tgz")..."
        tar -C "$PREBUILT_DIR" -xJf "$tgz"
    fi
    ver="$(VERILATOR_ROOT="$dest" "$dest/bin/verilator" --version 2>&1 | head -1)" \
        || { err "Unpacked, but 'verilator --version' failed: $ver"; return 1; }
    ok "Works: $ver"
    cat > "$NATIVE_ENV" <<EOF
# Written by setup.sh --portable on $(date +%F). common_sourceme sources this
# when VERILATOR_ROOT is not already set. Delete it to go back to containers.
export VERILATOR_ROOT="$dest"
EOF
    ok "Wrote $NATIVE_ENV"
    hdr "Next steps"
    cat <<EOF
  cd \$ODVE/comp/agents/apb/vrf/work/run
  source sourceme          # picks up native.env automatically
  make clean all run VERILATOR=1
EOF
}

case "$MODE" in
    native)   install_native  || exit 1; exit 0 ;;
    pack)     pack_portable   || exit 1; exit 0 ;;
    portable) unpack_portable || exit 1; exit 0 ;;
esac

# --check: a working native install is what the build will actually use.
if [ "$MODE" = "check" ] && [ -r "$NATIVE_ENV" ]; then
    hdr "Native Verilator"
    # shellcheck disable=SC1090
    if ver="$(. "$NATIVE_ENV" && "$VERILATOR_ROOT/bin/verilator" --version 2>&1 | head -1)"; then
        ok "$ver  (from $NATIVE_ENV)"
        hdr "Result"; ok "Environment looks good."; exit 0
    fi
    warn "$NATIVE_ENV exists but its verilator does not run - checking containers instead."
fi

# --------------------------------------------------- container engine handling

ENGINE=""

find_engine() {
    if [ -n "${ODVE_CONTAINER_ENGINE:-}" ]; then
        if command -v "$ODVE_CONTAINER_ENGINE" >/dev/null 2>&1; then
            ENGINE="$ODVE_CONTAINER_ENGINE"
        else
            warn "ODVE_CONTAINER_ENGINE=$ODVE_CONTAINER_ENGINE is set but not on PATH."
        fi
        return 0
    fi
    for e in docker podman apptainer singularity; do
        if command -v "$e" >/dev/null 2>&1; then ENGINE="$e"; return; fi
    done
}

is_apptainer() {
    case "$(basename "${1:-$ENGINE}")" in
        apptainer|singularity) return 0 ;;
        *)                     return 1 ;;
    esac
}

print_install_help() {
    hdr "How to install a container engine"
    case "$OS_KIND" in
        wsl)
            cat <<'EOF'
Option A - Docker Desktop on Windows (simplest):
  1. Install from https://www.docker.com/products/docker-desktop/
  2. Settings -> Resources -> WSL integration -> enable for this distro
  3. Reopen this shell, then re-run: ./setup.sh

Option B - engine inside WSL (no Docker Desktop):
  Docker:     curl -fsSL https://get.docker.com | sudo sh
              sudo usermod -aG docker "$USER"     # then reopen the shell
  Podman:     sudo apt-get update && sudo apt-get install -y podman
  Apptainer:  sudo apt-get update && sudo apt-get install -y apptainer  (or: singularity-container)
EOF
            ;;
        linux)
            case "$PKG" in
                apt)    echo "  Docker:     curl -fsSL https://get.docker.com | sudo sh"
                        echo "              sudo usermod -aG docker \"\$USER\"   # then re-login"
                        echo "  Podman:     sudo apt-get update && sudo apt-get install -y podman"
                        echo "  Apptainer:  sudo apt-get update && sudo apt-get install -y apptainer  (or: singularity-container)" ;;
                dnf)    echo "  Podman:     sudo dnf install -y podman"
                        echo "  Apptainer:  sudo dnf install -y apptainer"
                        echo "  Docker:     sudo dnf install -y docker-ce docker-ce-cli containerd.io" ;;
                yum)    echo "  Podman:     sudo yum install -y podman"
                        echo "  Apptainer:  sudo yum install -y apptainer" ;;
                pacman) echo "  Docker: sudo pacman -S docker    Podman: sudo pacman -S podman    Apptainer: sudo pacman -S apptainer" ;;
                zypper) echo "  Podman:     sudo zypper install -y podman"
                        echo "  Apptainer:  sudo zypper install -y apptainer" ;;
                *)      echo "  See https://docs.docker.com/engine/install/, https://podman.io/getting-started/installation,"
                        echo "  or https://apptainer.org/docs/admin/main/installation.html" ;;
            esac
            echo "  Rootless podman and Apptainer both need no daemon and no group membership."
            ;;
        windows)
            cat <<'EOF'
  Install Docker Desktop: https://www.docker.com/products/docker-desktop/
  Enable the WSL2 backend during setup, then re-run this script.
EOF
            ;;
        macos)
            cat <<'EOF'
  Docker Desktop: https://www.docker.com/products/docker-desktop/
  Podman:         brew install podman && podman machine init && podman machine start
EOF
            ;;
        *)
            echo "  https://docs.docker.com/engine/install/"
            ;;
    esac
}

install_engine() {
    hdr "Installing a container engine ($ENGINE_CHOICE)"
    if [ "$OS_KIND" = "windows" ] || [ "$OS_KIND" = "macos" ]; then
        err "Automatic install is not supported on this OS - it needs a GUI installer."
        print_install_help
        return 1
    fi
    if [ "$ENGINE_CHOICE" = "apptainer" ]; then
        case "$PKG" in
            apt)
                info "Installing Apptainer via apt (rootless, no daemon needed)..."
                sudo apt-get update
                if apt-cache show apptainer >/dev/null 2>&1; then
                    sudo apt-get install -y apptainer
                else
                    info "Package 'apptainer' isn't in this distro's repo; installing 'singularity-container'"
                    info "(same upstream project - Debian/Ubuntu kept the older package name for it)."
                    sudo apt-get install -y singularity-container
                fi ;;
            dnf)    sudo dnf install -y apptainer ;;
            yum)    sudo yum install -y apptainer ;;
            pacman) sudo pacman -S --noconfirm apptainer ;;
            zypper) sudo zypper install -y apptainer ;;
            *)      err "No supported package manager found."; print_install_help; return 1 ;;
        esac
        return 0
    fi
    case "$PKG" in
        apt)
            info "Installing podman via apt (no daemon, no group setup needed)..."
            sudo apt-get update && sudo apt-get install -y podman ;;
        dnf)    sudo dnf install -y podman ;;
        yum)    sudo yum install -y podman ;;
        pacman) sudo pacman -S --noconfirm podman ;;
        zypper) sudo zypper install -y podman ;;
        *)      err "No supported package manager found."; print_install_help; return 1 ;;
    esac
}

hdr "Container engine"
find_engine

if [ -z "$ENGINE" ]; then
    err "No container engine found on PATH (checked docker, podman, apptainer, singularity)."
    if ! userns_ok; then
        warn_userns_blocked
        if [ "$INSTALL_ENGINE" = "1" ]; then
            err "Refusing to install $ENGINE_CHOICE: it is rootless-only and cannot run on this host."
            exit 1
        fi
    fi
    if [ "$INSTALL_ENGINE" = "1" ]; then
        install_engine || exit 1
        find_engine
        [ -n "$ENGINE" ] || { err "Install finished but no engine on PATH - reopen your shell."; exit 1; }
    else
        print_install_help
        echo
        info "Re-run with --install-engine to let this script install podman for you,"
        info "or --install-engine --engine apptainer to install Apptainer instead."
        exit 1
    fi
fi

ok "Found: $ENGINE ($("$ENGINE" --version 2>/dev/null | head -1))"
if [ "$(basename "$ENGINE")" != "docker" ] && ! userns_ok; then
    warn_userns_blocked
fi

if is_apptainer "$ENGINE"; then
    if ! "$ENGINE" version >/dev/null 2>&1; then
        err "$ENGINE is installed but 'version' failed - the installation looks broken."
        exit 1
    fi
    ok "$ENGINE is usable (rootless, no daemon needed)"
else
    if ! "$ENGINE" info >/dev/null 2>&1; then
        err "$ENGINE is installed but not usable (daemon down, or permission denied)."
        case "$OS_KIND" in
            wsl)   warn "If using Docker Desktop: start it, and enable WSL integration for this distro." ;;
            linux) warn "Try: sudo systemctl start docker    (and: sudo usermod -aG docker \"\$USER\", then re-login)" ;;
            *)     warn "Start the engine, then re-run." ;;
        esac
        exit 1
    fi
    ok "$ENGINE is running"
fi

# ------------------------------------------------------------------ the image

hdr "Verilator image"

# Apptainer has no daemon-backed image store - it keeps a single .sif file,
# named from the image reference, that setup.sh and bin/verilator agree on.
SIF_FILE="${ODVE_APPTAINER_SIF:-$SCRIPT_DIR/$(printf '%s' "$IMAGE" | tr '/:' '__').sif}"

if is_apptainer "$ENGINE"; then
    have_image()     { [ -f "$SIF_FILE" ]; }
    engine_version() { "$ENGINE" run "$SIF_FILE" --version 2>&1 | head -1; }
else
    have_image()     { "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; }
    engine_version() { "$ENGINE" run --rm "$IMAGE" --version 2>&1 | head -1; }
fi

if [ "$MODE" = "check" ]; then
    if have_image; then
        if is_apptainer "$ENGINE"; then ok "Image present: $SIF_FILE"; else ok "Image present: $IMAGE"; fi
        info "verilator: $(engine_version)"
    else
        if is_apptainer "$ENGINE"; then
            warn "SIF NOT present: $SIF_FILE   (run this script without --check to build it)"
        else
            warn "Image NOT present: $IMAGE   (run this script without --check to pull it)"
        fi
        exit 1
    fi
    hdr "Result"; ok "Environment looks good."; exit 0
fi

if [ "$MODE" = "load" ]; then
    [ -r "$LOAD_FILE" ] || { err "Cannot read $LOAD_FILE"; exit 1; }
    if is_apptainer "$ENGINE"; then
        info "Building $SIF_FILE from $LOAD_FILE (offline install)..."
        "$ENGINE" build "$SIF_FILE" "docker-archive:$LOAD_FILE"
    else
        info "Loading $IMAGE from $LOAD_FILE (offline install)..."
        "$ENGINE" load -i "$LOAD_FILE"
    fi
elif have_image; then
    if is_apptainer "$ENGINE"; then
        ok "Image already present: $SIF_FILE"
        info "Delete it and re-run this script for a fresh build."
    else
        ok "Image already present: $IMAGE"
        info "Delete it with '$ENGINE rmi $IMAGE' if you want a fresh pull."
    fi
else
    if is_apptainer "$ENGINE"; then
        info "Pulling $IMAGE as $SIF_FILE (a few hundred MB, one time)..."
        if ! "$ENGINE" pull "$SIF_FILE" "docker://$IMAGE"; then
            err "Pull failed."
            warn "No internet? Export the image on a machine with docker or podman:"
            warn "    docker pull $IMAGE && docker save $IMAGE | gzip > verilator-image.tar.gz"
            warn "copy the file over, then here run:"
            warn "    ./setup.sh --load verilator-image.tar.gz"
            exit 1
        fi
    else
        info "Pulling $IMAGE (a few hundred MB, one time)..."
        if ! "$ENGINE" pull "$IMAGE"; then
            err "Pull failed."
            warn "No internet? Export the image on a connected machine:"
            warn "    $ENGINE pull $IMAGE && $ENGINE save $IMAGE | gzip > verilator-image.tar.gz"
            warn "copy the file over, then here run:"
            warn "    ./setup.sh --load verilator-image.tar.gz"
            exit 1
        fi
    fi
fi

have_image || { err "Image still missing after $MODE."; exit 1; }
if is_apptainer "$ENGINE"; then ok "Image ready: $SIF_FILE"; else ok "Image ready: $IMAGE"; fi

VER="$(engine_version)" \
    && ok "Works: $VER" \
    || { err "Image present but 'verilator --version' failed."; exit 1; }

hdr "Next steps"
cat <<EOF
  cd \$ODVE/comp/agents/apb/vrf/work/run
  source sourceme
  make clean all run VERILATOR=1
EOF
if is_apptainer "$ENGINE"; then
    info "Using $ENGINE: export ODVE_CONTAINER_ENGINE=$ENGINE to pin it. (SIF: $SIF_FILE)"
elif [ "$ENGINE" != "docker" ]; then
    info "Using $ENGINE: export ODVE_CONTAINER_ENGINE=$ENGINE to pin it."
fi
exit 0
