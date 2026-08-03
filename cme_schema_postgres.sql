-- CME DB design for DocSynapse
-- Assumption: docsy_auth.users.id is a UUID.
-- If your users table uses BIGINT/INTEGER, replace UUID with that type in all FK columns.

CREATE SCHEMA IF NOT EXISTS docsy_cme;

CREATE TYPE docsy_cme.program_format AS ENUM ('Online', 'Offline', 'Recorded');
CREATE TYPE docsy_cme.program_visibility AS ENUM ('Public', 'Group', 'Invite');
CREATE TYPE docsy_cme.program_status AS ENUM ('draft', 'published', 'archived', 'cancelled');
CREATE TYPE docsy_cme.registration_status AS ENUM ('pending', 'registered', 'attended', 'cancelled');
CREATE TYPE docsy_cme.certificate_status AS ENUM ('pending', 'issued', 'failed');
CREATE TYPE docsy_cme.accreditation_status AS ENUM ('draft', 'submitted', 'approved', 'rejected');

CREATE TABLE IF NOT EXISTS docsy_cme.cme_programs (
    id BIGSERIAL PRIMARY KEY,
    created_by_doctor_id UUID NOT NULL REFERENCES docsy_auth.users(id),
    title TEXT NOT NULL,
    slug TEXT UNIQUE,
    banner_url TEXT,
    format docsy_cme.program_format NOT NULL,
    organization_name TEXT,
    description TEXT,
    visibility docsy_cme.program_visibility NOT NULL DEFAULT 'Public',
    group_id BIGINT,
    accreditation_body TEXT,
    certificate_template_url TEXT,
    meeting_link TEXT,
    support_name TEXT,
    support_email TEXT,
    support_phone TEXT,
    third_party_org_name TEXT,
    third_party_contact_name TEXT,
    third_party_contact_email TEXT,
    third_party_contact_phone TEXT,
    registration_start_date DATE,
    registration_end_date DATE,
    event_start_date DATE NOT NULL,
    event_end_date DATE,
    event_start_time TIME,
    event_end_time TIME,
    timezone TEXT DEFAULT 'IST · India Standard Time (GMT+5:30)',
    seats_total INTEGER,
    seats_pre_conference INTEGER,
    seats_post_conference INTEGER,
    is_paid BOOLEAN DEFAULT FALSE,
    fee NUMERIC(10,2) DEFAULT 0,
    early_bird_fee NUMERIC(10,2),
    early_bird_deadline DATE,
    status docsy_cme.program_status NOT NULL DEFAULT 'draft',
    is_consented BOOLEAN DEFAULT FALSE,
    metadata_json JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_dates CHECK (
        (registration_end_date IS NULL OR registration_start_date IS NULL OR registration_end_date >= registration_start_date)
        AND (event_end_date IS NULL OR event_end_date >= event_start_date)
    )
);

