-- =====================================================================
-- NovaDawa — Tenant-Scoped Schema (migration 01)
-- =====================================================================
-- These tables hold all pharmacy-specific operational data. Every table
-- is scoped to a pharmacy_group (the tenant) or a branch within it.
-- The global drug catalog (drug, drug_sku, clinical_reference,
-- drug_interaction_cache) lives in 00_schema.sql and is shared across
-- all tenants — not repeated here.
--
-- Apply order:  00_schema.sql  →  01_tenant_schema.sql
--
-- Design notes:
--   * "user" is a PostgreSQL reserved word — renamed to app_user here.
--   * All monetary amounts stored as INTEGER in santim (1 ETB = 100 santim)
--     to avoid floating-point rounding on financial calculations.
--   * Firebase Auth is the primary authentication mechanism; password_hash
--     is kept NULLABLE as a fallback for internal/service accounts.
--   * Row Level Security (RLS) is recommended before production to enforce
--     tenant isolation at the database level — add policies keyed on
--     pharmacy_group_id after initial build is stable.
--   * Ethiopian-specific fields: woreda/subcity address structure, TIN
--     (Tax Identification Number), EFDA license numbers, santim amounts,
--     Telebirr/CBE Birr payment methods, kebele ID patient identification.
-- =====================================================================

BEGIN;

-- ---------- Enums (idempotent) ----------

