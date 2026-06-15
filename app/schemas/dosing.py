from typing import Optional
from pydantic import BaseModel


class DosingGuideline(BaseModel):
    """Single dosing rule for a drug + indication + age band."""
    guideline_id: int
    drug_id: str
    drug_name: str
    indication: str
    route: str
    age_min_months: Optional[int] = None
    age_max_months: Optional[int] = None
    frequency: str
    doses_per_day: int
    duration_days: Optional[int] = None
    preferred_form: Optional[str] = None
    notes: Optional[str] = None
    source_name: str
    source_edition: Optional[str] = None
    # Per-dose amounts (one will be set depending on weight-based vs fixed)
    per_dose_mg_per_kg: Optional[float] = None
    per_dose_fixed_mg: Optional[float] = None
    max_single_dose_mg: Optional[float] = None
    max_daily_dose_mg: Optional[float] = None
    day_pattern: Optional[list] = None


class DosingGuidelinesResponse(BaseModel):
    """All dosing guidelines for a given drug."""
    drug_id: str
    drug_name: str
    total: int
    guidelines: list[DosingGuideline]


class CalculatedDose(BaseModel):
    """A single computed dose for a specific patient weight + age."""
    guideline_id: int
    indication: str
    route: str
    frequency: str
    doses_per_day: int
    duration_days: Optional[int] = None
    # Computed amounts — null for non-weight-based doses (inhaled puffs,
    # topical application, etc.) where instructions live in `notes`.
    per_dose_mg: Optional[float] = None
    daily_dose_mg: Optional[float] = None
    is_calculable: bool = True   # False when dose is by puffs/application/drops
    # Volume per available formulation
    volumes: list["DoseVolume"] = []
    # Safety
    max_single_dose_mg: Optional[float] = None
    max_daily_dose_mg: Optional[float] = None
    capped: bool = False       # True if dose was capped at max
    notes: Optional[str] = None
    source_name: str
    day_pattern: Optional[list] = None


class DoseVolume(BaseModel):
    """Calculated volume for a specific SKU formulation."""
    sku_id: str
    dosage_form: str
    strength: str
    concentration_mg_per_ml: Optional[float] = None
    volume_ml: Optional[float] = None
    volume_label: str          # e.g. "5.6 ml" or "1 tablet"


class DoseCalculationResponse(BaseModel):
    """Full dose calculation result for a patient."""
    drug_id: str
    drug_name: str
    patient_weight_kg: float
    patient_age_months: int
    calculated_doses: list[CalculatedDose]
