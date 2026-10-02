-- =====================================================================
-- SCOPE — Database Schema
-- AI-Assisted Smoking Violation Reporting and Monitoring System
--
-- Implements Tables 4.4 to 4.9 of SCOPE-Data-Dictionary.md (11 Aug 2026)
-- and the six entities / five relationships of SCOPE-ERD.md (Figure 4.7).
--
-- Platform: PostgreSQL 15 + PostGIS 3.4
-- Entity names are singular, matching the Data Dictionary and ERD.
--
-- DESIGN NOTE — attributes deliberately absent from this schema:
--   No `status`, `verified_by`, `verified_at` or `reviewed_by` column
--   exists on any table. Photographic evidence is validated by the
--   classification module BEFORE submission (S10) and administrators hold
--   read-only access over report data, so no process in the system can
--   alter a report once it is filed. Introducing a status attribute would
--   represent a workflow the system does not perform.
--   See SCOPE-Data-Dictionary.md Table 4.4, note on absent attributes.
--
--   No reporter entity exists either. Anonymity (FR04, NFR06) is achieved
--   by not collecting identity rather than by obscuring it after
--   collection. `report.device_id` is generated on the handset at first
--   launch, is unconnected to any account or hardware identifier, and
--   cannot be resolved to a person.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ---------------------------------------------------------------------
-- Table 4.4 — REPORT
-- One row per submitted violation report.
-- ---------------------------------------------------------------------
CREATE TABLE report (
    report_id         UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    reference_no      VARCHAR(20)    NOT NULL UNIQUE,
    device_id         VARCHAR(64)    NOT NULL,
    premise_name      VARCHAR(150),
    address_text      VARCHAR(255),
    latitude          NUMERIC(9,6)   NOT NULL,
    longitude         NUMERIC(9,6)   NOT NULL,
    geom              GEOGRAPHY(POINT, 4326) NOT NULL,
    capture_latitude  NUMERIC(9,6),
    capture_longitude NUMERIC(9,6),
    reported_at       TIMESTAMPTZ    NOT NULL,
    submitted_at      TIMESTAMPTZ    NOT NULL DEFAULT now(),

    CONSTRAINT report_latitude_range
        CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT report_longitude_range
        CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT report_capture_latitude_range
        CHECK (capture_latitude IS NULL OR capture_latitude BETWEEN -90 AND 90),
    CONSTRAINT report_capture_longitude_range
        CHECK (capture_longitude IS NULL OR capture_longitude BETWEEN -180 AND 180)
);

COMMENT ON TABLE  report IS
    'Submitted violation reports. Holds no reporter identity; device_id is an anonymous locally generated value.';
COMMENT ON COLUMN report.reference_no IS
    'Human-readable reference issued at S13; the reporter''s only durable handle on an anonymous submission.';
COMMENT ON COLUMN report.device_id IS
    'Anonymous device identifier. Keys Report History (S14) and supports per-device rate limiting.';
COMMENT ON COLUMN report.premise_name IS
    'Optional reporter-supplied premise name, pre-filled from reverse geocoding at S11. Free text, not a category.';
COMMENT ON COLUMN report.geom IS
    'PostGIS point derived from latitude/longitude by trigger. Supports spatial clustering for S06 and D03.';
COMMENT ON COLUMN report.capture_latitude IS
    'Device latitude at the moment of photo capture (S08). A large divergence from the tagged position flags the report for integrity review.';

-- Derive geom from latitude/longitude so the two can never disagree.
-- BEFORE INSERT fires ahead of the NOT NULL check, so geom need not be supplied.
CREATE OR REPLACE FUNCTION report_set_geom() RETURNS trigger AS $$
BEGIN
    NEW.geom := ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_report_set_geom
    BEFORE INSERT OR UPDATE OF latitude, longitude ON report
    FOR EACH ROW EXECUTE FUNCTION report_set_geom();

CREATE INDEX idx_report_geom         ON report USING GIST (geom);
CREATE INDEX idx_report_device_id    ON report (device_id);
CREATE INDEX idx_report_submitted_at ON report (submitted_at DESC);


