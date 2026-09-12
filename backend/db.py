"""Minimal SQLite-backed persistence.

Replaces the plain in-memory dicts that made every incident and Trusted
Circle membership evaporate on every backend restart -- a crash, `--reload`
triggering on a file save, the laptop sleeping, anything.

Deliberately not an ORM or a real schema-per-table design -- just a single
generic (collection, id) -> JSON blob table, since every "document" this
backend stores (IncidentRecord, CircleMember) is already a Pydantic model
that round-trips cleanly through JSON via `.model_dump(mode="json")` /
`.model_validate(...)`. Good enough for a hackathon demo; a real product
would want a proper schema + migrations instead.

sqlite3 is stdlib -- no new dependency. A fresh connection is opened per
call rather than one shared/pooled connection: FastAPI's sync `def` routes
run in a thread pool, and sqlite3 connections aren't safe to share across
threads without extra locking, so "open, do one thing, close" sidesteps
that entirely. Fine at this scale; would want a real pool under real load.
"""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Optional

_DB_PATH = Path(__file__).parent / "lifeoptimizer.db"


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(_DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS documents (
            collection TEXT NOT NULL,
            id TEXT NOT NULL,
            data TEXT NOT NULL,
            PRIMARY KEY (collection, id)
        )
        """
    )
    return conn


def put(collection: str, doc_id: str, data: dict) -> None:
    with _connect() as conn:
        conn.execute(
            "INSERT INTO documents (collection, id, data) VALUES (?, ?, ?) "
            "ON CONFLICT(collection, id) DO UPDATE SET data = excluded.data",
            (collection, doc_id, json.dumps(data)),
        )


def get(collection: str, doc_id: str) -> Optional[dict]:
    with _connect() as conn:
        row = conn.execute(
            "SELECT data FROM documents WHERE collection = ? AND id = ?",
            (collection, doc_id),
        ).fetchone()
    return json.loads(row[0]) if row else None


def list_all(collection: str) -> list[dict]:
    with _connect() as conn:
        rows = conn.execute(
            "SELECT data FROM documents WHERE collection = ?",
            (collection,),
        ).fetchall()
    return [json.loads(row[0]) for row in rows]


def delete(collection: str, doc_id: str) -> None:
    with _connect() as conn:
        conn.execute(
            "DELETE FROM documents WHERE collection = ? AND id = ?",
            (collection, doc_id),
        )
