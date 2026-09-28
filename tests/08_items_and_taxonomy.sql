-- Pricing plans, features, taxonomy and catalog filtering.

-- Pricing plans ------------------------------------------------------------
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price)
      VALUES (pg_temp.fx('item.acme_crm'), 'Free', 'freemium', 5)$$,
    '23514', 'pricing_plans_freemium_is_free', 'freemium plans are free');

INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price)
VALUES (pg_temp.fx('item.acme_crm'), 'Free', 'freemium', 0);
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price)
      VALUES (pg_temp.fx('item.acme_crm'), 'Free', 'freemium', 0)$$,
    '23505', 'pricing_plans_tier_unique', 'tier unique per item + frequency (NULL frequency included)');

-- Same tier name with a different billing frequency is a separate plan.
INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price, billing_frequency)
VALUES (pg_temp.fx('item.acme_crm'), 'Starter', 'seat', 100.00, 'annual');

SELECT pg_temp.assert_raises(
    $$INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price)
      VALUES (pg_temp.fx('item.acme_crm'), 'Pro', 'seat', 20)$$,
    '23514', 'pricing_plans_paid_has_frequency', 'paid plans need a billing frequency');
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price, billing_frequency)
      VALUES (pg_temp.fx('item.acme_crm'), 'Neg', 'flat', -1, 'monthly')$$,
    '23514', 'pricing_plans_price_check', 'negative price rejected');
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price, billing_frequency, currency)
      VALUES (pg_temp.fx('item.acme_crm'), 'Euro', 'flat', 1, 'monthly', 'eur')$$,
    '23514', 'pricing_plans_currency_check', 'currency must be ISO 4217 uppercase');
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price, billing_frequency, usage_limits)
      VALUES (pg_temp.fx('item.acme_crm'), 'Usage', 'usage', 0.01, 'monthly', '[1, 2]')$$,
    '23514', 'pricing_plans_usage_limits_is_object', 'usage_limits must be a JSON object');
INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price, billing_frequency, usage_limits)
VALUES (pg_temp.fx('item.acme_crm'), 'Usage', 'usage', 0.01, 'monthly', '{"api_calls": 100000}');

-- Features -----------------------------------------------------------------
INSERT INTO items.features (item_id, feature_name, feature_value) VALUES
    (pg_temp.fx('item.acme_crm'),    'sso', 'yes'),
    (pg_temp.fx('item.second_tool'), 'sso', 'no');
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.features (item_id, feature_name) VALUES (pg_temp.fx('item.acme_crm'), 'sso')$$,
    '23505', 'features_item_feature_unique', 'feature listed once per item');
SELECT pg_temp.assert_eq(
    (SELECT array_agg(i.slug || '=' || f.feature_value ORDER BY i.slug)
     FROM items.features f JOIN items.items i ON i.id = f.item_id WHERE f.feature_name = 'sso'),
    ARRAY['acme-crm=yes', 'second-tool=no'], 'features compare across items');

-- Category tree --------------------------------------------------------------
SELECT pg_temp.assert_raises(
    $$UPDATE items.categories SET parent_category_id = id WHERE id = pg_temp.fx('category.crm')$$,
    '23514', 'cycle', 'category cannot parent itself');
UPDATE items.categories SET parent_category_id = pg_temp.fx('category.crm') WHERE id = pg_temp.fx('category.analytics');
SELECT pg_temp.assert_raises(
    $$UPDATE items.categories SET parent_category_id = pg_temp.fx('category.analytics') WHERE id = pg_temp.fx('category.crm')$$,
    '23514', 'cycle', 'A -> B -> A cycle rejected');
SELECT pg_temp.assert_raises(
    $$DELETE FROM items.categories WHERE id = pg_temp.fx('category.crm')$$,
    '23503', 'categories_parent_category_id_fkey', 'parent category with children cannot be deleted');

-- Vendors with listings can't be hard-deleted.
SELECT pg_temp.assert_raises(
    $$DELETE FROM vendors.vendors WHERE id = pg_temp.fx('vendor.active')$$,
    '23001', 'items_vendor_id_fkey', 'vendor with listings cannot be hard-deleted');

-- Addresses ------------------------------------------------------------------
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.addresses (buyer_company_id, type, street, city, country)
      VALUES (pg_temp.fx('company.one'), 'billing', '1 Main St', 'Lansing', 'U1')$$,
    '23514', 'addresses_country_check', 'buyer address country is ISO alpha-2');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_addresses (vendor_id, type, street, city, country)
      VALUES (pg_temp.fx('vendor.active'), 'business', '1 Main St', 'Lansing', 'us')$$,
    '23514', 'vendor_addresses_country_check', 'vendor address country is ISO alpha-2');

-- Junction filtering (the catalog's filter use case) -------------------------
INSERT INTO items.integrations (name, slug) VALUES ('Slack', 'slack');
INSERT INTO items.certifications (name, slug) VALUES ('SOC 2', 'soc-2');
INSERT INTO items.item_integrations (item_id, integration_id)
    SELECT pg_temp.fx('item.acme_crm'), id FROM items.integrations WHERE slug = 'slack';
INSERT INTO items.item_certifications (item_id, certification_id)
    SELECT id, (SELECT id FROM items.certifications WHERE slug = 'soc-2')
    FROM items.items WHERE id IN (pg_temp.fx('item.acme_crm'), pg_temp.fx('item.second_tool'));
INSERT INTO items.item_categories (item_id, category_id) VALUES
    (pg_temp.fx('item.acme_crm'),    pg_temp.fx('category.crm')),
    (pg_temp.fx('item.second_tool'), pg_temp.fx('category.crm'));

SELECT pg_temp.assert_raises(
    $$INSERT INTO items.item_categories (item_id, category_id)
      VALUES (pg_temp.fx('item.acme_crm'), pg_temp.fx('category.crm'))$$,
    '23505', 'item_categories_pkey', 'item listed once per category');

SELECT pg_temp.assert_eq(
    (SELECT array_agg(c.slug) FROM items.published_catalog c
     WHERE EXISTS (SELECT 1 FROM items.item_categories ic JOIN items.categories cat ON cat.id = ic.category_id
                   WHERE ic.item_id = c.id AND cat.slug = 'crm')
       AND EXISTS (SELECT 1 FROM items.item_certifications x JOIN items.certifications ce ON ce.id = x.certification_id
                   WHERE x.item_id = c.id AND ce.slug = 'soc-2')
       AND EXISTS (SELECT 1 FROM items.item_integrations x JOIN items.integrations ig ON ig.id = x.integration_id
                   WHERE x.item_id = c.id AND ig.slug = 'slack')),
    ARRAY['acme-crm'], 'category + certification + integration filter');

-- Deleting an item cleans up its junction rows.
DELETE FROM items.items WHERE id = pg_temp.fx('item.acme_insights');
DELETE FROM items.items WHERE id = pg_temp.fx('item.second_tool');
SELECT pg_temp.assert_eq(
    (SELECT count(*) FROM items.item_categories WHERE item_id = pg_temp.fx('item.second_tool')),
    0::bigint, 'junction rows follow the item');
