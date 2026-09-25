#!/bin/sh
# LowPower の root 権限部分（pmset のバッテリー設定・システムデーモンの優先度）
# sudoers で NOPASSWD 許可されるため、引数は固定の語（on/off/throttle/status）だけ受け付ける
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
dir="/Library/Application Support/LowPower"
backup="$dir/pmset-battery.bak"
# 変更するキー。off で元の値に戻す
keys="displaysleep tcpkeepalive standbydelaylow standbydelayhigh powernap halfdim lessbright"
# 常駐して電力を使いがちなシステムデーモン（索引・写真解析・iCloud 同期など）
daemons="mds mds_stores mdworker_shared mediaanalysisd photoanalysisd cloudd bird suggestd corespotlightd"

current() { pmset -g custom | awk -v k="$1" '/^Battery Power:/{b=1;next} /^[A-Z]/{b=0} b && $1==k {print $2}'; }
daemon_pids() { for d in $daemons; do pgrep -x "$d"; done; }

case "${1:-}" in
on)
  mkdir -p "$dir"
  # 既にバックアップがあれば（前回 off されずに終わった等）元の値を上書きしない
  if [ ! -f "$backup" ]; then
    for k in $keys; do v=$(current "$k"); [ -n "$v" ] && echo "$k $v"; done > "$backup"
  fi
  # バッテリー駆動時の設定だけ変える（AC 時の設定は触らない）
  # standbydelay 短縮 = 蓋を閉じてから早めに深いスリープへ / tcpkeepalive 0 = スリープ中の通信を止める
  pmset -b displaysleep 2 tcpkeepalive 0 standbydelaylow 900 standbydelayhigh 3600 powernap 0 halfdim 1 lessbright 1
  for p in $(daemon_pids); do taskpolicy -b -p "$p" 2>/dev/null; done
  ;;
off)
  if [ -f "$backup" ]; then
    # shellcheck disable=SC2046
    pmset -b $(tr '\n' ' ' < "$backup") && rm -f "$backup"
  fi
  for p in $(daemon_pids); do taskpolicy -B -p "$p" 2>/dev/null; done
  ;;
throttle)
  # mdworker などは次々起動し直すので定期的に掛け直す
  [ -f "$backup" ] && for p in $(daemon_pids); do taskpolicy -b -p "$p" 2>/dev/null; done
  ;;
status)
  [ -f "$backup" ] && echo on || echo off
  ;;
*)
  echo "usage: $0 on|off|throttle|status" >&2; exit 2
  ;;
esac
exit 0
