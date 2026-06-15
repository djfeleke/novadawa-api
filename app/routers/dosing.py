"""
Dosing guideline & calculator endpoints.

  GET /api/v1/dosing/{drug_id}
      All dosing guidelines for a drug (all indications, age bands).

  GET /api/v1/dosing/calculate?drug_id=...&weight_kg=10&age_months=14
      Compute per-dose mg and per-SKU ml for a specific patient.
      The core endpoint for the dispensing UI.
"""
import re
from typing import Optional

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.dosing import (
    CalculatedDose,
    DoseCalculationResponse,
    DoseVolume,
    DosingGuideline,
    DosingGuidelinesResponse,
)

router = APIRouter(prefix="/api/v1/dosing", tags=["dosing"])


def _parse_concentration(strength: str) -> Optional[float]:
    """
    Extract mg-per-ml concentration from a strength string.

    Examples:
        '400mg/5ml'  → 80.0
        '250mg/5ml'  → 50.0
        '100mg/5ml'  → 20.0
        '15mg/1ml'   → 15.0
        '200mg'      → None  (tablet — no volume calc)
        '500mg'      → None
    """
    match = re.match(
        r"(\d+(?:\.\d+)?)\s*mg\s*/\s*(\d+(?:\.\d+)?)\s*ml",
        strength.strip(),
        re.IGNORECASE,
    )
    if match:
        mg = float(match.group(1))
        ml = float(match.group(2))
        return mg / ml if ml > 0 else None
    return None


