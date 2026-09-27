-- migrate:up

CREATE TYPE items.item_status AS ENUM ('draft', 'published', 'suspended', 'archived');
CREATE TYPE items.pricing_model AS ENUM ('flat', 'seat', 'usage', 'freemium');
CREATE TYPE items.billing_frequency AS ENUM ('monthly', 'annual');
CREATE TYPE items.media_type AS ENUM ('image', 'video', 'document');

-- ---------------------------------------------------------------------------
-- Taxonomy (operator-managed lookups)
-- ---------------------------------------------------------------------------

-- Self-referencing tree: parent_category_id NULL = top-level category.
CREATE TABLE items.categories (
    id                 uuid PRIMARY KEY DEFAULT uuidv7(),
    parent_category_id uuid REFERENCES items.categories (id),
    name               text NOT NULL,
    slug               text NOT NULL UNIQUE,
    description        text,
    sort_order         integer NOT NULL DEFAULT 0,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT categories_not_own_parent CHECK (parent_category_id <> id)
);
CREATE INDEX categories_parent_category_id_idx ON items.categories (parent_category_id);

-- Reject cycles (A -> B -> A) anywhere in the tree, not just self-parenting.
CREATE FUNCTION items.prevent_category_cycle() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.parent_category_id IS NOT NULL AND EXISTS (
        WITH RECURSIVE ancestors AS (
            SELECT parent_category_id AS id FROM items.categories WHERE id = NEW.parent_category_id
            UNION
            SELECT c.parent_category_id FROM items.categories c JOIN ancestors a ON c.id = a.id
        )
        SELECT 1 FROM ancestors WHERE id = NEW.id
    ) OR NEW.parent_category_id = NEW.id THEN
        RAISE EXCEPTION 'category % would create a cycle in the category tree', NEW.id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER categories_prevent_cycle
    BEFORE INSERT OR UPDATE OF parent_category_id ON items.categories
    FOR EACH ROW EXECUTE FUNCTION items.prevent_category_cycle();

