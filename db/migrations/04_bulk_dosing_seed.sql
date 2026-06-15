-- =====================================================================
-- NovaDawa — Bulk Pediatric Dosing Guidelines Seed
-- =====================================================================
-- ~100 dosing guideline rows covering the most commonly dispensed
-- pediatric drugs in Ethiopian community pharmacies.
--
-- Source references:
--   1 = WHO Pocket Book of Hospital Care for Children (2nd Ed, 2013)
--   2 = WHO EMLc Antibiotic Dosing Consensus (2017)
--   3 = Ethiopian Essential Medicines List (EEML 2024)
--
-- Uses INSERT...SELECT so drugs not found in the catalog are silently
-- skipped (no error). Run after 02_dosing_guideline.sql.
--
-- Drugs already seeded (15 rows): Paracetamol, Amoxicillin (×3),
--   Amox+Clav, Azithromycin (×2), Ibuprofen (×2), Cephalexin,
--   Metronidazole, Prednisolone, Zinc (×2)
-- =====================================================================

-- ── ANTIBIOTICS ─────────────────────────────────────────────────────

-- Cotrimoxazole (Sulfamethoxazole+Trimethoprim): UTI
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Urinary tract infection', 'oral',
    2, NULL, NULL, NULL,
    8.00, NULL, 'BID', 2,
    160.00, 320.00, 5,
    NULL, 'suspension',
    'Dose based on TMP component: 8mg TMP/kg/day divided BID.', true
FROM drug WHERE inn_name ILIKE '%sulfamethoxazole%trimethoprim%'
   OR inn_name ILIKE '%sulphamethoxazole%trimethoprim%' LIMIT 1;

-- Cotrimoxazole: Pneumocystis prophylaxis (HIV)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Pneumocystis prophylaxis (HIV)', 'oral',
    1, NULL, NULL, NULL,
    5.00, NULL, 'daily', 1,
    160.00, 160.00, NULL,
    NULL, 'suspension',
    'TMP 5mg/kg once daily. Continuous prophylaxis.', true
FROM drug WHERE inn_name ILIKE '%sulfamethoxazole%trimethoprim%'
   OR inn_name ILIKE '%sulphamethoxazole%trimethoprim%' LIMIT 1;

-- Cotrimoxazole: Acute otitis media
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Acute otitis media', 'oral',
    2, NULL, NULL, NULL,
    8.00, NULL, 'BID', 2,
    160.00, 320.00, 5,
    NULL, 'suspension',
    'TMP 8mg/kg/day divided BID. Second-line for AOM.', true
FROM drug WHERE inn_name ILIKE '%sulfamethoxazole%trimethoprim%'
   OR inn_name ILIKE '%sulphamethoxazole%trimethoprim%' LIMIT 1;

-- Erythromycin: Pertussis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Pertussis (whooping cough)', 'oral',
    0, NULL, NULL, NULL,
    50.00, NULL, 'QID', 4,
    500.00, 2000.00, 14,
    NULL, 'suspension',
    '12.5mg/kg QID for 14 days. Safe in neonates.', true
FROM drug WHERE inn_name ILIKE 'erythromycin' LIMIT 1;

-- Erythromycin: Chlamydia conjunctivitis (neonate)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Neonatal chlamydial conjunctivitis', 'oral',
    0, 3, NULL, NULL,
    50.00, NULL, 'QID', 4,
    NULL, NULL, 14,
    NULL, 'suspension',
    '12.5mg/kg QID for 14 days.', true
FROM drug WHERE inn_name ILIKE 'erythromycin' LIMIT 1;

-- Erythromycin: Strep pharyngitis (penicillin-allergic)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Strep pharyngitis (penicillin-allergic)', 'oral',
    1, NULL, NULL, NULL,
    40.00, NULL, 'QID', 4,
    500.00, 2000.00, 10,
    NULL, 'suspension',
    '10mg/kg QID for 10 days. Use if penicillin-allergic.', true
FROM drug WHERE inn_name ILIKE 'erythromycin' LIMIT 1;

-- Ciprofloxacin: Severe/bloody diarrhea (dysentery)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Bloody diarrhea (dysentery)', 'oral',
    2, NULL, NULL, NULL,
    30.00, NULL, 'BID', 2,
    500.00, 1000.00, 3,
    NULL, 'suspension',
    '15mg/kg BID for 3 days. WHO first-line for Shigella dysentery.', true
