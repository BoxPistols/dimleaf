#!/bin/sh
# LowPower を完全に取り除く。アプリを終了して設定を元に戻してから、ヘルパー・sudoers・自動起動を削除する
set -e
pkill -x LowPower 2>/dev/null && sleep 2 || true
# アプリが異常終了していた場合に備えて pmset の元の値を戻す
[ -x /Library/PrivilegedHelperTools/local.lowpower.helper ] && sudo /Library/PrivilegedHelperTools/local.lowpower.helper off || true
rm -rf ~/Applications/LowPower.app ~/.local/bin/lowpower ~/Library/LaunchAgents/local.lowpower.plist "$HOME/Library/Application Support/LowPower"
defaults delete local.lowpower 2>/dev/null || true
sudo rm -f /etc/sudoers.d/lowpower /Library/PrivilegedHelperTools/local.lowpower.helper
sudo rm -rf "/Library/Application Support/LowPower"
echo "LowPower を削除しました"
