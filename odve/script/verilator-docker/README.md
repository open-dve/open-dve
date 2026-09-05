# Containerised Verilator

Runs Verilator from a container image so no native Verilator/gcc/flex/bison
toolchain has to be installed on the host. Used by the agents' `VERILATOR=1`
build path (`vrf/work/common/Makefile_veri`).

Works with **docker**, **podman**, or **Apptainer** (formerly Singularity),
on **WSL**, **native Linux**, **macOS**, and **Git Bash on Windows** (WSL is
the better-tested path on Windows).

## First-time setup

```bash
./setup.sh
```

Checks the OS and container engine, then pulls `verilator/verilator:latest`
(a few hundred MB, once). If no engine is installed it prints per-OS install
instructions; `./setup.sh --install-engine` will install podman for you on
Linux/WSL, or `./setup.sh --install-engine --engine apptainer` installs
Apptainer instead — both are rootless and need no daemon, so either is a good
choice on a host where you'd rather not run a background service.

Then build and run any agent that supports it:

```bash
cd $ODVE/comp/agents/apb/vrf/work/run
source sourceme
make clean all run VERILATOR=1
```

`sourceme` points `VERILATOR_ROOT` at this directory, so `bin/verilator`
is picked up as the `verilator` binary automatically.

## No root, no containers: `--native`

Ubuntu 23.10+ ships `kernel.apparmor_restrict_unprivileged_userns=1`, which
blocks the uid-map write that rootless podman and Apptainer both depend on.
Only root can lift that, so on such a host (`unshare -U -r true` fails) no
container engine can run unprivileged. `setup.sh` detects this and says so.

The no-root route is a native Verilator from conda-forge, entirely under
`$HOME`:

```bash
./setup.sh --native
```

Fetches the static `micromamba` binary to `~/.local/bin`, creates
`~/opt/verilator-conda` with `verilator` and `cxx-compiler` (the latter is
required — conda-forge's `verilated.mk` hardcodes conda's own compiler
names), and writes `native.env` next to `setup.sh` with the two exports
(`VERILATOR_ROOT`, `PATH`). `common_sourceme` sources that file whenever
`VERILATOR_ROOT` is not already set, so `source sourceme` then just works and
`make ... VERILATOR=1` never touches the container shim. `native.env` is
gitignored; delete it to go back to containers. `./setup.sh --check` reports
the native install when one is active.

## No root, no containers, no network: `--portable`

`prebuilt/` vendors a relocatable Verilator tarball per OS/arch
(`verilator-<ver>-linux-x86_64.tar.xz`), made from a `--native` install by
`./setup.sh --pack-portable`. Any clone on a matching host can use it with
nothing but `perl`, `tar`/`xz` and a `g++` ≥ 10:

```bash
./setup.sh --portable
```

Unpacks it next to itself (the unpacked directory is gitignored), checks
`verilator --version`, and writes `native.env` with `VERILATOR_ROOT` pointing
at it — so `source sourceme` picks it up exactly as with `--native`.

What packing does to make the copy portable: conda's Perl shims in
`share/verilator/bin` are replaced by the real files, the launcher's root
path is patched for the flat `bin/ include/ lib/` layout, `verilated.mk`'s
`CXX`/`LINK`/`AR` are rewritten from conda's toolchain names to plain
`g++`/`ar` so the host compiler builds the generated model, and the
`libstdc++`/`libgcc_s` the binary was linked against are bundled in `lib/`
(its RPATH is `$ORIGIN/../lib`). The binary only needs glibc ≥ 2.17.

To refresh it after a `--native` upgrade: `./setup.sh --pack-portable`, then
commit the new tarball.

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

Nothing contacts the network after that. Under Apptainer, `--load` builds the
`.sif` from the same tarball (`apptainer build ... docker-archive:<file>`) —
producing the tarball still needs docker or podman on the connected machine,
Apptainer just needs to consume it on the offline one.

## Options

| Command | Effect |
| --- | --- |
| `./setup.sh` | check environment, pull image if missing |
| `./setup.sh --check` | report only, change nothing (exit 1 if unusable) |
| `./setup.sh --install-engine` | install podman if no engine is present |
| `./setup.sh --install-engine --engine apptainer` | install Apptainer instead of podman |
| `./setup.sh --load <tarball>` | load the image from a file instead of pulling |
| `./setup.sh --image <ref>` | use a different image than the default |
| `./setup.sh --native` | no container: install Verilator from conda-forge under `$HOME` and write `native.env` |
| `./setup.sh --portable` | no container, no network: unpack the vendored `prebuilt/` tarball for this host and write `native.env` |
| `./setup.sh --pack-portable` | maintainers: rebuild the `prebuilt/` tarball from the `--native` install |

## Environment variables

| Variable | Purpose |
| --- | --- |
| `VERILATOR_ROOT` | Set it **before** `source sourceme` to use your own native Verilator instead of this wrapper or `native.env`. |
| `ODVE_VERILATOR_NATIVE_PREFIX` | `--native` only: where to create the conda env. Default `~/opt/verilator-conda`. |
| `ODVE_CONTAINER_ENGINE` | Pin the engine (`docker`, `podman`, or `apptainer`). Default: docker if present, else podman, else apptainer. |
| `VERILATOR_DOCKER_IMAGE` | Override the image reference. Default `verilator/verilator:latest`. |
| `ODVE_APPTAINER_SIF` | Apptainer only: override the `.sif` file path. Default: derived from the image reference, next to `setup.sh`. |

## How the wrapper works

`bin/verilator` mounts the repo root at the **same absolute path** inside the
container and sets the working directory to match, so the absolute paths in
this framework's `.f` filelists resolve identically inside and out. `ODVE` and
`ODVE_UVM` are forwarded so `${ODVE}`-style expansion inside filelists still
works when Verilator parses them.

Output files are written back as your own user (docker: `-u uid:gid`;
rootless podman: `--userns=keep-id`; Apptainer: no mapping needed, it already
runs as the invoking user).

Apptainer has no daemon and no `docker run`-style image cache — `setup.sh`
builds/pulls a single `.sif` file next to itself (name derived from the image
reference, e.g. `verilator_verilator_latest.sif`), and `bin/verilator`
derives the same path to find it. Delete the file and re-run `setup.sh` to
force a fresh pull.
