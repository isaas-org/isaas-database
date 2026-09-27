-- Catalog visibility is query-time: item status = 'published' AND vendor status = 'active'.
-- Covers vendors in every status (spec: "test data covering pending/active/suspended vendors")
-- and items in every status.

SELECT pg_temp.assert_eq(
    (SELECT array_agg(slug ORDER BY slug) FROM items.published_catalog),
    ARRAY['acme-crm', 'second-tool'],
    'baseline: only published items of active vendors');

-- Vendor moved back to PENDING: its published listings disappear...
UPDATE vendors.vendors SET status = 'pending' WHERE id = pg_temp.fx('vendor.active');
SELECT pg_temp.assert_eq(
    (SELECT array_agg(slug ORDER BY slug) FROM items.published_catalog),
    ARRAY['second-tool'],
    'pending vendor''s published listing is hidden');
-- ...without any write to the item row.
SELECT pg_temp.assert_eq(
    (SELECT status FROM items.items WHERE id = pg_temp.fx('item.acme_crm')),
    'published'::items.item_status,
    'item row is untouched when its vendor goes pending');

UPDATE vendors.vendors SET status = 'active' WHERE id = pg_temp.fx('vendor.active');
SELECT pg_temp.assert_true(
    EXISTS (SELECT 1 FROM items.published_catalog WHERE slug = 'acme-crm'),
    'listing reappears when the vendor is active again');

-- Vendor SUSPENDED: same behaviour.
UPDATE vendors.vendors SET status = 'suspended' WHERE id = pg_temp.fx('vendor.second');
SELECT pg_temp.assert_eq(
    (SELECT array_agg(slug ORDER BY slug) FROM items.published_catalog),
    ARRAY['acme-crm'],
    'suspended vendor''s published listing is hidden');

UPDATE vendors.vendors SET status = 'active' WHERE id = pg_temp.fx('vendor.second');
SELECT pg_temp.assert_true(
    EXISTS (SELECT 1 FROM items.published_catalog WHERE slug = 'second-tool'),
    'listing reappears when the suspension is lifted');

-- Item-level statuses under an ACTIVE vendor: only 'published' is visible.
UPDATE items.items SET status = 'suspended' WHERE id = pg_temp.fx('item.acme_crm');
SELECT pg_temp.assert_true(
    NOT EXISTS (SELECT 1 FROM items.published_catalog WHERE slug = 'acme-crm'),
    'suspended item hidden even though its vendor is active');

UPDATE items.items SET status = 'archived' WHERE id = pg_temp.fx('item.second_tool');
SELECT pg_temp.assert_true(
    NOT EXISTS (SELECT 1 FROM items.published_catalog WHERE slug = 'second-tool'),
    'archived item hidden');

SELECT pg_temp.assert_true(
    NOT EXISTS (SELECT 1 FROM items.published_catalog WHERE slug IN ('acme-insights', 'pending-product')),
    'draft items hidden');

SELECT pg_temp.assert_eq(
    (SELECT count(*) FROM items.published_catalog), 0::bigint,
    'nothing visible once no item is published');
