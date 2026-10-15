typeset -U path # don't add duplicate PATH entries in nested shells
export PATH="$HOME/.local/bin:$PATH"

# --- History ---
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE

# Up/Down search history for commands starting with what you've typed
autoload -U up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search

unsetopt BEEP # stop beep

# Aliases, functions and tool setup shared with bash
[ -f ~/.config/shell/shared.sh ] && source ~/.config/shell/shared.sh

# Rebindings
alias c='clear'
alias n='nvim'
t() { tree -L "${1:-2}"; }

alias cc='cd ~/claude-scratch && claude'

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

# Move the most recent <count> items from ~/Downloads into the current dir
recentdl() {
  emulate -L zsh
  setopt local_options extended_glob

  local n="${1:-1}"

  if [[ -z "$n" || ! "$n" =~ '^[0-9]+$' || "$n" -le 0 ]]; then
    print -u2 "usage: recentdl <count>"
    return 1
  fi

  local dl="${HOME}/Downloads"
  local dest="${PWD}"

  if [[ ! -d "$dl" ]]; then
    print -u2 "recentdl: no Downloads dir at $dl"
    return 1
  fi

  # Most recently modified entries first (files and dirs), skip dotfiles
  local -a files
  files=("${dl}"/*(Nom[1,$n]))

  if (( ${#files[@]} == 0 )); then
    echo "recentdl: nothing found in $dl"
    return 0
  fi

  echo "About to move to: $dest"
  echo "----------------------------------------"
  local f
  for f in "${files[@]}"; do
    echo "  ${f:t}"
  done
  echo "----------------------------------------"

  read -q "REPLY?Proceed? [y/N] "
  echo
  if [[ "$REPLY" != "y" ]]; then
    echo "recentdl: aborted"
    return 1
  fi

  for f in "${files[@]}"; do
    mv -i -- "$f" "$dest"/
  done

  echo "recentdl: moved ${#files[@]} item(s) to $dest"
}

# Machine-specific settings and secrets (not in git)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# zsh-autosuggestions: shows a dim inline suggestion as you type,
# based on history / what completion would fill in. Accept with -> or End.
# (keep this last)
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
