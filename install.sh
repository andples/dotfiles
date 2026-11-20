#!/bin/sh
# Link dotfiles into $HOME (same result as `stow --no-folding`), no dependencies.
# Anything already in the way is moved to ~/.dotfiles-backup/<timestamp>/.
#
#   ./install.sh               ask which packages to install (this machine's defaults ticked)
#   ./install.sh -y            install the defaults without asking (also when not on a terminal)
#   ./install.sh zsh git       only these packages
#   ./install.sh -n ...        dry run: show what would happen (the picker still asks)
#   ./install.sh --check       only check for missing tools
#
# Personal packages (agents, peek) are only ticked by default on the owner's machines:
# gh logged in as the owner, DOTFILES_OWNER=1, or a ~/.config/dotfiles/owner file.
# DOTFILES_OWNER=0 shows what anyone else gets.
#
# After linking it checks for missing tools and prints how to install them for this OS.
# It never installs tools itself (only Peek, when asked), and missing tools never make it fail.
set -e

DOTFILES=$(cd "$(dirname "$0")" && pwd)
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
OS_RELEASE=${DOTFILES_OS_RELEASE:-/etc/os-release}
DRY=
YES=
while :; do
  case $1 in
    -n) DRY=1; shift ;;
    -y) YES=1; shift ;;
    -ny|-yn) DRY=1; YES=1; shift ;;
    *) break ;;
  esac
done
OWNER=andples

run() { if [ -n "$DRY" ]; then echo "  would: $*"; else "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

# Tools the configs use. Everything works without them, minus that feature.
TOOLS="git nvim fzf zoxide eza bat starship direnv uv tree lsof unzip python3 clipboard tmux typst"
# Tools mise can install into $HOME without admin rights
MISE_TOOLS="nvim fzf zoxide eza bat starship direnv uv typst"

installed() {
  case $1 in
    bat) have bat || have batcat ;;
    # for `pb`: pbcopy ships with macOS
    clipboard) have pbcopy || have wl-copy || have xclip || have xsel ;;
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
    starship:apt|starship:dnf|uv:apt|uv:zypper|typst:apt|typst:dnf) ;;
    clipboard:*)             if [ -n "$WAYLAND_DISPLAY" ]; then echo wl-clipboard; else echo xclip; fi ;;
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

  if [ -n "$admin" ] && [ -n "$mgr" ] && [ -z "$pkgs" ]; then
    echo "  not in $mgr:$unpackaged"
  elif [ -n "$admin" ] && [ -n "$mgr" ]; then
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

# Peek, the Markdown viewer the Zed config pops up (github.com/andples/peek, private).
# Not a package of this repo: it's cloned to $PEEK_SRC (default ~/.local/src/peek), or
# updated if it's already there, then built into /Applications. macOS only.
PEEK_REPO=${PEEK_REPO:-git@github.com:andples/peek.git}
PEEK_SRC=${PEEK_SRC:-$HOME/.local/src/peek}
install_peek() {
  echo "peek"
  if [ "$(uname)" != Darwin ]; then
    echo "  skipped: Peek is a macOS app (the \`peek\` command falls back to xdg-open)"
    return 0
  fi
  if ! have git || ! have swift; then
    echo "  skipped: building Peek needs git and Swift (xcode-select --install)"
    return 0
  fi
  if [ -d "$PEEK_SRC/.git" ]; then
    echo "  updating ${PEEK_SRC#"$HOME"/}"
    run git -C "$PEEK_SRC" pull --ff-only -q || echo "  couldn't update it, building what's there"
  else
    echo "  cloning $PEEK_REPO into ${PEEK_SRC#"$HOME"/}"
    run mkdir -p "$(dirname "$PEEK_SRC")"
    if ! run git clone -q "$PEEK_REPO" "$PEEK_SRC"; then
      echo "  skipped: couldn't clone it (the repo is private: needs your GitHub ssh key)"
      return 0
    fi
  fi
  echo "  building (a minute the first time)"
  if [ -n "$DRY" ]; then
    echo "  would: $PEEK_SRC/scripts/build-app.sh --install"
  elif ! "$PEEK_SRC/scripts/build-app.sh" --install >/dev/null; then
    echo "  build failed: run $PEEK_SRC/scripts/build-app.sh to see why"
  else
    echo "  installed Peek.app"
  fi
  return 0
}

