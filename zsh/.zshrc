eval "$(zoxide init zsh)"
eval "$(zoxide init zsh --cmd cd)" # make cd => zoxide

# fuzzy search recent opened nvim files 
alias nf='nvim $(nvim --headless -c "lua io.write(table.concat(vim.v.oldfiles, \"\n\"))" -c "q" 2>/dev/null | fzf)'

# Rebindings
alias c='clear'
alias n='nvim'

unsetopt BEEP # stop beep

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

venv() {
  if [[ -f ./env/bin/activate ]]; then
# source ./env/bin/activate  # commented out by conda initialize
    echo "✅ Activated virtual environment from ./env/"
  else
    echo "❌ No virtual environment found at ./env/"
  fi
}

