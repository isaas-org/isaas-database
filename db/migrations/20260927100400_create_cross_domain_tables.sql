-- migrate:up

-- Tables whose FKs span domains. Migrated after all three domains' core
-- tables exist.

-- ---------------------------------------------------------------------------
-- buyers.subscriptions  (buyer company -> item pricing plan)
-- ---------------------------------------------------------------------------

CREATE TYPE buyers.subscription_status AS ENUM ('trial', 'active', 'cancelled');

CREATE TABLE buyers.subscriptions (
    id               uuid PRIMARY KEY DEFAULT uuidv7(),
    buyer_company_id uuid NOT NULL REFERENCES buyers.buyer_companies (id) ON DELETE RESTRICT,
    pricing_plan_id  uuid NOT NULL REFERENCES items.pricing_plans (id) ON DELETE RESTRICT,
    status           buyers.subscription_status NOT NULL,
    start_date       date NOT NULL DEFAULT current_date,
    end_date         date,
    seats            integer CHECK (seats > 0),
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT subscriptions_dates_ordered CHECK (end_date IS NULL OR end_date >= start_date)
);
CREATE INDEX subscriptions_buyer_company_id_idx ON buyers.subscriptions (buyer_company_id, status);
CREATE INDEX subscriptions_pricing_plan_id_idx ON buyers.subscriptions (pricing_plan_id);

CREATE TRIGGER subscriptions_set_updated_at BEFORE UPDATE ON buyers.subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- buyers.watchlist  (owned by the individual user, not the company)
-- ---------------------------------------------------------------------------

CREATE TABLE buyers.watchlist (
    id            uuid PRIMARY KEY DEFAULT uuidv7(),
    buyer_user_id uuid NOT NULL REFERENCES buyers.buyer_users (id) ON DELETE CASCADE,
    item_id       uuid NOT NULL REFERENCES items.items (id) ON DELETE CASCADE,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT watchlist_user_item_unique UNIQUE (buyer_user_id, item_id)
);
CREATE INDEX watchlist_item_id_idx ON buyers.watchlist (item_id);

-- ---------------------------------------------------------------------------
-- items.reviews  (company drives "verified purchase", user is the author)
-- ---------------------------------------------------------------------------

CREATE TABLE items.reviews (
    id                   uuid PRIMARY KEY DEFAULT uuidv7(),
    item_id              uuid NOT NULL REFERENCES items.items (id) ON DELETE CASCADE,
    buyer_company_id     uuid NOT NULL REFERENCES buyers.buyer_companies (id) ON DELETE CASCADE,
    buyer_user_id        uuid NOT NULL,
    rating               smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
    body                 text,
    -- Set by trigger at creation; any client-supplied value is overwritten.
    is_verified_purchase boolean NOT NULL DEFAULT false,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    -- The author must belong to the reviewing company.
    CONSTRAINT reviews_author_fkey
        FOREIGN KEY (buyer_user_id, buyer_company_id)
        REFERENCES buyers.buyer_users (id, buyer_company_id) ON DELETE CASCADE,
    -- One review per user per item.
    CONSTRAINT reviews_item_user_unique UNIQUE (item_id, buyer_user_id)
);
CREATE INDEX reviews_item_id_idx ON items.reviews (item_id, created_at DESC);
CREATE INDEX reviews_buyer_company_id_idx ON items.reviews (buyer_company_id);
CREATE INDEX reviews_author_idx ON items.reviews (buyer_user_id, buyer_company_id);

-- Verified purchase = the company has (or had) a paid subscription to any plan
-- of this item. Trials don't count. Frozen after creation, and the review's
-- item/company are immutable so the flag can't be carried elsewhere.
CREATE FUNCTION items.set_review_verified_purchase() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND (NEW.item_id IS DISTINCT FROM OLD.item_id
                             OR NEW.buyer_company_id IS DISTINCT FROM OLD.buyer_company_id) THEN
        -- Moving a review would carry its verified flag to an unpurchased item.
        RAISE EXCEPTION 'reviews cannot be moved to another item or company'
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'INSERT' THEN
        NEW.is_verified_purchase := EXISTS (
            SELECT 1
            FROM buyers.subscriptions s
            JOIN items.pricing_plans p ON p.id = s.pricing_plan_id
            WHERE s.buyer_company_id = NEW.buyer_company_id
              AND p.item_id = NEW.item_id
              AND s.status IN ('active', 'cancelled')
        );
    ELSE
        NEW.is_verified_purchase := OLD.is_verified_purchase;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER reviews_set_verified_purchase
    BEFORE INSERT OR UPDATE ON items.reviews
    FOR EACH ROW EXECUTE FUNCTION items.set_review_verified_purchase();

