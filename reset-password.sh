#!/usr/bin/env bash
# reset-password.sh - change panel username and/or password.
# Run on the server as root: sudo bash reset-password.sh
set -euo pipefail

REPO_DIR="/opt/awg-deploy"
ENV_FILE="$REPO_DIR/.env"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  OK:\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m WARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m FAIL:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$EUID" -eq 0 ] || die "run as root (or sudo)"
log "checking $ENV_FILE"
[ -f "$ENV_FILE" ] || die "$ENV_FILE not found - is the panel installed?"
[ -f "$REPO_DIR/docker-compose.yml" ] || die "docker-compose.yml not found"
command -v htpasswd >/dev/null 2>&1 || die "htpasswd not found - apt-get install apache2-utils"

CURRENT_USER=$(grep -E '^PANEL_USERNAME=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
CURRENT_USER="${CURRENT_USER:-admin}"
log "current username: $CURRENT_USER"

printf 'New username [%s]: ' "$CURRENT_USER"
read -r NEW_USER || NEW_USER=""
NEW_USER="${NEW_USER:-$CURRENT_USER}"
[[ "$NEW_USER" =~ ^[a-zA-Z0-9_.-]{1,64}$ ]] || die "invalid username (letters, digits, _ . -)"

while :; do
  printf 'New password: '
  read -r -s NEW_PASS || NEW_PASS=""
  echo
  [ -n "$NEW_PASS" ] || { warn "password cannot be empty"; continue; }
  [ "${#NEW_PASS}" -ge 6 ] || { warn "password too short (min 6 chars)"; continue; }
  printf 'Confirm password: '
  read -r -s NEW_PASS2 || NEW_PASS2=""
  echo
  [ "$NEW_PASS" = "$NEW_PASS2" ] && break
  warn "passwords do not match, try again"
done

log "generating bcrypt hash"
NEW_HASH=$(htpasswd -nbB "$NEW_USER" "$NEW_PASS" | cut -d: -f2)
[ -n "$NEW_HASH" ] || die "htpasswd failed"

cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%s)"
log "backup: $ENV_FILE.bak.*"

python3 - "$ENV_FILE" "$NEW_USER" "$NEW_HASH" <<'PYEOF'
import sys, io
env_file, new_user, new_hash = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(env_file, encoding='utf-8').read()
lines = s.split('\n')
out = []
for ln in lines:
    if ln.startswith('PASSWORD_HASH='):
        out.append('PASSWORD_HASH=' + chr(39) + new_hash + chr(39))
    elif ln.startswith('PANEL_USERNAME='):
        out.append('PANEL_USERNAME="' + new_user + '"')
    else:
        out.append(ln)
io.open(env_file, 'w', encoding='utf-8').write('\n'.join(out))
PYEOF
ok ".env updated"

log "recreating container"
cd "$REPO_DIR"
docker compose up -d --force-recreate 2>&1 | tail -3

log "waiting for health"
HEALTH_OK=0
for i in $(seq 1 40); do
  if curl -fsS --max-time 2 http://127.0.0.1:51821/api/health >/dev/null 2>&1; then
    ok "container is up"
    HEALTH_OK=1
    break
  fi
  sleep 1
done
[ "$HEALTH_OK" -eq 1 ] || die "container did not respond after 40s: run 'docker compose logs'"

log "testing login"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:51821/api/session \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$NEW_USER\",\"password\":\"$NEW_PASS\"}")
if [ "$CODE" = "200" ]; then
  ok "login OK (HTTP 200)"
else
  warn "login returned HTTP $CODE - check credentials manually"
fi

echo
echo "==============================="
echo "  NEW PANEL CREDENTIALS"
echo "==============================="
echo "  Username: $NEW_USER"
echo "  Password: $NEW_PASS"
echo "==============================="
echo
echo "Open https://<server-ip>:60443/ and log in with the above."
echo "This info is NOT shown again. Save it now."
