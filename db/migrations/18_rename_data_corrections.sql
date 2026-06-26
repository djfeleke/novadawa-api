-- Migration 18: two name corrections (cosmetic; SKUs/data unchanged).
--   ceead3a4: 'Liquid Nitrogen /Nitrogen mustard/ Mechlorethamine' (SKU = Gel 0.012mg/60g, a
--             mechlorethamine topical gel) -> clean name. 'Liquid Nitrogen' was wrongly fused in.
--   8414644f: truncated 'Soya-based non-milk preparations Phospholipids from soya-beans (con'
--             -> drop the dangling '(con' fragment.
BEGIN;
UPDATE drug SET inn_name = 'Mechlorethamine (topical gel)'
  WHERE id = 'ceead3a4-c1fb-4357-bab0-b80ee49aee80';
UPDATE drug SET inn_name = 'Soya-based non-milk preparations (Phospholipids from soya-beans)'
  WHERE id = '8414644f-b43f-44c0-9343-498509af51b3';
SELECT id, inn_name FROM drug
  WHERE id IN ('ceead3a4-c1fb-4357-bab0-b80ee49aee80','8414644f-b43f-44c0-9343-498509af51b3');
COMMIT;
