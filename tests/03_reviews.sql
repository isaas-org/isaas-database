-- Buyer One has an active subscription to Acme CRM; Buyer Two only a trial.
INSERT INTO buyers.subscriptions (buyer_company_id, pricing_plan_id, status, seats) VALUES
    ('0e000000-0000-0000-0000-000000000001', '0d000000-0000-0000-0000-000000000001', 'active', 5),
    ('0e000000-0000-0000-0000-000000000002', '0d000000-0000-0000-0000-000000000001', 'trial',  NULL);

-- Verified purchase is computed, and a client-supplied value is ignored.
INSERT INTO items.reviews (item_id, buyer_company_id, buyer_user_id, rating, body, is_verified_purchase) VALUES
    ('0c000000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-000000000001',
     '0f000000-0000-0000-0000-000000000001', 5, 'Great', false),
    ('0c000000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-000000000002',
     '0f000000-0000-0000-0000-000000000003', 2, 'Meh', true);

SELECT pg_temp.assert_eq(
    (SELECT is_verified_purchase FROM items.reviews WHERE buyer_user_id = '0f000000-0000-0000-0000-000000000001'),
    true, 'subscriber''s review is verified even if client sent false');

SELECT pg_temp.assert_eq(
    (SELECT is_verified_purchase FROM items.reviews WHERE buyer_user_id = '0f000000-0000-0000-0000-000000000003'),
    false, 'trial-only buyer cannot forge verified=true');

-- Verification is frozen after creation.
UPDATE items.reviews SET is_verified_purchase = true, body = 'edited'
WHERE buyer_user_id = '0f000000-0000-0000-0000-000000000003';
SELECT pg_temp.assert_eq(
    (SELECT is_verified_purchase FROM items.reviews WHERE buyer_user_id = '0f000000-0000-0000-0000-000000000003'),
    false, 'verified flag cannot be changed by update');

-- Aggregates maintained on insert / update / delete.
SELECT pg_temp.assert_eq(
    (SELECT (avg_rating, review_count)::text FROM items.items WHERE id = '0c000000-0000-0000-0000-000000000001'),
    '(3.50,2)', 'aggregates after two reviews');

UPDATE items.reviews SET rating = 4 WHERE buyer_user_id = '0f000000-0000-0000-0000-000000000003';
SELECT pg_temp.assert_eq(
    (SELECT avg_rating FROM items.items WHERE id = '0c000000-0000-0000-0000-000000000001'),
    4.50::numeric(3,2), 'aggregates after rating update');

DELETE FROM items.reviews;
SELECT pg_temp.assert_eq(
    (SELECT (avg_rating, review_count)::text FROM items.items WHERE id = '0c000000-0000-0000-0000-000000000001'),
    '(,0)', 'aggregates reset after all reviews deleted');

-- The author must belong to the reviewing company.
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.reviews (item_id, buyer_company_id, buyer_user_id, rating)
      VALUES ('0c000000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-000000000002',
              '0f000000-0000-0000-0000-000000000001', 5)$$,
    '23503', 'user from company One cannot review on behalf of company Two');

-- One review per user per item; ratings bounded.
INSERT INTO items.reviews (item_id, buyer_company_id, buyer_user_id, rating)
VALUES ('0c000000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-000000000001',
        '0f000000-0000-0000-0000-000000000002', 3);
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.reviews (item_id, buyer_company_id, buyer_user_id, rating)
      VALUES ('0c000000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-000000000001',
              '0f000000-0000-0000-0000-000000000002', 4)$$,
    '23505', 'duplicate review rejected');
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.reviews (item_id, buyer_company_id, buyer_user_id, rating)
      VALUES ('0c000000-0000-0000-0000-000000000003', '0e000000-0000-0000-0000-000000000001',
              '0f000000-0000-0000-0000-000000000001', 6)$$,
    '23514', 'rating above 5 rejected');

-- Subscribed plans can't be deleted out from under subscriptions.
SELECT pg_temp.assert_raises(
    $$DELETE FROM items.pricing_plans WHERE id = '0d000000-0000-0000-0000-000000000001'$$,
    '23001', 'plan with subscriptions cannot be deleted (ON DELETE RESTRICT)');

-- A verified review can't be moved to an item/company that never purchased.
SELECT pg_temp.assert_raises(
    $$UPDATE items.reviews SET item_id = '0c000000-0000-0000-0000-000000000003'
      WHERE buyer_user_id = '0f000000-0000-0000-0000-000000000002'$$,
    '23514', 'review item_id is immutable');
