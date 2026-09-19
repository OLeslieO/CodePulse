#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
swift build -c release "${swift_options[@]}"
bundle="$PWD/dist/Codex Signal.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp .build/release/CodexSignal "$bundle/Contents/MacOS/CodexSignal"
cp .build/release/signalctl dist/signalctl
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codex-signal.app</string>
<key>CFBundleName</key><string>Codex Signal</string>
<key>CFBundleDisplayName</key><string>Codex Signal</string>
<key>CFBundleExecutable</key><string>CodexSignal</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
cp README.md dist/README.md
cp -R docs dist/
cp -R examples dist/
archive="$PWD/dist/Codex-Signal-0.1.0-$(uname -m).zip"
staging=$(mktemp -d "${TMPDIR:-/tmp}/codex-signal-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$bundle" "$staging/Codex Signal.app"
cp dist/signalctl README.md "$staging/"
cp -R docs examples "$staging/"
ditto -c -k "$staging" "$archive"
printf 'Built: %s\n' "$bundle"
printf 'Archive: %s\n' "$archive"
