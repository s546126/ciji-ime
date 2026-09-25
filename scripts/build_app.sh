#!/usr/bin/env bash
# Build build/Ciji.app with swiftc (Command Line Tools are enough; no Xcode project needed).
#   ARCHS="arm64 x86_64"  universal binary (default: host arch only)
#   VERSION=1.2.3         CFBundleShortVersionString
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="com.shengtao.ciji.inputmethod"
PRODUCT_NAME="Ciji"
DEPLOY_TARGET="${DEPLOY_TARGET:-13.0}"
ARCHS="${ARCHS:-$(uname -m)}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUT_DIR="${OUT_DIR:-${ROOT}/build}"
APP_OUT="${OUT_DIR}/${PRODUCT_NAME}.app"

if [[ ! -f Ciji/Resources/cedict.tsv.gz ]]; then
  echo "Dictionary missing; running scripts/build_dict.py …"
  python3 scripts/build_dict.py
fi

SWIFTC="$(xcrun --find swiftc 2>/dev/null || command -v swiftc)"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

SOURCES=(
  Ciji/main.swift
  Ciji/AppDelegate.swift
  Ciji/CijiInputController.swift
  Ciji/InputSession.swift
  Ciji/CandidatePanel.swift
  Ciji/SelfTest.swift
  Ciji/Engine/Pinyin.swift
  Ciji/Engine/Xiaohe.swift
  Ciji/Engine/Lexicon.swift
  Ciji/Engine/Decoder.swift
  Ciji/Engine/UserHistory.swift
  Ciji/Translation/AppConfig.swift
  Ciji/Translation/GlossService.swift
)

rm -rf "$APP_OUT"
mkdir -p "${APP_OUT}/Contents/MacOS" "${APP_OUT}/Contents/Resources/zh-Hans.lproj" "${APP_OUT}/Contents/Resources/en.lproj"

sed \
  -e "s/\$(EXECUTABLE_NAME)/${PRODUCT_NAME}/g" \
  -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
  -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/${DEPLOY_TARGET}/g" \
  "Ciji/Info.plist" > "${APP_OUT}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_OUT}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_OUT}/Contents/Info.plist"
plutil -lint "${APP_OUT}/Contents/Info.plist"
printf 'APPL????' > "${APP_OUT}/Contents/PkgInfo"

cp Ciji/Resources/cedict.tsv.gz Ciji/Resources/config.sample.json Ciji/Resources/ciji.icns "${APP_OUT}/Contents/Resources/"
cp Ciji/zh-Hans.lproj/InfoPlist.strings "${APP_OUT}/Contents/Resources/zh-Hans.lproj/"
cp Ciji/en.lproj/InfoPlist.strings "${APP_OUT}/Contents/Resources/en.lproj/"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SLICES=()
for arch in $ARCHS; do
  echo "Compiling ${PRODUCT_NAME} for ${arch} (macOS ${DEPLOY_TARGET}) …"
  "$SWIFTC" \
    -module-name Ciji \
    -O -whole-module-optimization \
    -swift-version 5 \
    -target "${arch}-apple-macosx${DEPLOY_TARGET}" \
    -sdk "$SDKROOT" \
    -framework Cocoa -framework InputMethodKit -framework Carbon \
    -lz \
    -o "${TMP}/${PRODUCT_NAME}-${arch}" \
    "${SOURCES[@]}"
  SLICES+=("${TMP}/${PRODUCT_NAME}-${arch}")
done
lipo -create "${SLICES[@]}" -output "${APP_OUT}/Contents/MacOS/${PRODUCT_NAME}"
lipo -info "${APP_OUT}/Contents/MacOS/${PRODUCT_NAME}"

# Ad-hoc signature: required on Apple Silicon; not a Developer ID.
codesign --force --deep --sign - "$APP_OUT"
codesign --verify --verbose "$APP_OUT"
echo "Built ${APP_OUT}"
