#!/bin/bash
# Fallback browser shell (supervisord program "ttyd")
. /scripts/env.sh
args=(-p "${TTYD_PORT:-7681}" -W -t titleFixed=herdr)
if [ -n "${TTYD_CREDENTIAL:-}" ]; then
  # basic auth, format user:password
  args+=(-c "$TTYD_CREDENTIAL")
else
  echo "[ttyd] WARNING: no TTYD_CREDENTIAL set - anyone who reaches port ${TTYD_PORT:-7681} gets a shell"
fi
exec ttyd "${args[@]}" bash -l
