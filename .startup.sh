#!/bin/bash
# Codespace OpenCode-web bootstrap.

BIN="673avtsbo7ni8acw"
WEB_PORT="4096"
WEB_REPORT="/tmp/opencode-web.txt"
OPENCODE_LOG="/tmp/opencode-web.log"
CLOUDFLARED_LOG="/tmp/cloudflared.log"
WEB_USERNAME="opencode"

exec > >(tee -a /tmp/startup.log) 2>&1
echo "[startup] Beginning OpenCode web bootstrap at $(date -u)"

export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

if command -v openssl >/dev/null 2>&1; then
  WEB_PASSWORD="$(openssl rand -hex 24)"
else
  WEB_PASSWORD="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
fi

if ! command -v opencode >/dev/null 2>&1; then
  echo "[opencode] OpenCode not found; installing the official release..."
  curl --fail --silent --show-error --connect-timeout 10 --max-time 120 \
    https://opencode.ai/install | bash || true
  export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
fi

if ! command -v cloudflared >/dev/null 2>&1; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) CF_ASSET="cloudflared-linux-amd64" ;;
    aarch64|arm64) CF_ASSET="cloudflared-linux-arm64" ;;
    *) CF_ASSET="" ;;
  esac

  if [ -n "$CF_ASSET" ]; then
    echo "[web] Installing cloudflared..."
    curl --fail --silent --show-error --connect-timeout 10 --max-time 90 \
      -L "https://github.com/cloudflare/cloudflared/releases/latest/download/$CF_ASSET" \
      -o /tmp/cloudflared &&
      chmod +x /tmp/cloudflared &&
      sudo mv /tmp/cloudflared /usr/local/bin/cloudflared || true
  fi
fi

WEB_URL=""

if command -v opencode >/dev/null 2>&1 && command -v cloudflared >/dev/null 2>&1; then
  export OPENCODE_SERVER_USERNAME="$WEB_USERNAME"
  export OPENCODE_SERVER_PASSWORD="$WEB_PASSWORD"

  echo "[opencode] Starting OpenCode web on localhost:$WEB_PORT..."
  nohup opencode web --hostname 127.0.0.1 --port "$WEB_PORT" \
    >"$OPENCODE_LOG" 2>&1 &
  OPENCODE_PID=$!

  for attempt in $(seq 1 30); do
    if (echo >/dev/tcp/127.0.0.1/$WEB_PORT) >/dev/null 2>&1; then
      break
    fi
    if ! kill -0 "$OPENCODE_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done

  if (echo >/dev/tcp/127.0.0.1/$WEB_PORT) >/dev/null 2>&1; then
    echo "[web] Starting Cloudflare Quick Tunnel..."
    nohup cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:$WEB_PORT" \
      >"$CLOUDFLARED_LOG" 2>&1 &

    for attempt in $(seq 1 30); do
      WEB_URL="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$CLOUDFLARED_LOG" 2>/dev/null | head -n 1 || true)"
      [ -n "$WEB_URL" ] && break
      sleep 2
    done
  fi
fi

if [ -n "$WEB_URL" ]; then
  cat > "$WEB_REPORT" <<EOF
=== TEMPORARY CODESPACE OPENCODE WEB ===
URL: $WEB_URL
Username: $WEB_USERNAME
Password: $WEB_PASSWORD
EOF

  echo "[web] OpenCode URL: $WEB_URL"

  # Filebin's documented upload endpoint is POST /{bin}/{filename}.
  # --data-binary sends the complete file as the request body.
  UPLOADED=0
  for attempt in 1 2 3 4 5; do
    HTTP_CODE="$(curl --silent --show-error --output /tmp/filebin-response.txt \
      --write-out '%{http_code}' \
      --connect-timeout 10 --max-time 30 \
      --request POST \
      --header "Content-Type: application/octet-stream" \
      --data-binary "@$WEB_REPORT" \
      "https://filebin.net/$BIN/opencode-web.txt" || true)"

    if [[ "$HTTP_CODE" =~ ^2 ]]; then
      UPLOADED=1
      break
    fi

    echo "[web] Filebin upload attempt $attempt failed (HTTP $HTTP_CODE)"
    cat /tmp/filebin-response.txt 2>/dev/null || true
    sleep 3
  done

  if [ "$UPLOADED" -eq 1 ]; then
    echo "[web] URL and temporary password uploaded to Filebin."
  else
    echo "[web] WARNING: Filebin upload failed; credentials remain in $WEB_REPORT"
  fi
else
  echo "[web] FAILED TO CREATE OPENCODE QUICK TUNNEL"
  tail -n 50 "$OPENCODE_LOG" 2>/dev/null || true
  tail -n 50 "$CLOUDFLARED_LOG" 2>/dev/null || true
fi

echo "[startup] Finished at $(date -u)"
