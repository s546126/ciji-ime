#!/usr/bin/env bash
# Build 词记 and install it into ~/Library/Input Methods/Ciji.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f Ciji/Resources/cedict.tsv.gz ]]; then
  echo "Dictionary missing; running scripts/build_dict.py …"
  python3 scripts/build_dict.py
fi

if [[ ! -f Ciji/Resources/ciji.icns ]]; then
  python3 scripts/generate_icon.py
fi

DERIVED="${ROOT}/build/DerivedData"
mkdir -p "$DERIVED"

echo "Building Ciji (Release) …"
xcodebuild \
  -project Ciji.xcodeproj \
  -scheme Ciji \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  build

APP="$(find "$DERIVED/Build/Products/Release" -maxdepth 1 -name 'Ciji.app' -type d | head -n 1)"
if [[ -z "$APP" ]]; then
  echo "xcodebuild succeeded but Ciji.app was not found." >&2
  exit 1
fi

DEST="${HOME}/Library/Input Methods/Ciji.app"
echo "Installing to ${DEST}"
mkdir -p "${HOME}/Library/Input Methods"
killall Ciji 2>/dev/null || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"

if command -v codesign >/dev/null; then
  codesign --force --deep --sign - "$DEST" || true
fi
if command -v xattr >/dev/null; then
  xattr -dr com.apple.quarantine "$DEST" || true
fi

mkdir -p "${HOME}/Library/Application Support/Ciji"
if [[ ! -f "${HOME}/Library/Application Support/Ciji/config.json" ]]; then
  cp "$ROOT/Ciji/Resources/config.sample.json" "${HOME}/Library/Application Support/Ciji/config.json"
  echo "Wrote default config to ~/Library/Application Support/Ciji/config.json"
fi

echo
echo "已安装 词记。"
echo "请打开：系统设置 → 键盘 → 输入法 → 添加 词记。"
echo "第一次启用可能需要注销并重新登录。"
echo "配置 CLIProxyAPI：编辑 ~/Library/Application Support/Ciji/config.json 后重新登录或 killall Ciji。"
