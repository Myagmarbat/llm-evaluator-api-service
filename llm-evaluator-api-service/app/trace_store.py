import json
import logging
from datetime import datetime, timezone
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)

_CREATE_TABLE = """
CREATE TABLE IF NOT EXISTS mismatch_traces (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    request_payload TEXT NOT NULL,
    primary_response TEXT NOT NULL,
    candidate_response TEXT NOT NULL,
    evaluation TEXT NOT NULL
)
"""


class TraceStore:
    """Asynchronous SQLite store for mismatched shadow evaluations."""

    def __init__(self, db_path: str) -> None:
        self._db_path = db_path
        self._initialized = False
        self._init_lock = None

    async def initialize(self) -> None:
        if self._initialized:
            return
        async with aiosqlite.connect(self._db_path) as db:
            await db.execute(_CREATE_TABLE)
            await db.commit()
        self._initialized = True

    async def record_mismatch(
        self,
        *,
        request_payload: dict[str, Any],
        primary_response: dict[str, Any],
        candidate_response: dict[str, Any],
        evaluation: dict[str, Any],
    ) -> None:
        await self.initialize()
        created_at = datetime.now(timezone.utc).isoformat()
        try:
            async with aiosqlite.connect(self._db_path) as db:
                await db.execute(
                    """
                    INSERT INTO mismatch_traces
                    (created_at, request_payload, primary_response, candidate_response, evaluation)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        created_at,
                        json.dumps(request_payload),
                        json.dumps(primary_response),
                        json.dumps(candidate_response),
                        json.dumps(evaluation),
                    ),
                )
                await db.commit()
        except Exception:
            logger.exception("Failed to persist mismatch trace")

    async def count_mismatches(self) -> int:
        await self.initialize()
        async with aiosqlite.connect(self._db_path) as db:
            cursor = await db.execute("SELECT COUNT(*) FROM mismatch_traces")
            row = await cursor.fetchone()
            return int(row[0]) if row else 0