# notes: clone the repo, then start the sync timer
LAUNCHD_LABEL=dotfiles.notes-sync
setup_notes() {
  if [ ! -d "${NOTES_DIR:-$HOME/notes}/.git" ]; then
    if [ -n "$DRY" ]; then
      echo "  would: notes --clone"
    elif ! "$DOTFILES/notes/.local/bin/notes" --clone; then
      echo "  no sync timer until ~/notes exists: run \`notes\`, then ./install.sh notes"
      return 0
    fi
  fi
  if [ "$(uname)" = Darwin ]; then
    # launchd needs absolute paths, so the agent is written, not linked
    plist="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
    tmp="${TMPDIR:-/tmp}/dotfiles-notes.$$"
    cat > "$tmp" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LAUNCHD_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$HOME/.local/bin/notes-sync</string><string>-q</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>StartInterval</key><integer>120</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/notes-sync.log</string>
</dict>
</plist>
PLIST
    if cmp -s "$tmp" "$plist"; then
      echo "  launchd agent up to date"
    else
      echo "  ~/Library/LaunchAgents/$LAUNCHD_LABEL.plist (sync every 2 minutes)"
      run mkdir -p "$HOME/Library/LaunchAgents"
      run cp "$tmp" "$plist"
      run launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
      run launchctl bootstrap "gui/$(id -u)" "$plist" || echo "  couldn't load it: launchctl bootstrap gui/$(id -u) $plist"
    fi
    rm -f "$tmp"
  elif have systemctl && systemctl --user show-environment >/dev/null 2>&1; then
    if [ -z "$DRY" ] && systemctl --user is-enabled -q notes-sync.timer 2>/dev/null; then
      return 0
    fi
    echo "  enabling notes-sync.timer (sync every 2 minutes)"
    run systemctl --user daemon-reload
    run systemctl --user enable -q --now notes-sync.timer || echo "  couldn't enable it"
  else
    echo "  no systemd user session: run notes-sync from cron or by hand"
  fi
}

# Ghostty reads the shared settings via an include, so ~/.config/ghostty/config stays this
# machine's own file (window position, utheme's block). The include goes first: included
# files load in order after the main file, so anything included later (a theme) wins.
setup_ghostty() {
  cfg="$HOME/.config/ghostty/config"
  grep -qs '^config-file *= *"\{0,1\}dotfiles.conf' "$cfg" && return 0
  echo "  including dotfiles.conf from ~/.config/ghostty/config"
  [ -n "$DRY" ] && return 0
  tmp="$cfg.dotfiles.$$"
  { echo 'config-file = dotfiles.conf'; [ -f "$cfg" ] && cat "$cfg"; } > "$tmp" && mv "$tmp" "$cfg"
}

# Karabiner-Elements rewrites karabiner.json when you change anything in its window and
# doesn't notice changes through a link, so the file is copied, and only when there's
# none yet. The rule files under assets/ are linked as usual.
setup_karabiner() {
  src="$DOTFILES/karabiner/karabiner.json"
  dest="$HOME/.config/karabiner/karabiner.json"
  if [ ! -f "$dest" ]; then
    echo "  copying karabiner.json to ~/.config/karabiner/"
    run mkdir -p "$(dirname "$dest")"
    run cp "$src" "$dest"
  elif ! cmp -s "$src" "$dest"; then
    echo "  ~/.config/karabiner/karabiner.json differs from the repo's, left alone. To keep yours:"
    echo "    cp ~/.config/karabiner/karabiner.json $DOTFILES/karabiner/"
  fi
}

peek_installed() {
  [ -d /Applications/Peek.app ] || [ -d "$HOME/Applications/Peek.app" ]
}

if [ "$1" = --check ]; then
  check_deps
  exit 0
fi

# Every package, in the order they're listed and installed:
#   name|where it works (any, macos, linux)|personal|label
PACKAGES='shell|any||aliases and functions for bash and zsh
bin|any||helper scripts: proj, ports, devtunnel, send, recentdl, claude-rc, ...
git|any||git settings, included from your own config
starship|any||prompt with machine name and git status
agents|any|personal|my instructions for Claude Code, Codex, opencode, pi
zsh|any||~/.zshrc
nvim|any||minimal plugin-free nvim config
readline|any||~/.inputrc for bash
zed|any||Zed settings, keys and tasks
direnv|any||direnv layout uv: activates the .venv in folders set up by uve
ghostty|macos||Ghostty terminal settings, included from your own config
karabiner|macos||Karabiner-Elements key remaps (Right Shift bracket layer, no Escape key)
notes|any||~/notes: Typst notes in your own repo (<you>/notes on GitHub), synced every 2 minutes
peek|macos|personal|Peek Markdown viewer app (private repo, builds from source)'

pkg_field() { # pkg_field NAME N
  echo "$PACKAGES" | awk -F'|' -v n="$1" -v i="$2" '$1 == n { print $i }'
}

this_os() { if [ "$(uname)" = Darwin ]; then echo macos; else echo linux; fi; }

# Why a package can't be installed here (empty if it can)
pkg_unsupported() {
  os=$(pkg_field "$1" 2)
  if [ -z "$os" ] || [ "$os" = any ] || [ "$os" = "$(this_os)" ]; then return 0; fi
  case $os in macos) echo "macOS only" ;; linux) echo "Linux only" ;; esac
}

is_owner() {
  case $DOTFILES_OWNER in 1) return 0 ;; 0) return 1 ;; esac
  [ -e "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/owner" ] && return 0
  # reads gh's local config, no network
  have gh && [ "$(gh config get -h github.com user 2>/dev/null)" = "$OWNER" ]
}