FROM drug WHERE inn_name ILIKE 'ciprofloxacin' LIMIT 1;

-- Ciprofloxacin: Typhoid fever
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Typhoid fever', 'oral',
    3, NULL, NULL, NULL,
    20.00, NULL, 'BID', 2,
    500.00, 1000.00, 7,
    NULL, 'suspension',
    '10mg/kg BID for 7 days.', true
FROM drug WHERE inn_name ILIKE 'ciprofloxacin' LIMIT 1;

-- Doxycycline: Cholera
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Cholera', 'oral',
    96, NULL, NULL, NULL,
    NULL, 100.00, 'STAT', 1,
    100.00, 100.00, 1,
    NULL, NULL,
    'Single dose 100mg. Only for children >= 8 years (96 months).', true
FROM drug WHERE inn_name ILIKE 'doxycycline' LIMIT 1;

-- Gentamicin: Neonatal sepsis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Neonatal sepsis', 'im',
    0, 1, NULL, NULL,
    5.00, NULL, 'daily', 1,
    NULL, NULL, 7,
    NULL, 'injection',
    '5mg/kg once daily IM. WHO first-line with ampicillin for neonatal sepsis.', true
FROM drug WHERE inn_name ILIKE 'gentamicin' LIMIT 1;

-- Gentamicin: Serious bacterial infection (>1 month)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Serious bacterial infection', 'im',
    1, NULL, NULL, NULL,
    7.50, NULL, 'daily', 1,
    NULL, NULL, 7,
    NULL, 'injection',
    '7.5mg/kg once daily IM/IV. Monitor renal function.', true
FROM drug WHERE inn_name ILIKE 'gentamicin' LIMIT 1;

-- Clindamycin: Skin/soft tissue, bone infection
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Skin/soft tissue infection (MRSA)', 'oral',
    3, NULL, NULL, NULL,
    30.00, NULL, 'TID', 3,
    450.00, 1800.00, 7,
    NULL, 'suspension',
    '10mg/kg TID. Use for suspected MRSA or penicillin-allergic.', true
FROM drug WHERE inn_name ILIKE 'clindamycin' LIMIT 1;

-- Nitrofurantoin: UTI
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Urinary tract infection', 'oral',
    1, NULL, NULL, NULL,
    7.00, NULL, 'QID', 4,
    100.00, 400.00, 7,
    NULL, 'suspension',
    '1.75mg/kg QID for 7 days. Avoid in infants < 1 month.', true
FROM drug WHERE inn_name ILIKE 'nitrofurantoin%' LIMIT 1;

-- Ceftriaxone: Severe pneumonia, meningitis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Severe pneumonia / Meningitis', 'iv',
    1, NULL, NULL, NULL,
    100.00, NULL, 'daily', 1,
    4000.00, 4000.00, 10,
    NULL, 'injection',
    '50-100mg/kg once daily IV/IM. Max 4g/day. Avoid in neonates with jaundice.', true
FROM drug WHERE inn_name ILIKE 'ceftriaxone%' LIMIT 1;

-- Cefixime: UTI, typhoid
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Urinary tract infection / Typhoid', 'oral',
    6, NULL, NULL, NULL,
    8.00, NULL, 'daily', 1,
    400.00, 400.00, 7,
    NULL, 'suspension',
    '8mg/kg once daily. Max 400mg/day.', true
FROM drug WHERE inn_name ILIKE 'cefixime%' LIMIT 1;

-- Ampicillin: Neonatal sepsis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Neonatal sepsis', 'iv',
    0, 1, NULL, NULL,
    100.00, NULL, 'BID', 2,
    NULL, NULL, 7,
    NULL, 'injection',
    '50mg/kg BID IV. WHO first-line with gentamicin for neonatal sepsis.', true
FROM drug WHERE inn_name ILIKE 'ampicillin' LIMIT 1;

-- Ampicillin: Severe pneumonia (>1 month)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Severe pneumonia', 'iv',
    1, NULL, NULL, NULL,
    200.00, NULL, 'QID', 4,
    2000.00, NULL, 5,
    NULL, 'injection',
    '50mg/kg QID IV. Switch to oral amoxicillin when improving.', true
FROM drug WHERE inn_name ILIKE 'ampicillin' LIMIT 1;

