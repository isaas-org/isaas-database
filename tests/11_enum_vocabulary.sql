-- Pins every status/role vocabulary to the design doc. Adding, removing or
-- reordering a value is a product decision, so it must show up as a test change.

SELECT pg_temp.assert_eq(enum_range(NULL::items.item_status)::text[],
    ARRAY['draft', 'published', 'suspended', 'archived'], 'items.item_status');
SELECT pg_temp.assert_eq(enum_range(NULL::items.pricing_model)::text[],
    ARRAY['flat', 'seat', 'usage', 'freemium'], 'items.pricing_model');
SELECT pg_temp.assert_eq(enum_range(NULL::items.billing_frequency)::text[],
    ARRAY['monthly', 'annual'], 'items.billing_frequency');
SELECT pg_temp.assert_eq(enum_range(NULL::items.media_type)::text[],
    ARRAY['image', 'video', 'document'], 'items.media_type');

SELECT pg_temp.assert_eq(enum_range(NULL::vendors.vendor_status)::text[],
    ARRAY['pending', 'active', 'suspended'], 'vendors.vendor_status');
SELECT pg_temp.assert_eq(enum_range(NULL::vendors.verification_status)::text[],
    ARRAY['pending', 'verified', 'rejected'], 'vendors.verification_status');
SELECT pg_temp.assert_eq(enum_range(NULL::vendors.vendor_user_role)::text[],
    ARRAY['admin', 'sales', 'support'], 'vendors.vendor_user_role');
SELECT pg_temp.assert_eq(enum_range(NULL::vendors.address_type)::text[],
    ARRAY['business', 'mailing'], 'vendors.address_type');
SELECT pg_temp.assert_eq(enum_range(NULL::vendors.artifact_type)::text[],
    ARRAY['business_registration', 'tax_id', 'bank_verification', 'other'], 'vendors.artifact_type');
SELECT pg_temp.assert_eq(enum_range(NULL::vendors.artifact_status)::text[],
    ARRAY['pending', 'approved', 'rejected'], 'vendors.artifact_status');
SELECT pg_temp.assert_eq(enum_range(NULL::vendors.payout_account_type)::text[],
    ARRAY['bank', 'other'], 'vendors.payout_account_type');

SELECT pg_temp.assert_eq(enum_range(NULL::buyer_companies.company_status)::text[],
    ARRAY['active', 'suspended'], 'buyer_companies.company_status');
SELECT pg_temp.assert_eq(enum_range(NULL::buyer_companies.verification_status)::text[],
    ARRAY['unverified', 'pending', 'verified', 'rejected'], 'buyer_companies.verification_status');
SELECT pg_temp.assert_eq(enum_range(NULL::buyer_companies.buyer_user_role)::text[],
    ARRAY['admin', 'purchaser', 'approver', 'viewer'], 'buyer_companies.buyer_user_role');
SELECT pg_temp.assert_eq(enum_range(NULL::buyer_companies.address_type)::text[],
    ARRAY['billing', 'headquarters'], 'buyer_companies.address_type');
SELECT pg_temp.assert_eq(enum_range(NULL::buyer_companies.payment_method_type)::text[],
    ARRAY['card', 'ach', 'purchase_order'], 'buyer_companies.payment_method_type');
SELECT pg_temp.assert_eq(enum_range(NULL::buyer_companies.artifact_type)::text[],
    ARRAY['business_registration', 'tax_id', 'proof_of_address', 'other'], 'buyer_companies.artifact_type');
SELECT pg_temp.assert_eq(enum_range(NULL::buyer_companies.artifact_status)::text[],
    ARRAY['pending', 'approved', 'rejected'], 'buyer_companies.artifact_status');
SELECT pg_temp.assert_eq(enum_range(NULL::buyer_companies.subscription_status)::text[],
    ARRAY['trial', 'active', 'cancelled'], 'buyer_companies.subscription_status');
SELECT pg_temp.assert_eq(enum_range(NULL::buyer_companies.company_size)::text[],
    ARRAY['1-10', '11-50', '51-200', '201-1000', '1001-5000', '5000+'], 'buyer_companies.company_size');

-- Catch enums added without a pin here.
SELECT pg_temp.assert_eq(
    (SELECT count(*) FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
     WHERE t.typtype = 'e' AND n.nspname IN ('items', 'vendors', 'buyer_companies')),
    20::bigint, 'every domain enum is pinned in this file');
