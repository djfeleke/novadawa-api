"""
Tenant management endpoints — pharmacy group, branch, user, and role CRUD.

  POST /api/v1/tenants/onboard
      All-in-one onboarding: creates pharmacy group + first branch + admin
      user + group_admin role in a single transaction.

  POST /api/v1/tenants/pharmacy-groups
  GET  /api/v1/tenants/pharmacy-groups/{group_id}

  POST /api/v1/tenants/branches
  GET  /api/v1/tenants/branches?pharmacy_group_id=...

  POST /api/v1/tenants/users
  GET  /api/v1/tenants/users?pharmacy_group_id=...

  POST /api/v1/tenants/roles
  GET  /api/v1/tenants/roles?user_id=...
"""
import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.auth.firebase import get_current_user
from app.database import get_db
from app.schemas.tenant import (
    BranchCreate,
    BranchResponse,
    OnboardingRequest,
    OnboardingResponse,
    PharmacyGroupCreate,
    PharmacyGroupResponse,
    RoleAssign,
    RoleResponse,
    UserCreate,
    UserResponse,
)

router = APIRouter(prefix="/api/v1/tenants", tags=["tenants"])


# ── Onboarding (all-in-one) ─────────────────────────────────────────

@router.post("/onboard", response_model=OnboardingResponse, status_code=status.HTTP_201_CREATED)
async def onboard_pharmacy(
    req: OnboardingRequest,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    One-shot pharmacy onboarding. Creates everything in a single transaction:
    1. Pharmacy group (the tenant)
    2. First branch
    3. Admin user
    4. group_admin role assignment

    If any step fails, the entire operation rolls back.
    """
    async with db.transaction():
        # 1. Create pharmacy group
        group = await db.fetchrow(
            """
            INSERT INTO pharmacy_group (name, tin_number, efda_license_number, billing_email, country_code)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
            """,
            req.pharmacy_name, req.tin_number, req.efda_license_number,
            req.billing_email, "ET",
        )

        # 2. Create first branch
        branch = await db.fetchrow(
            """
            INSERT INTO branch (pharmacy_group_id, name, woreda, subcity, city, phone)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING *
            """,
            group["id"], req.branch_name, req.woreda, req.subcity, req.city, req.branch_phone,
        )

        # 3. Create admin user
        user = await db.fetchrow(
            """
            INSERT INTO app_user (pharmacy_group_id, firebase_uid, email, full_name, phone)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
            """,
            group["id"], req.admin_firebase_uid, req.admin_email,
            req.admin_full_name, req.admin_phone,
        )

        # 4. Assign group_admin role (self-granted for bootstrap)
        role = await db.fetchrow(
            """
            INSERT INTO user_branch_role (user_id, branch_id, role, granted_by_user_id)
            VALUES ($1, NULL, 'group_admin', $1)
            RETURNING *
            """,
            user["id"],
        )

    return OnboardingResponse(
        pharmacy_group=_group_response(group),
        branch=_branch_response(branch),
        admin_user=_user_response(user),
        role=_role_response(role),
    )


# ── Pharmacy Groups ──────────────────────────────────────────────────

@router.post("/pharmacy-groups", response_model=PharmacyGroupResponse, status_code=status.HTTP_201_CREATED)
async def create_pharmacy_group(
    req: PharmacyGroupCreate,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Create a new pharmacy group (tenant)."""
    row = await db.fetchrow(
        """
        INSERT INTO pharmacy_group
            (name, tin_number, efda_license_number, efda_license_expiry, billing_email, country_code)
        VALUES ($1, $2, $3, $4::date, $5, $6)
        RETURNING *
        """,
        req.name, req.tin_number, req.efda_license_number,
        req.efda_license_expiry, req.billing_email, req.country_code,
    )
    return _group_response(row)


@router.get("/pharmacy-groups/{group_id}", response_model=PharmacyGroupResponse)
async def get_pharmacy_group(
    group_id: str,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Get pharmacy group details."""
    row = await db.fetchrow("SELECT * FROM pharmacy_group WHERE id = $1", group_id)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pharmacy group not found.")
    return _group_response(row)


# ── Branches ─────────────────────────────────────────────────────────

@router.post("/branches", response_model=BranchResponse, status_code=status.HTTP_201_CREATED)
async def create_branch(
    req: BranchCreate,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Add a new branch to an existing pharmacy group."""
    # Verify group exists
    group = await db.fetchval("SELECT id FROM pharmacy_group WHERE id = $1", req.pharmacy_group_id)
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pharmacy group not found.")

    row = await db.fetchrow(
        """
        INSERT INTO branch (pharmacy_group_id, name, woreda, subcity, city, phone, efda_branch_license)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING *
        """,
        req.pharmacy_group_id, req.name, req.woreda, req.subcity,
        req.city, req.phone, req.efda_branch_license,
    )
    return _branch_response(row)


@router.get("/branches", response_model=list[BranchResponse])
async def list_branches(
    pharmacy_group_id: str = Query(..., description="Filter branches by pharmacy group"),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """List all branches for a pharmacy group."""
    rows = await db.fetch(
        "SELECT * FROM branch WHERE pharmacy_group_id = $1 ORDER BY name",
        pharmacy_group_id,
    )
    return [_branch_response(r) for r in rows]


# ── Users ────────────────────────────────────────────────────────────

@router.post("/users", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    req: UserCreate,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """Create a new staff user within a pharmacy group."""
    # Verify group exists
    group = await db.fetchval("SELECT id FROM pharmacy_group WHERE id = $1", req.pharmacy_group_id)
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pharmacy group not found.")

    try:
        row = await db.fetchrow(
            """
            INSERT INTO app_user (pharmacy_group_id, firebase_uid, email, full_name, phone, efda_license_number)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING *
            """,
            req.pharmacy_group_id, req.firebase_uid, req.email,
            req.full_name, req.phone, req.efda_license_number,
        )
    except asyncpg.UniqueViolationError as e:
        field = "email" if "email" in str(e) else "firebase_uid"
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"A user with that {field} already exists.",
        )
    return _user_response(row)


@router.get("/users", response_model=list[UserResponse])
async def list_users(
    pharmacy_group_id: str = Query(..., description="Filter users by pharmacy group"),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """List all staff users for a pharmacy group."""
    rows = await db.fetch(
        "SELECT * FROM app_user WHERE pharmacy_group_id = $1 AND is_active = TRUE ORDER BY full_name",
        pharmacy_group_id,
    )
    return [_user_response(r) for r in rows]


# ── Roles ────────────────────────────────────────────────────────────

@router.post("/roles", response_model=RoleResponse, status_code=status.HTTP_201_CREATED)
async def assign_role(
    req: RoleAssign,
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """
    Assign a role to a user at a specific branch (or group-wide if branch_id is null).
    The granting user is recorded for audit.
    """
    # For now, use a placeholder for granted_by — in production this comes from
    # the authenticated user's app_user.id resolved via firebase_uid.
    # TODO: resolve _user["uid"] → app_user.id for proper audit trail
    row = await db.fetchrow(
        """
        INSERT INTO user_branch_role (user_id, branch_id, role, granted_by_user_id)
        VALUES ($1, $2, $3::user_role, $1)
        RETURNING *
        """,
        req.user_id, req.branch_id, req.role,
    )
    return _role_response(row)


@router.get("/roles", response_model=list[RoleResponse])
async def list_user_roles(
    user_id: str = Query(..., description="Filter roles by user"),
    db: asyncpg.Connection = Depends(get_db),
    _user: dict = Depends(get_current_user),
):
    """List all active roles for a user."""
    rows = await db.fetch(
        "SELECT * FROM user_branch_role WHERE user_id = $1 AND revoked_at IS NULL ORDER BY granted_at",
        user_id,
    )
    return [_role_response(r) for r in rows]


# ── Response helpers ─────────────────────────────────────────────────

def _group_response(row) -> PharmacyGroupResponse:
    return PharmacyGroupResponse(
        id=str(row["id"]),
        name=row["name"],
        tin_number=row["tin_number"],
        efda_license_number=row["efda_license_number"],
        efda_license_expiry=str(row["efda_license_expiry"]) if row["efda_license_expiry"] else None,
        subscription_tier=row["subscription_tier"],
        subscription_status=row["subscription_status"],
        billing_email=row["billing_email"],
        country_code=row["country_code"],
        created_at=str(row["created_at"]),
    )


def _branch_response(row) -> BranchResponse:
    return BranchResponse(
        id=str(row["id"]),
        pharmacy_group_id=str(row["pharmacy_group_id"]),
        name=row["name"],
        woreda=row["woreda"],
        subcity=row["subcity"],
        city=row["city"],
        phone=row["phone"],
        efda_branch_license=row["efda_branch_license"],
        is_active=row["is_active"],
        created_at=str(row["created_at"]),
    )


def _user_response(row) -> UserResponse:
    return UserResponse(
        id=str(row["id"]),
        pharmacy_group_id=str(row["pharmacy_group_id"]),
        firebase_uid=row["firebase_uid"],
        email=row["email"],
        full_name=row["full_name"],
        phone=row["phone"],
        efda_license_number=row["efda_license_number"],
        is_active=row["is_active"],
        created_at=str(row["created_at"]),
    )


def _role_response(row) -> RoleResponse:
    return RoleResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        branch_id=str(row["branch_id"]) if row["branch_id"] else None,
        role=row["role"],
        granted_by_user_id=str(row["granted_by_user_id"]),
        granted_at=str(row["granted_at"]),
    )
