-- migrate:up

-- One database, one Postgres schema per domain. Cross-domain FKs are allowed
-- (and relied on); each schema is the extraction boundary if a domain is ever
-- split into its own database.
CREATE SCHEMA vendors;
CREATE SCHEMA items;
CREATE SCHEMA buyers;

-- Trigram indexes for fuzzy catalog search.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Shared trigger function: keeps updated_at current on every UPDATE.
CREATE FUNCTION public.set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

-- migrate:down

DROP FUNCTION public.set_updated_at();
DROP EXTENSION IF EXISTS pg_trgm;
DROP SCHEMA buyers;
DROP SCHEMA items;
DROP SCHEMA vendors;
