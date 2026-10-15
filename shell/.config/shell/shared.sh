# Shared shell config, sourced by both zsh (Mac) and bash (Omarchy, uni).
# Everything is guarded, so missing tools are just skipped.

have() { command -v "$1" >/dev/null 2>&1; }

if [ -n "$ZSH_VERSION" ]; then _sh=zsh; else _sh=bash; fi

# helper scripts from the bin package
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# --- Things Omarchy already sets up; only do them elsewhere ---
if [ -z "$OMARCHY_PATH" ]; then
  # mise: user-level tool installs (no admin needed), see install.sh
  have mise && eval "$(mise activate $_sh)"
  have zoxide && eval "$(zoxide init $_sh)" && eval "$(zoxide init $_sh --cmd cd)"
  # fzf: Ctrl-R history, Ctrl-T insert file path, Alt-C cd into dir (needs fzf >= 0.48)
  have fzf && fzf --$_sh >/dev/null 2>&1 && eval "$(fzf --$_sh)"
  have starship && eval "$(starship init $_sh)"

  alias ..='cd ..'
  alias ...='cd ../..'
  alias ....='cd ../../..'

  if have eza; then
    alias ls='eza -lh --group-directories-first --icons=auto'
    alias lsa='ls -a'
    alias lt='eza --tree --level=2 --long --icons --git'
  fi

  # Debian/Ubuntu name bat "batcat"
  have bat || { have batcat && alias bat='batcat'; }

  # fuzzy find a file with preview / open it in nvim
  { have bat || have batcat; } && alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
  { have bat || have batcat; } && alias eff='nvim "$(ff)"'

  alias g='git'
  alias gcm='git commit -m'
  alias gcam='git commit -a -m'

  compress() { tar -czf "${1%/}.tar.gz" "${1%/}"; }
  alias decompress='tar -xzf'

  if [ "$_sh" = bash ]; then
    shopt -s histappend
    HISTCONTROL=ignoreboth
    HISTSIZE=32768
    HISTFILESIZE=$HISTSIZE
  fi
fi

if have direnv; then
  eval "$(direnv hook $_sh)"
  export DIRENV_LOG_FORMAT=
fi

# --- Aliases ---
alias gsend='git add -A && git commit -m wip && git push'

# --- Functions ---

# fuzzy search recently opened nvim files (Esc does nothing)
nf() {
  local f
  f=$(nvim --headless -c 'lua io.write(table.concat(vim.v.oldfiles, "\n"))' -c q 2>/dev/null | fzf) && nvim "$f"
}

# activate the venv in the current directory
venv() {
  local d
  for d in .venv venv env; do
    if [ -f "$d/bin/activate" ]; then
      . "$d/bin/activate"
      echo "✅ Activated virtual environment from ./$d/"
      return 0
    fi
  done
  echo "❌ No virtual environment found (.venv, venv, env)"
  return 1
}

# set up direnv + uv for this directory
uve() {
  if [ -f .envrc ]; then
    echo "Skipping: .envrc already exists here." >&2
    return 1
  fi
  echo 'layout uv' > .envrc
  direnv allow
}

mkcd() { mkdir -p -- "$1" && builtin cd -- "$1"; }

# print PATH one entry per line
path() { echo "$PATH" | tr ':' '\n'; }

# what is listening on a port / kill it
port() { lsof -nP -iTCP:"$1" -sTCP:LISTEN; }
killport() {
  local pids
  pids=$(lsof -t -iTCP:"$1" -sTCP:LISTEN)
  if [ -z "$pids" ]; then
    echo "nothing listening on $1"
    return 1
  fi
  echo "$pids" | xargs kill && echo "killed: $(echo "$pids" | tr '\n' ' ')"
}

# serve the current directory over http
serve() { python3 -m http.server "${1:-8000}"; }

# unpack any archive
extract() {
  if [ ! -f "$1" ]; then
    echo "extract: no such file: $1" >&2
    return 1
  fi
  case "$1" in
    *.tar.gz|*.tgz)   tar -xzf "$1" ;;
    *.tar.bz2|*.tbz2) tar -xjf "$1" ;;
    *.tar.xz|*.txz)   tar -xJf "$1" ;;
    *.tar.zst)        tar --zstd -xf "$1" ;;
    *.tar)            tar -xf "$1" ;;
    *.zip)            unzip "$1" ;;
    *.gz)             gunzip -k "$1" ;;
    *.bz2)            bunzip2 -k "$1" ;;
    *.7z)             7z x "$1" ;;
    *) echo "extract: don't know how to extract $1" >&2; return 1 ;;
  esac
}

# git checkout; with no args pick a branch (most recent first) with fzf
gco() {
  if [ $# -gt 0 ]; then
    git checkout "$@"
    return
  fi
  local b
  b=$(git for-each-ref --sort=-committerdate --format='%(refname)' refs/heads refs/remotes \
    | grep -v '/HEAD$' | sed -e 's#^refs/heads/##' -e 's#^refs/remotes/[^/]*/##' \
    | awk '!seen[$0]++' | fzf --prompt='branch> ') || return
  git checkout "$b"
}

# quick usage examples: cheat tar
cheat() { curl -s "cheat.sh/$1"; }
