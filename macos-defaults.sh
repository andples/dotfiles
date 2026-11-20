#!/bin/sh
# macOS settings that would otherwise be clicked through again on a new Mac.
# Run it yourself (install.sh doesn't): ./macos-defaults.sh   (-n: show, don't change)
# Safe to re-run. Some settings only apply after logging out and back in.
set -e

DRY=
[ "${1-}" = -n ] && DRY=1

set_default() { # set_default DOMAIN KEY TYPE VALUE
  now=$(defaults read "$1" "$2" 2>/dev/null || echo '(unset)')
  [ "$now" = "$4" ] && return 0
  case $now in "~/"*) [ "$HOME/${now#"~/"}" = "$4" ] && return 0 ;; esac
  [ "$3" = -bool ] && case "$now:$4" in 1:true|0:false) return 0 ;; esac
  echo "  $1 $2: $now -> $4"
  [ -n "$DRY" ] || defaults write "$1" "$2" "$3" "$4"
}

echo "Keyboard and text"
# fast key repeat, and holding a key repeats it instead of showing the accent picker
set_default NSGlobalDomain KeyRepeat -int 6
set_default NSGlobalDomain InitialKeyRepeat -int 25
set_default NSGlobalDomain ApplePressAndHoldEnabled -bool false
# no autocorrect, auto-capitals or double-space full stops
set_default NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
set_default NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
set_default NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

echo "Finder"
set_default com.apple.finder AppleShowAllFiles -bool true
set_default NSGlobalDomain AppleShowAllExtensions -bool true
set_default com.apple.finder ShowPathbar -bool true
set_default com.apple.finder FXPreferredViewStyle -string Nlsv # list view
set_default com.apple.finder _FXSortFoldersFirst -bool true
set_default com.apple.finder FXDefaultSearchScope -string SCcf # search this folder
set_default com.apple.finder FXEnableExtensionChangeWarning -bool false
# no .DS_Store files on network shares and USB drives
set_default com.apple.desktopservices DSDontWriteNetworkStores -bool true
set_default com.apple.desktopservices DSDontWriteUSBStores -bool true

echo "Dock and windows"
set_default com.apple.dock autohide -bool true
set_default com.apple.dock tilesize -int 64
set_default com.apple.dock show-recents -bool false
set_default com.apple.dock wvous-br-corner -int 1 # no Quick Note in the bottom-right corner
# clicking the wallpaper doesn't hide every window; no Stage Manager; no gaps when tiling
set_default com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
set_default com.apple.WindowManager GloballyEnabled -bool false
set_default com.apple.WindowManager EnableTiledWindowMargins -bool false

echo "Screenshots"
shots="$HOME/Documents/Screenshots"
[ -n "$DRY" ] || mkdir -p "$shots"
set_default com.apple.screencapture location -string "$shots"

echo "Activity Monitor"
set_default com.apple.ActivityMonitor ShowCategory -int 100 # all processes

if [ -z "$DRY" ]; then
  killall Finder Dock SystemUIServer 2>/dev/null || true
  echo "done (log out and back in for the keyboard settings)"
fi
