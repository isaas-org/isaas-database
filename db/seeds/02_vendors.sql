-- Sample vendors. Seeded directly into 'active'/'verified' -- bypassing the
-- real KYB flow -- so their items can be published. Cascade Labs is left
-- 'pending' on purpose, to prove the publish gate and items.published_catalog
-- correctly exclude an unverified vendor's listings.
--
-- Idempotent: vendors conflict on slug, vendor_users on lower(email).

INSERT INTO vendors.vendors (company_name, slug, description, logo_url, website_url, support_email, status, verification_status) VALUES
    ('Northstar CRM, Inc.',  'northstar-crm',   'Pipeline and relationship management for growing sales teams.', 'https://placehold.co/200x200?text=Northstar', 'https://northstar-crm.test',   'support@northstar-crm.test',   'active',  'verified'),
    ('Pulseboard, Inc.',     'pulseboard',       'Real-time analytics dashboards for product and revenue teams.', 'https://placehold.co/200x200?text=Pulseboard', 'https://pulseboard.test',       'support@pulseboard.test',       'active',  'verified'),
    ('Everhire, Inc.',       'everhire',         'Hiring and people operations for distributed teams.',            'https://placehold.co/200x200?text=Everhire',   'https://everhire.test',         'support@everhire.test',         'active',  'verified'),
    ('Northwind DevOps Co.', 'northwind-devops', 'CI/CD and infrastructure tooling for platform teams.',           'https://placehold.co/200x200?text=Northwind',  'https://northwind-devops.test', 'support@northwind-devops.test', 'active',  'verified'),
    ('Cascade Labs',         'cascade-labs',     'Workflow automation, currently onboarding.',                      'https://placehold.co/200x200?text=Cascade',    'https://cascade-labs.test',     'support@cascade-labs.test',     'pending', 'pending')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO vendors.vendor_users (vendor_id, name, email, role)
SELECT v.id, admin.name, admin.email, 'admin'
FROM vendors.vendors v
JOIN (VALUES
    ('northstar-crm',   'Nora Ito',   'admin@northstar-crm.test'),
    ('pulseboard',      'Priya Shah', 'admin@pulseboard.test'),
    ('everhire',        'Elliot Cho', 'admin@everhire.test'),
    ('northwind-devops', 'Nadia Fox', 'admin@northwind-devops.test'),
    ('cascade-labs',    'Cory Lane',  'admin@cascade-labs.test')
) AS admin(vendor_slug, name, email) ON admin.vendor_slug = v.slug
ON CONFLICT (lower(email)) DO NOTHING;
