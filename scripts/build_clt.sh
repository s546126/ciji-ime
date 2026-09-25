#!/usr/bin/env bash
# Build 词记 with Command Line Tools + swiftc (no Xcode.app) and install it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build_app.sh"
exec "$ROOT/packaging/install.command" "$ROOT/build/Ciji.app"
