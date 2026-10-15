# dotfiles

Stow packages (run from this directory):

| Package | Goes to | Use on |
|---|---|---|
| `zsh` | `~/.zshrc` | Mac |
| `shell` | `~/.config/shell/shared.sh` | everywhere |
| `git` | `~/.config/git/config` | everywhere |
| `nvim` | `~/.config/nvim` | everywhere |
| `readline` | `~/.inputrc` | bash without Omarchy (uni) |

Mac: `stow zsh shell git nvim` (back up your existing `~/.zshrc` first).

Bash: add this to the end of `~/.bashrc`:

```sh
[ -f ~/.config/shell/shared.sh ] && . ~/.config/shell/shared.sh
```

No stow (uni): `mkdir -p ~/.config/shell && ln -s ~/dotfiles/shell/.config/shell/shared.sh ~/.config/shell/`

Secrets and machine-specific settings go in `~/.zshrc.local` / `~/.bashrc.local` (gitignored).
