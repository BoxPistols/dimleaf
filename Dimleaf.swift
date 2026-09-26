import AppKit
import CoreWLAN
import IOKit.ps
import IOKit.pwr_mgt

// 仮想低電力モード。この Mac（MacBook10,1 / Intel / macOS 13）は OS の低電力モード非対応のため、
// pmset のバッテリー設定・画面/キーボード輝度・プロセス優先度・Wi-Fi を組み合わせて近い効果を出す
// 同じバイナリを引数付きで起動すると CLI（dimleaf on|off|toggle|status）として動く

let bundleID = "local.dimleaf"
let helperPath = "/Library/PrivilegedHelperTools/local.dimleaf.helper"
let commandNote = Notification.Name("local.dimleaf.command")
let home = FileManager.default.homeDirectoryForCurrentUser
let stateFile = home.appendingPathComponent("Library/Application Support/Dimleaf/state.json")
let agentFile = home.appendingPathComponent("Library/LaunchAgents/local.dimleaf.plist")
let appPath = home.appendingPathComponent("Applications/Dimleaf.app").path
let deepLevel: Float = 0.06

struct Prefs {
    static let d = UserDefaults.standard  // 自分の bundle id を suite 名にすると nil になるため standard を使う
    static func get<T>(_ k: String, _ def: T) -> T { d.object(forKey: k) as? T ?? def }
    static var enabled: Bool { get { get("enabled", false) } set { d.set(newValue, forKey: "enabled") } }
    static var autoOnBattery: Bool { get { get("autoOnBattery", true) } set { d.set(newValue, forKey: "autoOnBattery") } }
    static var autoOffOnAC: Bool { get { get("autoOffOnAC", true) } set { d.set(newValue, forKey: "autoOffOnAC") } }
    static var autoOnBelow: Int { get { get("autoOnBelow", 30) } set { d.set(newValue, forKey: "autoOnBelow") } }
    static var idleMinutes: Int { get { get("idleMinutes", 2) } set { d.set(newValue, forKey: "idleMinutes") } }
    static var brightnessCap: Double { get { get("brightnessCap", 0.5) } set { d.set(newValue, forKey: "brightnessCap") } }
    static var throttleApps: Bool { get { get("throttleApps", true) } set { d.set(newValue, forKey: "throttleApps") } }
    static var keyboardOff: Bool { get { get("keyboardOff", true) } set { d.set(newValue, forKey: "keyboardOff") } }
    static var wifiOffIdle: Bool { get { get("wifiOffIdle", false) } set { d.set(newValue, forKey: "wifiOffIdle") } }
    // 抑制すると困るアプリ（音声・通話・動画・ターミナル）。追加は defaults write local.dimleaf exclude -array-add <bundle id>
    static let defaultExcluded: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.apple.Music", "com.spotify.client", "com.apple.podcasts",
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.apple.FaceTime", "com.hnc.Discord",
        "com.apple.QuickTimePlayerX", "com.colliderli.iina", "org.videolan.vlc", "com.apple.ScreenSharing",
    ]
    static var excluded: Set<String> { defaultExcluded.union(get("exclude", [String]())) }
}

// 内蔵ディスプレイの輝度（非公開の DisplayServices を dlopen で呼ぶ）
enum Screen {
    typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFn = @convention(c) (UInt32, Float) -> Int32
    static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    static let getFn = lib.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    static let setFn = lib.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
    static var display: UInt32 {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8), n: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }
    static var brightness: Float? {
        var v: Float = 0
        guard let f = getFn, f(display, &v) == 0 else { return nil }
        return v
    }
    static func set(_ v: Float) { _ = setFn?(display, v) }
    // 輝度キー・自動調整を含む全ての輝度変更で呼ばれる
    typealias RegFn = @convention(c) (UInt32, UnsafeRawPointer?, CFNotificationCallback) -> Int32
    static func onChange(_ cb: CFNotificationCallback) {
        guard let f = lib.flatMap({ dlsym($0, "DisplayServicesRegisterForBrightnessChangeNotifications") }) else { return }
        _ = unsafeBitCast(f, to: RegFn.self)(display, UnsafeRawPointer(bitPattern: 1), cb)
    }
}

