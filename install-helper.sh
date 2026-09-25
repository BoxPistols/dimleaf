#!/bin/sh
# ヘルパーを root 所有で配置し、パスワード無しで実行できるよう sudoers に登録する（sudo で 1 回だけ実行）
set -e
[ "$(id -u)" = 0 ] || { echo "sudo $0 で実行してください" >&2; exit 1; }
cd "$(dirname "$0")"
user="${SUDO_USER:?sudo 経由で実行してください}"
dst=/Library/PrivilegedHelperTools/local.lowpower.helper
install -o root -g wheel -m 755 helper.sh "$dst"
tmp=$(mktemp)
echo "$user ALL=(root) NOPASSWD: $dst on, $dst off, $dst throttle, $dst status" > "$tmp"
# 構文エラーの sudoers を置くと sudo 自体が使えなくなるので必ず検査してから入れる
visudo -cf "$tmp"
install -o root -g wheel -m 440 "$tmp" /etc/sudoers.d/lowpower
rm -f "$tmp"
echo "installed $dst and /etc/sudoers.d/lowpower"
