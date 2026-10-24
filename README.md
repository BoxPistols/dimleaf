# Dimleaf

A menu bar app that gives a **virtual low power mode** to Macs that don't have one — e.g. older Intel MacBooks where `pmset -g cap` lists no `dimleafmode`.

[日本語](README.ja.md)

> Not affiliated with or endorsed by Apple. It combines existing macOS knobs; it does not enable Apple's own Low Power Mode.

## What it does

When **on**:

- Caps screen brightness (10–90%). Raising it with the brightness keys or auto-brightness snaps back to the cap immediately.
- Turns off the keyboard backlight.
- Lowers the priority (`PRIO_DARWIN_BG`, same as `taskpolicy -b`) of apps in the background and their child processes. The frontmost app is restored instantly. Audio/call/video/terminal apps and processes holding power assertions are excluded.
- *(helper)* Applies a battery-only `pmset` profile: display sleep 2 min, no TCP keepalive during sleep, earlier standby after closing the lid, Power Nap off. Original values are saved and restored.
- *(helper)* Lowers the priority of background system daemons (Spotlight indexing, photo analysis, iCloud sync).

**Idle ("deep") mode** — after N minutes without input: dims the screen to 6%, also throttles the frontmost app, optionally turns Wi‑Fi off. Any input restores everything. Skipped while video/meetings keep the display awake.

**Automatic switching** — on when unplugged, off when plugged in, on below a battery threshold, re-evaluated when the lid opens.

## Requirements

- macOS 11 or later (macOS 11–12 untested), built-in display
- Xcode Command Line Tools (`xcode-select --install`)
- Built and tested on an Intel MacBook (MacBook10,1, macOS 13.7). Apple Silicon is untested.

## Install

### Download

1. Download `Dimleaf-x.y.z.zip` from [Releases](https://github.com/BoxPistols/dimleaf/releases) and unzip it.
2. Move `Dimleaf.app` to `~/Applications` (launch-at-login and the CLI expect it there).
3. The app is not notarized: right-click `Dimleaf.app` → **Open** the first time.
4. Optional: run `./install-helper.sh` from the unzipped folder for the pmset / daemon parts.
5. Optional CLI: `ln -s ~/Applications/Dimleaf.app/Contents/MacOS/Dimleaf ~/.local/bin/dimleaf`

### Build from source

```sh
git clone https://github.com/BoxPistols/dimleaf.git
cd dimleaf
./build.sh install              # builds, copies to ~/Applications, links ~/.local/bin/dimleaf
./install-helper.sh             # optional: enables the pmset / daemon parts (asks for your password)
```

Enable "Launch at login" from the menu.

### About the helper

`install-helper.sh` installs a root-owned script at `/Library/PrivilegedHelperTools/local.dimleaf.helper` and a sudoers rule that lets your user run it **only** with the fixed arguments `on`, `off`, `throttle` and `status`, without a password. Read [`helper.sh`](helper.sh) before installing — it is short. Without the helper everything else still works.

## CLI

```sh
dimleaf on | off | toggle | status
```

## Settings

All in the menu. To exclude more apps from throttling:

```sh
defaults write local.dimleaf exclude -array-add com.example.app
```

## Uninstall

```sh
./uninstall.sh
```

## Caveats

- Screen and keyboard brightness use private frameworks (DisplayServices, CoreBrightness). They may break in future macOS versions, and they are why this can't go to the Mac App Store.
- Turbo Boost is not disabled (that needs a kernel extension).
- If the app is force-killed, the pmset profile stays applied until you launch it and turn it off (or run `uninstall.sh`).

## License

MIT