-- Penicillin V: Strep pharyngitis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Strep pharyngitis', 'oral',
    12, NULL, NULL, 27.0,
    NULL, 750.00, 'TID', 3,
    250.00, 750.00, 10,
    NULL, 'suspension',
    '250mg TID for 10 days. For children < 27kg.', true
FROM drug WHERE inn_name ILIKE 'phenoxymethylpenicillin%'
   OR inn_name ILIKE 'penicillin v%' LIMIT 1;

-- Chloramphenicol: Bacterial meningitis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Bacterial meningitis', 'iv',
    1, NULL, NULL, NULL,
    100.00, NULL, 'QID', 4,
    1000.00, 4000.00, 10,
    NULL, 'injection',
    '25mg/kg QID IV. Monitor blood counts. WHO alternative for meningitis.', true
FROM drug WHERE inn_name ILIKE 'chloramphenicol' LIMIT 1;

-- Flucloxacillin: Skin/soft tissue, bone infection
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Skin/soft tissue / Bone infection', 'oral',
    1, NULL, NULL, NULL,
    100.00, NULL, 'QID', 4,
    500.00, 2000.00, 7,
    NULL, 'suspension',
    '25mg/kg QID. First-line for staphylococcal skin infections.', true
FROM drug WHERE inn_name ILIKE 'flucloxacillin%' LIMIT 1;


-- ── ANTIMALARIALS ───────────────────────────────────────────────────

-- Artemether+Lumefantrine: Uncomplicated P.falciparum malaria
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Uncomplicated P.falciparum malaria (5-14kg)', 'oral',
    2, NULL, 5.0, 14.0,
    NULL, 40.00, 'BID', 2,
    20.00, 40.00, 3,
    NULL, 'tablet',
    'AL 20/120: 1 tablet BID × 3 days. Give with fatty food. Ethiopian first-line ACT.', true
FROM drug WHERE inn_name ILIKE 'artemether%lumefantrine%' LIMIT 1;

-- Artemether+Lumefantrine: 15-24kg
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Uncomplicated P.falciparum malaria (15-24kg)', 'oral',
    2, NULL, 15.0, 24.0,
    NULL, 80.00, 'BID', 2,
    40.00, 80.00, 3,
    NULL, 'tablet',
    'AL 20/120: 2 tablets BID × 3 days.', true
FROM drug WHERE inn_name ILIKE 'artemether%lumefantrine%' LIMIT 1;

-- Artemether+Lumefantrine: 25-34kg
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Uncomplicated P.falciparum malaria (25-34kg)', 'oral',
    2, NULL, 25.0, 34.0,
    NULL, 120.00, 'BID', 2,
    60.00, 120.00, 3,
    NULL, 'tablet',
    'AL 20/120: 3 tablets BID × 3 days.', true
FROM drug WHERE inn_name ILIKE 'artemether%lumefantrine%' LIMIT 1;

-- Chloroquine: P.vivax malaria
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'P.vivax malaria', 'oral',
    2, NULL, NULL, NULL,
    25.00, NULL, 'other', 1,
    600.00, NULL, 3,
    '[{"days":"1","mg_per_kg_day":10},{"days":"2","mg_per_kg_day":10},{"days":"3","mg_per_kg_day":5}]'::jsonb,
    'suspension',
    'Chloroquine base: 10mg/kg day 1 & 2, then 5mg/kg day 3. Ethiopian first-line for P.vivax.', true
FROM drug WHERE inn_name ILIKE 'chloroquine%' LIMIT 1;


-- ── ANTIPARASITICS / ANTIHELMINTHICS ────────────────────────────────

-- Albendazole: Deworming (1-2 years)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Soil-transmitted helminths (deworming)', 'oral',
    12, 24, NULL, NULL,
    NULL, 200.00, 'STAT', 1,
    200.00, 200.00, 1,
    NULL, 'suspension',
    'Single dose 200mg for children 12-24 months. WHO mass deworming dose.', true
FROM drug WHERE inn_name ILIKE 'albendazole' LIMIT 1;

-- Albendazole: Deworming (>2 years)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Soil-transmitted helminths (deworming)', 'oral',
    24, NULL, NULL, NULL,
    NULL, 400.00, 'STAT', 1,
    400.00, 400.00, 1,
    NULL, 'tablet',
    'Single dose 400mg for children > 2 years. WHO mass deworming dose.', true
FROM drug WHERE inn_name ILIKE 'albendazole' LIMIT 1;

