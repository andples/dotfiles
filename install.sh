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

# Zed has no way to include other settings files, and it rewrites settings.json itself, so
# the zed package isn't linked: its snippets (zed/*.json) are merged into the machine's own
# settings.json. Keys from the snippets win; everything else in the file is kept.
merge_zed() {
  dest="$HOME/.config/zed/settings.json"
  base=$dest
  if ! have python3; then
    echo "  skipped: merging Zed settings needs python3"
    return 0
  fi
  # Older installs linked the whole file: go back to a real file, starting from the
  # settings that install backed up
  case "$(readlink "$dest" 2>/dev/null)" in
    "$DOTFILES"/*)
      echo "  replacing the old link with a real file"
      run rm "$dest"
      base=$(ls -d "$HOME"/.dotfiles-backup/*/.config/zed/settings.json 2>/dev/null | tail -n 1)
      [ -n "$base" ] && echo "  starting from ${base#"$HOME"/}" ;;
  esac

  tmp="${TMPDIR:-/tmp}/dotfiles-zed.$$"
  set +e
  python3 - "$base" "$tmp" "$DOTFILES"/zed/*.json <<'PY'
import json, os, sys

def strip_jsonc(text):
    # Zed's settings are JSON plus comments and trailing commas
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\":
                out.append(text[i + 1])
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            out.append(c)
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        elif c == ",":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j < n and text[j] in "}]":
                i += 1
                continue
            out.append(c)
        else:
            out.append(c)
        i += 1
    return "".join(out)

def load(path):
    if not path or not os.path.exists(path):
        return {}
    with open(path) as f:
        text = strip_jsonc(f.read())
    return json.loads(text) if text.strip() else {}

def merge(into, new):
    for key, value in new.items():
        if isinstance(value, dict) and isinstance(into.get(key), dict):
            merge(into[key], value)
        else:
            into[key] = value

base, tmp, snippets = sys.argv[1], sys.argv[2], sys.argv[3:]
path = base
try:
    current = load(base)
    merged = json.loads(json.dumps(current))
    for path in snippets:
        merge(merged, load(path))
except ValueError as e:
    print("  couldn't read %s: %s" % (path, e))
    sys.exit(1)
with open(tmp, "w") as f:
    json.dump(merged, f, indent=2)
    f.write("\n")
sys.exit(0 if merged != current else 3)
PY
  status=$?
  set -e
  # restoring from a backup always needs writing, even if the snippets add nothing new
  [ "$status" = 3 ] && [ "$base" != "$dest" ] && status=0

  case $status in
    0)
      if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        echo "  backing up ~/.config/zed/settings.json (comments in it aren't kept)"
        run mkdir -p "$BACKUP/.config/zed"
        run cp "$dest" "$BACKUP/.config/zed/settings.json"
      fi
      echo "  merging $(cd "$DOTFILES/zed" && echo *.json) into ~/.config/zed/settings.json"
      run mkdir -p "$(dirname "$dest")"
      run cp "$tmp" "$dest" ;;
    3) echo "  ~/.config/zed/settings.json already up to date" ;;
    *) echo "  left ~/.config/zed/settings.json alone" ;;
  esac
  rm -f "$tmp"
}

if [ "$1" = --check ]; then
  check_deps
  exit 0
fi

if [ $# -eq 0 ]; then
  set -- shell bin git agents starship
  # Omarchy ships its own LazyVim setup; only install the minimal nvim config elsewhere
  if [ -z "$OMARCHY_PATH" ] && [ ! -d /usr/share/omarchy ]; then set -- "$@" nvim; fi
  [ "$(uname)" = Darwin ] && set -- "$@" zsh
  [ -z "$OMARCHY_PATH" ] && [ ! -d /usr/share/omarchy ] && set -- "$@" readline
  # Zed creates this folder on first launch
  [ -d "$HOME/.config/zed" ] && set -- "$@" zed
fi

for pkg in "$@"; do
  if [ ! -d "$DOTFILES/$pkg" ]; then
    echo "no such package: $pkg" >&2
    exit 1
  fi
  echo "$pkg"
  if [ "$pkg" = zed ]; then merge_zed; continue; fi
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

# Remove links to files that are no longer in the repo (e.g. a package that was deleted)
for dir in "$HOME/.config" "$HOME/.local/bin" "$HOME/.claude" "$HOME/.codex" "$HOME/.pi"; do
  [ -d "$dir" ] || continue
  find "$dir" -type l 2>/dev/null | while IFS= read -r link; do
    case "$(readlink "$link")" in
      "$DOTFILES"/*)
        if [ ! -e "$link" ]; then
          echo "removing stale link ${link#"$HOME"/}"
          run rm "$link"
        fi ;;
    esac
  done
done

# git reads the shared settings via an include, so the machine's own config (identity,
# credential helpers) stays a real file. Older installs linked that file directly: undo that.
gitcfg="$HOME/.config/git/config"
case "$(readlink "$gitcfg" 2>/dev/null)" in
  "$DOTFILES"/*)
    echo "git: ~/.config/git/config was a link into dotfiles, removing it"
    run rm "$gitcfg" ;;
esac
if [ -e "$HOME/.config/git/dotfiles.gitconfig" ] && ! grep -qs 'path = dotfiles.gitconfig' "$gitcfg"; then
  echo "git: including dotfiles.gitconfig from ~/.config/git/config"
  if [ -z "$DRY" ]; then
    printf '\n[include]\n\tpath = dotfiles.gitconfig\n' >> "$gitcfg"
  fi
fi

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
