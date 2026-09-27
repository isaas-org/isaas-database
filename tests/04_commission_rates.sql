-- Vendor-wide, category-scoped and item-scoped rates can coexist.
INSERT INTO vendors.commission_rates (vendor_id, item_id, category_id, rate) VALUES
    ('0a000000-0000-0000-0000-000000000001', NULL, NULL, 0.1500),
    ('0a000000-0000-0000-0000-000000000001', NULL, '01000000-0000-0000-0000-000000000001', 0.1200),
    ('0a000000-0000-0000-0000-000000000001', '0c000000-0000-0000-0000-000000000001', NULL, 0.1000);

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, rate)
      VALUES ('0a000000-0000-0000-0000-000000000001', 0.2)$$,
    '23505', 'only one vendor-wide rate (NULLS NOT DISTINCT)');

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, item_id, rate)
      VALUES ('0a000000-0000-0000-0000-000000000001', '0c000000-0000-0000-0000-000000000001', 0.2)$$,
    '23505', 'only one rate per item');

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, item_id, category_id, rate)
      VALUES ('0a000000-0000-0000-0000-000000000001', '0c000000-0000-0000-0000-000000000002',
              '01000000-0000-0000-0000-000000000002', 0.2)$$,
    '23514', 'a rate is scoped to an item OR a category, not both');

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, item_id, rate)
      VALUES ('0a000000-0000-0000-0000-000000000002', '0c000000-0000-0000-0000-000000000001', 0.2)$$,
    '23503', 'item override must be for the vendor''s own item');

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.commission_rates (vendor_id, category_id, rate)
      VALUES ('0a000000-0000-0000-0000-000000000001', '01000000-0000-0000-0000-000000000002', 1.5)$$,
    '23514', 'rate must be within 0..1');

-- Most-specific-wins resolution works off these rows.
SELECT pg_temp.assert_eq(
    (SELECT rate FROM vendors.commission_rates
     WHERE vendor_id = '0a000000-0000-0000-0000-000000000001'
       AND (item_id = '0c000000-0000-0000-0000-000000000001'
            OR category_id = '01000000-0000-0000-0000-000000000001'
            OR (item_id IS NULL AND category_id IS NULL))
     ORDER BY (item_id IS NOT NULL) DESC, (category_id IS NOT NULL) DESC
     LIMIT 1),
    0.1000::numeric(5,4), 'item override beats category and vendor-wide');
