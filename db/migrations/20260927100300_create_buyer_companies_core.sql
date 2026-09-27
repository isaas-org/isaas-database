-- migrate:up

CREATE TYPE buyer_companies.company_size AS ENUM ('1-10', '11-50', '51-200', '201-1000', '1001-5000', '5000+');
CREATE TYPE buyer_companies.company_status AS ENUM ('active', 'suspended');
CREATE TYPE buyer_companies.verification_status AS ENUM ('unverified', 'pending', 'verified', 'rejected');
CREATE TYPE buyer_companies.buyer_user_role AS ENUM ('admin', 'purchaser', 'approver', 'viewer');
CREATE TYPE buyer_companies.address_type AS ENUM ('billing', 'headquarters');
CREATE TYPE buyer_companies.payment_method_type AS ENUM ('card', 'ach', 'purchase_order');
CREATE TYPE buyer_companies.artifact_type AS ENUM ('business_registration', 'tax_id', 'proof_of_address', 'other');
CREATE TYPE buyer_companies.artifact_status AS ENUM ('pending', 'approved', 'rejected');

-- Buyer verification is optional/triggered (enterprise deals, RFPs, high
-- spend), so verification_status starts at 'unverified' and gates nothing here.
CREATE TABLE buyer_companies.buyer_companies (
    id                  uuid PRIMARY KEY DEFAULT uuidv7(),
    name                text NOT NULL,
    website_url         text,
    industry_id         uuid REFERENCES items.industries (id),
    company_size        buyer_companies.company_size,
    status              buyer_companies.company_status NOT NULL DEFAULT 'active',
    verification_status buyer_companies.verification_status NOT NULL DEFAULT 'unverified',
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX buyer_companies_industry_id_idx ON buyer_companies.buyer_companies (industry_id);

CREATE TABLE buyer_companies.buyer_users (
    id               uuid PRIMARY KEY DEFAULT uuidv7(),
    buyer_company_id uuid NOT NULL REFERENCES buyer_companies.buyer_companies (id) ON DELETE CASCADE,
    name             text NOT NULL,
    email            text NOT NULL,
    role             buyer_companies.buyer_user_role NOT NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    -- Target for composite FKs that must stay within one company.
    CONSTRAINT buyer_users_id_company_key UNIQUE (id, buyer_company_id)
);
CREATE UNIQUE INDEX buyer_users_email_key ON buyer_companies.buyer_users (lower(email));
CREATE INDEX buyer_users_buyer_company_id_idx ON buyer_companies.buyer_users (buyer_company_id);

CREATE TABLE buyer_companies.addresses (
    id               uuid PRIMARY KEY DEFAULT uuidv7(),
    buyer_company_id uuid NOT NULL REFERENCES buyer_companies.buyer_companies (id) ON DELETE CASCADE,
    type             buyer_companies.address_type NOT NULL,
    street           text NOT NULL,
    city             text NOT NULL,
    state            text,
    postal_code      text,
    country          char(2) NOT NULL CHECK (country ~ '^[A-Z]{2}$'), -- ISO 3166-1 alpha-2
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX addresses_buyer_company_id_idx ON buyer_companies.addresses (buyer_company_id);

CREATE TABLE buyer_companies.payment_methods (
    id               uuid PRIMARY KEY DEFAULT uuidv7(),
    buyer_company_id uuid NOT NULL REFERENCES buyer_companies.buyer_companies (id) ON DELETE CASCADE,
    type             buyer_companies.payment_method_type NOT NULL,
    -- Tokenized reference at the payment provider; never raw card/bank data.
    -- Purchase orders are paid against invoices, so they carry no token.
    provider_token   text,
    is_default       boolean NOT NULL DEFAULT false,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payment_methods_token_required
        CHECK (type = 'purchase_order' OR provider_token IS NOT NULL)
);
CREATE INDEX payment_methods_buyer_company_id_idx ON buyer_companies.payment_methods (buyer_company_id);
-- At most one default payment method per company.
CREATE UNIQUE INDEX payment_methods_one_default_per_company
    ON buyer_companies.payment_methods (buyer_company_id) WHERE is_default;

CREATE TABLE buyer_companies.buyer_verification_artifacts (
    id                   uuid PRIMARY KEY DEFAULT uuidv7(),
    buyer_company_id     uuid NOT NULL REFERENCES buyer_companies.buyer_companies (id) ON DELETE CASCADE,
    artifact_type        buyer_companies.artifact_type NOT NULL,
    file_url             text NOT NULL,
    status               buyer_companies.artifact_status NOT NULL DEFAULT 'pending',
    submitted_by_user_id uuid NOT NULL,
    reviewed_by_staff_id uuid, -- no FK yet: internal staff entity is deferred
    reviewed_at          timestamptz,
    review_notes         text,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    -- The submitter must belong to the company being verified.
    CONSTRAINT buyer_verification_artifacts_submitter_fkey
        FOREIGN KEY (submitted_by_user_id, buyer_company_id)
        REFERENCES buyer_companies.buyer_users (id, buyer_company_id),
    CONSTRAINT buyer_verification_artifacts_reviewed_when_decided
        CHECK ((status = 'pending') = (reviewed_at IS NULL))
);
CREATE INDEX buyer_verification_artifacts_company_id_idx
    ON buyer_companies.buyer_verification_artifacts (buyer_company_id);
CREATE INDEX buyer_verification_artifacts_submitter_idx
    ON buyer_companies.buyer_verification_artifacts (submitted_by_user_id, buyer_company_id);
CREATE INDEX buyer_verification_artifacts_pending_idx
    ON buyer_companies.buyer_verification_artifacts (created_at) WHERE status = 'pending';

CREATE TRIGGER buyer_companies_set_updated_at BEFORE UPDATE ON buyer_companies.buyer_companies
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER buyer_users_set_updated_at BEFORE UPDATE ON buyer_companies.buyer_users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER addresses_set_updated_at BEFORE UPDATE ON buyer_companies.addresses
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER payment_methods_set_updated_at BEFORE UPDATE ON buyer_companies.payment_methods
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER buyer_verification_artifacts_set_updated_at BEFORE UPDATE ON buyer_companies.buyer_verification_artifacts
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- migrate:down

DROP TABLE buyer_companies.buyer_verification_artifacts;
DROP TABLE buyer_companies.payment_methods;
DROP TABLE buyer_companies.addresses;
DROP TABLE buyer_companies.buyer_users;
DROP TABLE buyer_companies.buyer_companies;

DROP TYPE buyer_companies.artifact_status;
DROP TYPE buyer_companies.artifact_type;
DROP TYPE buyer_companies.payment_method_type;
DROP TYPE buyer_companies.address_type;
DROP TYPE buyer_companies.buyer_user_role;
DROP TYPE buyer_companies.verification_status;
DROP TYPE buyer_companies.company_status;
DROP TYPE buyer_companies.company_size;
