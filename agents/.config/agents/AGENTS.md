# Git commit conventions

- Never include a `Claude-Session:` link (or any session URL) in commit messages.
- Only include `Co-Authored-By: Claude ...` attribution for large-scale changes (e.g. substantial features, multi-file refactors) — not for small or routine commits (typo fixes, small tweaks, one-liners).

# tmux safety

- Never run bare `tmux kill-server`, `pkill tmux`, or `killall tmux` — the user's default tmux server hosts their long-running `claude remote-control` sessions, and killing it takes down every session at once (this happened on 2026-10-12).
- When you need tmux for testing (e.g. driving a TUI), always use a private socket: `tmux -L <name> new -d ...`, `tmux -L <name> send-keys ...`, `tmux -L <name> kill-server`. Never touch sessions on the default socket you didn't create.
