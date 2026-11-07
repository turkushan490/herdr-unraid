FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TERM=xterm-256color \
    TZ=Etc/UTC \
    PUID=99 \
    PGID=100 \
    ENABLE_WEBUI=true \
    ENABLE_TTYD=true \
    ENABLE_SUDO=true \
    AUTO_UPDATE=false \
    WEBUI_PORT=7317 \
    TTYD_PORT=7681

# Base tools. ttyd comes from Ubuntu universe; Node 22 (NodeSource) is for the
# agents themselves (claude code, codex, ... via npm). Ovis runs on Bun.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-server curl ca-certificates git sudo supervisor tini ttyd \
      unzip xz-utils build-essential tzdata locales less nano vim-tiny \
      tmux procps iproute2 jq ripgrep python3 \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* \
 # Ubuntu images ship user "ubuntu" (1000) - drop it so PUID 1000 is free
 && (userdel -r ubuntu 2>/dev/null || true) \
 # pam_loginuid can't write loginuid inside Docker -> every SSH session would
 # fail with "pam_open_session(): Cannot make/remove an entry"; also drop MOTD
 && sed -i -E 's/^session\s+required\s+pam_loginuid.so/session optional pam_loginuid.so/; s/^(session\s+optional\s+pam_motd.so.*)/# \1/' /etc/pam.d/sshd \
 && mkdir -p /run/sshd /config /var/log/herdr

COPY rootfs/ /
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh /entrypoint.sh

EXPOSE 22 7317 7681
VOLUME ["/home/herdr", "/config"]

# First start downloads herdr, herdr-core, Bun and Ovis -> give it time.
HEALTHCHECK --interval=30s --timeout=10s --start-period=10m --retries=3 \
  CMD /scripts/healthcheck.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
