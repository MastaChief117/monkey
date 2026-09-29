#!/bin/bash
# Codespace SSH bootstrap/diagnostic script.
# Deliberately does NOT upload private keys, passwords, tokens, or environment variables.

BIN="673avtsbo7ni8acw"
REPORT="/tmp/ssh-info.txt"
ALT_PORT="2222"

exec > >(tee -a /tmp/startup.log) 2>&1
echo "[startup] Beginning SSH bootstrap at $(date -u)"

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
