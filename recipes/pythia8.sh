#!/usr/bin/env bash
# Recipe: Pythia8
set -euo pipefail

VERSION="${PYTHIA8_VERSION:-8312}"
# Pythia8 version format: 8312 -> 8.312
DOTVER="$(echo $VERSION | sed 's/\(.\)\(.*\)/\1.\2/')"
URL="https://pythia.org/download/pythia83/pythia${VERSION}.tgz"

SOURCE_DIR="$BUILD_AREA/sources/pythia${VERSION}"
BUILD_DIR="$BUILD_AREA/builds/pythia8-${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources"
  echo "==> Downloading Pythia8 ${VERSION}..."
  curl -L "$URL" -o "/tmp/pythia${VERSION}.tgz"
  tar xzf "/tmp/pythia${VERSION}.tgz" -C "$BUILD_AREA/sources"
fi

mkdir -p "$INSTALL_PREFIX"
cd "$SOURCE_DIR"

./configure --prefix="$INSTALL_PREFIX" \
  --with-hepmc3="$(na6pbuild_prefix hepmc3)" \
  --cxx-common="-std=c++17 -O2 -fPIC"

make -j"${JOBS:-4}"
make install
