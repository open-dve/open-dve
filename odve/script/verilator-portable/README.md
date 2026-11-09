# Portable Verilator bundle

One folder with everything `make ... VERILATOR=1` needs on a Linux x86_64 host
that has **no internet, no docker, no root and no compiler**: Verilator, the
g++ toolchain that compiles the generated model, GNU make, perl (Verilator's
launcher) and a glibc-2.17 sysroot. Nothing is installed system-wide and
nothing is downloaded on the target. Python/pip/conda are not needed there.

| | |
| --- | --- |
| Asset | `odve-verilator-5.054-linux-x86_64.tar.gz` (224 MB, 830 MB unpacked) |
| Release | `https://github.com/open-dve/open-dve/releases/download/verilator-5.054/` (tag `verilator-5.054`) |
| Inside | Verilator 5.054 (2026-11-01), gcc/g++ 15.3.0, binutils 2.46.1, GNU make 4.4.1, perl 5.44, python 3.15 (only for Verilator's helper scripts and the relocation step), sysroot glibc 2.17 / kernel headers 3.10 |
| Host needs | Linux x86_64, glibc >= 2.17 (CentOS/RHEL 7 or newer), bash, tar, gzip. Nothing else. |
| Files | `install.sh` (target side), `build.sh` (maintainer, online host), `release.py` (upload), `bundle.lock` (pins), `bundle/` (output, gitignored) |

The tarball is **not** in git (too big) - it is a GitHub release asset. The
same bundle also works outside odve: `source <prefix>/env.sh` and
`verilator`, `make` and `g++` are on `PATH`.

## Install on the offline machine

Copy the tarball (and its `.sha256`, optional) across, then:

```bash
odve/script/verilator-portable/install.sh /path/to/odve-verilator-5.054-linux-x86_64.tar.gz
```

or, where the machine can reach GitHub:

```bash
odve/script/verilator-portable/install.sh --release      # URL pinned in bundle.lock
odve/script/verilator-docker/setup.sh --bundle           # the same, from the Verilator setup script
```

What `install.sh` does, in order:

1. checks the host: Linux x86_64, glibc >= 2.17, `tar` and `gzip` present
2. verifies the `.sha256` sidecar when it sits next to the tarball
3. extracts into the prefix (default `$HOME/opt/odve-verilator-5.054-linux-x86_64`;
   `--prefix DIR` or `ODVE_VERILATOR_PREFIX` to change it)
4. relocates: the files still carry the path the bundle was built under, so
   `bin/python bin/conda-unpack` rewrites every recorded occurrence to the new
   prefix (text files such as `verilated.mk` and binaries such as the compiler's
   sysroot path alike). The bundled python does this; the host needs none.
5. writes `<prefix>/env.sh` with the two exports (`VERILATOR_ROOT=<prefix>/share/verilator`,
   `PATH=<prefix>/bin:$PATH`) and prints the versions of verilator, g++, make, perl
6. builds and runs a 10-line `--timing` design with the bundled g++ (`--no-test` skips it)
7. inside an odve checkout, writes `script/verilator-docker/native.env` with the same
   exports, which `sourceme` loads whenever `VERILATOR_ROOT` is not already set
   (`--odve DIR` names another checkout, `--no-odve` writes none)

Then the usual flow:

```bash
cd odve/comp/agents/apb/vrf/work/run
source sourceme
make clean all run VERILATOR=1 TESTNAME=rw_test
./regress.py submit -ropts="VERILATOR=1"
```

`odve/script/verilator-docker/setup.sh --check` reports the bundle as the active
native Verilator and confirms `make` and `g++` resolve.

A copy of `install.sh` is inside the tarball, so after a manual `tar xzf` you can
run `<dir>/install.sh` to relocate that directory in place (steps 4-7). The manual
equivalent is `cd <dir> && bin/python bin/conda-unpack`, then export the two
variables above.

## How the bundle is built (what I did)

All of this is `build.sh`; the steps are listed so they can be repeated by hand.
Run on a Linux x86_64 host **with** internet, no root needed (about 30 s plus the
download):

```bash
odve/script/verilator-portable/build.sh            # -> bundle/odve-verilator-5.054-linux-x86_64.tar.gz + .sha256
odve/script/verilator-portable/build.sh --version 5.056   # another Verilator
```

1. **Package source: conda-forge.** It is not Python wheels - it is a repository of
   prebuilt binaries for Linux (and other OSes) of many kinds of software, built
   against an old glibc so they run on old distributions. Verilator, gcc, make,
   perl and binutils all come from it as ready-made binaries. The micromamba
   package manager (one static binary) is fetched into `~/.local/bin` if neither it
   nor conda/mamba is present.
2. **Create the environment** with the packages pinned in `bundle.lock`:
   `verilator=5.054`, `cxx-compiler` (gcc, g++, binutils, the conda gcc specs),
   `make`, `sysroot_linux-64=2.17`. Perl and python come in as Verilator's
   dependencies. The sysroot pin matters: without it the solver takes the newest
   sysroot (2.39 here), and a model linked against that needs glibc 2.38+ on the
   machine that runs it. With 2.17 the compiled `Vtop` needs only `GLIBC_2.17`
   symbols (checked with `objdump -T`), as do verilator_bin, python, make and g++.
   `build.sh` fails if any package in the env declares a higher glibc floor.
3. **Manifest and installer**: `BUNDLE.txt` (name, build date, versions, the full
   package list) and a copy of `install.sh` are placed at the root of the env.
4. **Pack with conda-pack** into a second tiny env (`conda-pack` itself is not in
   the bundle). conda-pack writes a tar.gz of the whole prefix, with a list of
   every file that embeds the build path, and `bin/conda-unpack` to rewrite them at
   the destination. `--arcroot` gives the tarball a single top directory. Left out
   to save space (`--exclude`): man/info/doc pages and locales, python's test
   suite, idle, tkinter and tk/tcl, the sanitizer runtimes (`libasan` etc.), the
   Objective-C front ends (`cc1obj`, `cc1objplus`) and gcc's plugin headers. That
   takes the env from 895 MB to 830 MB unpacked and 224 MB compressed.
5. **Checksum**: `<asset>.sha256` (`sha256sum` format), uploaded next to the tarball
   and checked by `install.sh`.
6. **Smoke test**: `install.sh --prefix <work>/verify --no-odve <asset>` runs under
   `env -i PATH=/usr/bin:/bin`, i.e. without any compiler, make, python or conda
   from the build host, and must build and run the test design.

Verified here on 2026-11-09 with the host's own `g++` and `make` absent: apb
`make lint VERILATOR=1` 0 errors, `./regress.py submit -ropts="VERILATOR=1"`
and `-cov` all passing, `make ut VERILATOR=1` of the coverage runtime PASSED,
uart `make all run VERILATOR=1` ok - all with Verilator 5.054 from the bundle.

### Why conda-pack and not a plain `tar` of the env

A conda env is not relocatable as is: the build prefix is embedded in text
files (`verilated.mk`, perl and python scripts) and in binaries (gcc's default
sysroot and library search paths). conda-pack knows every such file from the
package metadata and `conda-unpack` patches them (binaries get a padded
in-place replacement, which is why the install prefix must not be longer than
the build prefix - conda-pack reserves 255 characters, so any sane path works).
The alternative, patching paths by hand as `verilator-docker/setup.sh --pack-portable`
does for the small Verilator-only tarball, does not scale to a whole compiler.

### Relation to `verilator-docker/`

| | `--portable` (prebuilt/, in git) | this bundle (release asset) |
| --- | --- | --- |
| Size | 5 MB | 224 MB |
| Contents | Verilator only | Verilator + g++ + make + perl |
| Host needs | perl, g++ >= 10, make | glibc >= 2.17 |
| Use when | the machine has a modern compiler | the machine has nothing (CAD servers, RHEL 7/8) |

`--native` (conda-forge online) and the container image remain as before; all
four end in the same `native.env` / `VERILATOR_ROOT` contract, so the Makefiles
do not care which one is active.

## Publish a new bundle

```bash
odve/script/verilator-portable/build.sh
odve/script/verilator-portable/release.py --check
GITHUB_TOKEN=... odve/script/verilator-portable/release.py --upload      # or --token-file FILE
```

`release.py` (standard library, no `gh`) creates the release `verilator-<ver>`
when it does not exist and uploads the tarball and its `.sha256`; `--replace`
overwrites assets of the same name, `--notes FILE` supplies the release text.
The token is read from `$GITHUB_TOKEN` or a file and never printed. To publish a
newer Verilator: bump `VERILATOR_VER` in `bundle.lock`, `build.sh`, `release.py --upload`.

## Troubleshooting

- `host glibc is 2.12, the bundle needs >= 2.17`: RHEL/CentOS 6 - too old for every
  conda-forge build; use a newer machine.
- `verilator: command not found` after install: `source <prefix>/env.sh` (or, in
  odve, `source sourceme` after `native.env` was written).
- The build of a model fails with `x86_64-conda-linux-gnu-c++: not found`:
  `<prefix>/bin` is not on `PATH` - `verilated.mk` names that compiler, which is
  what `env.sh` / `native.env` add.
- `conda-unpack` complains about a path length: the prefix is longer than 255
  characters; choose a shorter `--prefix`.
- Going back to another Verilator: delete `script/verilator-docker/native.env`
  (container shim) or set `VERILATOR_ROOT` before `source sourceme`.
