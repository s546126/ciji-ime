#!/usr/bin/env bash
# Build 词记 from source and install it into ~/Library/Input Methods/Ciji.app.
# Needs only the Command Line Tools (xcode-select --install).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/build_clt.sh"