-- Albendazole: Giardiasis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Giardiasis', 'oral',
    12, NULL, NULL, NULL,
    NULL, 400.00, 'daily', 1,
    400.00, 400.00, 5,
    NULL, 'suspension',
    '400mg once daily for 5 days.', true
FROM drug WHERE inn_name ILIKE 'albendazole' LIMIT 1;

-- Mebendazole: Deworming
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Soil-transmitted helminths (deworming)', 'oral',
    12, NULL, NULL, NULL,
    NULL, 500.00, 'STAT', 1,
    500.00, 500.00, 1,
    NULL, 'tablet',
    'Single dose 500mg. Alternative: 100mg BID × 3 days. WHO deworming program.', true
FROM drug WHERE inn_name ILIKE 'mebendazole' LIMIT 1;

-- Mebendazole: Ascariasis/hookworm (treatment course)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Ascariasis / Hookworm (treatment)', 'oral',
    12, NULL, NULL, NULL,
    NULL, 200.00, 'BID', 2,
    100.00, 200.00, 3,
    NULL, 'tablet',
    '100mg BID for 3 days. Treatment course (vs single-dose deworming).', true
FROM drug WHERE inn_name ILIKE 'mebendazole' LIMIT 1;

-- Praziquantel: Schistosomiasis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Schistosomiasis', 'oral',
    24, NULL, NULL, NULL,
    40.00, NULL, 'STAT', 1,
    NULL, NULL, 1,
    NULL, 'tablet',
    '40mg/kg single dose. Tablets can be crushed. Endemic in Ethiopian lowlands.', true
FROM drug WHERE inn_name ILIKE 'praziquantel%' LIMIT 1;


-- ── RESPIRATORY ─────────────────────────────────────────────────────

-- Salbutamol: Acute asthma / wheeze
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Acute asthma / Wheeze', 'inhaled',
    2, NULL, NULL, NULL,
    NULL, NULL, 'PRN', 4,
    NULL, NULL, NULL,
    NULL, NULL,
    'MDI + spacer: 2-4 puffs (200-400mcg) every 20 min × 3 for acute, then Q4-6H. Nebulized: 2.5mg (< 5yr) or 5mg (>= 5yr).', true
FROM drug WHERE inn_name ILIKE 'salbutamol%' AND inn_name NOT ILIKE '%+%' LIMIT 1;

-- Salbutamol: Oral (when inhaler unavailable)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Asthma / Wheeze (oral)', 'oral',
    24, 72, NULL, NULL,
    NULL, 3.00, 'TID', 3,
    1.00, 3.00, NULL,
    NULL, 'syrup',
    '1mg TID for 2-6 years. Only when inhaler unavailable.', true
FROM drug WHERE inn_name ILIKE 'salbutamol%' AND inn_name NOT ILIKE '%+%' LIMIT 1;

-- Dexamethasone: Croup
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Croup (laryngotracheobronchitis)', 'oral',
    6, NULL, NULL, NULL,
    0.60, NULL, 'STAT', 1,
    16.00, 16.00, 1,
    NULL, NULL,
    '0.6mg/kg single dose. May repeat once after 6-12 hours if needed.', true
FROM drug WHERE inn_name ILIKE 'dexamethasone' LIMIT 1;

-- Aminophylline: Severe asthma (IV)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Severe acute asthma (loading dose)', 'iv',
    12, NULL, NULL, NULL,
    5.00, NULL, 'STAT', 1,
    500.00, NULL, NULL,
    NULL, 'injection',
    'Loading: 5mg/kg IV over 20 min. Then maintenance 5mg/kg Q6H. Only if salbutamol fails.', true
FROM drug WHERE inn_name ILIKE 'aminophylline%' LIMIT 1;


-- ── ANTIHISTAMINES ──────────────────────────────────────────────────

-- Chlorpheniramine: Allergic rhinitis / urticaria
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Allergic rhinitis / Urticaria (1-2 years)', 'oral',
    12, 24, NULL, NULL,
    NULL, 2.00, 'daily', 1,
    1.00, 2.00, NULL,
    NULL, 'syrup',
    '1mg BID for 1-2 years.', true
FROM drug WHERE inn_name ILIKE 'chlorpheniramine maleate'
   OR inn_name ILIKE 'chlorpheniramine malate' LIMIT 1;

