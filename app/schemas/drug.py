from typing import Optional
from pydantic import BaseModel


class DrugSearchResult(BaseModel):
    id: str
    inn_name: str
    aware_category: str
    therapeutic_category: Optional[str] = None
    pharmacological_class: Optional[str] = None
    is_community_pharmacy_approved: bool
    controlled_substance: bool
    prescription_required: bool
    who_not_recommended: bool
    dosage_forms: list[str] = []
    similarity_score: float = 0.0


class DrugSearchResponse(BaseModel):
    query: str
    total: int
    results: list[DrugSearchResult]


class ClinicalReference(BaseModel):
    id: str
    drug_id: str
    inn_name: str
    indications: Optional[str] = None
    dose_and_administration: Optional[str] = None
    contraindications: Optional[str] = None
    drug_interactions_text: Optional[str] = None
    side_effects: Optional[str] = None
    cautions: Optional[str] = None
    storage_condition: Optional[str] = None
    source: str


class DrugDetail(BaseModel):
    id: str
    inn_name: str
    amharic_name: Optional[str] = None
    aware_category: str
    atc_code: Optional[str] = None
    therapeutic_category: Optional[str] = None
    pharmacological_class: Optional[str] = None
    is_on_eeml: bool
    prescription_required: bool
    controlled_substance: bool
    is_community_pharmacy_approved: bool
    who_not_recommended: bool
    dosage_forms: list[str] = []
    clinical_reference: Optional[ClinicalReference] = None
    interactions: list[str] = []   # partner drug names
