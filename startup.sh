#!/usr/bin/env bash
set -u
umask 077
STATE="/tmp/monkey-bootstrap"
mkdir -p "$STATE"
exec > >(tee -a "$STATE/startup.log") 2>&1

WEB_PORT=7681
SSH_PORT=2222
WEB_USER=monkey
WEB_PASSWORD_FILE="$STATE/password"
WEB_REPORT="$STATE/web-terminal.txt"
SSH_REPORT="$STATE/ssh-terminal.txt"
DIAG_REPORT="$STATE/diagnostics.txt"
TTYD_LOG="$STATE/ttyd.log"
CF_LOG="$STATE/cloudflared.log"
PINGGY_LOG="$STATE/pinggy.log"
SSHD_LOG="$STATE/sshd.log"

have(){ command -v "$1" >/dev/null 2>&1; }
password(){
  if have openssl; then openssl rand -hex 24
  else od -An -N24 -tx1 /dev/urandom | tr -d ' \n'; fi
}
wait_port(){
  local h="$1" p="$2" n="$3"
  for _ in $(seq 1 "$n"); do
    (echo >/dev/tcp/"$h"/"$p") >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}
install_bin(){
  local n="$1" u="$2" d="$3"
  have "$n" && return 0
  have curl || return 1
  echo "[install] $n"
  curl -fL --connect-timeout 10 --max-time 180 "$u" -o "/tmp/$n" &&
  chmod +x "/tmp/$n" &&
  sudo -n mv "/tmp/$n" "$d"
}

echo "===== MONKEY STARTUP $(date -u) ====="

if [ -s "$WEB_PASSWORD_FILE" ]; then
  WEB_PASSWORD="$(cat "$WEB_PASSWORD_FILE")"
else
  WEB_PASSWORD="$(password)"
  printf '%s\n' "$WEB_PASSWORD" > "$WEB_PASSWORD_FILE"
fi

USER_NAME="$(id -un)"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) TTYD_ASSET=ttyd.x86_64; CF_ASSET=cloudflared-linux-amd64 ;;
  aarch64|arm64) TTYD_ASSET=ttyd.aarch64; CF_ASSET=cloudflared-linux-arm64 ;;
  *) TTYD_ASSET=""; CF_ASSET="" ;;
esac

if [ -n "$TTYD_ASSET" ] && ! have ttyd; then
  install_bin ttyd "https://github.com/tsl0922/ttyd/releases/latest/download/$TTYD_ASSET" /usr/local/bin/ttyd || true
fi
if [ -n "$CF_ASSET" ] && ! have cloudflared; then
  install_bin cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/$CF_ASSET" /usr/local/bin/cloudflared || true
fi

# ---------- browser terminal ----------
if have ttyd && have cloudflared; then
  pkill -f "ttyd.*-p $WEB_PORT" 2>/dev/null || true
  pkill -f "cloudflared.*127.0.0.1:$WEB_PORT" 2>/dev/null || true
  rm -f "$CF_LOG"

  echo "[web] ttyd -> 127.0.0.1:$WEB_PORT"
  nohup ttyd -W -p "$WEB_PORT" -c "$WEB_USER:$WEB_PASSWORD" bash >"$TTYD_LOG" 2>&1 &
  TTYD_PID=$!

  if wait_port 127.0.0.1 "$WEB_PORT" 20; then
    nohup cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:$WEB_PORT" >"$CF_LOG" 2>&1 &
    CF_PID=$!
    WEB_URL=""
    for _ in $(seq 1 30); do
      WEB_URL="$(grep -Eo 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' "$CF_LOG" 2>/dev/null | head -n1 || true)"
      [ -n "$WEB_URL" ] && break
      kill -0 "$CF_PID" 2>/dev/null || break
      sleep 2
    done
    if [ -n "$WEB_URL" ]; then
      cat >"$WEB_REPORT" <<EOF