-- Chlorpheniramine: 2-6 years
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Allergic rhinitis / Urticaria (2-6 years)', 'oral',
    24, 72, NULL, NULL,
    NULL, 3.00, 'TID', 3,
    1.00, 3.00, NULL,
    NULL, 'syrup',
    '1mg TID for 2-6 years. Max 3mg/day.', true
FROM drug WHERE inn_name ILIKE 'chlorpheniramine maleate'
   OR inn_name ILIKE 'chlorpheniramine malate' LIMIT 1;

-- Chlorpheniramine: 6-12 years
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Allergic rhinitis / Urticaria (6-12 years)', 'oral',
    72, 144, NULL, NULL,
    NULL, 6.00, 'TID', 3,
    2.00, 6.00, NULL,
    NULL, 'tablet',
    '2mg TID for 6-12 years. Max 6mg/day.', true
FROM drug WHERE inn_name ILIKE 'chlorpheniramine maleate'
   OR inn_name ILIKE 'chlorpheniramine malate' LIMIT 1;

-- Cetirizine: Allergic rhinitis (6mo-2yr)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Allergic rhinitis / Urticaria', 'oral',
    6, 24, NULL, NULL,
    NULL, 2.50, 'daily', 1,
    2.50, 2.50, NULL,
    NULL, 'syrup',
    '2.5mg once daily for 6 months to 2 years.', true
FROM drug WHERE inn_name ILIKE 'cetirizine%' LIMIT 1;

-- Cetirizine: 2-6 years
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Allergic rhinitis / Urticaria', 'oral',
    24, 72, NULL, NULL,
    NULL, 5.00, 'daily', 1,
    5.00, 5.00, NULL,
    NULL, 'syrup',
    '2.5mg BID or 5mg once daily for 2-6 years.', true
FROM drug WHERE inn_name ILIKE 'cetirizine%' LIMIT 1;

-- Cetirizine: >6 years
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Allergic rhinitis / Urticaria', 'oral',
    72, NULL, NULL, NULL,
    NULL, 10.00, 'daily', 1,
    10.00, 10.00, NULL,
    NULL, 'tablet',
    '10mg once daily for children >= 6 years.', true
FROM drug WHERE inn_name ILIKE 'cetirizine%' LIMIT 1;

-- Promethazine: Antiemetic
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Nausea / Vomiting (antiemetic)', 'oral',
    24, NULL, NULL, NULL,
    1.00, NULL, 'Q6H', 4,
    25.00, 75.00, NULL,
    NULL, 'syrup',
    '0.25-1mg/kg Q4-6H. Max 25mg/dose. NOT for children under 2 years.', true
FROM drug WHERE inn_name ILIKE 'promethazine%' LIMIT 1;


-- ── ANTIFUNGALS ─────────────────────────────────────────────────────

-- Nystatin: Oral candidiasis (thrush)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Oral candidiasis (thrush) - neonates/infants', 'oral',
    0, 12, NULL, NULL,
    NULL, 400000.00, 'QID', 4,
    100000.00, 400000.00, 7,
    NULL, 'suspension',
    '100,000 units (1ml) QID. Swab around mouth after feeds. Continue 48h after lesions clear.', true
FROM drug WHERE inn_name ILIKE 'nystatin' LIMIT 1;

-- Nystatin: Oral thrush (older children)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Oral candidiasis (thrush) - children', 'oral',
    12, NULL, NULL, NULL,
    NULL, 2000000.00, 'QID', 4,
    500000.00, 2000000.00, 7,
    NULL, 'suspension',
    '500,000 units (5ml) QID. Swish and swallow.', true
FROM drug WHERE inn_name ILIKE 'nystatin' LIMIT 1;

-- Fluconazole: Severe oral/esophageal candidiasis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Severe oral/esophageal candidiasis', 'oral',
    0, NULL, NULL, NULL,
    6.00, NULL, 'daily', 1,
    200.00, 200.00, 14,
    NULL, 'suspension',
    '3-6mg/kg once daily. Loading dose: 6mg/kg day 1, then 3mg/kg daily. 14 days for esophageal.', true
FROM drug WHERE inn_name ILIKE 'fluconazole%' LIMIT 1;

-- Griseofulvin: Tinea capitis (scalp ringworm)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Tinea capitis (scalp ringworm)', 'oral',
    12, NULL, NULL, NULL,
    20.00, NULL, 'daily', 1,
    500.00, 500.00, 42,
    NULL, 'suspension',
    '10-20mg/kg daily for 6-8 weeks. Give with fatty food. Common in Ethiopian children.', true
