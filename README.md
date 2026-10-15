# dotfiles

Stow packages (run from this directory):

| Package | Goes to | Use on |
|---|---|---|
| `zsh` | `~/.zshrc` | Mac |
| `shell` | `~/.config/shell/shared.sh` | everywhere |
| `git` | `~/.config/git/config` | everywhere |
| `nvim` | `~/.config/nvim` | everywhere |
| `agents` | `~/.config/agents/AGENTS.md`, linked from Claude, Codex, opencode, pi | everywhere |
| `readline` | `~/.inputrc` | bash without Omarchy (uni) |

Mac: `stow --no-folding zsh shell git nvim agents` (back up your existing `~/.zshrc` and agent files first; stow refuses to overwrite real files).

`--no-folding` stops stow from replacing a whole directory like `~/.claude` with one symlink.

Agent instructions: edit `agents/.config/agents/AGENTS.md`. Every tool's file links to it.

Bash: add this to the end of `~/.bashrc`:

```sh
[ -f ~/.config/shell/shared.sh ] && . ~/.config/shell/shared.sh
```

No stow (uni): `mkdir -p ~/.config/shell && ln -s ~/dotfiles/shell/.config/shell/shared.sh ~/.config/shell/`

Secrets and machine-specific settings go in `~/.zshrc.local` / `~/.bashrc.local` (gitignored).
