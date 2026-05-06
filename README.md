# na6pbuild

A standalone build tool for **NA6PRoot** and all its dependencies, inspired by ALICE's [aliBuild](https://github.com/alisw/alibuild).

---

## Quick start

```bash
# 1. Install na6pbuild (from NA6PRoot repository root)
pip install .

# 2. Check that your system has the required tools
na6pbuild doctor

# 3. Build everything (downloads sources automatically)
na6pbuild build na6proot

# 4. Load the environment
source ~/na6pbuild_sw/env.sh

# 5. Point NA6PROOT_ROOT to your local NA6PRoot install
export NA6PROOT_ROOT=~/na6pbuild_sw/sw/na6proot/dev

# 6. Run the simulation
mkdir tst && cd tst
na6psim -n 5 -g $NA6PROOT_ROOT/share/test/genbox.C+
```

---

## Commands

| Command | Description |
|---------|-------------|
| `na6pbuild build [PKG ...]` | Build packages and their dependencies (default: `na6proot`) |
| `na6pbuild list` | Show all packages, their versions and build status |
| `na6pbuild env [PKG ...]` | Print shell `export` statements to load the environment |
| `na6pbuild clean PKG [...]` | Delete build artifacts and install prefix for a package |
| `na6pbuild doctor` | Check that all required system tools/libraries are present |

### Common options

| Option | Description |
|--------|-------------|
| `--work-dir DIR` / `-w DIR` | Directory for sources, builds and installs (default: `~/na6pbuild_sw`, or `$NA6PBUILD_WORK_DIR`) |
| `--jobs N` / `-j N` | Parallel build jobs (default: number of CPU cores) |
| `--force` / `-f` | Rebuild even if already installed |
| `--<pkg>-version VER` | Override the version of a specific package |

---

## Packages and dependency graph

```
boost ──────────────────────────────────────────► na6proot
fmt ────────────────────────────────────────────► na6proot
         └─► fairlogger ──────────────────────► na6proot
root (needs boost) ─────────────────────────────► na6proot
                    └─► vmc ─────────────────────► na6proot
                    └─► vgm (+ geant4) ──────────► na6proot
                    └─► hepmc3 ──────────────────► na6proot
                              └─► pythia8 ────────► na6proot
geant4 ─────────────────────────────────────────► na6proot
         └─► geant4vmc (root+vmc+vgm) ──────────► na6proot
```

### Default versions

| Package | Default version |
|---------|----------------|
| Boost | 1.84.0 |
| fmt | 10.2.1 |
| FairLogger | 1.11.1 |
| ROOT | 6.32.02 |
| Geant4 | 11.2.2 |
| VMC | 2.1 |
| VGM | 5.3 |
| Geant4VMC | 6.6 |
| HepMC3 | 3.2.7 |
| Pythia8 | 8312 |

Override any version on the command line:

```bash
python3 na6plist/na6pbuild build --root-version 6.30.06 na6proot
```

or via environment variables:

```bash
ROOT_VERSION=6.30.06 python3 na6plist/na6pbuild build na6proot
```

---

## Work directory layout

```
~/na6pbuild_sw/
  sources/           # unpacked source trees
  builds/<pkg-ver>/  # CMake build directories
  sw/<pkg>/<ver>/    # installation prefixes
  logs/<pkg>.log     # build logs
  env.sh             # generated environment script
  .na6pbuild_state.json   # build state tracker
```

---

## Recipes

Each package has a shell recipe in `na6plist/recipes/<pkg>.sh`. A recipe receives:

| Variable | Description |
|----------|-------------|
| `$BUILD_AREA` | Work directory root |
| `$INSTALL_PREFIX` | Where to install this package |
| `$JOBS` | Parallel build jobs |
| `$<PKG>_VERSION` | Version being built |

Inside a recipe you can call `na6pbuild_prefix <pkg>` to get the install prefix of any already-built dependency:

```bash
ROOT_DIR="$(na6pbuild_prefix root)/cmake"
```

---

## Troubleshooting

### ROOT build fails with `read jobs pipe: Bad file descriptor`

This is typically a GNU Make jobserver issue inside ROOT's optional `clad` plugin build.
`na6pbuild` disables `clad` in the ROOT recipe to avoid it.

If you already started a failed ROOT build, clean and rebuild ROOT:

```bash
na6pbuild clean root
na6pbuild build root
```

Then continue with NA6PRoot:

```bash
na6pbuild build na6proot
```
