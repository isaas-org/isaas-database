-- Join requests: only active companies can be asked to join or add members
-- through SSO; an admin invite works while pending. Path, reviewer and
-- decision fields must agree.

-- Buyer side ---------------------------------------------------------------
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_join_requests
      (buyer_company_id, auth_provider_id, name, email, requested_role, granted_via)
      VALUES (pg_temp.fx('company.pending'), 'auth0|imp', 'Ivy', 'ivy@pending-buyer.test', 'viewer', 'peer_approval')$$,
    '23514', 'join request not allowed', 'cannot ask to join a pending buyer company');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_join_requests
      (buyer_company_id, auth_provider_id, name, email, requested_role, status, granted_via, reviewed_at)
      VALUES (pg_temp.fx('company.pending'), 'auth0|sso', 'Sso', 'sso@pending-buyer.test', 'viewer',
              'approved', 'sso_auto_provision', now())$$,
    '23514', 'join request not allowed', 'no SSO provisioning into a pending buyer company');

-- An invite works while pending, and needs no Auth0 identity yet.
INSERT INTO buyer_companies.buyer_join_requests
    (buyer_company_id, name, email, requested_role, status, granted_via, reviewed_by_user_id, reviewed_at)
VALUES (pg_temp.fx('company.pending'), 'Fin Ance', 'fin@pending-buyer.test', 'purchaser',
        'approved', 'admin_invite', pg_temp.fx('buyer_user.pending_admin'), now());

-- Peer request to an active company; one open request per person.
INSERT INTO pg_temp.fixture_ids (name) VALUES ('join.buyer_peer');
INSERT INTO buyer_companies.buyer_join_requests
    (id, buyer_company_id, auth_provider_id, name, email, requested_role, granted_via)
VALUES (pg_temp.fx('join.buyer_peer'), pg_temp.fx('company.one'), 'auth0|joe', 'Joe', 'joe@one.test',
        'approver', 'peer_approval');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_join_requests
      (buyer_company_id, auth_provider_id, name, email, requested_role, granted_via)
      VALUES (pg_temp.fx('company.one'), 'auth0|joe', 'Joe', 'joe@one.test', 'viewer', 'peer_approval')$$,
    '23505', 'buyer_join_requests_one_pending', 'one pending request per person per company');

SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_join_requests
      (buyer_company_id, name, email, requested_role, granted_via)
      VALUES (pg_temp.fx('company.one'), 'Anon', 'anon@one.test', 'viewer', 'peer_approval')$$,
    '23514', 'buyer_join_requests_identity_required', 'peer request needs an Auth0 identity');

-- Decision fields.
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_join_requests SET status = 'approved', reviewed_by_user_id = pg_temp.fx('buyer_user.one_admin')
      WHERE id = pg_temp.fx('join.buyer_peer')$$,
    '23514', 'buyer_join_requests_reviewed_when_decided', 'approval needs reviewed_at');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_join_requests SET status = 'approved', reviewed_at = now()
      WHERE id = pg_temp.fx('join.buyer_peer')$$,
    '23514', 'buyer_join_requests_path_rules', 'peer approval needs a reviewer');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_join_requests
      SET status = 'approved', reviewed_at = now(), reviewed_by_user_id = pg_temp.fx('buyer_user.two_purchaser')
      WHERE id = pg_temp.fx('join.buyer_peer')$$,
    '23503', 'buyer_join_requests_reviewer_fkey', 'reviewer must belong to the company being joined');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_join_requests
      (buyer_company_id, name, email, requested_role, status, granted_via, reviewed_at)
      VALUES (pg_temp.fx('company.one'), 'Nobody', 'nobody@one.test', 'viewer', 'approved', 'admin_invite', now())$$,
    '23514', 'buyer_join_requests_path_rules', 'invite records the inviting admin');
SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_join_requests
      (buyer_company_id, auth_provider_id, name, email, requested_role, granted_via)
      VALUES (pg_temp.fx('company.one'), 'auth0|sso2', 'Sso', 'sso2@one.test', 'viewer', 'sso_auto_provision')$$,
    '23514', 'buyer_join_requests_path_rules', 'SSO provisioning is approved at once');