@router.get("/calculate", response_model=DoseCalculationResponse)
async def calculate_dose(
    drug_id: str = Query(..., description="Drug UUID"),
    weight_kg: float = Query(..., gt=0, le=150, description="Patient weight in kg"),
    age_months: int = Query(..., ge=0, le=216, description="Patient age in months"),
    indication: Optional[str] = Query(default=None, description="Filter by indication"),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    Compute per-dose amounts for a specific patient.

    1. Finds matching dosing guidelines (filtered by age eligibility)
    2. Computes per_dose_mg = (daily_mg_per_kg × weight) / doses_per_day
    3. Applies max_single_dose_mg ceiling
    4. Looks up available SKUs and computes volume_ml for liquid forms

    Example:
        GET /api/v1/dosing/calculate?drug_id=abc-123&weight_kg=10&age_months=14
        → Amoxicillin AOM: 45mg/kg/dose × 10kg = 450mg → 400mg/5ml = 5.6ml BID × 10 days
    """
    # Fetch matching guidelines
    indication_filter = "AND dg.indication ILIKE $4" if indication else ""
    params = [drug_id, age_months, age_months]
    if indication:
        params.append(f"%{indication}%")

    rows = await db.fetch(
        f"""
        SELECT
            dg.id AS guideline_id,
            dg.drug_id,
            d.inn_name AS drug_name,
            dg.indication,
            dg.route::text,
            dg.frequency::text,
            dg.doses_per_day,
            dg.dose_mg_per_kg_day,
            dg.dose_fixed_mg,
            dg.max_single_dose_mg,
            dg.max_daily_dose_mg,
            dg.duration_days,
            dg.day_pattern,
            dg.preferred_form,
            dg.notes,
            ds.name AS source_name
        FROM dosing_guideline dg
        JOIN drug d ON d.id = dg.drug_id
        JOIN dosing_source ds ON ds.id = dg.source_id
        WHERE dg.drug_id = $1
          AND dg.is_active = true
          AND (dg.age_min_months IS NULL OR dg.age_min_months <= $2)
          AND (dg.age_max_months IS NULL OR dg.age_max_months >= $3)
          {indication_filter}
        ORDER BY dg.indication, dg.id
        """,
        *params,
    )

    if not rows:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No dosing guidelines found for this drug/age combination.",
        )

    drug_name = rows[0]["drug_name"]

    # Fetch available SKUs for volume calculation
    skus = await db.fetch(
        """
        SELECT id, dosage_form::text, strength
        FROM drug_sku
        WHERE drug_id = $1
        ORDER BY dosage_form, strength
        """,
        drug_id,
    )

    # Build calculated doses
    calculated = []
    for r in rows:
        # Compute per-dose mg
        capped = False
        if r["dose_mg_per_kg_day"] is not None:
            daily_mg = float(r["dose_mg_per_kg_day"]) * weight_kg
            per_dose_mg = daily_mg / r["doses_per_day"]
        elif r["dose_fixed_mg"] is not None:
            daily_mg = float(r["dose_fixed_mg"])
            per_dose_mg = daily_mg / r["doses_per_day"]
        else:
            continue

        # Apply ceiling
        if r["max_single_dose_mg"] and per_dose_mg > float(r["max_single_dose_mg"]):
            per_dose_mg = float(r["max_single_dose_mg"])
            capped = True

        actual_daily = per_dose_mg * r["doses_per_day"]
        if r["max_daily_dose_mg"] and actual_daily > float(r["max_daily_dose_mg"]):
            per_dose_mg = float(r["max_daily_dose_mg"]) / r["doses_per_day"]
            actual_daily = float(r["max_daily_dose_mg"])
            capped = True

        # Compute volume per SKU
        volumes = []
        for sku in skus:
            conc = _parse_concentration(sku["strength"] or "")
            if conc and conc > 0:
                vol_ml = round(per_dose_mg / conc, 1)
                volumes.append(DoseVolume(
                    sku_id=str(sku["id"]),
                    dosage_form=sku["dosage_form"],
                    strength=sku["strength"],
                    concentration_mg_per_ml=round(conc, 2),
                    volume_ml=vol_ml,
                    volume_label=f"{vol_ml} ml",
                ))
            else:
                # Tablet / capsule — show mg, not ml
                volumes.append(DoseVolume(
                    sku_id=str(sku["id"]),
                    dosage_form=sku["dosage_form"],
                    strength=sku["strength"],
                    concentration_mg_per_ml=None,
                    volume_ml=None,
                    volume_label=f"{round(per_dose_mg, 1)} mg",
                ))

        calculated.append(CalculatedDose(
            guideline_id=r["guideline_id"],
            indication=r["indication"],
            route=r["route"],
            frequency=r["frequency"],
            doses_per_day=r["doses_per_day"],
            duration_days=r["duration_days"],
            per_dose_mg=round(per_dose_mg, 1),
            daily_dose_mg=round(actual_daily, 1),
            volumes=volumes,
            max_single_dose_mg=float(r["max_single_dose_mg"]) if r["max_single_dose_mg"] else None,
            max_daily_dose_mg=float(r["max_daily_dose_mg"]) if r["max_daily_dose_mg"] else None,
            capped=capped,
            notes=r["notes"],
            source_name=r["source_name"],
            day_pattern=r["day_pattern"],
        ))

    return DoseCalculationResponse(
        drug_id=drug_id,
        drug_name=drug_name,
        patient_weight_kg=weight_kg,
        patient_age_months=age_months,
        calculated_doses=calculated,
    )


@router.get("/{drug_id}", response_model=DosingGuidelinesResponse)
async def get_dosing_guidelines(
    drug_id: str,
    pediatric_only: bool = Query(default=False, description="Filter to pediatric guidelines only"),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    All dosing guidelines for a drug — all indications, age bands, sources.

    Example:
        GET /api/v1/dosing/{drug_id}
        → Paracetamol: Fever (10mg/kg QID), Pain (15mg/kg QID)
    """
    pediatric_filter = "AND dg.is_pediatric = true" if pediatric_only else ""

    rows = await db.fetch(
        f"""
        SELECT
            dg.id AS guideline_id,
            dg.drug_id::text,
            d.inn_name AS drug_name,
            dg.indication,
            dg.route::text,
            dg.age_min_months,
            dg.age_max_months,
            dg.frequency::text,
            dg.doses_per_day,
            dg.duration_days,
            dg.preferred_form,
            dg.notes,
            ds.name AS source_name,
            ds.edition AS source_edition,
            CASE
                WHEN dg.dose_mg_per_kg_day IS NOT NULL
                THEN ROUND(dg.dose_mg_per_kg_day / dg.doses_per_day, 2)
                ELSE NULL
            END AS per_dose_mg_per_kg,
            CASE
                WHEN dg.dose_fixed_mg IS NOT NULL
                THEN ROUND(dg.dose_fixed_mg / dg.doses_per_day, 2)
                ELSE NULL
            END AS per_dose_fixed_mg,
            dg.max_single_dose_mg,
            dg.max_daily_dose_mg,
            dg.day_pattern
        FROM dosing_guideline dg
        JOIN drug d ON d.id = dg.drug_id
        JOIN dosing_source ds ON ds.id = dg.source_id
        WHERE dg.drug_id = $1
          AND dg.is_active = true
          {pediatric_filter}
        ORDER BY dg.indication, dg.age_min_months
        """,
        drug_id,
    )

    if not rows:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No dosing guidelines found for this drug.",
        )

    drug_name = rows[0]["drug_name"]

    guidelines = [
        DosingGuideline(
            guideline_id=r["guideline_id"],
            drug_id=r["drug_id"],
            drug_name=r["drug_name"],
            indication=r["indication"],
            route=r["route"],
            age_min_months=r["age_min_months"],
            age_max_months=r["age_max_months"],
            frequency=r["frequency"],
            doses_per_day=r["doses_per_day"],
            duration_days=r["duration_days"],
            preferred_form=r["preferred_form"],
            notes=r["notes"],
            source_name=r["source_name"],
            source_edition=r["source_edition"],
            per_dose_mg_per_kg=float(r["per_dose_mg_per_kg"]) if r["per_dose_mg_per_kg"] else None,
            per_dose_fixed_mg=float(r["per_dose_fixed_mg"]) if r["per_dose_fixed_mg"] else None,
            max_single_dose_mg=float(r["max_single_dose_mg"]) if r["max_single_dose_mg"] else None,
            max_daily_dose_mg=float(r["max_daily_dose_mg"]) if r["max_daily_dose_mg"] else None,
            day_pattern=r["day_pattern"],
        )
        for r in rows
    ]

    return DosingGuidelinesResponse(
        drug_id=drug_id,
        drug_name=drug_name,
        total=len(guidelines),
        guidelines=guidelines,
    )
