#!/bin/sh
# Link dotfiles into $HOME (same result as `stow --no-folding`), no dependencies.
# Anything already in the way is moved to ~/.dotfiles-backup/<timestamp>/.
#
#   ./install.sh               pick packages for this machine
#   ./install.sh zsh git       only these packages
#   ./install.sh -n ...        dry run: show what would happen
#   ./install.sh --check       only check for missing tools
#
# After linking it checks for missing tools and prints how to install them for this OS.
# It never installs anything itself, and missing tools never make it fail.
set -e

DOTFILES=$(cd "$(dirname "$0")" && pwd)
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
OS_RELEASE=${DOTFILES_OS_RELEASE:-/etc/os-release}
DRY=
if [ "$1" = -n ]; then DRY=1; shift; fi

run() { if [ -n "$DRY" ]; then echo "  would: $*"; else "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

# Tools the configs use. Everything works without them, minus that feature.
TOOLS="git nvim fzf zoxide eza bat starship direnv uv tree lsof unzip python3"
# Tools mise can install into $HOME without admin rights
MISE_TOOLS="nvim fzf zoxide eza bat starship direnv uv"

installed() {
  case $1 in
    bat) have bat || have batcat ;;
    zsh-autosuggestions)
      for f in /opt/homebrew/share /usr/local/share /usr/share/zsh/plugins /usr/share; do
        [ -f "$f/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && return 0
      done
      return 1 ;;
    *) have "$1" ;;
  esac
}

# Package name for a tool under a package manager (empty: not packaged there)
pkg_name() {
  case "$1:$2" in
    nvim:*)                  echo neovim ;;
    python3:brew|python3:pacman) echo python ;;
    starship:apt|uv:apt|uv:zypper) ;;
    *)                       echo "$1" ;;
  esac
}

check_deps() {
  tools=$TOOLS
  [ "$(uname)" = Darwin ] && tools="$tools zsh-autosuggestions"

  missing=
  for t in $tools; do
    installed "$t" || missing="$missing $t"
  done

  mgr=
  if [ "$(uname)" = Darwin ]; then
    os=macOS
    mgr=brew
  elif [ -r "$OS_RELEASE" ]; then
    os=$(. "$OS_RELEASE"; echo "${PRETTY_NAME:-${ID:-Linux}}")
    case " $(. "$OS_RELEASE"; echo "$ID $ID_LIKE") " in
      *" arch "*)                 mgr=pacman ;;
      *" debian "*|*" ubuntu "*)  mgr=apt ;;
      *" fedora "*|*" rhel "*)    mgr=dnf ;;
      *suse*)                     mgr=zypper ;;
    esac
  else
    os=$(uname)
  fi

  echo
  echo "Dependencies ($os):"
  if [ -z "$missing" ]; then
    echo "  all installed"
    return 0
  fi
  echo "  missing:$missing"

  # Admin rights: brew needs none; on Linux check groups (never run sudo, it can
  # email the admin on machines where you aren't allowed)
  admin=
  if [ "$mgr" = brew ]; then
    have brew && admin=1
  elif [ "$(id -u)" = 0 ] || id -nG 2>/dev/null | grep -qwE 'wheel|sudo|admin'; then
    admin=1
  fi
  sudo="sudo "
  [ "$(id -u)" = 0 ] && sudo=

  pkgs=
  unpackaged=
  for t in $missing; do
    p=$(pkg_name "$t" "$mgr")
    if [ -n "$p" ]; then pkgs="$pkgs $p"; else unpackaged="$unpackaged $t"; fi
  done

  if [ -n "$admin" ] && [ -n "$mgr" ]; then
    case $mgr in
      brew)   echo "  install: brew install$pkgs" ;;
      pacman) echo "  install: ${sudo}pacman -S --needed$pkgs" ;;
      apt)    echo "  install: ${sudo}apt install$pkgs" ;;
      dnf)    echo "  install: ${sudo}dnf install$pkgs" ;;
      zypper) echo "  install: ${sudo}zypper install$pkgs" ;;
    esac
    [ -n "$unpackaged" ] && echo "  not in $mgr:$unpackaged"
  elif [ "$mgr" = brew ]; then
    echo "  Homebrew isn't installed (needs admin): https://brew.sh"
  elif [ -n "$mgr" ]; then
    echo "  no admin rights here, so $mgr isn't an option"
  else
    echo "  unknown package manager: install these with your system's one, or mise (below)"
  fi

  # User-level fallback that never needs admin
  # (with a working package manager, only for what it doesn't package)
  want=$missing
  [ -n "$admin" ] && [ -n "$mgr" ] && want=$unpackaged
  user=
  rest=
  for t in $want; do
    case " $MISE_TOOLS " in
      *" $t "*) user="$user $(pkg_name "$t" mise)" ;;
      *) rest="$rest $t" ;;
    esac
  done
  if [ -n "$user" ]; then
    if have mise; then
      echo "  user install: mise use -g$user"
    else
      echo "  user install: curl https://mise.run | sh && ~/.local/bin/mise use -g$user"
    fi
  fi
  if [ -z "$admin" ] && [ -n "$rest" ]; then
    echo "  needs admin (ask, or live without):$rest"
  fi
  return 0
}

if [ "$1" = --check ]; then
  check_deps
  exit 0
fi

if [ $# -eq 0 ]; then
  set -- shell bin git nvim agents starship
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
check_deps || true
exit 0
