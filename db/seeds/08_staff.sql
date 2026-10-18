-- The repo owner as the first platform staff admin, and the staff member on
-- record for the sample vendors and buyer companies seeded as 'verified'
-- (they skipped the real review). auth_provider_id is bound on first login.
--
-- Idempotent: staff conflict on lower(email); only companies with no
-- verifier yet are attributed.

INSERT INTO platform.staff_users (name, email, role)
VALUES ('AdityaAA2004', 'anandad1@msu.edu', 'admin')
ON CONFLICT (lower(email)) DO NOTHING;

UPDATE vendors.vendors v
SET verified_by_staff_id = s.id
FROM platform.staff_users s
WHERE lower(s.email) = 'anandad1@msu.edu'
  AND v.verification_status = 'verified'
  AND v.verified_by_staff_id IS NULL;

UPDATE buyer_companies.buyer_companies bc
SET verified_by_staff_id = s.id
FROM platform.staff_users s
WHERE lower(s.email) = 'anandad1@msu.edu'
  AND bc.verification_status = 'verified'
  AND bc.verified_by_staff_id IS NULL;