-- Reject, then the person may ask again.
UPDATE buyer_companies.buyer_join_requests
SET status = 'rejected', reviewed_at = now(), reviewed_by_user_id = pg_temp.fx('buyer_user.one_admin')
WHERE id = pg_temp.fx('join.buyer_peer');
INSERT INTO buyer_companies.buyer_join_requests
    (buyer_company_id, auth_provider_id, name, email, requested_role, granted_via)
VALUES (pg_temp.fx('company.one'), 'auth0|joe', 'Joe', 'joe@one.test', 'viewer', 'peer_approval');

-- SSO provisioning into an active company.
INSERT INTO buyer_companies.buyer_join_requests
    (buyer_company_id, auth_provider_id, name, email, requested_role, status, granted_via, reviewed_at)
VALUES (pg_temp.fx('company.one'), 'auth0|sso3', 'Sso', 'sso3@one.test', 'viewer', 'approved', 'sso_auto_provision', now());

-- Vendor side --------------------------------------------------------------
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_join_requests
      (vendor_id, auth_provider_id, name, email, requested_role, granted_via)
      VALUES (pg_temp.fx('vendor.pending'), 'auth0|imp', 'Ivy', 'ivy@pending.test', 'sales', 'peer_approval')$$,
    '23514', 'join request not allowed', 'cannot ask to join a pending vendor');

INSERT INTO vendors.vendor_join_requests
    (vendor_id, name, email, requested_role, status, granted_via, reviewed_by_user_id, reviewed_at)
VALUES (pg_temp.fx('vendor.pending'), 'Sal Es', 'sal@pending.test', 'sales',
        'approved', 'admin_invite', pg_temp.fx('vendor_user.pending_admin'), now());

INSERT INTO pg_temp.fixture_ids (name) VALUES ('join.vendor_peer');
INSERT INTO vendors.vendor_join_requests
    (id, vendor_id, auth_provider_id, name, email, requested_role, granted_via)
VALUES (pg_temp.fx('join.vendor_peer'), pg_temp.fx('vendor.active'), 'auth0|sam', 'Sam', 'sam@acme.test',
        'support', 'peer_approval');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_join_requests
      (vendor_id, auth_provider_id, name, email, requested_role, granted_via)
      VALUES (pg_temp.fx('vendor.active'), 'auth0|sam', 'Sam', 'sam@acme.test', 'sales', 'peer_approval')$$,
    '23505', 'vendor_join_requests_one_pending', 'one pending request per person per vendor');
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_join_requests
      (vendor_id, name, email, requested_role, granted_via)
      VALUES (pg_temp.fx('vendor.active'), 'Anon', 'anon@acme.test', 'sales', 'peer_approval')$$,
    '23514', 'vendor_join_requests_identity_required', 'vendor peer request needs an Auth0 identity');
SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendor_join_requests SET status = 'approved', reviewed_by_user_id = pg_temp.fx('vendor_user.active_admin')
      WHERE id = pg_temp.fx('join.vendor_peer')$$,
    '23514', 'vendor_join_requests_reviewed_when_decided', 'vendor approval needs reviewed_at');
SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendor_join_requests SET status = 'approved', reviewed_at = now()
      WHERE id = pg_temp.fx('join.vendor_peer')$$,
    '23514', 'vendor_join_requests_path_rules', 'vendor peer approval needs a reviewer');
SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendor_join_requests
      SET status = 'approved', reviewed_at = now(), reviewed_by_user_id = pg_temp.fx('vendor_user.pending_admin')
      WHERE id = pg_temp.fx('join.vendor_peer')$$,
    '23503', 'vendor_join_requests_reviewer_fkey', 'vendor reviewer must belong to the vendor being joined');

UPDATE vendors.vendor_join_requests
SET status = 'approved', reviewed_at = now(), reviewed_by_user_id = pg_temp.fx('vendor_user.active_admin')
WHERE id = pg_temp.fx('join.vendor_peer');

-- Deleting a vendor removes its requests along with its users.
DELETE FROM items.items WHERE vendor_id = pg_temp.fx('vendor.pending');
DELETE FROM vendors.vendors WHERE id = pg_temp.fx('vendor.pending');
SELECT pg_temp.assert_eq(
    (SELECT count(*) FROM vendors.vendor_join_requests WHERE vendor_id = pg_temp.fx('vendor.pending')),
    0::bigint, 'vendor join requests removed with the vendor');
