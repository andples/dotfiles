#!/bin/sh
# Link dotfiles into $HOME (same result as `stow --no-folding`), no dependencies.
# Anything already in the way is moved to ~/.dotfiles-backup/<timestamp>/.
#
#   ./install.sh               pick packages for this machine
#   ./install.sh zsh git       only these packages
#   ./install.sh -n ...        dry run: show what would happen
set -e

DOTFILES=$(cd "$(dirname "$0")" && pwd)
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
DRY=
if [ "$1" = -n ]; then DRY=1; shift; fi

run() { if [ -n "$DRY" ]; then echo "  would: $*"; else "$@"; fi; }

if [ $# -eq 0 ]; then
  set -- shell bin git nvim agents
  [ "$(uname)" = Darwin ] && set -- "$@" zsh
  [ -z "$OMARCHY_PATH" ] && [ ! -d /usr/share/omarchy ] && set -- "$@" readline
fi

for pkg in "$@"; do
  if [ ! -d "$DOTFILES/$pkg" ]; then
    echo "no such package: $pkg" >&2
    exit 1
  fi
  echo "$pkg"
  (cd "$DOTFILES/$pkg" && find . -mindepth 1 \( -type f -o -type l \) | sed 's#^\./##') |
  while IFS= read -r rel; do
    src="$DOTFILES/$pkg/$rel"
    dest="$HOME/$rel"

    # agent tools: only link into tools that are installed here
    case "$pkg/$rel" in
      agents/.config/agents/*) ;;
      agents/*) [ -d "$(dirname "$dest")" ] || continue ;;
    esac

    [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ] && continue

    if [ -e "$dest" ] || [ -L "$dest" ]; then
      echo "  backing up ~/$rel"
      run mkdir -p "$(dirname "$BACKUP/$rel")"
      run mv "$dest" "$BACKUP/$rel"
    fi
    echo "  ~/$rel"
    run mkdir -p "$(dirname "$dest")"
    run ln -s "$src" "$dest"
  done
done

# bash loads the shared config with one line (Omarchy owns ~/.bashrc, so it isn't linked)
if [ "$(uname)" != Darwin ] && ! grep -qs 'config/shell/shared.sh' "$HOME/.bashrc"; then
  echo "bash: adding shared.sh to ~/.bashrc"
  if [ -z "$DRY" ]; then
    printf '\n[ -f ~/.config/shell/shared.sh ] && . ~/.config/shell/shared.sh\n' >> "$HOME/.bashrc"
  fi
fi

[ -d "$BACKUP" ] && echo "old files saved in $BACKUP"
exit 0
