-- =====================================================================
-- SCOPE — Schema verification
--
-- Run after `docker compose up -d` to confirm the database matches
-- Chapter 4. The output of this script is Development-phase evidence:
-- capture it for your report.
--
--   docker exec -i scope-db psql -U scope -d scope -f - < infra/verify.sql
-- =====================================================================

\echo '=== PostGIS version ==='
SELECT PostGIS_Version();

\echo ''
\echo '=== Entities (expect exactly 6) ==='
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
  AND table_name IN ('report','report_photo','ai_classification',
                     'admin_user','admin_activity_log','infographic')
ORDER BY table_name;

\echo ''
\echo '=== Confirm NO status / verification columns exist anywhere ==='
\echo '(expect zero rows — this is the read-only administrator model)'
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name IN ('status','verified_by','verified_at','reviewed_by',
                      'violation_type','premise_type');

\echo ''
\echo '=== Constraints carrying design weight ==='
SELECT conrelid::regclass AS entity, conname AS constraint_name
FROM pg_constraint
WHERE conname IN (
    'report_photo_sequence_range',      -- three-photograph maximum
    'report_photo_sequence_unique',
    'ai_classification_outcome_valid',  -- only PASS is persisted
    'ai_classification_passed_range',   -- at least one photo passed
    'infographic_slot_range',           -- three fixed slots
    'admin_user_role_valid',
    'admin_activity_log_type_valid'
)
ORDER BY conrelid::regclass::text, conname;

\echo ''
\echo '=== Spatial index on report.geom (supports S06 and D03) ==='
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'report' AND indexname = 'idx_report_geom';

\echo ''
\echo '=== Seeded infographic slots (expect exactly 3) ==='
SELECT infographic_id, title FROM infographic ORDER BY infographic_id;

\echo ''
\echo '=== Seeded admin accounts (expect 2, hashes are bcrypt $2a$) ==='
SELECT email, organisation, role, left(password_hash, 7) AS hash_prefix
FROM admin_user ORDER BY email;