CREATE TABLE IF NOT EXISTS docsy_cme.cme_program_attachments (
    id BIGSERIAL PRIMARY KEY,
    program_id BIGINT NOT NULL REFERENCES docsy_cme.cme_programs(id) ON DELETE CASCADE,
    attachment_type TEXT NOT NULL CHECK (attachment_type IN ('banner', 'brochure', 'certificate', 'chapter')),
    file_name TEXT,
    file_url TEXT NOT NULL,
    mime_type TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS docsy_cme.cme_program_specialties (
    id BIGSERIAL PRIMARY KEY,
    program_id BIGINT NOT NULL REFERENCES docsy_cme.cme_programs(id) ON DELETE CASCADE,
    specialty_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (program_id, specialty_name)
);

CREATE TABLE IF NOT EXISTS docsy_cme.cme_program_speakers (
    id BIGSERIAL PRIMARY KEY,
    program_id BIGINT NOT NULL REFERENCES docsy_cme.cme_programs(id) ON DELETE CASCADE,
    doctor_id UUID REFERENCES docsy_auth.users(id),
    display_name TEXT NOT NULL,
    designation TEXT,
    bio TEXT,
    avatar_url TEXT,
    is_featured BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS docsy_cme.cme_program_invites (
    id BIGSERIAL PRIMARY KEY,
    program_id BIGINT NOT NULL REFERENCES docsy_cme.cme_programs(id) ON DELETE CASCADE,
    invited_doctor_id UUID NOT NULL REFERENCES docsy_auth.users(id),
    invited_by_doctor_id UUID REFERENCES docsy_auth.users(id),
    invited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (program_id, invited_doctor_id)
);

CREATE TABLE IF NOT EXISTS docsy_cme.cme_program_registrations (
    id BIGSERIAL PRIMARY KEY,
    program_id BIGINT NOT NULL REFERENCES docsy_cme.cme_programs(id) ON DELETE CASCADE,
    doctor_id UUID NOT NULL REFERENCES docsy_auth.users(id),
    status docsy_cme.registration_status NOT NULL DEFAULT 'registered',
    registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    attended_at TIMESTAMPTZ,
    payment_status TEXT DEFAULT 'pending',
    payment_reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (program_id, doctor_id)
);

CREATE TABLE IF NOT EXISTS docsy_cme.cme_program_sessions (
    id BIGSERIAL PRIMARY KEY,
    program_id BIGINT NOT NULL REFERENCES docsy_cme.cme_programs(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    session_order INTEGER NOT NULL DEFAULT 1,
    duration_minutes INTEGER,
    video_url TEXT,
    thumbnail_url TEXT,
    credits NUMERIC(4,2) DEFAULT 0,
    summary TEXT,
    is_published BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (program_id, session_order)
);

CREATE TABLE IF NOT EXISTS docsy_cme.cme_session_progress (
    id BIGSERIAL PRIMARY KEY,
    session_id BIGINT NOT NULL REFERENCES docsy_cme.cme_program_sessions(id) ON DELETE CASCADE,
    doctor_id UUID NOT NULL REFERENCES docsy_auth.users(id),
    watched_percent INTEGER NOT NULL DEFAULT 0,
    completed BOOLEAN NOT NULL DEFAULT FALSE,
    last_watched_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (session_id, doctor_id)
);

CREATE TABLE IF NOT EXISTS docsy_cme.cme_certificates (
    id BIGSERIAL PRIMARY KEY,
    program_id BIGINT NOT NULL REFERENCES docsy_cme.cme_programs(id) ON DELETE CASCADE,
    doctor_id UUID NOT NULL REFERENCES docsy_auth.users(id),
    certificate_url TEXT,
    status docsy_cme.certificate_status NOT NULL DEFAULT 'pending',
    issued_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (program_id, doctor_id)
);

CREATE TABLE IF NOT EXISTS docsy_cme.cme_accreditation_requests (
    id BIGSERIAL PRIMARY KEY,
    program_id BIGINT NOT NULL REFERENCES docsy_cme.cme_programs(id) ON DELETE CASCADE,
    submitted_by_doctor_id UUID NOT NULL REFERENCES docsy_auth.users(id),
    status docsy_cme.accreditation_status NOT NULL DEFAULT 'draft',
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    review_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cme_programs_created_by ON docsy_cme.cme_programs(created_by_doctor_id);
CREATE INDEX IF NOT EXISTS idx_cme_programs_status ON docsy_cme.cme_programs(status);
CREATE INDEX IF NOT EXISTS idx_cme_program_registrations_doctor ON docsy_cme.cme_program_registrations(doctor_id);
CREATE INDEX IF NOT EXISTS idx_cme_session_progress_doctor ON docsy_cme.cme_session_progress(doctor_id);
CREATE INDEX IF NOT EXISTS idx_cme_certificates_doctor ON docsy_cme.cme_certificates(doctor_id);
