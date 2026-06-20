"""Pydantic models for supplier management."""

from typing import Literal, Optional

from pydantic import BaseModel, Field

SupplierType = Literal["importer", "local_manufacturer", "distributor", "pharmacy_wholesaler"]


class SupplierCreate(BaseModel):
    pharmacy_group_id: str
    name: str
    supplier_type: SupplierType
    contact_person: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    tin_number: Optional[str] = None
    payment_terms_days: int = 30
    currency: str = Field("ETB", max_length=3)


class SupplierUpdate(BaseModel):
    name: Optional[str] = None
    supplier_type: Optional[SupplierType] = None
    contact_person: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    tin_number: Optional[str] = None
    payment_terms_days: Optional[int] = None
    currency: Optional[str] = Field(None, max_length=3)
    is_active: Optional[bool] = None


class SupplierResponse(BaseModel):
    id: str
    pharmacy_group_id: str
    name: str
    supplier_type: str
    contact_person: Optional[str]
    phone: Optional[str]
    email: Optional[str]
    tin_number: Optional[str]
    payment_terms_days: Optional[int]
    currency: str
    is_active: bool
    created_at: str
