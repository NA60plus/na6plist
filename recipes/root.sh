#!/usr/bin/env bash
# Recipe: ROOT
set -euo pipefail

VERSION="${ROOT_VERSION:-6.32.02}"
URL="https://root.cern/download/root_v${VERSION}.source.tar.gz"

SOURCE_DIR="$BUILD_AREA/sources/root-${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/root-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources"
  echo "==> Downloading ROOT ${VERSION}..."
  curl -L "$URL" -o "/tmp/root-${VERSION}.tar.gz"
  tar xzf "/tmp/root-${VERSION}.tar.gz" -C "$BUILD_AREA/sources"
  # ROOT tarball extracts to root-<version>
  if [ ! -d "$SOURCE_DIR" ]; then
    mv "$BUILD_AREA/sources/root-${VERSION}" "$SOURCE_DIR" 2>/dev/null || true
  fi
fi

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

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
