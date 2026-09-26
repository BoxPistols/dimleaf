#!/bin/sh
# Dimleaf を完全に取り除く。アプリを終了して設定を元に戻してから、ヘルパー・sudoers・自動起動を削除する
set -e
pkill -x Dimleaf 2>/dev/null && sleep 2 || true
# アプリが異常終了していた場合に備えて pmset の元の値を戻す
[ -x /Library/PrivilegedHelperTools/local.dimleaf.helper ] && sudo /Library/PrivilegedHelperTools/local.dimleaf.helper off || true
rm -rf ~/Applications/Dimleaf.app ~/.local/bin/dimleaf ~/Library/LaunchAgents/local.dimleaf.plist "$HOME/Library/Application Support/Dimleaf"
defaults delete local.dimleaf 2>/dev/null || true
sudo rm -f /etc/sudoers.d/dimleaf /Library/PrivilegedHelperTools/local.dimleaf.helper
sudo rm -rf "/Library/Application Support/Dimleaf"
echo "Dimleaf を削除しました"
