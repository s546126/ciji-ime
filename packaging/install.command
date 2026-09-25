#!/bin/bash
# 词记 installer: copies Ciji.app into ~/Library/Input Methods and enables it.
# Double-click this file from the DMG, or run: ./install.command [path/to/Ciji.app]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-${HERE}/Ciji.app}"
DEST_DIR="${HOME}/Library/Input Methods"
DEST="${DEST_DIR}/Ciji.app"

if [[ ! -d "$SRC" ]]; then
  echo "找不到 Ciji.app：$SRC" >&2
  exit 1
fi

echo "==> 安装 词记 到 ${DEST}"
mkdir -p "$DEST_DIR"
killall Ciji 2>/dev/null || true
rm -rf "$DEST"
ditto "$SRC" "$DEST"
# Unsigned (ad-hoc) build: drop the download quarantine so macOS will load it.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || true

mkdir -p "${HOME}/Library/Application Support/Ciji"
if [[ ! -f "${HOME}/Library/Application Support/Ciji/config.json" ]]; then
  cp "${DEST}/Contents/Resources/config.sample.json" "${HOME}/Library/Application Support/Ciji/config.json"
fi

echo "==> 注册输入法"
"${DEST}/Contents/MacOS/Ciji" --register || true

cat <<'MSG'

✅ 词记 已安装。

下一步：
  系统设置 → 键盘 → 输入法 → 编辑… → 「+」 → 简体中文 → 词记
  （如果列表里没有，注销并重新登录一次即可。）

使用：Shift 切换中/英，Ctrl+Shift+P 切换 小鹤双拼/全拼。
MSG
