# isaas-database

Database schema and migrations for the iSaaS marketplace, where buyer companies discover and buy SaaS products from vendors. It runs on **PostgreSQL 18 on Neon** and uses **[dbmate](https://github.com/amacneil/dbmate)** for migrations (plain SQL, independent of any framework).

## Layout

The repo holds one database with one Postgres schema per domain. Cross-domain foreign keys are allowed, and each schema is the boundary to split along if a domain ever needs its own database.

| Schema    | Tables |
|-----------|--------|
| `vendors` | `vendors`, `vendor_users`, `vendor_addresses`, `vendor_verification_artifacts`, `payout_accounts`, `commission_rates`, `vendor_join_requests`, `vendor_access_tokens` |
| `items`   | `items`, `categories`, `item_categories`, `industries`, `pricing_plans`, `features`, `integrations`, `item_integrations`, `certifications`, `item_certifications`, `item_media`, `reviews`, view `published_catalog` |
| `buyer_companies` | `buyer_companies`, `buyer_users`, `addresses`, `payment_methods`, `buyer_verification_artifacts`, `subscriptions`, `watchlist`, `buyer_join_requests`, `buyer_access_tokens` |
| `platform` | `staff_users` (marketplace staff, who review verification) |

The migrations run in dependency order:

```
db/migrations/
  20260927100000_create_schemas_and_extensions.sql   schemas, pg_trgm, set_updated_at()
  20260927100100_create_vendors_core.sql
  20260927100200_create_items_core.sql                (depends on vendors)
  20260927100300_create_buyer_companies_core.sql               (depends on items.industries)
  20260927100400_create_cross_domain_tables.sql       subscriptions, watchlist, reviews, commission_rates
  20260927100500_create_catalog_search_and_view.sql   full-text search, trigram index, published_catalog
  20261018200000_create_platform_staff.sql             platform schema, staff_users
  20261018200100_add_identity_and_verification_columns.sql   auth_provider_id, user status, SSO, verified_at
  20261018200200_add_pending_status_and_authority_artifacts.sql   new enum values only
  20261018200300_gate_buyer_company_activation.sql     buyer company, subscription and payment gates
  20261018200400_create_join_requests.sql
  20261018200500_create_access_tokens.sql
```

## Rules enforced by the database

| Rule | How |
|------|-----|
| A vendor can only be `active` while `verified` (KYB is a hard gate) | CHECK `vendors_active_requires_verified` |
| A listing can only become `published` (or, once published, move to another vendor) while that vendor is `active` | trigger `items.enforce_publish_gate` (also stamps `published_at`) |
| The catalog shows published items from active vendors only | view `items.published_catalog`. Visibility is decided at query time, so suspending a vendor hides its listings without updating any item rows |
| `reviews.is_verified_purchase` can't be forged | trigger sets it at insert (paid subscription to any of the item's plans; trials don't count) and freezes it afterwards; a review's `item_id` / `buyer_company_id` can't be changed |
| `items.avg_rating` / `review_count` stay exact | trigger on `reviews` recomputes the values under a `FOR NO KEY UPDATE` row lock (checked with 16 concurrent clients: no deadlocks, exact counts) |
| The category tree has no cycles | trigger `items.prevent_category_cycle` |
| A review author or artifact submitter belongs to the company/vendor named on the row | composite FKs to `(id, buyer_company_id)` / `(id, vendor_id)` |
| An item-level commission override is for the vendor's own item | composite FK to `items (id, vendor_id)` |
| A subscription stores its `item_id` and `pricing_plan_id`, and the plan always belongs to that item (upgrades/downgrades stay within the item) | composite FK to `pricing_plans (id, item_id)` |
| A commission rate has one scope (item, category, or vendor-wide), and each scope has one rate | CHECK `num_nonnulls(...) <= 1` + `UNIQUE NULLS NOT DISTINCT` |
| A company or vendor has at most one default payment method / payout account | partial unique indexes `WHERE is_default` |
| A subscribed plan can't be deleted (retire it with `is_active = false`) | `ON DELETE RESTRICT` |
| A decided verification artifact has `reviewed_at`; a pending one doesn't | CHECK |
| A buyer company can only be `active` while `verified`, and starts `pending` | CHECK `buyer_companies_active_requires_verified` |
| Only an `active` buyer company can start a trial or paid subscription, or add a payment method | triggers `buyer_companies.enforce_subscription_gate`, `enforce_payment_method_gate` |
| A company is `verified` exactly when it has `verified_at`; only a verified company has a verifier or an SSO connection | trigger `public.stamp_verified_at` (stamps and clears) + CHECKs |
| Verification artifacts and verified companies are reviewed by real staff, who can't be deleted while referenced | FKs to `platform.staff_users` |
| One Auth0 identity per row in `vendor_users`, `buyer_users` and `staff_users` | UNIQUE `auth_provider_id` (NULL until first login) |
| Join requests and SSO provisioning only reach an `active` company; an admin invite also works while pending | triggers `vendors.enforce_join_request_gate`, `buyer_companies.enforce_join_request_gate` |
| A join request's path, reviewer and decision agree (SSO and invites are approved at once; invites name the inviting admin, who belongs to the company) | CHECKs `*_join_requests_path_rules`, `*_reviewed_when_decided`, composite FK to the users table |
| One open join request per person per company | partial unique index `WHERE status = 'pending'` |
| An access token belongs to a member of the company it acts for, stores only a SHA-256 hash, and lives at most 90 days | composite FK + CHECKs |

Commission resolution goes most-specific first: item → category → vendor-wide → platform default. The platform default lives in application config, not in a table row.

## Local development

```bash
brew install dbmate            # or: npx --yes dbmate@2 <command>
cp .env.example .env           # dbmate reads DATABASE_URL from .env
docker compose up -d           # Postgres 18 on localhost:55432

dbmate up                      # apply pending migrations
dbmate status
dbmate rollback                # undo the latest migration
dbmate new add_promotions      # create db/migrations/<timestamp>_add_promotions.sql
```

### Tests

```bash
TEST_DATABASE_URL='postgres://postgres:postgres@localhost:55432/isaas_test?sslmode=disable' ./scripts/test.sh
# with npx instead of an installed dbmate:
DBMATE='npx --yes dbmate@2' TEST_DATABASE_URL=... ./scripts/test.sh
```

`scripts/test.sh` drops and recreates the test database, then:
1. applies every migration;
2. runs each `tests/NN_*.sql` against shared fixtures inside a transaction that is rolled back afterwards;
3. rolls back every migration and checks that nothing is left behind (schemas, `public` objects, extensions);
4. migrates up again and re-runs the tests.

Writing tests:
- Refer to fixture rows by name, e.g. `pg_temp.fx('vendor.pending')`. The names are listed at the top of `tests/_fixtures.sql`. To add your own, insert a name into `pg_temp.fixture_ids` and use `pg_temp.fx(...)` as the row's `id`.
- A negative test must name what should reject the statement: `pg_temp.assert_raises(stmt, sqlstate, '<constraint or index name>', message)`. For errors raised by a trigger, give a substring of the error message instead. This means a test can't pass because a *different* constraint with the same SQLSTATE happened to fire.
- `tests/11_enum_vocabulary.sql` pins every status and role value list. Adding or changing an enum value must update that file too.
- A new rule needs a test that fails when the rule is removed. Check this by dropping the constraint in a scratch database and running the test file.

CI (`.github/workflows/test.yml`) runs the same script against a `postgres:18` service container on every PR and every push to `feature/**`.

## Seed data

`db/seeds/` holds sample catalog data (vendors, items, pricing plans, taxonomy) for development and demos. It's not part of the schema and isn't tracked by dbmate or the release flow below -- every insert conflicts on the table's natural key, so it's safe to re-run.

```bash
DATABASE_URL=... ./scripts/seed.sh    # local or Neon branch
```

- `05_buyer_companies.sql`: two active buyer companies and one pending (Fernway Logistics).
- `06_test_users.sql`: one member per role for login testing, matching the Auth0 test users in `isaas-auth0-config`. Test data only; leave it out of any production database.
- `07_verification_requests.sql`: pending documents for Cascade Labs and Fernway Logistics, for trying staff review.

Against production Neon, run the **seed** workflow manually from the Actions tab (`workflow_dispatch`). It reuses the `production` environment's `NEON_DATABASE_URL` secret and required reviewers, same as `deploy.yml`, but creates no tag.

## Staff bootstrap

The first platform staff admin is added by script, so their email is never committed:

```bash
DATABASE_URL=... STAFF_EMAIL=you@example.com STAFF_NAME='Your Name' ./scripts/bootstrap_staff.sh
```

Use the email you sign in to Auth0 with. The backend binds `auth_provider_id` on your first login. Later staff are added through the backend.

## Release flow

1. Work on a feature branch (e.g. `feature/FD-2`) and open a PR. CI runs the tests.
2. If the PR changes `db/migrations/`, give it **exactly one** release label. The `release-label` check fails until it has one.

   | Label | When to use it | Example |
   |-------|----------------|---------|
   | `release:major` | Breaking change for code reading the DB | drop or rename a column, table or enum value |
   | `release:minor` | Additive change | new table, nullable column, enum value |
   | `release:patch` | No structural change | index, comment, trigger fix |

3. Merge to `main` (done by the repo owner). `.github/workflows/deploy.yml` then runs, only ever from `main`:
   - **test**: re-runs the test suite.
   - **plan**: reads the merged PR's release label (it defaults to `minor` if there is none) and writes the planned release to the run summary: the version (the first release is `v1.0.0`), the previous release and the new migrations.
   - **migrate**: **waits for your approval** (the `production` environment's required reviewers). It then:
     1. records the currently applied migrations, which are the *latest stable version*;
     2. creates the tag;
     3. applies the migrations with `dbmate up`;
     4. verifies nothing is still pending.
4. **Wrong version in the plan?** Reject the paused job, change the label on the (already merged) PR, and click **Re-run all jobs**. The plan job fetches labels live, so it picks up the change.
5. **If applying or verifying fails**, `migrate`:
   - rolls back every migration applied during that run, returning the schema exactly to the stable snapshot (migrations that were already live are never touched);
   - **deletes the tag it created**.

You can also start a release manually from the Actions tab (`workflow_dispatch`, main only). The bump you choose there overrides the label. A run with no pending migrations creates no tag.

The release logic lives in `scripts/deploy.sh`. `scripts/test_deploy.sh` runs in CI and exercises the failure paths against a deliberately failing migration: a partial deploy, a first deploy, out-of-order migrations, version bumps and label parsing.

One-time setup: in Settings → Environments → `production`:
- add the secret `NEON_DATABASE_URL`. Use Neon's **direct** connection string (not the `-pooler` host) with `sslmode=require`;
- add yourself under **Required reviewers**, which is what makes `migrate` wait for approval. Leave "Prevent self-review" unchecked if you're the only reviewer.

Caveat: rollback runs each migration's `-- migrate:down` section, so a down section must genuinely undo its up section. For a destructive change (e.g. dropping a column that holds data), also take a Neon branch snapshot before merging, because a down section can't restore deleted data.

To try a change against real Neon first, create a Neon branch, point `DATABASE_URL` at it and run `dbmate up`.

**Migrations are append-only once released.** Never edit a migration that has been applied to Neon. Add a new one instead.

## Additions to the design document

These were filled in during implementation and are not in the original design doc:

- **Primary keys** are `uuid DEFAULT uuidv7()`. These IDs are time-ordered, so indexes stay compact, and they stay unique across domains if one is later split into its own database.
- **`items.industries`** is a lookup table for `buyer_companies.industry_id`, which the design referenced but never defined. It lives in the `items` schema next to the rest of the taxonomy, ready for a future "industries served" junction table.
- **`pricing_plans`** gains `currency` (default `USD`) and `is_active` (plans that have subscriptions are retired rather than deleted). `billing_frequency` is `monthly | annual` and may be NULL only for freemium plans. `usage_limits` is `jsonb`.
- **`features`** has both `feature_value` and `description`.
- **`payment_methods.type`** is `card | ach | purchase_order`. Purchase orders carry no provider token.
- **`created_at` / `updated_at`** are on every mutable table, and a shared trigger maintains `updated_at`.
- **Search**: `items.search_vector` is a generated, weighted `tsvector` over name, tagline and description, with a GIN index. A `pg_trgm` index on `name` supports typo-tolerant matching.
- **Emails** are unique case-insensitively within `buyer_users` and within `vendor_users`.
- **Hard deletes** are restricted wherever audit history matters: a vendor that has items, or a plan that has subscriptions, can't be deleted. Use status fields instead.

Still deferred, as in the design: `promotions` (featured listings), `payouts`, a `feature_key` normalization table, and "industries served" / "company sizes supported" on items.

Buyer verification was originally optional and triggered. Since FD-8 it is a hard gate, like vendor KYB: a buyer company starts `pending` and can only buy once staff verify it.
