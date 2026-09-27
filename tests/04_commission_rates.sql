-- Scopes: vendor-wide (no item, no category), category, or item. One rate per scope.

INSERT INTO vendors.commission_rates (vendor_id, item_id, category_id, rate) VALUES
    (pg_temp.fx('vendor.active'), NULL,                          NULL,                          0.1500),
    (pg_temp.fx('vendor.active'), NULL,                          pg_temp.fx('category.crm'),    0.1200),
    (pg_temp.fx('vendor.active'), pg_temp.fx('item.acme_crm'),   NULL,                          0.1000),
    -- the same scopes for a different vendor are independent
    (pg_temp.fx('vendor.second'), NULL,                          NULL,                          0.2000),
    (pg_temp.fx('vendor.second'), NULL,                          pg_temp.fx('category.crm'),    0.1800);

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, rate) VALUES (pg_temp.fx('vendor.active'), 0.2)$$,
    '23505', 'commission_rates_scope_unique', 'one vendor-wide rate (NULLS NOT DISTINCT)');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, category_id, rate)
      VALUES (pg_temp.fx('vendor.active'), pg_temp.fx('category.crm'), 0.2)$$,
    '23505', 'commission_rates_scope_unique', 'one rate per category');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, item_id, rate)
      VALUES (pg_temp.fx('vendor.active'), pg_temp.fx('item.acme_crm'), 0.2)$$,
    '23505', 'commission_rates_scope_unique', 'one rate per item');

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, item_id, category_id, rate)
      VALUES (pg_temp.fx('vendor.active'), pg_temp.fx('item.acme_insights'), pg_temp.fx('category.analytics'), 0.2)$$,
    '23514', 'commission_rates_single_scope', 'item OR category, not both');

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, item_id, rate)
      VALUES (pg_temp.fx('vendor.pending'), pg_temp.fx('item.acme_crm'), 0.2)$$,
    '23503', 'commission_rates_item_fkey', 'item override must be for the vendor''s own item');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, category_id, rate)
      VALUES (pg_temp.fx('vendor.pending'), uuidv7(), 0.2)$$,
    '23503', 'commission_rates_category_id_fkey', 'category must exist');

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, category_id, rate)
      VALUES (pg_temp.fx('vendor.active'), pg_temp.fx('category.analytics'), 1.5)$$,
    '23514', 'commission_rates_rate_check', 'rate above 100% rejected');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, category_id, rate)
      VALUES (pg_temp.fx('vendor.active'), pg_temp.fx('category.analytics'), -0.01)$$,
    '23514', 'commission_rates_rate_check', 'negative rate rejected');

-- Most-specific-wins resolution works off these rows.
SELECT pg_temp.assert_eq(
    (SELECT rate FROM vendors.commission_rates
     WHERE vendor_id = pg_temp.fx('vendor.active')
       AND (item_id = pg_temp.fx('item.acme_crm')
            OR category_id = pg_temp.fx('category.crm')
            OR (item_id IS NULL AND category_id IS NULL))
     ORDER BY (item_id IS NOT NULL) DESC, (category_id IS NOT NULL) DESC
     LIMIT 1),
    0.1000::numeric(5,4), 'item override beats category and vendor-wide');

-- Item override follows the item.
DELETE FROM items.items WHERE id = pg_temp.fx('item.acme_crm');
SELECT pg_temp.assert_eq(
    (SELECT count(*) FROM vendors.commission_rates WHERE item_id IS NOT NULL), 0::bigint,
    'deleting an item removes its override');
