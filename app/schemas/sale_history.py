"""Pydantic models for sale history & detail (read-only reporting)."""
from typing import Optional
from pydantic import BaseModel


# ---------- List / summary ----------
class SaleSummary(BaseModel):
    id: str
    sale_number: str
    branch_id: str
    cashier_user_id: str
    dispensed_by_user_id: Optional[str]
    customer_name: Optional[str]
    customer_phone: Optional[str]
    subtotal_santim: int
    vat_total_santim: int
    discount_santim: int
    total_santim: int
    payment_method: str
    payment_reference: Optional[str]
    sale_status: str
    created_at: str


class SaleHistoryResponse(BaseModel):
    branch_id: str
    total_count: int            # total matching the filter (ignores pagination)
    total_santim_sum: int       # SUM(total_santim) across the filtered set
    limit: int
    offset: int
    sales: list[SaleSummary]


# ---------- Detail ----------
class SaleLineDetail(BaseModel):
    sale_line_id: str
    product_id: str
    inventory_id: str
    batch_number: Optional[str] = None
    inn_name: Optional[str] = None
    brand_name: Optional[str] = None
    quantity_sale_units: int
    quantity_base_units: int
    unit_price_santim: int
    line_subtotal_santim: int
    vat_amount_santim: int
    line_total_santim: int


class SaleDetailResponse(BaseModel):
    id: str
    sale_number: str
    branch_id: str
    cashier_user_id: str
    dispensed_by_user_id: Optional[str]
    customer_name: Optional[str]
    customer_phone: Optional[str]
    prescription_ref: Optional[str]
    prescription_image_url: Optional[str]
    subtotal_santim: int
    vat_total_santim: int
    discount_santim: int
    total_santim: int
    payment_method: str
    payment_reference: Optional[str]
    sale_status: str
    void_reason: Optional[str]
    voided_by_user_id: Optional[str]
    created_at: str
    lines: list[SaleLineDetail]
