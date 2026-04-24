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

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DROOT_DIR="${ROOT_PREFIX}/cmake" \
  -DGeant4_DIR="${GEANT4_PREFIX}/lib/cmake/Geant4" \
  -DVMC_DIR="${VMC_PREFIX}/lib/cmake/vmc" \
  -DVGM_DIR="${VGM_PREFIX}/lib/cmake/VGM" \
  -DGeant4VMC_DIR="${GEANT4VMC_PREFIX}/lib/cmake/Geant4VMC" \
  -DHepMC3_DIR="${HEPMC3_PREFIX}/share/HepMC3/cmake" \
  -DPYTHIA8_DIR="${PYTHIA8_PREFIX}" \
  -DBoost_ROOT="${BOOST_PREFIX}" \
  -Dfmt_DIR="${FMT_PREFIX}/lib/cmake/fmt" \
  -DFairLogger_DIR="${FAIRLOGGER_PREFIX}/lib/cmake/FairLogger"

cmake --build . -j"${JOBS:-4}"
cmake --install .
