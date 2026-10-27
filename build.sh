#!/bin/sh
# macOS 11 以降（Intel）向けに Dimleaf.app をビルドし、~/Applications と ~/.local/bin/dimleaf に配置する
set -e
cd "$(dirname "$0")"
app=Dimleaf.app
# 一時ディレクトリでビルドし、成功したときだけ差し替える。失敗しても前の成果物が残る
# 同じディスク上に作り、差し替えをコピーではなく名前の変更で済ませる
tmp=$(mktemp -d ./.build.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$tmp/$app/Contents/MacOS"
swiftc -O -target x86_64-apple-macos11 Dimleaf.swift -o "$tmp/$app/Contents/MacOS/Dimleaf"
cat > "$tmp/$app/Contents/Info.plist" <<PLIST
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
codesign --force -s - "$tmp/$app"
rm -rf "$app" && mv "$tmp/$app" .
if [ "${1:-}" = install ]; then
  # 終了時に設定を元に戻すので 1 秒では終わらない。消えるまで待たないと open が -600 で失敗する
  pkill -x Dimleaf 2>/dev/null || true
  for _ in $(seq 50); do pgrep -x Dimleaf >/dev/null || break; sleep 0.2; done
  rm -rf ~/Applications/Dimleaf.app && cp -R "$app" ~/Applications/
  mkdir -p ~/.local/bin && ln -sf ~/Applications/Dimleaf.app/Contents/MacOS/Dimleaf ~/.local/bin/dimleaf
  open ~/Applications/Dimleaf.app
fi
echo "built $app"
