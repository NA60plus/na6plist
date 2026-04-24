#!/usr/bin/env bash
# Recipe: Boost
set -euo pipefail

VERSION="${BOOST_VERSION:-1.84.0}"
# Convert dots to underscores for tarball name
VUNDER="${VERSION//./_}"
URL="https://archives.boost.io/release/${VERSION}/source/boost_${VUNDER}.tar.gz"

SOURCE_DIR="$BUILD_AREA/sources/boost_${VUNDER}"
BUILD_DIR="$BUILD_AREA/builds/boost_${VERSION}"

if [ ! -d "$SOURCE_DIR" ]; then
  mkdir -p "$BUILD_AREA/sources"
  echo "==> Downloading Boost ${VERSION}..."
  curl -L "$URL" -o "/tmp/boost_${VUNDER}.tar.gz"
  tar xzf "/tmp/boost_${VUNDER}.tar.gz" -C "$BUILD_AREA/sources"
fi

mkdir -p "$INSTALL_PREFIX"

cd "$SOURCE_DIR"
echo "==> Bootstrapping Boost ${VERSION}..."
./bootstrap.sh --prefix="$INSTALL_PREFIX" \
  --with-libraries=program_options,filesystem,system,thread,date_time,regex,serialization,atomic,chrono

echo "==> Building and installing Boost ${VERSION}..."
./b2 -j"${JOBS:-4}" install
