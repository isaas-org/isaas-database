-- A subscription records the item AND the chosen plan, and they must agree.

INSERT INTO pg_temp.fixture_ids (name) VALUES ('subscription.one_acme');
INSERT INTO buyer_companies.subscriptions (id, buyer_company_id, item_id, pricing_plan_id, status, seats)
VALUES (pg_temp.fx('subscription.one_acme'), pg_temp.fx('company.one'),
        pg_temp.fx('item.acme_crm'), pg_temp.fx('plan.acme_starter'), 'active', 5);

SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.subscriptions (buyer_company_id, item_id, pricing_plan_id, status)
      VALUES (pg_temp.fx('company.one'), pg_temp.fx('item.acme_crm'), pg_temp.fx('plan.second_pro'), 'active')$$,
    '23503', 'subscriptions_plan_item_fkey', 'plan must belong to the subscribed item');

-- Upgrade within the same item is allowed...
INSERT INTO pg_temp.fixture_ids (name) VALUES ('plan.acme_professional');
INSERT INTO items.pricing_plans (id, item_id, tier_name, pricing_model, price, billing_frequency)
VALUES (pg_temp.fx('plan.acme_professional'), pg_temp.fx('item.acme_crm'), 'Professional', 'seat', 25.00, 'monthly');
UPDATE buyer_companies.subscriptions SET pricing_plan_id = pg_temp.fx('plan.acme_professional')
WHERE id = pg_temp.fx('subscription.one_acme');
SELECT pg_temp.assert_eq(
    (SELECT pricing_plan_id FROM buyer_companies.subscriptions WHERE id = pg_temp.fx('subscription.one_acme')),
    pg_temp.fx('plan.acme_professional'), 'upgrade to another plan of the same item');

-- ...switching to another item's plan is not.
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.subscriptions SET pricing_plan_id = pg_temp.fx('plan.second_pro')
      WHERE id = pg_temp.fx('subscription.one_acme')$$,
    '23503', 'subscriptions_plan_item_fkey', 'cannot switch to a plan of a different item');

SELECT pg_temp.assert_eq(
    (SELECT count(*) FROM buyer_companies.subscriptions
     WHERE item_id = pg_temp.fx('item.acme_crm') AND status = 'active'),
    1::bigint, 'direct lookup by item_id');

-- Shape.
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.subscriptions (buyer_company_id, item_id, pricing_plan_id, status, start_date, end_date)
      VALUES (pg_temp.fx('company.two'), pg_temp.fx('item.acme_crm'), pg_temp.fx('plan.acme_starter'),
              'active', '2026-02-01', '2026-01-01')$$,
    '23514', 'subscriptions_dates_ordered', 'end_date before start_date rejected');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.subscriptions (buyer_company_id, item_id, pricing_plan_id, status, seats)
      VALUES (pg_temp.fx('company.two'), pg_temp.fx('item.acme_crm'), pg_temp.fx('plan.acme_starter'), 'active', 0)$$,
    '23514', 'subscriptions_seats_check', 'zero seats rejected');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.subscriptions (buyer_company_id, item_id, pricing_plan_id, status)
      VALUES (pg_temp.fx('company.two'), pg_temp.fx('item.acme_crm'), pg_temp.fx('plan.acme_starter'), 'paused')$$,
    '22P02', 'invalid input value for enum', 'status limited to trial/active/cancelled');

-- Purchase history can't be deleted out from under subscriptions.
SELECT pg_temp.assert_raises(
    $$DELETE FROM items.pricing_plans WHERE id = pg_temp.fx('plan.acme_professional')$$,
    '23001', 'subscriptions_plan_item_fkey', 'subscribed plan cannot be deleted (retire it instead)');
SELECT pg_temp.assert_raises(
    $$DELETE FROM buyer_companies.buyer_companies WHERE id = pg_temp.fx('company.one')$$,
    '23001', 'subscriptions_buyer_company_id_fkey', 'company with subscriptions cannot be deleted');

-- Retiring works.
UPDATE items.pricing_plans SET is_active = false WHERE id = pg_temp.fx('plan.acme_professional');
