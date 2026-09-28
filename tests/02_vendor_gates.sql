-- KYB gate: a vendor can only be 'active' while 'verified'.

SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendors SET status = 'active' WHERE id = pg_temp.fx('vendor.pending')$$,
    '23514', 'vendors_active_requires_verified', 'unverified vendor cannot be activated');

SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendors (company_name, slug, status, verification_status)
      VALUES ('Shortcut', 'shortcut', 'active', 'pending')$$,
    '23514', 'vendors_active_requires_verified', 'vendor cannot be inserted active + unverified');

SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendors SET verification_status = 'rejected' WHERE id = pg_temp.fx('vendor.active')$$,
    '23514', 'vendors_active_requires_verified', 'active vendor cannot become rejected without leaving active');

-- status and verification move independently.
UPDATE vendors.vendors SET status = 'suspended' WHERE id = pg_temp.fx('vendor.second');
SELECT pg_temp.assert_eq(
    (SELECT verification_status FROM vendors.vendors WHERE id = pg_temp.fx('vendor.second')),
    'verified'::vendors.verification_status,
    'suspension leaves verification intact');

UPDATE vendors.vendors SET verification_status = 'verified' WHERE id = pg_temp.fx('vendor.pending');
SELECT pg_temp.assert_eq(
    (SELECT status FROM vendors.vendors WHERE id = pg_temp.fx('vendor.pending')),
    'pending'::vendors.vendor_status,
    'verification does not auto-activate a vendor');
UPDATE vendors.vendors SET verification_status = 'pending' WHERE id = pg_temp.fx('vendor.pending');

-- Publish gate: only an ACTIVE vendor's listing can become published.

SELECT pg_temp.assert_raises(
    $$UPDATE items.items SET status = 'published' WHERE id = pg_temp.fx('item.pending_product')$$,
    '23514', 'cannot be published', 'pending vendor''s draft cannot be published');

SELECT pg_temp.assert_raises(
    $$INSERT INTO items.items (vendor_id, name, slug, status)
      VALUES (pg_temp.fx('vendor.pending'), 'Sneaky', 'sneaky', 'published')$$,
    '23514', 'cannot be published', 'pending vendor cannot insert an already-published item');

-- vendor.second was suspended above.
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.items (vendor_id, name, slug, status)
      VALUES (pg_temp.fx('vendor.second'), 'Late', 'late', 'published')$$,
    '23514', 'cannot be published', 'suspended vendor cannot publish');

SELECT pg_temp.assert_raises(
    $$UPDATE items.items SET vendor_id = pg_temp.fx('vendor.pending') WHERE id = pg_temp.fx('item.acme_crm')$$,
    '23514', 'cannot be published', 'published item cannot be transferred to a pending vendor');

-- Pending vendors can still build drafts, and drafts can move between vendors.
INSERT INTO items.items (vendor_id, name, slug) VALUES (pg_temp.fx('vendor.pending'), 'Draft Two', 'draft-two');
UPDATE items.items SET vendor_id = pg_temp.fx('vendor.active') WHERE id = pg_temp.fx('item.pending_product');
SELECT pg_temp.assert_eq(
    (SELECT vendor_id FROM items.items WHERE id = pg_temp.fx('item.pending_product')),
    pg_temp.fx('vendor.active'), 'draft listing can be transferred');

-- Active vendor publishes; published_at is stamped and must stay set.
UPDATE items.items SET status = 'published' WHERE id = pg_temp.fx('item.acme_insights');
SELECT pg_temp.assert_true(
    (SELECT published_at IS NOT NULL FROM items.items WHERE id = pg_temp.fx('item.acme_insights')),
    'publishing stamps published_at');

SELECT pg_temp.assert_raises(
    $$UPDATE items.items SET published_at = NULL WHERE id = pg_temp.fx('item.acme_insights')$$,
    '23514', 'items_published_has_timestamp', 'published item cannot lose published_at');

-- updated_at trigger.
UPDATE items.items SET updated_at = '2000-01-01', tagline = 'x' WHERE id = pg_temp.fx('item.acme_crm');
SELECT pg_temp.assert_true(
    (SELECT updated_at > '2000-01-01' FROM items.items WHERE id = pg_temp.fx('item.acme_crm')),
    'updated_at is maintained by trigger');

-- URL-safe slugs.
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendors (company_name, slug) VALUES ('Bad', 'Bad Slug')$$,
    '23514', 'vendors_slug_format', 'vendor slug format enforced');
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.items (vendor_id, name, slug) VALUES (pg_temp.fx('vendor.active'), 'Bad', 'bad--slug')$$,
    '23514', 'items_slug_format', 'item slug format enforced');