// キーボードバックライト（非公開の CoreBrightness.KeyboardBrightnessClient）
enum Keyboard {
    static let client: NSObject? = {
        guard Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework")?.load() == true,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()
    static let id: UInt64 = {
        let sel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let c = client, c.responds(to: sel),
              let ids = c.perform(sel)?.takeRetainedValue() as? [NSNumber], let first = ids.first else { return 1 }
        return first.uint64Value
    }()
    static func imp(_ name: String) -> (NSObject, Selector, IMP)? {
        let sel = NSSelectorFromString(name)
        guard let c = client, c.responds(to: sel) else { return nil }
        return (c, sel, c.method(for: sel))
    }
    static var available: Bool { imp("setBrightness:forKeyboard:") != nil }
    static var brightness: Float? {
        typealias F = @convention(c) (AnyObject, Selector, UInt64) -> Float
        guard let (c, s, i) = imp("brightnessForKeyboard:") else { return nil }
        return unsafeBitCast(i, to: F.self)(c, s, id)
    }
    static func set(_ v: Float) {
        typealias F = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        guard let (c, s, i) = imp("setBrightness:forKeyboard:") else { return }
        _ = unsafeBitCast(i, to: F.self)(c, s, v, id)
    }
    static var auto: Bool? {
        typealias F = @convention(c) (AnyObject, Selector, UInt64) -> Bool
        guard let (c, s, i) = imp("isAutoBrightnessEnabledForKeyboard:") else { return nil }
        return unsafeBitCast(i, to: F.self)(c, s, id)
    }
    static func setAuto(_ on: Bool) {
        typealias F = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool
        guard let (c, s, i) = imp("enableAutoBrightness:forKeyboard:") else { return }
        _ = unsafeBitCast(i, to: F.self)(c, s, on, id)
    }
}

struct Power: Equatable {
    var onBattery = false, percent = 100, minutesLeft: Int?
    static func read() -> Power {
        var p = Power()
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        p.onBattery = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSBatteryPowerValue
        for ps in IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef] {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = desc[kIOPSCurrentCapacityKey] as? Int, let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            p.percent = cur * 100 / max
        }
        let t = IOPSGetTimeRemainingEstimate()
        if t > 0 { p.minutesLeft = Int(t / 60) }
        return p
    }
}

// 画面スリープを止めているアサーション（動画再生・会議など）があるか。あれば無操作でも暗くしない
func displaySleepBlocked() -> Bool {
    var status: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
          let d = status?.takeRetainedValue() as? [String: Int] else { return false }
    return (d["PreventUserIdleDisplaySleep"] ?? 0) > 0 || (d["NoDisplaySleepAssertion"] ?? 0) > 0
}

// 何らかの電源アサーションを持っているプロセス（再生中・転送中など）は抑制しない
func assertionPIDs() -> Set<pid_t> {
    var dict: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
          let d = dict?.takeRetainedValue() as? [NSNumber: Any] else { return [] }
    return Set(d.keys.map { $0.int32Value })
}

// setpriority(PRIO_DARWIN_PROCESS, pid, PRIO_DARWIN_BG) = taskpolicy -b と同じ。CPU・I/O・通信を低優先度にする
let PRIO_DARWIN_PROCESS_: Int32 = 4, PRIO_DARWIN_BG_: Int32 = 0x1000
func setBackground(_ pid: pid_t, _ on: Bool) { setpriority(PRIO_DARWIN_PROCESS_, id_t(pid), on ? PRIO_DARWIN_BG_ : 0) }

