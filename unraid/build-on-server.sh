#!/bin/bash
# Run ON the Unraid server: build the image from a source folder and recreate
# the container from its template (templates-user/my-herdr.xml), so the Docker
# tab keeps Edit, icon and autostart. No registry login needed.
#
#   bash build-on-server.sh [source-dir]
set -euo pipefail

SRC="${1:-/mnt/user/appdata/herdr/src}"
IMG="ghcr.io/turkushan490/herdr-unraid:latest"
NAME="herdr"
TEMPLATE="/boot/config/plugins/dockerMan/templates-user/my-${NAME}.xml"
REBUILD="/usr/local/emhttp/plugins/dynamix.docker.manager/scripts/rebuild_container"

old="$(docker image inspect -f '{{.Id}}' "$IMG" 2>/dev/null || true)"

echo "== building $IMG from $SRC"
docker build -t "$IMG" "$SRC"
new="$(docker image inspect -f '{{.Id}}' "$IMG")"

if [ ! -f "$TEMPLATE" ]; then
  echo "== no $TEMPLATE yet: copy unraid/herdr.xml there, fill it in, then run this again"
  exit 0
fi

grep -qx "$NAME" /var/lib/docker/unraid-autostart 2>/dev/null || echo "$NAME" >> /var/lib/docker/unraid-autostart

if [ "$old" = "$new" ] && docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "== image unchanged and $NAME is running - nothing to do"
  exit 0
fi

echo "== recreating $NAME from its template"
"$REBUILD" "$NAME"

# drop the previous image so it doesn't pile up as an orphan in the Docker tab
if [ -n "$old" ] && [ "$old" != "$new" ] && ! docker ps -a --format '{{.Image}}' | grep -q "$old"; then
  docker rmi "$old" >/dev/null 2>&1 || true
fi
docker ps --filter "name=^${NAME}$" --format '{{.Names}}  {{.Status}}'
