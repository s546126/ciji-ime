#!/usr/bin/env bash
# Package build/Ciji.app into build/Ciji-<version>.dmg (run scripts/build_app.sh first).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${VERSION:-1.0.0}"
APP="build/Ciji.app"
DMG="build/Ciji-${VERSION}.dmg"
STAGE="build/dmg"

[[ -d "$APP" ]] || { echo "missing $APP; run scripts/build_app.sh" >&2; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Ciji.app"
cp packaging/install.command "$STAGE/安装词记.command"
cp packaging/uninstall.command "$STAGE/卸载词记.command"
chmod +x "$STAGE/"*.command
cp packaging/README-dmg.txt "$STAGE/使用说明.txt"
cp NOTICE "$STAGE/NOTICE.txt"

hdiutil create -volname "词记 ${VERSION}" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
shasum -a 256 "$DMG" | tee "${DMG}.sha256"
echo "Built $DMG"
