#!/usr/bin/env bash
# Adds a platform staff admin to the database at DATABASE_URL. Used once to
# create the first staff member; after that, staff admins add others through
# the backend. The email is passed in rather than committed, because this
# repo is public.
#
#   DATABASE_URL  target database
#   STAFF_EMAIL   the email the person signs in to Auth0 with (verified)
#   STAFF_NAME    display name
#
# auth_provider_id stays NULL until the person's first login, when the backend
# binds it by verified email. Safe to re-run: an existing email is left as is.
set -euo pipefail

: "${DATABASE_URL:?set DATABASE_URL to the target database}"
: "${STAFF_EMAIL:?set STAFF_EMAIL to the staff member's Auth0 email}"
: "${STAFF_NAME:?set STAFF_NAME to the staff member's display name}"

psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 \
    -v email="$STAFF_EMAIL" -v name="$STAFF_NAME" <<'SQL'
INSERT INTO platform.staff_users (name, email, role)
VALUES (:'name', :'email', 'admin')
ON CONFLICT (lower(email)) DO NOTHING;

\pset format unaligned
\pset tuples_only on
SELECT 'staff: ' || email || ' (' || role || ', ' || status || ')'
FROM platform.staff_users WHERE lower(email) = lower(:'email');
SQL
