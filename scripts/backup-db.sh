#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"
command -v pg_dump >/dev/null 2>&1 || {
  echo "ERROR: pg_dump is required" >&2
  exit 1
}

output="${1:-${EVE_BACKUP_PATH:-./artifacts/fullstack-example.dump}}"
mkdir -p "$(dirname "$output")"
umask 077

pg_dump \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file="$output" \
  "$DATABASE_URL"

test -s "$output"
echo "Backup written to $output"
