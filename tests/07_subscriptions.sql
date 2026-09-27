-- A subscription records both the item and the chosen plan, and they must agree.
INSERT INTO buyer_companies.subscriptions (id, buyer_company_id, item_id, pricing_plan_id, status, seats) VALUES
    ('0a100000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-000000000001',
     '0c000000-0000-0000-0000-000000000001', '0d000000-0000-0000-0000-000000000001', 'active', 5);

SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.subscriptions (buyer_company_id, item_id, pricing_plan_id, status)
      VALUES ('0e000000-0000-0000-0000-000000000001', '0c000000-0000-0000-0000-000000000001',
              '0d000000-0000-0000-0000-000000000002', 'active')$$,
    '23503', 'plan must belong to the subscribed item');

-- Upgrade within the same item is allowed...
INSERT INTO items.pricing_plans (id, item_id, tier_name, pricing_model, price, billing_frequency)
VALUES ('0d000000-0000-0000-0000-000000000003', '0c000000-0000-0000-0000-000000000001', 'Professional', 'seat', 25.00, 'monthly');
UPDATE buyer_companies.subscriptions SET pricing_plan_id = '0d000000-0000-0000-0000-000000000003'
WHERE id = '0a100000-0000-0000-0000-000000000001';
SELECT pg_temp.assert_eq(
    (SELECT pricing_plan_id FROM buyer_companies.subscriptions WHERE id = '0a100000-0000-0000-0000-000000000001'),
    '0d000000-0000-0000-0000-000000000003'::uuid, 'upgrade to another plan of the same item');

-- ...but switching to another item's plan without changing item_id is not.
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.subscriptions SET pricing_plan_id = '0d000000-0000-0000-0000-000000000002'
      WHERE id = '0a100000-0000-0000-0000-000000000001'$$,
    '23503', 'cannot switch to a plan of a different item');

-- "Who subscribes to item X" needs no join.
SELECT pg_temp.assert_eq(
    (SELECT count(*) FROM buyer_companies.subscriptions
     WHERE item_id = '0c000000-0000-0000-0000-000000000001' AND status = 'active'),
    1::bigint, 'direct lookup by item_id');
