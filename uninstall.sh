#!/bin/zsh
# Remove MouseNav: LaunchAgent, app, logs. Leaves ~/.config/mousenav unless --purge.
LABEL=com.asa.mousenav
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null
rm -f ~/Library/LaunchAgents/$LABEL.plist ~/Library/Logs/mousenav.log
rm -rf ~/Applications/MouseNav.app
[[ ${1:-} == --purge ]] && rm -rf ~/.config/mousenav
echo "Uninstalled. Remove MouseNav from System Settings → Privacy & Security → Accessibility."