func descendants(_ pid: pid_t, depth: Int = 2) -> [pid_t] {
    guard depth > 0 else { return [] }
    var buf = [pid_t](repeating: 0, count: 1024)
    let n = proc_listchildpids(pid, &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
    guard n > 0 else { return [] }
    let kids = Array(buf.prefix(Int(n))).filter { $0 > 0 }
    return kids + kids.flatMap { descendants($0, depth: depth - 1) }
}

func anyInputIdleSeconds() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

final class Item: NSMenuItem {
    let handler: () -> Void
    init(_ title: String, checked: Bool = false, key: String = "", _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        state = checked ? .on : .off
    }
    required init(coder: NSCoder) { fatalError() }
    @objc func fire() { handler() }
}

func info(_ title: String) -> NSMenuItem { let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""); i.isEnabled = false; return i }

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var power = Power.read()
    var enabled = false
    var deep = false
    var helperOK = FileManager.default.fileExists(atPath: helperPath)
    var throttled = Set<pid_t>()
    // 元に戻すための値。ユーザーが途中で手動変更していたら戻さない
    var savedBrightness: Float?, cappedBrightness: Float?
    var deepBrightness: Float?
    var savedKbd: Float?, savedKbdAuto: Bool?
    var wifiWasOn = false
    var idleTimer: Timer?, maintTimer: Timer?, mouseMonitor: Any?
    var maintTicks = 0

    func applicationDidFinishLaunching(_ n: Notification) {
        item.menu = NSMenu()
        item.menu?.delegate = self
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(self, selector: #selector(appsChanged), name: name, object: nil)
        }
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(screensWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(forName: commandNote, object: nil, queue: .main) { [weak self] n in
            guard let self, let cmd = n.object as? String else { return }
            switch cmd {
            case "on": setEnabled(true)
            case "off": setEnabled(false)
            case "toggle": setEnabled(!enabled)
            default: break
            }
        }
        // 電源の接続/切断・残量変化の通知
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue().powerChanged()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        // 輝度キーで上限を超えたら即座に上限へ戻す（60 秒ごとの見直しだけでは操作で超えられてしまう）
        Screen.onChange { _, _, _, _, _ in DispatchQueue.main.async { (NSApp.delegate as? App)?.applyCap() } }
        // 起動時: 前回の状態を引き継ぎ、電源状態に応じた自動ルールを当てる
        var want = Prefs.enabled
        if power.onBattery && (Prefs.autoOnBattery || (Prefs.autoOnBelow > 0 && power.percent <= Prefs.autoOnBelow)) { want = true }
        if !power.onBattery && Prefs.autoOffOnAC { want = false }
        if want { setEnabled(true) }
        scheduleIdle()
        updateUI()
    }

    func applicationWillTerminate(_ n: Notification) {
        exitDeep()
        // 終了時は全部元に戻す。ただし次回起動で再開できるよう Prefs.enabled は残す
        if enabled { disable(sync: true) }
    }

    // MARK: 低電力モード

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        exitDeep()
        Prefs.enabled = on
        if on { enable() } else { disable(sync: false) }
    }

    func enable() {
        enabled = true
        helper("on")
        applyCap()
        if Prefs.keyboardOff { keyboardOff() }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.maintain() }
        t.tolerance = 20
        RunLoop.main.add(t, forMode: .common)
        maintTimer = t
        refreshThrottle(); scheduleIdle(); updateUI()
    }

    func disable(sync: Bool) {
        enabled = false
        helper("off", sync: sync)
        if let s = savedBrightness, let c = cappedBrightness, let b = Screen.brightness, abs(b - c) < 0.02 { Screen.set(s) }
        savedBrightness = nil; cappedBrightness = nil
        keyboardRestore()
        maintTimer?.invalidate(); maintTimer = nil
        refreshThrottle(); scheduleIdle(); updateUI()
    }

    func maintain() {
        refreshThrottle()
        applyCap()  // 明るさの自動調整が上限を超えて明るくすることがあるので掛け直す
        maintTicks += 1
        if maintTicks % 5 == 0 { helper("throttle") }
    }

    func applyCap() {
        let cap = Float(Prefs.brightnessCap)
        guard enabled, !deep, cap < 1, let b = Screen.brightness, b > cap + 0.02 else { return }
        if savedBrightness == nil { savedBrightness = b }
        cappedBrightness = cap
        Screen.set(cap)
    }

    func keyboardOff() {
        guard Keyboard.available else { return }
        if savedKbd == nil { savedKbd = Keyboard.brightness; savedKbdAuto = Keyboard.auto }
        Keyboard.setAuto(false)
        Keyboard.set(0)
    }

    func keyboardRestore() {
        guard let s = savedKbd else { return }
        Keyboard.set(s)
        if let a = savedKbdAuto { Keyboard.setAuto(a) }
        savedKbd = nil; savedKbdAuto = nil
    }

    func helper(_ arg: String, sync: Bool = false) {
        guard FileManager.default.fileExists(atPath: helperPath) else { helperOK = false; return }
        let run = {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            p.arguments = ["-n", helperPath, arg]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }
        if sync { helperOK = run(); return }
        DispatchQueue.global(qos: .utility).async {
            let ok = run()
            DispatchQueue.main.async { self.helperOK = ok; self.updateUI() }
        }
    }

    // 非アクティブなアプリ（ディープ中は前面アプリも）とその子プロセスを低優先度にする
    func refreshThrottle() {
        var want = Set<pid_t>()
        if (enabled || deep) && Prefs.throttleApps {
            let busy = assertionPIDs(), skip = Prefs.excluded, me = getpid()
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                let pid = app.processIdentifier
                if pid == me || (!deep && app.isActive) || skip.contains(app.bundleIdentifier ?? "") || busy.contains(pid) { continue }
                want.insert(pid)
                want.formUnion(descendants(pid).filter { !busy.contains($0) })
            }
        }
        for pid in throttled.subtracting(want) { setBackground(pid, false) }
        for pid in want { setBackground(pid, true) }
        throttled = want
    }

    @objc func appsChanged() { if enabled || deep || !throttled.isEmpty { refreshThrottle() } }

    // MARK: 無操作時のディープ省電力

    var idleActive: Bool { Prefs.idleMinutes > 0 && (enabled || power.onBattery) }

    func scheduleIdle() {
        idleTimer?.invalidate(); idleTimer = nil
        guard idleActive || deep else { return }
        // 通常は 5 秒おきに無操作時間を見る。ディープ中は操作再開にすぐ反応するため 1 秒おき
        let t = Timer(timeInterval: deep ? 1 : 5, repeats: true) { [weak self] _ in self?.checkIdle() }
        t.tolerance = deep ? 0.2 : 2
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    func checkIdle() {
        let idle = anyInputIdleSeconds()
        if deep { if idle < 2 { exitDeep() }; return }
        if idleActive, idle >= Double(Prefs.idleMinutes * 60), !displaySleepBlocked() { enterDeep() }
    }

    func enterDeep() {
        guard !deep else { return }
        deep = true
        if let b = Screen.brightness, b > deepLevel { deepBrightness = b; Screen.set(deepLevel) }
        keyboardOff()
        if Prefs.wifiOffIdle, let wifi = CWWiFiClient.shared().interface(), wifi.powerOn() {
            wifiWasOn = (try? wifi.setPower(false)) != nil
        }
        // マウス操作はアクセシビリティ権限なしで拾えるので即復帰に使う（キー入力は 1 秒ポーリングで拾う）
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] _ in
            self?.exitDeep()
        }
        refreshThrottle(); scheduleIdle(); updateUI()
    }

    func exitDeep() {
        guard deep else { return }
        deep = false
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let b = deepBrightness, let cur = Screen.brightness, abs(cur - deepLevel) < 0.02 { Screen.set(b) }
        deepBrightness = nil
        if !(enabled && Prefs.keyboardOff) { keyboardRestore() }
        if wifiWasOn { try? CWWiFiClient.shared().interface()?.setPower(true); wifiWasOn = false }
        refreshThrottle(); scheduleIdle(); updateUI()
    }

    // MARK: 電源・スリープ

    func powerChanged() {
        let now = Power.read()
        let before = power
        power = now
        if now.onBattery != before.onBattery {
            if now.onBattery && Prefs.autoOnBattery { setEnabled(true) }
            if !now.onBattery && Prefs.autoOffOnAC { setEnabled(false) }
        }
        // 残量がしきい値を下回った瞬間だけ ON にする（手動で OFF にしたのを毎回上書きしない）
        let th = Prefs.autoOnBelow
        if th > 0, now.onBattery, now.percent <= th, before.percent > th || !before.onBattery { setEnabled(true) }
        if deep && !idleActive { exitDeep() }
        scheduleIdle()
        updateUI()
    }

    // 蓋を開けた（スリープ復帰）: 眠っている間の電源変化を反映し、デーモン抑制を掛け直す
    @objc func didWake() {
        exitDeep()
        powerChanged()
        if enabled { helper("throttle"); refreshThrottle() }
    }

    @objc func screensWoke() { exitDeep() }

    // MARK: UI

    func updateUI() {
        let symbol = deep ? "moon.zzz.fill" : enabled ? "leaf.fill" : "leaf"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Dimleaf")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = "Dimleaf: \(modeName)"
        let state: [String: Any] = ["enabled": enabled, "deep": deep, "helper": helperOK, "onBattery": power.onBattery,
                                    "percent": power.percent, "throttledPIDs": throttled.count]
        try? FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]).write(to: stateFile)
    }

    var modeName: String { deep ? "無操作で省電力中" : enabled ? "低電力モード ON" : "通常" }

    func menuWillOpen(_ menu: NSMenu) {
        power = Power.read()
        menu.removeAllItems()
        let left = power.minutesLeft.map { String(format: "（残り %d:%02d）", $0 / 60, $0 % 60) } ?? ""
        menu.addItem(info("\(power.onBattery ? "バッテリー" : "電源アダプタ") \(power.percent)%\(left)"))
        menu.addItem(info("状態: \(modeName)\(throttled.isEmpty ? "" : "・抑制中 \(throttled.count) プロセス")"))
        if !helperOK { menu.addItem(info("⚠ pmset/デーモン制御が無効（sudo install-helper.sh 未実行）")) }
        menu.addItem(.separator())
        menu.addItem(Item("低電力モード", checked: enabled, key: "l") { [unowned self] in setEnabled(!enabled) })
        menu.addItem(.separator())

        menu.addItem(info("自動切り替え"))
        menu.addItem(Item("電源を外したら ON", checked: Prefs.autoOnBattery) { Prefs.autoOnBattery.toggle() })
        menu.addItem(Item("電源につないだら OFF", checked: Prefs.autoOffOnAC) { Prefs.autoOffOnAC.toggle() })
        menu.addItem(choices("残量で ON", [0, 20, 30, 50], Prefs.autoOnBelow, { $0 == 0 ? "しない" : "\($0)% 以下" }) {
            Prefs.autoOnBelow = $0
        })
        menu.addItem(choices("無操作で画面を暗く", [0, 1, 2, 5, 10], Prefs.idleMinutes, { $0 == 0 ? "しない" : "\($0) 分" }) { [unowned self] in
            Prefs.idleMinutes = $0; scheduleIdle()
        })
        menu.addItem(.separator())

        menu.addItem(info("低電力モードの内容"))
        menu.addItem(choices("画面輝度の上限", [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0], Prefs.brightnessCap, { $0 >= 1 ? "制限なし" : "\(Int($0 * 100))%" }) { [unowned self] in
            Prefs.brightnessCap = $0
            applyCap()  // 60 秒後の見直しを待たずにすぐ反映する
        })
        menu.addItem(Item("裏のアプリを低優先度に", checked: Prefs.throttleApps) { [unowned self] in
            Prefs.throttleApps.toggle(); refreshThrottle()
        })
        if Keyboard.available {
            menu.addItem(Item("キーボードライトを消す", checked: Prefs.keyboardOff) { [unowned self] in
                Prefs.keyboardOff.toggle()
                if enabled { Prefs.keyboardOff ? keyboardOff() : keyboardRestore() }
            })
        }
        menu.addItem(Item("無操作中は Wi-Fi もオフ", checked: Prefs.wifiOffIdle) { Prefs.wifiOffIdle.toggle() })
        menu.addItem(.separator())

        let top = NSMenuItem(title: "CPU 使用率の上位", action: nil, keyEquivalent: "")
        top.submenu = NSMenu()
        for line in topProcesses() { top.submenu?.addItem(info(line)) }
        menu.addItem(top)
        menu.addItem(Item("ログイン時に起動", checked: FileManager.default.fileExists(atPath: agentFile.path)) { toggleLoginItem() })
        menu.addItem(Item("終了（設定を元に戻す）", key: "q") { NSApp.terminate(nil) })
    }

    func choices<T: Equatable>(_ title: String, _ values: [T], _ current: T, _ label: @escaping (T) -> String,
                               _ pick: @escaping (T) -> Void) -> NSMenuItem {
        let parent = NSMenuItem(title: "\(title): \(label(current))", action: nil, keyEquivalent: "")
        parent.submenu = NSMenu()
        for v in values { parent.submenu?.addItem(Item(label(v), checked: v == current) { pick(v) }) }
        return parent
    }

    func topProcesses() -> [String] {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Aceo", "pcpu=,comm=", "-r"]
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return out.split(separator: "\n").prefix(6).map { $0.trimmingCharacters(in: .whitespaces) }
            .map { l in let parts = l.split(separator: " ", maxSplits: 1); return "\(parts.first ?? "")%  \(parts.dropFirst().first ?? "")" }
    }
}

func toggleLoginItem() {
    let fm = FileManager.default
    if fm.fileExists(atPath: agentFile.path) { try? fm.removeItem(at: agentFile); return }
    let plist: [String: Any] = ["Label": bundleID, "ProgramArguments": ["/usr/bin/open", "-a", appPath], "RunAtLoad": true]
    try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agentFile)
}

// MARK: CLI

func runCLI(_ cmd: String) -> Int32 {
    switch cmd {
    case "on", "off", "toggle":
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { $0.processIdentifier != getpid() }
        if !running {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-g", "-a", appPath]
            try? p.run(); p.waitUntilExit()
            sleep(2)
        }
        DistributedNotificationCenter.default().postNotificationName(commandNote, object: cmd, userInfo: nil, deliverImmediately: true)
        return 0
    case "status":
        print((try? String(contentsOf: stateFile)) ?? "Dimleaf が起動していません")
        return 0
    default:
        FileHandle.standardError.write("usage: dimleaf on|off|toggle|status\n".data(using: .utf8)!)
        return 2
    }
}

if CommandLine.arguments.count > 1, !CommandLine.arguments[1].hasPrefix("-psn") {
    exit(runCLI(CommandLine.arguments[1]))
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
