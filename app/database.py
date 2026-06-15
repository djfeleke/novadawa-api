"""
Database connection pool using asyncpg.

The pool is created once at startup (via FastAPI lifespan) and stored on
app.state.db_pool. Individual endpoints acquire a connection via the
get_db() dependency injected into each route.
"""
import asyncpg
from fastapi import Request

from app.config import settings


async def create_pool() -> asyncpg.Pool:
    """Create and return the asyncpg connection pool."""
    return await asyncpg.create_pool(
        dsn=settings.database_url,
        min_size=settings.db_pool_min,
        max_size=settings.db_pool_max,
        # Neon requires SSL; the DSN already has ?sslmode=require but we also
        # pass ssl='require' explicitly so asyncpg enables it even if the DSN
        # query-string is stripped by a proxy layer.
        ssl="require",
        # Register UUID codec so UUIDs come back as Python uuid.UUID objects.
        init=_register_codecs,
    )


async def _register_codecs(conn: asyncpg.Connection) -> None:
    await conn.set_type_codec(
        "uuid",
        encoder=str,
        decoder=str,
        schema="pg_catalog",
        format="text",
    )


async def get_db(request: Request) -> asyncpg.Connection:
    """
    FastAPI dependency — yields a pooled connection for the duration of
    the request and releases it back to the pool when the response is sent.
    """
    async with request.app.state.db_pool.acquire() as conn:
        yield conn
