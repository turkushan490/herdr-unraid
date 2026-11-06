#!/bin/bash
# Headless herdr server (supervisord program "herdr")
. /scripts/env.sh
if ! command -v herdr >/dev/null; then
  echo "[herdr] herdr not installed (first-start download failed?) - retrying in 60s"
  sleep 60
  /scripts/install-herdr.sh
  exit 1
fi

# Warm up the herdr-core daemon too, so the Herdr desktop app / `hc machine add`
# find it running. It daemonizes itself; failure here is not fatal.
command -v hc >/dev/null && hc ls >/dev/null 2>&1 || true

exec herdr server
