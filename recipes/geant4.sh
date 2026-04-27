#!/usr/bin/env bash
# Recipe: Geant4
set -euo pipefail

VERSION="${GEANT4_VERSION:-11.2.2}"
URL="https://gitlab.cern.ch/geant4/geant4/-/archive/v${VERSION}/geant4-v${VERSION}.tar.gz"

SOURCE_DIR="$BUILD_AREA/sources/geant4-v${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/geant4-${VERSION}"
ARCHIVE_DIR="$BUILD_AREA/builds/geant4-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources" "$ARCHIVE_DIR"
  echo "==> Downloading Geant4 ${VERSION}..."
  curl -L "$URL" -o "$ARCHIVE_DIR/geant4-${VERSION}.tar.gz"
  tar xzf "$ARCHIVE_DIR/geant4-${VERSION}.tar.gz" -C "$BUILD_AREA/sources"
fi

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"
cd "$BUILD_DIR"

if [ -f CMakeCache.txt ]; then
  cached_source="$(sed -n 's|^CMAKE_HOME_DIRECTORY:INTERNAL=||p' CMakeCache.txt | head -n1 || true)"
  if [ -n "$cached_source" ] && [ "$cached_source" != "$SOURCE_DIR" ]; then
    echo "==> Detected stale CMake cache (old source: $cached_source)"
    echo "==> Resetting build directory for Geant4..."
    rm -rf CMakeCache.txt CMakeFiles
  fi
fi

# Allow pkg-config to discover local installs (e.g. ~/local)
for pcdir in "$HOME/local/lib/pkgconfig" "$HOME/local/lib64/pkgconfig"; do
  if [ -d "$pcdir" ]; then
    export PKG_CONFIG_PATH="$pcdir:${PKG_CONFIG_PATH:-}"
  fi
done

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

find "${BUILD_AREA}/builds" -maxdepth 2 \( -name "*.tar.gz" -o -name "*.tgz" \) -delete
