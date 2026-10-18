-- Personal access tokens for agent apps: owned by a member of the company they
-- act for, stored as a SHA-256 hash, and limited to 90 days.

INSERT INTO vendors.vendor_access_tokens
    (vendor_id, vendor_user_id, name, token_prefix, token_hash, expires_at)
VALUES (pg_temp.fx('vendor.active'), pg_temp.fx('vendor_user.active_admin'), 'my agent', 'isaas_vpat_ab12',
        sha256('vendor-token-1'::bytea), now() + interval '30 days');

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_access_tokens
      (vendor_id, vendor_user_id, name, token_prefix, token_hash, expires_at)
      VALUES (pg_temp.fx('vendor.second'), pg_temp.fx('vendor_user.active_admin'), 'x', 'isaas_vpat_x',
              sha256('vendor-token-2'::bytea), now() + interval '1 day')$$,
    '23503', 'vendor_access_tokens_owner_fkey', 'vendor token owner must belong to the vendor');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_access_tokens
      (vendor_id, vendor_user_id, name, token_prefix, token_hash, expires_at)
      VALUES (pg_temp.fx('vendor.active'), pg_temp.fx('vendor_user.active_admin'), 'dup', 'isaas_vpat_ab12',
              sha256('vendor-token-1'::bytea), now() + interval '1 day')$$,
    '23505', 'vendor_access_tokens_token_hash_key', 'vendor token hash is unique');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_access_tokens
      (vendor_id, vendor_user_id, name, token_prefix, token_hash, expires_at)
      VALUES (pg_temp.fx('vendor.active'), pg_temp.fx('vendor_user.active_admin'), 'raw', 'isaas_vpat_r',
              'not-a-hash'::bytea, now() + interval '1 day')$$,
    '23514', 'vendor_access_tokens_hash_is_sha256', 'vendor token stores a SHA-256 hash only');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_access_tokens
      (vendor_id, vendor_user_id, name, token_prefix, token_hash, expires_at)
      VALUES (pg_temp.fx('vendor.active'), pg_temp.fx('vendor_user.active_admin'), 'long', 'isaas_vpat_l',
              sha256('vendor-token-3'::bytea), now() + interval '91 days')$$,
    '23514', 'vendor_access_tokens_max_lifetime', 'vendor token lives at most 90 days');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_access_tokens
      (vendor_id, vendor_user_id, name, token_prefix, token_hash, expires_at)
      VALUES (pg_temp.fx('vendor.active'), pg_temp.fx('vendor_user.active_admin'), 'old', 'isaas_vpat_o',
              sha256('vendor-token-4'::bytea), now() - interval '1 day')$$,
    '23514', 'vendor_access_tokens_max_lifetime', 'vendor token cannot be born expired');

INSERT INTO buyer_companies.buyer_access_tokens
    (buyer_company_id, buyer_user_id, name, token_prefix, token_hash, expires_at)
VALUES (pg_temp.fx('company.one'), pg_temp.fx('buyer_user.one_viewer'), 'my agent', 'isaas_bpat_cd34',
        sha256('buyer-token-1'::bytea), now() + interval '90 days');

SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_access_tokens
      (buyer_company_id, buyer_user_id, name, token_prefix, token_hash, expires_at)
      VALUES (pg_temp.fx('company.two'), pg_temp.fx('buyer_user.one_viewer'), 'x', 'isaas_bpat_x',
              sha256('buyer-token-2'::bytea), now() + interval '1 day')$$,
    '23503', 'buyer_access_tokens_owner_fkey', 'buyer token owner must belong to the company');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_access_tokens
      (buyer_company_id, buyer_user_id, name, token_prefix, token_hash, expires_at)
      VALUES (pg_temp.fx('company.one'), pg_temp.fx('buyer_user.one_admin'), 'dup', 'isaas_bpat_cd34',
              sha256('buyer-token-1'::bytea), now() + interval '1 day')$$,
    '23505', 'buyer_access_tokens_token_hash_key', 'buyer token hash is unique');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_access_tokens
      (buyer_company_id, buyer_user_id, name, token_prefix, token_hash, expires_at)
      VALUES (pg_temp.fx('company.one'), pg_temp.fx('buyer_user.one_admin'), 'raw', 'isaas_bpat_r',
              'not-a-hash'::bytea, now() + interval '1 day')$$,
    '23514', 'buyer_access_tokens_hash_is_sha256', 'buyer token stores a SHA-256 hash only');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_access_tokens
      (buyer_company_id, buyer_user_id, name, token_prefix, token_hash, expires_at)
      VALUES (pg_temp.fx('company.one'), pg_temp.fx('buyer_user.one_admin'), 'long', 'isaas_bpat_l',
              sha256('buyer-token-3'::bytea), now() + interval '91 days')$$,
    '23514', 'buyer_access_tokens_max_lifetime', 'buyer token lives at most 90 days');

-- Tokens go with their user.
DELETE FROM buyer_companies.buyer_users WHERE id = pg_temp.fx('buyer_user.one_viewer');
SELECT pg_temp.assert_eq(
    (SELECT count(*) FROM buyer_companies.buyer_access_tokens), 0::bigint,
    'buyer tokens removed with their user');
