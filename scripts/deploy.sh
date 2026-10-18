#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
[[ -f .env ]] || { printf '%s\n' 'Run bash scripts/init-env.sh first.' >&2; exit 1; }
docker compose version >/dev/null
if [[ "${1:-}" == "--edge" ]]; then
  docker compose -f compose.yml -f compose.edge.yml up -d --build
  docker compose -f compose.yml -f compose.edge.yml ps
else
  docker compose up -d --build
  docker compose ps
  printf '%s\n' 'App is bound to loopback port 4100 (or APP_PORT). Connect your HTTPS reverse proxy.'
fi
