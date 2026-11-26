#!/usr/bin/env bash
# End-to-end test of `./install.sh claude-rc` on a systemd machine (Docker), with a fake claude:
# install from a fresh clone, a crashed server, a crash right after which the folder is still
# "already served", a killed conversation, and a reboot.
#   tests/claude-rc/run.sh          build, run, clean up
#   KEEP=1 tests/claude-rc/run.sh   leave the container running to poke at
#
# Never run it with --privileged: systemd in the container then hangs up the host's console,
# which logs out a desktop on tty1. Unprivileged Docker mounts the cgroup read-only, so
# systemd can't boot yet: this needs a rootless runner (podman) or a VM to work.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
name=claude-rc-test
img=claude-rc-test
fails=0

docker build -q -t "$img" "$here" >/dev/null || exit 1
docker rm -f "$name" >/dev/null 2>&1
# Not --privileged: that would hand the container the host's devices, and systemd in it
# would then hang up the host's console (logging out a desktop on tty1). Its own cgroup
# namespace and tmpfs /run are all systemd needs here.
docker run -d --name "$name" --cgroupns=private --tmpfs /run --tmpfs /run/lock \
  --tmpfs /tmp "$img" >/dev/null || exit 1
[ -n "${KEEP:-}" ] || trap 'docker rm -f "$name" >/dev/null' EXIT

as_u() { docker exec -u u -w /home/u -e XDG_RUNTIME_DIR=/run/user/1000 \
  -e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "$name" bash -lc "$1"; }
ok() { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }
# wait_for SECONDS DESCRIPTION COMMAND
wait_for() {
  local i=0
  while [ $i -lt "$1" ]; do as_u "$3" >/dev/null 2>&1 && { ok "$2 (${i}s)"; return 0; }; sleep 1; i=$((i + 1)); done
  bad "$2 (not within $1s)"; as_u 'claude-rc ls; claude-rc log -n 15' 2>&1 | sed 's/^/      /'
  return 1
}
running() { echo "~/.local/bin/claude-rc ls | grep -E '^$1 +(running|connected)'"; }
pid_of() { echo "pgrep -u u -f 'bash /usr/local/bin/claude $1' | head -1"; }
# what the user's own clone and shell would look like
wait_for 30 "user systemd is up" 'systemctl --user is-system-running | grep -qE "running|degraded"'
docker cp "$repo" "$name:/home/u/dotfiles" && docker exec "$name" chown -R u:u /home/u/dotfiles
as_u 'mkdir -p proj && echo "export PATH=\$HOME/.local/bin:\$PATH" >> .profile'

echo "install"
as_u 'cd dotfiles && ./install.sh claude-rc' | sed 's/^/    /'
as_u 'systemctl --user is-active -q claude-rc.timer' && ok "timer active" || bad "timer not active"
as_u 'claude-rc add srv ~/proj --server >/dev/null; claude-rc add conv ~/proj >/dev/null'
wait_for 10 "server up" "$(running srv)"
wait_for 10 "conversation up" "$(running conv)"
as_u 'claude-rc ls' | grep -q 'claude-rc install' && bad "ls still says not installed" || ok "ls knows it's installed"

echo "server crash (kill -9), folder still 'already served' for 30s"
as_u "kill -9 \$($(pid_of remote-control))"
wait_for 100 "server back after retrying" "$(running srv)"
as_u 'claude-rc log' | grep -q 'already served\|didn.t stay up' && ok "first retry hit 'already served'" ||
  echo "  note: no 'already served' retry seen (restart came after 30s)"

echo "conversation crash"
id=$(as_u "claude-rc ls --json" | python3 -c 'import json,sys; print([r["id"] for r in json.load(sys.stdin) if r["name"]=="conv"][0])')
as_u "kill -9 \$($(pid_of --session-id))"
wait_for 90 "conversation resumed on the same id" "claude-rc ls | grep -E '^conv +connected +$id'"

echo "logged out: background runs wait, nothing is restarted"
as_u 'touch ~/.fake-claude/logged-out; kill -9 $('"$(pid_of remote-control)"')'
sleep 70
as_u "$(running srv)" >/dev/null && bad "restarted while logged out" || ok "left alone while logged out"
as_u 'claude-rc log' | grep -q 'not logged in' && ok "log says to log in" || bad "log doesn't say why"
as_u 'rm ~/.fake-claude/logged-out'
wait_for 90 "back once logged in" "$(running srv)"

echo "reboot"
docker restart "$name" >/dev/null
wait_for 60 "user systemd is up again" 'systemctl --user is-system-running | grep -qE "running|degraded"'
wait_for 90 "server back after reboot" "$(running srv)"
wait_for 60 "conversation back after reboot" "claude-rc ls | grep -E '^conv +connected +$id'"

echo "uninstall"
as_u 'claude-rc uninstall' >/dev/null
as_u 'systemctl --user is-enabled -q claude-rc.timer' && bad "timer still enabled" || ok "timer gone"

echo
if [ $fails -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
