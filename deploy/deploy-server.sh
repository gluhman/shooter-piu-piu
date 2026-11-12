#!/usr/bin/env bash
set -euo pipefail

image="${1:?Usage: deploy-server.sh registry.example/shooter-server:version}"
grep -Eq '^SHOOTER_SERVER_IMAGE=' /etc/shooter/server.env &&
  sed -i "s|^SHOOTER_SERVER_IMAGE=.*$|SHOOTER_SERVER_IMAGE=$image|" /etc/shooter/server.env ||
  printf 'SHOOTER_SERVER_IMAGE=%s\n' "$image" | sudo tee -a /etc/shooter/server.env >/dev/null
sudo systemctl restart shooter-server
sudo systemctl --no-pager --full status shooter-server
