#!/usr/bin/env bash
# Recipe: HepMC3
set -euo pipefail

VERSION="${HEPMC3_VERSION:-3.3.1}"
SOURCE_DIR="$BUILD_AREA/sources/HepMC3-${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/hepmc3-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources"
  echo "==> Cloning HepMC3 ${VERSION}..."
  git clone --depth 1 --branch "${VERSION}" \
    https://gitlab.cern.ch/hepmc/HepMC3.git "$SOURCE_DIR"
fi

ROOT_PREFIX="$(na6pbuild_prefix root)"

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

if [ -f CMakeCache.txt ]; then
  cached_source="$(sed -n 's|^CMAKE_HOME_DIRECTORY:INTERNAL=||p' CMakeCache.txt | head -n1 || true)"
  if [ -n "$cached_source" ] && [ "$cached_source" != "$SOURCE_DIR" ]; then
    echo "==> Detected stale CMake cache (old source: $cached_source)"
    echo "==> Resetting build directory for HepMC3..."
    rm -rf CMakeCache.txt CMakeFiles
  fi
fi

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DHEPMC3_ENABLE_ROOTIO=ON \
  -DROOT_DIR="${ROOT_PREFIX}/cmake" \
  -DHEPMC3_ENABLE_PYTHON=OFF \
  -DHEPMC3_BUILD_EXAMPLES=OFF

cmake --build . -j"${JOBS:-4}"
cmake --install .

find "${BUILD_AREA}/builds" -maxdepth 2 \( -name "*.tar.gz" -o -name "*.tgz" \) -delete
