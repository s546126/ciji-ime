#!/bin/bash
# Remove 词记 from ~/Library/Input Methods (user settings are kept).
set -euo pipefail
killall Ciji 2>/dev/null || true
rm -rf "${HOME}/Library/Input Methods/Ciji.app"
echo "已卸载 词记。配置与学习记录保留在 ~/Library/Application Support/Ciji（可手动删除）。"
echo "请在 系统设置 → 键盘 → 输入法 中移除「词记」，必要时注销重新登录。"
