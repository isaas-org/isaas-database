-- Buyer verification is a hard gate: a company can only be 'active' while
-- 'verified', and only an active company can subscribe or add payment methods.

INSERT INTO pg_temp.fixture_ids (name) VALUES ('company.new');
INSERT INTO buyer_companies.buyer_companies (id, name) VALUES (pg_temp.fx('company.new'), 'New Buyer');
SELECT pg_temp.assert_eq(
    (SELECT (status, verification_status)::text FROM buyer_companies.buyer_companies WHERE id = pg_temp.fx('company.new')),
    '(pending,unverified)', 'new buyer company starts pending and unverified');

SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_companies SET status = 'active' WHERE id = pg_temp.fx('company.pending')$$,
    '23514', 'buyer_companies_active_requires_verified', 'unverified company cannot be activated');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_companies (name, status, verification_status)
      VALUES ('Shortcut', 'active', 'unverified')$$,
    '23514', 'buyer_companies_active_requires_verified', 'company cannot be inserted active + unverified');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_companies SET verification_status = 'rejected' WHERE id = pg_temp.fx('company.two')$$,
    '23514', 'buyer_companies_active_requires_verified', 'active company cannot become rejected without leaving active');

-- Subscriptions -----------------------------------------------------------------
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.subscriptions (buyer_company_id, item_id, pricing_plan_id, status)
      VALUES (pg_temp.fx('company.pending'), pg_temp.fx('item.acme_crm'), pg_temp.fx('plan.acme_starter'), 'active')$$,
    '23514', 'subscription cannot start', 'pending company cannot subscribe');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.subscriptions (buyer_company_id, item_id, pricing_plan_id, status)
      VALUES (pg_temp.fx('company.pending'), pg_temp.fx('item.acme_crm'), pg_temp.fx('plan.acme_starter'), 'trial')$$,
    '23514', 'subscription cannot start', 'pending company cannot start a trial');

INSERT INTO pg_temp.fixture_ids (name) VALUES ('subscription.two_acme');
INSERT INTO buyer_companies.subscriptions (id, buyer_company_id, item_id, pricing_plan_id, status)
VALUES (pg_temp.fx('subscription.two_acme'), pg_temp.fx('company.two'),
        pg_temp.fx('item.acme_crm'), pg_temp.fx('plan.acme_starter'), 'active');

SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.subscriptions SET buyer_company_id = pg_temp.fx('company.pending')
      WHERE id = pg_temp.fx('subscription.two_acme')$$,
    '23514', 'subscription cannot start', 'live subscription cannot move to a pending company');

-- Suspending a company keeps its subscriptions, but a cancelled one can't be revived.
UPDATE buyer_companies.subscriptions SET status = 'cancelled' WHERE id = pg_temp.fx('subscription.two_acme');
UPDATE buyer_companies.buyer_companies SET status = 'suspended' WHERE id = pg_temp.fx('company.two');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.subscriptions SET status = 'active' WHERE id = pg_temp.fx('subscription.two_acme')$$,
    '23514', 'subscription cannot start', 'suspended company cannot revive a subscription');

-- Cancelled rows are history and pass the gate.
INSERT INTO buyer_companies.subscriptions (buyer_company_id, item_id, pricing_plan_id, status)
VALUES (pg_temp.fx('company.pending'), pg_temp.fx('item.acme_crm'), pg_temp.fx('plan.acme_starter'), 'cancelled');

-- Payment methods ---------------------------------------------------------------
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.payment_methods (buyer_company_id, type, provider_token)
      VALUES (pg_temp.fx('company.pending'), 'card', 'tok_p')$$,
    '23514', 'payment method cannot be added', 'pending company cannot add a payment method');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.payment_methods (buyer_company_id, type)
      VALUES (pg_temp.fx('company.two'), 'purchase_order')$$,
    '23514', 'payment method cannot be added', 'suspended company cannot add a payment method');

INSERT INTO pg_temp.fixture_ids (name) VALUES ('payment.one_card');
INSERT INTO buyer_companies.payment_methods (id, buyer_company_id, type, provider_token)
VALUES (pg_temp.fx('payment.one_card'), pg_temp.fx('company.one'), 'card', 'tok_1');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.payment_methods SET buyer_company_id = pg_temp.fx('company.pending')
      WHERE id = pg_temp.fx('payment.one_card')$$,
    '23514', 'payment method cannot be added', 'payment method cannot move to a pending company');

-- A pending company's members can still keep a watchlist.
INSERT INTO buyer_companies.watchlist (buyer_user_id, item_id)
VALUES (pg_temp.fx('buyer_user.pending_admin'), pg_temp.fx('item.acme_crm'));

-- Verification doesn't auto-activate; once staff activate, the gates open.
UPDATE buyer_companies.buyer_companies SET verification_status = 'verified' WHERE id = pg_temp.fx('company.pending');
SELECT pg_temp.assert_eq(
    (SELECT status FROM buyer_companies.buyer_companies WHERE id = pg_temp.fx('company.pending')),
    'pending'::buyer_companies.company_status, 'verification does not auto-activate a company');

UPDATE buyer_companies.buyer_companies SET status = 'active' WHERE id = pg_temp.fx('company.pending');
INSERT INTO buyer_companies.subscriptions (buyer_company_id, item_id, pricing_plan_id, status)
VALUES (pg_temp.fx('company.pending'), pg_temp.fx('item.acme_crm'), pg_temp.fx('plan.acme_starter'), 'trial');
INSERT INTO buyer_companies.payment_methods (buyer_company_id, type, provider_token)
VALUES (pg_temp.fx('company.pending'), 'card', 'tok_p');
