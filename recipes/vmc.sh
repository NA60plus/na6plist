#!/usr/bin/env bash
# Recipe: VMC (Virtual Monte Carlo core)
set -euo pipefail

VERSION="${VMC_VERSION:-2.1}"
SOURCE_DIR="$BUILD_AREA/sources/vmc-${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/vmc-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources"
  echo "==> Cloning VMC ${VERSION}..."
  git clone --depth 1 --branch "v${VERSION//./-}" \
    https://github.com/vmc-project/vmc.git "$SOURCE_DIR"
fi

ROOT_PREFIX="$(na6pbuild_prefix root)"

if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
  CACHED_SOURCE="$(grep '^CMAKE_HOME_DIRECTORY:INTERNAL=' "$BUILD_DIR/CMakeCache.txt" | cut -d= -f2- || true)"
  if [ -n "$CACHED_SOURCE" ] && [ "$CACHED_SOURCE" != "$SOURCE_DIR" ]; then
    echo "==> Detected stale VMC CMake cache (source changed). Resetting build dir..."
    rm -rf "$BUILD_DIR"
  fi
fi

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DROOT_DIR="${ROOT_PREFIX}/cmake" \
  -DVMC_BUILD_EXAMPLES=OFF

cmake --build . -j"${JOBS:-4}"
cmake --install .
