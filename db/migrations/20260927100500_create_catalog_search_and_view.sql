-- migrate:up

-- Full-text search: weighted name > tagline > description.
ALTER TABLE items.items
    ADD COLUMN search_vector tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english'::regconfig, coalesce(name, '')), 'A') ||
        setweight(to_tsvector('english'::regconfig, coalesce(tagline, '')), 'B') ||
        setweight(to_tsvector('english'::regconfig, coalesce(description, '')), 'C')
    ) STORED;

CREATE INDEX items_search_vector_idx ON items.items USING gin (search_vector);

-- Fuzzy / typo-tolerant name matching ("salesforse" -> "Salesforce").
CREATE INDEX items_name_trgm_idx ON items.items USING gin (name gin_trgm_ops);

-- The browsable catalog. Visibility is decided here, at query time, by
-- joining on the vendor's current status — nothing is cached on items, so
-- suspending a vendor hides its listings immediately with no bulk update.
CREATE VIEW items.published_catalog AS
SELECT
    i.id,
    i.vendor_id,
    i.name,
    i.slug,
    i.tagline,
    i.description,
    i.logo_url,
    i.website_url,
    i.published_at,
    i.avg_rating,
    i.review_count,
    i.search_vector,
    v.company_name AS vendor_name,
    v.slug         AS vendor_slug
FROM items.items i
JOIN vendors.vendors v ON v.id = i.vendor_id
WHERE i.status = 'published'
  AND v.status = 'active';

-- migrate:down

DROP VIEW items.published_catalog;
DROP INDEX items.items_name_trgm_idx;
DROP INDEX items.items_search_vector_idx;
ALTER TABLE items.items DROP COLUMN search_vector;