=== TEMPORARY CODESPACE WEB TERMINAL ===
URL: $WEB_URL
Username: $WEB_USER
Password: $WEB_PASSWORD
EOF
      echo "[web] $WEB_URL"
    else
      echo "[web] Cloudflare failed"
      tail -n 30 "$CF_LOG" 2>/dev/null || true
    fi
  else
    echo "[web] ttyd failed"
    tail -n 30 "$TTYD_LOG" 2>/dev/null || true
  fi
else
  echo "[web] ttyd/cloudflared unavailable"
fi

# ---------- local SSH server ----------
SSHD=""
for x in sshd /usr/sbin/sshd /usr/lib/openssh/sshd; do
  if [ -x "$x" ]; then SSHD="$x"; break; fi
done

if [ -n "$SSHD" ]; then
  KEYDIR="$STATE/hostkeys"
  mkdir -p "$KEYDIR"
  [ -f "$KEYDIR/ed25519" ] || ssh-keygen -q -t ed25519 -N "" -f "$KEYDIR/ed25519" || true
  [ -f "$KEYDIR/rsa" ] || ssh-keygen -q -t rsa -b 3072 -N "" -f "$KEYDIR/rsa" || true

  if have sudo && sudo -n true >/dev/null 2>&1; then
    printf '%s:%s\n' "$USER_NAME" "$WEB_PASSWORD" | sudo chpasswd || true
  elif [ "$(id -u)" = 0 ]; then
    printf '%s:%s\n' "$USER_NAME" "$WEB_PASSWORD" | chpasswd || true
  else
    echo "[ssh] Cannot set password: sudo unavailable"
  fi

  SSH_CONFIG="$STATE/sshd_config"
  cat >"$SSH_CONFIG" <<EOF
Port $SSH_PORT
ListenAddress 127.0.0.1
HostKey $KEYDIR/ed25519
HostKey $KEYDIR/rsa
PasswordAuthentication yes
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
PermitRootLogin no
AllowUsers $USER_NAME
AllowTcpForwarding no
GatewayPorts no
PermitTunnel no
X11Forwarding no
PidFile $STATE/sshd.pid
EOF

  if "$SSHD" -t -f "$SSH_CONFIG" >/tmp/monkey-sshd-check 2>&1; then
    if [ -f "$STATE/sshd.pid" ]; then
      kill "$(cat "$STATE/sshd.pid")" 2>/dev/null || true
    fi
    nohup "$SSHD" -D -e -f "$SSH_CONFIG" >"$SSHD_LOG" 2>&1 &
    SSHD_PID=$!
    if wait_port 127.0.0.1 "$SSH_PORT" 15; then
      echo "[ssh] local sshd ready on 127.0.0.1:$SSH_PORT"
    else
      echo "[ssh] sshd did not open port"
      cat /tmp/monkey-sshd-check
      tail -n 30 "$SSHD_LOG" 2>/dev/null || true
    fi
  else
    echo "[ssh] sshd config invalid"
    cat /tmp/monkey-sshd-check
  fi
else
  echo "[ssh] openssh-server/sshd is missing."
  echo "[ssh] Install once: sudo apt-get update && sudo apt-get install -y openssh-server"
fi

# ---------- Pinggy ----------
SSH_URL=""
if have ssh && wait_port 127.0.0.1 "$SSH_PORT" 2; then
  pkill -f "ssh.*free\.pinggy\.io.*$SSH_PORT" 2>/dev/null || true
  rm -f "$PINGGY_LOG"

  echo "[ssh] Pinggy TCP tunnel"
  nohup ssh -p 443 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -o ConnectTimeout=15 \
    -R0:127.0.0.1:$SSH_PORT \
    tcp@free.pinggy.io >"$PINGGY_LOG" 2>&1 &
  PINGGY_PID=$!

  for _ in $(seq 1 30); do
    SSH_URL="$(grep -Eo 'tcp://[A-Za-z0-9.-]+:[0-9]+' "$PINGGY_LOG" 2>/dev/null | head -n1 || true)"
    [ -n "$SSH_URL" ] && break
    SSH_URL="$(grep -Eo '[A-Za-z0-9.-]+\.pinggy\.link:[0-9]+' "$PINGGY_LOG" 2>/dev/null | head -n1 || true)"
    [ -n "$SSH_URL" ] && break
    kill -0 "$PINGGY_PID" 2>/dev/null || break
    sleep 2
  done

  if [ -n "$SSH_URL" ]; then
    SSH_URL="$(printf '%s' "$SSH_URL" | sed 's#^tcp://##')"
    PINGGY_HOST="$(printf '%s' "$SSH_URL" | sed 's/:[0-9]*$//')"
    PINGGY_PORT="$(printf '%s' "$SSH_URL" | sed 's/^.*://')"
    cat >"$SSH_REPORT" <<EOF
