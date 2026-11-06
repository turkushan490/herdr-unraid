#!/bin/bash
# Shared environment for everything that runs as user herdr.
# supervisord's user= does not set HOME, so set it explicitly.
export HOME=/home/herdr
export USER=herdr
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export LANG="${LANG:-C.UTF-8}"
export TERM="${TERM:-xterm-256color}"
export SHELL=/bin/bash
cd "$HOME" || exit 1

export OVIS_DIR="$HOME/.local/share/ovis/app"
