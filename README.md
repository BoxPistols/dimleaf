# LowPower

A menu bar app that gives a **virtual low power mode** to Macs that don't have one — e.g. older Intel MacBooks where `pmset -g cap` lists no `lowpowermode`.

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

- macOS 13 or later, built-in display
- Xcode Command Line Tools (`xcode-select --install`)
- Built and tested on an Intel MacBook (MacBook10,1, macOS 13.7). Apple Silicon is untested.

## Install

```sh
git clone https://github.com/BoxPistols/lowpower.git
cd lowpower
./build.sh install              # builds, copies to ~/Applications, links ~/.local/bin/lowpower
sudo ./install-helper.sh        # optional: enables the pmset / daemon parts
```

Enable "Launch at login" from the menu.

### About the helper

`install-helper.sh` installs a root-owned script at `/Library/PrivilegedHelperTools/local.lowpower.helper` and a sudoers rule that lets your user run it **only** with the fixed arguments `on`, `off`, `throttle` and `status`, without a password. Read [`helper.sh`](helper.sh) before installing — it is short. Without the helper everything else still works.

## CLI

```sh
lowpower on | off | toggle | status
```

## Settings

All in the menu. To exclude more apps from throttling:

```sh
defaults write local.lowpower exclude -array-add com.example.app
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
