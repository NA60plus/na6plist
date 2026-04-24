#!/usr/bin/env bash
# Recipe: FairLogger
set -euo pipefail

VERSION="${FAIRLOGGER_VERSION:-1.11.1}"
URL="https://github.com/FairRootGroup/FairLogger/archive/refs/tags/v${VERSION}.tar.gz"

SOURCE_DIR="$BUILD_AREA/sources/FairLogger-${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/FairLogger-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources"
  echo "==> Downloading FairLogger ${VERSION}..."
  curl -L "$URL" -o "/tmp/FairLogger-${VERSION}.tar.gz"
  tar xzf "/tmp/FairLogger-${VERSION}.tar.gz" -C "$BUILD_AREA/sources"
fi

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_EXTERNAL_FMT=ON \
  -Dfmt_DIR="$(na6pbuild_prefix fmt)/lib/cmake/fmt" \
  -DBUILD_TESTING=OFF

cmake --build . -j"${JOBS:-4}"
cmake --install .
