# MouseNav

Back/forward mouse buttons for macOS, configured in a text file, in ~235 lines of Swift you can read before you install.

**Built for people who keep their setup in dotfiles and let an AI agent edit them.** Every behaviour lives in one JSON file, so you can version it, copy it to a new Mac, or tell Claude *"make the back button close the tab in Slack"* and it just edits the file. There's no settings window to click through.

## Why this one

| | |
|---|---|
| **Config as code** | One JSON file. Changes apply instantly, with no restart. Agents can edit it; GUI-only mouse apps can't be driven that way |
| **Invisible** | No window, no menu bar icon, no account, no network access, no telemetry, no updater |
| **Minimal access** | It only listens for extra mouse button clicks. It never sees mouse movement, scrolling or keystrokes |
| **Per-app** | A different shortcut or shell command for each app, e.g. ⌃- in VS Code, untouched in Chrome |
| **Auditable** | One source file, built on your machine from source. No pre-built binary to trust |

## Performance

Measured on an Apple Silicon Mac (macOS 15). Reproduce with `~/Applications/MouseNav.app/Contents/MacOS/MouseNav --bench`.

| | |
|---|---|
| Time to handle a click | **~40 ns** median, under 8 µs worst case (excludes sending the keystroke) |
| CPU when idle | **0%**. The process sleeps until a side button is pressed |
| Memory | **~4.5 MB** physical footprint |
| Binary | ~150 KB |

How: settings are compiled into a lookup table when the file changes, and the active app is tracked when you switch apps, not when you click. A click does one array lookup: no file checks, no text parsing, no system calls.

## Use something else if…

- **You want a settings window**: [LinearMouse](https://linearmouse.app) (free, open source)
- **You want smooth scrolling or click-and-drag gestures**: [Mac Mouse Fix](https://macmousefix.com)
- **You need the MX Master gesture button or thumb wheel fully customised**: Logitech Options+

Works with any mouse that has side buttons (built and tested on a Logitech MX Master 3S over Bluetooth).

## Install

Needs the Xcode Command Line Tools (`xcode-select --install`). You build it yourself from source, so there's nothing pre-built for macOS to block.

```sh
curl -fsSL https://raw.githubusercontent.com/willosullivan/mousenav/main/install.sh | zsh
```

Or with Claude Code (or any coding agent): *"Install github.com/willosullivan/mousenav"*. The agent reads this README and runs the line above.

Or from a clone: `git clone https://github.com/willosullivan/mousenav.git && cd mousenav && ./install.sh`

Then turn on **MouseNav** in **System Settings → Privacy & Security → Accessibility**. It starts within about 10 seconds and launches at login from then on.

## Default behaviour

| App | Back / Forward |
|---|---|
| Most apps (Finder, Safari, Slack, Notes, System Settings…) | ⌘[ / ⌘] |
| Chrome, Arc, Brave, Edge, Firefox | Passed through untouched (these handle the buttons natively) |
| VS Code, Cursor | ⌃- / ⌃⇧- |

## Configure

Edit `~/.config/mousenav/config.json`. Changes apply on your next click, with no restart needed.

```json
{
  "debug": false,
  "default": { "3": "cmd+[", "4": "cmd+]" },
  "apps": {
    "com.microsoft.VSCode": { "3": "ctrl+-", "4": "ctrl+shift+-" },
    "com.apple.Terminal":   { "3": "shell:open -a 'Mission Control'" }
  }
}
```

| Action | Meaning |
|---|---|
| `"cmd+shift+]"` | Send a key combo (`cmd` `ctrl` `alt`/`opt` `shift` `fn` + key) |
| `"passthrough"` | Leave the click alone |
| `"none"` | Swallow the click |
| `"shell:<command>"` | Run a shell command |

Button numbers start at 0, so **3 = back** and **4 = forward**. Set `"debug": true` and run `tail -f ~/Library/Logs/mousenav.log` to see each click's button number and the frontmost app's bundle ID.

## Manage

```sh
launchctl kickstart -k gui/$(id -u)/com.asa.mousenav   # restart
tail -f ~/Library/Logs/mousenav.log                    # logs
./uninstall.sh                                         # remove (add --purge to delete config)
```

## How it works

A `CGEventTap` that only listens for "other mouse button" events, so it never sees mouse movement or keystrokes. When a mapped button is pressed, it swallows the click and sends the configured keystroke instead. Settings reload via file-system events (kqueue), the frontmost app is tracked via workspace notifications, and a LaunchAgent (`ProcessType: Interactive`, so macOS doesn't deprioritise it) keeps it running.

**Note:** builds are ad-hoc signed by default, so macOS forgets the Accessibility approval after each rebuild or update. If it stops working, remove MouseNav from the Accessibility list and add it again. To avoid this on your own machine, create a self-signed code-signing certificate named `MouseNav Local Signing` in your login keychain. `install.sh` uses it automatically, and the approval then survives rebuilds.

## License

MIT
