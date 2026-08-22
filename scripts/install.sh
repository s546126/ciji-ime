#!/usr/bin/env bash
# Build 词记 and install it into ~/Library/Input Methods/Ciji.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodebuild_needs_xcode() {
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild not found"
    return 0
  fi
  local out rc=0
  out="$(xcodebuild -version 2>&1)" || rc=$?
  if echo "$out" | grep -qiE 'requires Xcode|command line tools instance'; then
    echo "$out"
    return 0
  fi
  return 1
}

install_built_app() {
  local app="$1"
  local dest="${HOME}/Library/Input Methods/Ciji.app"
  echo "Installing to ${dest}"
  mkdir -p "${HOME}/Library/Input Methods"
  killall Ciji 2>/dev/null || true
  rm -rf "$dest"
  cp -R "$app" "$dest"
  if command -v codesign >/dev/null; then
    codesign --force --deep --sign - "$dest" || true
  fi
  if command -v xattr >/dev/null; then
    xattr -dr com.apple.quarantine "$dest" || true
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
}

if [[ ! -f Ciji/Resources/cedict.tsv.gz ]]; then
  echo "Dictionary missing; running scripts/build_dict.py …"
  python3 scripts/build_dict.py
fi

if [[ ! -f Ciji/Resources/ciji.icns ]]; then
  python3 scripts/generate_icon.py
fi

if probe="$(xcodebuild_needs_xcode)"; then
  echo "xcodebuild 需要完整 Xcode，改用 Command Line Tools / swiftc。"
  if [[ -n "$probe" ]]; then
    echo "$probe"
  fi
  exec "$ROOT/scripts/build_clt.sh"
fi

DERIVED="${ROOT}/build/DerivedData"
mkdir -p "$DERIVED"

echo "Building Ciji (Release) …"
set +e
XCODE_LOG="$(xcodebuild \
  -project Ciji.xcodeproj \
  -scheme Ciji \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  build 2>&1)"
XCODE_RC=$?
set -e
if [[ $XCODE_RC -ne 0 ]]; then
  echo "$XCODE_LOG"
  if echo "$XCODE_LOG" | grep -qiE 'requires Xcode|command line tools instance'; then
    echo "xcodebuild 需要完整 Xcode，改用 Command Line Tools / swiftc。"
    exec "$ROOT/scripts/build_clt.sh"
  fi
  exit "$XCODE_RC"
fi
echo "$XCODE_LOG" | tail -n 20

APP="$(find "$DERIVED/Build/Products/Release" -maxdepth 1 -name 'Ciji.app' -type d | head -n 1)"
if [[ -z "$APP" ]]; then
  echo "xcodebuild succeeded but Ciji.app was not found." >&2
  exit 1
fi

install_built_app "$APP"
