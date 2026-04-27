#!/usr/bin/env bash
# Recipe: NA6PRoot itself
set -euo pipefail

SOURCE_DIR="${NA6PROOT_SOURCE:-$(cd "$(dirname "$0")/.." && pwd)}"
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

# NA6PRoot requires HDF5 at configure time
HDF5_PKG=""
if pkg-config --exists hdf5 2>/dev/null; then
  HDF5_PKG="hdf5"
elif pkg-config --exists hdf5-serial 2>/dev/null; then
  HDF5_PKG="hdf5-serial"
fi

if [ -n "$HDF5_PKG" ]; then
  HDF5_PREFIX="$(pkg-config --variable=prefix "$HDF5_PKG" 2>/dev/null || true)"
  if [ -n "$HDF5_PREFIX" ]; then
    export HDF5_ROOT="$HDF5_PREFIX"
  fi
elif command -v h5cc >/dev/null 2>&1; then
  H5CC_BIN="$(command -v h5cc)"
  export HDF5_ROOT="$(cd "$(dirname "$H5CC_BIN")/.." && pwd)"
  export HDF5_C_COMPILER_EXECUTABLE="$H5CC_BIN"
  if command -v h5c++ >/dev/null 2>&1; then
    export HDF5_CXX_COMPILER_EXECUTABLE="$(command -v h5c++)"
  fi
else
  echo "ERROR: HDF5 not found (neither pkg-config module hdf5/hdf5-serial nor h5cc wrapper)."
  echo "Install HDF5 development package (e.g. libhdf5-dev) or expose your custom install in PATH/PKG_CONFIG_PATH."
  exit 1
fi

CMAKE_HDF5_ARGS=()
if [ -n "${HDF5_ROOT:-}" ]; then
  CMAKE_HDF5_ARGS+=("-DHDF5_ROOT=${HDF5_ROOT}")
  if [ -d "${HDF5_ROOT}/include" ]; then
    CMAKE_HDF5_ARGS+=("-DHDF5_INCLUDE_DIR=${HDF5_ROOT}/include")
    CMAKE_HDF5_ARGS+=("-DHDF5_INCLUDE_DIRS=${HDF5_ROOT}/include")
    CMAKE_HDF5_ARGS+=("-DHDF5_CXX_INCLUDE_DIR=${HDF5_ROOT}/include")
  fi
fi
if [ -n "${HDF5_C_COMPILER_EXECUTABLE:-}" ]; then
  CMAKE_HDF5_ARGS+=("-DHDF5_C_COMPILER_EXECUTABLE=${HDF5_C_COMPILER_EXECUTABLE}")
fi
if [ -n "${HDF5_CXX_COMPILER_EXECUTABLE:-}" ]; then
  CMAKE_HDF5_ARGS+=("-DHDF5_CXX_COMPILER_EXECUTABLE=${HDF5_CXX_COMPILER_EXECUTABLE}")
elif [ -n "${HDF5_C_COMPILER_EXECUTABLE:-}" ]; then
  CMAKE_HDF5_ARGS+=("-DHDF5_CXX_COMPILER_EXECUTABLE=${HDF5_C_COMPILER_EXECUTABLE}")
fi
CMAKE_HDF5_ARGS+=("-DHDF5_CXX_COMPILER_NO_INTERROGATE=TRUE")

# Some custom HDF5 builds provide C+HL but no separate C++ libs.
# NA6PRoot requests HDF5 CXX component; provide compatible fallbacks.
if [ -n "${HDF5_ROOT:-}" ] && [ -f "${HDF5_ROOT}/lib/libhdf5.so" ] && [ ! -f "${HDF5_ROOT}/lib/libhdf5_cpp.so" ]; then
  CMAKE_HDF5_ARGS+=("-DHDF5_hdf5_cpp_LIBRARY=${HDF5_ROOT}/lib/libhdf5.so")
  CMAKE_HDF5_ARGS+=("-DHDF5_hdf5_cpp_LIBRARY_RELEASE=${HDF5_ROOT}/lib/libhdf5.so")
  CMAKE_HDF5_ARGS+=("-DHDF5_hdf5_cpp_LIBRARY_DEBUG=${HDF5_ROOT}/lib/libhdf5.so")
fi
if [ -n "${HDF5_ROOT:-}" ] && [ -f "${HDF5_ROOT}/lib/libhdf5_hl.so" ] && [ ! -f "${HDF5_ROOT}/lib/libhdf5_hl_cpp.so" ]; then
  CMAKE_HDF5_ARGS+=("-DHDF5_hdf5_hl_cpp_LIBRARY=${HDF5_ROOT}/lib/libhdf5_hl.so")
  CMAKE_HDF5_ARGS+=("-DHDF5_hdf5_hl_cpp_LIBRARY_RELEASE=${HDF5_ROOT}/lib/libhdf5_hl.so")
  CMAKE_HDF5_ARGS+=("-DHDF5_hdf5_hl_cpp_LIBRARY_DEBUG=${HDF5_ROOT}/lib/libhdf5_hl.so")
fi

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
