# dotfiles

My shell, git, prompt and editor config, shared between macOS (zsh) and Linux (bash,
including [Omarchy](https://omarchy.org) and machines where I don't have admin rights).
Every helper works the same in bash and zsh. Fork it and make it yours.

## Install

```sh
git clone https://github.com/andples/dotfiles.git ~/dotfiles && ~/dotfiles/install.sh
```

`install.sh` needs nothing but `sh`. It symlinks each file into `$HOME` (like
`stow --no-folding`), moves anything in the way to `~/.dotfiles-backup/`, and is safe to re-run.

- `./install.sh -n` shows what it would do without changing anything
- `./install.sh git zsh` installs just those packages
- `./install.sh --check` only checks for missing tools

At the end it lists missing tools (fzf, zoxide, eza, starship, ...) with the install command
for your OS (brew, pacman, apt, dnf, zypper). Without admin rights it suggests
[mise](https://mise.jdx.dev), which installs into your home folder. It never installs anything
itself, and a missing tool never makes it fail.

## Packages

| Package | Goes to | Installed on |
|---|---|---|
| `shell` | `~/.config/shell/shared.sh`: aliases and functions for bash and zsh | everywhere |
| `bin` | `~/.local/bin/`: helper scripts like `recentdl` | everywhere |
| `git` | `~/.config/git/dotfiles.gitconfig`, included from your own `~/.config/git/config` | everywhere |
| `starship` | `~/.config/starship.toml`: prompt with machine name, folder, git branch and status | everywhere |
| `agents` | `~/.config/agents/AGENTS.md`, linked from Claude Code, Codex, opencode and pi | everywhere |
| `zsh` | `~/.zshrc` | macOS |
| `readline` | `~/.inputrc` | bash without Omarchy |

On Linux, `install.sh` adds one line to `~/.bashrc` that loads `shared.sh`, rather than
replacing `~/.bashrc`.

## Your own settings and secrets

Keep anything personal or machine-specific outside the repo. `shared.sh` loads these last,
if they exist, so they can override anything:

| What | Where |
|---|---|
| Machine-only aliases, functions, exports | `~/.config/shell/local.sh` |
| API keys and other secrets (`chmod 600`) | `~/.config/shell/secrets.sh` |
| SSH hosts and usernames | `~/.ssh/config` |
| Git name, email, credential helpers | `~/.config/git/config` |
| Secrets for one project | that project's `.envrc` (loaded by direnv) |

The prompt starts with a short machine name: `mac` on macOS, `oma` on Omarchy, otherwise
the hostname. Set `export MACHINE_NAME=...` in `local.sh` to change it.

## Agent instructions

Edit `agents/.config/agents/AGENTS.md`. Every agent's global instructions file links to it,
so one change applies to all of them.

## Using stow instead

`stow --no-folding shell bin git starship agents zsh` works too. Stow refuses to overwrite
real files, so move them out of the way first. `--no-folding` stops it from replacing a whole
directory like `~/.claude` with a single link. With stow, add the git include yourself:
`git config --file ~/.config/git/config include.path dotfiles.gitconfig`.

## License

[MIT](LICENSE)
