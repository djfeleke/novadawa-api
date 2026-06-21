"""Pydantic models for expiry & low-stock alerts (read-only)."""
from typing import Optional
from pydantic import BaseModel


# ---------- Expiry ----------
class ExpiryAlertLot(BaseModel):
    inventory_id: str
    product_id: str
    inn_name: Optional[str] = None
    brand_name: Optional[str] = None
    batch_number: str
    expiry_date: str
    days_to_expiry: int          # negative if already expired
    quantity_base_units: int
    is_expired: bool


class ExpiryAlertResponse(BaseModel):
    branch_id: str
    within_days: int
    include_expired: bool
    as_of_date: str              # local (Addis) date used for the calc
    count: int
    lots: list[ExpiryAlertLot]


# ---------- Low stock ----------
class LowStockItem(BaseModel):
    product_id: str
    inn_name: Optional[str] = None
    brand_name: Optional[str] = None
    total_available: int         # non-expired, active, qty>0
    reorder_level: int           # the product's configured level
    threshold: int               # effective value compared against (param or reorder_level)


class LowStockResponse(BaseModel):
    branch_id: str
    mode: str                    # 'param' (explicit threshold) | 'per_product'
    threshold: Optional[int]     # the param value, or null in per_product mode
    as_of_date: str
    count: int
    items: list[LowStockItem]
