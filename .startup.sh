#!/bin/bash
set -e

BIN="673avtsbo7ni8acw"
REPORT="/tmp/ssh-info.txt"

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
  echo "=== SSH CONFIG (non-secret fields) ==="
  if [ -f "$HOME/.ssh/config" ]; then
    awk 'tolower($1) ~ /^(host|hostname|port|user)$/ {print}' "$HOME/.ssh/config"
  else
    echo "No ~/.ssh/config found"
  fi
} > "$REPORT"

curl --fail --silent --show-error --data-binary "@$REPORT"   "https://filebin.net/$BIN/ssh-info.txt"

echo "SSH information uploaded to Filebin."
