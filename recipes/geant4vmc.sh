#!/usr/bin/env bash
# Recipe: Geant4VMC
set -euo pipefail

VERSION="${GEANT4VMC_VERSION:-6.6}"
SOURCE_DIR="$BUILD_AREA/sources/geant4_vmc-${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/geant4vmc-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources"
  echo "==> Cloning Geant4VMC ${VERSION}..."
  git clone --depth 1 --branch "v${VERSION//./-}" \
    https://github.com/vmc-project/geant4_vmc.git "$SOURCE_DIR"
fi

ROOT_PREFIX="$(na6pbuild_prefix root)"
GEANT4_PREFIX="$(na6pbuild_prefix geant4)"
VMC_PREFIX="$(na6pbuild_prefix vmc)"
VGM_PREFIX="$(na6pbuild_prefix vgm)"

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

if [ -f CMakeCache.txt ]; then
  cached_source="$(sed -n 's|^CMAKE_HOME_DIRECTORY:INTERNAL=||p' CMakeCache.txt | head -n1 || true)"
  if [ -n "$cached_source" ] && [ "$cached_source" != "$SOURCE_DIR" ]; then
    echo "==> Detected stale CMake cache (old source: $cached_source)"
    echo "==> Resetting build directory for Geant4VMC..."
    rm -rf CMakeCache.txt CMakeFiles
  fi
fi

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DROOT_DIR="${ROOT_PREFIX}/cmake" \
  -DGeant4_DIR="${GEANT4_PREFIX}/lib/cmake/Geant4" \
  -DVMC_DIR="${VMC_PREFIX}/lib/cmake/vmc" \
  -DVGM_DIR="${VGM_PREFIX}/lib/cmake/VGM" \
  -DWITH_TEST=OFF \
  -DWITH_EXAMPLES=OFF \
  -DWITH_MTRoot=OFF

cmake --build . -j"${JOBS:-4}"
cmake --install .