omarchy() { [ -n "$OMARCHY_PATH" ] || [ -d /usr/share/omarchy ]; }

# This machine's defaults. Without the picker (-y, or not on a terminal) only these are
# installed, so scripted installs only gain a personal package (agents) on the owner's machines.
default_packages() {
  d="shell bin git starship"
  if is_owner; then d="$d agents"; fi
  if [ "$(uname)" = Darwin ]; then d="$d zsh"; fi
  # Omarchy ships its own LazyVim setup and inputrc
  if ! omarchy; then d="$d nvim readline"; fi
  # Zed creates this folder on first launch
  if [ -d "$HOME/.config/zed" ]; then d="$d zed"; fi
  if have direnv; then d="$d direnv"; fi
  if [ -d /Applications/Ghostty.app ]; then d="$d ghostty"; fi
  if [ -d /Applications/Karabiner-Elements.app ]; then d="$d karabiner"; fi
  echo "$d"
}

# Ticked in the picker: the defaults, plus the owner's notes and (if missing) Peek
picker_defaults() {
  d=$(default_packages)
  if is_owner; then
    d="$d notes"
    if [ "$(uname)" = Darwin ] && ! peek_installed; then d="$d peek"; fi
  fi
  echo "$d"
}

# Numbered list of what works here; numbers toggle, enter installs. Sets PICKED.
pick() {
  avail=
  for p in $(echo "$PACKAGES" | cut -d'|' -f1); do
    [ -z "$(pkg_unsupported "$p")" ] && avail="$avail $p"
  done
  sel=" $* "
  while :; do
    echo
    i=0
    for p in $avail; do
      i=$((i + 1))
      case $sel in *" $p "*) m=x ;; *) m=" " ;; esac
      label=$(pkg_field "$p" 4)
      [ -n "$(pkg_field "$p" 3)" ] && label="$label (personal)"
      printf '  %2d [%s] %-9s %s\n' "$i" "$m" "$p" "$label"
    done
    printf 'toggle numbers, enter to install, q to quit: '
    read -r ans || exit 1
    case $ans in
      '') break ;;
      q|Q) exit 0 ;;
    esac
    for w in $ans; do
      i=0
      found=
      for p in $avail; do
        i=$((i + 1))
        [ "$i" = "$w" ] || continue
        found=1
        case $sel in
          *" $p "*) sel=$(echo "$sel" | sed "s/ $p / /") ;;
          *) sel="$sel$p " ;;
        esac
      done
      [ -n "$found" ] || echo "  no package $w"
    done
  done
  PICKED=
  for p in $avail; do
    case $sel in *" $p "*) PICKED="$PICKED $p" ;; esac
  done
}

if [ $# -eq 0 ]; then
  if [ -z "$YES" ] && [ -t 0 ] && [ -t 1 ]; then
    # shellcheck disable=SC2046
    pick $(picker_defaults)
    if [ -z "$PICKED" ]; then echo "nothing picked"; exit 0; fi
    echo
    # shellcheck disable=SC2086
    set -- $PICKED
  else
    # shellcheck disable=SC2046
    set -- $(default_packages)
  fi
fi

for pkg in "$@"; do
  why=$(pkg_unsupported "$pkg")
  if [ -n "$why" ]; then
    echo "$pkg"
    echo "  skipped: $why"
    continue
  fi
  if [ "$pkg" = peek ]; then
    install_peek
    continue
  fi
  if [ ! -d "$DOTFILES/$pkg" ]; then
    echo "no such package: $pkg" >&2
    exit 1
  fi
  echo "$pkg"
  [ "$pkg" = zed ] && merge_zed
  (cd "$DOTFILES/$pkg" && find . -mindepth 1 \( -type f -o -type l \) | sed 's#^\./##') |
  while IFS= read -r rel; do
    src="$DOTFILES/$pkg/$rel"
    dest="$HOME/$rel"

    # zed: the top-level snippets were merged above; only files under .config/ are linked
    case "$pkg/$rel" in
      zed/.config/*) ;;
      zed/*) continue ;;
    esac

    # karabiner.json is copied by setup_karabiner, not linked
    [ "$pkg/$rel" = karabiner/karabiner.json ] && continue

    # notes: the timer is a systemd unit on Linux, a generated launchd agent on macOS
    case "$pkg/$rel" in
      notes/.config/systemd/*) [ "$(uname)" = Darwin ] && continue ;;
    esac

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
  if [ "$pkg" = notes ]; then setup_notes; fi
  if [ "$pkg" = ghostty ]; then setup_ghostty; fi
  if [ "$pkg" = karabiner ]; then setup_karabiner; fi
done

# Remove links to files that are no longer in the repo (e.g. a package that was deleted)
for dir in "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share/notes" "$HOME/.local/share/localview" "$HOME/.claude" "$HOME/.codex" "$HOME/.pi"; do
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
if [ "$(uname)" = Darwin ] && is_owner && ! peek_installed; then
  echo
  echo "Optional: Peek, the Markdown viewer behind Zed's space p: ./install.sh peek"
fi
exit 0
