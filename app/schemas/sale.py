"""Pydantic models for the sale checkout flow."""

from typing import Literal, Optional

from pydantic import BaseModel, Field


# ---------- Narcotics (controlled substance compliance) ----------

class NarcoticsInfo(BaseModel):
    """Required when dispensing a controlled substance."""
    patient_full_name: str
    patient_id_type: Literal["kebele_id", "passport", "drivers_license", "other"]
    patient_id_number: str
    prescribing_doctor_name: str
    prescribing_doctor_license: str
    prescription_serial: str
    prescription_image_url: str


# ---------- Checkout request ----------

class CheckoutLineInput(BaseModel):
    """One item the customer is buying."""
    product_id: str
    quantity_sale_units: int = Field(..., gt=0)
    is_vat_applicable: bool = True
    narcotics: Optional[NarcoticsInfo] = None


class CheckoutRequest(BaseModel):
    """
    Complete a pharmacy sale atomically.

    Creates sale + sale_lines + inventory movements + narcotics register
    entries (for controlled substances) in a single transaction.
    """
    cashier_user_id: str
    dispensed_by_user_id: Optional[str] = None   # pharmacist; falls back to cashier
    customer_name: Optional[str] = None
    customer_phone: Optional[str] = None
    prescription_ref: Optional[str] = None
    prescription_image_url: Optional[str] = None
    payment_method: Literal["cash", "telebirr", "cbe_birr", "credit"]
    payment_reference: Optional[str] = None
    discount_santim: int = 0
    lines: list[CheckoutLineInput] = Field(..., min_length=1)


# ---------- Checkout response ----------

class SaleLineResponse(BaseModel):
    sale_line_id: str
    product_id: str
    inventory_id: str
    batch_number: str
    quantity_sale_units: int
    quantity_base_units: int
    unit_price_santim: int
    line_subtotal_santim: int
    vat_amount_santim: int
    line_total_santim: int


class CheckoutResponse(BaseModel):
    sale_id: str
    sale_number: str
    branch_id: str
    subtotal_santim: int
    vat_total_santim: int
    discount_santim: int
    total_santim: int
    payment_method: str
    sale_status: str
    lines: list[SaleLineResponse]
    narcotics_entries: int