-- ---------------------------------------------------------------------
-- Table 4.5 — REPORT_PHOTO
-- The one to three photographs attached to a report (relationship R1).
-- Only photographs that cleared the threshold are persisted; failing
-- photographs are discarded at S10 and never reach the database.
-- ---------------------------------------------------------------------
CREATE TABLE report_photo (
    photo_id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id        UUID         NOT NULL REFERENCES report(report_id) ON DELETE CASCADE,
    sequence_no      SMALLINT     NOT NULL,
    storage_path     VARCHAR(255) NOT NULL,
    captured_at      TIMESTAMPTZ  NOT NULL,
    confidence_score NUMERIC(5,4) NOT NULL,
    is_validated     BOOLEAN      NOT NULL DEFAULT TRUE,

    -- Enforces the three-photograph maximum declaratively.
    CONSTRAINT report_photo_sequence_range
        CHECK (sequence_no BETWEEN 1 AND 3),
    CONSTRAINT report_photo_sequence_unique
        UNIQUE (report_id, sequence_no),
    CONSTRAINT report_photo_confidence_range
        CHECK (confidence_score BETWEEN 0 AND 1)
);

COMMENT ON TABLE  report_photo IS
    'Photographic evidence, normalised out of REPORT to satisfy First Normal Form.';
COMMENT ON COLUMN report_photo.sequence_no IS
    'Display order 1-3. The CHECK plus UNIQUE(report_id, sequence_no) enforces the three-photograph maximum at the database level.';
COMMENT ON COLUMN report_photo.is_validated IS
    'Confirms the photograph cleared the threshold. Retained explicitly so the stored value is auditable rather than implied.';

CREATE INDEX idx_report_photo_report_id ON report_photo (report_id);


-- ---------------------------------------------------------------------
-- Table 4.6 — AI_CLASSIFICATION
-- Report-level classification outcome, one-to-one with REPORT (R2).
-- Separated from REPORT so that retraining the model does not alter the
-- meaning of any column in REPORT.
-- ---------------------------------------------------------------------
CREATE TABLE ai_classification (
    classification_id  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id          UUID         NOT NULL UNIQUE REFERENCES report(report_id) ON DELETE CASCADE,
    model_version      VARCHAR(50)  NOT NULL,
    threshold_used     NUMERIC(5,4) NOT NULL,
    outcome            VARCHAR(10)  NOT NULL DEFAULT 'PASS',
    highest_confidence NUMERIC(5,4) NOT NULL,
    photos_evaluated   SMALLINT     NOT NULL,
    photos_passed      SMALLINT     NOT NULL,
    evaluated_at       TIMESTAMPTZ  NOT NULL,

    -- Only PASS is persisted. A full failure returns the reporter to S08
    -- and no report is created, so no FAIL row can legitimately exist.
    -- This constraint is the declarative expression of the design rule
    -- that classification precedes persistence (DFD process 2.0 -> 3.0).
    CONSTRAINT ai_classification_outcome_valid
        CHECK (outcome = 'PASS'),
    CONSTRAINT ai_classification_threshold_range
        CHECK (threshold_used BETWEEN 0 AND 1),
    CONSTRAINT ai_classification_confidence_range
        CHECK (highest_confidence BETWEEN 0 AND 1),
    CONSTRAINT ai_classification_evaluated_range
        CHECK (photos_evaluated BETWEEN 1 AND 3),
    -- At least one photograph must have passed, per the confirmed
    -- multi-photo validation rule in SCOPE-System-Flow-Revised.md section 8.
    CONSTRAINT ai_classification_passed_range
        CHECK (photos_passed BETWEEN 1 AND photos_evaluated)
);

COMMENT ON TABLE  ai_classification IS
    'Classification provenance: which model version and threshold judged this report, evaluated pre-submission.';
COMMENT ON COLUMN ai_classification.outcome IS
    'Only PASS is persisted; a total failure returns the reporter to S08 and creates no report.';
COMMENT ON COLUMN ai_classification.photos_passed IS
    'A value lower than photos_evaluated records that photographs were dropped at S10.';


