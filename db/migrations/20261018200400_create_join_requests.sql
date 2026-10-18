-- migrate:up

-- One audit trail of how every member after the first got access:
--   peer_approval       the person asked to join; an admin approved or rejected
--   sso_auto_provision  the company's own IdP vouched for them (approved at once)
--   admin_invite        an admin added them by email (approved at once)
-- requested_role is only the ask. The role written to the user row is the
-- authoritative one. A user row is created by the backend on approval.

CREATE TYPE vendors.join_request_status AS ENUM ('pending', 'approved', 'rejected');
CREATE TYPE vendors.join_grant_path AS ENUM ('peer_approval', 'sso_auto_provision', 'admin_invite');
CREATE TYPE buyer_companies.join_request_status AS ENUM ('pending', 'approved', 'rejected');
CREATE TYPE buyer_companies.join_grant_path AS ENUM ('peer_approval', 'sso_auto_provision', 'admin_invite');

CREATE TABLE vendors.vendor_join_requests (
    id                  uuid PRIMARY KEY DEFAULT uuidv7(),
    vendor_id           uuid NOT NULL REFERENCES vendors.vendors (id) ON DELETE CASCADE,
    -- NULL only for an invite: the invitee may not have an Auth0 account yet.
    auth_provider_id    text,
    name                text NOT NULL,
    email               text NOT NULL,
    requested_role      vendors.vendor_user_role NOT NULL,
    status              vendors.join_request_status NOT NULL DEFAULT 'pending',
    granted_via         vendors.join_grant_path NOT NULL,
    reviewed_by_user_id uuid,
    reviewed_at         timestamptz,
    review_notes        text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    -- The reviewer must belong to the vendor being joined. Users are disabled,
    -- not deleted, so the reviewer stays on record.
    CONSTRAINT vendor_join_requests_reviewer_fkey
        FOREIGN KEY (reviewed_by_user_id, vendor_id)
        REFERENCES vendors.vendor_users (id, vendor_id),
    CONSTRAINT vendor_join_requests_reviewed_when_decided
        CHECK ((status = 'pending') = (reviewed_at IS NULL)),
    CONSTRAINT vendor_join_requests_identity_required
        CHECK (granted_via = 'admin_invite' OR auth_provider_id IS NOT NULL),
    CONSTRAINT vendor_join_requests_path_rules CHECK (
        CASE granted_via
            WHEN 'sso_auto_provision' THEN status = 'approved' AND reviewed_by_user_id IS NULL
            WHEN 'admin_invite'       THEN status = 'approved' AND reviewed_by_user_id IS NOT NULL
            ELSE (status = 'pending') = (reviewed_by_user_id IS NULL)
        END)
);
CREATE INDEX vendor_join_requests_vendor_id_idx ON vendors.vendor_join_requests (vendor_id, status);
CREATE INDEX vendor_join_requests_reviewer_idx
    ON vendors.vendor_join_requests (reviewed_by_user_id, vendor_id);
-- One open request per person per vendor.
CREATE UNIQUE INDEX vendor_join_requests_one_pending
    ON vendors.vendor_join_requests (vendor_id, auth_provider_id) WHERE status = 'pending';

CREATE TABLE buyer_companies.buyer_join_requests (
    id                  uuid PRIMARY KEY DEFAULT uuidv7(),
    buyer_company_id    uuid NOT NULL REFERENCES buyer_companies.buyer_companies (id) ON DELETE CASCADE,
    auth_provider_id    text,
    name                text NOT NULL,
    email               text NOT NULL,
    requested_role      buyer_companies.buyer_user_role NOT NULL,
    status              buyer_companies.join_request_status NOT NULL DEFAULT 'pending',
    granted_via         buyer_companies.join_grant_path NOT NULL,
    reviewed_by_user_id uuid,
    reviewed_at         timestamptz,
    review_notes        text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT buyer_join_requests_reviewer_fkey
        FOREIGN KEY (reviewed_by_user_id, buyer_company_id)
        REFERENCES buyer_companies.buyer_users (id, buyer_company_id),
    CONSTRAINT buyer_join_requests_reviewed_when_decided
        CHECK ((status = 'pending') = (reviewed_at IS NULL)),
    CONSTRAINT buyer_join_requests_identity_required
        CHECK (granted_via = 'admin_invite' OR auth_provider_id IS NOT NULL),
    CONSTRAINT buyer_join_requests_path_rules CHECK (
        CASE granted_via
            WHEN 'sso_auto_provision' THEN status = 'approved' AND reviewed_by_user_id IS NULL
            WHEN 'admin_invite'       THEN status = 'approved' AND reviewed_by_user_id IS NOT NULL
            ELSE (status = 'pending') = (reviewed_by_user_id IS NULL)
        END)
);
CREATE INDEX buyer_join_requests_company_id_idx
    ON buyer_companies.buyer_join_requests (buyer_company_id, status);
CREATE INDEX buyer_join_requests_reviewer_idx
    ON buyer_companies.buyer_join_requests (reviewed_by_user_id, buyer_company_id);
CREATE UNIQUE INDEX buyer_join_requests_one_pending
    ON buyer_companies.buyer_join_requests (buyer_company_id, auth_provider_id) WHERE status = 'pending';

-- Only an active (so verified) company can be asked to join or add members
-- through SSO. While pending, an admin invite is the only way in, so an
-- impostor's unverified company can't collect a real company's employees.
CREATE FUNCTION vendors.enforce_join_request_gate() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_status vendors.vendor_status;
BEGIN
    IF NEW.granted_via <> 'admin_invite' THEN
        SELECT status INTO v_status
        FROM vendors.vendors WHERE id = NEW.vendor_id
        FOR SHARE;

        IF v_status IS DISTINCT FROM 'active' THEN
            RAISE EXCEPTION 'join request not allowed: vendor % is %',
                NEW.vendor_id, coalesce(v_status::text, 'missing')
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION buyer_companies.enforce_join_request_gate() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_status buyer_companies.company_status;
BEGIN
    IF NEW.granted_via <> 'admin_invite' THEN
        SELECT status INTO v_status
        FROM buyer_companies.buyer_companies WHERE id = NEW.buyer_company_id
        FOR SHARE;

        IF v_status IS DISTINCT FROM 'active' THEN
            RAISE EXCEPTION 'join request not allowed: buyer company % is %',
                NEW.buyer_company_id, coalesce(v_status::text, 'missing')
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER vendor_join_requests_enforce_join_request_gate
    BEFORE INSERT ON vendors.vendor_join_requests
    FOR EACH ROW EXECUTE FUNCTION vendors.enforce_join_request_gate();
CREATE TRIGGER buyer_join_requests_enforce_join_request_gate
    BEFORE INSERT ON buyer_companies.buyer_join_requests
    FOR EACH ROW EXECUTE FUNCTION buyer_companies.enforce_join_request_gate();

CREATE TRIGGER vendor_join_requests_set_updated_at BEFORE UPDATE ON vendors.vendor_join_requests
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER buyer_join_requests_set_updated_at BEFORE UPDATE ON buyer_companies.buyer_join_requests
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- migrate:down

DROP TABLE buyer_companies.buyer_join_requests;
DROP TABLE vendors.vendor_join_requests;
DROP FUNCTION buyer_companies.enforce_join_request_gate();
DROP FUNCTION vendors.enforce_join_request_gate();

DROP TYPE buyer_companies.join_grant_path;
DROP TYPE buyer_companies.join_request_status;
DROP TYPE vendors.join_grant_path;
DROP TYPE vendors.join_request_status;
