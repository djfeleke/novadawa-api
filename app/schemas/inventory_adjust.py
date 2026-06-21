"""Pydantic models for inventory adjustments (wastage/expired/adjustment) and transfers."""
from typing import Literal
from pydantic import BaseModel, Field


# ---------- Adjust (wastage / expired / manual correction) ----------
class LotAdjustRequest(BaseModel):
    movement_type: Literal["wastage", "expired", "adjustment"]
    quantity_change_base_units: int = Field(
        ...,
        description="Signed delta. Negative removes stock. "
                    "wastage/expired must be negative; adjustment may be + or -.",
    )
    reason: str = Field(..., min_length=1)
    performed_by_user_id: str


class LotAdjustResponse(BaseModel):
    inventory_id: str
    branch_id: str
    product_id: str
    movement_type: str
    quantity_change_base_units: int
    quantity_after_base_units: int
    reason: str
    performed_by_user_id: str
    movement_id: str


# ---------- Transfer (branch -> branch) ----------
class LotTransferRequest(BaseModel):
    to_branch_id: str
    quantity_base_units: int = Field(..., gt=0)
    reason: str = Field(..., min_length=1)
    performed_by_user_id: str


class LotTransferResponse(BaseModel):
    transfer_id: str               # shared reference_id linking both movement legs
    product_id: str
    quantity_base_units: int
    source_inventory_id: str
    source_branch_id: str
    source_quantity_after: int
    dest_inventory_id: str
    dest_branch_id: str
    dest_quantity: int
    reason: str
    performed_by_user_id: str
