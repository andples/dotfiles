# dotfiles

Personal config shared between a Mac (zsh), an Omarchy Linux machine (bash) and a uni Linux
machine (bash, no sudo). Each top-level folder is a package that `install.sh` symlinks into
`$HOME` (stow layout). See README.md for the package list.

## Helper commands must work in both bash and zsh

Every helper command (function, alias or script) must be available and behave the same in
bash and zsh, on both macOS and Linux. Never add a helper to only one shell.

- **Short helpers** (a few lines) go in `shell/.config/shell/shared.sh`, which both shells
  source. Use syntax both shells accept: no zsh glob qualifiers, `print`, `read -q`,
  `emulate`, or `${var:t}`; no bash-only `[[ =~ ]]`, `mapfile` or `shopt` outside a
  `$_sh = bash` check. Remember zsh doesn't word-split unquoted variables.
- **Longer helpers** become a standalone script in `bin/.local/bin/` (see `recentdl`),
  so they work from any shell. Use `#!/usr/bin/env bash` and keep it bash 3.2 compatible
  (macOS ships 3.2): no `mapfile`, `${var,,}`, associative arrays or `&>>`.
- **macOS vs Linux tools differ** (BSD vs GNU): avoid `sed -i`, `date -d`, `stat -c`,
  `readlink -f`, `find -printf`, `grep -P`. Prefer flags both support.
- Guard optional tools with `have <tool> && ...` so nothing errors on a bare machine.
- Don't redefine names Omarchy already uses (`c`, `n`, `t`, `cd`, `ff`, `g`, ...).
  The Mac-only `c`/`n`/`t` aliases in `zsh/.zshrc` are the one deliberate exception.

## Testing a change

- Run the helper in both `bash` and `zsh` (`bash -n` / `zsh -n` for syntax at minimum).
- Test `install.sh` against a scratch `HOME` (e.g. `HOME=/tmp/dotfiles-test ./install.sh`),
  never against the real home directory without asking.

## Other rules

- No secrets in this repo. They go in `~/.zshrc.local` / `~/.bashrc.local` (gitignored).
- `install.sh` must stay POSIX `sh` with no dependencies, and safe to re-run.
- New packages: add them to the README table and, if they belong on every machine, to the
  default list in `install.sh`.
