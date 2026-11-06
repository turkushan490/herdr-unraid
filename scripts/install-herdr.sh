#!/bin/bash
# First-start install (idempotent), runs as user herdr.
# Everything lands in the home volume, so it survives image rebuilds and
# `herdr update` / `hc update` keep working.
set -uo pipefail
. /scripts/env.sh

log() { echo "[install] $*"; }
mkdir -p "$HOME/.local/bin" "$HOME/.npm-global" /var/log/herdr

# herdr (TUI + headless server) -> ~/.local/bin/herdr
if [ ! -x "$HOME/.local/bin/herdr" ]; then
  log "installing herdr"
  curl -fsSL https://herdr.dev/install.sh | sh || log "ERROR: herdr install failed"
elif [ "${AUTO_UPDATE:-false}" = true ]; then
  log "updating herdr"
  herdr update || log "WARNING: herdr update failed"
fi

# herdr-core -> ~/.local/bin/herdr-core (+ hc symlink). Used by the Herdr
# desktop app and by `hc machine add`.
if [ ! -x "$HOME/.local/bin/herdr-core" ]; then
  log "installing herdr-core (hc)"
  curl -fsSL https://releases.herdr.dev/core/install.sh | sh || log "ERROR: herdr-core install failed"
elif [ "${AUTO_UPDATE:-false}" = true ]; then
  log "updating herdr-core"
  hc update || log "WARNING: hc update failed"
fi

if [ "${ENABLE_WEBUI:-true}" = true ]; then
  # Bun -> ~/.bun/bin/bun
  if [ ! -x "$HOME/.bun/bin/bun" ]; then
    log "installing bun"
    curl -fsSL https://bun.sh/install | bash >/dev/null || log "ERROR: bun install failed"
  fi

  # Ovis (formerly devswha/herdr-web-ui), source checkout
  if [ ! -d "$OVIS_DIR/.git" ]; then
    log "cloning Ovis web UI${OVIS_REF:+ ($OVIS_REF)}"
    mkdir -p "$(dirname "$OVIS_DIR")"
    git clone --depth 1 ${OVIS_REF:+--branch "$OVIS_REF"} https://github.com/devswha/ovis.git "$OVIS_DIR" \
      && (cd "$OVIS_DIR" && bun install) || log "ERROR: Ovis install failed"
  elif [ "${AUTO_UPDATE:-false}" = true ]; then
    log "updating Ovis"
    (cd "$OVIS_DIR" && git pull --ff-only && bun install) || log "WARNING: Ovis update failed"
  fi
fi

log "herdr:      $(herdr --version 2>/dev/null || echo missing)"
log "herdr-core: $(hc --version 2>/dev/null || echo missing)"
[ "${ENABLE_WEBUI:-true}" = true ] && log "bun:        $(bun --version 2>/dev/null || echo missing)"
exit 0
