#!/usr/bin/env bash
# Recipe: fmt
set -euo pipefail

VERSION="${FMT_VERSION:-10.2.1}"
URL="https://github.com/fmtlib/fmt/archive/refs/tags/${VERSION}.tar.gz"

SOURCE_DIR="$BUILD_AREA/sources/fmt-${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/fmt-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources"
  echo "==> Downloading fmt ${VERSION}..."
  curl -L "$URL" -o "/tmp/fmt-${VERSION}.tar.gz"
  tar xzf "/tmp/fmt-${VERSION}.tar.gz" -C "$BUILD_AREA/sources"
fi

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DFMT_TEST=OFF \
  -DFMT_DOC=OFF \
  -DBUILD_SHARED_LIBS=ON

cmake --build . -j"${JOBS:-4}"
cmake --install .
