-- Operator-managed reference data: categories, industries, integrations,
-- certifications. Every insert conflicts on the table's natural key (slug),
-- so this file is safe to re-run.

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------

INSERT INTO items.categories (name, slug, description, sort_order) VALUES
    ('CRM',                     'crm',                   'Customer relationship management',          10),
    ('Project Management',      'project-management',    'Planning and tracking work',                 20),
    ('Data Analytics',          'data-analytics',         'Reporting and business intelligence',        30),
    ('HR & People',             'hr-people',               'Hiring, payroll and people management',      40),
    ('DevOps & Infrastructure', 'devops-infrastructure',   'CI/CD, hosting and infrastructure tooling',  50)
ON CONFLICT (slug) DO NOTHING;

-- Subcategory of Data Analytics.
INSERT INTO items.categories (parent_category_id, name, slug, description, sort_order)
SELECT id, 'Business Intelligence', 'business-intelligence', 'Dashboards and BI tooling', 10
FROM items.categories WHERE slug = 'data-analytics'
ON CONFLICT (slug) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Industries
-- ---------------------------------------------------------------------------

INSERT INTO items.industries (name, slug) VALUES
    ('Healthcare',          'healthcare'),
    ('Financial Services',  'financial-services'),
    ('Retail & E-commerce', 'retail-ecommerce'),
    ('Technology',          'technology'),
    ('Manufacturing',       'manufacturing')
ON CONFLICT (slug) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Integrations
-- ---------------------------------------------------------------------------

INSERT INTO items.integrations (name, slug, website_url) VALUES
    ('Slack',             'slack',             'https://slack.com'),
    ('Salesforce',        'salesforce',        'https://salesforce.com'),
    ('Google Workspace',  'google-workspace',  'https://workspace.google.com'),
    ('Microsoft 365',     'microsoft-365',     'https://www.microsoft.com/microsoft-365'),
    ('Zapier',            'zapier',            'https://zapier.com')
ON CONFLICT (slug) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Certifications
-- ---------------------------------------------------------------------------

INSERT INTO items.certifications (name, slug, description) VALUES
    ('SOC 2 Type II', 'soc-2-type-ii', 'Independently audited security, availability and confidentiality controls'),
    ('HIPAA',          'hipaa',         'Meets U.S. healthcare data privacy and security requirements'),
    ('GDPR',           'gdpr',          'Compliant with EU data protection requirements'),
    ('ISO 27001',      'iso-27001',     'Certified information security management system')
ON CONFLICT (slug) DO NOTHING;
