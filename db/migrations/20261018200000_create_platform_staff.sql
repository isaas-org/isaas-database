-- migrate:up

-- Marketplace staff: the people who review KYC/KYB and act on disputes.
-- They belong to neither side of the marketplace, so they get their own schema.
CREATE SCHEMA platform;

CREATE TYPE platform.staff_role AS ENUM ('admin', 'reviewer');
CREATE TYPE platform.staff_status AS ENUM ('active', 'disabled');

-- auth_provider_id is the Auth0 subject. It stays NULL until the person's
-- first login, when the backend binds it by verified email.
CREATE TABLE platform.staff_users (
    id               uuid PRIMARY KEY DEFAULT uuidv7(),
    auth_provider_id text,
    name             text NOT NULL,
    email            text NOT NULL,
    role             platform.staff_role NOT NULL,
    status           platform.staff_status NOT NULL DEFAULT 'active',
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT staff_users_auth_provider_id_key UNIQUE (auth_provider_id)
);
CREATE UNIQUE INDEX staff_users_email_key ON platform.staff_users (lower(email));

CREATE TRIGGER staff_users_set_updated_at BEFORE UPDATE ON platform.staff_users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- The staff entity the artifact tables were waiting for. Staff are disabled,
-- not deleted, so a review never loses its reviewer.
ALTER TABLE vendors.vendor_verification_artifacts
    ADD CONSTRAINT vendor_verification_artifacts_reviewed_by_staff_id_fkey
        FOREIGN KEY (reviewed_by_staff_id) REFERENCES platform.staff_users (id);
ALTER TABLE buyer_companies.buyer_verification_artifacts
    ADD CONSTRAINT buyer_verification_artifacts_reviewed_by_staff_id_fkey
        FOREIGN KEY (reviewed_by_staff_id) REFERENCES platform.staff_users (id);

-- migrate:down

ALTER TABLE buyer_companies.buyer_verification_artifacts
    DROP CONSTRAINT buyer_verification_artifacts_reviewed_by_staff_id_fkey;
ALTER TABLE vendors.vendor_verification_artifacts
    DROP CONSTRAINT vendor_verification_artifacts_reviewed_by_staff_id_fkey;

DROP TABLE platform.staff_users;
DROP TYPE platform.staff_status;
DROP TYPE platform.staff_role;
DROP SCHEMA platform;
