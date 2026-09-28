-- Shared test world, loaded inside each test's transaction and rolled back after.
-- Refer to rows by name with pg_temp.fx('<name>'); ids are generated.
--
--   vendor.active        Acme CRM Inc     active / verified
--   vendor.pending       Pending Soft     pending / pending
--   vendor.second        Second Vendor    active / verified
--
--   item.acme_crm        vendor.active   published   (plan.acme_starter)
--   item.acme_insights   vendor.active   draft       (plan.insights_basic)
--   item.second_tool     vendor.second   published   (plan.second_pro)
--   item.pending_product vendor.pending  draft
--
--   company.one          buyer_user.one_admin, buyer_user.one_viewer
--   company.two          buyer_user.two_purchaser

INSERT INTO pg_temp.fixture_ids (name) VALUES
    ('vendor.active'), ('vendor.pending'), ('vendor.second'),
    ('vendor_user.active_admin'), ('vendor_user.pending_admin'),
    ('category.crm'), ('category.analytics'), ('industry.healthcare'),
    ('item.acme_crm'), ('item.acme_insights'), ('item.second_tool'), ('item.pending_product'),
    ('plan.acme_starter'), ('plan.insights_basic'), ('plan.second_pro'),
    ('company.one'), ('company.two'),
    ('buyer_user.one_admin'), ('buyer_user.one_viewer'), ('buyer_user.two_purchaser');

INSERT INTO vendors.vendors (id, company_name, slug, status, verification_status) VALUES
    (pg_temp.fx('vendor.active'),  'Acme CRM Inc',  'acme-crm',      'active',  'verified'),
    (pg_temp.fx('vendor.pending'), 'Pending Soft',  'pending-soft',  'pending', 'pending'),
    (pg_temp.fx('vendor.second'),  'Second Vendor', 'second-vendor', 'active',  'verified');

INSERT INTO vendors.vendor_users (id, vendor_id, name, email, role) VALUES
    (pg_temp.fx('vendor_user.active_admin'),  pg_temp.fx('vendor.active'),  'Ana Admin',   'ana@acme.test',    'admin'),
    (pg_temp.fx('vendor_user.pending_admin'), pg_temp.fx('vendor.pending'), 'Pat Pending', 'pat@pending.test', 'admin');

INSERT INTO items.categories (id, name, slug) VALUES
    (pg_temp.fx('category.crm'),       'CRM',            'crm'),
    (pg_temp.fx('category.analytics'), 'Data Analytics', 'data-analytics');

INSERT INTO items.industries (id, name, slug) VALUES
    (pg_temp.fx('industry.healthcare'), 'Healthcare', 'healthcare');

INSERT INTO items.items (id, vendor_id, name, slug, tagline, description, status) VALUES
    (pg_temp.fx('item.acme_crm'), pg_temp.fx('vendor.active'),
     'Acme CRM', 'acme-crm', 'Pipeline management for small teams',
     'Track leads, deals and customer relationships.', 'published'),
    (pg_temp.fx('item.acme_insights'), pg_temp.fx('vendor.active'),
     'Acme Insights', 'acme-insights', 'Dashboards', 'Analytics add-on.', 'draft'),
    (pg_temp.fx('item.second_tool'), pg_temp.fx('vendor.second'),
     'Second Tool', 'second-tool', NULL, NULL, 'published'),
    (pg_temp.fx('item.pending_product'), pg_temp.fx('vendor.pending'),
     'Pending Product', 'pending-product', NULL, NULL, 'draft');

INSERT INTO items.pricing_plans (id, item_id, tier_name, pricing_model, price, billing_frequency) VALUES
    (pg_temp.fx('plan.acme_starter'),   pg_temp.fx('item.acme_crm'),      'Starter', 'seat', 10.00, 'monthly'),
    (pg_temp.fx('plan.insights_basic'), pg_temp.fx('item.acme_insights'), 'Basic',   'flat', 20.00, 'monthly'),
    (pg_temp.fx('plan.second_pro'),     pg_temp.fx('item.second_tool'),   'Pro',     'flat', 99.00, 'annual');

INSERT INTO buyer_companies.buyer_companies (id, name, industry_id, company_size) VALUES
    (pg_temp.fx('company.one'), 'Buyer One LLC',  pg_temp.fx('industry.healthcare'), '51-200'),
    (pg_temp.fx('company.two'), 'Buyer Two Corp', NULL,                              '5000+');

INSERT INTO buyer_companies.buyer_users (id, buyer_company_id, name, email, role) VALUES
    (pg_temp.fx('buyer_user.one_admin'),     pg_temp.fx('company.one'), 'Bo Buyer',   'bo@one.test',  'admin'),
    (pg_temp.fx('buyer_user.one_viewer'),    pg_temp.fx('company.one'), 'Bea Viewer', 'bea@one.test', 'viewer'),
    (pg_temp.fx('buyer_user.two_purchaser'), pg_temp.fx('company.two'), 'Tom Two',    'tom@two.test', 'purchaser');