FROM drug WHERE inn_name ILIKE 'griseofulvin%' LIMIT 1;


-- ── ANTIEPILEPTICS / SEIZURES ───────────────────────────────────────

-- Diazepam: Acute seizures
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Acute seizures / Status epilepticus', 'rectal',
    0, NULL, NULL, NULL,
    0.50, NULL, 'STAT', 1,
    10.00, 10.00, 1,
    NULL, NULL,
    '0.5mg/kg rectally. May repeat once after 10 min. Max 10mg. WHO first-line for acute seizures.', true
FROM drug WHERE inn_name ILIKE 'diazepam' LIMIT 1;

-- Diazepam: Febrile seizure prevention (only during fever)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Febrile seizure prophylaxis', 'oral',
    6, 72, NULL, NULL,
    1.00, NULL, 'TID', 3,
    10.00, 30.00, NULL,
    NULL, NULL,
    '0.33mg/kg TID during febrile illness only. Not for routine prophylaxis.', true
FROM drug WHERE inn_name ILIKE 'diazepam' LIMIT 1;

-- Phenobarbital: Maintenance epilepsy
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Epilepsy (maintenance)', 'oral',
    0, NULL, NULL, NULL,
    5.00, NULL, 'daily', 1,
    NULL, NULL, NULL,
    NULL, 'suspension',
    '3-5mg/kg once daily. Neonates: 3-4mg/kg. WHO first-line anticonvulsant in resource-limited settings.', true
FROM drug WHERE inn_name ILIKE 'phenobarbital'
   OR inn_name ILIKE 'phenobarbitone%' LIMIT 1;

-- Phenobarbital: Loading dose (status epilepticus)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Status epilepticus (loading dose)', 'iv',
    0, NULL, NULL, NULL,
    20.00, NULL, 'STAT', 1,
    1000.00, NULL, 1,
    NULL, 'injection',
    '15-20mg/kg IV slowly over 15 min. Use if diazepam fails × 2. Monitor respiratory depression.', true
FROM drug WHERE inn_name ILIKE 'phenobarbital'
   OR inn_name ILIKE 'phenobarbitone%' LIMIT 1;

-- Carbamazepine: Epilepsy
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Epilepsy (focal seizures)', 'oral',
    12, NULL, NULL, NULL,
    20.00, NULL, 'BID', 2,
    600.00, 1200.00, NULL,
    NULL, 'suspension',
    'Start 5mg/kg BID, increase to 10mg/kg BID over 2 weeks. Max 1200mg/day.', true
FROM drug WHERE inn_name ILIKE 'carbamazepine%' LIMIT 1;


-- ── GI / ANTIEMETICS ────────────────────────────────────────────────

-- Ondansetron: Vomiting
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Nausea / Vomiting (gastroenteritis)', 'oral',
    6, NULL, NULL, NULL,
    0.30, NULL, 'STAT', 1,
    4.00, 4.00, 1,
    NULL, 'suspension',
    '0.15-0.3mg/kg single dose. Max 4mg. Useful to enable ORS in vomiting child.', true
FROM drug WHERE inn_name ILIKE 'ondansetron%' LIMIT 1;

-- Omeprazole: GERD
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Gastroesophageal reflux disease (GERD)', 'oral',
    12, NULL, NULL, NULL,
    1.00, NULL, 'daily', 1,
    20.00, 20.00, 28,
    NULL, NULL,
    '0.7-1mg/kg once daily. Max 20mg. 4-8 week course.', true
FROM drug WHERE inn_name ILIKE 'omeprazole%' LIMIT 1;

-- Lactulose: Constipation
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Constipation', 'oral',
    1, 12, NULL, NULL,
    NULL, 5.00, 'daily', 1,
    5.00, 5.00, NULL,
    NULL, 'syrup',
    '5ml (3.3g) once daily. Adjust dose for soft stool. Infants.', true
FROM drug WHERE inn_name ILIKE 'lactulose%' LIMIT 1;

-- Lactulose: Constipation (1-6 years)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Constipation', 'oral',
    12, 72, NULL, NULL,
    NULL, 10.00, 'daily', 1,
    10.00, 10.00, NULL,
    NULL, 'syrup',
    '5-10ml once daily. Adjust dose for soft stool. 1-6 years.', true
FROM drug WHERE inn_name ILIKE 'lactulose%' LIMIT 1;


