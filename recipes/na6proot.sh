#!/usr/bin/env bash
# Recipe: NA6PRoot itself
set -euo pipefail

# If NA6PROOT_SOURCE is not set, clone from GitHub if not already present
if [ -z "${NA6PROOT_SOURCE:-}" ]; then
  SOURCE_DIR="$BUILD_AREA/sources/NA6PRoot"
  
  # Try to find it in common locations first
  for candidate in "$(cd "$(dirname "$0")/.." && pwd)" "$HOME/NA6PRoot" "$HOME/na6proot"; do
    if [ -d "$candidate" ] && [ -f "$candidate/CMakeLists.txt" ] && [ -f "$candidate/NA6PSim.cxx" ]; then
      SOURCE_DIR="$candidate"
      break
    fi
  done
  
  # If not found in common locations, clone from GitHub
  if [ ! -d "$SOURCE_DIR" ] || [ ! -f "$SOURCE_DIR/CMakeLists.txt" ]; then
    mkdir -p "$BUILD_AREA/sources"
    echo "==> Cloning NA6PRoot from GitHub..."
    git clone https://github.com/shahor02/NA6PRoot.git "$SOURCE_DIR"
  fi
else
  SOURCE_DIR="$NA6PROOT_SOURCE"
fi

BUILD_DIR="$BUILD_AREA/builds/na6proot"

ROOT_PREFIX="$(na6pbuild_prefix root)"
GEANT4_PREFIX="$(na6pbuild_prefix geant4)"
VMC_PREFIX="$(na6pbuild_prefix vmc)"
VGM_PREFIX="$(na6pbuild_prefix vgm)"
GEANT4VMC_PREFIX="$(na6pbuild_prefix geant4vmc)"
HEPMC3_PREFIX="$(na6pbuild_prefix hepmc3)"
PYTHIA8_PREFIX="$(na6pbuild_prefix pythia8)"
BOOST_PREFIX="$(na6pbuild_prefix boost)"
FMT_PREFIX="$(na6pbuild_prefix fmt)"
FAIRLOGGER_PREFIX="$(na6pbuild_prefix fairlogger)"

find_cmake_dir() {
  local prefix="$1"
  local package="$2"
  local guessed="$3"
  if [ -f "${guessed}/${package}Config.cmake" ]; then
    echo "${guessed}"
    return 0
  fi
  local found
  found="$(find "${prefix}" -type f -name "${package}Config.cmake" 2>/dev/null | head -n1 || true)"
  if [ -n "${found}" ]; then
    dirname "${found}"
    return 0
  fi
  echo "${guessed}"
}

FAIRLOGGER_CMAKE_DIR="${FAIRLOGGER_PREFIX}/lib/cmake/FairLogger"
if [ ! -f "${FAIRLOGGER_CMAKE_DIR}/FairLoggerConfig.cmake" ]; then
  FOUND_FAIRLOGGER_CONFIG="$(find "${FAIRLOGGER_PREFIX}" -type f -name FairLoggerConfig.cmake 2>/dev/null | head -n1 || true)"
  if [ -n "${FOUND_FAIRLOGGER_CONFIG}" ]; then
    FAIRLOGGER_CMAKE_DIR="$(dirname "${FOUND_FAIRLOGGER_CONFIG}")"
  fi
fi

VMC_CMAKE_DIR="$(find_cmake_dir "${VMC_PREFIX}" "VMC" "${VMC_PREFIX}/lib/cmake/vmc")"
VGM_CMAKE_DIR="$(find_cmake_dir "${VGM_PREFIX}" "VGM" "${VGM_PREFIX}/lib/cmake/VGM")"
GEANT4VMC_CMAKE_DIR="$(find_cmake_dir "${GEANT4VMC_PREFIX}" "Geant4VMC" "${GEANT4VMC_PREFIX}/lib/cmake/Geant4VMC")"

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

# Allow pkg-config to discover local installs (e.g. ~/local)
for pcdir in "$HOME/local/lib/pkgconfig" "$HOME/local/lib64/pkgconfig"; do
  if [ -d "$pcdir" ]; then
    export PKG_CONFIG_PATH="$pcdir:${PKG_CONFIG_PATH:-}"
  fi
done

# Ensure clean re-configure in case prior cache kept NOTFOUND entries
rm -f CMakeCache.txt
rm -rf CMakeFiles

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DWITH_FLUKA=OFF \
  -DCMAKE_PREFIX_PATH="${BOOST_PREFIX};${FMT_PREFIX};${FAIRLOGGER_PREFIX};${ROOT_PREFIX};${GEANT4_PREFIX};${VMC_PREFIX};${VGM_PREFIX};${GEANT4VMC_PREFIX};${HEPMC3_PREFIX};${PYTHIA8_PREFIX};${HDF5_ROOT:-}" \
  "${CMAKE_HDF5_ARGS[@]}" \
  -DROOT_DIR="${ROOT_PREFIX}/cmake" \
  -DGeant4_DIR="${GEANT4_PREFIX}/lib/cmake/Geant4" \
  -DVMC_DIR="${VMC_CMAKE_DIR}" \
  -DVGM_DIR="${VGM_CMAKE_DIR}" \
  -DGeant4VMC_DIR="${GEANT4VMC_CMAKE_DIR}" \
  -DHepMC3_DIR="${HEPMC3_PREFIX}/share/HepMC3/cmake" \
  -DPYTHIA8_DIR="${PYTHIA8_PREFIX}" \
  -DBoost_ROOT="${BOOST_PREFIX}" \
  -Dfmt_DIR="${FMT_PREFIX}/lib/cmake/fmt" \
  -DFairLogger_DIR="${FAIRLOGGER_CMAKE_DIR}"

cmake --build . -j"${JOBS:-4}"
cmake --install .

find "${BUILD_AREA}/builds" -maxdepth 2 \( -name "*.tar.gz" -o -name "*.tgz" \) -delete