=== TEMPORARY CODESPACE SSH FOR TERMIUS ===
Host: $PINGGY_HOST
Port: $PINGGY_PORT
Username: $USER_NAME
Password: $WEB_PASSWORD

Termius:
  Host = $PINGGY_HOST
  Port = $PINGGY_PORT
  Username = $USER_NAME
  Password = $WEB_PASSWORD

OpenSSH:
  ssh -p $PINGGY_PORT $USER_NAME@$PINGGY_HOST
EOF
    echo "[ssh] $PINGGY_HOST:$PINGGY_PORT"
  else
    echo "[ssh] Pinggy failed"
    tail -n 50 "$PINGGY_LOG" 2>/dev/null || true
  fi
fi

# ---------- diagnostics ----------
{
  echo "=== MONKEY DIAGNOSTICS ==="
  date -u
  echo "user=$USER_NAME"
  echo "arch=$ARCH"
  echo
  echo "[binaries]"
  command -v ssh || true
  command -v sshd || true
  command -v ttyd || true
  command -v cloudflared || true
  command -v curl || true
  echo
  echo "[ports]"
  (echo >/dev/tcp/127.0.0.1/$WEB_PORT) >/dev/null 2>&1 && echo "web:$WEB_PORT OPEN" || echo "web:$WEB_PORT CLOSED"
  (echo >/dev/tcp/127.0.0.1/$SSH_PORT) >/dev/null 2>&1 && echo "ssh:$SSH_PORT OPEN" || echo "ssh:$SSH_PORT CLOSED"
  echo
  echo "[web]"
  cat "$WEB_REPORT" 2>/dev/null || echo unavailable
  echo
  echo "[ssh]"
  cat "$SSH_REPORT" 2>/dev/null || echo unavailable
  echo
  echo "[pinggy]"
  tail -n 50 "$PINGGY_LOG" 2>/dev/null || true
  echo
  echo "[cloudflared]"
  tail -n 50 "$CF_LOG" 2>/dev/null || true
  echo
  echo "[sshd]"
  tail -n 50 "$SSHD_LOG" 2>/dev/null || true
} >"$DIAG_REPORT"

# ---------- Filebin ----------
if have curl; then
  BIN="$(openssl rand -hex 8 2>/dev/null || od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  echo "[filebin] https://filebin.net/$BIN"

  upload(){
    local f="$1" n="$2"
    [ -f "$f" ] || return 0
    local code
    code="$(curl -sS -o /tmp/filebin-response -w '%{http_code}' \
      --connect-timeout 10 --max-time 45 \
      -X POST -H 'Content-Type: application/octet-stream' \
      --data-binary "@$f" "https://filebin.net/$BIN/$n" 2>&1)"
    case "$code" in
      2*) echo "[filebin] uploaded $n" ;;
      *) echo "[filebin] FAILED $n HTTP=$code"; cat /tmp/filebin-response 2>/dev/null || true ;;
    esac
  }
  upload "$SSH_REPORT" ssh-terminal.txt
  upload "$WEB_REPORT" web-terminal.txt
  upload "$DIAG_REPORT" diagnostics.txt
fi

echo "===== STARTUP FINISHED $(date -u) ====="
