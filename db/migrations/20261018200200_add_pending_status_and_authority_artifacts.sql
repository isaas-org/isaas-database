-- migrate:up

-- New enum values only. Postgres can't use a value added by ALTER TYPE ... ADD
-- VALUE in the same transaction, and dbmate runs each migration in one, so
-- anything that uses them (defaults, checks, triggers) is in the next migration.

-- Buyer companies start 'pending' until staff verify them, like vendors.
ALTER TYPE buyer_companies.company_status ADD VALUE 'pending' BEFORE 'active';

-- Verification proves the person may act for the company, not only that the
-- company exists: an officer listing or signed authorisation, plus a photo ID.
ALTER TYPE vendors.artifact_type ADD VALUE 'proof_of_authority' BEFORE 'other';
ALTER TYPE vendors.artifact_type ADD VALUE 'identity_document' BEFORE 'other';
ALTER TYPE buyer_companies.artifact_type ADD VALUE 'proof_of_authority' BEFORE 'other';
ALTER TYPE buyer_companies.artifact_type ADD VALUE 'identity_document' BEFORE 'other';

-- migrate:down

-- Postgres can't drop an enum value, so each type is recreated without the
-- new values. This fails (and the rollback stops) if any row still uses one.

ALTER TABLE buyer_companies.buyer_verification_artifacts
    ALTER COLUMN artifact_type TYPE text;
DROP TYPE buyer_companies.artifact_type;
CREATE TYPE buyer_companies.artifact_type AS ENUM ('business_registration', 'tax_id', 'proof_of_address', 'other');
ALTER TABLE buyer_companies.buyer_verification_artifacts
    ALTER COLUMN artifact_type TYPE buyer_companies.artifact_type
    USING artifact_type::buyer_companies.artifact_type;

ALTER TABLE vendors.vendor_verification_artifacts
    ALTER COLUMN artifact_type TYPE text;
DROP TYPE vendors.artifact_type;
CREATE TYPE vendors.artifact_type AS ENUM ('business_registration', 'tax_id', 'bank_verification', 'other');
ALTER TABLE vendors.vendor_verification_artifacts
    ALTER COLUMN artifact_type TYPE vendors.artifact_type
    USING artifact_type::vendors.artifact_type;

ALTER TABLE buyer_companies.buyer_companies
    ALTER COLUMN status DROP DEFAULT,
    ALTER COLUMN status TYPE text;
DROP TYPE buyer_companies.company_status;
CREATE TYPE buyer_companies.company_status AS ENUM ('active', 'suspended');
ALTER TABLE buyer_companies.buyer_companies
    ALTER COLUMN status TYPE buyer_companies.company_status
    USING status::buyer_companies.company_status,
    ALTER COLUMN status SET DEFAULT 'active';
