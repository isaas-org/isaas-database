-- Sample buyer companies, each with an admin. Harbor Health and Brightline
-- Retail are seeded directly into 'active'/'verified' -- bypassing the real
-- verification flow -- so their members can subscribe. Fernway Logistics is
-- left 'pending' on purpose, to exercise the buyer gates and staff review.
--
-- Idempotent: buyer companies have no natural unique key, so they are matched
-- by name; buyer_users conflict on lower(email).

INSERT INTO buyer_companies.buyer_companies (name, website_url, industry_id, company_size, status, verification_status)
SELECT c.name, c.website_url, ind.id, c.company_size::buyer_companies.company_size,
       c.status::buyer_companies.company_status, c.verification_status::buyer_companies.verification_status
FROM (VALUES
    ('Harbor Health Group',   'https://harbor-health.test',      'healthcare',       '201-1000', 'active',  'verified'),
    ('Brightline Retail Co.', 'https://brightline-retail.test',  'retail-ecommerce', '51-200',   'active',  'verified'),
    ('Fernway Logistics',     'https://fernway-logistics.test',  'manufacturing',    '11-50',    'pending', 'pending')
) AS c(name, website_url, industry_slug, company_size, status, verification_status)
JOIN items.industries ind ON ind.slug = c.industry_slug
WHERE NOT EXISTS (
    SELECT 1 FROM buyer_companies.buyer_companies existing WHERE existing.name = c.name
);

INSERT INTO buyer_companies.buyer_users (buyer_company_id, name, email, role)
SELECT bc.id, admin.name, admin.email, 'admin'
FROM buyer_companies.buyer_companies bc
JOIN (VALUES
    ('Harbor Health Group',   'Hana Reyes',  'admin@harbor-health.test'),
    ('Brightline Retail Co.', 'Ben Okafor',  'admin@brightline-retail.test'),
    ('Fernway Logistics',     'Farah Malik', 'admin@fernway-logistics.test')
) AS admin(company_name, name, email) ON admin.company_name = bc.name
ON CONFLICT (lower(email)) DO NOTHING;
