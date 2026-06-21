-- 06_narcotics_reversal.sql
-- Append-only audit record for reversals (void/refund) of controlled-substance
-- dispenses. The original narcotics_register entry is NEVER mutated; each
-- reversal is a new linked row, so the controlled-substance trail stays
-- reconstructable for EFDA: net position = SUM(dispensed) - SUM(reversed).

CREATE TABLE IF NOT EXISTS narcotics_reversal (
    id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    narcotics_register_id        uuid NOT NULL REFERENCES narcotics_register(id),
    sale_id                      uuid NOT NULL REFERENCES sale(id),
    branch_id                    uuid NOT NULL REFERENCES branch(id),
    drug_sku_id                  uuid NOT NULL REFERENCES drug_sku(id),
    reversed_quantity_base_units integer NOT NULL CHECK (reversed_quantity_base_units > 0),
    reversal_type                varchar(20) NOT NULL CHECK (reversal_type IN ('void', 'refund')),
    reason                       text NOT NULL,
    reversed_by_user_id          uuid NOT NULL REFERENCES app_user(id),
    reversed_at                  timestamptz NOT NULL DEFAULT now(),
    -- one reversal per dispense (the sale status guard already prevents
    -- double-reversal; this is defense in depth)
    CONSTRAINT uq_narcotics_reversal_register UNIQUE (narcotics_register_id)
);

CREATE INDEX IF NOT EXISTS idx_narc_reversal_register    ON narcotics_reversal(narcotics_register_id);
CREATE INDEX IF NOT EXISTS idx_narc_reversal_branch_time ON narcotics_reversal(branch_id, reversed_at DESC);
CREATE INDEX IF NOT EXISTS idx_narc_reversal_sale        ON narcotics_reversal(sale_id);
