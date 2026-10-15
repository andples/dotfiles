# dotfiles

## Install anywhere

```sh
git clone <this repo> ~/dotfiles && ~/dotfiles/install.sh
```

`install.sh` needs nothing but `sh`. It symlinks each file into `$HOME` (like `stow --no-folding`),
moves anything in the way to `~/.dotfiles-backup/`, adds the shared config to `~/.bashrc` on
Linux, and is safe to re-run. `./install.sh -n` shows what it would do; `./install.sh git zsh`
installs just those packages.

At the end it lists any missing tools (fzf, zoxide, eza, ...) with the install command for
this OS (brew, pacman, apt, dnf, zypper). Without admin rights (e.g. uni) it suggests
[mise](https://mise.jdx.dev), which installs into your home folder. It never installs anything
itself, and a missing tool never makes it fail. Run just the check with `./install.sh --check`.

## Packages

| Package | Goes to | Use on |
|---|---|---|
| `zsh` | `~/.zshrc` | Mac |
| `shell` | `~/.config/shell/shared.sh` | everywhere |
| `bin` | `~/.local/bin/` (helper scripts like `recentdl`) | everywhere |
| `git` | `~/.config/git/config` | everywhere |
| `starship` | `~/.config/starship.toml` (prompt: folder, git branch, status) | everywhere |
| `nvim` | `~/.config/nvim` | everywhere |
| `agents` | `~/.config/agents/AGENTS.md`, linked from Claude, Codex, opencode, pi | everywhere |
| `readline` | `~/.inputrc` | bash without Omarchy (uni) |

Using stow instead: `stow --no-folding zsh shell git nvim agents` (stow refuses to overwrite real files, so move them out of the way first).

`--no-folding` stops stow from replacing a whole directory like `~/.claude` with one symlink.

Agent instructions: edit `agents/.config/agents/AGENTS.md`. Every tool's file links to it.

Bash: add this to the end of `~/.bashrc`:

```sh
[ -f ~/.config/shell/shared.sh ] && . ~/.config/shell/shared.sh
```

No stow (uni): `mkdir -p ~/.config/shell && ln -s ~/dotfiles/shell/.config/shell/shared.sh ~/.config/shell/`

Secrets and machine-specific settings go in `~/.zshrc.local` / `~/.bashrc.local` (gitignored).
