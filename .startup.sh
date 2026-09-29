#!/bin/bash
# Codespace browser-terminal bootstrap.
# No Tailscale. No SSH setup. No private keys or auth secrets are uploaded.
# A temporary password-protected ttyd terminal is exposed through a
# Cloudflare Quick Tunnel and its credentials are sent to Filebin.

BIN="673avtsbo7ni8acw"
WEB_PORT="7681"
WEB_REPORT="/tmp/web-terminal.txt"
TTYD_LOG="/tmp/ttyd.log"
CLOUDFLARED_LOG="/tmp/cloudflared.log"
WEB_USERNAME="monkey"

exec > >(tee -a /tmp/startup.log) 2>&1
echo "[startup] Beginning Cloudflare web-terminal bootstrap at $(date -u)"

if command -v openssl >/dev/null 2>&1; then
  WEB_PASSWORD="$(openssl rand -hex 24)"
else
  WEB_PASSWORD="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
fi

if ! command -v ttyd >/dev/null 2>&1; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) TTYD_ASSET="ttyd.x86_64" ;;
    aarch64|arm64) TTYD_ASSET="ttyd.aarch64" ;;
    *) TTYD_ASSET="" ;;
  esac
  if [ -n "$TTYD_ASSET" ] && command -v curl >/dev/null 2>&1; then
    echo "[web-terminal] Installing ttyd..."
    curl --fail --silent --show-error --connect-timeout 10 --max-time 90       -L "https://github.com/tsl0922/ttyd/releases/latest/download/$TTYD_ASSET"       -o /tmp/ttyd &&
      chmod +x /tmp/ttyd &&
      sudo mv /tmp/ttyd /usr/local/bin/ttyd || true
  fi
fi

if ! command -v cloudflared >/dev/null 2>&1; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) CF_ASSET="cloudflared-linux-amd64" ;;
    aarch64|arm64) CF_ASSET="cloudflared-linux-arm64" ;;
    *) CF_ASSET="" ;;
  esac
  if [ -n "$CF_ASSET" ] && command -v curl >/dev/null 2>&1; then
    echo "[web-terminal] Installing cloudflared..."
    curl --fail --silent --show-error --connect-timeout 10 --max-time 90       -L "https://github.com/cloudflare/cloudflared/releases/latest/download/$CF_ASSET"       -o /tmp/cloudflared &&
      chmod +x /tmp/cloudflared &&
      sudo mv /tmp/cloudflared /usr/local/bin/cloudflared || true
  fi
fi

WEB_URL=""

if command -v ttyd >/dev/null 2>&1 && command -v cloudflared >/dev/null 2>&1; then
  echo "[web-terminal] Starting ttyd on localhost:$WEB_PORT..."
  nohup ttyd -W -p "$WEB_PORT" -c "$WEB_USERNAME:$WEB_PASSWORD" bash     >"$TTYD_LOG" 2>&1 &

  for attempt in $(seq 1 15); do
    if (echo >/dev/tcp/127.0.0.1/$WEB_PORT) >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if (echo >/dev/tcp/127.0.0.1/$WEB_PORT) >/dev/null 2>&1; then
    echo "[web-terminal] Starting Cloudflare Quick Tunnel..."
    nohup cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:$WEB_PORT"       >"$CLOUDFLARED_LOG" 2>&1 &

    for attempt in $(seq 1 30); do
      WEB_URL="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$CLOUDFLARED_LOG" 2>/dev/null | head -n 1 || true)"
      [ -n "$WEB_URL" ] && break
      sleep 2
    done
  else
    echo "[web-terminal] WARNING: ttyd did not start."
  fi
else
  echo "[web-terminal] WARNING: ttyd or cloudflared is unavailable."
fi

if [ -n "$WEB_URL" ]; then
  cat > "$WEB_REPORT" <<EOF
=== TEMPORARY CODESPACE WEB TERMINAL ===
URL: $WEB_URL
Username: $WEB_USERNAME
Password: $WEB_PASSWORD

DELETE THIS FILEBIN ITEM AFTER RETRIEVING THESE CREDENTIALS.
EOF

  echo "[web-terminal] Quick Tunnel: $WEB_URL"

  UPLOADED=0
  for attempt in 1 2 3 4 5; do
    if curl --fail --silent --show-error --connect-timeout 10 --max-time 30         --data-binary "@$WEB_REPORT"         "https://filebin.net/$BIN/web-terminal.txt"; then
      UPLOADED=1
      break
    fi
    sleep 3
  done

  if [ "$UPLOADED" -eq 1 ]; then
    echo "[web-terminal] URL and temporary password uploaded to Filebin."
  else
    echo "[web-terminal] WARNING: Filebin upload failed."
  fi
else
  echo "[web-terminal] FAILED TO CREATE QUICK TUNNEL"
  echo "--- ttyd log ---"
  tail -n 30 "$TTYD_LOG" 2>/dev/null || true
  echo "--- cloudflared log ---"
  tail -n 50 "$CLOUDFLARED_LOG" 2>/dev/null || true
fi

echo "[startup] Finished at $(date -u)"