-- Keep items.avg_rating / review_count in sync. Recomputes rather than
-- increments so it is always exact.
CREATE FUNCTION items.refresh_item_rating(p_item_id uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    -- Lock first, then aggregate in a separate statement: the aggregate then
    -- runs with a fresh snapshot that includes any concurrent review whose
    -- transaction held this lock before us. NO KEY UPDATE (not UPDATE) so it
    -- doesn't conflict with the FOR KEY SHARE locks FK checks take on the item
    -- — FOR UPDATE deadlocks concurrent review inserts.
    PERFORM 1 FROM items.items WHERE id = p_item_id FOR NO KEY UPDATE;

    UPDATE items.items i
    SET avg_rating   = agg.avg_rating,
        review_count = agg.review_count
    FROM (
        SELECT round(avg(rating), 2) AS avg_rating, count(*)::integer AS review_count
        FROM items.reviews
        WHERE item_id = p_item_id
    ) agg
    WHERE i.id = p_item_id;
END;
$$;

CREATE FUNCTION items.reviews_refresh_item_rating() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    -- item_id is immutable (see set_review_verified_purchase), so one item per row.
    IF TG_OP = 'DELETE' THEN
        PERFORM items.refresh_item_rating(OLD.item_id);
    ELSE
        PERFORM items.refresh_item_rating(NEW.item_id);
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER reviews_refresh_item_rating
    AFTER INSERT OR UPDATE OF rating OR DELETE ON items.reviews
    FOR EACH ROW EXECUTE FUNCTION items.reviews_refresh_item_rating();

CREATE TRIGGER reviews_set_updated_at BEFORE UPDATE ON items.reviews
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- vendors.commission_rates
-- ---------------------------------------------------------------------------
-- Scope resolution (most specific wins): item -> category -> vendor-wide ->
-- platform default (application config, not a row).

CREATE TABLE vendors.commission_rates (
    id          uuid PRIMARY KEY DEFAULT uuidv7(),
    vendor_id   uuid NOT NULL REFERENCES vendors.vendors (id) ON DELETE CASCADE,
    item_id     uuid,
    category_id uuid REFERENCES items.categories (id) ON DELETE CASCADE,
    rate        numeric(5, 4) NOT NULL CHECK (rate >= 0 AND rate <= 1), -- 0.1500 = 15%
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    -- An item override must be for one of this vendor's own items.
    CONSTRAINT commission_rates_item_fkey
        FOREIGN KEY (item_id, vendor_id)
        REFERENCES items.items (id, vendor_id) ON DELETE CASCADE,
    CONSTRAINT commission_rates_single_scope CHECK (num_nonnulls(item_id, category_id) <= 1),
    -- One rate per scope; NULLS NOT DISTINCT makes the vendor-wide row unique too.
    CONSTRAINT commission_rates_scope_unique
        UNIQUE NULLS NOT DISTINCT (vendor_id, item_id, category_id)
);
CREATE INDEX commission_rates_category_id_idx ON vendors.commission_rates (category_id);
CREATE INDEX commission_rates_item_id_idx ON vendors.commission_rates (item_id, vendor_id);

CREATE TRIGGER commission_rates_set_updated_at BEFORE UPDATE ON vendors.commission_rates
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- migrate:down

DROP TABLE vendors.commission_rates;

DROP TABLE items.reviews;
DROP FUNCTION items.reviews_refresh_item_rating();
DROP FUNCTION items.refresh_item_rating(uuid);
DROP FUNCTION items.set_review_verified_purchase();

DROP TABLE buyers.watchlist;

DROP TABLE buyers.subscriptions;
DROP TYPE buyers.subscription_status;
