-- 08_narcotics_register_overrides.sql
-- Adds EFDA-required patient demographics (age/sex/address) and a pharmacist
-- override mechanism (reason + authorizing user) to narcotics_register.
-- Human-supplied fields become nullable (required-unless-overridden is enforced
-- at the API layer). System-derived fields stay NOT NULL.

BEGIN;

-- 1) Patient demographics required by official register (NPS/09/A, NPS/09/B)
ALTER TABLE narcotics_register
    ADD COLUMN IF NOT EXISTS patient_age     integer,
    ADD COLUMN IF NOT EXISTS patient_sex     char(1),
    ADD COLUMN IF NOT EXISTS patient_address text;

-- 2) Override tracking
ALTER TABLE narcotics_register
    ADD COLUMN IF NOT EXISTS override_reason       text,
    ADD COLUMN IF NOT EXISTS overridden_by_user_id uuid;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'narcotics_register_overridden_by_user_id_fkey') THEN
        ALTER TABLE narcotics_register
            ADD CONSTRAINT narcotics_register_overridden_by_user_id_fkey
            FOREIGN KEY (overridden_by_user_id) REFERENCES app_user(id);
    END IF;
END $$;

-- 3) Value guards
ALTER TABLE narcotics_register
    ADD CONSTRAINT chk_narcotics_patient_age
        CHECK (patient_age IS NULL OR (patient_age >= 0 AND patient_age <= 150));
ALTER TABLE narcotics_register
    ADD CONSTRAINT chk_narcotics_patient_sex
        CHECK (patient_sex IS NULL OR patient_sex IN ('M','F'));

-- 4) Relax NOT NULL on human-supplied fields (all 7 currently NOT NULL)
ALTER TABLE narcotics_register ALTER COLUMN patient_full_name          DROP NOT NULL;
ALTER TABLE narcotics_register ALTER COLUMN patient_id_type            DROP NOT NULL;
ALTER TABLE narcotics_register ALTER COLUMN patient_id_number          DROP NOT NULL;
ALTER TABLE narcotics_register ALTER COLUMN prescribing_doctor_name    DROP NOT NULL;
ALTER TABLE narcotics_register ALTER COLUMN prescribing_doctor_license DROP NOT NULL;
ALTER TABLE narcotics_register ALTER COLUMN prescription_serial        DROP NOT NULL;
ALTER TABLE narcotics_register ALTER COLUMN prescription_image_url     DROP NOT NULL;
-- System-derived fields deliberately left NOT NULL.

COMMIT;
