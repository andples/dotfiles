# dotfiles

My shell, git, prompt and editor config, shared between macOS (zsh) and Linux (bash,
including [Omarchy](https://omarchy.org) and machines where I don't have admin rights).
Every helper works the same in bash and zsh. Fork it and make it yours.

## Install

```sh
git clone https://github.com/andples/dotfiles.git ~/dotfiles && ~/dotfiles/install.sh
```

`install.sh` needs nothing but `sh`. It lists the packages with this machine's defaults
ticked (type numbers to toggle, enter to install), symlinks each file into `$HOME` (like
`stow --no-folding`), moves anything in the way to `~/.dotfiles-backup/`, and is safe to re-run.

- `./install.sh -y` installs the defaults without asking (so does running it without a terminal)
- `./install.sh -n` shows what it would do without changing anything
- `./install.sh git zsh` installs just those packages
- `./install.sh --check` only checks for missing tools
- `./install.sh peek` (macOS) downloads, builds and installs Peek, the Markdown viewer below

Packages marked personal below are mine (private repos, my agent instructions) and are only
ticked on my machines: gh logged in as me, `DOTFILES_OWNER=1`, or a `~/.config/dotfiles/owner`
file. `DOTFILES_OWNER=0 ./install.sh -n` shows what anyone else gets. A package that can't
work on this OS is left out of the list, and skipped if you name it.

At the end it lists missing tools (fzf, zoxide, eza, starship, ...) with the install command
for your OS (brew, pacman, apt, dnf, zypper). Without admin rights it suggests
[mise](https://mise.jdx.dev), which installs into your home folder. It never installs anything
itself, and a missing tool never makes it fail.

## Packages

| Package | Goes to | Installed on |
|---|---|---|
| `shell` | `~/.config/shell/shared.sh`: aliases and functions for bash and zsh | everywhere |
| `bin` | `~/.local/bin/`: helper scripts like `recentdl` and `send` | everywhere |
| `git` | `~/.config/git/dotfiles.gitconfig`, included from your own `~/.config/git/config` | everywhere |
| `starship` | `~/.config/starship.toml`: prompt with machine name, folder, git branch and status | everywhere |
| `agents` | `~/.config/agents/AGENTS.md`, linked from Claude Code, Codex, opencode and pi | personal |
| `zsh` | `~/.zshrc` | macOS |
| `nvim` | `~/.config/nvim/init.lua`: minimal, no plugins, for quick edits | not Omarchy (it has LazyVim) |
| `zed` | snippets merged into `~/.config/zed/settings.json` (see below) | wherever Zed has been opened |
| `readline` | `~/.inputrc` | bash without Omarchy |
| `direnv` | `~/.config/direnv/direnvrc`: `layout uv` for the `.envrc` that `uve` writes | where direnv is installed |
| `notes` | `notes` and `notes-sync` in `~/.local/bin`, Typst templates, a 2-minute sync timer (see [Notes](#notes)) | when picked |
| `peek` | builds the Peek app (see [Peek](#peek)) | personal, macOS, when picked |

On Linux, `install.sh` adds one line to `~/.bashrc` that loads `shared.sh`, rather than
replacing `~/.bashrc`.

## Zed

Zed can't include other files and rewrites its own `settings.json`, so that file isn't
linked. Instead each `zed/<topic>.json` snippet (e.g. `ocaml.json`) is merged into it:
keys from the snippets win and everything else you've set is kept. The old file is backed
up first, since comments in it don't survive the merge. Re-run `./install.sh zed` after
editing a snippet. Removing a key from a snippet doesn't remove it from `settings.json`.
Merging needs `python3`; without it the step is skipped. `keymap.json` and `tasks.json`
(under `zed/.config/zed/`) are linked as usual.

Set up for Python (ty + ruff), OCaml, Rust (clippy), C/C++ (clangd), LaTeX, Typst and
Markdown. Language servers are downloaded by Zed itself; the toolchains are yours to install.

| Key (vim normal mode) | Does |
|---|---|
| `space p` | Markdown: pop it up formatted in [Peek](#peek) (`space P`: Zed's preview beside the file). LaTeX: open the PDF at the cursor. Typst: live preview beside Zed, click to jump (`space P`: the PDF) |
| `space r` / `space R` | re-run last task / pick a task (run file, tests, builds…) |
| `space t` | run the test or `main` at the cursor |
| `space o` / `space O` / `space z` | recent projects / open any folder (Zed's fuzzy picker, not the macOS dialog) / folder picker (same as `proj`: frequent folders, repos, or type a path) |
| `space g g` | git panel (stage, commit, push); `space g` + `s` stage hunk, `r` undo hunk, `b` branch, `l` blame, `h` file history |
| `space f` `space /` `space e` `space j` | files, project search, file tree, terminal |
| `space d` `space a` `space c` `space F` | diagnostics, code actions, rename, format |

Typst and LaTeX prose is rewrapped to 80 columns on save (tinymist; `tex-fmt` for LaTeX), so
long lines never break vim motions; `gq` rewraps by hand in between.

LaTeX builds with latexmk on every save and the PDF follows the cursor. PDFs open through
`pdfview` (in `bin`): Skim on macOS, Zathura on Linux; both reload on change. For the jump
back from the PDF (Cmd-Shift-click in Skim), set Skim → Settings → Sync → Preset: Custom,
Command: `/Applications/Zed.app/Contents/MacOS/cli`, Arguments: `"%file":%line`.
Typst writes its PDF on save. `space p` opens tinymist's live preview (what VS Code shows in
its side pane) through `typview`: it updates as you type, and clicking in it moves the
cursor. On macOS it's LocalView, a tiny borderless viewer (built from
`bin/.local/share/localview/LocalView.swift` on first use, no Dock icon), on the right half of
Zed's window. A small menu bar icon shows it's running (its menu closes or reloads it). It hides while Zed shows a non-Typst
file and quits a minute later, or when Zed quits; `space p` again closes it, and Zed gets
its full width back. Placing Zed needs Zed, and following it needs LocalView, in System Settings → Privacy →
Accessibility. On Linux it's a Chromium app window, or the default browser.

### Peek

`peek file.md` (in `bin`) pops Markdown up formatted in Peek, a small macOS viewer app built
separately (private repo; `./install.sh peek` clones it to `~/.local/src/peek` and installs it).
It opens `.md` files by default and has vim keys: `esc` closes, `space p` full window,
`i` edits in Zed, `space ?` lists the rest. Without Peek, `peek` opens the file in the
system's default app, so nothing here needs it.
`space ?` in Zed shows the cheat sheet of this config's keys in it.

In the shell, `proj` fuzzy-picks a folder: the ones you visit most (zoxide) first, then every
git repo under `$PROJECT_DIRS` (default `~/Documents ~/dotfiles ~/code ~/src ~/projects`).
Type a path (`~/`, `/`) to browse instead, Tab to go into a folder. Enter cd's there,
Ctrl-O also opens it in Zed. `space z` in Zed is the same picker.

`zed-playground/` (a submodule: `git submodule update --init`) has a small project in each
language and a checklist for trying all of the above. Open it in Zed with `space O`.

## Notes

Notes in a git repo at `~/notes`, written in [Typst](https://typst.app) (good for maths) and
read as PDFs. `notes` opens the folder in Zed, `notes NAME` opens (or starts)
`~/notes/NAME.typ`, `notes -p NAME` opens its PDF. Zed rebuilds the PDF on every save, and
PDFs aren't committed. Markdown still works: `notes NAME.md`, read in Peek. The first run
clones your notes repo: `<your GitHub user>/notes` (from `gh`), which it offers to make,
private, if you don't have one. Set `NOTES_REPO` (owner/repo or a git URL) in `local.sh` to
use another. The sync timer starts once `~/notes` exists.

Every note imports `~/notes/template.typ`, a copy of one of the templates in
`notes/.local/share/notes/templates/`: `classic` (the default, LaTeX look) or `math` (accent
colour, tinted boxes for definitions and theorems). `notes template --preview` renders a
sample note in both, `notes template NAME` switches. They share the same functions (`#definition`,
`#theorem`, `#lemma`, `#proof`, `#example`, `#remark`), so switching never means editing notes.

`notes pdfs` (once per notes repo) adds a GitHub Action that builds every note to PDF daily
and publishes them on the repo's `latest` release, to read from anywhere
(`github.com/<you>/notes/releases/latest`, or the GitHub app). It skips days with no new
commits, so it uses well under the free Actions minutes. Pushing it over https needs
`gh auth refresh -h github.com -s workflow` first; `notes pdfs` says so if it's missing.

`notes-sync` commits whatever changed, rebases onto the remote and pushes; installing the
package runs it every 2 minutes (a systemd user timer on Linux, a launchd agent on macOS) and
`notes` runs it when it opens. Offline it waits for next time. On a conflict it stops with
the repo as it is and sends one notification: fix the file, `git add` it,
`git rebase --continue`. It never forces anything. Logs: `journalctl --user -u notes-sync`,
or `~/Library/Logs/notes-sync.log`.

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

`send` copies files to another machine and lets you fuzzy-pick both the local files and the
remote folder. Give the machine a nickname in `~/.ssh/config` and set
`export SEND_HOST=<nickname>` in `local.sh`. See `send --help`.

`claude-rc` keeps Claude Remote Control running in a tmux session called `rc`: servers
(`claude-rc add NAME DIR --server`, which you start sessions on from the app) and single
conversations (`claude-rc add NAME DIR`, or `--resume ID` to continue one). After a reauth,
`claude-rc restart --login` restarts whatever exited, resuming conversations where they
were; `claude-rc up` does the same after a reboot. Sessions inside a server end with it, so
keep anything long-lived as its own conversation. `claude-rc ls --json` lists everything for
scripts and dashboards. The list lives in `~/.config/claude-rc/`, outside the repo. See
`claude-rc --help`.

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
