"""Pydantic models for inventory receive, dispense, and stock queries."""

from datetime import date
from typing import Optional

from pydantic import BaseModel, Field


# ---------- Receive (purchase) ----------

class ReceiveRequest(BaseModel):
    """Record a new batch arriving at a branch."""
    product_id: str
    batch_number: str
    expiry_date: date
    quantity_base_units: int = Field(..., gt=0)
    cost_per_base_unit_santim: int = Field(..., gt=0)
    exchange_rate_at_purchase: float = Field(..., gt=0)
    selling_price_per_sale_unit_santim: int = Field(..., gt=0)
    supplier_id: Optional[str] = None
    purchase_order_ref: Optional[str] = None
    received_by_user_id: str          # TODO: resolve from Firebase auth
    notes: Optional[str] = None


class ReceiveResponse(BaseModel):
    inventory_id: str
    movement_id: str
    branch_id: str
    product_id: str
    batch_number: str
    expiry_date: str
    quantity_base_units: int
    received_at: str


# ---------- Dispense (sale) ----------

class DispenseRequest(BaseModel):
    """Dispense stock using FEFO. Hard-rejects if insufficient."""
    product_id: str
    quantity_base_units: int = Field(..., gt=0)
    performed_by_user_id: str         # TODO: resolve from Firebase auth
    sale_id: Optional[str] = None     # links movement to a sale record
    notes: Optional[str] = None


class DispenseLotDetail(BaseModel):
    """One inventory lot touched by a dispense."""
    inventory_id: str
    batch_number: str
    expiry_date: str
    quantity_taken: int
    quantity_remaining: int


class DispenseResponse(BaseModel):
    product_id: str
    quantity_dispensed: int
    lots: list[DispenseLotDetail]


# ---------- Stock query ----------

class StockLot(BaseModel):
    inventory_id: str
    batch_number: str
    expiry_date: str
    quantity_base_units: int
    is_expired: bool
    selling_price_per_sale_unit_santim: int


class StockResponse(BaseModel):
    branch_id: str
    product_id: str
    total_available: int              # non-expired, active only
    lots: list[StockLot]
