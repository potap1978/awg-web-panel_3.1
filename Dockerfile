# awg-web-panel_3.1 вЂ” self-contained AmneziaWG 3.1 web panel.
# Full image: AmneziaWG runtime + Python + agent + web UI. Nothing else needed.
FROM ghcr.io/potap1978/amneziawg-go:3.1.20260828

# nftables + init.
RUN apk add --no-cache python3 py3-pip iptables ip6tables nftables dumb-init

WORKDIR /app
COPY src/requirements.txt ./
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

COPY src/agent/ ./agent/
COPY src/web/ ./web/

ARG BUILD_SHA=dev
ENV AGENT_BUILD=${BUILD_SHA} \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    WG_PATH=/etc/amnezia/amneziawg

EXPOSE 51820/udp
EXPOSE 51821/tcp
EXPOSE 51822/udp

LABEL org.opencontainers.image.title="awg-web-panel_3.1"
LABEL org.opencontainers.image.description="AmneziaWG 3.1 web panel (ContentPadding, per-client LAN subnets, admin login with per-IP rate limit)"
LABEL org.opencontainers.image.url="https://github.com/potap1978/awg-web-panel_3.1"
LABEL org.opencontainers.image.source="https://github.com/potap1978/awg-web-panel_3.1"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="potap1978"

CMD ["/usr/bin/dumb-init", "sh", "-c", "exec uvicorn agent.main:app --host ${WEBUI_HOST:-0.0.0.0} --port ${PORT:-51821} --no-access-log"]