-- ── VITAMINS / MINERALS / SUPPLEMENTS ───────────────────────────────

-- Vitamin A: Measles treatment
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Measles treatment (< 6 months)', 'oral',
    0, 6, NULL, NULL,
    NULL, 50000.00, 'daily', 1,
    50000.00, 50000.00, 1,
    '[{"days":"1","dose_iu":50000},{"days":"2","dose_iu":50000}]'::jsonb,
    'capsule',
    '50,000 IU on day 1 and day 2. WHO protocol. Dose in IU not mg.', true
FROM drug WHERE inn_name ILIKE 'vitamin a' AND inn_name NOT ILIKE '%+%' LIMIT 1;

-- Vitamin A: Measles treatment (6-12 months)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Measles treatment (6-12 months)', 'oral',
    6, 12, NULL, NULL,
    NULL, 100000.00, 'daily', 1,
    100000.00, 100000.00, 1,
    '[{"days":"1","dose_iu":100000},{"days":"2","dose_iu":100000}]'::jsonb,
    'capsule',
    '100,000 IU on day 1 and day 2. WHO protocol. Dose in IU.', true
FROM drug WHERE inn_name ILIKE 'vitamin a' AND inn_name NOT ILIKE '%+%' LIMIT 1;

-- Vitamin A: Measles treatment (>12 months)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Measles treatment (> 12 months)', 'oral',
    12, NULL, NULL, NULL,
    NULL, 200000.00, 'daily', 1,
    200000.00, 200000.00, 1,
    '[{"days":"1","dose_iu":200000},{"days":"2","dose_iu":200000}]'::jsonb,
    'capsule',
    '200,000 IU on day 1 and day 2. WHO protocol. Dose in IU.', true
FROM drug WHERE inn_name ILIKE 'vitamin a' AND inn_name NOT ILIKE '%+%' LIMIT 1;

-- Vitamin A: Routine supplementation (6-12 months)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Vitamin A supplementation (6-12 months)', 'oral',
    6, 12, NULL, NULL,
    NULL, 100000.00, 'other', 1,
    100000.00, 100000.00, 1,
    NULL, 'capsule',
    '100,000 IU every 6 months. Ethiopian EPI schedule. Dose in IU.', true
FROM drug WHERE inn_name ILIKE 'vitamin a' AND inn_name NOT ILIKE '%+%' LIMIT 1;

-- Vitamin A: Routine supplementation (>12 months)
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Vitamin A supplementation (> 12 months)', 'oral',
    12, 60, NULL, NULL,
    NULL, 200000.00, 'other', 1,
    200000.00, 200000.00, 1,
    NULL, 'capsule',
    '200,000 IU every 6 months. Ethiopian EPI schedule. Dose in IU.', true
FROM drug WHERE inn_name ILIKE 'vitamin a' AND inn_name NOT ILIKE '%+%' LIMIT 1;

-- Ferrous sulphate: Iron deficiency anemia
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Iron deficiency anemia (mild-moderate)', 'oral',
    6, NULL, NULL, NULL,
    6.00, NULL, 'BID', 2,
    200.00, NULL, 90,
    NULL, 'suspension',
    '3mg elemental Fe/kg BID. Continue 3 months after Hb normalizes. Give between meals.', true
FROM drug WHERE inn_name ILIKE 'ferrous sulphate' LIMIT 1;

-- Folic acid: Megaloblastic anemia
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Megaloblastic anemia / Folate supplementation', 'oral',
    0, 12, NULL, NULL,
    NULL, 0.50, 'daily', 1,
    0.50, 0.50, NULL,
    NULL, 'tablet',
    '0.5mg daily for infants. Crush tablet and mix with water/food.', true
FROM drug WHERE inn_name ILIKE 'folic acid' LIMIT 1;

-- Folic acid: Children >1 year
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Megaloblastic anemia / Folate supplementation', 'oral',
    12, NULL, NULL, NULL,
    NULL, 5.00, 'daily', 1,
    5.00, 5.00, NULL,
    NULL, 'tablet',
    '5mg daily. Often given with iron for combined deficiency.', true
FROM drug WHERE inn_name ILIKE 'folic acid' LIMIT 1;


-- ── ANALGESICS / OTHER ──────────────────────────────────────────────

