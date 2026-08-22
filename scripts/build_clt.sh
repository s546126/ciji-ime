#!/usr/bin/env bash
# Build and install 词记 with Command Line Tools + swiftc (no Xcode.app).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="com.shengtao.ciji.inputmethod"
PRODUCT_NAME="Ciji"
DEPLOY_TARGET="13.0"
APP_OUT="${ROOT}/build/CLT/${PRODUCT_NAME}.app"
DEST="${HOME}/Library/Input Methods/${PRODUCT_NAME}.app"

if [[ ! -f Ciji/Resources/cedict.tsv.gz ]]; then
  echo "Dictionary missing; running scripts/build_dict.py …"
  python3 scripts/build_dict.py
fi

if [[ ! -f Ciji/Resources/ciji.icns ]]; then
  python3 scripts/generate_icon.py
fi

if ! command -v swiftc >/dev/null 2>&1 && ! command -v xcrun >/dev/null 2>&1; then
  echo "swiftc / xcrun not found. Install Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

SWIFTC="$(xcrun --find swiftc 2>/dev/null || command -v swiftc)"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx${DEPLOY_TARGET}"

echo "Building ${PRODUCT_NAME}.app with swiftc (${TARGET}) …"

rm -rf "$APP_OUT"
mkdir -p "${APP_OUT}/Contents/MacOS"
mkdir -p "${APP_OUT}/Contents/Resources/zh-Hans.lproj"
mkdir -p "${APP_OUT}/Contents/Resources/en.lproj"

# Substitute Xcode build-setting tokens so IMK can read the connection name.
sed \
  -e "s/\$(EXECUTABLE_NAME)/${PRODUCT_NAME}/g" \
  -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
  -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/${DEPLOY_TARGET}/g" \
  "${ROOT}/Ciji/Info.plist" > "${APP_OUT}/Contents/Info.plist"

printf 'APPL????' > "${APP_OUT}/Contents/PkgInfo"

cp "${ROOT}/Ciji/Resources/cedict.tsv.gz" "${APP_OUT}/Contents/Resources/"
cp "${ROOT}/Ciji/Resources/config.sample.json" "${APP_OUT}/Contents/Resources/"
cp "${ROOT}/Ciji/Resources/ciji.icns" "${APP_OUT}/Contents/Resources/"
cp "${ROOT}/Ciji/zh-Hans.lproj/InfoPlist.strings" "${APP_OUT}/Contents/Resources/zh-Hans.lproj/"
cp "${ROOT}/Ciji/en.lproj/InfoPlist.strings" "${APP_OUT}/Contents/Resources/en.lproj/"

SOURCES=(
  Ciji/main.swift
  Ciji/AppDelegate.swift
  Ciji/CijiInputController.swift
  Ciji/InputSession.swift
  Ciji/CandidatePanel.swift
  Ciji/Engine/Pinyin.swift
  Ciji/Engine/Xiaohe.swift
  Ciji/Engine/Lexicon.swift
  Ciji/Engine/Decoder.swift
  Ciji/Translation/AppConfig.swift
  Ciji/Translation/GlossService.swift
)

"$SWIFTC" \
  -module-name Ciji \
  -O \
  -swift-version 5 \
  -target "$TARGET" \
  -sdk "$SDKROOT" \
  -framework Cocoa \
  -framework InputMethodKit \
  -lz \
  -o "${APP_OUT}/Contents/MacOS/${PRODUCT_NAME}" \
  "${SOURCES[@]}"

if command -v codesign >/dev/null; then
  codesign --force --deep --sign - "$APP_OUT"
fi
if command -v xattr >/dev/null; then
  xattr -dr com.apple.quarantine "$APP_OUT" || true
fi

echo "Installing to ${DEST}"
mkdir -p "${HOME}/Library/Input Methods"
killall Ciji 2>/dev/null || true
rm -rf "$DEST"
cp -R "$APP_OUT" "$DEST"

if command -v codesign >/dev/null; then
  codesign --force --deep --sign - "$DEST" || true
fi
if command -v xattr >/dev/null; then
  xattr -dr com.apple.quarantine "$DEST" || true
fi

mkdir -p "${HOME}/Library/Application Support/Ciji"
if [[ ! -f "${HOME}/Library/Application Support/Ciji/config.json" ]]; then
  cp "${ROOT}/Ciji/Resources/config.sample.json" "${HOME}/Library/Application Support/Ciji/config.json"
  echo "Wrote default config to ~/Library/Application Support/Ciji/config.json"
fi

echo
echo "已安装 词记（swiftc / Command Line Tools）。"
echo "请打开：系统设置 → 键盘 → 输入法 → 添加 词记。"
echo "第一次启用可能需要注销并重新登录。"
echo "配置 CLIProxyAPI：编辑 ~/Library/Application Support/Ciji/config.json 后重新登录或 killall Ciji。"
