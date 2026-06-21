"""Pydantic models for the drug interaction checker."""
from typing import Optional
from pydantic import BaseModel, Field


# ---------- Request ----------
class InteractionCheckRequest(BaseModel):
    product_ids: list[str] = Field(
        ..., min_length=1, description="Basket of product IDs to screen."
    )


# ---------- Response ----------
class InteractionFlag(BaseModel):
    severity: str                 # minor | moderate | major | contraindicated
    drug_a_id: str
    drug_a_name: str
    drug_b_id: str
    drug_b_name: str
    source: str
    products_a: list[str]         # basket product_ids mapping to drug_a
    products_b: list[str]         # basket product_ids mapping to drug_b


class InteractionCheckResponse(BaseModel):
    interaction_count: int
    highest_severity: Optional[str] = None     # null when no interactions
    flags: list[InteractionFlag]
    checked_product_ids: list[str]             # products that resolved to a drug
    unresolved_product_ids: list[str]          # NOT found — basket not fully screened
