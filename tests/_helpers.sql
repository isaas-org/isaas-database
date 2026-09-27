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
-- (e.g. 23514 check_violation, 23503 foreign_key_violation, 23505 unique_violation,
-- 23001 restrict_violation — raised by ON DELETE RESTRICT).
-- The failed statement is rolled back to an implicit savepoint.
CREATE FUNCTION pg_temp.assert_raises(stmt text, expected_state text, message text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE stmt;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE <> expected_state THEN
            RAISE EXCEPTION 'ASSERTION FAILED: % (expected SQLSTATE %, got %: %)',
                message, expected_state, SQLSTATE, SQLERRM;
        END IF;
        RETURN;
    END;
    RAISE EXCEPTION 'ASSERTION FAILED: % (expected SQLSTATE %, but statement succeeded)',
        message, expected_state;
END;
$$;
