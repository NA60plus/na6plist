#!/usr/bin/env bash
# Recipe: Geant4
set -euo pipefail

VERSION="${GEANT4_VERSION:-11.2.2}"
URL="https://gitlab.cern.ch/geant4/geant4/-/archive/v${VERSION}/geant4-v${VERSION}.tar.gz"

SOURCE_DIR="$BUILD_AREA/sources/geant4-v${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/geant4-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources"
  echo "==> Downloading Geant4 ${VERSION}..."
  curl -L "$URL" -o "/tmp/geant4-${VERSION}.tar.gz"
  tar xzf "/tmp/geant4-${VERSION}.tar.gz" -C "$BUILD_AREA/sources"
fi

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

cmake "$SOURCE_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGEANT4_INSTALL_DATA=ON \
  -DGEANT4_USE_GDML=ON \
  -DGEANT4_USE_QT=OFF \
  -DGEANT4_USE_OPENGL_X11=ON \
  -DGEANT4_BUILD_MULTITHREADED=OFF \
  -DGEANT4_USE_SYSTEM_EXPAT=ON

cmake --build . -j"${JOBS:-4}"
cmake --install .
