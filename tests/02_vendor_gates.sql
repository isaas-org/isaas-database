-- KYB gate: a vendor can't be active unless verified.
SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendors SET status = 'active'
      WHERE id = '0a000000-0000-0000-0000-000000000002'$$,
    '23514', 'pending-verification vendor cannot become active');

SELECT pg_temp.assert_raises(
    $$UPDATE vendors.vendors SET verification_status = 'rejected'
      WHERE id = '0a000000-0000-0000-0000-000000000001'$$,
    '23514', 'active vendor cannot be flipped to rejected without suspending first');

-- A verified vendor can later be suspended (status and verification move independently).
UPDATE vendors.vendors SET status = 'suspended'
WHERE id = '0a000000-0000-0000-0000-000000000003';
SELECT pg_temp.assert_eq(
    (SELECT verification_status FROM vendors.vendors WHERE id = '0a000000-0000-0000-0000-000000000003'),
    'verified'::vendors.verification_status,
    'suspension leaves verification intact');

-- Publish gate: a pending vendor's listing can't leave draft.
SELECT pg_temp.assert_raises(
    $$UPDATE items.items SET status = 'published'
      WHERE id = '0c000000-0000-0000-0000-000000000004'$$,
    '23514', 'pending vendor cannot publish');

SELECT pg_temp.assert_raises(
    $$INSERT INTO items.items (vendor_id, name, slug, status)
      VALUES ('0a000000-0000-0000-0000-000000000002', 'Sneaky', 'sneaky', 'published')$$,
    '23514', 'pending vendor cannot insert an already-published item');

-- ...nor can a suspended one.
SELECT pg_temp.assert_raises(
    $$INSERT INTO items.items (vendor_id, name, slug, status)
      VALUES ('0a000000-0000-0000-0000-000000000003', 'Late', 'late', 'published')$$,
    '23514', 'suspended vendor cannot publish');

-- Pending vendor can still build drafts.
INSERT INTO items.items (vendor_id, name, slug)
VALUES ('0a000000-0000-0000-0000-000000000002', 'Draft Two', 'draft-two');

-- Active vendor publishes; published_at is stamped automatically.
UPDATE items.items SET status = 'published' WHERE id = '0c000000-0000-0000-0000-000000000002';
SELECT pg_temp.assert_true(
    (SELECT published_at IS NOT NULL FROM items.items WHERE id = '0c000000-0000-0000-0000-000000000002'),
    'publishing stamps published_at');

-- updated_at trigger fires.
UPDATE items.items SET updated_at = '2000-01-01', tagline = 'x' WHERE slug = 'acme-crm';
SELECT pg_temp.assert_true(
    (SELECT updated_at > '2000-01-01' FROM items.items WHERE slug = 'acme-crm'),
    'updated_at is maintained by trigger');

-- Slugs are URL-safe.
SELECT pg_temp.assert_raises(
    $$INSERT INTO vendors.vendors (company_name, slug) VALUES ('Bad', 'Bad Slug')$$,
    '23514', 'slug format enforced');

-- Transferring a published listing to a non-active vendor is also gated.
SELECT pg_temp.assert_raises(
    $$UPDATE items.items SET vendor_id = '0a000000-0000-0000-0000-000000000002'
      WHERE id = '0c000000-0000-0000-0000-000000000001'$$,
    '23514', 'published item cannot be moved to a pending vendor');
-- ...but a draft can move freely.
UPDATE items.items SET vendor_id = '0a000000-0000-0000-0000-000000000001'
WHERE id = '0c000000-0000-0000-0000-000000000004';
SELECT pg_temp.assert_eq(
    (SELECT vendor_id FROM items.items WHERE id = '0c000000-0000-0000-0000-000000000004'),
    '0a000000-0000-0000-0000-000000000001'::uuid, 'draft listing can be transferred');
