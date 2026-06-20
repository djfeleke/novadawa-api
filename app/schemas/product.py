"""Pydantic models for product management."""

from typing import Optional

from pydantic import BaseModel, Field


# ---------- Create ----------

class ProductCreate(BaseModel):
    drug_sku_id: str
    pharmacy_group_id: str
    pack_size: int = Field(..., gt=0)
    sale_unit: str                          # e.g. "tablet", "bottle", "vial"
    sale_unit_size: int = Field(1, gt=0)    # base units per sale unit
    brand_name: Optional[str] = None
    primary_barcode: Optional[str] = None
    secondary_barcodes: Optional[list[str]] = None
    image_url: Optional[str] = None
    country_of_origin: Optional[str] = Field(None, max_length=2)
    supplier_id: Optional[str] = None


# ---------- Update (PATCH) ----------

class ProductUpdate(BaseModel):
    brand_name: Optional[str] = None
    pack_size: Optional[int] = Field(None, gt=0)
    sale_unit: Optional[str] = None
    sale_unit_size: Optional[int] = Field(None, gt=0)
    primary_barcode: Optional[str] = None
    secondary_barcodes: Optional[list[str]] = None
    image_url: Optional[str] = None
    country_of_origin: Optional[str] = Field(None, max_length=2)
    supplier_id: Optional[str] = None


# ---------- Response ----------

class ProductResponse(BaseModel):
    id: str
    drug_sku_id: str
    pharmacy_group_id: Optional[str]
    brand_name: Optional[str]
    pack_size: int
    sale_unit: str
    sale_unit_size: int
    primary_barcode: Optional[str]
    secondary_barcodes: Optional[list[str]]
    image_url: Optional[str]
    country_of_origin: Optional[str]
    supplier_id: Optional[str]
    created_at: str
    # Joined catalog fields
    inn_name: Optional[str] = None
    dosage_form: Optional[str] = None
    strength: Optional[str] = None


# ---------- Barcode lookup ----------

class BarcodeLookupResponse(BaseModel):
    product: ProductResponse
    branch_stock: Optional[int] = None   # if branch_id provided
