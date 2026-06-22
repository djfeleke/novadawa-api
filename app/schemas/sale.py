"""Pydantic models for the sale checkout flow."""

from typing import Literal, Optional

from pydantic import BaseModel, Field, model_validator


# ---------- Narcotics (controlled substance compliance) ----------

# Fields the pharmacist supplies from the prescription / patient. Any of these
# may be missing in the real world (e.g. prescriber licence not retrievable);
# when that happens an override_reason must be given so the gap is a documented
# professional decision rather than a silent omission.
_OVERRIDABLE_FIELDS = (
    "patient_full_name",
    "patient_age",
    "patient_sex",
    "patient_address",
    "patient_id_type",
    "patient_id_number",
    "prescribing_doctor_name",
    "prescribing_doctor_license",
    "prescription_serial",
    "prescription_image_url",
)


class NarcoticsInfo(BaseModel):
    """
    Controlled-substance dispense record (EFDA registers NPS/09/A & NPS/09/B).

    All human-supplied fields are required by default. If any is genuinely
    unavailable, the pharmacist may omit it ONLY by supplying override_reason
    — one reason covers the whole dispense (controlled scripts are single-drug,
    colour-coded). System-derived data (drug, quantity, dispenser, balance) is
    never part of this payload and can never be overridden.
    """
    # Patient (official register columns: Name, Age, Sex, Address)
    patient_full_name: Optional[str] = None
    patient_age: Optional[int] = Field(default=None, ge=0, le=150)
    patient_sex: Optional[Literal["M", "F"]] = None
    patient_address: Optional[str] = None
    patient_id_type: Optional[
        Literal["kebele_id", "passport", "drivers_license", "other"]
    ] = None
    patient_id_number: Optional[str] = None

    # Prescriber + prescription
    prescribing_doctor_name: Optional[str] = None
    prescribing_doctor_license: Optional[str] = None
    prescription_serial: Optional[str] = None
    prescription_image_url: Optional[str] = None

    # Override: when present, missing human-supplied fields above are permitted
    # and the dispense is recorded as a documented exception.
    override_reason: Optional[str] = None

    @model_validator(mode="after")
    def _require_unless_overridden(self) -> "NarcoticsInfo":
        override = (self.override_reason or "").strip()
        if override:
            # Documented exception: missing human fields are allowed.
            # Normalise the stored reason to the trimmed value.
            self.override_reason = override
            return self
        # No override -> every human-supplied field must be present & non-empty.
        missing = []
        for f in _OVERRIDABLE_FIELDS:
            v = getattr(self, f)
            if v is None or (isinstance(v, str) and not v.strip()):
                missing.append(f)
        if missing:
            raise ValueError(
                "Controlled-substance dispense is missing required field(s): "
                + ", ".join(missing)
                + ". Supply them, or set override_reason to dispense with an "
                "audited exception."
            )
        return self


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
    narcotics_overrides: int = 0
