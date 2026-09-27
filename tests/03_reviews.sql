-- Rules: verified purchase = company has an ACTIVE or CANCELLED subscription to
-- the reviewed item (trials don't count); computed at creation, then frozen.
-- One review per user per item.

INSERT INTO buyer_companies.subscriptions (buyer_company_id, item_id, pricing_plan_id, status) VALUES
    (pg_temp.fx('company.one'), pg_temp.fx('item.acme_crm'),    pg_temp.fx('plan.acme_starter'), 'active'),
    (pg_temp.fx('company.two'), pg_temp.fx('item.acme_crm'),    pg_temp.fx('plan.acme_starter'), 'trial'),
    (pg_temp.fx('company.two'), pg_temp.fx('item.second_tool'), pg_temp.fx('plan.second_pro'),   'cancelled');

INSERT INTO pg_temp.fixture_ids (name) VALUES
    ('review.acme_by_one'), ('review.acme_by_two'), ('review.second_by_two'), ('review.second_by_one');

-- Client-supplied is_verified_purchase values are deliberately wrong; the trigger must override them.
INSERT INTO items.reviews (id, item_id, buyer_company_id, buyer_user_id, rating, is_verified_purchase) VALUES
    (pg_temp.fx('review.acme_by_one'),   pg_temp.fx('item.acme_crm'),    pg_temp.fx('company.one'), pg_temp.fx('buyer_user.one_admin'),     5, false),
    (pg_temp.fx('review.acme_by_two'),   pg_temp.fx('item.acme_crm'),    pg_temp.fx('company.two'), pg_temp.fx('buyer_user.two_purchaser'), 2, true),
    (pg_temp.fx('review.second_by_two'), pg_temp.fx('item.second_tool'), pg_temp.fx('company.two'), pg_temp.fx('buyer_user.two_purchaser'), 4, false),
    (pg_temp.fx('review.second_by_one'), pg_temp.fx('item.second_tool'), pg_temp.fx('company.one'), pg_temp.fx('buyer_user.one_viewer'),    3, true);

SELECT pg_temp.assert_eq(
    (SELECT is_verified_purchase FROM items.reviews WHERE id = pg_temp.fx('review.acme_by_one')),
    true, 'active subscription => verified (client sent false)');
SELECT pg_temp.assert_eq(
    (SELECT is_verified_purchase FROM items.reviews WHERE id = pg_temp.fx('review.acme_by_two')),
    false, 'trial subscription does not count (client sent true)');
SELECT pg_temp.assert_eq(
    (SELECT is_verified_purchase FROM items.reviews WHERE id = pg_temp.fx('review.second_by_two')),
    true, 'cancelled subscription still counts as a past purchase');
SELECT pg_temp.assert_eq(
    (SELECT is_verified_purchase FROM items.reviews WHERE id = pg_temp.fx('review.second_by_one')),
    false, 'subscription to a DIFFERENT item does not verify this one');

-- Frozen after creation, in both directions.
UPDATE items.reviews SET is_verified_purchase = false WHERE id = pg_temp.fx('review.acme_by_one');
UPDATE items.reviews SET is_verified_purchase = true  WHERE id = pg_temp.fx('review.acme_by_two');
SELECT pg_temp.assert_eq(
    (SELECT array_agg(is_verified_purchase ORDER BY rating DESC) FROM items.reviews
     WHERE item_id = pg_temp.fx('item.acme_crm')),
    ARRAY[true, false], 'verified flag cannot be changed by UPDATE');

-- A review can't be moved to another item or company (would carry its flag along).
SELECT pg_temp.assert_raises(
    $$UPDATE items.reviews SET item_id = pg_temp.fx('item.acme_crm') WHERE id = pg_temp.fx('review.second_by_two')$$,
    '23514', 'cannot be moved', 'review item_id is immutable');
SELECT pg_temp.assert_raises(
    $$UPDATE items.reviews SET buyer_company_id = pg_temp.fx('company.one') WHERE id = pg_temp.fx('review.second_by_two')$$,
    '23514', 'cannot be moved', 'review buyer_company_id is immutable');

-- Aggregates maintained on insert / update / delete, per item.
SELECT pg_temp.assert_eq(
    (SELECT array_agg((slug, avg_rating, review_count)::text ORDER BY slug) FROM items.items
     WHERE id IN (pg_temp.fx('item.acme_crm'), pg_temp.fx('item.second_tool'))),
    ARRAY['(acme-crm,3.50,2)', '(second-tool,3.50,2)'], 'aggregates after inserts');

UPDATE items.reviews SET rating = 4 WHERE id = pg_temp.fx('review.acme_by_two');
SELECT pg_temp.assert_eq(
    (SELECT avg_rating FROM items.items WHERE id = pg_temp.fx('item.acme_crm')),
    4.50::numeric(3,2), 'aggregates after rating update');

DELETE FROM items.reviews WHERE item_id = pg_temp.fx('item.acme_crm');
SELECT pg_temp.assert_eq(
    (SELECT array_agg((slug, avg_rating, review_count)::text ORDER BY slug) FROM items.items
     WHERE id IN (pg_temp.fx('item.acme_crm'), pg_temp.fx('item.second_tool'))),
    ARRAY['(acme-crm,,0)', '(second-tool,3.50,2)'], 'delete resets only the affected item');

-- Authorship and shape.
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.reviews (item_id, buyer_company_id, buyer_user_id, rating)
      VALUES (pg_temp.fx('item.acme_crm'), pg_temp.fx('company.two'), pg_temp.fx('buyer_user.one_admin'), 5)$$,
    '23503', 'reviews_author_fkey', 'author must belong to the reviewing company');
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.reviews (item_id, buyer_company_id, buyer_user_id, rating)
      VALUES (pg_temp.fx('item.second_tool'), pg_temp.fx('company.one'), pg_temp.fx('buyer_user.one_viewer'), 4)$$,
    '23505', 'reviews_item_user_unique', 'one review per user per item');
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.reviews (item_id, buyer_company_id, buyer_user_id, rating)
      VALUES (pg_temp.fx('item.acme_crm'), pg_temp.fx('company.one'), pg_temp.fx('buyer_user.one_admin'), 6)$$,
    '23514', 'reviews_rating_check', 'rating above 5 rejected');
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.reviews (item_id, buyer_company_id, buyer_user_id, rating)
      VALUES (pg_temp.fx('item.acme_crm'), pg_temp.fx('company.one'), pg_temp.fx('buyer_user.one_admin'), 0)$$,
    '23514', 'reviews_rating_check', 'rating below 1 rejected');
