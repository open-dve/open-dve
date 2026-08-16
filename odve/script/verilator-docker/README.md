# Containerised Verilator

Runs Verilator from a container image so no native Verilator/gcc/flex/bison
toolchain has to be installed on the host. Used by the agents' `VERILATOR=1`
build path (`vrf/work/common/Makefile_veri`).

Works with **docker** or **podman**, on **WSL**, **native Linux**, **macOS**,
and **Git Bash on Windows** (WSL is the better-tested path on Windows).

## First-time setup

```bash
./setup.sh
```

Checks the OS and container engine, then pulls `verilator/verilator:latest`
(a few hundred MB, once). If no engine is installed it prints per-OS install
instructions; `./setup.sh --install-engine` will install podman for you on
Linux/WSL.

Then build and run any agent that supports it:

```bash
cd $ODVE/comp/agents/apb/vrf/work/run
source sourceme
make clean all run VERILATOR=1
```

`sourceme` points `VERILATOR_ROOT` at this directory, so `bin/verilator`
is picked up as the `verilator` binary automatically.

## Offline / air-gapped hosts (e.g. CAD machines)

On a machine **with** internet:

```bash
docker pull verilator/verilator:latest
docker save verilator/verilator:latest | gzip > verilator-image.tar.gz
```

Copy `verilator-image.tar.gz` across, then on the offline machine:

```bash
./setup.sh --load verilator-image.tar.gz
```

Nothing contacts the network after that.

## Options

| Command | Effect |
| --- | --- |
| `./setup.sh` | check environment, pull image if missing |
| `./setup.sh --check` | report only, change nothing (exit 1 if unusable) |
| `./setup.sh --install-engine` | install podman if no engine is present |
| `./setup.sh --load <tarball>` | load the image from a file instead of pulling |
| `./setup.sh --image <ref>` | use a different image than the default |

## Environment variables

| Variable | Purpose |
| --- | --- |
| `VERILATOR_ROOT` | Set it **before** `source sourceme` to use a native Verilator install instead of this wrapper. |
| `ODVE_CONTAINER_ENGINE` | Pin the engine (`docker` or `podman`). Default: docker if present, else podman. |
| `VERILATOR_DOCKER_IMAGE` | Override the image reference. Default `verilator/verilator:latest`. |

## How the wrapper works

`bin/verilator` mounts the repo root at the **same absolute path** inside the
container and sets the working directory to match, so the absolute paths in
this framework's `.f` filelists resolve identically inside and out. `ODVE` and
`ODVE_UVM` are forwarded so `${ODVE}`-style expansion inside filelists still
works when Verilator parses them.

Output files are written back as your own user (docker: `-u uid:gid`;
rootless podman: `--userns=keep-id`), not as root.
