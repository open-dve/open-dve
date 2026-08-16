#!/usr/bin/env bash
# One-time setup for the containerised Verilator used by `make ... VERILATOR=1`.
#
# Detects the host OS and container engine, installs the engine if asked,
# then pulls (or loads, for offline hosts) the Verilator image.
#
#   ./setup.sh                     check environment + pull the image
#   ./setup.sh --check             check only, change nothing
#   ./setup.sh --install-engine    also install docker/podman if missing
#   ./setup.sh --load <tarball>    load image from a file instead of pulling
#   ./setup.sh --image <ref>       use a different image than the default
#
# Exit codes: 0 ok, 1 environment not usable, 2 bad usage.
set -euo pipefail

IMAGE="${VERILATOR_DOCKER_IMAGE:-verilator/verilator:latest}"
MODE=pull
LOAD_FILE=""
INSTALL_ENGINE=0

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
        --install-engine) INSTALL_ENGINE=1 ;;
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
    for e in docker podman; do
        if command -v "$e" >/dev/null 2>&1; then ENGINE="$e"; return; fi
    done
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
  Docker:  curl -fsSL https://get.docker.com | sudo sh
           sudo usermod -aG docker "$USER"     # then reopen the shell
  Podman:  sudo apt-get update && sudo apt-get install -y podman
EOF
            ;;
        linux)
            case "$PKG" in
                apt)    echo "  Docker: curl -fsSL https://get.docker.com | sudo sh"
                        echo "          sudo usermod -aG docker \"\$USER\"   # then re-login"
                        echo "  Podman: sudo apt-get update && sudo apt-get install -y podman" ;;
                dnf)    echo "  Podman: sudo dnf install -y podman"
                        echo "  Docker: sudo dnf install -y docker-ce docker-ce-cli containerd.io" ;;
                yum)    echo "  Podman: sudo yum install -y podman" ;;
                pacman) echo "  Docker: sudo pacman -S docker    Podman: sudo pacman -S podman" ;;
                zypper) echo "  Podman: sudo zypper install -y podman" ;;
                *)      echo "  See https://docs.docker.com/engine/install/ or https://podman.io/getting-started/installation" ;;
            esac
            echo "  Rootless podman needs no daemon and no group membership."
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
    hdr "Installing a container engine"
    if [ "$OS_KIND" = "windows" ] || [ "$OS_KIND" = "macos" ]; then
        err "Automatic install is not supported on this OS - it needs a GUI installer."
        print_install_help
        return 1
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
    err "Neither docker nor podman found on PATH."
    if [ "$INSTALL_ENGINE" = "1" ]; then
        install_engine || exit 1
        find_engine
        [ -n "$ENGINE" ] || { err "Install finished but no engine on PATH - reopen your shell."; exit 1; }
    else
        print_install_help
        echo
        info "Re-run with --install-engine to let this script install podman for you."
        exit 1
    fi
fi

ok "Found: $ENGINE ($("$ENGINE" --version 2>/dev/null | head -1))"

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

# ------------------------------------------------------------------ the image

hdr "Verilator image"

have_image() { "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; }

if [ "$MODE" = "check" ]; then
    if have_image; then
        ok "Image present: $IMAGE"
        info "verilator: $("$ENGINE" run --rm "$IMAGE" --version 2>&1 | head -1)"
    else
        warn "Image NOT present: $IMAGE   (run this script without --check to pull it)"
        exit 1
    fi
    hdr "Result"; ok "Environment looks good."; exit 0
fi

if [ "$MODE" = "load" ]; then
    [ -r "$LOAD_FILE" ] || { err "Cannot read $LOAD_FILE"; exit 1; }
    info "Loading $IMAGE from $LOAD_FILE (offline install)..."
    "$ENGINE" load -i "$LOAD_FILE"
elif have_image; then
    ok "Image already present: $IMAGE"
    info "Delete it with '$ENGINE rmi $IMAGE' if you want a fresh pull."
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

have_image || { err "Image still missing after $MODE."; exit 1; }
ok "Image ready: $IMAGE"

VER="$("$ENGINE" run --rm "$IMAGE" --version 2>&1 | head -1)" \
    && ok "Works: $VER" \
    || { err "Image present but 'verilator --version' failed."; exit 1; }

hdr "Next steps"
cat <<EOF
  cd \$ODVE/comp/agents/apb/vrf/work/run
  source sourceme
  make clean all run VERILATOR=1
EOF
[ "$ENGINE" != "docker" ] && info "Using $ENGINE: export ODVE_CONTAINER_ENGINE=$ENGINE to pin it."
exit 0
