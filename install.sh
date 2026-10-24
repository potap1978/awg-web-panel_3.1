#!/usr/bin/env bash
# End-to-end installer for awg-web-panel_3.1-deploy.
# Tested on Ubuntu 24.04. Requires root.
set -euo pipefail

# ============================================================
# Configuration (interactive вЂ” prompted later unless preset here)
# ============================================================
# Leave empty ("") to prompt with an auto-detected / generated default.
PUBLIC_IP=""                        # public IPv4; used for TLS cert and WG endpoint
HTTPS_PORT="60443"                  # external HTTPS port for the panel
AGENT_PORT="51821"                  # internal port awg-web-panel_3.1 listens on (fixed, not prompted)
WG_PORT="51820"                     # WireGuard/AmneziaWG UDP port
PANEL_USERNAME=""                   # if empty, defaults to "admin"
PANEL_PASSWORD=""                   # if empty, a random one is generated
AGENT_IMAGE="ghcr.io/potap1978/awg-web-panel_3.1:latest"
CPA_DEFAULT="64"                    # ContentPaddingAddition default (32/48/64/96/128)
WG_INTERFACE="awg0"                 # internal interface name (awg0 or wg0)
# ============================================================

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="/opt/awg"
AGENT_DIR="/opt/awg-web-panel_3.1"
CADDY_DIR="/opt/caddy"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  OK:\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m WARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m FAIL:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 1. Root ----------
log "Checking root privileges"
if [[ $EUID -ne 0 ]]; then
  die "this script must be run as root (or with sudo)"
fi
ok "running as root"

# ---------- 1.5 Interactive configuration ----------
if [ -t 0 ]; then
  log "Interactive configuration (press Enter to accept defaults)"

  _detect_ip() {
    local ip=""
    for url in "https://api.ipify.org" "https://ifconfig.me/ip" "https://ipinfo.io/ip"; do
      ip=$(curl -fsS --max-time 4 "$url" 2>/dev/null | tr -d '[:space:]' || true)
      [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && { echo "$ip"; return 0; }
    done
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print $2}' | head -1 || true)
    [ -n "$ip" ] && echo "$ip"
  }
  _default_ip="${PUBLIC_IP:-$(_detect_ip || true)}"
  if [ -n "$_default_ip" ]; then
    printf '  Public IPv4 (TLS cert + VPN endpoint) [default: %s]: ' "$_default_ip"
  else
    printf '  Public IPv4 (TLS cert + VPN endpoint, required - auto-detect failed): '
  fi
  read -r _ans || _ans=""
  PUBLIC_IP="${_ans:-$_default_ip}"
  [[ "$PUBLIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || die "invalid IPv4: '$PUBLIC_IP'"
  ok "PUBLIC_IP=$PUBLIC_IP"

  printf '  HTTPS port for the web panel [default: %s]: ' "$HTTPS_PORT"
  read -r _ans || _ans=""
  HTTPS_PORT="${_ans:-$HTTPS_PORT}"
  [[ "$HTTPS_PORT" =~ ^[0-9]+$ ]] || die "invalid HTTPS port: '$HTTPS_PORT'"
  [ "$HTTPS_PORT" -ge 1 ] && [ "$HTTPS_PORT" -le 65535 ] || die "HTTPS port out of range"
  ok "HTTPS_PORT=$HTTPS_PORT"

  _default_user="${PANEL_USERNAME:-admin}"
  printf '  Panel username [default: %s]: ' "$_default_user"
  read -r _ans || _ans=""
  PANEL_USERNAME="${_ans:-$_default_user}"
  [[ "$PANEL_USERNAME" =~ ^[a-zA-Z0-9_.-]{1,64}$ ]] || die "invalid username (letters, digits, _ . -): '$PANEL_USERNAME'"
  ok "PANEL_USERNAME=$PANEL_USERNAME"

  _gen_pw() {
    if command -v openssl >/dev/null 2>&1; then
      openssl rand -base64 32 2>/dev/null | tr -d '/+=\n' | cut -c1-20
    else
      tr -dc 'A-Za-z0-9!@#%^&*' < /dev/urandom | head -c 20
    fi
  }
  _default_pw="${PANEL_PASSWORD:-$(_gen_pw)}"
  printf '  Panel password for admin [default: %s]: ' "$_default_pw"
  read -r _ans || _ans=""
  PANEL_PASSWORD="${_ans:-$_default_pw}"
  [ -n "$PANEL_PASSWORD" ] || die "empty password"
  ok "PANEL_PASSWORD set (${#PANEL_PASSWORD} chars)"

  printf '  AmneziaWG interface name [default: %s]: ' "$WG_INTERFACE"
  read -r _ans || _ans=""; WG_INTERFACE="${_ans:-$WG_INTERFACE}"
  printf '  VPN UDP port [default: %s]: ' "$WG_PORT"
  read -r _ans || _ans=""; WG_PORT="${_ans:-$WG_PORT}"
  printf '  ContentPaddingAddition 32/48/64/96/128 [default: %s]: ' "$CPA_DEFAULT"
  read -r _ans || _ans=""; CPA_DEFAULT="${_ans:-$CPA_DEFAULT}"
  ok "advanced settings collected"
else
  warn "stdin is not a terminal вЂ” skipping prompts, using preset values"
  [ -n "$PUBLIC_IP" ] || die "PUBLIC_IP must be preset when running non-interactively"
  [ -n "$PANEL_PASSWORD" ] || die "PANEL_PASSWORD must be preset when running non-interactively"
fi

# ---------- 2. OS ----------
log "Checking OS"
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  case "$ID" in
    ubuntu|debian) ok "$PRETTY_NAME" ;;
    *) warn "untested OS: $ID (continuing anyway)" ;;
  esac
