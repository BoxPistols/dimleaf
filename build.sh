#!/bin/sh
# macOS 13 (Intel) 向けに LowPower.app をビルドし、~/Applications と ~/.local/bin/lowpower に配置する
set -e
cd "$(dirname "$0")"
app=LowPower.app
rm -rf "$app" && mkdir -p "$app/Contents/MacOS"
swiftc -O -target x86_64-apple-macos13 LowPower.swift -o "$app/Contents/MacOS/LowPower"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LowPower</string>
<key>CFBundleIdentifier</key><string>local.lowpower</string>
<key>CFBundleName</key><string>LowPower</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$app"
if [ "${1:-}" = install ]; then
  pkill -x LowPower 2>/dev/null && sleep 1 || true
  rm -rf ~/Applications/LowPower.app && cp -R "$app" ~/Applications/
  mkdir -p ~/.local/bin && ln -sf ~/Applications/LowPower.app/Contents/MacOS/LowPower ~/.local/bin/lowpower
  open ~/Applications/LowPower.app
fi
echo "built $app"
