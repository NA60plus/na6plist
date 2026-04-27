#!/usr/bin/env bash
# Recipe: fmt
set -euo pipefail

VERSION="${FMT_VERSION:-10.2.1}"
URL="https://github.com/fmtlib/fmt/archive/refs/tags/${VERSION}.tar.gz"

SOURCE_DIR="$BUILD_AREA/sources/fmt-${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/fmt-${VERSION}"
ARCHIVE_DIR="$BUILD_AREA/builds/fmt-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources" "$ARCHIVE_DIR"
  echo "==> Downloading fmt ${VERSION}..."
  curl -L "$URL" -o "$ARCHIVE_DIR/fmt-${VERSION}.tar.gz"
  tar xzf "$ARCHIVE_DIR/fmt-${VERSION}.tar.gz" -C "$BUILD_AREA/sources"
fi

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

if [ -f CMakeCache.txt ]; then
  cached_source="$(sed -n 's|^CMAKE_HOME_DIRECTORY:INTERNAL=||p' CMakeCache.txt | head -n1 || true)"
  if [ -n "$cached_source" ] && [ "$cached_source" != "$SOURCE_DIR" ]; then
    echo "==> Detected stale CMake cache (old source: $cached_source)"
    echo "==> Resetting build directory for fmt..."
    rm -rf CMakeCache.txt CMakeFiles
  fi
fi

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DFMT_TEST=OFF \
  -DFMT_DOC=OFF \
  -DBUILD_SHARED_LIBS=ON

cmake --build . -j"${JOBS:-4}"
cmake --install .

find "${BUILD_AREA}/builds" -maxdepth 2 \( -name "*.tar.gz" -o -name "*.tgz" \) -delete
