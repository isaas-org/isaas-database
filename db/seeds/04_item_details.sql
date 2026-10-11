-- Pricing plans, features, taxonomy links and media for the items seeded in
-- 03_items.sql. Plans/features/links conflict on their natural key; media
-- has no natural-key constraint, so it's guarded with NOT EXISTS instead.

-- ---------------------------------------------------------------------------
-- Pricing plans
-- ---------------------------------------------------------------------------

INSERT INTO items.pricing_plans (item_id, tier_name, pricing_model, price, billing_frequency, usage_limits)
SELECT it.id, p.tier_name, p.pricing_model::items.pricing_model, p.price,
       p.billing_frequency::items.billing_frequency, p.usage_limits::jsonb
FROM items.items it
JOIN (VALUES
    ('northstar-crm',        'Starter',    'seat',     12.00, 'monthly', NULL),
    ('northstar-crm',        'Growth',     'seat',     29.00, 'monthly', NULL),
    ('northstar-crm',        'Enterprise', 'seat',     65.00, 'annual',  NULL),
    ('pulseboard-analytics', 'Free',       'freemium',  0.00, NULL,      NULL),
    ('pulseboard-analytics', 'Pro',        'flat',     49.00, 'monthly', NULL),
    ('pulseboard-analytics', 'Business',   'flat',    990.00, 'annual',  NULL),
    ('everhire-ats',         'Starter',    'seat',      8.00, 'monthly', NULL),
    ('everhire-ats',         'Growth',     'seat',     18.00, 'monthly', NULL),
    ('everhire-payroll',     'Standard',   'flat',     99.00, 'monthly', NULL),
    ('northwind-pipelines',  'Usage',      'usage',     0.02, 'monthly', '{"included_build_minutes": 2000}'),
    ('northwind-pipelines',  'Enterprise', 'flat',  12000.00, 'annual',  NULL)
) AS p(item_slug, tier_name, pricing_model, price, billing_frequency, usage_limits) ON p.item_slug = it.slug
ON CONFLICT (item_id, tier_name, billing_frequency) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Features
-- ---------------------------------------------------------------------------

INSERT INTO items.features (item_id, feature_name, description)
SELECT it.id, f.feature_name, f.description
FROM items.items it
JOIN (VALUES
    ('northstar-crm',        'Pipeline management', 'Visual drag-and-drop sales pipeline'),
    ('northstar-crm',        'Email sync',           'Two-way sync with Gmail and Outlook'),
    ('northstar-crm',        'Custom fields',         NULL),
    ('northstar-crm',        'API access',            'REST API for custom integrations'),
    ('pulseboard-analytics', 'Real-time dashboards',  NULL),
    ('pulseboard-analytics', 'Custom reports',        NULL),
    ('pulseboard-analytics', 'Data export',           'CSV and API export'),
    ('everhire-ats',         'Candidate pipeline',    NULL),
    ('everhire-ats',         'Interview scheduling',  'Calendar sync for interviewers'),
    ('northwind-pipelines',  'CI/CD pipelines',       NULL),
    ('northwind-pipelines',  'Container registry',    NULL),
    ('northwind-pipelines',  'Secrets management',    NULL)
) AS f(item_slug, feature_name, description) ON f.item_slug = it.slug
ON CONFLICT (item_id, feature_name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Category links
-- ---------------------------------------------------------------------------

INSERT INTO items.item_categories (item_id, category_id)
SELECT it.id, c.id
FROM items.items it
JOIN (VALUES
    ('northstar-crm',        'crm'),
    ('pulseboard-analytics', 'data-analytics'),
    ('pulseboard-analytics', 'business-intelligence'),
    ('everhire-ats',         'hr-people'),
    ('everhire-payroll',     'hr-people'),
    ('northwind-pipelines',  'devops-infrastructure'),
    ('cascade-workflow',     'project-management')
) AS l(item_slug, category_slug) ON l.item_slug = it.slug
JOIN items.categories c ON c.slug = l.category_slug
ON CONFLICT (item_id, category_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Integration links
-- ---------------------------------------------------------------------------

INSERT INTO items.item_integrations (item_id, integration_id)
SELECT it.id, i.id
FROM items.items it
JOIN (VALUES
    ('northstar-crm',        'slack'),
    ('northstar-crm',        'google-workspace'),
    ('pulseboard-analytics', 'salesforce'),
    ('pulseboard-analytics', 'slack'),
    ('everhire-ats',         'google-workspace'),
    ('everhire-ats',         'microsoft-365'),
    ('northwind-pipelines',  'slack'),
    ('northwind-pipelines',  'zapier')
) AS l(item_slug, integration_slug) ON l.item_slug = it.slug
JOIN items.integrations i ON i.slug = l.integration_slug
ON CONFLICT (item_id, integration_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Certification links
-- ---------------------------------------------------------------------------

INSERT INTO items.item_certifications (item_id, certification_id)
SELECT it.id, c.id
FROM items.items it
JOIN (VALUES
    ('northstar-crm',        'soc-2-type-ii'),
    ('pulseboard-analytics', 'soc-2-type-ii'),
    ('pulseboard-analytics', 'gdpr'),
    ('everhire-ats',         'gdpr'),
    ('northwind-pipelines',  'soc-2-type-ii'),
    ('northwind-pipelines',  'iso-27001')
) AS l(item_slug, certification_slug) ON l.item_slug = it.slug
JOIN items.certifications c ON c.slug = l.certification_slug
ON CONFLICT (item_id, certification_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Media (one logo-style image, one screenshot, per published item)
-- ---------------------------------------------------------------------------

INSERT INTO items.item_media (item_id, media_type, url, sort_order)
SELECT it.id, m.media_type::items.media_type, m.url, m.sort_order
FROM items.items it
JOIN (VALUES
    ('northstar-crm',        'image', 'https://placehold.co/1200x800?text=Northstar+CRM+Dashboard', 0),
    ('northstar-crm',        'image', 'https://placehold.co/1200x800?text=Northstar+CRM+Pipeline',   1),
    ('pulseboard-analytics', 'image', 'https://placehold.co/1200x800?text=Pulseboard+Dashboard',      0),
    ('everhire-ats',         'image', 'https://placehold.co/1200x800?text=Everhire+ATS+Pipeline',     0),
    ('northwind-pipelines',  'image', 'https://placehold.co/1200x800?text=Northwind+Pipelines',       0)
) AS m(item_slug, media_type, url, sort_order) ON m.item_slug = it.slug
WHERE NOT EXISTS (
    SELECT 1 FROM items.item_media existing
    WHERE existing.item_id = it.id AND existing.url = m.url
);
