-- migrate:up

-- ---------------------------------------------------------------------------
-- Users: link to the Auth0 identity, and disable instead of delete
-- ---------------------------------------------------------------------------
-- auth_provider_id is the Auth0 subject (JWT "sub"). Invited and seeded users
-- have no Auth0 account yet, so it stays NULL until their first login, when
-- the backend binds it by verified email. UNIQUE still allows many NULLs.

CREATE TYPE vendors.vendor_user_status AS ENUM ('active', 'disabled');
CREATE TYPE buyer_companies.buyer_user_status AS ENUM ('active', 'disabled');

ALTER TABLE vendors.vendor_users
    ADD COLUMN auth_provider_id text,
    ADD COLUMN status vendors.vendor_user_status NOT NULL DEFAULT 'active',
    ADD CONSTRAINT vendor_users_auth_provider_id_key UNIQUE (auth_provider_id);

ALTER TABLE buyer_companies.buyer_users
    ADD COLUMN auth_provider_id text,
    ADD COLUMN status buyer_companies.buyer_user_status NOT NULL DEFAULT 'active',
    ADD CONSTRAINT buyer_users_auth_provider_id_key UNIQUE (auth_provider_id);

-- ---------------------------------------------------------------------------
-- Companies: SSO hook and who verified them
-- ---------------------------------------------------------------------------
-- sso_connection_id is the Auth0 enterprise connection. Staff set it only for
-- a verified company, because it lets the company's own IdP add members.

ALTER TABLE vendors.vendors
    ADD COLUMN sso_connection_id text,
    ADD COLUMN verified_by_staff_id uuid,
    ADD COLUMN verified_at timestamptz,
    ADD CONSTRAINT vendors_sso_connection_id_key UNIQUE (sso_connection_id),
    ADD CONSTRAINT vendors_verified_by_staff_id_fkey
        FOREIGN KEY (verified_by_staff_id) REFERENCES platform.staff_users (id),
    ADD CONSTRAINT vendors_sso_requires_verified
        CHECK (sso_connection_id IS NULL OR verification_status = 'verified');

ALTER TABLE buyer_companies.buyer_companies
    ADD COLUMN sso_connection_id text,
    ADD COLUMN verified_by_staff_id uuid,
    ADD COLUMN verified_at timestamptz,
    ADD CONSTRAINT buyer_companies_sso_connection_id_key UNIQUE (sso_connection_id),
    ADD CONSTRAINT buyer_companies_verified_by_staff_id_fkey
        FOREIGN KEY (verified_by_staff_id) REFERENCES platform.staff_users (id),
    ADD CONSTRAINT buyer_companies_sso_requires_verified
        CHECK (sso_connection_id IS NULL OR verification_status = 'verified');

-- Rows verified before this migration (seed data) get their last update time.
-- verified_by_staff_id stays NULL for them: no staff member reviewed them.
UPDATE vendors.vendors SET verified_at = updated_at WHERE verification_status = 'verified';
UPDATE buyer_companies.buyer_companies SET verified_at = updated_at WHERE verification_status = 'verified';

ALTER TABLE vendors.vendors
    ADD CONSTRAINT vendors_verified_has_timestamp
        CHECK ((verification_status = 'verified') = (verified_at IS NOT NULL)),
    ADD CONSTRAINT vendors_verifier_requires_verified
        CHECK (verified_by_staff_id IS NULL OR verification_status = 'verified');

ALTER TABLE buyer_companies.buyer_companies
    ADD CONSTRAINT buyer_companies_verified_has_timestamp
        CHECK ((verification_status = 'verified') = (verified_at IS NOT NULL)),
    ADD CONSTRAINT buyer_companies_verifier_requires_verified
        CHECK (verified_by_staff_id IS NULL OR verification_status = 'verified');

-- Stamps verified_at when a company becomes verified and clears the
-- verification fields when it stops being verified, the same way
-- items.enforce_publish_gate stamps published_at. Shared by both company
-- tables; their verification_status enums differ, so compare as text.
CREATE FUNCTION public.stamp_verified_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.verification_status::text = 'verified' THEN
        IF TG_OP = 'INSERT' OR OLD.verification_status IS DISTINCT FROM NEW.verification_status THEN
            NEW.verified_at := coalesce(NEW.verified_at, now());
        END IF;
    ELSE
        NEW.verified_at := NULL;
        NEW.verified_by_staff_id := NULL;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER vendors_stamp_verified_at
    BEFORE INSERT OR UPDATE OF verification_status ON vendors.vendors
    FOR EACH ROW EXECUTE FUNCTION public.stamp_verified_at();
CREATE TRIGGER buyer_companies_stamp_verified_at
    BEFORE INSERT OR UPDATE OF verification_status ON buyer_companies.buyer_companies
    FOR EACH ROW EXECUTE FUNCTION public.stamp_verified_at();

-- migrate:down

DROP TRIGGER buyer_companies_stamp_verified_at ON buyer_companies.buyer_companies;
DROP TRIGGER vendors_stamp_verified_at ON vendors.vendors;
DROP FUNCTION public.stamp_verified_at();

ALTER TABLE buyer_companies.buyer_companies
    DROP COLUMN verified_at,
    DROP COLUMN verified_by_staff_id,
    DROP COLUMN sso_connection_id;
ALTER TABLE vendors.vendors
    DROP COLUMN verified_at,
    DROP COLUMN verified_by_staff_id,
    DROP COLUMN sso_connection_id;

ALTER TABLE buyer_companies.buyer_users
    DROP COLUMN status,
    DROP COLUMN auth_provider_id;
ALTER TABLE vendors.vendor_users
    DROP COLUMN status,
    DROP COLUMN auth_provider_id;

DROP TYPE buyer_companies.buyer_user_status;
DROP TYPE vendors.vendor_user_status;
