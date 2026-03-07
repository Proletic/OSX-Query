#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi

VERSION="${1#v}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED_FILE="$ROOT_DIR/Sources/osx/Models/GeneratedVersion.swift"
NPM_PACKAGE_JSON="$ROOT_DIR/npm/package.json"

cat > "$GENERATED_FILE" <<EOF
// GeneratedVersion.swift - Release version metadata for the OSX CLI

import Foundation

let osxVersion = "$VERSION"
EOF

node -e '
const fs = require("node:fs");
const path = process.argv[1];
const version = process.argv[2];
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
pkg.version = version;
fs.writeFileSync(path, `${JSON.stringify(pkg, null, 2)}\n`);
' "$NPM_PACKAGE_JSON" "$VERSION"

echo "Updated CLI and npm package version to $VERSION"
