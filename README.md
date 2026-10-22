# MouseNav

Make your mouse's back/forward buttons work on macOS, in every app, with **one ~140-line Swift file**.

No Logitech Options+, no account, no menu bar clutter, no network access, no telemetry.

| | MouseNav |
|---|---|
| Memory | ~14 MB |
| CPU when idle | 0% (only wakes on side-button clicks, never on mouse movement) |
| Binary | ~125 KB |
| Code you can read | 1 file, ~140 lines |

Works with any mouse that has side buttons (built and tested on a Logitech MX Master 3S over Bluetooth).

## Install

Needs the Xcode Command Line Tools (`xcode-select --install`). You build it yourself from source, so there's nothing pre-built for macOS to block.

```sh
git clone https://github.com/willosullivan/mousenav.git
cd mousenav && ./install.sh
```

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

A `CGEventTap` that only listens for "other mouse button" events, so it never sees mouse movement or keystrokes. When a mapped button is pressed in the frontmost app, it swallows the click and sends the configured keystroke instead. A LaunchAgent keeps it running.

**Note:** each rebuild changes the binary's signature, so macOS may forget the Accessibility approval. If it stops working after `./install.sh`, remove MouseNav from the Accessibility list and add it again.

## License

MIT
