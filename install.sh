#!/bin/zsh
# Build MouseNav.app, install the LaunchAgent, seed config. Safe to re-run.
set -euo pipefail
# Piped via `curl … | zsh` there's no checkout, so fetch the source into a temp dir first.
if [[ -f "${0:A:h}/Sources/main.swift" ]]; then
  cd "${0:A:h}"
else
  SRC=$(mktemp -d)
  curl -fsSL https://github.com/willosullivan/mousenav/archive/refs/heads/main.tar.gz | tar -xz -C "$SRC" --strip-components 1
  cd "$SRC"
fi

APP=~/Applications/MouseNav.app
LABEL=com.asa.mousenav
PLIST=~/Library/LaunchAgents/$LABEL.plist
CONFIG=~/.config/mousenav/config.json

mkdir -p "$APP/Contents/MacOS" ~/.config/mousenav ~/Library/Logs build

# CLT 16.x bug: a stale usr/include/swift/module.modulemap (left by an older CLT) redefines
# SwiftBridging and breaks `import Cocoa`. Mask it with a VFS overlay rather than needing sudo rm.
STALE=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
FLAGS=()
if [[ -f $STALE && -f ${STALE:h}/bridging.modulemap ]]; then
  : > build/empty.modulemap
  print -r -- "{\"version\":0,\"roots\":[{\"type\":\"file\",\"name\":\"$STALE\",\"external-contents\":\"$PWD/build/empty.modulemap\"}]}" > build/overlay.yaml
  FLAGS=(-vfsoverlay build/overlay.yaml -Xcc -ivfsoverlay -Xcc build/overlay.yaml)
fi
swiftc -O -swift-version 5 $FLAGS Sources/main.swift -o "$APP/Contents/MacOS/MouseNav"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>MouseNav</string>
  <key>CFBundleExecutable</key><string>MouseNav</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
# Ad-hoc signatures change every build, so macOS drops the Accessibility grant on rebuild.
# A stable "MouseNav Local Signing" identity in the keychain keeps the grant (see README).
IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk '/"MouseNav Local Signing"/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" --identifier "$LABEL" "$APP"

[[ -f $CONFIG ]] || cp config.example.json "$CONFIG"
rm -f ~/.config/mousenav/.prompted  # let the new build show the permission prompt once

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/MouseNav</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/mousenav.log</string>
</dict></plist>
EOF

launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PLIST"
echo "Installed. Logs: tail -f ~/Library/Logs/mousenav.log"
