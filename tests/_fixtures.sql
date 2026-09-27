-- Shared test world. Loaded inside each test's transaction and rolled back after.
-- Fixed UUIDs keep the tests readable: 0a.. vendors, 0b.. vendor users,
-- 0c.. items, 0d.. plans, 0e.. buyer companies, 0f.. buyer users, 01.. taxonomy.

INSERT INTO vendors.vendors (id, company_name, slug, status, verification_status) VALUES
    ('0a000000-0000-0000-0000-000000000001', 'Acme CRM Inc',     'acme-crm',     'active',  'verified'),
    ('0a000000-0000-0000-0000-000000000002', 'Pending Soft',     'pending-soft', 'pending', 'pending'),
    ('0a000000-0000-0000-0000-000000000003', 'Soon Suspended',   'soon-susp',    'active',  'verified');

INSERT INTO vendors.vendor_users (id, vendor_id, name, email, role) VALUES
    ('0b000000-0000-0000-0000-000000000001', '0a000000-0000-0000-0000-000000000001', 'Ana Admin',  'ana@acme.test',     'admin'),
    ('0b000000-0000-0000-0000-000000000002', '0a000000-0000-0000-0000-000000000002', 'Pat Pending', 'pat@pending.test', 'admin');

INSERT INTO items.categories (id, name, slug) VALUES
    ('01000000-0000-0000-0000-000000000001', 'CRM',            'crm'),
    ('01000000-0000-0000-0000-000000000002', 'Data Analytics', 'data-analytics');

INSERT INTO items.industries (id, name, slug) VALUES
    ('01000000-0000-0000-0000-000000000101', 'Healthcare', 'healthcare');

INSERT INTO items.items (id, vendor_id, name, slug, tagline, description, status) VALUES
    ('0c000000-0000-0000-0000-000000000001', '0a000000-0000-0000-0000-000000000001',
     'Acme CRM', 'acme-crm', 'Pipeline management for small teams',
     'Track leads, deals and customer relationships.', 'published'),
    ('0c000000-0000-0000-0000-000000000002', '0a000000-0000-0000-0000-000000000001',
     'Acme Insights', 'acme-insights', 'Dashboards', 'Analytics add-on.', 'draft'),
    ('0c000000-0000-0000-0000-000000000003', '0a000000-0000-0000-0000-000000000003',
     'Suspendable Tool', 'suspendable-tool', NULL, NULL, 'published'),
    ('0c000000-0000-0000-0000-000000000004', '0a000000-0000-0000-0000-000000000002',
     'Pending Product', 'pending-product', NULL, NULL, 'draft');

INSERT INTO items.pricing_plans (id, item_id, tier_name, pricing_model, price, billing_frequency) VALUES
    ('0d000000-0000-0000-0000-000000000001', '0c000000-0000-0000-0000-000000000001', 'Starter', 'seat', 10.00, 'monthly'),
    ('0d000000-0000-0000-0000-000000000002', '0c000000-0000-0000-0000-000000000003', 'Pro',     'flat', 99.00, 'annual');

INSERT INTO buyers.buyer_companies (id, name, industry_id, company_size) VALUES
    ('0e000000-0000-0000-0000-000000000001', 'Buyer One LLC', '01000000-0000-0000-0000-000000000101', '51-200'),
    ('0e000000-0000-0000-0000-000000000002', 'Buyer Two Corp', NULL, '5000+');

INSERT INTO buyers.buyer_users (id, buyer_company_id, name, email, role) VALUES
    ('0f000000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-000000000001', 'Bo Buyer',   'bo@one.test',   'admin'),
    ('0f000000-0000-0000-0000-000000000002', '0e000000-0000-0000-0000-000000000001', 'Bea Viewer', 'bea@one.test',  'viewer'),
    ('0f000000-0000-0000-0000-000000000003', '0e000000-0000-0000-0000-000000000002', 'Tom Two',    'tom@two.test',  'purchaser');
