#!/usr/bin/env bash
# Recipe: VGM (Virtual Geometry Model)
set -euo pipefail

VERSION="${VGM_VERSION:-5.3}"
SOURCE_DIR="$BUILD_AREA/sources/vgm-${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/vgm-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources"
  echo "==> Cloning VGM ${VERSION}..."
  git clone --depth 1 --branch "v${VERSION//./-}" \
    https://github.com/vmc-project/vgm.git "$SOURCE_DIR"
fi

ROOT_PREFIX="$(na6pbuild_prefix root)"
GEANT4_PREFIX="$(na6pbuild_prefix geant4)"

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DROOT_DIR="${ROOT_PREFIX}/cmake" \
  -DGeant4_DIR="${GEANT4_PREFIX}/lib/Geant4-$(echo ${GEANT4_VERSION:-11.2.2} | sed 's/\.[0-9]*$//')" \
  -DWITH_TEST=OFF \
  -DWITH_EXAMPLES=OFF

cmake --build . -j"${JOBS:-4}"
cmake --install .
