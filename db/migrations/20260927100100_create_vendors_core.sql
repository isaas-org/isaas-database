-- migrate:up

CREATE TYPE vendors.vendor_status AS ENUM ('pending', 'active', 'suspended');
CREATE TYPE vendors.verification_status AS ENUM ('pending', 'verified', 'rejected');
CREATE TYPE vendors.vendor_user_role AS ENUM ('admin', 'sales', 'support');
CREATE TYPE vendors.address_type AS ENUM ('business', 'mailing');
CREATE TYPE vendors.artifact_type AS ENUM ('business_registration', 'tax_id', 'bank_verification', 'other');
CREATE TYPE vendors.artifact_status AS ENUM ('pending', 'approved', 'rejected');
CREATE TYPE vendors.payout_account_type AS ENUM ('bank', 'other');

-- status = operational gate (can they sell right now).
-- verification_status = KYC/KYB review outcome.
-- They move independently, but KYB is a hard gate: a vendor can only be
-- 'active' while 'verified'.
CREATE TABLE vendors.vendors (
    id                  uuid PRIMARY KEY DEFAULT uuidv7(),
    company_name        text NOT NULL,
    slug                text NOT NULL UNIQUE,
    description         text,
    logo_url            text,
    website_url         text,
    support_email       text,
    status              vendors.vendor_status NOT NULL DEFAULT 'pending',
    verification_status vendors.verification_status NOT NULL DEFAULT 'pending',
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT vendors_active_requires_verified
        CHECK (status <> 'active' OR verification_status = 'verified'),
    CONSTRAINT vendors_slug_format CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

CREATE TABLE vendors.vendor_users (
    id         uuid PRIMARY KEY DEFAULT uuidv7(),
    vendor_id  uuid NOT NULL REFERENCES vendors.vendors (id) ON DELETE CASCADE,
    name       text NOT NULL,
    email      text NOT NULL,
    role       vendors.vendor_user_role NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    -- Target for composite FKs that must stay within one vendor.
    CONSTRAINT vendor_users_id_vendor_key UNIQUE (id, vendor_id)
);
CREATE UNIQUE INDEX vendor_users_email_key ON vendors.vendor_users (lower(email));
CREATE INDEX vendor_users_vendor_id_idx ON vendors.vendor_users (vendor_id);

CREATE TABLE vendors.vendor_addresses (
    id          uuid PRIMARY KEY DEFAULT uuidv7(),
    vendor_id   uuid NOT NULL REFERENCES vendors.vendors (id) ON DELETE CASCADE,
    type        vendors.address_type NOT NULL,
    street      text NOT NULL,
    city        text NOT NULL,
    state       text,
    postal_code text,
    country     char(2) NOT NULL CHECK (country ~ '^[A-Z]{2}$'), -- ISO 3166-1 alpha-2
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX vendor_addresses_vendor_id_idx ON vendors.vendor_addresses (vendor_id);

-- Auditable KYC/KYB document history (resubmissions keep old rows).
CREATE TABLE vendors.vendor_verification_artifacts (
    id                   uuid PRIMARY KEY DEFAULT uuidv7(),
    vendor_id            uuid NOT NULL REFERENCES vendors.vendors (id) ON DELETE CASCADE,
    artifact_type        vendors.artifact_type NOT NULL,
    file_url             text NOT NULL,
    status               vendors.artifact_status NOT NULL DEFAULT 'pending',
    submitted_by_user_id uuid NOT NULL,
    reviewed_by_staff_id uuid, -- no FK yet: internal staff entity is deferred
    reviewed_at          timestamptz,
    review_notes         text,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    -- The submitter must belong to the vendor being verified.
    CONSTRAINT vendor_verification_artifacts_submitter_fkey
        FOREIGN KEY (submitted_by_user_id, vendor_id)
        REFERENCES vendors.vendor_users (id, vendor_id),
    CONSTRAINT vendor_verification_artifacts_reviewed_when_decided
        CHECK ((status = 'pending') = (reviewed_at IS NULL))
);
CREATE INDEX vendor_verification_artifacts_vendor_id_idx
    ON vendors.vendor_verification_artifacts (vendor_id);
CREATE INDEX vendor_verification_artifacts_submitter_idx
    ON vendors.vendor_verification_artifacts (submitted_by_user_id, vendor_id);
CREATE INDEX vendor_verification_artifacts_pending_idx
    ON vendors.vendor_verification_artifacts (created_at) WHERE status = 'pending';

-- Payout destinations only; payout transaction records wait for billing.
CREATE TABLE vendors.payout_accounts (
    id             uuid PRIMARY KEY DEFAULT uuidv7(),
    vendor_id      uuid NOT NULL REFERENCES vendors.vendors (id) ON DELETE CASCADE,
    type           vendors.payout_account_type NOT NULL,
    provider_token text NOT NULL,
    is_default     boolean NOT NULL DEFAULT false,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX payout_accounts_vendor_id_idx ON vendors.payout_accounts (vendor_id);
-- At most one default payout account per vendor.
CREATE UNIQUE INDEX payout_accounts_one_default_per_vendor
    ON vendors.payout_accounts (vendor_id) WHERE is_default;

CREATE TRIGGER vendors_set_updated_at BEFORE UPDATE ON vendors.vendors
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER vendor_users_set_updated_at BEFORE UPDATE ON vendors.vendor_users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER vendor_addresses_set_updated_at BEFORE UPDATE ON vendors.vendor_addresses
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER vendor_verification_artifacts_set_updated_at BEFORE UPDATE ON vendors.vendor_verification_artifacts
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER payout_accounts_set_updated_at BEFORE UPDATE ON vendors.payout_accounts
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- migrate:down

DROP TABLE vendors.payout_accounts;
DROP TABLE vendors.vendor_verification_artifacts;
DROP TABLE vendors.vendor_addresses;
DROP TABLE vendors.vendor_users;
DROP TABLE vendors.vendors;

DROP TYPE vendors.payout_account_type;
DROP TYPE vendors.artifact_status;
DROP TYPE vendors.artifact_type;
DROP TYPE vendors.address_type;
DROP TYPE vendors.vendor_user_role;
DROP TYPE vendors.verification_status;
DROP TYPE vendors.vendor_status;
