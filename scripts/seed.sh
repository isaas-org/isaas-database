#!/usr/bin/env bash
# Applies sample catalog data (db/seeds/*.sql) to the database at DATABASE_URL.
#
# This is dev/demo data, not part of the versioned schema release in
# deploy.yml -- it never creates a tag and isn't tracked by dbmate. Every
# insert in db/seeds/ is idempotent (conflicts on the table's natural key),
# so running this twice leaves the same rows in place.
set -euo pipefail

: "${DATABASE_URL:?set DATABASE_URL to the target database}"
cd "$(dirname "$0")/.."

PSQL=(psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1)

for seed_file in db/seeds/[0-9]*.sql; do
    echo "==> $seed_file"
    "${PSQL[@]}" -f "$seed_file"
done

echo "==> done"
"${PSQL[@]}" -A -t -c "SELECT count(*) || ' rows in items.published_catalog' FROM items.published_catalog"
