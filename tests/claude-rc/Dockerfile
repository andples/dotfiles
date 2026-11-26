# A machine with systemd as PID 1, for testing claude-rc install, crash recovery and reboots.
# Claude Code is replaced by fake-claude (no login or network needed).
FROM debian:trixie-slim
RUN apt-get -o Acquire::http::Dl-Limit=3000 update && \
    apt-get -o Acquire::http::Dl-Limit=3000 install -y --no-install-recommends \
      systemd systemd-sysv dbus dbus-user-session tmux python3 procps && \
    rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 1000 -s /bin/bash u && loginctl enable-linger u 2>/dev/null; \
    mkdir -p /var/lib/systemd/linger && touch /var/lib/systemd/linger/u
# Never touch a console: not the container's, and above all not the host's
RUN systemctl mask getty.target console-getty.service getty@tty1.service \
      serial-getty@.service systemd-vconsole-setup.service \
      systemd-firstboot.service systemd-ask-password-console.path >/dev/null 2>&1; true
COPY --chmod=755 fake-claude /usr/local/bin/claude
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
