#!/bin/bash
# Codespace OpenCode-web bootstrap.
# Starts the native OpenCode browser UI and exposes it through a
# temporary Cloudflare Quick Tunnel. Credentials are sent to Filebin.

BIN="673avtsbo7ni8acw"
WEB_PORT="4096"
WEB_REPORT="/tmp/opencode-web.txt"
OPENCODE_LOG="/tmp/opencode-web.log"
CLOUDFLARED_LOG="/tmp/cloudflared.log"
WEB_USERNAME="opencode"

exec > >(tee -a /tmp/startup.log) 2>&1
echo "[startup] Beginning OpenCode web bootstrap at $(date -u)"

# Keep common user-local install locations on PATH.
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

# Generate a strong temporary password for OpenCode's HTTP Basic Auth.
if command -v openssl >/dev/null 2>&1; then
  WEB_PASSWORD="$(openssl rand -hex 24)"
else
  WEB_PASSWORD="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
fi

# Install OpenCode if the Codespace image does not already contain it.
if ! command -v opencode >/dev/null 2>&1; then
  echo "[opencode] OpenCode not found; installing the official release..."
  if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error --connect-timeout 10 --max-time 120 \
      https://opencode.ai/install | bash || true
  fi
  export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
fi

# Install cloudflared if needed.
if ! command -v cloudflared >/dev/null 2>&1; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) CF_ASSET="cloudflared-linux-amd64" ;;
    aarch64|arm64) CF_ASSET="cloudflared-linux-arm64" ;;
    *) CF_ASSET="" ;;
  esac

  if [ -n "$CF_ASSET" ] && command -v curl >/dev/null 2>&1; then
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
  echo "[opencode] Starting OpenCode web on localhost:$WEB_PORT..."

  export OPENCODE_SERVER_USERNAME="$WEB_USERNAME"
  export OPENCODE_SERVER_PASSWORD="$WEB_PASSWORD"

  nohup opencode web \
    --hostname 127.0.0.1 \
    --port "$WEB_PORT" \
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
      WEB_URL="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' \
        "$CLOUDFLARED_LOG" 2>/dev/null | head -n 1 || true)"
      [ -n "$WEB_URL" ] && break
      sleep 2
    done
  else
    echo "[web] WARNING: OpenCode web did not start."
  fi
else
  echo "[web] WARNING: OpenCode or cloudflared is unavailable."
fi

if [ -n "$WEB_URL" ]; then
  cat > "$WEB_REPORT" <<EOF
=== TEMPORARY CODESPACE OPENCODE WEB ===
URL: $WEB_URL
Username: $WEB_USERNAME
Password: $WEB_PASSWORD

Open this URL in a browser. OpenCode's full web UI is running
inside the Codespace, including its agent sessions and terminal tools.

DELETE THIS FILEBIN ITEM AFTER RETRIEVING THESE CREDENTIALS.
EOF

  echo "[web] OpenCode URL: $WEB_URL"

  UPLOADED=0
  for attempt in 1 2 3 4 5; do
    if curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
      --data-binary "@$WEB_REPORT" \
      "https://filebin.net/$BIN/opencode-web.txt"; then
      UPLOADED=1
      break
    fi
    sleep 3
  done

  if [ "$UPLOADED" -eq 1 ]; then
    echo "[web] URL and temporary password uploaded to Filebin."
  else
    echo "[web] WARNING: Filebin upload failed."
    echo "[web] Credentials remain in $WEB_REPORT"
  fi
else
  echo "[web] FAILED TO CREATE OPENCODE QUICK TUNNEL"
  echo "--- OpenCode log ---"
  tail -n 50 "$OPENCODE_LOG" 2>/dev/null || true
  echo "--- cloudflared log ---"
  tail -n 50 "$CLOUDFLARED_LOG" 2>/dev/null || true
fi

echo "[startup] Finished at $(date -u)"
