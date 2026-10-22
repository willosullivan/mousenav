# MouseNav

Personal macOS utility: remaps extra mouse buttons (MX Master 3S) to keystrokes or shell commands, per app. Replaces Logi Options+ / LinearMouse.

## Constraints
- Needs **Accessibility** permission. On Will's Mac, builds are signed with the keychain identity `MouseNav Local Signing` (self-signed, expires 2036), so the permission survives rebuilds (verified 2026-10-22 with a changed binary). Without that identity, builds fall back to ad-hoc signing and every rebuild resets the permission.
- If the permission gets stuck: `tccutil reset Accessibility com.asa.mousenav && rm ~/.config/mousenav/.prompted && launchctl kickstart -k gui/$(id -u)/com.asa.mousenav`, then approve the single prompt.
- `install.sh` works around a CLT 16.4 modulemap bug with a VFS overlay (see ~/.claude/ERROR_LEARNINGS.md).

## Layout
| Path | Purpose |
|---|---|
| `Sources/main.swift` | Event tap, config loader, actions |
| `install.sh` | Build → `~/Applications/MouseNav.app`, ad-hoc sign, LaunchAgent `com.asa.mousenav` |
| `~/.config/mousenav/config.json` | Live config (re-read on the next click after a change) |
| `~/Library/Logs/mousenav.log` | Logs |

## Config actions
`"cmd+["` key combo · `"passthrough"` leave the click alone · `"none"` swallow it · `"shell:<cmd>"` run a command.
Buttons are macOS 0-indexed: 3 = back, 4 = forward. Set `"debug": true` to log the button number and frontmost bundle ID on each click.

## Status (2026-10-22)
- [x] v1.0.0 tagged locally; stable signing; curl one-line install
- [x] Published: https://github.com/willosullivan/mousenav (2026-10-22)
- [ ] Homebrew tap (only if people use it)
- [x] Back/forward: ⌘[ / ⌘] by default; native passthrough for Chromium browsers and Firefox; ⌃- / ⌃⇧- in VS Code and Cursor
- [ ] Gesture button / thumb wheel. Over Bluetooth these may need Logitech's own protocol (HID++) rather than standard mouse events. Check with debug mode first.
