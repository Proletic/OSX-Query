#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
PRODUCT_NAME="osx"

if [[ -z "$VERSION" ]]; then
  VERSION="$(git -C "$ROOT_DIR" describe --tags --exact-match 2>/dev/null || true)"
fi

if [[ -z "$VERSION" ]]; then
  echo "version not provided and no exact git tag found" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$DIST_DIR/$VERSION"
mkdir -p "$DIST_DIR/$VERSION"

"$ROOT_DIR/scripts/set-version.sh" "$VERSION"

build_arch() {
  local arch="$1"
  local release_dir="$ROOT_DIR/.build/${arch}-apple-macosx/release"
  local package_dir="$DIST_DIR/$VERSION/${PRODUCT_NAME}-${VERSION}-${arch}"
  local archive_path="$DIST_DIR/$VERSION/${PRODUCT_NAME}-${VERSION}-${arch}.zip"

  echo "Building $PRODUCT_NAME for $arch"
  swift build \
    --package-path "$ROOT_DIR" \
    --arch "$arch" \
    -c release \
    -Xswiftc -Osize \
    -Xlinker -dead_strip

  mkdir -p "$package_dir"
  cp "$release_dir/$PRODUCT_NAME" "$package_dir/$PRODUCT_NAME"
  strip -x "$package_dir/$PRODUCT_NAME"
  "$ROOT_DIR/scripts/sign.sh" "$package_dir/$PRODUCT_NAME"

  ditto -c -k --keepParent "$package_dir" "$archive_path"
  echo "Created $archive_path"
}

build_arch arm64
build_arch x86_64

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  "$ROOT_DIR/scripts/notarize.sh" "$DIST_DIR/$VERSION/${PRODUCT_NAME}-${VERSION}-arm64.zip"
  "$ROOT_DIR/scripts/notarize.sh" "$DIST_DIR/$VERSION/${PRODUCT_NAME}-${VERSION}-x86_64.zip"
fi

echo "Release artifacts available in $DIST_DIR/$VERSION"
