# Shared shell config, sourced by both zsh (Mac) and bash (Omarchy, uni).
# Everything is guarded, so missing tools are just skipped.

have() { command -v "$1" >/dev/null 2>&1; }

if [ -n "$ZSH_VERSION" ]; then _sh=zsh; else _sh=bash; fi

# Short machine name, shown at the start of the prompt.
# Override with `export MACHINE_NAME=...` in ~/.config/shell/local.sh.
if [ -z "$MACHINE_NAME" ]; then
  if [ "$(uname)" = Darwin ]; then
    MACHINE_NAME=mac
  elif [ -n "$OMARCHY_PATH" ] || [ -d /usr/share/omarchy ]; then
    MACHINE_NAME=oma
  else
    MACHINE_NAME=$(uname -n)
    MACHINE_NAME=${MACHINE_NAME%%.*}
  fi
fi
export MACHINE_NAME

# helper scripts from the bin package
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# OCaml: opam's environment (PATH to ocaml, dune, ocamllsp). Run `opam init --no-setup`
# so opam doesn't append this to the linked rc files itself.
[ -r "$HOME/.opam/opam-init/variables.sh" ] && . "$HOME/.opam/opam-init/variables.sh"

# nvm, if installed: its default Node goes on PATH now, and nvm itself loads the first time
# you run `nvm` (loading it in every shell took over half a second)
export NVM_DIR=${NVM_DIR:-$HOME/.nvm}
if [ -s "$NVM_DIR/nvm.sh" ]; then
  _nvm_want=
  [ -r "$NVM_DIR/alias/default" ] && read -r _nvm_want < "$NVM_DIR/alias/default"
  # the newest installed version matching the default alias (26, 26.5.0, v26...); for
  # anything else (node, lts/*, none) the newest installed
  _nvm_bin=$(ls "$NVM_DIR/versions/node" 2>/dev/null | sort -t. -k1.2,1n -k2,2n -k3,3n | awk -v w="${_nvm_want#v}" '
    { v = substr($0, 2) } w ~ /^[0-9]/ && v != w && index(v, w ".") != 1 { next } { last = $0 } END { print last }')
  [ -n "$_nvm_bin" ] && [ -d "$NVM_DIR/versions/node/$_nvm_bin/bin" ] &&
    export PATH="$NVM_DIR/versions/node/$_nvm_bin/bin:$PATH"
  unset _nvm_want _nvm_bin
  nvm() {
    unset -f nvm
    . "$NVM_DIR/nvm.sh"
    nvm "$@"
  }
fi

# --- Things Omarchy already sets up; only do them elsewhere ---
if [ -z "$OMARCHY_PATH" ]; then
  # mise: user-level tool installs (no admin needed), see install.sh
  have mise && eval "$(mise activate $_sh)"
  have zoxide && eval "$(zoxide init $_sh)" && eval "$(zoxide init $_sh --cmd cd)"
  # fzf: Ctrl-R history, Ctrl-T insert file path, Alt-C cd into dir (needs fzf >= 0.48)
  have fzf && fzf --$_sh >/dev/null 2>&1 && eval "$(fzf --$_sh)"
  if have starship; then
    eval "$(starship init $_sh)"
  elif [ "$_sh" = zsh ]; then
    PROMPT="%F{cyan}$MACHINE_NAME%f $PROMPT"
  else
    PS1="\[\e[36m\]$MACHINE_NAME\[\e[0m\] $PS1"
  fi

  alias ..='cd ..'
  alias ...='cd ../..'
  alias ....='cd ../../..'

  if have eza; then
    alias ls='eza -lh --group-directories-first --icons=auto'
    alias lsa='ls -a'
    alias lt='eza --tree --level=2 --long --icons --git'
  fi

  # Debian/Ubuntu name bat "batcat". ff's preview runs in a new shell, which doesn't see
  # aliases, so it gets the real name (checked first: once aliased, `have bat` is true)
  _bat=
  if have batcat; then _bat=batcat; alias bat='batcat'; elif have bat; then _bat=bat; fi

  # fuzzy find a file with preview / open it in nvim
  if [ -n "$_bat" ]; then
    alias ff="fzf --preview '$_bat --style=numbers --color=always {}'"
    alias eff='nvim "$(ff)"'
  fi
  unset _bat

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

# just: Tab completes the justfile's recipes, and its options only after `-`
# (zsh's version is in .zshrc)
if [ "$_sh" = bash ] && have just; then
  eval "$(just --completions bash)"
  _just_recipes() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    case $cur in
      -*) declare -F _clap_complete_just >/dev/null && _clap_complete_just "$@" ;;
      *) COMPREPLY=($(compgen -W "$(just --summary 2>/dev/null)" -- "$cur")) ;;
    esac
  }
  complete -o bashdefault -o nosort -F _just_recipes just
