#!/bin/bash
# herdr-unraid entrypoint (runs as root, then hands over to supervisord)
set -euo pipefail

log() { echo "[entrypoint] $*"; }

bool() { case "${1,,}" in 1|true|yes|on) echo true ;; *) echo false ;; esac; }
export ENABLE_WEBUI="$(bool "${ENABLE_WEBUI:-true}")"
export ENABLE_TTYD="$(bool "${ENABLE_TTYD:-true}")"
export ENABLE_SUDO="$(bool "${ENABLE_SUDO:-true}")"
export AUTO_UPDATE="$(bool "${AUTO_UPDATE:-false}")"

PUID="${PUID:-99}"
PGID="${PGID:-100}"
HOME_DIR=/home/herdr

# --- timezone ---------------------------------------------------------------
if [ -n "${TZ:-}" ] && [ -e "/usr/share/zoneinfo/$TZ" ]; then
  ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
fi

# --- user herdr with Unraid-friendly ids (default 99:100 = nobody:users) ----
GROUP_NAME="$(getent group "$PGID" | cut -d: -f1 || true)"
if [ -z "$GROUP_NAME" ]; then
  groupadd -g "$PGID" herdr
  GROUP_NAME=herdr
fi
if id herdr >/dev/null 2>&1; then
  [ "$(id -u herdr)" = "$PUID" ] || usermod -o -u "$PUID" herdr
  usermod -g "$GROUP_NAME" herdr
else
  # -o: UID 99 may already exist as another name in some bases
  useradd -o -u "$PUID" -g "$GROUP_NAME" -d "$HOME_DIR" -s /bin/bash -M herdr
fi
# '*' = no password, but not "locked" (locked accounts can't use SSH keys)
usermod -p '*' herdr

if [ "$ENABLE_SUDO" = true ]; then
  echo 'herdr ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/herdr
  chmod 440 /etc/sudoers.d/herdr
else
  rm -f /etc/sudoers.d/herdr
fi

# --- home volume ---------------------------------------------------------------
mkdir -p "$HOME_DIR" "$HOME_DIR/.ssh" "$HOME_DIR/projects" /config
if [ "$(stat -c %u:%g "$HOME_DIR")" != "$PUID:$PGID" ]; then
  log "fixing ownership of $HOME_DIR (first start or PUID/PGID changed)"
  chown -R "$PUID:$PGID" "$HOME_DIR"
fi
# skeleton dotfiles on first start
for f in .bashrc .profile; do
  [ -e "$HOME_DIR/$f" ] || install -o "$PUID" -g "$PGID" -m 644 "/etc/skel/$f" "$HOME_DIR/$f"
done

# authorized_keys: file in the volume + optional AUTHORIZED_KEYS env (one per line)
AK="$HOME_DIR/.ssh/authorized_keys"
touch "$AK"
if [ -n "${AUTHORIZED_KEYS:-}" ]; then
  while IFS= read -r key; do
    key="$(printf '%s' "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$key" ] && continue
    grep -qxF "$key" "$AK" || echo "$key" >> "$AK"
  done <<< "$(echo -e "${AUTHORIZED_KEYS//;/\\n}")"
fi
chown "$PUID:$PGID" "$HOME_DIR" "$HOME_DIR/.ssh" "$AK"
chmod 755 "$HOME_DIR"
chmod 700 "$HOME_DIR/.ssh"
chmod 600 "$AK"
if [ ! -s "$AK" ]; then
  log "WARNING: no SSH keys in $AK - SSH login will be refused until you add one"
fi

# --- persistent SSH host keys ------------------------------------------------
mkdir -p /config/ssh_host_keys
chmod 700 /config/ssh_host_keys
[ -f /config/ssh_host_keys/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -N '' -f /config/ssh_host_keys/ssh_host_ed25519_key
[ -f /config/ssh_host_keys/ssh_host_rsa_key ] || ssh-keygen -q -t rsa -b 4096 -N '' -f /config/ssh_host_keys/ssh_host_rsa_key
chmod 600 /config/ssh_host_keys/*_key

# --- web UI token (never printed) ---------------------------------------------
if [ "$ENABLE_WEBUI" = true ]; then
  if [ -n "${OVIS_TOKEN:-}" ]; then
    printf '%s' "$OVIS_TOKEN" > /config/ovis_token
  elif [ ! -s /config/ovis_token ]; then
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > /config/ovis_token
    log "generated a web UI token -> /config/ovis_token (appdata/herdr/config/ovis_token)"
  fi
  chown "$PUID:$PGID" /config/ovis_token
  chmod 600 /config/ovis_token
fi

# --- PATH for SSH sessions and login shells ---------------------------------
USER_PATH="$HOME_DIR/.local/bin:$HOME_DIR/.bun/bin:$HOME_DIR/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
echo "PATH=\"$USER_PATH\"" > /etc/environment
cat > /etc/profile.d/herdr.sh <<EOF
export PATH="$USER_PATH"
export NPM_CONFIG_PREFIX="$HOME_DIR/.npm-global"
EOF

# --- install / update herdr, herdr-core, Bun, Ovis (as user herdr) ----------
chown -R "$PUID:$PGID" /var/log/herdr
su herdr -s /bin/bash -c /scripts/install-herdr.sh

log "starting services (webui=$ENABLE_WEBUI ttyd=$ENABLE_TTYD sudo=$ENABLE_SUDO)"
exec /usr/bin/supervisord -c /etc/supervisor/herdr.conf
