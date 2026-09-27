#!/usr/bin/env bash
# Migration + constraint test suite.
#
#   TEST_DATABASE_URL  URL of a THROWAWAY database. It is dropped and recreated.
#   DBMATE             dbmate command (default: dbmate), e.g. "npx --yes dbmate@2"
#
# Steps: create db -> migrate up -> run tests/NN_*.sql (each in its own
# rolled-back transaction) -> roll back every migration -> check nothing is
# left behind -> migrate up again -> drop db.
set -euo pipefail

: "${TEST_DATABASE_URL:?set TEST_DATABASE_URL to a throwaway database URL}"
DBMATE=${DBMATE:-dbmate}

cd "$(dirname "$0")/.."
export DATABASE_URL="$TEST_DATABASE_URL"
export DBMATE_NO_DUMP_SCHEMA=true

PSQL=(psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1)
# Test files: discard result rows, keep errors.
PSQL_TEST=("${PSQL[@]}" -o /dev/null)

$DBMATE drop >/dev/null 2>&1 || true
$DBMATE --wait create
trap '$DBMATE drop >/dev/null 2>&1 || true' EXIT

echo "==> migrate up"
$DBMATE up

echo "==> tests"
failed=0
for test_file in tests/[0-9]*.sql; do
    if output=$("${PSQL_TEST[@]}" \
            -c 'BEGIN' \
            -f tests/_helpers.sql \
            -f tests/_fixtures.sql \
            -f "$test_file" \
            -c 'ROLLBACK' 2>&1); then
        echo "  PASS  $test_file"
    else
        echo "  FAIL  $test_file"
        echo "$output" | sed 's/^/        /'
        failed=1
    fi
done

echo "==> roll back every migration"
migration_count=$(find db/migrations -name '*.sql' | wc -l | tr -d ' ')
for _ in $(seq "$migration_count"); do
    $DBMATE rollback
done

leftovers=$("${PSQL[@]}" -At -c "
    SELECT string_agg(nspname, ', ') FROM pg_namespace WHERE nspname IN ('items', 'buyers', 'vendors')
")
if [[ -n "$leftovers" ]]; then
    echo "  FAIL  schemas left after full rollback: $leftovers"
    failed=1
else
    echo "  PASS  full rollback leaves no domain schemas"
fi

echo "==> migrate up again (round trip)"
$DBMATE up

if [[ $failed -ne 0 ]]; then
    echo "FAILED"
    exit 1
fi
echo "ALL PASSED"
