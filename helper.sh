#!/bin/sh
# Dimleaf の root 権限部分（pmset のバッテリー設定・システムデーモンの優先度）
# sudoers で NOPASSWD 許可されるため、引数は固定の語（on/off/throttle/status）だけ受け付ける
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
dir="/Library/Application Support/Dimleaf"
backup="$dir/pmset-battery.bak"
# 変更するキー。off で元の値に戻す
keys="displaysleep tcpkeepalive standbydelaylow standbydelayhigh powernap halfdim lessbright"
# 常駐して電力を使いがちなシステムデーモン（索引作成・写真解析など）
# bird/cloudd（iCloud 同期）と corespotlightd は前面アプリがファイルを開く・検索するときに待たされるので対象外
daemons="mds mds_stores mdworker_shared mediaanalysisd photoanalysisd suggestd"

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
  # 機種や OS によって無いキーがあり、1 つでも混ざると pmset 全体が失敗するので 1 つずつ、存在するキーだけ設定する
  for kv in displaysleep:2 tcpkeepalive:0 standbydelaylow:900 standbydelayhigh:3600 powernap:0 halfdim:1 lessbright:1; do
    k=${kv%%:*}; [ -n "$(current "$k")" ] && pmset -b "$k" "${kv#*:}"
  done
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
