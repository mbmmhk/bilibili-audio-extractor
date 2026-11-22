"""Tiny SQLite key/value cache for remote lookups (lyric search, Shazam)."""

from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any


class KVCache:
    def __init__(self, path: Path, ttl_seconds: int = 30 * 24 * 3600):
        path.parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(path, check_same_thread=False)
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.execute(
            "CREATE TABLE IF NOT EXISTS kv (ns TEXT, k TEXT, v TEXT, ts REAL, PRIMARY KEY (ns, k))"
        )
        self._lock = threading.Lock()
        self._ttl = ttl_seconds

    def get(self, ns: str, key: str) -> Any | None:
        with self._lock:
            row = self._db.execute("SELECT v, ts FROM kv WHERE ns=? AND k=?", (ns, key)).fetchone()
        if not row or time.time() - row[1] > self._ttl:
            return None
        return json.loads(row[0])

    def set(self, ns: str, key: str, value: Any) -> None:
        with self._lock:
            self._db.execute(
                "INSERT OR REPLACE INTO kv VALUES (?, ?, ?, ?)",
                (ns, key, json.dumps(value, ensure_ascii=False), time.time()),
            )
            self._db.commit()
