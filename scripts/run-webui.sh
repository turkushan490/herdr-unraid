#!/bin/bash
# Ovis web UI (supervisord program "webui")
. /scripts/env.sh
if [ ! -f "$OVIS_DIR/package.json" ] || ! command -v bun >/dev/null; then
  echo "[webui] Ovis not installed (first-start download failed?) - retrying in 60s"
  sleep 60
  /scripts/install-herdr.sh
  exit 1
fi

# Listen on all interfaces inside the container; the token gates every request.
export HOST="${WEBUI_HOST:-0.0.0.0}"
export PORT="${WEBUI_PORT:-7317}"
export OVIS_TOKEN="$(cat /config/ovis_token)"
export OVIS_NO_OPEN=1
export OVIS_AUTO_UPDATE=0
export OVIS_STATE_DIR="$HOME/.config/ovis"
export HERDR_SOCKET="${HERDR_SOCKET:-$HOME/.config/herdr/herdr.sock}"

cd "$OVIS_DIR"
if [ -f scripts/with-bun.sh ]; then
  exec /bin/sh scripts/with-bun.sh run start
fi
exec bun run start
