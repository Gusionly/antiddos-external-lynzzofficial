#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="ptero-antiddos-tool"
VERSION="0.1.0"
RATE_DEFAULT="15r/s"
BURST_DEFAULT="40"
CONN_DEFAULT="40"
ZONE_REQ="ptero_req_limit"
ZONE_CONN="ptero_conn_limit"
MARK_START="# BEGIN PTERO-ANTIDDOS MANAGED BLOCK"
MARK_END="# END PTERO-ANTIDDOS MANAGED BLOCK"

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err() { printf '[ERROR] %s\n' "$*" >&2; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    err "Run as root: sudo bash install.sh"
    exit 1
  fi
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

  local candidate
  candidate=$(grep -RIl "pterodactyl\|/var/www/pterodactyl\|server_name" /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null | head -n 1 || true)
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

backup_file() {
  local file="$1"
  local backup_dir="/var/backups/${SCRIPT_NAME}"
  mkdir -p "$backup_dir"
  local backup_file="$backup_dir/$(basename "$file").$(date +%Y%m%d-%H%M%S).bak"
  cp -a "$file" "$backup_file"
  printf '%s\n' "$backup_file"
}

insert_http_zones() {
  local nginx_conf="$1"
  if grep -q "$MARK_START" "$nginx_conf"; then
    log "Zone config already present in $nginx_conf"
    return 0
  fi

  awk -v mark_start="$MARK_START" -v mark_end="$MARK_END" -v req="$ZONE_REQ" -v conn="$ZONE_CONN" -v rate="$RATE" '
    BEGIN { inserted=0 }
    {
      print $0
      if (!inserted && $0 ~ /^[[:space:]]*http[[:space:]]*\{[[:space:]]*$/) {
        print "    " mark_start
        print "    limit_req_zone $binary_remote_addr zone=" req ":10m rate=" rate ";"
        print "    limit_conn_zone $binary_remote_addr zone=" conn ":10m;"
        print "    " mark_end
        inserted=1
      }
    }
    END {
      if (!inserted) exit 42
    }
  ' "$nginx_conf" > "$nginx_conf.tmp"

  mv "$nginx_conf.tmp" "$nginx_conf"
}

insert_server_limits() {
  local site_conf="$1"
  if grep -q "$MARK_START" "$site_conf"; then
    log "Server limit block already present in $site_conf"
    return 0
  fi

  awk -v mark_start="$MARK_START" -v mark_end="$MARK_END" -v req="$ZONE_REQ" -v conn="$ZONE_CONN" -v burst="$BURST" -v connmax="$CONN" '
    BEGIN { inserted=0 }
    {
      print $0
      if (!inserted && $0 ~ /^[[:space:]]*server[[:space:]]*\{[[:space:]]*$/) {
        print "    " mark_start
        print "    limit_req zone=" req " burst=" burst " nodelay;"
        print "    limit_conn " conn " " connmax ";"
        print "    " mark_end
        inserted=1
      }
    }
    END {
      if (!inserted) exit 43
    }
  ' "$site_conf" > "$site_conf.tmp"

  mv "$site_conf.tmp" "$site_conf"
}

restore_from_backup() {
  local original="$1"
  local backup="$2"
  if [ -f "$backup" ]; then
    cp -a "$backup" "$original"
    warn "Restored $original from $backup"
  fi
}

show_summary() {
  cat <<EOF
Done.

Applied settings:
- rate:  $RATE
- burst: $BURST
- conn:  $CONN
- site:  $SITE_CONF_PATH

Next:
1. Open your panel.
2. Test login, dashboard, and server console.
3. If anything looks wrong, run: sudo bash uninstall.sh
EOF
}

require_root

RATE="${RATE:-$RATE_DEFAULT}"
BURST="${BURST:-$BURST_DEFAULT}"
CONN="${CONN:-$CONN_DEFAULT}"
NGINX_CONF="/etc/nginx/nginx.conf"

if ! command -v nginx >/dev/null 2>&1; then
  err "nginx is not installed"
  exit 1
fi

if [ ! -f "$NGINX_CONF" ]; then
  err "Missing $NGINX_CONF"
  exit 1
fi

SITE_CONF_PATH="$(find_site_conf || true)"
if [ -z "$SITE_CONF_PATH" ]; then
  err "Could not find Pterodactyl nginx site config. Set SITE_CONF=/path/to/file and retry."
  exit 1
fi

log "Using site config: $SITE_CONF_PATH"
log "Validating current nginx config"
nginx -t

NGINX_BACKUP="$(backup_file "$NGINX_CONF")"
SITE_BACKUP="$(backup_file "$SITE_CONF_PATH")"
log "Backups created"
log "- $NGINX_BACKUP"
log "- $SITE_BACKUP"

trap 'restore_from_backup "$NGINX_CONF" "$NGINX_BACKUP"; restore_from_backup "$SITE_CONF_PATH" "$SITE_BACKUP"' ERR

insert_http_zones "$NGINX_CONF"
insert_server_limits "$SITE_CONF_PATH"

log "Testing updated nginx config"
nginx -t

log "Reloading nginx"
systemctl reload nginx

trap - ERR
show_summary
