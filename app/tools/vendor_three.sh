#!/usr/bin/env bash
# Copies the three.js files the avatar engine needs into the app assets,
# from the npm tarball of the exact version the prototype uses (MIT).
# Usage: app/tools/vendor_three.sh   (needs npm; writes only assets/avatar/three/)
set -euo pipefail
VERSION=0.186.0
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/../ishara_app/assets/avatar/three"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
(cd "$TMP" && npm pack "three@$VERSION" --silent >/dev/null && tar xzf "three-$VERSION.tgz")
P="$TMP/package"
FILES=(
  build/three.module.js
  build/three.core.js
  examples/jsm/loaders/GLTFLoader.js
  examples/jsm/utils/BufferGeometryUtils.js
  examples/jsm/utils/SkeletonUtils.js
  examples/jsm/libs/meshopt_decoder.module.js
)
rm -rf "$DEST"
for f in "${FILES[@]}"; do
  mkdir -p "$DEST/$(dirname "$f")"
  cp "$P/$f" "$DEST/$f"
done
cp "$P/LICENSE" "$DEST/LICENSE"
echo "three@$VERSION" > "$DEST/VERSION"
# Checked by test/avatar/avatar_page_test.dart (no silent edits).
(cd "$DEST" && sha256sum "${FILES[@]}" > SHA256SUMS)
echo "vendored three@$VERSION into $DEST"
