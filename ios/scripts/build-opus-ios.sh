#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Vendor"
OUTPUT="$VENDOR/Opus.xcframework"
HEADERS="$VENDOR/OpusHeaders"
OPUS_VERSION="1.6.1"
OPUS_ARCHIVE="opus-${OPUS_VERSION}.tar.gz"
OPUS_URL="https://downloads.xiph.org/releases/opus/${OPUS_ARCHIVE}"
OPUS_SHA256="6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"

if [[ -d "$OUTPUT" ]]; then
  echo "Using existing $OUTPUT"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$VENDOR"

cd "$WORK"
curl --fail --location --retry 3 --output "$OPUS_ARCHIVE" "$OPUS_URL"
echo "$OPUS_SHA256  $OPUS_ARCHIVE" | shasum -a 256 --check
tar -xzf "$OPUS_ARCHIVE"
SOURCE="$WORK/opus-${OPUS_VERSION}"

build_arch() {
  local name="$1"
  local sysroot="$2"
  local architectures="$3"
  local build="$WORK/build-$name"
  local install="$WORK/install-$name"

  cmake -S "$SOURCE" -B "$build" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES="$architectures" \
    -DCMAKE_INSTALL_PREFIX="$install" \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
    -DBUILD_SHARED_LIBS=OFF \
    -DOPUS_BUILD_PROGRAMS=OFF \
    -DOPUS_BUILD_TESTING=OFF >&2
  cmake --build "$build" --config Release --target install >&2
  echo "$install"
}

DEVICE_INSTALL="$(build_arch device iphoneos arm64)"
SIMULATOR_INSTALL="$(build_arch simulator iphonesimulator 'arm64;x86_64')"

rm -rf "$HEADERS"
mkdir -p "$HEADERS/opus"
cp "$SOURCE"/include/*.h "$HEADERS/opus/"

rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
  -library "$DEVICE_INSTALL/lib/libopus.a" \
  -headers "$HEADERS" \
  -library "$SIMULATOR_INSTALL/lib/libopus.a" \
  -headers "$HEADERS" \
  -output "$OUTPUT"

echo "Created $OUTPUT"

