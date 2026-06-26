BEGIN;
INSERT INTO drug_sku (drug_id, dosage_form, strength, base_unit) VALUES
  ('24da4b40-2dbe-486a-85f5-8da37f7ef54d', 'Spray',    '(80mcg +4.5mcg)/dose', 'each'),
  ('24da4b40-2dbe-486a-85f5-8da37f7ef54d', 'Spray',    '(60mcg +4.5mcg)/dose', 'each'),
  ('0f55fe8c-74ec-4cef-846d-13ffe3be1885', 'Solution', '5% + 10%',             'bottle'),
  ('5f4055b7-7f2e-4f26-a898-706ecfb22abf', 'Capsule',  NULL,                   'each')
ON CONFLICT ON CONSTRAINT uq_drug_sku_drug_form_strength DO NOTHING
RETURNING (SELECT inn_name FROM drug WHERE id = drug_id), dosage_form, strength, base_unit;
COMMIT;

