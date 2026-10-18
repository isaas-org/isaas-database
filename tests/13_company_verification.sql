-- verified_at / verified_by_staff_id on vendors and buyer companies, and the
-- SSO connection that only a verified company may have.

-- Rows inserted as verified get a timestamp; unverified rows have none.
SELECT pg_temp.assert_true(
    (SELECT verified_at IS NOT NULL FROM vendors.vendors WHERE id = pg_temp.fx('vendor.active')),
    'vendor inserted verified gets verified_at');
SELECT pg_temp.assert_true(
    (SELECT verified_at IS NULL FROM buyer_companies.buyer_companies WHERE id = pg_temp.fx('company.pending')),
    'pending company has no verified_at');

-- Staff verify a pending vendor: verified_at is stamped, the reviewer kept.
UPDATE vendors.vendors
SET verification_status = 'verified', verified_by_staff_id = pg_temp.fx('staff.reviewer')
WHERE id = pg_temp.fx('vendor.pending');
SELECT pg_temp.assert_eq(
    (SELECT (verified_at IS NOT NULL, verified_by_staff_id = pg_temp.fx('staff.reviewer'))::text
     FROM vendors.vendors WHERE id = pg_temp.fx('vendor.pending')),
    '(t,t)', 'verifying a vendor stamps verified_at and keeps the reviewer');

-- Leaving 'verified' clears both. (An active vendor must leave 'active' first.)
UPDATE vendors.vendors SET verification_status = 'rejected' WHERE id = pg_temp.fx('vendor.pending');
SELECT pg_temp.assert_eq(
    (SELECT (verified_at, verified_by_staff_id)::text FROM vendors.vendors WHERE id = pg_temp.fx('vendor.pending')),
    '(,)', 'leaving verified clears verified_at and the reviewer');

-- Same for buyer companies.
UPDATE buyer_companies.buyer_companies
SET verification_status = 'verified', verified_by_staff_id = pg_temp.fx('staff.reviewer')
WHERE id = pg_temp.fx('company.pending');
SELECT pg_temp.assert_true(
    (SELECT verified_at IS NOT NULL FROM buyer_companies.buyer_companies WHERE id = pg_temp.fx('company.pending')),
    'verifying a buyer company stamps verified_at');
UPDATE buyer_companies.buyer_companies SET verification_status = 'pending' WHERE id = pg_temp.fx('company.pending');

-- The fields can't drift out of step when set directly.
SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendors SET verified_at = NULL WHERE id = pg_temp.fx('vendor.active')$$,
    '23514', 'vendors_verified_has_timestamp', 'verified vendor keeps verified_at');
SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendors SET verified_at = now() WHERE id = pg_temp.fx('vendor.pending')$$,
    '23514', 'vendors_verified_has_timestamp', 'unverified vendor cannot have verified_at');
SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendors SET verified_by_staff_id = pg_temp.fx('staff.reviewer') WHERE id = pg_temp.fx('vendor.pending')$$,
    '23514', 'vendors_verifier_requires_verified', 'unverified vendor cannot have a verifier');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_companies SET verified_at = NULL WHERE id = pg_temp.fx('company.one')$$,
    '23514', 'buyer_companies_verified_has_timestamp', 'verified company keeps verified_at');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_companies SET verified_by_staff_id = pg_temp.fx('staff.reviewer')
      WHERE id = pg_temp.fx('company.pending')$$,
    '23514', 'buyer_companies_verifier_requires_verified', 'unverified company cannot have a verifier');

SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendors SET verified_by_staff_id = uuidv7() WHERE id = pg_temp.fx('vendor.active')$$,
    '23503', 'vendors_verified_by_staff_id_fkey', 'vendor verifier must be staff');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_companies SET verified_by_staff_id = uuidv7() WHERE id = pg_temp.fx('company.one')$$,
    '23503', 'buyer_companies_verified_by_staff_id_fkey', 'buyer company verifier must be staff');

-- SSO only for verified companies, one company per connection.
UPDATE vendors.vendors SET sso_connection_id = 'con_acme' WHERE id = pg_temp.fx('vendor.active');
SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendors SET sso_connection_id = 'con_acme' WHERE id = pg_temp.fx('vendor.second')$$,
    '23505', 'vendors_sso_connection_id_key', 'vendor SSO connection is unique');
SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendors SET sso_connection_id = 'con_pending' WHERE id = pg_temp.fx('vendor.pending')$$,
    '23514', 'vendors_sso_requires_verified', 'unverified vendor cannot have SSO');

UPDATE buyer_companies.buyer_companies SET sso_connection_id = 'con_one' WHERE id = pg_temp.fx('company.one');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_companies SET sso_connection_id = 'con_one' WHERE id = pg_temp.fx('company.two')$$,
    '23505', 'buyer_companies_sso_connection_id_key', 'buyer SSO connection is unique');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_companies SET sso_connection_id = 'con_pending' WHERE id = pg_temp.fx('company.pending')$$,
    '23514', 'buyer_companies_sso_requires_verified', 'unverified buyer company cannot have SSO');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_companies SET status = 'suspended', verification_status = 'rejected'
      WHERE id = pg_temp.fx('company.one')$$,
    '23514', 'buyer_companies_sso_requires_verified', 'company with SSO cannot lose verification');
