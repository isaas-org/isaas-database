-- Members beyond each company's admin, one per role, for login and
-- authorization testing. Each email has a matching Auth0 test user (created by
-- isaas-auth0-config); the backend binds auth_provider_id on first login.
--
--   Northstar CRM (vendor, active)      admin (02_vendors.sql), sales, support
--   Pulseboard (vendor, active)         admin, plus Dana as sales
--   Cascade Labs (vendor, pending)      admin only
--   Harbor Health (buyer, active)       admin (05_buyer_companies.sql), purchaser, approver, viewer
--   Brightline Retail (buyer, active)   admin, plus Dana as viewer
--   Fernway Logistics (buyer, pending)  admin only
--
-- Dana is in one vendor and one buyer company under the same email, to test a
-- single login with two memberships. This file is test data only: leave it out
-- of any production database.
--
-- Idempotent: conflicts on lower(email).

INSERT INTO vendors.vendor_users (vendor_id, name, email, role)
SELECT v.id, u.name, u.email, u.role::vendors.vendor_user_role
FROM vendors.vendors v
JOIN (VALUES
    ('northstar-crm', 'Sid Moreno', 'sales@northstar-crm.test',   'sales'),
    ('northstar-crm', 'Sue Park',   'support@northstar-crm.test', 'support'),
    ('pulseboard',    'Dana Cruz',  'dana@pulseboard.test',       'sales')
) AS u(vendor_slug, name, email, role) ON u.vendor_slug = v.slug
ON CONFLICT (lower(email)) DO NOTHING;

INSERT INTO buyer_companies.buyer_users (buyer_company_id, name, email, role)
SELECT bc.id, u.name, u.email, u.role::buyer_companies.buyer_user_role
FROM buyer_companies.buyer_companies bc
JOIN (VALUES
    ('Harbor Health Group',   'Pia Lund',   'purchaser@harbor-health.test', 'purchaser'),
    ('Harbor Health Group',   'Ari Stone',  'approver@harbor-health.test',  'approver'),
    ('Harbor Health Group',   'Vic Hale',   'viewer@harbor-health.test',    'viewer'),
    ('Brightline Retail Co.', 'Dana Cruz',  'dana@pulseboard.test',         'viewer')
) AS u(company_name, name, email, role) ON u.company_name = bc.name
ON CONFLICT (lower(email)) DO NOTHING;
