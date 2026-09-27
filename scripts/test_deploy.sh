#!/usr/bin/env bash
# Exercises the failure paths of scripts/deploy.sh against a throwaway database,
# using copies of db/migrations plus deliberately good/bad extra migrations.
#
#   TEST_DATABASE_URL  URL of a THROWAWAY database. It is dropped and recreated.
#   DBMATE             dbmate command (default: dbmate)
set -euo pipefail

: "${TEST_DATABASE_URL:?set TEST_DATABASE_URL to a throwaway database URL}"
DBMATE=${DBMATE:-dbmate}
export DBMATE

cd "$(dirname "$0")/.."
export DATABASE_URL="$TEST_DATABASE_URL"
export DBMATE_NO_DUMP_SCHEMA=true

work=$(mktemp -d)
$DBMATE drop >/dev/null 2>&1 || true
$DBMATE --wait create >/dev/null
trap 'rm -rf "$work"; $DBMATE drop >/dev/null 2>&1 || true' EXIT

failed=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; failed=1; }

# Migrations dir = the real migrations + extras named on the command line.
make_dir() {
    local dir="$work/$1"; shift
    cp -R db/migrations "$dir"
    local extra
    for extra in "$@"; do
        case "$extra" in
            good) printf -- '-- migrate:up\nCREATE TABLE public.deploy_probe (id int);\n-- migrate:down\nDROP TABLE public.deploy_probe;\n' \
                      > "$dir/29990101000000_good.sql" ;;
            bad)  printf -- '-- migrate:up\nSELECT 1 / 0;\n-- migrate:down\n' \
                      > "$dir/29990101000100_bad.sql" ;;
            old)  printf -- '-- migrate:up\nSELECT 1;\n-- migrate:down\n' \
                      > "$dir/20000101000000_old.sql" ;;
        esac
    done
    echo "$dir"
}

echo "==> first deploy fails: everything applied in the run is rolled back"
: > "$work/stable_empty.txt"
dir=$(make_dir first good bad)
if DBMATE_MIGRATIONS_DIR=$dir $DBMATE up >/dev/null 2>&1; then
    fail "bad migration should have failed the deploy"
fi
DBMATE_MIGRATIONS_DIR=$dir ./scripts/deploy.sh rollback-to "$work/stable_empty.txt" >/dev/null
[[ -z "$(./scripts/deploy.sh applied)" ]] && pass "no migrations left applied" || fail "migrations left applied"
[[ "$(psql "$DATABASE_URL" -XAtc "SELECT count(*) FROM pg_namespace WHERE nspname IN ('items','vendors','buyer_companies')")" == 0 ]] \
    && pass "domain schemas removed" || fail "domain schemas still present"

echo "==> release on top of a stable version fails: only this run's migrations are rolled back"
$DBMATE up >/dev/null
./scripts/deploy.sh applied > "$work/stable.txt"
dir=$(make_dir release good bad)
if DBMATE_MIGRATIONS_DIR=$dir $DBMATE up >/dev/null 2>&1; then
    fail "bad migration should have failed the deploy"
fi
[[ "$(psql "$DATABASE_URL" -XAtc "SELECT to_regclass('public.deploy_probe') IS NOT NULL")" == t ]] \
    && pass "partial deploy left the good migration applied (the case rollback must handle)" \
    || fail "expected the good migration to be applied before rollback"
DBMATE_MIGRATIONS_DIR=$dir ./scripts/deploy.sh rollback-to "$work/stable.txt" >/dev/null
diff "$work/stable.txt" <(./scripts/deploy.sh applied) >/dev/null \
    && pass "applied versions equal the stable snapshot" || fail "applied versions differ from snapshot"
[[ "$(psql "$DATABASE_URL" -XAtc "SELECT to_regclass('public.deploy_probe') IS NULL")" == t ]] \
    && pass "good migration's objects removed" || fail "deploy_probe table still exists"
[[ "$(psql "$DATABASE_URL" -XAtc "SELECT to_regclass('items.items') IS NOT NULL")" == t ]] \
    && pass "previously live schema untouched" || fail "stable schema was rolled back"

echo "==> out-of-order pending migration is rejected before deploying"
dir=$(make_dir order old)
if DBMATE_MIGRATIONS_DIR=$dir ./scripts/deploy.sh check-order 2>/dev/null; then
    fail "check-order accepted a migration older than the newest applied one"
else
    pass "check-order rejects it"
fi
dir=$(make_dir inorder good)
DBMATE_MIGRATIONS_DIR=$dir ./scripts/deploy.sh check-order && pass "check-order accepts newer migrations" \
    || fail "check-order rejected a valid migration"
[[ "$(DBMATE_MIGRATIONS_DIR=$dir ./scripts/deploy.sh pending)" == 29990101000000 ]] \
    && pass "pending lists only the new migration" || fail "pending list wrong"

echo "==> version bumps"
check_bump() {
    local got; got=$(./scripts/deploy.sh bump "$1" "$2")
    [[ "$got" == "$3" ]] && pass "bump '$1' $2 -> $3" || fail "bump '$1' $2 -> expected $3, got $got"
}
check_bump ""        minor v1.0.0
check_bump v1.2.3    minor v1.3.0
check_bump v1.2.3    patch v1.2.4
check_bump v1.2.3    major v2.0.0
check_bump v1.9.0    minor v1.10.0

if [[ $failed -ne 0 ]]; then
    echo "FAILED"
    exit 1
fi
echo "ALL PASSED"
