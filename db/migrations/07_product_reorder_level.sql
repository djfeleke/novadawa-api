-- 07_product_reorder_level.sql
-- Per-product low-stock threshold. When a low-stock query is run without an
-- explicit threshold, each product is compared against its own reorder_level.
-- Default 0 means "no alert configured" (available can't drop below 0, so a
-- level of 0 never triggers).

ALTER TABLE product
    ADD COLUMN IF NOT EXISTS reorder_level integer NOT NULL DEFAULT 0
        CHECK (reorder_level >= 0);
