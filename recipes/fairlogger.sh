#!/usr/bin/env bash
# Recipe: FairLogger
set -euo pipefail

VERSION="${FAIRLOGGER_VERSION:-1.11.1}"
URL="https://github.com/FairRootGroup/FairLogger/archive/refs/tags/v${VERSION}.tar.gz"

SOURCE_DIR="$BUILD_AREA/sources/FairLogger-${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/FairLogger-${VERSION}"
ARCHIVE_DIR="$BUILD_AREA/builds/FairLogger-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources" "$ARCHIVE_DIR"
  echo "==> Downloading FairLogger ${VERSION}..."
  curl -L "$URL" -o "$ARCHIVE_DIR/FairLogger-${VERSION}.tar.gz"
  tar xzf "$ARCHIVE_DIR/FairLogger-${VERSION}.tar.gz" -C "$BUILD_AREA/sources"
fi

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

if [ -f CMakeCache.txt ]; then
  cached_source="$(sed -n 's|^CMAKE_HOME_DIRECTORY:INTERNAL=||p' CMakeCache.txt | head -n1 || true)"
  if [ -n "$cached_source" ] && [ "$cached_source" != "$SOURCE_DIR" ]; then
    echo "==> Detected stale CMake cache (old source: $cached_source)"
    echo "==> Resetting build directory for FairLogger..."
    rm -rf CMakeCache.txt CMakeFiles
  fi
fi

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_EXTERNAL_FMT=ON \
  -Dfmt_DIR="$(na6pbuild_prefix fmt)/lib/cmake/fmt" \
  -DBUILD_TESTING=OFF

cmake --build . -j"${JOBS:-4}"
cmake --install .

find "${BUILD_AREA}/builds" -maxdepth 2 \( -name "*.tar.gz" -o -name "*.tgz" \) -delete