else
  warn "/etc/os-release missing вЂ” untested system"
fi

# ---------- 3. Ports ----------
log "Checking that required ports are free"
for p in 80 "$HTTPS_PORT" "$AGENT_PORT"; do
  if ss -lntu 2>/dev/null | awk '{print $5}' | grep -qE ":${p}\$"; then
    die "TCP port $p is already in use. Free it and re-run."
  fi
done
if ss -lun 2>/dev/null | awk '{print $5}' | grep -qE ":${WG_PORT}\$"; then
  die "UDP port $WG_PORT is already in use. Free it and re-run."
fi
ok "ports 80, $HTTPS_PORT, $AGENT_PORT, $WG_PORT are free"

# ---------- 4. Packages ----------
log "Installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release \
  apache2-utils nftables iproute2 procps \
  debian-keyring debian-archive-keyring apt-transport-https
ok "base packages installed"

# ---------- 5. Docker ----------
log "Installing Docker (if not present)"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  ok "docker installed"
else
  ok "docker already present: $(docker --version)"
fi

# ---------- 6. ip_forward ----------
log "Enabling IPv4 forwarding"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
ok "ip_forward enabled"

# ---------- 7. State + agent dirs ----------
log "Preparing /opt directories"
mkdir -p "$STATE_DIR" "$AGENT_DIR" "$CADDY_DIR"
chmod 700 "$STATE_DIR"

if [[ ! -f "$STATE_DIR/clients.json" ]]; then
  ok "state dir is empty вЂ” first start will generate keys"
else
  warn "existing clients.json found in $STATE_DIR вЂ” will be reused"
fi

# ---------- 8. State dir ----------
log "State dir: $STATE_DIR (already prepared)"
ok "patches are baked into the image вЂ” no mounts needed"

# ---------- 9. Start awg-web-panel_3.1 container ----------
log "Starting awg-web-panel_3.1 container"
PASSWORD_HASH=$(htpasswd -nbB admin "$PANEL_PASSWORD" | cut -d: -f2)

if docker ps -a --format '{{.Names}}' | grep -qx awg-web-panel_3.1; then
  warn "existing awg-web-panel_3.1 container found вЂ” removing"
  docker rm -f awg-web-panel_3.1 >/dev/null
