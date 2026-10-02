-- =====================================================================
-- Migration 001 — three infographic slots become two, and slots can be
-- emptied from D06.
--
-- schema.sql only runs on a fresh volume, so an existing database needs
-- this applied by hand:
--
--   docker exec -i scope-db psql -U scope -d scope -v ON_ERROR_STOP=1 \
--       < infra/migrations/001-two-infographic-slots.sql
--
-- Slot 1 is dropped and slots 2 and 3 move up to 1 and 2. The image
-- files are not touched here: rename uploads/infographics/slot-2.* to
-- slot-1.* and slot-3.* to slot-2.* alongside it.
-- =====================================================================

BEGIN;

-- The old slot 1 row is the one row this migration genuinely removes.
ALTER TABLE infographic DISABLE TRIGGER trg_infographic_block_delete;
DELETE FROM infographic WHERE infographic_id = 1;
ALTER TABLE infographic ENABLE TRIGGER trg_infographic_block_delete;

-- One row at a time: a single UPDATE could collide on the primary key.
UPDATE infographic
   SET infographic_id = 1,
       image_path = regexp_replace(image_path, 'slot-2', 'slot-1')
 WHERE infographic_id = 2;
UPDATE infographic
   SET infographic_id = 2,
       image_path = regexp_replace(image_path, 'slot-3', 'slot-2')
 WHERE infographic_id = 3;

ALTER TABLE infographic DROP CONSTRAINT infographic_slot_range;
ALTER TABLE infographic ADD CONSTRAINT infographic_slot_range
    CHECK (infographic_id BETWEEN 1 AND 2);

ALTER TABLE infographic ALTER COLUMN title DROP NOT NULL;
ALTER TABLE infographic ALTER COLUMN image_path DROP NOT NULL;
ALTER TABLE infographic ADD CONSTRAINT infographic_published_pair
    CHECK ((title IS NULL) = (image_path IS NULL));

COMMENT ON TABLE infographic IS
    'Two fixed slots. D06 replaces image and title in place, or empties a slot; the rows themselves are never added or deleted.';

CREATE OR REPLACE FUNCTION infographic_block_delete() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION
        'Infographic slots are fixed at two and their rows cannot be deleted. Empty the slot instead (D06).';
END;
$$ LANGUAGE plpgsql;

ALTER TABLE admin_activity_log DROP CONSTRAINT admin_activity_log_type_valid;
ALTER TABLE admin_activity_log ADD CONSTRAINT admin_activity_log_type_valid
    CHECK (activity_type IN (
        'LOGIN', 'LOGOUT', 'FAILED_LOGIN',
        'VIEW_REPORT', 'EXPORT_CSV', 'UPDATE_INFOGRAPHIC',
        'DELETE_INFOGRAPHIC'
    ));

COMMIT;
