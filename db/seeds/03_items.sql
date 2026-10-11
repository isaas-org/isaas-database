-- Sample item listings, one or two per vendor. Everhire Payroll and Cascade
-- Workflow are left 'draft' (Payroll because it's unfinished, Cascade
-- because its vendor isn't 'active' yet -- the publish gate would reject it
-- as 'published' anyway).
--
-- Idempotent: conflicts on slug.

INSERT INTO items.items (vendor_id, name, slug, tagline, description, logo_url, website_url, status)
SELECT v.id, i.name, i.slug, i.tagline, i.description, i.logo_url, i.website_url, i.status::items.item_status
FROM vendors.vendors v
JOIN (VALUES
    ('northstar-crm',   'Northstar CRM',        'northstar-crm',        'Pipeline management for growing sales teams',
        'Track leads, deals and customer relationships in one place, with automation for the busywork.',
        'https://placehold.co/200x200?text=Northstar+CRM', 'https://northstar-crm.test', 'published'),
    ('pulseboard',       'Pulseboard Analytics', 'pulseboard-analytics', 'Real-time dashboards for product and revenue teams',
        'Build live dashboards and reports without waiting on a data team.',
        'https://placehold.co/200x200?text=Pulseboard', 'https://pulseboard.test', 'published'),
    ('everhire',          'Everhire ATS',         'everhire-ats',         'Applicant tracking built for fast-moving teams',
        'Manage candidate pipelines, interviews and offers end to end.',
        'https://placehold.co/200x200?text=Everhire+ATS', 'https://everhire.test', 'published'),
    ('everhire',          'Everhire Payroll',     'everhire-payroll',     'Payroll for distributed teams',
        'Multi-country payroll and compliance, still in development.',
        'https://placehold.co/200x200?text=Everhire+Payroll', 'https://everhire.test', 'draft'),
    ('northwind-devops',  'Northwind Pipelines',  'northwind-pipelines',  'CI/CD built for platform teams',
        'Build, test and deploy pipelines with a built-in container registry and secrets management.',
        'https://placehold.co/200x200?text=Northwind', 'https://northwind-devops.test', 'published'),
    ('cascade-labs',       'Cascade Workflow',    'cascade-workflow',     'Workflow automation',
        'No-code workflow automation across your tools.',
        'https://placehold.co/200x200?text=Cascade', 'https://cascade-labs.test', 'draft')
) AS i(vendor_slug, name, slug, tagline, description, logo_url, website_url, status) ON i.vendor_slug = v.slug
ON CONFLICT (slug) DO NOTHING;
