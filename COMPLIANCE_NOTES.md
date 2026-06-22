# NovaDawa — EFDA Controlled-Substance Compliance Notes

Source of truth: **EFDA National List of Psychotropic Substances and Narcotic
drugs**, Ethiopian Food, Medicine and Healthcare Administration and Control
Authority, Addis Ababa, May 2017. Plus the reporting forms (NPS series) bound
in the same document.

This file pins the regulatory reasoning behind NovaDawa's controlled-substance
handling so the basis for each design choice is recoverable later.

---

## 1. Narcotic vs Psychotropic classification

EFDA defines the split by UN convention, not by clinical category:

- **Narcotic drug** — controlled under the 1961 Single Convention on Narcotic
  Drugs (Schedules I & II), as ratified by Ethiopia.
- **Psychotropic substance** — controlled under the 1971 Convention on
  Psychotropic Substances (Schedules III & IV), as ratified by Ethiopia.

Classification is a property of the **substance** (parent drug), and applies to
all SKUs/dosage forms of that drug. Stored on `drug_sku.narcotic_class`
(`'narcotic'` | `'psychotropic'`), populated from the list below.

### NARCOTIC (1961 Convention)
Cocaine · Codeine · Diphenoxylate (+ Atropine) · Fentanyl · Methadone ·
Morphine · Pethidine

### PSYCHOTROPIC (1971 Convention)
Alprazolam · Bromazepam · Chlordiazepoxide (incl. + Clidinium, and the
Amitriptyline + Chlordiazepoxide combination) · Clonazepam · Dextroamphetamine ·
Diazepam · Flurazepam · Lorazepam · Medazepam · Methylphenidate · Midazolam ·
Oxazepam · Pentazocine · Pentobarbital · Phenobarbital · Temazepam · Zolpidem

### Notes / edge cases
- **Plain Amitriptyline** is NOT controlled. Only the
  *Amitriptyline + Chlordiazepoxide* combination is (via chlordiazepoxide).
- **Apomorphine** is NOT on the EFDA list. By internal decision it is kept
  `controlled_substance = true` (clinical caution) but assigned **no** class —
  so it is gated at checkout yet appears on neither EFDA register.
- **Tramadol** is classified **narcotic** even though it is absent from the
  2017 list and from the 1961/1971 UN Conventions. EFDA categorises it as a
  narcotic drug by *executive categorization* under Proclamation No. 1112/2019
  (which defines a narcotic drug to include one the executive organ so
  categorizes). Documented example of "controlled by national directive, not by
  UN convention." Its 5 SKUs were classified narcotic via classify_tramadol.sql.
- The catalogue's `controlled_substance` flags did not originally match this
  list; the classification script corrects them so the checkout gate fires for
  every EFDA-controlled substance (see `classify_controlled_substances.sql`).
- The controlled-substance flag is stored at the **SKU level**
  (`drug_sku.controlled_substance`). The checkout gate must therefore test
  `(drug.controlled_substance OR drug_sku.controlled_substance)` — testing only
  the drug-level flag would miss SKU-level-only controlled drugs (a hole that
  existed and was fixed).

---

## 2. Dispensing registers (kept at the pharmacy)

Two official forms, **identical in columns**, differing only by title/class:

- **FORM NPS/09/A** — Record of Dispensed *Narcotic* Drugs
- **FORM NPS/09/B** — Record of Dispensed *Psychotropic* Drugs

Columns (both): S.No · Date · Name of patient · **Age · Sex · Address** ·
Description of drug · Quantity dispensed · Name of prescriber ·
Prescription serial No.

Implication: one PDF template, filtered by `narcotic_class`, with a class-specific
title — not two layouts. Age/Sex/Address are EFDA-required and were missing from
the original schema (added in migration 08).

Unit of measure for the Quantity column is `drug_sku.base_unit` (not dosage_form).
Strength and Dosage Form are carried as separate columns (the annual forms list
them separately).

---

## 3. Override policy (missing human-supplied fields)

A controlled medicine should still be dispensable when a required *paper* field
is genuinely unavailable (e.g. prescriber license not retrievable) — but the
record must show this was a documented professional decision, not a silent gap.

Rules:
- **Overridable (human-supplied):** patient name/age/sex/address/ID, prescriber
  name/license, prescription serial, prescription image.
- **Never overridable (system-derived):** drug, quantity, date, dispensing
  pharmacist, branch, running balance — the system always knows these.
- An override records **one reason per controlled dispense** plus the
  **authorizing pharmacist** (`override_reason`, `overridden_by_user_id`).
- Available for **both** narcotic and psychotropic dispenses.
- Enforced at the **checkout API layer** ("required unless overridden"), not as
  DB NOT NULL constraints — so an overridden entry is a documented exception,
  not a data error.

Domain basis: controlled substances are prescribed on their own
single-drug, **color-coded** prescriptions (narcotic vs psychotropic are
distinct documents), so one override reason per dispense maps cleanly to one
prescription.

---

## 4. Reporting cadence (for the future annual/quarterly report feature)

- **Narcotic** statistics — required **quarterly** (G.C. calendar).
- **Psychotropic** statistics — annual report required at end of December
  (various NPS forms also collect quarterly import/export/distribution stats).

Annual report forms (per-substance rollup, NOT per-dispense):
`NPS/15/A` / `NPS/16/A` (Narcotic), `NPS/15/B` / `NPS/16/B` (Psychotropic).
Columns: Substance · Dosage Form · Strength · Balance at beginning of year ·
Quantity purchased during year · (Purchased from) · Consumption during year ·
Balance at end of year. Derivable from existing data: purchases =
`inventory_movement` type `purchase`; consumption = register dispenses;
balances = stock at the year boundaries. **Not yet built.**

---

## 5. Facility authorization matrix (future multi-facility scale-up)

From the National List, ANNEX 1 — "Health Institutions Authorized to handle
Narcotic drug or Psychotropic prescription." Captured here as reference data for
a future facility-type model; **not yet implemented**.

| Facility type      | Narcotic | Psychotropic |
|--------------------|:--------:|:------------:|
| Hospital           |   yes    |     yes      |
| Health center      |   yes    |     yes      |
| Specialty center   |   yes    |     yes      |
| Specialty clinic   |    —     |     yes      |
| Medium clinic      |    —     |     yes      |
| Nursing home       |    —     |     yes      |
| Primary clinic     |    —     |     yes      |

(Transcribed from the source table; verify exact tiers against the original
before relying on it for authorization logic.)

### Architectural intent (no change made now)
If NovaDawa later serves government facilities (tertiary/regional hospitals,
health centers, clinics, retail pharmacies) with tier-dependent features and
dispensing rights:

- `facility_type` becomes an attribute of the branch/tenant (trivial migration;
  schema is already tenant-shaped: pharmacy_group → branch → users/roles).
- The table above becomes the seed of an **authorization layer**: facility_type
  × prescription_type → allowed.
- **One discipline worth keeping from now at zero cost:** route every
  permission/capability check through a single "what is this facility allowed to
  do" lookup rather than scattering `if facility == X` checks across the code.
  Then adding facility types changes one place, not many. Everything else
  (the column, the matrix, tier-based feature flags) slots in when needed.
