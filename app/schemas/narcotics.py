"""Pydantic models for the narcotics register report (read-only, EFDA audit)."""
from typing import Optional
from pydantic import BaseModel


class NarcoticsRegisterEntry(BaseModel):
    id: str
    dispensed_at: str                 # local Addis time, 'YYYY-MM-DD HH:MM'
    sale_line_id: str
    sale_id: str
    sale_number: Optional[str]
    drug_sku_id: str
    inn_name: Optional[str]
    narcotic_class: Optional[str]
    strength: Optional[str]
    dosage_form: Optional[str]         # unit of measure for qty/balance
    dispensed_quantity_base_units: int
    running_balance_base_units: int
    # Patient (official register: Name, Age, Sex, Address). Any may be null
    # when the dispense was recorded under an override.
    patient_full_name: Optional[str]
    patient_age: Optional[int]
    patient_sex: Optional[str]
    patient_address: Optional[str]
    patient_id_type: Optional[str]
    patient_id_number: Optional[str]
    prescribing_doctor_name: Optional[str]
    prescribing_doctor_license: Optional[str]
    prescription_serial: Optional[str]
    prescription_image_url: Optional[str]
    # Override audit (set when a required field was omitted with a logged reason)
    override_reason: Optional[str]
    overridden_by_user_id: Optional[str]
    dispensed_by_user_id: str
    dispensed_by_name: Optional[str]
    dispensed_by_license: Optional[str]


class NarcoticsRegisterResponse(BaseModel):
    branch_id: str
    from_date: Optional[str]
    to_date: Optional[str]
    total_count: int                  # matches the filter (ignores pagination)
    total_dispensed_base_units: int   # SUM over the filtered set
    limit: int
    offset: int
    entries: list[NarcoticsRegisterEntry]