-- ---------------------------------------------------------------------
-- Table 4.7 — ADMIN_USER
-- Enforcement officers and NCSM staff authorised to access the dashboard.
-- The only entity in the system holding personal data.
-- ---------------------------------------------------------------------
CREATE TABLE admin_user (
    admin_id      UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email         VARCHAR(120) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name     VARCHAR(120) NOT NULL,
    organisation  VARCHAR(100) NOT NULL,
    role          VARCHAR(20)  NOT NULL,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    -- All current roles are read-only over report data. No role grants
    -- the ability to verify, approve, reject or amend a report.
    CONSTRAINT admin_user_role_valid
        CHECK (role IN ('OFFICER', 'RESEARCHER', 'SUPERVISOR'))
);

COMMENT ON TABLE  admin_user IS
    'Dashboard accounts. All roles are read-only over report data; none can alter a filed report.';
COMMENT ON COLUMN admin_user.is_active IS
    'Allows an account to be suspended without deletion, preserving its activity history.';


-- ---------------------------------------------------------------------
-- Table 4.8 — ADMIN_ACTIVITY_LOG
-- Records administrator authentication, report access and data export.
-- Satisfies the accountability expectation attaching to the Security
-- Principle of the Personal Data Protection Act 2010, since FR13 permits
-- report data to leave the system as a CSV export.
-- ---------------------------------------------------------------------
CREATE TABLE admin_activity_log (
    log_id        BIGSERIAL    PRIMARY KEY,
    admin_id      UUID         REFERENCES admin_user(admin_id) ON DELETE SET NULL,
    report_id     UUID         REFERENCES report(report_id)    ON DELETE SET NULL,
    activity_type VARCHAR(30)  NOT NULL,
    ip_address    INET,
    detail        VARCHAR(255),
    activity_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT admin_activity_log_type_valid
        CHECK (activity_type IN (
            'LOGIN', 'LOGOUT', 'FAILED_LOGIN',
            'VIEW_REPORT', 'EXPORT_CSV', 'UPDATE_INFOGRAPHIC',
            'DELETE_INFOGRAPHIC'
        ))
);

COMMENT ON TABLE  admin_activity_log IS
    'Administrator activity trail. Written by processes 5.0, 6.0 and 7.0 only; no reporter-facing process writes here.';
COMMENT ON COLUMN admin_activity_log.admin_id IS
    'Null where a login attempt failed and no account was authenticated.';
COMMENT ON COLUMN admin_activity_log.report_id IS
    'Null for logins, exports and content updates, which do not concern a single report.';

CREATE INDEX idx_admin_activity_log_admin_id    ON admin_activity_log (admin_id);
CREATE INDEX idx_admin_activity_log_report_id   ON admin_activity_log (report_id);
CREATE INDEX idx_admin_activity_log_activity_at ON admin_activity_log (activity_at DESC);


-- ---------------------------------------------------------------------
-- Table 4.9 — INFOGRAPHIC
-- The two fixed awareness slots managed at D06 and rendered in the
-- mobile Awareness Hub (S04).
-- The primary key is a fixed slot number rather than a generated
-- identifier, so the slot set never grows. A slot is either published
-- (title and image both set) or empty (both NULL): D06 "deletes" an
-- infographic by emptying its slot, and S04 lists published slots only.
-- ---------------------------------------------------------------------
CREATE TABLE infographic (
    infographic_id  SMALLINT     PRIMARY KEY,
    title           VARCHAR(120),
    image_path      VARCHAR(255),
    source_filename VARCHAR(150),
    updated_by      UUID         REFERENCES admin_user(admin_id) ON DELETE SET NULL,
    updated_at      TIMESTAMPTZ,

    CONSTRAINT infographic_slot_range
        CHECK (infographic_id BETWEEN 1 AND 2),
    CONSTRAINT infographic_published_pair
        CHECK ((title IS NULL) = (image_path IS NULL))
);

COMMENT ON TABLE infographic IS
    'Two fixed slots. D06 replaces image and title in place, or empties a slot; the rows themselves are never added or deleted.';

-- D06 empties a slot rather than deleting its row, so the slot can be
-- published into again. Blocking DELETE keeps both rows present even
-- against direct database access.
CREATE OR REPLACE FUNCTION infographic_block_delete() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION
        'Infographic slots are fixed at two and their rows cannot be deleted. Empty the slot instead (D06).';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_infographic_block_delete
    BEFORE DELETE ON infographic
    FOR EACH ROW EXECUTE FUNCTION infographic_block_delete();
