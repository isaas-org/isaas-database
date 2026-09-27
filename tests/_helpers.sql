-- Session-local assertion helpers (pg_temp = gone when the session ends).

CREATE FUNCTION pg_temp.assert_true(condition boolean, message text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF condition IS NOT TRUE THEN
        RAISE EXCEPTION 'ASSERTION FAILED: %', message;
    END IF;
END;
$$;

CREATE FUNCTION pg_temp.assert_eq(actual anyelement, expected anyelement, message text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF actual IS DISTINCT FROM expected THEN
        RAISE EXCEPTION 'ASSERTION FAILED: % (expected %, got %)', message, expected, actual;
    END IF;
END;
$$;

-- Runs `stmt` and passes only if it fails with SQLSTATE `expected_state`
-- raised by `expected_source`:
--   * constraint / unique-index errors: the exact constraint or index name
--     (checked against the error's CONSTRAINT_NAME, so a *different*
--     constraint with the same SQLSTATE does not satisfy the test);
--   * trigger errors (no constraint name): a substring of the error message.
-- Common states: 23514 check_violation, 23503 foreign_key_violation,
-- 23505 unique_violation, 23001 restrict_violation (ON DELETE RESTRICT).
-- The failed statement is rolled back to an implicit savepoint.
CREATE FUNCTION pg_temp.assert_raises(
    stmt text, expected_state text, expected_source text, message text
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_constraint text;
    v_message    text;
BEGIN
    BEGIN
        EXECUTE stmt;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME, v_message = MESSAGE_TEXT;
        IF SQLSTATE <> expected_state THEN
            RAISE EXCEPTION 'ASSERTION FAILED: % (expected SQLSTATE %, got %: %)',
                message, expected_state, SQLSTATE, v_message;
        END IF;
        IF (v_constraint <> '' AND v_constraint <> expected_source)
           OR (v_constraint = '' AND position(expected_source IN v_message) = 0) THEN
            RAISE EXCEPTION 'ASSERTION FAILED: % (expected "%" to fire, got: %)',
                message, expected_source, v_message;
        END IF;
        RETURN;
    END;
    RAISE EXCEPTION 'ASSERTION FAILED: % (expected SQLSTATE %, but statement succeeded)',
        message, expected_state;
END;
$$;

-- Named fixture ids: pg_temp.fx('vendor.pending') instead of UUID literals.
-- Unknown names raise, so a typo can't silently match nothing.
CREATE TEMP TABLE fixture_ids (
    name text PRIMARY KEY,
    id   uuid NOT NULL DEFAULT uuidv7()
);

CREATE FUNCTION pg_temp.fx(p_name text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
    v_id uuid;
BEGIN
    SELECT id INTO v_id FROM pg_temp.fixture_ids WHERE name = p_name;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'unknown fixture "%"', p_name;
    END IF;
    RETURN v_id;
END;
$$;