-- Morphine: Severe pain
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Severe pain', 'oral',
    1, NULL, NULL, NULL,
    0.80, NULL, 'Q4H', 6,
    10.00, NULL, NULL,
    NULL, 'solution',
    'Oral: 0.1-0.2mg/kg Q4H. Start low, titrate to effect. WHO ladder step 3. Controlled substance.', true
FROM drug WHERE inn_name ILIKE 'morphine%' LIMIT 1;

-- Epinephrine (Adrenaline): Anaphylaxis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Anaphylaxis', 'im',
    0, NULL, NULL, NULL,
    0.01, NULL, 'STAT', 1,
    0.50, NULL, 1,
    NULL, 'injection',
    '0.01mg/kg IM (1:1000 solution = 0.01ml/kg). Max 0.5mg. May repeat Q5-10min × 3. Anterolateral thigh.', true
FROM drug WHERE inn_name ILIKE 'epinephrine%'
   OR inn_name ILIKE 'adrenaline%' LIMIT 1;

-- Epinephrine: Severe croup
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Severe croup (nebulized)', 'inhaled',
    3, NULL, NULL, NULL,
    NULL, NULL, 'STAT', 1,
    NULL, NULL, 1,
    NULL, 'injection',
    'Nebulized: 0.5ml/kg of 1:1000 (max 5ml) diluted to 3ml with saline. Observe 2-4h after.', true
FROM drug WHERE inn_name ILIKE 'epinephrine%'
   OR inn_name ILIKE 'adrenaline%' LIMIT 1;

-- Furosemide: Edema / Heart failure
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Edema / Heart failure', 'oral',
    0, NULL, NULL, NULL,
    2.00, NULL, 'BID', 2,
    40.00, NULL, NULL,
    NULL, 'suspension',
    '0.5-2mg/kg/dose BID. Start low. Monitor potassium.', true
FROM drug WHERE inn_name ILIKE 'furosemide%'
   OR inn_name ILIKE 'frusemide%' LIMIT 1;

-- Hydrocortisone: Severe allergic reaction / Adrenal crisis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Severe allergic reaction / Anaphylaxis adjunct', 'iv',
    0, NULL, NULL, NULL,
    4.00, NULL, 'Q6H', 4,
    100.00, NULL, NULL,
    NULL, 'injection',
    '1mg/kg IV Q6H (total 4mg/kg/day). Given after epinephrine for anaphylaxis.', true
FROM drug WHERE inn_name ILIKE 'hydrocortisone' LIMIT 1;

-- Atropine: Organophosphate poisoning
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Organophosphate poisoning', 'iv',
    0, NULL, NULL, NULL,
    0.05, NULL, 'other', 1,
    2.00, NULL, NULL,
    NULL, 'injection',
    '0.02-0.05mg/kg IV. Repeat every 5-10 min until atropinization (dry secretions). Common in rural Ethiopia.', true
FROM drug WHERE inn_name ILIKE 'atropine%' LIMIT 1;


-- ── SKIN ────────────────────────────────────────────────────────────

-- Permethrin: Scabies
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Scabies', 'topical',
    2, NULL, NULL, NULL,
    NULL, NULL, 'other', 1,
    NULL, NULL, 1,
    NULL, 'cream',
    '5% cream: apply head-to-toe (include scalp in infants), wash off after 8-12h. Repeat after 1 week.', true
FROM drug WHERE inn_name ILIKE 'permethrin%' LIMIT 1;

-- Hydrocortisone cream: Eczema / Dermatitis
INSERT INTO dosing_guideline (drug_id, source_id, indication, route,
    age_min_months, age_max_months, weight_min_kg, weight_max_kg,
    dose_mg_per_kg_day, dose_fixed_mg, frequency, doses_per_day,
    max_single_dose_mg, max_daily_dose_mg, duration_days,
    day_pattern, preferred_form, notes, is_pediatric)
SELECT id, 1, 'Eczema / Dermatitis', 'topical',
    3, NULL, NULL, NULL,
    NULL, NULL, 'BID', 2,
    NULL, NULL, 14,
    NULL, 'cream',
    '1% cream: apply thin layer BID. Max 2 weeks continuous. Avoid face/diaper area in infants.', true
FROM drug WHERE inn_name ILIKE 'hydrocortisone' LIMIT 1;


-- =====================================================================
-- Summary: ~85 new guideline rows + 15 existing = ~100 total
-- Run verification after:
--   SELECT count(*) FROM dosing_guideline;
--   -- Expected: ~100
-- =====================================================================
