#!/usr/bin/env python3
"""
na6pbuild - Build tool for NA6PRoot and its dependencies.
Inspired by ALICE's aliBuild.

Usage:
  na6pbuild build [PACKAGE ...]   # Build one or more packages (and their deps)
  na6pbuild list                  # List available packages and their status
  na6pbuild clean [PACKAGE ...]   # Remove build artifacts for a package
  na6pbuild env [PACKAGE ...]     # Print shell environment setup commands
  na6pbuild doctor                # Check system prerequisites

Examples:
  na6pbuild build na6proot            # Build na6proot and all dependencies
  na6pbuild build geant4 vmc vgm      # Build specific packages
  na6pbuild build --jobs 8 na6proot   # Build with 8 parallel jobs
  na6pbuild env na6proot | source /dev/stdin   # Load environment
  na6pbuild --work-dir ~/sw build na6proot     # Custom work directory
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Default versions (override via environment or --version flags)
# ---------------------------------------------------------------------------
DEFAULT_VERSIONS = {
    "boost":      "1.84.0",
    "fmt":        "10.2.1",
    "fairlogger": "1.11.1",
    "root":       "6.32.02",
    "geant4":     "11.2.2",
    "vmc":        "2.1",
    "vgm":        "5.3",
    "geant4vmc":  "6.6",
    "hepmc3":     "3.3.1",
    "pythia8":    "8312",
    "na6proot":   "dev",
}

# ---------------------------------------------------------------------------
# Dependency graph (each package lists its build-time dependencies)
# ---------------------------------------------------------------------------
DEPENDENCIES = {
    "boost":      [],
    "fmt":        [],
    "fairlogger": ["fmt"],
    "root":       ["boost"],
    "geant4":     [],
    "vmc":        ["root"],
    "vgm":        ["root", "geant4"],
    "geant4vmc":  ["root", "geant4", "vmc", "vgm"],
    "hepmc3":     ["root"],
    "pythia8":    ["hepmc3"],
    "na6proot":   ["boost", "fmt", "fairlogger", "root", "geant4",
                   "vmc", "vgm", "geant4vmc", "hepmc3", "pythia8"],
}

# System packages required (checked via 'which' or pkg-config)
SYSTEM_PREREQS = {
    "cmake":        "cmake",
    "git":          "git",
    "curl":         "curl",
    "make":         "make",
    "g++":          "g++",
    "pkg-config":   "pkg-config",
}

SYSTEM_LIBS = {
    "libssl-dev / openssl-devel": ["pkg-config", "--exists", "openssl"],
    "libxml2-dev / libxml2-devel": ["pkg-config", "--exists", "libxml-2.0"],
    "libexpat-dev": ["pkg-config", "--exists", "expat"],
    "python3-dev": [sys.executable, "-c", "import sys; assert sys.version_info >= (3,8)"],
}

REQUIRED_SYSTEM_LIBS = {
    "libxerces-c-dev (required for Geant4 GDML)": ["pkg-config", "--exists", "xerces-c"],
    "libhdf5-dev (required for NA6PRoot)": ["bash", "-lc", "pkg-config --exists hdf5 || pkg-config --exists hdf5-serial || command -v h5cc >/dev/null 2>&1"],
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

RECIPES_DIR = Path(__file__).parent / "recipes"
STATE_FILE_NAME = ".na6pbuild_state.json"


def _candidate_recipes_dirs() -> list[Path]:
    candidates: list[Path] = []

    env_dir = os.environ.get("NA6PBUILD_RECIPES_DIR")
    if env_dir:
        candidates.append(Path(env_dir).expanduser().resolve())

    module_dir = Path(__file__).resolve().parent
    candidates.extend([
        module_dir / "recipes",
        module_dir.parent / "recipes",
        Path.cwd() / "recipes",
    ])

    unique: list[Path] = []
    seen: set[Path] = set()
    for cand in candidates:
        if cand not in seen:
            seen.add(cand)
            unique.append(cand)
    return unique


def get_recipes_dir() -> Path:
    for cand in _candidate_recipes_dirs():
        if cand.is_dir():
            return cand
    return RECIPES_DIR


def bold(s: str) -> str:
    return f"\033[1m{s}\033[0m"

def green(s: str) -> str:
    return f"\033[92m{s}\033[0m"

def yellow(s: str) -> str:
    return f"\033[93m{s}\033[0m"

def red(s: str) -> str:
    return f"\033[91m{s}\033[0m"

def info(msg: str):
    print(f"  {bold('==>')} {msg}")

def warn(msg: str):
    print(f"  {yellow('WARNING:')} {msg}")

def error(msg: str):
    print(f"  {red('ERROR:')} {msg}", file=sys.stderr)


def pkg_config_env() -> dict[str, str]:
    env = os.environ.copy()
    extra_paths: list[str] = []
    for p in (
        Path.home() / "local/lib/pkgconfig",
        Path.home() / "local/lib64/pkgconfig",
    ):
        if p.is_dir():
            extra_paths.append(str(p))

    if extra_paths:
        current = env.get("PKG_CONFIG_PATH", "")
        env["PKG_CONFIG_PATH"] = ":".join(extra_paths + ([current] if current else []))
    return env


def topo_sort(packages: list[str], dep_graph: dict) -> list[str]:
    """Return packages in topological build order."""
    visited: set[str] = set()
    result: list[str] = []

    def visit(pkg):
        if pkg in visited:
            return
        visited.add(pkg)
        for dep in dep_graph.get(pkg, []):
            visit(dep)
        result.append(pkg)

    for pkg in packages:
        visit(pkg)
    return result


def load_state(work_dir: Path) -> dict:
    state_file = work_dir / STATE_FILE_NAME
    if state_file.exists():
        with open(state_file) as f:
            return json.load(f)
    return {}


def save_state(work_dir: Path, state: dict):
    state_file = work_dir / STATE_FILE_NAME
    with open(state_file, "w") as f:
        json.dump(state, f, indent=2)


def hash_source_dir(src: Path, extensions: tuple = (".cxx", ".h", ".hh", ".cc", ".cpp", ".hpp", "CMakeLists.txt")) -> str:
    """Return a stable hash of all relevant source files under src, excluding build artifacts."""
    hasher = hashlib.sha256()
    # Directories to skip (build artifacts, caches, etc.)
    skip_dirs = {"build", "CMakeFiles", ".git", ".vscode", "__pycache__", ".pytest_cache", ".tox", "dist", "*.egg-info"}
    
    for path in sorted(src.rglob("*")):
        # Skip if any parent directory is in skip_dirs
        if any(part in skip_dirs for part in path.relative_to(src).parts):
            continue
        if path.is_file() and (path.suffix in extensions or path.name in extensions):
            hasher.update(str(path.relative_to(src)).encode())
            hasher.update(path.read_bytes())
    return hasher.hexdigest()


def get_install_prefix(work_dir: Path, package: str, version: str) -> Path:
    return work_dir / "sw" / package / version


def get_build_log(work_dir: Path, package: str) -> Path:
    log_dir = work_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    return log_dir / f"{package}.log"


def na6pbuild_prefix_func(work_dir: Path, versions: dict) -> str:
    """
    Shell function definition that recipes call as: na6pbuild_prefix <pkg>
    Returns the install prefix for a built package.
    """
    lines = ["na6pbuild_prefix() {"]
    lines.append("  local pkg=$1")
    lines.append("  case $pkg in")
    for pkg, ver in versions.items():
        prefix = get_install_prefix(work_dir, pkg, ver)
        lines.append(f"    {pkg}) echo '{prefix}' ;;")
    lines.append("    *) echo \"na6pbuild_prefix: unknown package '$pkg'\" >&2; return 1 ;;")
    lines.append("  esac")
    lines.append("}")
    return "\n".join(lines)


def env_for_package(work_dir: Path, package: str, version: str) -> dict[str, str]:
    """Return extra PATH/LD_LIBRARY_PATH/CMAKE_PREFIX_PATH items for a package."""
    prefix = get_install_prefix(work_dir, package, version)
    extras: dict[str, list[str]] = {
        "PATH": [],
        "LD_LIBRARY_PATH": [],
        "CMAKE_PREFIX_PATH": [],
        "PKG_CONFIG_PATH": [],
    }

    bin_dir = prefix / "bin"
    lib_dir = prefix / "lib"
    lib64_dir = prefix / "lib64"
    pkgconfig_dirs = [lib_dir / "pkgconfig", lib64_dir / "pkgconfig"]

    if bin_dir.exists():
        extras["PATH"].append(str(bin_dir))
    for ld in [lib_dir, lib64_dir]:
        if ld.exists():
            extras["LD_LIBRARY_PATH"].append(str(ld))
    extras["CMAKE_PREFIX_PATH"].append(str(prefix))
    for pc in pkgconfig_dirs:
        if pc.exists():
            extras["PKG_CONFIG_PATH"].append(str(pc))

    # ROOT-specific
    if package == "root":
        rootsys = prefix
        extras["ROOTSYS"] = [str(rootsys)]
        thisroot = rootsys / "bin" / "thisroot.sh"
        if thisroot.exists():
            extras["_ROOT_THISROOT"] = [str(thisroot)]

    # Geant4 data
    if package == "geant4":
        share = prefix / "share" / "Geant4" / "data"
        if share.exists():
            for d in share.iterdir():
                if d.is_dir():
                    env_var = d.name.upper().replace("-", "_").replace(".", "_") + "DATA"
                    extras[env_var] = [str(d)]

    return {k: os.pathsep.join(v) for k, v in extras.items() if v}


def build_env(work_dir: Path, packages: list[str], versions: dict) -> dict[str, str]:
    """Build a cumulative environment dict for all installed packages."""
    env = os.environ.copy()

    def prepend(key, val):
        old = env.get(key, "")
        env[key] = val + (os.pathsep + old if old else "")

    for pkg in packages:
        ver = versions[pkg]
        extras = env_for_package(work_dir, pkg, ver)
        for key, val in extras.items():
            if key.startswith("_ROOT_THISROOT"):
                continue
            prepend(key, val)

    return env


def detect_na6proot_source() -> Path:
    def is_na6proot_dir(path: Path) -> bool:
        return (path / "CMakeLists.txt").exists() and (path / "NA6PSim.cxx").exists()

    env_source = os.environ.get("NA6PROOT_SOURCE")
    if env_source:
        src = Path(env_source).expanduser().resolve()
        if is_na6proot_dir(src):
            return src
        raise FileNotFoundError(
            f"NA6PROOT_SOURCE is set to '{src}' but this is not a valid NA6PRoot source directory"
        )

    cwd = Path.cwd().resolve()
    candidates = [
        cwd,
        cwd / "NA6PRoot",
        cwd / "na6proot",
        cwd.parent / "NA6PRoot",
        cwd.parent / "na6proot",
        Path.home() / "NA6PRoot",
        Path.home() / "na6proot",
    ]

    for cand in candidates:
        cand = cand.resolve()
        if is_na6proot_dir(cand):
            return cand

    pkg_root = Path(__file__).resolve().parent.parent
    if is_na6proot_dir(pkg_root):
        return pkg_root

    # If not found anywhere, suggest cloning
    work_dir = Path(os.environ.get("BUILD_AREA", Path.home() / "na6pbuild_sw"))
    suggested_path = work_dir / "sources" / "NA6PRoot"
    
    tried = "\n  - ".join(str(p) for p in candidates + [pkg_root])
    raise FileNotFoundError(
        "Could not locate NA6PRoot source directory. "
        "Set NA6PROOT_SOURCE to a path containing CMakeLists.txt and NA6PSim.cxx,\n"
        "or the recipe will attempt to clone from GitHub to:\n"
        f"  {suggested_path}\n\n"
        f"Searched:\n  - {tried}"
    )



# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_doctor(_args, _work_dir, _versions):
    print(bold("==> Checking system prerequisites for na6pbuild\n"))
    ok = True
    pc_env = pkg_config_env()

    print("  Checking executables:")
    for name, cmd in SYSTEM_PREREQS.items():
        found = shutil.which(cmd)
        status = green("OK") if found else red("MISSING")
        print(f"    {name:<30} {status}" + (f"  ({found})" if found else ""))
        if not found:
            ok = False

    print("\n  Checking system libraries:")
    for name, check_cmd in SYSTEM_LIBS.items():
        try:
            subprocess.check_call(check_cmd, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, env=pc_env)
            status = green("OK")
        except (subprocess.CalledProcessError, FileNotFoundError):
            status = yellow("NOT FOUND (may be optional)")
        print(f"    {name:<45} {status}")

    print("\n  Checking required libraries:")
    for name, check_cmd in REQUIRED_SYSTEM_LIBS.items():
        try:
            subprocess.check_call(check_cmd, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, env=pc_env)
            status = green("OK")
        except (subprocess.CalledProcessError, FileNotFoundError):
            status = red("MISSING")
            ok = False
        print(f"    {name:<45} {status}")

    cmake_ver = subprocess.run(["cmake", "--version"], capture_output=True, text=True)
    if cmake_ver.returncode == 0:
        ver_line = cmake_ver.stdout.splitlines()[0]
        print(f"\n  cmake version: {ver_line.split()[-1]}")

    print()
    if ok:
        print(green("  All required tools are present."))
    else:
        print(red("  Some required tools are missing. Please install them before building."))
    return 0 if ok else 1


def cmd_list(args, work_dir: Path, versions: dict):
    state = load_state(work_dir)
    print(bold(f"\n  {'Package':<15} {'Version':<12} {'Status':<12} {'Install prefix'}"))
    print("  " + "-" * 70)
    for pkg in DEPENDENCIES:
        ver = versions[pkg]
        prefix = get_install_prefix(work_dir, pkg, ver)
        pkg_state = state.get(pkg, {})
        built_ver = pkg_state.get("version")
        if built_ver == ver and prefix.exists():
            status = green("installed")
        elif pkg_state.get("version"):
            status = yellow(f"stale ({built_ver})")
        else:
            status = "not built"
        print(f"  {pkg:<15} {ver:<12} {status:<22} {prefix}")
    print()
    return 0


def cmd_env(args, work_dir: Path, versions: dict):
    packages = args.packages or list(DEPENDENCIES.keys())
    order = topo_sort(packages, DEPENDENCIES)

    for pkg in order:
        ver = versions[pkg]
        prefix = get_install_prefix(work_dir, pkg, ver)
        if not prefix.exists():
            continue
        extras = env_for_package(work_dir, pkg, ver)
        thisroot = extras.pop("_ROOT_THISROOT", None)
        if thisroot:
            print(f'source "{thisroot}"')
        for key, val in extras.items():
            print(f'export {key}="{val}:${key}"')

    # Also emit CMAKE_PREFIX_PATH summary
    return 0


def cmd_clean(args, work_dir: Path, versions: dict):
    packages = args.packages or []
    if not packages:
        error("Specify package(s) to clean, or use --all.")
        return 1
    state = load_state(work_dir)
    for pkg in packages:
        ver = versions.get(pkg, DEFAULT_VERSIONS.get(pkg, ""))
        prefix = get_install_prefix(work_dir, pkg, ver)
        build_dir = work_dir / "builds" / f"{pkg}-{ver}"
        removed = []
        for d in [prefix, build_dir]:
            if d.exists():
                shutil.rmtree(d)
                removed.append(str(d))
        if pkg in state:
            del state[pkg]
        save_state(work_dir, state)
        if removed:
            info(f"Removed: {', '.join(removed)}")
        else:
            info(f"{pkg}: nothing to clean")
    return 0


def run_recipe(recipe: Path, env: dict, log_path: Path) -> int:
    """Execute a recipe shell script, streaming output to log and stdout."""
    info(f"Log: {log_path}")
    with open(log_path, "w") as log_f:
        proc = subprocess.Popen(
            ["bash", "-euo", "pipefail", str(recipe)],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        assert proc.stdout is not None
        for line in proc.stdout:
            sys.stdout.write("    " + line)
            log_f.write(line)
        proc.wait()
    return proc.returncode


def cmd_build(args, work_dir: Path, versions: dict):
    packages = args.packages or ["na6proot"]
    build_order = topo_sort(packages, DEPENDENCIES)
    state = load_state(work_dir)
    jobs = str(args.jobs)

    print(bold(f"\n==> Build plan: {' → '.join(build_order)}\n"))

    recipes_dir = get_recipes_dir()

    for pkg in build_order:
        ver = versions[pkg]
        prefix = get_install_prefix(work_dir, pkg, ver)
        pkg_state = state.get(pkg, {})
        already_built = pkg_state.get("version") == ver and prefix.exists()

        # For na6proot, also check if the source has changed since last build
        if already_built and pkg == "na6proot":
            try:
                na6proot_src_env = os.environ.get("NA6PROOT_SOURCE", "")
                src_dir = Path(na6proot_src_env).resolve() if na6proot_src_env else detect_na6proot_source()
                current_hash = hash_source_dir(src_dir)
                stored_hash = pkg_state.get("source_hash")
                if stored_hash != current_hash:
                    info(f"{bold(pkg)}: source changed (stored={stored_hash[:8]}..., current={current_hash[:8]}...), rebuilding...")
                    already_built = False
            except FileNotFoundError:
                pass  # will fail later with a proper error

        if already_built and not args.force:
            info(f"{bold(pkg)} {ver}  {green('already installed, skipping')}")
            continue

        recipe = recipes_dir / f"{pkg}.sh"
        if not recipe.exists():
            searched = "\n    - ".join(str(p / f"{pkg}.sh") for p in _candidate_recipes_dirs())
            error(
                f"No recipe found for '{pkg}'\n"
                f"  expected: {recipe}\n"
                f"  searched:\n    - {searched}\n"
                "  tip: set NA6PBUILD_RECIPES_DIR=/path/to/recipes"
            )
            return 1

        info(f"Building {bold(pkg)} {ver}...")

        # Collect env from all packages built so far
        built_pkgs = [p for p in build_order[:build_order.index(pkg)]
                      if state.get(p, {}).get("version") == versions[p]]
        env = build_env(work_dir, built_pkgs, versions)

        # Inject na6pbuild_prefix shell function
        preamble = na6pbuild_prefix_func(work_dir, versions)

        # Set recipe-specific env vars
        env["BUILD_AREA"] = str(work_dir)
        env["INSTALL_PREFIX"] = str(prefix)
        env["JOBS"] = jobs
        env[f"{pkg.upper()}_VERSION"] = ver
        # Source directory only needed for na6proot
        if pkg == "na6proot":
            try:
                env["NA6PROOT_SOURCE"] = str(detect_na6proot_source())
            except FileNotFoundError as exc:
                error(str(exc))
                return 1

        # Write a wrapper that sources the preamble, then runs the recipe
        wrapper = work_dir / "tmp" / f"build_{pkg}.sh"
        wrapper.parent.mkdir(parents=True, exist_ok=True)
        wrapper.write_text(
            f"#!/usr/bin/env bash\nset -euo pipefail\n\n{preamble}\n\n"
            + recipe.read_text()
        )
        wrapper.chmod(0o755)

        log_path = get_build_log(work_dir, pkg)
        rc = run_recipe(wrapper, env, log_path)
        if rc != 0:
            error(f"Build of {pkg} FAILED (exit code {rc}). See log: {log_path}")
            return rc

        state[pkg] = {"version": ver}
        # For na6proot, record the source hash so we can detect future changes
        if pkg == "na6proot":
            try:
                na6proot_src_env = env.get("NA6PROOT_SOURCE", "")
                src_dir = Path(na6proot_src_env).resolve() if na6proot_src_env else detect_na6proot_source()
                if src_dir.is_dir():
                    state[pkg]["source_hash"] = hash_source_dir(src_dir)
            except Exception:
                pass
        save_state(work_dir, state)
        print(f"  {green('✓')} {bold(pkg)} {ver} installed to {prefix}\n")

    print(bold(green("==> All packages built successfully.\n")))
    print("  To load the environment, run:")
    print(f"    eval $(na6pbuild env {' '.join(packages)})")
    print("  or source the generated env script:")
    env_script = work_dir / "env.sh"
    _write_env_script(env_script, work_dir, build_order, versions)
    print(f"    source {env_script}\n")
    return 0


def _write_env_script(path: Path, work_dir: Path, packages: list[str], versions: dict):
    lines = [
        "#!/usr/bin/env bash",
        "# Auto-generated by na6pbuild - source this file to set up the environment",
        "",
    ]
    for pkg in packages:
        ver = versions[pkg]
        prefix = get_install_prefix(work_dir, pkg, ver)
        if not prefix.exists():
            continue
        extras = env_for_package(work_dir, pkg, ver)
        thisroot = extras.pop("_ROOT_THISROOT", None)
        if thisroot:
            lines.append(f'source "{thisroot}"')
        for key, val in extras.items():
            lines.append(f'export {key}="{val}:${{{key}:-}}"')
    path.write_text("\n".join(lines) + "\n")
    path.chmod(0o755)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="na6pbuild – build NA6PRoot and its dependencies",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""
        Examples:
          na6pbuild build na6proot
          na6pbuild build --jobs 8 --force geant4
          na6pbuild list
          na6pbuild env na6proot
          na6pbuild clean geant4 vgm
          na6pbuild doctor
        """),
    )
    parser.add_argument(
        "--work-dir", "-w",
        default=os.environ.get("NA6PBUILD_WORK_DIR",
                               str(Path.home() / "na6pbuild_sw")),
        help="Working directory for sources, builds, and installs "
             "(default: ~/na6pbuild_sw or $NA6PBUILD_WORK_DIR)",
    )
    parser.add_argument(
        "--architecture", "-a",
        default=None,
        help="Target architecture tag (informational, not yet used for selection)",
    )

    # Per-package version overrides
    for pkg, ver in DEFAULT_VERSIONS.items():
        parser.add_argument(
            f"--{pkg}-version",
            default=os.environ.get(f"{pkg.upper()}_VERSION", ver),
            metavar="VER",
            dest=f"{pkg.replace('-', '_')}_version",
            help=f"{pkg} version (default: {ver})",
        )

    subparsers = parser.add_subparsers(dest="command", required=True)

    # build
    p_build = subparsers.add_parser("build", help="Build packages and dependencies")
    p_build.add_argument("packages", nargs="*", help="Packages to build (default: na6proot)")
    p_build.add_argument("--jobs", "-j", type=int, default=max(1, os.cpu_count() or 4),
                         help="Parallel build jobs (default: number of CPUs)")
    p_build.add_argument("--force", "-f", action="store_true",
                         help="Rebuild even if already installed")

    # list
    subparsers.add_parser("list", help="List packages and build status")

    # env
    p_env = subparsers.add_parser("env", help="Print environment setup commands")
    p_env.add_argument("packages", nargs="*", help="Packages (default: all)")

    # clean
    p_clean = subparsers.add_parser("clean", help="Remove build artifacts")
    p_clean.add_argument("packages", nargs="+", help="Packages to clean")
    p_clean.add_argument("--all", action="store_true", help="Clean all packages")

    # doctor
    subparsers.add_parser("doctor", help="Check system prerequisites")

    args = parser.parse_args()

    work_dir = Path(args.work_dir).expanduser().resolve()
    work_dir.mkdir(parents=True, exist_ok=True)

    # Collect versions from parsed args
    versions = {
        pkg: getattr(args, f"{pkg.replace('-', '_')}_version", DEFAULT_VERSIONS[pkg])
        for pkg in DEFAULT_VERSIONS
    }

    dispatch = {
        "build":  cmd_build,
        "list":   cmd_list,
        "env":    cmd_env,
        "clean":  cmd_clean,
        "doctor": cmd_doctor,
    }

    handler = dispatch.get(args.command)
    if handler is None:
        parser.print_help()
        return 1

    sys.exit(handler(args, work_dir, versions) or 0)


if __name__ == "__main__":
    main()
