typeset -U path # don't add duplicate PATH entries in nested shells
export PATH="$HOME/.local/bin:$PATH"

# --- History ---
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE

# --- Tab completion ---
# Completes commands' own arguments: git branches, brew packages, `just` recipes from the
# justfile here, ... Homebrew's completions are on zsh's path already (it's
# /opt/homebrew/share/zsh/site-functions); the others are added if they exist.
for _d in /usr/local/share/zsh/site-functions /usr/share/zsh/site-functions; do
  [[ -d $_d && ${fpath[(Ie)$_d]} -eq 0 ]] && fpath=("$_d" $fpath)
done
unset _d
autoload -Uz compinit
# The full check (new completion files, insecure folders) takes ~20ms, so it runs once a day;
# other shells reuse the cached ~/.zcompdump
_dump=(~/.zcompdump(N.mh-24))
if (( $#_dump )); then compinit -C; else compinit; fi
unset _dump
zstyle ':completion:*' menu select                 # Tab again to pick from the list with arrows
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' # lower case matches upper case

# Up/Down search history for commands starting with what you've typed
autoload -U up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search

# Double-space types " && " (make<space><space>./run -> make && ./run).
# Ctrl-V then space for a literal second space.
space-or-and() {
  if [[ $LBUFFER == *[^\ ]\  && $LBUFFER != *'&& ' ]]; then
    LBUFFER="${LBUFFER% } && "
  else
    zle self-insert
  fi
}
zle -N space-or-and
bindkey ' ' space-or-and

unsetopt BEEP # stop beep

# Rebindings
alias c='clear'
alias n='nvim'
t() { tree -L "${1:-2}"; }

alias cc='cd ~/claude-scratch && claude'

# Aliases, functions and tool setup shared with bash. It loads this machine's
# private ~/.config/shell/local.sh and secrets.sh last, so they can override anything.
[ -f ~/.config/shell/shared.sh ] && source ~/.config/shell/shared.sh

# zsh-autosuggestions: shows a dim inline suggestion as you type,
# based on history / what completion would fill in. Accept with -> or End.
# (keep this last)
for f in /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
         /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
         /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
         /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh; do
  [ -f "$f" ] && source "$f" && break
done

md() {
  local width=80
  local cols=$(tput cols)
  local pad=$(( (cols - width) / 2 ))
  (( pad < 0 )) && pad=0
  glow -w "$width" "$@" | sed "s/^/$(printf '%*s' "$pad" '')/" | less -R
}
