#!/usr/bin/env bash
# End-to-end admin sign-in test.
#
# Boots the shop against a throwaway PostgreSQL database, seeds the owner from
# ADMIN_EMAIL/ADMIN_PASSWORD, then drives a real Chromium browser through the
# /staff/sign-in flow (scripts/e2e/admin-signin.e2e.mjs).
#
# Usage:
#   ADMIN_EMAIL=... ADMIN_PASSWORD=... scripts/e2e.sh
#   E2E_DATABASE=robinah_e2e E2E_PORT=4300 scripts/e2e.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

E2E_DATABASE="${E2E_DATABASE:-robinah_e2e}"
E2E_PORT="${E2E_PORT:-4300}"
E2E_ADMIN_EMAIL="${ADMIN_EMAIL:-${E2E_ADMIN_EMAIL:-abenitwerobinah@gmail.com}}"
E2E_ADMIN_PASSWORD="${ADMIN_PASSWORD:-${E2E_ADMIN_PASSWORD:-33d6751617f4e24dac8cf57fd8761ed18566864078f878493b4795d9c57336fc}}"

case "$E2E_DATABASE" in
  *e2e*) ;;
  *)
    echo "Refusing to reset non-e2e database '$E2E_DATABASE'." >&2
    exit 1
    ;;
esac

export DATABASE_URL="$E2E_DATABASE"
export ADMIN_EMAIL="$E2E_ADMIN_EMAIL"
ADMIN_PASSWORD="$E2E_ADMIN_PASSWORD"
export ADMIN_PASSWORD
export MIX_ENV=dev

echo "==> Preparing throwaway database $E2E_DATABASE"
# Recreate when possible; if another client is still attached, fall back to
# wiping the staff tables below so the seeded credentials are always fresh.
for _ in 1 2 3; do
  mix ecto.drop --quiet 2>/dev/null && break
  sleep 3
done
mix ecto.create --quiet
mix ecto.migrate --quiet

echo "==> Seeding owner $E2E_ADMIN_EMAIL"
mix run -e '
  alias RobinahsShop.{Repo, Staff, StaffSession}
  Repo.delete_all(StaffSession)
  Repo.delete_all(Staff)
'
mix run priv/repo/seeds.exs

echo "==> Starting server on port $E2E_PORT"
PORT="$E2E_PORT" mix phx.server >"$ROOT/scripts/e2e/server.log" 2>&1 &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:$E2E_PORT/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:$E2E_PORT/healthz" >/dev/null 2>&1; then
  echo "Server did not become healthy; see scripts/e2e/server.log" >&2
  exit 1
fi

# First requests in dev compile LiveView modules on demand; warm the routes the
# browser will hit so navigation is not competing with compilation.
curl -sS -o /dev/null "http://127.0.0.1:$E2E_PORT/staff/pos" || true
curl -sS -o /dev/null "http://127.0.0.1:$E2E_PORT/staff/sign-in" || true

echo "==> Running admin sign-in browser test"
if [ ! -d scripts/e2e/node_modules ]; then
  npm --prefix scripts/e2e install --no-audit --no-fund
fi

E2E_BASE_URL="http://127.0.0.1:$E2E_PORT" \
E2E_ADMIN_EMAIL="$E2E_ADMIN_EMAIL" \
E2E_ADMIN_PASSWORD="$E2E_ADMIN_PASSWORD" \
  node scripts/e2e/admin-signin.e2e.mjs
