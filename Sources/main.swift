// MouseNav — remaps extra mouse buttons to keystrokes / shell commands, per app.
// Config: ~/.config/mousenav/config.json (hot-reloaded on change, no rebuild needed).

import Cocoa

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/mousenav/config.json")

// MARK: - Config

struct Config: Decodable {
    var debug: Bool?
    var `default`: [String: String]
    var apps: [String: [String: String]]?
}

var config = Config(debug: false, default: ["3": "cmd+[", "4": "cmd+]"], apps: nil)
var configMtime: Date?

func reloadConfigIfChanged() {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path),
          let mtime = attrs[.modificationDate] as? Date, mtime != configMtime else { return }
    configMtime = mtime
    do {
        config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
        log("config loaded")
    } catch {
        log("config error, keeping previous: \(error)")
    }
}

func log(_ msg: String) {
    FileHandle.standardError.write("[\(Date())] \(msg)\n".data(using: .utf8)!)
}

// MARK: - Actions

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

// "cmd+shift+]" -> keystroke. Split on the last '+' groups so "ctrl+-" and "cmd++" both parse.
func sendCombo(_ combo: String) {
    var parts = combo.lowercased().components(separatedBy: "+")
    if combo.hasSuffix("++") { parts.removeLast(2); parts.append("=") } // cmd++ means cmd+=
    guard let key = parts.last, let code = keyCodes[key] else { log("unknown key in '\(combo)'"); return }
    var flags = CGEventFlags()
    for m in parts.dropLast() {
        guard let f = modifiers[m] else { log("unknown modifier '\(m)' in '\(combo)'"); return }
        flags.insert(f)
    }
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }
}

func runShell(_ cmd: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", cmd]
    do { try p.run() } catch { log("shell failed: \(error)") }
}

// nil = no mapping (pass the click through untouched)
func action(for button: Int64) -> String? {
    let key = String(button)
    let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    if let appMap = config.apps?[bundleID], let a = appMap[key] { return a }
    return config.default[key]
}

// MARK: - Event tap

var tap: CFMachPort?

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        log("tap re-enabled")
        return Unmanaged.passUnretained(event)
    }

    let button = event.getIntegerValueField(.mouseEventButtonNumber)
    if type == .otherMouseDown { reloadConfigIfChanged() }

    if config.debug == true, type == .otherMouseDown {
        log("button \(button) in \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
    }

    guard let act = action(for: button), act != "passthrough" else {
        return Unmanaged.passUnretained(event)
    }
    if type == .otherMouseDown {
        if act.hasPrefix("shell:") { runShell(String(act.dropFirst(6))) }
        else if act != "none" { sendCombo(act) }
    }
    return nil // swallow both down and up for mapped buttons
}

// MARK: - Main

reloadConfigIfChanged()

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
