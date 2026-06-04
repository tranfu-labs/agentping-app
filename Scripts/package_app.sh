#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_VERSION="${AGENTPING_APP_VERSION:-0.1.4}"
APP_DIR="$ROOT_DIR/dist/AgentPing.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/AgentPingMenu" "$MACOS_DIR/AgentPingMenu"
cp "$ROOT_DIR/agentping.py" "$RESOURCES_DIR/agentping.py"
if [ -f "$ROOT_DIR/Assets/AgentPingIcon.icns" ]; then
  cp "$ROOT_DIR/Assets/AgentPingIcon.icns" "$RESOURCES_DIR/AgentPingIcon.icns"
fi
chmod +x "$MACOS_DIR/AgentPingMenu" "$RESOURCES_DIR/agentping.py"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>AgentPingMenu</string>
  <key>CFBundleIdentifier</key>
  <string>com.tranfu.agentping</string>
  <key>CFBundleName</key>
  <string>Ageng网络医生</string>
  <key>CFBundleDisplayName</key>
  <string>Ageng网络医生</string>
  <key>CFBundleIconFile</key>
  <string>AgentPingIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>4</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
