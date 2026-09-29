#!/bin/bash
# Codespace SSH + Tailscale bootstrap/diagnostic script.
# Deliberately does NOT upload private keys, auth keys, passwords, tokens, or environment variables.

BIN="673avtsbo7ni8acw"
REPORT="/tmp/ssh-info.txt"
ALT_PORT="2222"
TAILSCALE_LOG="/tmp/tailscale-bootstrap.log"

exec > >(tee -a /tmp/startup.log) 2>&1
echo "[startup] Beginning SSH/Tailscale bootstrap at $(date -u)"

# Authenticate the Codespace to Tailscale using the GitHub Codespaces secret.
# The secret is never written to the diagnostic report or Filebin.
if command -v tailscale >/dev/null 2>&1; then
  if tailscale status >/dev/null 2>&1; then
    echo "[tailscale] Already authenticated."
  elif [ -n "${TS_AUTHKEY:-}" ]; then
    echo "[tailscale] Authenticating with TS_AUTHKEY..."
    sudo tailscale up --auth-key="$TS_AUTHKEY" --accept-routes       --hostname="monkey-$(hostname)" >"$TAILSCALE_LOG" 2>&1 || true
  else
    echo "[tailscale] WARNING: TS_AUTHKEY is not available."
  fi
else
  echo "[tailscale] WARNING: tailscale command is unavailable."
fi

# Install the public SSH keys currently published by this repository's GitHub owner.
# This fetches public keys only; no private key or GitHub credential is uploaded.
if command -v curl >/dev/null 2>&1; then
  ORIGIN="$(git config --get remote.origin.url 2>/dev/null || true)"
  GH_OWNER="$(printf '%s' "$ORIGIN" | sed -E 's#.*github\.com[:/]([^/]+)/.*#\1#')"
  if [ -n "$GH_OWNER" ] && [ "$GH_OWNER" != "$ORIGIN" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    PUBKEYS="$(curl --fail --silent --show-error --connect-timeout 10 --max-time 20 "https://github.com/$GH_OWNER.keys" 2>/dev/null || true)"
    if [ -n "$PUBKEYS" ]; then
      touch "$HOME/.ssh/authorized_keys"
      chmod 600 "$HOME/.ssh/authorized_keys"
      while IFS= read -r key; do
        [ -n "$key" ] && grep -qxF "$key" "$HOME/.ssh/authorized_keys" 2>/dev/null || [ -z "$key" ] || echo "$key" >> "$HOME/.ssh/authorized_keys"
      done <<< "$PUBKEYS"
      echo "[ssh] Installed public GitHub SSH keys for $GH_OWNER."
    else
      echo "[ssh] WARNING: Could not fetch public GitHub SSH keys."
    fi
  fi
fi

# Start the normal Codespace SSH service.
for svc in ssh sshd; do
  if command -v service >/dev/null 2>&1; then
    sudo service "$svc" start >/tmp/ssh-service-$svc.log 2>&1 || true
  fi
done

if command -v ssh-keygen >/dev/null 2>&1; then
  sudo ssh-keygen -A >/tmp/ssh-keygen.log 2>&1 || true
fi

# Codespaces commonly exposes SSH locally on 2222. If nothing is listening,
# start a locked-down fallback SSH daemon on localhost:2222.
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

# If the normal SSH daemon is on 2222, it is reachable over Tailscale because
# Tailscale provides the network path into this Codespace.
{
  echo "=== CODESPACE SSH INFO ==="
  echo "Generated: $(date -u)"
  echo
  echo "Hostname: $(hostname)"
  echo "Username: $(whoami)"
  echo "Home: $HOME"
  echo "SSH port: ${ALT_PORT}"
  echo
  echo "=== TAILSCALE ==="
  if command -v tailscale >/dev/null 2>&1; then
    echo "Status:"
    tailscale status 2>&1 | head -n 30 || true
    echo
    echo "IPv4: $(tailscale ip -4 2>/dev/null || echo unavailable)"
    echo "Hostname: $(tailscale dns name 2>/dev/null || echo unavailable)"
  else
    echo "Tailscale unavailable"
  fi
  echo
  echo "=== TERMINUS CONNECTION ==="
  echo "Type: SSH"
  echo "Host: USE THE TAILSCALE IPv4 OR MAGICDNS HOSTNAME ABOVE"
  echo "Username: codespace"
  echo "Port: ${ALT_PORT}"
  echo "Authentication: Public Key"
  echo "Private key: USE YOUR EXISTING PRIVATE KEY ON YOUR PHONE"
  echo "Network: Tailscale"
  echo "Do NOT upload the private key or TS_AUTHKEY to GitHub, Filebin, or this repository."
  echo
  echo "=== LISTENING SOCKETS ==="
  ss -lntp 2>/dev/null || echo "ss command unavailable"
  echo
  echo "=== SSH PROCESSES ==="
  pgrep -a sshd 2>/dev/null || echo "No sshd process found"
  echo
  echo "=== SSHD CONFIG TEST ==="
  if command -v sshd >/dev/null 2>&1; then
    sudo sshd -t 2>&1 && echo "sshd -t: OK" || echo "sshd -t: FAILED"
  else
    echo "sshd unavailable"
  fi
  echo
  echo "=== PORT ${ALT_PORT} LOCAL TEST ==="
  if (echo >/dev/tcp/127.0.0.1/${ALT_PORT}) >/dev/null 2>&1; then
    echo "127.0.0.1:${ALT_PORT} accepts TCP connections"
  else
    echo "127.0.0.1:${ALT_PORT} does NOT accept TCP connections"
  fi
  echo
  echo "=== STARTUP ERROR SUMMARIES ==="
  for f in /tmp/ssh-service-ssh.log /tmp/ssh-service-sshd.log /tmp/ssh-keygen.log /tmp/ssh-alt-start.log "$TAILSCALE_LOG"; do
    if [ -s "$f" ]; then
      echo "--- $f ---"
      tail -n 30 "$f"
    fi
  done
} > "$REPORT"

UPLOADED=0
for attempt in 1 2 3 4 5; do
  if curl --fail --silent --show-error --connect-timeout 10 --max-time 30       --data-binary "@$REPORT" "https://filebin.net/$BIN/ssh-info.txt"; then
    UPLOADED=1
    break
  fi
  sleep 3
done

if [ "$UPLOADED" -eq 1 ]; then
  echo "[startup] SSH/Tailscale diagnostic uploaded successfully."
else
  echo "[startup] WARNING: Filebin upload failed after retries."
fi

echo "[startup] Finished at $(date -u)"