fi

if have direnv; then
  eval "$(direnv hook $_sh)"
  export DIRENV_LOG_FORMAT=
fi

# --- Aliases ---
alias gsend='git add -A && git commit -m wip && git push'
# look through a CSV: csv file.csv (/ search, & filter rows, q quit)
have csvlens && alias csv='csvlens'

# --- Functions ---

# fuzzy search recently opened nvim files (Esc does nothing)
nf() {
  local f
  f=$(nvim --headless -c 'lua io.write(table.concat(vim.v.oldfiles, "\n"))' -c q 2>/dev/null | fzf) && nvim "$f"
}

# open a folder in Zed (its CLI is `zed`, `zeditor` on Arch, and not installed by default on macOS)
zedo() {
  if have zed; then zed "${1:-.}"
  elif have zeditor; then zeditor "${1:-.}"
  elif [ "$(uname)" = Darwin ]; then open -a Zed "${1:-.}"
  else echo "zedo: Zed's CLI isn't installed" >&2; return 1
  fi
}

# fuzzy-pick a folder: most visited first, then every git repo; type ~/ or / to browse
# (Tab goes into a folder). Enter: cd into it. Ctrl-O: cd and open in Zed.
# `proj foo` starts with "foo" typed. See the `pick-dir` and `projects` scripts.
proj() {
  local out key d
  out=$(pick-dir --query="$*" --expect=ctrl-o) || return
  key=$(printf '%s\n' "$out" | head -n 1)
  d=$(printf '%s\n' "$out" | tail -n 1)
  builtin cd -- "$d" || return
  have zoxide && zoxide add "$d"
  [ "$key" = ctrl-o ] && zedo .
  return 0
}

# resume any Claude Code session from any folder: fuzzy-pick one (newest first, with the
# start of the conversation alongside), cd to the folder it ran in, and `claude --resume` it.
# `cresume poker` starts with "poker" typed; `cresume -c` only lists this folder's sessions.
# The list comes from the `claude-sessions` script.
cresume() {
  local here= pick cwd id tab
  tab=$(printf '\t')
  have fzf || { echo "cresume: needs fzf" >&2; return 1; }
  have claude || { echo "cresume: needs Claude Code (claude)" >&2; return 1; }
  case ${1-} in
    -c|--here) here=$PWD; shift ;;
    -h|--help) echo "usage: cresume [-c] [QUERY]   (-c: only sessions started in this folder)"; return 0 ;;
  esac
  if [ -n "$here" ]; then
    pick=$(claude-sessions --cwd "$here")
  else
    pick=$(claude-sessions)
  fi || return
  [ -n "$pick" ] || { echo "cresume: no sessions${here:+ for this folder}" >&2; return 1; }
  pick=$(printf '%s\n' "$pick" | fzf --delimiter="$tab" --with-nth=4.. --nth=2.. \
    --query="$*" --prompt='resume> ' --preview='claude-sessions --preview {1}' \
    --preview-window='down,55%,wrap') || return
  cwd=$(printf '%s\n' "$pick" | cut -f2)
  id=$(printf '%s\n' "$pick" | cut -f3)
  [ -d "$cwd" ] || { echo "cresume: $cwd no longer exists (session $id)" >&2; return 1; }
  builtin cd -- "$cwd" && claude --resume "$id"
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

# set up a uv project here: .venv with ipykernel (for Zed's REPL) + direnv.
# Run it before opening the folder in Zed so its Python tools find the venv at startup.
# Safe in an existing project: adds ipykernel and leaves an existing .envrc alone.
uve() {
  have uv || { echo "uve: needs uv" >&2; return 1; }
  [ -f pyproject.toml ] || uv init --bare --quiet || return 1
  uv add --dev --quiet ipykernel || return 1
  if [ ! -f .envrc ]; then
    echo 'layout uv' > .envrc
    have direnv && direnv allow
  fi
  echo "✅ .venv ready (with ipykernel)"
}

# copy stdin to the clipboard: echo hi | pb
pb() {
  if have pbcopy; then pbcopy
  elif [ -n "$WAYLAND_DISPLAY" ] && have wl-copy; then wl-copy
  elif have xclip; then xclip -selection clipboard
  elif have xsel; then xsel --clipboard --input
  else echo "pb: no clipboard tool found (install wl-clipboard or xclip)" >&2; return 1
  fi
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

# --- This machine only (never in the repo) ---
# local.sh: machine-specific aliases, functions, exports
# secrets.sh: API keys etc. (chmod 600)
[ -f ~/.config/shell/local.sh ] && . ~/.config/shell/local.sh
[ -f ~/.config/shell/secrets.sh ] && . ~/.config/shell/secrets.sh
