-- =====================================================================
-- SCOPE — Database constraint tests
--
-- Proves that the design decisions documented in Chapter 4 are enforced
-- by the database itself, not merely by application code. Every block
-- marked EXPECT FAIL must raise an error; if one succeeds silently, the
-- corresponding design rule is unenforced.
--
-- Runs inside a transaction and rolls back, so no test data persists.
--
--   docker exec -i scope-db psql -U scope -d scope -f - < infra/constraint-tests.sql
-- =====================================================================

\set ON_ERROR_ROLLBACK on
BEGIN;

-- ---------------------------------------------------------------------
\echo '=== TEST 1 — Valid report inserts, and geom is derived by trigger ==='
-- ---------------------------------------------------------------------
INSERT INTO report (report_id, reference_no, device_id, premise_name,
                    address_text, latitude, longitude,
                    capture_latitude, capture_longitude, reported_at)
VALUES ('11111111-1111-1111-1111-111111111111',
        'SCP-20260812-T001', 'test-device-aaa', 'Test Food Court',
        'Jalan Bukit Bintang, Kuala Lumpur',
        3.146600, 101.711300, 3.146590, 101.711280, now());

\echo '--> geom must be populated even though it was never supplied:'
SELECT reference_no,
       ST_AsText(geom::geometry) AS derived_geom,
       ST_SRID(geom::geometry)   AS srid
FROM report WHERE reference_no = 'SCP-20260812-T001';

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 2 — Three photographs accepted ==='
-- ---------------------------------------------------------------------
INSERT INTO report_photo (report_id, sequence_no, storage_path, captured_at, confidence_score)
VALUES ('11111111-1111-1111-1111-111111111111', 1, 'uploads/t1.jpg', now(), 0.9412),
       ('11111111-1111-1111-1111-111111111111', 2, 'uploads/t2.jpg', now(), 0.8833),
       ('11111111-1111-1111-1111-111111111111', 3, 'uploads/t3.jpg', now(), 0.9105);

SELECT count(*) AS photos_attached FROM report_photo
WHERE report_id = '11111111-1111-1111-1111-111111111111';

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 3 — EXPECT FAIL: a fourth photograph (three-photo maximum) ==='
-- ---------------------------------------------------------------------
INSERT INTO report_photo (report_id, sequence_no, storage_path, captured_at, confidence_score)
VALUES ('11111111-1111-1111-1111-111111111111', 4, 'uploads/t4.jpg', now(), 0.8000);

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 4 — EXPECT FAIL: duplicate sequence_no within one report ==='
-- ---------------------------------------------------------------------
INSERT INTO report_photo (report_id, sequence_no, storage_path, captured_at, confidence_score)
VALUES ('11111111-1111-1111-1111-111111111111', 2, 'uploads/dup.jpg', now(), 0.8000);

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 5 — Classification record accepted (one-to-one, R2) ==='
-- ---------------------------------------------------------------------
INSERT INTO ai_classification (report_id, model_version, threshold_used, outcome,
                               highest_confidence, photos_evaluated, photos_passed, evaluated_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'vit-scope-v1', 0.8500, 'PASS',
        0.9412, 3, 3, now());

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 6 — EXPECT FAIL: a second classification for the same report ==='
-- ---------------------------------------------------------------------
INSERT INTO ai_classification (report_id, model_version, threshold_used, outcome,
                               highest_confidence, photos_evaluated, photos_passed, evaluated_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'vit-scope-v1', 0.8500, 'PASS',
        0.7000, 2, 1, now());

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 7 — EXPECT FAIL: outcome = FAIL (only PASS may persist) ==='
\echo '    Classification precedes persistence; a total failure creates no report.'
-- ---------------------------------------------------------------------
INSERT INTO report (report_id, reference_no, device_id, latitude, longitude, reported_at)
VALUES ('22222222-2222-2222-2222-222222222222', 'SCP-20260812-T002',
        'test-device-bbb', 3.15, 101.71, now());

INSERT INTO ai_classification (report_id, model_version, threshold_used, outcome,
                               highest_confidence, photos_evaluated, photos_passed, evaluated_at)
VALUES ('22222222-2222-2222-2222-222222222222', 'vit-scope-v1', 0.8500, 'FAIL',
        0.1200, 3, 0, now());

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 8 — EXPECT FAIL: photos_passed = 0 (at least one must clear) ==='
-- ---------------------------------------------------------------------
INSERT INTO ai_classification (report_id, model_version, threshold_used, outcome,
                               highest_confidence, photos_evaluated, photos_passed, evaluated_at)
VALUES ('22222222-2222-2222-2222-222222222222', 'vit-scope-v1', 0.8500, 'PASS',
        0.1200, 3, 0, now());

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 9 — EXPECT FAIL: a fourth infographic slot ==='
-- ---------------------------------------------------------------------
INSERT INTO infographic (infographic_id, title, image_path)
VALUES (4, 'A fourth slot', 'infographics/slot-4.png');

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 10 — EXPECT FAIL: deleting an infographic slot ==='
\echo '    S02 renders three carousel dots and S04 three buttons; neither has an empty state.'
-- ---------------------------------------------------------------------
DELETE FROM infographic WHERE infographic_id = 3;

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 11 — EXPECT FAIL: an admin role outside the read-only set ==='
-- ---------------------------------------------------------------------
INSERT INTO admin_user (email, password_hash, full_name, organisation, role)
VALUES ('super@ncsm.org.my', 'x', 'Super Admin', 'NCSM', 'SUPERADMIN');

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 12 — EXPECT FAIL: an activity type outside the defined set ==='
-- ---------------------------------------------------------------------
INSERT INTO admin_activity_log (activity_type)
VALUES ('APPROVE_REPORT');

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 13 — Spatial query works (backs S06 heatmap and D03 clusters) ==='
\echo '    Reports within 2 km of KLCC:'
-- ---------------------------------------------------------------------
SELECT reference_no,
       round(ST_Distance(geom, ST_MakePoint(101.7117, 3.1578)::geography)::numeric, 1) AS metres_from_klcc
FROM report
WHERE ST_DWithin(geom, ST_MakePoint(101.7117, 3.1578)::geography, 2000)
ORDER BY metres_from_klcc;

-- ---------------------------------------------------------------------
\echo ''
\echo '=== TEST 14 — Cascade delete removes child rows (R1, R2) ==='
-- ---------------------------------------------------------------------
DELETE FROM report WHERE report_id = '11111111-1111-1111-1111-111111111111';

SELECT
    (SELECT count(*) FROM report_photo
       WHERE report_id = '11111111-1111-1111-1111-111111111111') AS orphan_photos,
    (SELECT count(*) FROM ai_classification
       WHERE report_id = '11111111-1111-1111-1111-111111111111') AS orphan_classifications;

ROLLBACK;

\echo ''
\echo '=== Rolled back. Verifying the database is clean: ==='
SELECT (SELECT count(*) FROM report)      AS reports,
       (SELECT count(*) FROM infographic) AS infographic_slots,
       (SELECT count(*) FROM admin_user)  AS admin_accounts;
