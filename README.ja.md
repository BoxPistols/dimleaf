# Dimleaf

OS の低電力モードが無い Mac（`pmset -g cap` に `dimleafmode` が出ない古い Intel MacBook など）に、**仮想の低電力モード**を足すメニューバーアプリです。

> Apple とは無関係です。macOS の既存の設定を組み合わせたもので、Apple の低電力モードを有効にするものではありません。

## できること

**ON のとき**

- 画面輝度に上限をかける（10〜90%）。輝度キーや自動調整で上げても、すぐ上限に戻す
- キーボードのバックライトを消す
- 裏にあるアプリとその子プロセスを低優先度にする（`PRIO_DARWIN_BG` = `taskpolicy -b` と同じ）。前面に出したアプリはすぐ戻す。音楽・通話・動画・ターミナル系と、電源アサーションを持つプロセスは対象外
- （ヘルパー）バッテリー時だけの pmset 設定：画面スリープ2分、スリープ中の通信停止、蓋を閉じた後の深いスリープを早める、Power Nap オフ。元の値は保存して OFF で戻す
- （ヘルパー）Spotlight の索引作成・写真の解析・iCloud 同期などのシステムデーモンを低優先度にする

**無操作時（ディープ）** — N 分操作が無いと、輝度 6%、前面アプリも低優先度、任意で Wi-Fi オフ。操作すればすぐ元に戻る。動画や会議で画面スリープが止められている間は暗くしない。

**自動切り替え** — 電源を外すと ON、つなぐと OFF、残量がしきい値を下回ると ON、蓋を開けたら状態を見直す。

## 必要なもの

- macOS 13 以降、内蔵ディスプレイ
- Xcode Command Line Tools（`xcode-select --install`）
- Intel MacBook（MacBook10,1 / macOS 13.7）で開発・動作確認。Apple Silicon は未確認

## インストール

```sh
git clone https://github.com/BoxPistols/dimleaf.git
cd dimleaf
./build.sh install              # ビルドして ~/Applications に配置、~/.local/bin/dimleaf を作成
./install-helper.sh             # 任意: pmset とデーモン制御を有効にする（パスワードを聞かれます）
```

自動起動はメニューの「ログイン時に起動」から。

### ヘルパーについて

`install-helper.sh` は root 所有のスクリプトを `/Library/PrivilegedHelperTools/local.dimleaf.helper` に置き、決まった引数（`on` `off` `throttle` `status`）に限ってパスワード無しで実行できる sudoers 設定を入れます。入れる前に [`helper.sh`](helper.sh) を読んでください（短いです）。ヘルパーが無くても、それ以外の機能は動きます。

## CLI

```sh
dimleaf on | off | toggle | status
```

## 設定

メニューから変更できます。抑制から外すアプリを追加するには:

```sh
defaults write local.dimleaf exclude -array-add com.example.app
```

## アンインストール

```sh
./uninstall.sh
```

## 注意

- 画面とキーボードの輝度は非公開フレームワーク（DisplayServices, CoreBrightness）を使っています。将来の macOS で動かなくなる可能性があり、Mac App Store に出せない理由でもあります。
- Turbo Boost は切りません（カーネル拡張が必要なため）。
- アプリが強制終了された場合、pmset の設定は変わったまま残ります。アプリを起動して OFF にするか、`uninstall.sh` を実行してください。

## ライセンス

MIT