DO $$ BEGIN
    CREATE TYPE subscription_tier AS ENUM ('starter','professional','enterprise');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE subscription_status AS ENUM ('trial','active','suspended','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE user_role AS ENUM (
        'group_admin','branch_manager','pharmacist','cashier','stock_clerk','viewer'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE supplier_type AS ENUM (
        'importer','local_manufacturer','distributor','pharmacy_wholesaler'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE movement_type AS ENUM (
        'purchase','sale','adjustment','transfer_out','transfer_in',
        'return','wastage','expired'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE payment_method AS ENUM ('cash','telebirr','cbe_birr','credit');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE sale_status AS ENUM ('completed','voided','refunded');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE patient_id_type AS ENUM (
        'kebele_id','passport','drivers_license','other'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------- pharmacy_group ----------
-- The top-level tenant. One chain/independent pharmacy business = one group.
CREATE TABLE IF NOT EXISTS pharmacy_group (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    VARCHAR(200) NOT NULL,
    tin_number              VARCHAR(50),            -- Ethiopian Tax Identification Number
    efda_license_number     VARCHAR(100),           -- EFDA wholesale/retail license
    efda_license_expiry     DATE,                   -- 90-day expiry alert trigger
    subscription_tier       subscription_tier NOT NULL DEFAULT 'starter',
    subscription_status     subscription_status NOT NULL DEFAULT 'trial',
    billing_email           VARCHAR(200) NOT NULL,
    country_code            CHAR(2) NOT NULL DEFAULT 'ET',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- branch ----------
-- A physical pharmacy location belonging to a group.
CREATE TABLE IF NOT EXISTS branch (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacy_group_id       UUID NOT NULL REFERENCES pharmacy_group(id) ON DELETE CASCADE,
    name                    VARCHAR(200) NOT NULL,
    woreda                  VARCHAR(100) NOT NULL,  -- Ethiopian administrative sub-city/woreda
    subcity                 VARCHAR(100),
    city                    VARCHAR(100) NOT NULL DEFAULT 'Addis Ababa',
    phone                   VARCHAR(20),
    efda_branch_license     VARCHAR(100),
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- app_user ----------
-- Staff accounts. Renamed from "user" (PostgreSQL reserved word).
-- Firebase Auth is primary; firebase_uid links this row to the Auth record.
CREATE TABLE IF NOT EXISTS app_user (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacy_group_id       UUID NOT NULL REFERENCES pharmacy_group(id) ON DELETE CASCADE,
    firebase_uid            TEXT UNIQUE,            -- Firebase Auth UID (primary auth)
    email                   VARCHAR(254) NOT NULL UNIQUE,
    phone                   VARCHAR(20),
    full_name               VARCHAR(200) NOT NULL,
    password_hash           TEXT,                   -- bcrypt cost ≥ 12; NULL if Firebase-only
    efda_license_number     VARCHAR(100),           -- required for pharmacist role
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at           TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- user_branch_role ----------
-- Grants a user a role at a specific branch, or group-wide (branch_id NULL).
CREATE TABLE IF NOT EXISTS user_branch_role (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    branch_id               UUID REFERENCES branch(id) ON DELETE CASCADE,
    -- NULL branch_id = group-wide access (used for group_admin role)
    role                    user_role NOT NULL,
    granted_by_user_id      UUID NOT NULL REFERENCES app_user(id),
    granted_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at              TIMESTAMPTZ             -- soft revoke; NULL = currently active
);

-- ---------- supplier ----------
-- Drug suppliers scoped to a pharmacy group.
CREATE TABLE IF NOT EXISTS supplier (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacy_group_id       UUID NOT NULL REFERENCES pharmacy_group(id) ON DELETE CASCADE,
    name                    VARCHAR(200) NOT NULL,
    supplier_type           supplier_type NOT NULL,
    contact_person          VARCHAR(200),
    phone                   VARCHAR(20),
    email                   VARCHAR(254),
    tin_number              VARCHAR(50),            -- for VAT invoice matching
    payment_terms_days      INTEGER DEFAULT 30,
    currency                CHAR(3) NOT NULL DEFAULT 'ETB', -- ETB, USD, EUR
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- product ----------
-- A specific (drug_sku, pack_size, brand) stocked by a group.
-- pharmacy_group_id NULL = global registry entry (shared catalog product).
CREATE TABLE IF NOT EXISTS product (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_sku_id             UUID NOT NULL REFERENCES drug_sku(id),
    pharmacy_group_id       UUID REFERENCES pharmacy_group(id) ON DELETE CASCADE,
    brand_name              VARCHAR(200),
    pack_size               INTEGER NOT NULL,       -- base units per pack (e.g. 100 tablets)
    sale_unit               VARCHAR(50) NOT NULL,   -- e.g. 'strip of 10', 'bottle', 'piece'
    sale_unit_size          INTEGER NOT NULL DEFAULT 1, -- base units per sale unit
    primary_barcode         VARCHAR(100) UNIQUE,
    secondary_barcodes      TEXT[],                 -- additional EAN/GS1/local barcodes
    image_url               TEXT,
    country_of_origin       CHAR(2),                -- ISO 3166-1 alpha-2
    supplier_id             UUID REFERENCES supplier(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- inventory ----------
-- A specific batch of a product in stock at a branch (FIFO per product).
CREATE TABLE IF NOT EXISTS inventory (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id                   UUID NOT NULL REFERENCES branch(id),
    product_id                  UUID NOT NULL REFERENCES product(id),
    batch_number                VARCHAR(100) NOT NULL,
    expiry_date                 DATE NOT NULL,      -- 90-day alert driven from here
    quantity_base_units         INTEGER NOT NULL,
    cost_per_base_unit_santim   INTEGER NOT NULL,   -- purchase cost in santim
    exchange_rate_at_purchase   NUMERIC(10,4) NOT NULL, -- ETB/USD at purchase time
    selling_price_per_sale_unit_santim INTEGER NOT NULL,
    supplier_id                 UUID REFERENCES supplier(id),
    purchase_order_ref          VARCHAR(100),       -- PO number / GRN reference
    received_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- FIFO tiebreaker
    received_by_user_id         UUID NOT NULL REFERENCES app_user(id),
    is_active                   BOOLEAN NOT NULL DEFAULT TRUE -- FALSE when fully consumed
);

-- ---------- inventory_movement ----------
-- Immutable audit trail for every stock change.
CREATE TABLE IF NOT EXISTS inventory_movement (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inventory_id                UUID NOT NULL REFERENCES inventory(id),
    branch_id                   UUID NOT NULL REFERENCES branch(id), -- denormalized for perf
    movement_type               movement_type NOT NULL,
    quantity_change_base_units  INTEGER NOT NULL,   -- negative = reduction, positive = addition
    quantity_after_base_units   INTEGER NOT NULL,   -- snapshot for reconciliation
    reference_id                UUID,               -- FK to sale_id, transfer_id, PO, etc.
    reference_type              VARCHAR(50),        -- 'sale', 'transfer', 'purchase_order'
    notes                       TEXT,
    performed_by_user_id        UUID NOT NULL REFERENCES app_user(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Intentionally no UPDATE/DELETE: this table is append-only
);

-- ---------- sale ----------
-- A dispensing transaction at a branch.
CREATE TABLE IF NOT EXISTS sale (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id                   UUID NOT NULL REFERENCES branch(id),
    sale_number                 VARCHAR(50) NOT NULL UNIQUE, -- e.g. 'BOLE-2026-00142'
    cashier_user_id             UUID NOT NULL REFERENCES app_user(id),
    dispensed_by_user_id        UUID REFERENCES app_user(id), -- pharmacist for controlled substances
    customer_name               VARCHAR(200),       -- required for controlled substances
    customer_phone              VARCHAR(20),
    prescription_ref            VARCHAR(100),
    prescription_image_url      TEXT,
    subtotal_santim             INTEGER NOT NULL,
    vat_total_santim            INTEGER NOT NULL DEFAULT 0,
    discount_santim             INTEGER NOT NULL DEFAULT 0,
    total_santim                INTEGER NOT NULL,
    payment_method              payment_method NOT NULL,
    payment_reference           VARCHAR(100),       -- Telebirr/CBE transaction ID
    sale_status                 sale_status NOT NULL DEFAULT 'completed',
    void_reason                 TEXT,               -- required when voided
    voided_by_user_id           UUID REFERENCES app_user(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- sale_line ----------
-- One line per product dispensed in a sale.
CREATE TABLE IF NOT EXISTS sale_line (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id                     UUID NOT NULL REFERENCES sale(id),
    inventory_id                UUID NOT NULL REFERENCES inventory(id), -- specific batch
    product_id                  UUID NOT NULL REFERENCES product(id),   -- denormalized
    quantity_sale_units         INTEGER NOT NULL,
    quantity_base_units         INTEGER NOT NULL,   -- quantity_sale_units × sale_unit_size
    unit_price_santim           INTEGER NOT NULL,   -- price per sale unit at time of sale
    line_subtotal_santim        INTEGER NOT NULL,   -- quantity × unit_price
    is_vat_applicable           BOOLEAN NOT NULL,
    vat_rate_bps                INTEGER NOT NULL DEFAULT 1500, -- 1500 bps = 15% Ethiopian VAT
    vat_amount_santim           INTEGER NOT NULL DEFAULT 0,    -- 0 for exempt medicines
    line_total_santim           INTEGER NOT NULL,   -- subtotal + vat
    cogs_santim                 INTEGER NOT NULL,   -- cost of goods (FIFO)
    gross_margin_santim         INTEGER NOT NULL,   -- line_subtotal - cogs (pre-VAT)
    aware_warning_shown         BOOLEAN NOT NULL DEFAULT FALSE,
    aware_override_user_id      UUID REFERENCES app_user(id) -- who overrode a Reserve warning
);

-- ---------- narcotics_register ----------
-- Mandatory government log for every controlled substance dispensing.
-- One entry per sale_line involving a controlled substance.
CREATE TABLE IF NOT EXISTS narcotics_register (
    id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_line_id                    UUID NOT NULL UNIQUE REFERENCES sale_line(id),
    branch_id                       UUID NOT NULL REFERENCES branch(id),
    drug_sku_id                     UUID NOT NULL REFERENCES drug_sku(id),
    dispensed_quantity_base_units   INTEGER NOT NULL,
    dispensed_at                    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    dispensed_by_user_id            UUID NOT NULL REFERENCES app_user(id), -- must be pharmacist
    patient_full_name               VARCHAR(200) NOT NULL,
    patient_id_type                 patient_id_type NOT NULL,
    patient_id_number               VARCHAR(100) NOT NULL,
    prescribing_doctor_name         VARCHAR(200) NOT NULL,
    prescribing_doctor_license      VARCHAR(100) NOT NULL, -- Ethiopian Medical Practitioners reg no.
    prescription_serial             VARCHAR(100) NOT NULL, -- government-issued pad serial
    prescription_image_url          TEXT NOT NULL,
    running_balance_base_units      INTEGER NOT NULL -- stock balance after dispensing (audit)
);

-- =====================================================================
-- Indexes
-- =====================================================================

-- pharmacy_group / branch
CREATE INDEX IF NOT EXISTS idx_branch_group
    ON branch (pharmacy_group_id);

-- app_user
CREATE INDEX IF NOT EXISTS idx_user_group
    ON app_user (pharmacy_group_id);
CREATE INDEX IF NOT EXISTS idx_user_firebase
    ON app_user (firebase_uid);

-- user_branch_role
CREATE INDEX IF NOT EXISTS idx_ubr_user
    ON user_branch_role (user_id) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_ubr_branch
    ON user_branch_role (branch_id) WHERE revoked_at IS NULL;

-- supplier
CREATE INDEX IF NOT EXISTS idx_supplier_group
    ON supplier (pharmacy_group_id);

-- product
CREATE INDEX IF NOT EXISTS idx_product_sku
    ON product (drug_sku_id);
CREATE INDEX IF NOT EXISTS idx_product_group
    ON product (pharmacy_group_id);

-- inventory — most performance-critical indexes
CREATE INDEX IF NOT EXISTS idx_inventory_branch
    ON inventory (branch_id);
CREATE INDEX IF NOT EXISTS idx_inventory_product
    ON inventory (product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_expiry
    ON inventory (expiry_date) WHERE is_active = TRUE;  -- expiry alert queries
CREATE INDEX IF NOT EXISTS idx_inventory_active
    ON inventory (branch_id, product_id) WHERE is_active = TRUE; -- stock level queries
CREATE INDEX IF NOT EXISTS idx_inventory_received_at
    ON inventory (product_id, received_at) WHERE is_active = TRUE; -- FIFO ordering

-- inventory_movement
CREATE INDEX IF NOT EXISTS idx_movement_inventory
    ON inventory_movement (inventory_id);
CREATE INDEX IF NOT EXISTS idx_movement_branch_time
    ON inventory_movement (branch_id, created_at DESC);

-- sale
CREATE INDEX IF NOT EXISTS idx_sale_branch_time
    ON sale (branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sale_status
    ON sale (branch_id, sale_status);
CREATE INDEX IF NOT EXISTS idx_sale_cashier
    ON sale (cashier_user_id);

-- sale_line
CREATE INDEX IF NOT EXISTS idx_sale_line_sale
    ON sale_line (sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_line_product
    ON sale_line (product_id);
CREATE INDEX IF NOT EXISTS idx_sale_line_inventory
    ON sale_line (inventory_id);

-- narcotics_register
CREATE INDEX IF NOT EXISTS idx_narcotics_branch_time
    ON narcotics_register (branch_id, dispensed_at DESC);
CREATE INDEX IF NOT EXISTS idx_narcotics_sku
    ON narcotics_register (drug_sku_id);

COMMIT;
