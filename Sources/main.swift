// MouseNav — remaps extra mouse buttons to keystrokes / shell commands, per app.
// Config: ~/.config/mousenav/config.json (hot-reloaded on change, no rebuild needed).
//
// Hot path is one array index: config is compiled to actions up front, and the per-app table is
// resolved when the frontmost app changes, not on each click. No file I/O or string work per click.

import Cocoa

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/mousenav/config.json")

func log(_ msg: String) {
    FileHandle.standardError.write("[\(Date())] \(msg)\n".data(using: .utf8)!)
}

// MARK: - Actions

enum Action {
    case passthrough, none
    case keys(CGKeyCode, CGEventFlags)
    case shell(String)
}

let keyCodes: [String: CGKeyCode] = [
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
    "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
    "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
    "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
    "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
    "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
    "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "escape": 0x35,
    "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
    "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61,
    "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
]

let modifiers: [String: CGEventFlags] = [
    "cmd": .maskCommand, "ctrl": .maskControl, "alt": .maskAlternate, "opt": .maskAlternate,
    "shift": .maskShift, "fn": .maskSecondaryFn,
]

// "cmd+shift+]" -> .keys. "cmd++" means cmd+=. Returns nil (and logs) for anything unparseable.
func parseAction(_ s: String) -> Action? {
    switch s {
    case "passthrough": return .passthrough
    case "none": return Action.none
    default: break
    }
    if s.hasPrefix("shell:") { return .shell(String(s.dropFirst(6))) }
    var parts = s.lowercased().components(separatedBy: "+")
    if s.hasSuffix("++") { parts.removeLast(2); parts.append("=") }
    guard let key = parts.last, let code = keyCodes[key] else { log("unknown key in '\(s)'"); return nil }
    var flags = CGEventFlags()
    for m in parts.dropLast() {
        guard let f = modifiers[m] else { log("unknown modifier '\(m)' in '\(s)'"); return nil }
        flags.insert(f)
    }
    return .keys(code, flags)
}

let eventSource = CGEventSource(stateID: .hidSystemState)

func perform(_ action: Action) {
    switch action {
    case .passthrough, .none: break
    case let .keys(code, flags):
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    case let .shell(cmd):
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", cmd]
        do { try p.run() } catch { log("shell failed: \(error)") }
    }
}

// MARK: - Config (compiled to button-indexed tables)

struct RawConfig: Decodable {
    var debug: Bool?
    var `default`: [String: String]
    var apps: [String: [String: String]]?
}

let maxButtons = 32
typealias Table = [Action?]  // index = button number; nil = unmapped (pass through)

var debug = false
var defaultTable: Table = {
    var t = Table(repeating: nil, count: maxButtons)
    t[3] = .keys(0x21, .maskCommand); t[4] = .keys(0x1E, .maskCommand)  // cmd+[ / cmd+]
    return t
}()
var appOverrides: [String: Table] = [:]
var activeTable = defaultTable  // default merged with the frontmost app's overrides
var frontBundleID = ""

func compile(_ map: [String: String], onto base: Table) -> Table {
    var t = base
    for (k, v) in map {
        guard let b = Int(k), (0..<maxButtons).contains(b) else { log("bad button '\(k)'"); continue }
        if let a = parseAction(v) { t[b] = a }
    }
    return t
}

func activate(_ bundleID: String) {
    frontBundleID = bundleID
    activeTable = appOverrides[bundleID] ?? defaultTable
}

func loadConfig() {
    do {
        let raw = try JSONDecoder().decode(RawConfig.self, from: Data(contentsOf: configURL))
        debug = raw.debug ?? false
        defaultTable = compile(raw.default, onto: Table(repeating: nil, count: maxButtons))
        appOverrides = (raw.apps ?? [:]).mapValues { compile($0, onto: defaultTable) }
        activate(frontBundleID)
        log("config loaded")
    } catch {
        log("config error, keeping previous: \(error)")
    }
}

// Watch the directory (catches editors that save via rename) and the file (catches in-place writes).
var watchers: [DispatchSourceFileSystemObject] = []

func watchConfig() {
    watchers.forEach { $0.cancel() }
    watchers = []
    for path in [configURL.deletingLastPathComponent().path, configURL.path] {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { continue }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        src.setEventHandler { loadConfig(); watchConfig() }  // re-arm: the file may be a new inode
        src.setCancelHandler { close(fd) }
        src.resume()
        watchers.append(src)
    }
}

// MARK: - Event tap

var tap: CFMachPort?

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        log("tap re-enabled")
        return Unmanaged.passUnretained(event)
    }

    let t0 = debug ? DispatchTime.now().uptimeNanoseconds : 0
    let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
    let action = button < maxButtons ? activeTable[button] : nil

    var result: Unmanaged<CGEvent>? = Unmanaged.passUnretained(event)
    if let action {
        if case .passthrough = action {} else {
            if type == .otherMouseDown { perform(action) }
            result = nil  // swallow both down and up for mapped buttons
        }
    }
    if debug, type == .otherMouseDown {
        let us = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1000
        log("button \(button) in \(frontBundleID) → \(action.map { "\($0)" } ?? "-") (\(String(format: "%.1f", us)) µs)")
    }
    return result
}

// MARK: - Main

activate(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
loadConfig()

// `MouseNav --bench [button] [n]`: time the click handler in-process (no tap, no permission needed).
// Use an unmapped, "none" or "passthrough" button so nothing is actually sent.
if CommandLine.arguments.dropFirst().first == "--bench" {
    let args = CommandLine.arguments
    let button = Int64(args.count > 2 ? args[2] : "7")!, n = Int(args.count > 3 ? args[3] : "10000")!
    debug = false
    let ev = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                     mouseCursorPosition: .zero, mouseButton: .center)!
    ev.setIntegerValueField(.mouseEventButtonNumber, value: button)
    let proxy = OpaquePointer(bitPattern: 1)!
    var samples = [Double]()
    samples.reserveCapacity(n)
    for _ in 0..<n {
        let t0 = DispatchTime.now().uptimeNanoseconds
        _ = callback(proxy, .otherMouseDown, ev, nil)
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1000)
    }
    samples.sort()
    print(String(format: "button %lld, n=%d: p50 %.2f µs, p99 %.2f µs, max %.2f µs",
                 button, n, samples[n / 2], samples[n * 99 / 100], samples[n - 1]))
    exit(0)
}

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
// The trust check is cached for the life of the process, so polling never sees a later grant.
// Exit instead and let launchd relaunch us (ThrottleInterval) until permission is granted.
// Only show the system prompt once per install (install.sh clears the marker), not on every relaunch.
let promptedMarker = configURL.deletingLastPathComponent().appendingPathComponent(".prompted")
let shouldPrompt = !FileManager.default.fileExists(atPath: promptedMarker.path)
if !AXIsProcessTrustedWithOptions([promptKey: shouldPrompt] as CFDictionary) {
    if shouldPrompt { FileManager.default.createFile(atPath: promptedMarker.path, contents: nil) }
    log("waiting for Accessibility permission (System Settings → Privacy & Security → Accessibility)")
    Thread.sleep(forTimeInterval: 5)
    exit(1)
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { note in
    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    activate(app?.bundleIdentifier ?? "")
}
watchConfig()

let mask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                callback: callback, userInfo: nil) else {
    log("failed to create event tap"); exit(1)
}
tap = t
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
CGEvent.tapEnable(tap: t, enable: true)
log("running")
CFRunLoopRun()
