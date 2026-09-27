-- Catalog visibility is query-time: published item AND active vendor.

SELECT pg_temp.assert_eq(
    (SELECT array_agg(slug ORDER BY slug) FROM items.published_catalog),
    ARRAY['acme-crm', 'suspendable-tool'],
    'catalog shows only published items of active vendors');

-- Suspending a vendor hides its listings immediately, without touching items.
UPDATE vendors.vendors SET status = 'suspended'
WHERE id = '0a000000-0000-0000-0000-000000000003';

SELECT pg_temp.assert_eq(
    (SELECT array_agg(slug ORDER BY slug) FROM items.published_catalog),
    ARRAY['acme-crm'],
    'suspended vendor''s listings drop out of the catalog');

SELECT pg_temp.assert_eq(
    (SELECT status FROM items.items WHERE slug = 'suspendable-tool'),
    'published'::items.item_status,
    'item row itself is untouched by vendor suspension');

-- Reinstating the vendor brings the listing back with no item writes.
UPDATE vendors.vendors SET status = 'active'
WHERE id = '0a000000-0000-0000-0000-000000000003';

SELECT pg_temp.assert_true(
    EXISTS (SELECT 1 FROM items.published_catalog WHERE slug = 'suspendable-tool'),
    'reinstated vendor''s listing reappears');

-- Draft / archived items are never in the catalog.
UPDATE items.items SET status = 'archived' WHERE slug = 'acme-crm';
SELECT pg_temp.assert_true(
    NOT EXISTS (SELECT 1 FROM items.published_catalog WHERE slug IN ('acme-crm', 'acme-insights')),
    'archived and draft items are hidden');
