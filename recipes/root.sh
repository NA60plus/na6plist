#!/usr/bin/env bash
# Recipe: ROOT
set -euo pipefail

VERSION="${ROOT_VERSION:-6.32.02}"
URL="https://root.cern/download/root_v${VERSION}.source.tar.gz"

SOURCE_DIR="$BUILD_AREA/sources/root-${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/root-${VERSION}"
ARCHIVE_DIR="$BUILD_AREA/builds/root-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources" "$ARCHIVE_DIR"
  echo "==> Downloading ROOT ${VERSION}..."
  curl -L "$URL" -o "$ARCHIVE_DIR/root-${VERSION}.tar.gz"
  tar xzf "$ARCHIVE_DIR/root-${VERSION}.tar.gz" -C "$BUILD_AREA/sources"
  # ROOT tarball extracts to root-<version>
  if [ ! -d "$SOURCE_DIR" ]; then
    mv "$BUILD_AREA/sources/root-${VERSION}" "$SOURCE_DIR" 2>/dev/null || true
  fi
fi

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

if [ -f CMakeCache.txt ]; then
  cached_source="$(sed -n 's|^CMAKE_HOME_DIRECTORY:INTERNAL=||p' CMakeCache.txt | head -n1 || true)"
  if [ -n "$cached_source" ] && [ "$cached_source" != "$SOURCE_DIR" ]; then
    echo "==> Detected stale CMake cache (old source: $cached_source)"
    echo "==> Resetting build directory for ROOT..."
    rm -rf CMakeCache.txt CMakeFiles
  fi
fi

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_STANDARD=20 \
  -Dclad=OFF \
  -Dpython3=ON \
  -Dx11=ON \
  -Dssl=ON \
  -Dmathmore=ON \
  -Dxrootd=OFF \
  -Dfitsio=OFF \
  -Dbuiltin_cfitsio=OFF

cmake --build . -j"${JOBS:-4}"
cmake --install .

find "${BUILD_AREA}/builds" -maxdepth 2 \( -name "*.tar.gz" -o -name "*.tgz" \) -delete