fi

docker run -d \
  --name awg-web-panel_3.1 \
  --restart unless-stopped \
  -e PASSWORD_HASH="$PASSWORD_HASH" \
  -e PANEL_USERNAME="$PANEL_USERNAME" \
  -e WG_HOST="$PUBLIC_IP" \
  -e PORT="$AGENT_PORT" \
  -e AWG_CONTENT_PADDING_ADDITION="$CPA_DEFAULT" \
  -e WG_INTERFACE="$WG_INTERFACE" \
  -v "$STATE_DIR":/etc/amnezia/amneziawg \
  -p "127.0.0.1:${AGENT_PORT}:${AGENT_PORT}/tcp" \
  -p "${WG_PORT}:51820/udp" \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --cap-add NET_RAW \
  --sysctl net.ipv4.ip_forward=1 \
  --device /dev/net/tun \
  "$AGENT_IMAGE" >/dev/null

ok "container started: $(docker ps --filter name=awg-web-panel_3.1 --format '{{.Status}}')"

# ---------- 10. Caddy ----------
log "Installing Caddy"
if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy
  ok "caddy installed: $(caddy version | awk '{print $1}')"
else
  ok "caddy already present: $(caddy version | awk '{print $1}')"
fi

# ---------- 11. Caddyfile ----------
log "Configuring Caddy"
sed -e "s|__PUBLIC_IP__|$PUBLIC_IP|g" \
    -e "s|__HTTPS_PORT__|$HTTPS_PORT|g" \
    -e "s|__AGENT_PORT__|$AGENT_PORT|g" \
    "$REPO_DIR/caddy/Caddyfile.template" > "$CADDY_DIR/Caddyfile"
chown -R caddy:caddy "$CADDY_DIR"
chmod 750 "$CADDY_DIR"

mkdir -p /etc/systemd/system/caddy.service.d
cat > /etc/systemd/system/caddy.service.d/override.conf <<OVR
[Service]
ExecStart=
ExecStart=/usr/bin/caddy run --environ --config $CADDY_DIR/Caddyfile
ExecReload=
ExecReload=/usr/bin/caddy reload --config $CADDY_DIR/Caddyfile --force
OVR
systemctl daemon-reload
systemctl enable caddy >/dev/null 2>&1 || true
systemctl restart caddy
ok "caddy running"

# ---------- 12. Wait for certificate ----------
log "Waiting for ACME certificate (up to 90 s)"
for i in $(seq 1 45); do
  if curl -fsS --max-time 3 "https://${PUBLIC_IP}:${HTTPS_PORT}/api/health" >/dev/null 2>&1; then
    ok "certificate issued, panel is reachable"
    break
  fi
  sleep 2
done

# ---------- 13. Smoke test ----------
log "Smoke test"
CODE=$(curl -sk -o /dev/null -w '%{http_code}' "https://${PUBLIC_IP}:${HTTPS_PORT}/" || true)
if [[ "$CODE" == "200" ]]; then ok "panel: HTTP $CODE"
else warn "panel: HTTP $CODE (may need a moment, check journalctl -u caddy)"; fi

H=$(curl -sk "https://${PUBLIC_IP}:${HTTPS_PORT}/api/health" || true)
if [[ -n "$H" ]]; then echo "  health: $H"; else warn "health endpoint did not respond"; fi

# ---------- Done ----------
log "Installation complete"
cat <<SUMMARY

  Panel URL : https://${PUBLIC_IP}:${HTTPS_PORT}/
  Login     : ${PANEL_USERNAME}
  Password  : ${PANEL_PASSWORD}
  VPN port  : ${PUBLIC_IP}:${WG_PORT}/udp

  Next steps:
    1) Change the root password if you have not already:  passwd
    2) Log in to the panel and change the default password.
    3) Create a client, scan the QR, import the config.

  Important: the panel password above was set from PANEL_PASSWORD in this script.
  If you re-run the script with a different PANEL_PASSWORD, the container will
  be recreated and the password changed.

SUMMARY
