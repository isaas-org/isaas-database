-- migrate:up

-- Buyer verification moves from optional to a hard gate, the same as vendor
-- KYB: a company starts 'pending' and can only be 'active' while 'verified'.
-- Until then its members can browse, keep a watchlist, edit the profile and
-- invite colleagues, but cannot buy or add payment methods.

-- Existing active-but-unverified companies drop back to pending.
UPDATE buyer_companies.buyer_companies
SET status = 'pending'
WHERE status = 'active' AND verification_status <> 'verified';

ALTER TABLE buyer_companies.buyer_companies
    ALTER COLUMN status SET DEFAULT 'pending',
    ADD CONSTRAINT buyer_companies_active_requires_verified
        CHECK (status <> 'active' OR verification_status = 'verified');

-- Trials and paid subscriptions need an active company. Checked when a
-- subscription is created live, revived from 'cancelled', or moved to another
-- company. Cancelled rows are history and pass.
CREATE FUNCTION buyer_companies.enforce_subscription_gate() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_status buyer_companies.company_status;
BEGIN
    IF NEW.status IN ('trial', 'active')
       AND (TG_OP = 'INSERT'
            OR OLD.status = 'cancelled'
            OR OLD.buyer_company_id IS DISTINCT FROM NEW.buyer_company_id) THEN
        -- FOR SHARE blocks a concurrent company status change until we commit.
        SELECT status INTO v_status
        FROM buyer_companies.buyer_companies WHERE id = NEW.buyer_company_id
        FOR SHARE;

        IF v_status IS DISTINCT FROM 'active' THEN
            RAISE EXCEPTION 'subscription cannot start: buyer company % is %',
                NEW.buyer_company_id, coalesce(v_status::text, 'missing')
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER subscriptions_enforce_subscription_gate
    BEFORE INSERT OR UPDATE OF status, buyer_company_id ON buyer_companies.subscriptions
    FOR EACH ROW EXECUTE FUNCTION buyer_companies.enforce_subscription_gate();

-- Payment methods need an active company too.
CREATE FUNCTION buyer_companies.enforce_payment_method_gate() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_status buyer_companies.company_status;
BEGIN
    IF TG_OP = 'INSERT' OR OLD.buyer_company_id IS DISTINCT FROM NEW.buyer_company_id THEN
        SELECT status INTO v_status
        FROM buyer_companies.buyer_companies WHERE id = NEW.buyer_company_id
        FOR SHARE;

        IF v_status IS DISTINCT FROM 'active' THEN
            RAISE EXCEPTION 'payment method cannot be added: buyer company % is %',
                NEW.buyer_company_id, coalesce(v_status::text, 'missing')
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER payment_methods_enforce_payment_method_gate
    BEFORE INSERT OR UPDATE OF buyer_company_id ON buyer_companies.payment_methods
    FOR EACH ROW EXECUTE FUNCTION buyer_companies.enforce_payment_method_gate();

-- migrate:down

DROP TRIGGER payment_methods_enforce_payment_method_gate ON buyer_companies.payment_methods;
DROP FUNCTION buyer_companies.enforce_payment_method_gate();
DROP TRIGGER subscriptions_enforce_subscription_gate ON buyer_companies.subscriptions;
DROP FUNCTION buyer_companies.enforce_subscription_gate();

ALTER TABLE buyer_companies.buyer_companies
    DROP CONSTRAINT buyer_companies_active_requires_verified,
    ALTER COLUMN status SET DEFAULT 'active';

-- 'pending' is about to be removed from the enum by the previous migration's
-- down section. Before this migration, unverified companies were 'active'.
UPDATE buyer_companies.buyer_companies SET status = 'active' WHERE status = 'pending';
