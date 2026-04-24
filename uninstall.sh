#!/usr/bin/env bash
set -euo pipefail

MARK_START="# BEGIN PTERO-ANTIDDOS MANAGED BLOCK"
MARK_END="# END PTERO-ANTIDDOS MANAGED BLOCK"

log() { printf '[INFO] %s\n' "$*"; }
err() { printf '[ERROR] %s\n' "$*" >&2; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    err "Run as root: sudo bash uninstall.sh"
    exit 1
  fi
}

remove_managed_block() {
  local file="$1"
  if [ ! -f "$file" ]; then
    return 0
  fi

  awk -v start="$MARK_START" -v end="$MARK_END" '
    index($0, start) { skip=1; next }
    index($0, end) { skip=0; next }
    !skip { print }
  ' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

find_site_conf() {
  if [ -n "${SITE_CONF:-}" ] && [ -f "$SITE_CONF" ]; then
    printf '%s\n' "$SITE_CONF"
    return 0
  fi

  for f in \
    /etc/nginx/sites-available/pterodactyl.conf \
    /etc/nginx/sites-enabled/pterodactyl.conf \
    /etc/nginx/conf.d/pterodactyl.conf; do
    if [ -f "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done

  return 1
}

require_root

NGINX_CONF="/etc/nginx/nginx.conf"
SITE_CONF_PATH="$(find_site_conf || true)"

if ! command -v nginx >/dev/null 2>&1; then
  err "nginx is not installed"
  exit 1
fi

log "Removing managed block from $NGINX_CONF"
remove_managed_block "$NGINX_CONF"

if [ -n "$SITE_CONF_PATH" ]; then
  log "Removing managed block from $SITE_CONF_PATH"
  remove_managed_block "$SITE_CONF_PATH"
fi

log "Testing nginx config"
nginx -t

log "Reloading nginx"
systemctl reload nginx

log "Done"
