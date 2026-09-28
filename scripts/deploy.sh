#!/usr/bin/env bash
# Release helpers used by .github/workflows/deploy.yml (also runnable locally).
#
#   deploy.sh applied                  applied migration versions, oldest first
#   deploy.sh pending                  versions in the migrations dir not yet applied
#   deploy.sh check-order              fail if a pending migration is older than the newest
#                                      applied one (dbmate would apply it out of order, and
#                                      rollback could no longer undo it)
#   deploy.sh next-version [KIND]      next release tag after the newest vX.Y.Z git tag
#                                      (KIND = major | minor | patch, default minor;
#                                      v1.0.0 if there is no tag yet)
#   deploy.sh bump TAG KIND            pure version bump, e.g. bump v1.2.3 minor -> v1.3.0
#   deploy.sh release-kind             read PR label names (one per line) on stdin and print
#                                      major | minor | patch for the release:* label, or
#                                      nothing if there is none; exit 3 if there are several
#   deploy.sh rollback-to FILE         roll back newest-first until the applied versions
#                                      equal the list in FILE (a snapshot from `applied`)
#
# Env: DATABASE_URL (required for db commands), DBMATE (default: dbmate),
#      DBMATE_MIGRATIONS_DIR (default: db/migrations).
set -euo pipefail

DBMATE=${DBMATE:-dbmate}
MIGRATIONS_DIR=${DBMATE_MIGRATIONS_DIR:-db/migrations}
cd "$(dirname "$0")/.."

psql_q() {
    psql "$DATABASE_URL" -X -A -t -q -v ON_ERROR_STOP=1 -c "$1"
}

applied() {
    if [[ "$(psql_q "SELECT to_regclass('public.schema_migrations') IS NOT NULL")" == t ]]; then
        psql_q "SELECT version FROM public.schema_migrations ORDER BY version"
    fi
}

available() {
    find "$MIGRATIONS_DIR" -maxdepth 1 -name '*.sql' -exec basename {} \; \
        | sed -E 's/^([0-9]+)_.*/\1/' | sort
}

pending() {
    comm -23 <(available) <(applied | sort)
}

check_order() {
    local newest p
    newest=$(applied | tail -n 1)
    [[ -z "$newest" ]] && return 0
    while read -r p; do
        [[ -z "$p" ]] && continue
        if [[ "$p" < "$newest" ]]; then
            echo "pending migration $p is older than the newest applied migration $newest;" \
                 "give it a newer timestamp" >&2
            return 1
        fi
    done < <(pending)
}

bump() {
    local tag=$1 kind=${2:-minor} major minor patch
    if [[ -z "$tag" ]]; then
        echo "v1.0.0"
        return
    fi
    IFS=. read -r major minor patch <<< "${tag#v}"
    case "$kind" in
        major) echo "v$((major + 1)).0.0" ;;
        minor) echo "v${major}.$((minor + 1)).0" ;;
        patch) echo "v${major}.${minor}.$((patch + 1))" ;;
        *) echo "unknown bump kind: $kind" >&2; return 1 ;;
    esac
}

release_kind() {
    local kinds count
    kinds=$(grep -E '^release:(major|minor|patch)$' | sed 's/^release://' | sort -u || true)
    count=$(printf '%s' "$kinds" | grep -c . || true)
    if [[ "$count" -gt 1 ]]; then
        echo "PR has more than one release label: $(echo $kinds)" >&2
        return 3
    fi
    [[ -n "$kinds" ]] && echo "$kinds"
    return 0
}

next_version() {
    local latest
    latest=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1)
    bump "$latest" "${1:-minor}"
}

rollback_to() {
    local target=$1 max_steps newest extra i
    max_steps=$(available | wc -l | tr -d ' ')
    for ((i = 0; i <= max_steps; i++)); do
        extra=$(comm -13 <(sort "$target") <(applied | sort))
        [[ -z "$extra" ]] && break
        newest=$(applied | tail -n 1)
        if ! grep -qx "$newest" <<< "$extra"; then
            echo "cannot roll back: newest applied migration $newest is part of the stable set," \
                 "but these are not: $extra" >&2
            return 1
        fi
        echo "rolling back $newest"
        $DBMATE --no-dump-schema rollback
    done
    if ! diff <(sort "$target" | sed '/^$/d') <(applied | sort) >/dev/null; then
        echo "rollback incomplete: applied versions differ from the stable snapshot" >&2
        diff <(sort "$target" | sed '/^$/d') <(applied | sort) >&2 || true
        return 1
    fi
    echo "schema is back at the stable snapshot ($(sed '/^$/d' "$target" | wc -l | tr -d ' ') migrations)"
}

cmd=${1:-}
shift || true
case "$cmd" in
    applied)      applied ;;
    pending)      pending ;;
    check-order)  check_order ;;
    next-version) next_version "$@" ;;
    bump)         bump "$@" ;;
    release-kind) release_kind ;;
    rollback-to)  rollback_to "$1" ;;
    *) sed -n '2,20p' "$0" >&2; exit 2 ;;
esac
