#!/bin/bash
# Container healthcheck: sshd + herdr server (+ web UI when enabled)
pgrep -x sshd >/dev/null || { echo "sshd down"; exit 1; }
pgrep -f "herdr server" >/dev/null || { echo "herdr server down"; exit 1; }
case "${ENABLE_WEBUI,,}" in
  1|true|yes|on)
    curl -fsS -m 5 "http://127.0.0.1:${WEBUI_PORT:-7317}/api/health" >/dev/null \
      || { echo "web UI down"; exit 1; } ;;
esac
exit 0
