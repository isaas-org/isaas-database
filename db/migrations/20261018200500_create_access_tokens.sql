-- migrate:up

-- Personal access tokens, so an agent app can act as one specific user with
-- that user's current role and nothing more. The backend issues the token
-- (isaas_vpat_... / isaas_bpat_...), shows it once and stores only its
-- SHA-256 hash. 32 random bytes can't be guessed, so a fast hash is enough
-- and lets the backend look tokens up by hash directly.

CREATE TABLE vendors.vendor_access_tokens (
    id             uuid PRIMARY KEY DEFAULT uuidv7(),
    vendor_id      uuid NOT NULL,
    vendor_user_id uuid NOT NULL,
    name           text NOT NULL,
    -- The first characters of the token, so the user can tell tokens apart.
    token_prefix   text NOT NULL,
    token_hash     bytea NOT NULL,
    expires_at     timestamptz NOT NULL,
    last_used_at   timestamptz,
    revoked_at     timestamptz,
    created_at     timestamptz NOT NULL DEFAULT now(),
    -- The owner must belong to the vendor the token acts for.
    CONSTRAINT vendor_access_tokens_owner_fkey
        FOREIGN KEY (vendor_user_id, vendor_id)
        REFERENCES vendors.vendor_users (id, vendor_id) ON DELETE CASCADE,
    CONSTRAINT vendor_access_tokens_token_hash_key UNIQUE (token_hash),
    CONSTRAINT vendor_access_tokens_hash_is_sha256 CHECK (octet_length(token_hash) = 32),
    CONSTRAINT vendor_access_tokens_max_lifetime
        CHECK (expires_at > created_at AND expires_at <= created_at + interval '90 days')
);
CREATE INDEX vendor_access_tokens_owner_idx
    ON vendors.vendor_access_tokens (vendor_user_id, vendor_id);

CREATE TABLE buyer_companies.buyer_access_tokens (
    id               uuid PRIMARY KEY DEFAULT uuidv7(),
    buyer_company_id uuid NOT NULL,
    buyer_user_id    uuid NOT NULL,
    name             text NOT NULL,
    token_prefix     text NOT NULL,
    token_hash       bytea NOT NULL,
    expires_at       timestamptz NOT NULL,
    last_used_at     timestamptz,
    revoked_at       timestamptz,
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT buyer_access_tokens_owner_fkey
        FOREIGN KEY (buyer_user_id, buyer_company_id)
        REFERENCES buyer_companies.buyer_users (id, buyer_company_id) ON DELETE CASCADE,
    CONSTRAINT buyer_access_tokens_token_hash_key UNIQUE (token_hash),
    CONSTRAINT buyer_access_tokens_hash_is_sha256 CHECK (octet_length(token_hash) = 32),
    CONSTRAINT buyer_access_tokens_max_lifetime
        CHECK (expires_at > created_at AND expires_at <= created_at + interval '90 days')
);
CREATE INDEX buyer_access_tokens_owner_idx
    ON buyer_companies.buyer_access_tokens (buyer_user_id, buyer_company_id);

-- migrate:down

DROP TABLE buyer_companies.buyer_access_tokens;
DROP TABLE vendors.vendor_access_tokens;
