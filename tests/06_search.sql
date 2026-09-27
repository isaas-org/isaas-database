-- Keyword search over the catalog (stemming: "relationship" matches "relationships").
SELECT pg_temp.assert_eq(
    (SELECT array_agg(slug) FROM items.published_catalog
     WHERE search_vector @@ websearch_to_tsquery('english', 'customer relationship')),
    ARRAY['acme-crm'], 'full-text search matches description');

-- Name hits outrank description hits.
UPDATE items.items SET description = 'Pipeline tool, not a CRM clone.' WHERE slug = 'suspendable-tool';
SELECT pg_temp.assert_eq(
    (SELECT slug FROM items.published_catalog
     WHERE search_vector @@ websearch_to_tsquery('english', 'crm')
     ORDER BY ts_rank(search_vector, websearch_to_tsquery('english', 'crm')) DESC
     LIMIT 1),
    'acme-crm', 'name match ranks first');

-- Typo-tolerant name matching via pg_trgm.
SELECT pg_temp.assert_eq(
    (SELECT slug FROM items.published_catalog WHERE name % 'Acme CMR' ORDER BY similarity(name, 'Acme CMR') DESC LIMIT 1),
    'acme-crm', 'trigram similarity finds misspelled name');
