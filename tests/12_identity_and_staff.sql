-- Auth0 identity on users and staff, user status, and staff as reviewers.

-- New users start active and unbound to an Auth0 identity.
SELECT pg_temp.assert_eq(
    (SELECT (status, auth_provider_id)::text FROM vendors.vendor_users WHERE id = pg_temp.fx('vendor_user.active_admin')),
    '(active,)', 'vendor user defaults: active, no auth identity yet');
SELECT pg_temp.assert_eq(
    (SELECT (status, auth_provider_id)::text FROM buyer_companies.buyer_users WHERE id = pg_temp.fx('buyer_user.one_admin')),
    '(active,)', 'buyer user defaults: active, no auth identity yet');

-- One Auth0 identity maps to at most one row per table. Many unbound rows are fine.
UPDATE vendors.vendor_users SET auth_provider_id = 'auth0|ana' WHERE id = pg_temp.fx('vendor_user.active_admin');
SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendor_users SET auth_provider_id = 'auth0|ana' WHERE id = pg_temp.fx('vendor_user.pending_admin')$$,
    '23505', 'vendor_users_auth_provider_id_key', 'vendor auth identity is unique');

UPDATE buyer_companies.buyer_users SET auth_provider_id = 'auth0|bo' WHERE id = pg_temp.fx('buyer_user.one_admin');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_users SET auth_provider_id = 'auth0|bo' WHERE id = pg_temp.fx('buyer_user.two_purchaser')$$,
    '23505', 'buyer_users_auth_provider_id_key', 'buyer auth identity is unique');

-- The same person can be a vendor user and a buyer user (separate tables).
UPDATE buyer_companies.buyer_users SET auth_provider_id = 'auth0|ana' WHERE id = pg_temp.fx('buyer_user.one_viewer');

-- Disable instead of delete.
UPDATE vendors.vendor_users SET status = 'disabled' WHERE id = pg_temp.fx('vendor_user.pending_admin');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_users SET status = 'removed' WHERE id = pg_temp.fx('buyer_user.one_viewer')$$,
    '22P02', 'invalid input value for enum', 'buyer user status limited to active/disabled');

-- Staff ------------------------------------------------------------------------
SELECT pg_temp.assert_raises(
    $$INSERT INTO platform.staff_users (name, email, role) VALUES ('Dup', 'RAE@isaas.test', 'admin')$$,
    '23505', 'staff_users_email_key', 'staff email unique regardless of case');

UPDATE platform.staff_users SET auth_provider_id = 'auth0|rae' WHERE id = pg_temp.fx('staff.reviewer');
SELECT pg_temp.assert_raises(
    $$INSERT INTO platform.staff_users (name, email, role, auth_provider_id)
      VALUES ('Other', 'other@isaas.test', 'admin', 'auth0|rae')$$,
    '23505', 'staff_users_auth_provider_id_key', 'staff auth identity is unique');

SELECT pg_temp.assert_raises(
    $$INSERT INTO platform.staff_users (name, email, role) VALUES ('Boss', 'boss@isaas.test', 'owner')$$,
    '22P02', 'invalid input value for enum', 'staff roles limited to admin/reviewer');

-- Artifact reviewers must be real staff, and staff with reviews can't be deleted.
INSERT INTO pg_temp.fixture_ids (name) VALUES ('artifact.vendor'), ('artifact.buyer');
INSERT INTO vendors.vendor_verification_artifacts
    (id, vendor_id, artifact_type, file_url, submitted_by_user_id)
VALUES (pg_temp.fx('artifact.vendor'), pg_temp.fx('vendor.pending'), 'proof_of_authority', 'https://docs.test/letter.pdf',
        pg_temp.fx('vendor_user.pending_admin'));
INSERT INTO buyer_companies.buyer_verification_artifacts
    (id, buyer_company_id, artifact_type, file_url, submitted_by_user_id)
VALUES (pg_temp.fx('artifact.buyer'), pg_temp.fx('company.pending'), 'identity_document', 'https://docs.test/id.pdf',
        pg_temp.fx('buyer_user.pending_admin'));

SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendor_verification_artifacts
      SET status = 'approved', reviewed_at = now(), reviewed_by_staff_id = uuidv7()
      WHERE id = pg_temp.fx('artifact.vendor')$$,
    '23503', 'vendor_verification_artifacts_reviewed_by_staff_id_fkey', 'vendor artifact reviewer must be staff');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_verification_artifacts
      SET status = 'approved', reviewed_at = now(), reviewed_by_staff_id = uuidv7()
      WHERE id = pg_temp.fx('artifact.buyer')$$,
    '23503', 'buyer_verification_artifacts_reviewed_by_staff_id_fkey', 'buyer artifact reviewer must be staff');

UPDATE buyer_companies.buyer_verification_artifacts
SET status = 'approved', reviewed_at = now(), reviewed_by_staff_id = pg_temp.fx('staff.reviewer')
WHERE id = pg_temp.fx('artifact.buyer');
SELECT pg_temp.assert_raises(
    $$DELETE FROM platform.staff_users WHERE id = pg_temp.fx('staff.reviewer')$$,
    '23503', 'buyer_verification_artifacts_reviewed_by_staff_id_fkey', 'staff with reviews cannot be deleted');
