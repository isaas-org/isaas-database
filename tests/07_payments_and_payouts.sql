-- Payment methods (buyer) and payout accounts (vendor).

INSERT INTO buyer_companies.payment_methods (buyer_company_id, type, provider_token, is_default) VALUES
    (pg_temp.fx('company.one'), 'card', 'tok_1', true),
    (pg_temp.fx('company.one'), 'ach',  'tok_2', false),        -- non-defaults are unlimited
    (pg_temp.fx('company.two'), 'card', 'tok_3', true);         -- defaults are per company

SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.payment_methods (buyer_company_id, type, provider_token, is_default)
      VALUES (pg_temp.fx('company.one'), 'ach', 'tok_4', true)$$,
    '23505', 'payment_methods_one_default_per_company', 'one default payment method per company');

-- Purchase orders carry no token; cards and ACH must.
INSERT INTO buyer_companies.payment_methods (buyer_company_id, type) VALUES (pg_temp.fx('company.one'), 'purchase_order');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.payment_methods (buyer_company_id, type) VALUES (pg_temp.fx('company.one'), 'card')$$,
    '23514', 'payment_methods_token_required', 'card requires a provider token');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.payment_methods (buyer_company_id, type) VALUES (pg_temp.fx('company.one'), 'ach')$$,
    '23514', 'payment_methods_token_required', 'ACH requires a provider token');

INSERT INTO vendors.payout_accounts (vendor_id, type, provider_token, is_default) VALUES
    (pg_temp.fx('vendor.active'), 'bank', 'ba_1', true),
    (pg_temp.fx('vendor.active'), 'bank', 'ba_2', false),
    (pg_temp.fx('vendor.second'), 'bank', 'ba_3', true);

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.payout_accounts (vendor_id, type, provider_token, is_default)
      VALUES (pg_temp.fx('vendor.active'), 'other', 'ba_4', true)$$,
    '23505', 'payout_accounts_one_default_per_vendor', 'one default payout account per vendor');

-- Switching the default is a two-step update inside one transaction.
UPDATE vendors.payout_accounts SET is_default = false WHERE vendor_id = pg_temp.fx('vendor.active');
UPDATE vendors.payout_accounts SET is_default = true  WHERE provider_token = 'ba_2';
SELECT pg_temp.assert_eq(
    (SELECT provider_token FROM vendors.payout_accounts WHERE vendor_id = pg_temp.fx('vendor.active') AND is_default),
    'ba_2', 'default payout account switched');
