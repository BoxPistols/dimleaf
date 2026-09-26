#!/bin/sh
# ヘルパーを root 所有で配置し、パスワード無しで実行できるよう sudoers に登録する（sudo で 1 回だけ実行）
set -e
if [ "$(id -u)" != 0 ]; then
  # 端末が無い環境でもパスワードを入れられるよう、macOS の認証ダイアログで自分を再実行する
  exec osascript -e "do shell script quoted form of \"$(cd "$(dirname "$0")" && pwd)/$(basename "$0")\" & \" $(id -un)\" with administrator privileges"
fi
cd "$(dirname "$0")"
# osascript の with administrator privileges 経由では SUDO_USER が無いので引数でも受け取る
user="${SUDO_USER:-${1:?sudo 経由で実行するか、ユーザー名を引数に渡してください}}"
dst=/Library/PrivilegedHelperTools/local.dimleaf.helper
install -o root -g wheel -m 755 helper.sh "$dst"
tmp=$(mktemp)
echo "$user ALL=(root) NOPASSWD: $dst on, $dst off, $dst throttle, $dst status" > "$tmp"
# 構文エラーの sudoers を置くと sudo 自体が使えなくなるので必ず検査してから入れる
visudo -cf "$tmp"
install -o root -g wheel -m 440 "$tmp" /etc/sudoers.d/dimleaf
rm -f "$tmp"
echo "installed $dst and /etc/sudoers.d/dimleaf"
