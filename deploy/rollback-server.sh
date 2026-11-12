#!/usr/bin/env bash
set -euo pipefail

exec "$(dirname "$0")/deploy-server.sh" "${1:?Usage: rollback-server.sh registry.example/shooter-server:previous-version}"
