-- Users and the per-user watchlist.

SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_users (buyer_company_id, name, email, role)
      VALUES (pg_temp.fx('company.two'), 'Dup', 'BO@one.test', 'viewer')$$,
    '23505', 'buyer_users_email_key', 'buyer email unique regardless of case');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_users (vendor_id, name, email, role)
      VALUES (pg_temp.fx('vendor.second'), 'Dup', 'Ana@Acme.test', 'sales')$$,
    '23505', 'vendor_users_email_key', 'vendor email unique regardless of case');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_users (buyer_company_id, name, email, role)
      VALUES (pg_temp.fx('company.two'), 'Boss', 'boss@two.test', 'owner')$$,
    '22P02', 'invalid input value for enum', 'buyer roles limited to the defined set');

-- Watchlist: one entry per user per item, owned by the user (not the company).
INSERT INTO buyer_companies.watchlist (buyer_user_id, item_id) VALUES
    (pg_temp.fx('buyer_user.one_viewer'), pg_temp.fx('item.acme_crm')),
    (pg_temp.fx('buyer_user.one_admin'),  pg_temp.fx('item.acme_crm'));   -- colleagues keep separate lists
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.watchlist (buyer_user_id, item_id)
      VALUES (pg_temp.fx('buyer_user.one_viewer'), pg_temp.fx('item.acme_crm'))$$,
    '23505', 'watchlist_user_item_unique', 'duplicate watchlist entry rejected');

DELETE FROM buyer_companies.buyer_users WHERE id = pg_temp.fx('buyer_user.one_viewer');
SELECT pg_temp.assert_eq(
    (SELECT count(*) FROM buyer_companies.watchlist), 1::bigint,
    'watchlist entries follow their user; colleague''s entry remains');
