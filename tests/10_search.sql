-- Keyword search over the catalog (stemming: "relationship" matches "relationships").
SELECT pg_temp.assert_eq(
    (SELECT array_agg(slug) FROM items.published_catalog
     WHERE search_vector @@ websearch_to_tsquery('english', 'customer relationship')),
    ARRAY['acme-crm'], 'full-text search matches description');

-- Name hits outrank description hits.
UPDATE items.items SET description = 'Pipeline tool, not a CRM clone.' WHERE id = pg_temp.fx('item.second_tool');
SELECT pg_temp.assert_eq(
    (SELECT array_agg(slug ORDER BY ts_rank(search_vector, websearch_to_tsquery('english', 'crm')) DESC)
     FROM items.published_catalog
     WHERE search_vector @@ websearch_to_tsquery('english', 'crm')),
    ARRAY['acme-crm', 'second-tool'], 'name match ranks above description match');

-- search_vector is generated: it tracks edits.
UPDATE items.items SET tagline = 'Invoicing made simple' WHERE id = pg_temp.fx('item.second_tool');
SELECT pg_temp.assert_true(
    EXISTS (SELECT 1 FROM items.published_catalog
            WHERE slug = 'second-tool' AND search_vector @@ websearch_to_tsquery('english', 'invoice')),
    'search_vector updates with the row');

-- Typo-tolerant name matching via pg_trgm.
SELECT pg_temp.assert_eq(
    (SELECT slug FROM items.published_catalog WHERE name % 'Acme CMR' ORDER BY similarity(name, 'Acme CMR') DESC LIMIT 1),
    'acme-crm', 'trigram similarity finds misspelled name');

-- Hidden listings never leak into search.
UPDATE vendors.vendors SET status = 'suspended' WHERE id = pg_temp.fx('vendor.active');
SELECT pg_temp.assert_true(
    NOT EXISTS (SELECT 1 FROM items.published_catalog WHERE search_vector @@ websearch_to_tsquery('english', 'customer')),
    'suspended vendor''s listing is not searchable');
