#!/bin/sh
# macOS 11 以降（Intel）向けに Dimleaf.app をビルドし、~/Applications と ~/.local/bin/dimleaf に配置する
set -e
cd "$(dirname "$0")"
app=Dimleaf.app
rm -rf "$app" && mkdir -p "$app/Contents/MacOS"
swiftc -O -target x86_64-apple-macos11 Dimleaf.swift -o "$app/Contents/MacOS/Dimleaf"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Dimleaf</string>
<key>CFBundleIdentifier</key><string>local.dimleaf</string>
<key>CFBundleName</key><string>Dimleaf</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>11.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$app"
if [ "${1:-}" = install ]; then
  pkill -x Dimleaf 2>/dev/null && sleep 1 || true
  rm -rf ~/Applications/Dimleaf.app && cp -R "$app" ~/Applications/
  mkdir -p ~/.local/bin && ln -sf ~/Applications/Dimleaf.app/Contents/MacOS/Dimleaf ~/.local/bin/dimleaf
  open ~/Applications/Dimleaf.app
fi
echo "built $app"
