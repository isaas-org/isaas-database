-- Pending verification documents for the two pending companies (Cascade Labs,
-- Fernway Logistics), so staff review can be tried end to end. Documents are
-- checked outside the system for now; file_url points at wherever the
-- document lives.
--
-- Idempotent: matched on (company, artifact_type).

INSERT INTO vendors.vendor_verification_artifacts (vendor_id, artifact_type, file_url, submitted_by_user_id)
SELECT v.id, a.artifact_type::vendors.artifact_type, a.file_url, vu.id
FROM vendors.vendors v
JOIN vendors.vendor_users vu ON vu.vendor_id = v.id AND vu.role = 'admin'
JOIN (VALUES
    ('business_registration', 'https://docs.test/cascade-labs/registration.pdf'),
    ('proof_of_authority',    'https://docs.test/cascade-labs/officer-listing.pdf'),
    ('identity_document',     'https://docs.test/cascade-labs/admin-id.pdf')
) AS a(artifact_type, file_url) ON true
WHERE v.slug = 'cascade-labs'
  AND NOT EXISTS (
    SELECT 1 FROM vendors.vendor_verification_artifacts existing
    WHERE existing.vendor_id = v.id AND existing.artifact_type::text = a.artifact_type
);

INSERT INTO buyer_companies.buyer_verification_artifacts (buyer_company_id, artifact_type, file_url, submitted_by_user_id)
SELECT bc.id, a.artifact_type::buyer_companies.artifact_type, a.file_url, bu.id
FROM buyer_companies.buyer_companies bc
JOIN buyer_companies.buyer_users bu ON bu.buyer_company_id = bc.id AND bu.role = 'admin'
JOIN (VALUES
    ('business_registration', 'https://docs.test/fernway-logistics/registration.pdf'),
    ('proof_of_authority',    'https://docs.test/fernway-logistics/authorisation-letter.pdf'),
    ('identity_document',     'https://docs.test/fernway-logistics/admin-id.pdf')
) AS a(artifact_type, file_url) ON true
WHERE bc.name = 'Fernway Logistics'
  AND NOT EXISTS (
    SELECT 1 FROM buyer_companies.buyer_verification_artifacts existing
    WHERE existing.buyer_company_id = bc.id AND existing.artifact_type::text = a.artifact_type
);
