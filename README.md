# isaas-database

Database schema and migrations for the iSaaS marketplace, where buyer companies discover and buy SaaS products from vendors. It runs on **PostgreSQL 18 on Neon** and uses **[dbmate](https://github.com/amacneil/dbmate)** for migrations (plain SQL, independent of any framework).

## Layout

The repo holds one database with one Postgres schema per domain. Cross-domain foreign keys are allowed, and each schema is the boundary to split along if a domain ever needs its own database.

| Schema    | Tables |
|-----------|--------|
| `vendors` | `vendors`, `vendor_users`, `vendor_addresses`, `vendor_verification_artifacts`, `payout_accounts`, `commission_rates` |
| `items`   | `items`, `categories`, `item_categories`, `industries`, `pricing_plans`, `features`, `integrations`, `item_integrations`, `certifications`, `item_certifications`, `item_media`, `reviews`, view `published_catalog` |
| `buyer_companies` | `buyer_companies`, `buyer_users`, `addresses`, `payment_methods`, `buyer_verification_artifacts`, `subscriptions`, `watchlist` |

The migrations run in dependency order:

```
db/migrations/
  20260927100000_create_schemas_and_extensions.sql   schemas, pg_trgm, set_updated_at()
  20260927100100_create_vendors_core.sql
  20260927100200_create_items_core.sql                (depends on vendors)
  20260927100300_create_buyer_companies_core.sql               (depends on items.industries)
  20260927100400_create_cross_domain_tables.sql       subscriptions, watchlist, reviews, commission_rates
  20260927100500_create_catalog_search_and_view.sql   full-text search, trigram index, published_catalog
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

## Release flow

1. Work on a feature branch (e.g. `feature/FD-2`) and open a PR. CI runs the tests.
2. Merge to `main` (done by the repo owner). **That merge is the release.**
3. `.github/workflows/deploy.yml` runs automatically on pushes to `main` that change `db/migrations/`. It only ever deploys from `main`: it:
   1. re-runs the tests;
   2. records the currently applied migration versions, which are the *latest stable version*, and rejects out-of-order migrations;
   3. **creates the next version tag automatically** (`v1.0.0` for the first release, then a minor bump such as `v1.1.0`);
   4. applies the migrations with `dbmate up` and verifies nothing is still pending.
4. **If applying or verifying fails**, the job:
   - rolls back every migration applied during that run, returning the schema exactly to the stable snapshot (migrations that were already live are never touched);
   - **deletes the tag it created**.

   The job summary shows which of these happened.

You can also start a release manually from the Actions tab (`workflow_dispatch`, main only) and choose a `major`, `minor` or `patch` bump. A run with no pending migrations creates no tag.

The release logic lives in `scripts/deploy.sh`. `scripts/test_deploy.sh` runs in CI and exercises the failure paths against a deliberately failing migration: a partial deploy, a first deploy, out-of-order migrations, and version bumps.

Caveat: rollback runs each migration's `-- migrate:down` section, so a down section must genuinely undo its up section. For a destructive change (e.g. dropping a column that holds data), also take a Neon branch snapshot before merging, because a down section can't restore deleted data.

One-time setup: create a GitHub environment called `production` with the secret `NEON_DATABASE_URL`. Use Neon's **direct** connection string (not the `-pooler` host) with `sslmode=require`. Add required reviewers to that environment if you want a manual approval before production migrations.

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

Still deferred, as in the design: `promotions` (featured listings), `payouts`, an internal staff table (`reviewed_by_staff_id` has no FK yet), a `feature_key` normalization table, and "industries served" / "company sizes supported" on items.
