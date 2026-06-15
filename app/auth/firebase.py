"""
Firebase Auth token verification.

Flow:
  1. Frontend authenticates with Firebase (Google, email/password, etc.).
  2. Frontend sends the Firebase ID token in:   Authorization: Bearer <token>
  3. This module verifies the token with the Firebase Admin SDK.
  4. The verified uid is used to look up the matching app_user row.
  5. The app_user is attached to the request for downstream handlers.

During development (REQUIRE_AUTH=false) the dependency short-circuits and
returns a dummy dev user so you can test endpoints without a Firebase project.
"""
import asyncio
import json
import os
from functools import lru_cache
from typing import Optional

import firebase_admin
from firebase_admin import auth, credentials
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

import asyncpg
from app.config import settings
from app.database import get_db

bearer_scheme = HTTPBearer(auto_error=False)


@lru_cache(maxsize=1)
def get_firebase_app() -> firebase_admin.App:
    """Initialise the Firebase Admin SDK once (cached after first call)."""
    if settings.firebase_credentials_json:
        # Inline JSON — useful for Cloud Run / CI environment variables
        cred = credentials.Certificate(
            json.loads(settings.firebase_credentials_json)
        )
    elif os.path.exists(settings.firebase_credentials_path):
        cred = credentials.Certificate(settings.firebase_credentials_path)
    else:
        raise RuntimeError(
            "Firebase credentials not found. Set FIREBASE_CREDENTIALS_PATH "
            "or FIREBASE_CREDENTIALS_JSON in your .env file."
        )
    if not firebase_admin._apps:
        return firebase_admin.initialize_app(cred)
    return firebase_admin.get_app()


async def verify_token(token: str) -> dict:
    """
    Verify a Firebase ID token.  firebase_admin.auth.verify_id_token() is
    synchronous (pure crypto); run it in the default thread pool so it
    doesn't block the async event loop.
    """
    loop = asyncio.get_event_loop()
    decoded = await loop.run_in_executor(
        None,
        lambda: auth.verify_id_token(token, app=get_firebase_app()),
    )
    return decoded


async def get_current_user(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: asyncpg.Connection = Depends(get_db),
) -> dict:
    """
    FastAPI dependency — resolves the Firebase Bearer token to an app_user row.

    Returns the app_user record as a dict.  Raises HTTP 401 if the token is
    missing/invalid, or HTTP 403 if the Firebase uid has no matching app_user.

    When REQUIRE_AUTH=false (development), returns a synthetic dev user without
    hitting Firebase so you can test all endpoints locally.
    """
    if not settings.require_auth:
        # Dev shortcut — return a synthetic user; never reaches production
        return {
            "id": "00000000-0000-0000-0000-000000000001",
            "firebase_uid": "dev-uid",
            "email": "dev@novadawa.local",
            "full_name": "Dev User",
            "pharmacy_group_id": None,
            "is_active": True,
        }

    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header missing.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        decoded = await verify_token(credentials.credentials)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    uid = decoded.get("uid")
    user = await db.fetchrow(
        """
        SELECT id, firebase_uid, email, full_name, pharmacy_group_id, is_active
        FROM app_user
        WHERE firebase_uid = $1
        """,
        uid,
    )

    if not user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Firebase user has no NovaDawa account.",
        )

    if not user["is_active"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated.",
        )

    return dict(user)
