from typing import Optional
from pydantic import BaseModel, EmailStr


# ---------- Pharmacy Group ----------

class PharmacyGroupCreate(BaseModel):
    name: str
    tin_number: Optional[str] = None
    efda_license_number: Optional[str] = None
    efda_license_expiry: Optional[str] = None   # ISO date string
    billing_email: str
    country_code: str = "ET"


class PharmacyGroupResponse(BaseModel):
    id: str
    name: str
    tin_number: Optional[str] = None
    efda_license_number: Optional[str] = None
    efda_license_expiry: Optional[str] = None
    subscription_tier: str
    subscription_status: str
    billing_email: str
    country_code: str
    created_at: str


# ---------- Branch ----------

class BranchCreate(BaseModel):
    pharmacy_group_id: str
    name: str
    woreda: str
    subcity: Optional[str] = None
    city: str = "Addis Ababa"
    phone: Optional[str] = None
    efda_branch_license: Optional[str] = None


class BranchResponse(BaseModel):
    id: str
    pharmacy_group_id: str
    name: str
    woreda: str
    subcity: Optional[str] = None
    city: str
    phone: Optional[str] = None
    efda_branch_license: Optional[str] = None
    is_active: bool
    created_at: str


# ---------- App User ----------

class UserCreate(BaseModel):
    pharmacy_group_id: str
    email: str
    full_name: str
    phone: Optional[str] = None
    firebase_uid: Optional[str] = None
    efda_license_number: Optional[str] = None


class UserResponse(BaseModel):
    id: str
    pharmacy_group_id: str
    firebase_uid: Optional[str] = None
    email: str
    full_name: str
    phone: Optional[str] = None
    efda_license_number: Optional[str] = None
    is_active: bool
    created_at: str


# ---------- Role Assignment ----------

class RoleAssign(BaseModel):
    user_id: str
    branch_id: Optional[str] = None    # NULL = group-wide
    role: str                           # group_admin, branch_manager, pharmacist, cashier, etc.


class RoleResponse(BaseModel):
    id: str
    user_id: str
    branch_id: Optional[str] = None
    role: str
    granted_by_user_id: str
    granted_at: str


# ---------- Onboarding (all-in-one) ----------

class OnboardingRequest(BaseModel):
    """Single request to create pharmacy group + first branch + admin user."""
    # Pharmacy group
    pharmacy_name: str
    tin_number: Optional[str] = None
    efda_license_number: Optional[str] = None
    billing_email: str
    # First branch
    branch_name: str
    woreda: str
    subcity: Optional[str] = None
    city: str = "Addis Ababa"
    branch_phone: Optional[str] = None
    # Admin user
    admin_full_name: str
    admin_email: str
    admin_phone: Optional[str] = None
    admin_firebase_uid: Optional[str] = None


class OnboardingResponse(BaseModel):
    pharmacy_group: PharmacyGroupResponse
    branch: BranchResponse
    admin_user: UserResponse
    role: RoleResponse