-- Industry taxonomy. Referenced by buyer_companies.buyer_companies.industry_id, and the
-- natural target for a future items.item_industries ("industries served").
CREATE TABLE items.industries (
    id         uuid PRIMARY KEY DEFAULT uuidv7(),
    name       text NOT NULL UNIQUE,
    slug       text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE items.integrations (
    id          uuid PRIMARY KEY DEFAULT uuidv7(),
    name        text NOT NULL UNIQUE,
    slug        text NOT NULL UNIQUE,
    logo_url    text,
    website_url text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE items.certifications (
    id          uuid PRIMARY KEY DEFAULT uuidv7(),
    name        text NOT NULL UNIQUE,
    slug        text NOT NULL UNIQUE,
    description text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Items (the SaaS product listing)
-- ---------------------------------------------------------------------------

CREATE TABLE items.items (
    id           uuid PRIMARY KEY DEFAULT uuidv7(),
    vendor_id    uuid NOT NULL REFERENCES vendors.vendors (id) ON DELETE RESTRICT,
    name         text NOT NULL,
    slug         text NOT NULL UNIQUE,
    tagline      text,
    description  text,
    logo_url     text,
    website_url  text,
    status       items.item_status NOT NULL DEFAULT 'draft',
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    -- Denormalized review aggregates, maintained by triggers on items.reviews.
    avg_rating   numeric(3, 2) CHECK (avg_rating BETWEEN 1 AND 5),
    review_count integer NOT NULL DEFAULT 0 CHECK (review_count >= 0),
    -- Target for composite FKs that must stay within one vendor.
    CONSTRAINT items_id_vendor_key UNIQUE (id, vendor_id),
    CONSTRAINT items_slug_format CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    CONSTRAINT items_published_has_timestamp
        CHECK (status <> 'published' OR published_at IS NOT NULL)
);
CREATE INDEX items_vendor_id_idx ON items.items (vendor_id);
CREATE INDEX items_status_idx ON items.items (status);

-- Publish gate: a listing may only move to 'published' while its vendor is
-- 'active'. (Catalog *visibility* is still decided at query time — a vendor
-- suspended later hides its listings without touching these rows.)
CREATE FUNCTION items.enforce_publish_gate() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_status vendors.vendor_status;
BEGIN
    -- Checked when a row becomes published, and when a published row moves to
    -- another vendor (otherwise a transfer would bypass the gate).
    IF NEW.status = 'published'
       AND (TG_OP = 'INSERT'
            OR OLD.status IS DISTINCT FROM 'published'
            OR OLD.vendor_id IS DISTINCT FROM NEW.vendor_id) THEN
        -- FOR SHARE blocks a concurrent vendor status change until we commit.
        SELECT status INTO v_status
        FROM vendors.vendors WHERE id = NEW.vendor_id
        FOR SHARE;

        IF v_status IS DISTINCT FROM 'active' THEN
            RAISE EXCEPTION 'item % cannot be published: vendor % is %',
                NEW.id, NEW.vendor_id, coalesce(v_status::text, 'missing')
                USING ERRCODE = 'check_violation';
        END IF;

        NEW.published_at := coalesce(NEW.published_at, now());
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER items_enforce_publish_gate
    BEFORE INSERT OR UPDATE OF status, vendor_id ON items.items
    FOR EACH ROW EXECUTE FUNCTION items.enforce_publish_gate();

-- ---------------------------------------------------------------------------
-- Item children
-- ---------------------------------------------------------------------------

CREATE TABLE items.item_categories (
    item_id     uuid NOT NULL REFERENCES items.items (id) ON DELETE CASCADE,
    category_id uuid NOT NULL REFERENCES items.categories (id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (item_id, category_id)
);
CREATE INDEX item_categories_category_id_idx ON items.item_categories (category_id);

CREATE TABLE items.pricing_plans (
    id                uuid PRIMARY KEY DEFAULT uuidv7(),
    item_id           uuid NOT NULL REFERENCES items.items (id) ON DELETE CASCADE,
    tier_name         text NOT NULL,
    pricing_model     items.pricing_model NOT NULL,
    price             numeric(12, 2) NOT NULL CHECK (price >= 0),
    currency          char(3) NOT NULL DEFAULT 'USD' CHECK (currency ~ '^[A-Z]{3}$'),
    billing_frequency items.billing_frequency,
    usage_limits      jsonb,
    -- Plans with subscriptions can't be deleted; retire them instead.
    is_active         boolean NOT NULL DEFAULT true,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pricing_plans_freemium_is_free
        CHECK (pricing_model <> 'freemium' OR price = 0),
    CONSTRAINT pricing_plans_paid_has_frequency
        CHECK (pricing_model = 'freemium' OR billing_frequency IS NOT NULL),
    CONSTRAINT pricing_plans_usage_limits_is_object
        CHECK (usage_limits IS NULL OR jsonb_typeof(usage_limits) = 'object'),
    CONSTRAINT pricing_plans_tier_unique
        UNIQUE NULLS NOT DISTINCT (item_id, tier_name, billing_frequency)
);
CREATE INDEX pricing_plans_item_id_idx ON items.pricing_plans (item_id);
-- Supports price-range filtering in the catalog.
CREATE INDEX pricing_plans_active_price_idx ON items.pricing_plans (price) WHERE is_active;

-- Structured rows (not JSON) so items can be compared/filtered by feature.
CREATE TABLE items.features (
    id            uuid PRIMARY KEY DEFAULT uuidv7(),
    item_id       uuid NOT NULL REFERENCES items.items (id) ON DELETE CASCADE,
    feature_name  text NOT NULL,
    feature_value text,
    description   text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT features_item_feature_unique UNIQUE (item_id, feature_name)
);
CREATE INDEX features_feature_name_idx ON items.features (feature_name);

CREATE TABLE items.item_integrations (
    item_id        uuid NOT NULL REFERENCES items.items (id) ON DELETE CASCADE,
    integration_id uuid NOT NULL REFERENCES items.integrations (id) ON DELETE CASCADE,
    created_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (item_id, integration_id)
);
CREATE INDEX item_integrations_integration_id_idx ON items.item_integrations (integration_id);

CREATE TABLE items.item_certifications (
    item_id          uuid NOT NULL REFERENCES items.items (id) ON DELETE CASCADE,
    certification_id uuid NOT NULL REFERENCES items.certifications (id) ON DELETE CASCADE,
    created_at       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (item_id, certification_id)
);
CREATE INDEX item_certifications_certification_id_idx ON items.item_certifications (certification_id);

CREATE TABLE items.item_media (
    id         uuid PRIMARY KEY DEFAULT uuidv7(),
    item_id    uuid NOT NULL REFERENCES items.items (id) ON DELETE CASCADE,
    media_type items.media_type NOT NULL,
    url        text NOT NULL,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX item_media_item_id_idx ON items.item_media (item_id, sort_order);

CREATE TRIGGER categories_set_updated_at BEFORE UPDATE ON items.categories
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER items_set_updated_at BEFORE UPDATE ON items.items
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER pricing_plans_set_updated_at BEFORE UPDATE ON items.pricing_plans
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER features_set_updated_at BEFORE UPDATE ON items.features
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- migrate:down

DROP TABLE items.item_media;
DROP TABLE items.item_certifications;
DROP TABLE items.item_integrations;
DROP TABLE items.features;
DROP TABLE items.pricing_plans;
DROP TABLE items.item_categories;
DROP TABLE items.items;
DROP FUNCTION items.enforce_publish_gate();
DROP TABLE items.certifications;
DROP TABLE items.integrations;
DROP TABLE items.industries;
DROP TABLE items.categories;
DROP FUNCTION items.prevent_category_cycle();

DROP TYPE items.media_type;
DROP TYPE items.billing_frequency;
DROP TYPE items.pricing_model;
DROP TYPE items.item_status;
