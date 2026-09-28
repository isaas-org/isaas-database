-- Buyer and vendor verification artifacts: submitter belongs to the verified
-- party; a decided artifact has reviewed_at, a pending one does not.

-- Buyer side ---------------------------------------------------------------
INSERT INTO pg_temp.fixture_ids (name) VALUES ('artifact.buyer'), ('artifact.vendor');

INSERT INTO buyer_companies.buyer_verification_artifacts
    (id, buyer_company_id, artifact_type, file_url, submitted_by_user_id)
VALUES (pg_temp.fx('artifact.buyer'), pg_temp.fx('company.one'), 'tax_id', 's3://x/tax.pdf', pg_temp.fx('buyer_user.one_admin'));

SELECT pg_temp.assert_raises(
    $$INSERT INTO buyer_companies.buyer_verification_artifacts (buyer_company_id, artifact_type, file_url, submitted_by_user_id)
      VALUES (pg_temp.fx('company.two'), 'tax_id', 's3://x/tax.pdf', pg_temp.fx('buyer_user.one_admin'))$$,
    '23503', 'buyer_verification_artifacts_submitter_fkey', 'buyer submitter must belong to the company');

SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_verification_artifacts SET status = 'approved' WHERE id = pg_temp.fx('artifact.buyer')$$,
    '23514', 'buyer_verification_artifacts_reviewed_when_decided', 'buyer: decision requires reviewed_at');
SELECT pg_temp.assert_raises(
    $$UPDATE buyer_companies.buyer_verification_artifacts SET reviewed_at = now() WHERE id = pg_temp.fx('artifact.buyer')$$,
    '23514', 'buyer_verification_artifacts_reviewed_when_decided', 'buyer: pending artifact cannot have reviewed_at');

UPDATE buyer_companies.buyer_verification_artifacts
SET status = 'rejected', reviewed_at = now(), review_notes = 'blurry scan'
WHERE id = pg_temp.fx('artifact.buyer');
-- Resubmission keeps the history.
INSERT INTO buyer_companies.buyer_verification_artifacts (buyer_company_id, artifact_type, file_url, submitted_by_user_id)
VALUES (pg_temp.fx('company.one'), 'tax_id', 's3://x/tax-v2.pdf', pg_temp.fx('buyer_user.one_admin'));
SELECT pg_temp.assert_eq(
    (SELECT array_agg(status::text ORDER BY created_at, id) FROM buyer_companies.buyer_verification_artifacts
     WHERE buyer_company_id = pg_temp.fx('company.one')),
    ARRAY['rejected', 'pending'], 'resubmission keeps the rejected artifact');

-- Vendor side --------------------------------------------------------------
INSERT INTO vendors.vendor_verification_artifacts
    (id, vendor_id, artifact_type, file_url, submitted_by_user_id)
VALUES (pg_temp.fx('artifact.vendor'), pg_temp.fx('vendor.pending'), 'bank_verification', 's3://x/bank.pdf',
        pg_temp.fx('vendor_user.pending_admin'));

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendor_verification_artifacts (vendor_id, artifact_type, file_url, submitted_by_user_id)
      VALUES (pg_temp.fx('vendor.active'), 'tax_id', 's3://x/tax.pdf', pg_temp.fx('vendor_user.pending_admin'))$$,
    '23503', 'vendor_verification_artifacts_submitter_fkey', 'vendor submitter must belong to the vendor');

SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendor_verification_artifacts SET status = 'approved' WHERE id = pg_temp.fx('artifact.vendor')$$,
    '23514', 'vendor_verification_artifacts_reviewed_when_decided', 'vendor: decision requires reviewed_at');
SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendor_verification_artifacts SET reviewed_at = now() WHERE id = pg_temp.fx('artifact.vendor')$$,
    '23514', 'vendor_verification_artifacts_reviewed_when_decided', 'vendor: pending artifact cannot have reviewed_at');

UPDATE vendors.vendor_verification_artifacts
SET status = 'approved', reviewed_at = now(), reviewed_by_staff_id = uuidv7()
WHERE id = pg_temp.fx('artifact.vendor');

-- Deleting a vendor cascades its artifacts and users cleanly.
DELETE FROM items.items WHERE vendor_id = pg_temp.fx('vendor.pending');
DELETE FROM vendors.vendors WHERE id = pg_temp.fx('vendor.pending');
SELECT pg_temp.assert_eq(
    (SELECT count(*) FROM vendors.vendor_verification_artifacts WHERE vendor_id = pg_temp.fx('vendor.pending')),
    0::bigint, 'vendor artifacts removed with the vendor');
