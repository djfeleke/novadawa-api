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
    dispensed_quantity_base_units: int
    running_balance_base_units: int
    patient_full_name: str
    patient_id_type: str
    patient_id_number: str
    prescribing_doctor_name: str
    prescribing_doctor_license: str
    prescription_serial: str
    prescription_image_url: str
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
