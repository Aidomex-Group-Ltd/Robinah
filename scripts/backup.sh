#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
umask 077
mkdir -p backups
stamp=$(date -u +%Y%m%dT%H%M%SZ)
docker compose exec -T db sh -c 'pg_dump -U "${POSTGRES_USER:-robinah}" -d "${POSTGRES_DB:-robinah_db}" -Fc' \
  > "backups/robinahs-shop-${stamp}.dump"
printf 'Consistent PostgreSQL backup saved to backups/robinahs-shop-%s.dump\n' "$stamp"
printf 'Restore with: pg_restore -U <user> -d <database> backups/robinahs-shop-%s.dump\n' "$stamp"
