-- Verification artifacts: submitter must belong to the same company / vendor.
INSERT INTO buyers.buyer_verification_artifacts (buyer_company_id, artifact_type, file_url, submitted_by_user_id)
VALUES ('0e000000-0000-0000-0000-000000000001', 'tax_id', 's3://x/tax.pdf', '0f000000-0000-0000-0000-000000000001');

SELECT pg_temp.assert_raises(
    $$INSERT INTO buyers.buyer_verification_artifacts (buyer_company_id, artifact_type, file_url, submitted_by_user_id)
      VALUES ('0e000000-0000-0000-0000-000000000002', 'tax_id', 's3://x/tax.pdf', '0f000000-0000-0000-0000-000000000001')$$,
    '23503', 'buyer artifact submitter must belong to the company');

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_verification_artifacts (vendor_id, artifact_type, file_url, submitted_by_user_id)
      VALUES ('0a000000-0000-0000-0000-000000000001', 'tax_id', 's3://x/tax.pdf', '0b000000-0000-0000-0000-000000000002')$$,
    '23503', 'vendor artifact submitter must belong to the vendor');

-- A decided artifact must carry reviewed_at, and a pending one must not.
SELECT pg_temp.assert_raises(
    $$UPDATE buyers.buyer_verification_artifacts SET status = 'approved'
      WHERE buyer_company_id = '0e000000-0000-0000-0000-000000000001'$$,
    '23514', 'approval without reviewed_at rejected');
UPDATE buyers.buyer_verification_artifacts SET status = 'approved', reviewed_at = now()
WHERE buyer_company_id = '0e000000-0000-0000-0000-000000000001';

-- One default payment method / payout account.
INSERT INTO buyers.payment_methods (buyer_company_id, type, provider_token, is_default)
VALUES ('0e000000-0000-0000-0000-000000000001', 'card', 'tok_1', true);
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyers.payment_methods (buyer_company_id, type, provider_token, is_default)
      VALUES ('0e000000-0000-0000-0000-000000000001', 'ach', 'tok_2', true)$$,
    '23505', 'only one default payment method per company');
INSERT INTO buyers.payment_methods (buyer_company_id, type, is_default)
VALUES ('0e000000-0000-0000-0000-000000000001', 'purchase_order', false);
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyers.payment_methods (buyer_company_id, type) VALUES ('0e000000-0000-0000-0000-000000000001', 'card')$$,
    '23514', 'card requires a provider token');

INSERT INTO vendors.payout_accounts (vendor_id, type, provider_token, is_default)
VALUES ('0a000000-0000-0000-0000-000000000001', 'bank', 'ba_1', true);
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.payout_accounts (vendor_id, type, provider_token, is_default)
      VALUES ('0a000000-0000-0000-0000-000000000001', 'bank', 'ba_2', true)$$,
    '23505', 'only one default payout account per vendor');

-- Emails are unique case-insensitively.
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyers.buyer_users (buyer_company_id, name, email, role)
      VALUES ('0e000000-0000-0000-0000-000000000002', 'Dup', 'BO@one.test', 'viewer')$$,
    '23505', 'buyer email unique regardless of case');

-- Pricing plan rules.
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price)
      VALUES ('0c000000-0000-0000-0000-000000000001', 'Free', 'freemium', 5)$$,
    '23514', 'freemium plans are free');
INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price)
VALUES ('0c000000-0000-0000-0000-000000000001', 'Free', 'freemium', 0);
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price)
      VALUES ('0c000000-0000-0000-0000-000000000001', 'Free', 'freemium', 0)$$,
    '23505', 'tier names unique per item and frequency (NULL frequency included)');
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price)
      VALUES ('0c000000-0000-0000-0000-000000000001', 'Pro', 'seat', 20)$$,
    '23514', 'paid plans need a billing frequency');
INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price, billing_frequency, usage_limits)
VALUES ('0c000000-0000-0000-0000-000000000001', 'Usage', 'usage', 0.01, 'monthly', '{"api_calls": 100000}');

-- Subscriptions.
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyers.subscriptions (buyer_company_id, pricing_plan_id, status, start_date, end_date)
      VALUES ('0e000000-0000-0000-0000-000000000001', '0d000000-0000-0000-0000-000000000001', 'active', '2026-02-01', '2026-01-01')$$,
    '23514', 'end_date before start_date rejected');

-- Watchlist: one entry per user per item; removed with the user.
INSERT INTO buyers.watchlist (buyer_user_id, item_id)
VALUES ('0f000000-0000-0000-0000-000000000002', '0c000000-0000-0000-0000-000000000001');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyers.watchlist (buyer_user_id, item_id)
      VALUES ('0f000000-0000-0000-0000-000000000002', '0c000000-0000-0000-0000-000000000001')$$,
    '23505', 'duplicate watchlist entry rejected');
DELETE FROM buyers.buyer_users WHERE id = '0f000000-0000-0000-0000-000000000002';
SELECT pg_temp.assert_eq((SELECT count(*) FROM buyers.watchlist), 0::bigint, 'watchlist follows the user');

-- Categories can't be their own parent; vendors with items can't be deleted.
SELECT pg_temp.assert_raises(
    $$UPDATE items.categories SET parent_category_id = id WHERE slug = 'crm'$$,
    '23514', 'category cannot parent itself');
SELECT pg_temp.assert_raises(
    $$DELETE FROM vendors.vendors WHERE id = '0a000000-0000-0000-0000-000000000001'$$,
    '23001', 'vendor with listings cannot be hard-deleted (ON DELETE RESTRICT)');

-- Junctions.
INSERT INTO items.integrations (name, slug) VALUES ('Slack', 'slack');
INSERT INTO items.certifications (name, slug) VALUES ('SOC 2', 'soc-2');
INSERT INTO items.item_integrations (item_id, integration_id)
    SELECT '0c000000-0000-0000-0000-000000000001', id FROM items.integrations WHERE slug = 'slack';
INSERT INTO items.item_certifications (item_id, certification_id)
    SELECT '0c000000-0000-0000-0000-000000000001', id FROM items.certifications WHERE slug = 'soc-2';
INSERT INTO items.item_categories (item_id, category_id)
VALUES ('0c000000-0000-0000-0000-000000000001', '01000000-0000-0000-0000-000000000001');

-- Filter: published CRM items with SOC 2 that integrate with Slack.
SELECT pg_temp.assert_eq(
    (SELECT array_agg(c.slug) FROM items.published_catalog c
     WHERE EXISTS (SELECT 1 FROM items.item_categories ic JOIN items.categories cat ON cat.id = ic.category_id
                   WHERE ic.item_id = c.id AND cat.slug = 'crm')
       AND EXISTS (SELECT 1 FROM items.item_certifications x JOIN items.certifications ce ON ce.id = x.certification_id
                   WHERE x.item_id = c.id AND ce.slug = 'soc-2')
       AND EXISTS (SELECT 1 FROM items.item_integrations x JOIN items.integrations ig ON ig.id = x.integration_id
                   WHERE x.item_id = c.id AND ig.slug = 'slack')),
    ARRAY['acme-crm'], 'category + certification + integration filter');

-- Multi-level category cycles are rejected, not just self-parenting.
UPDATE items.categories SET parent_category_id = '01000000-0000-0000-0000-000000000001'
WHERE slug = 'data-analytics';
SELECT pg_temp.assert_raises(
    $$UPDATE items.categories SET parent_category_id = '01000000-0000-0000-0000-000000000002' WHERE slug = 'crm'$$,
    '23514', 'A -> B -> A category cycle rejected');
