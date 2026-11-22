"""Job persistence (SQLite), a single-worker queue, and live event fan-out."""

from __future__ import annotations

import asyncio
import json
import logging
import sqlite3
import threading
import time
import uuid
from collections import defaultdict
from pathlib import Path
from typing import AsyncIterator

from . import pipeline
from .bili import BiliError
from .cache import KVCache
from .models import Job, JobOptions, Segment, Stage

log = logging.getLogger(__name__)


class JobStore:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(path, check_same_thread=False)
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.execute("CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, data TEXT, created_at REAL)")
        self._db.execute("CREATE TABLE IF NOT EXISTS transcripts (job_id TEXT PRIMARY KEY, data TEXT)")
        self._lock = threading.Lock()

    def save(self, job: Job) -> None:
        with self._lock:
            self._db.execute(
                "INSERT OR REPLACE INTO jobs VALUES (?, ?, ?)", (job.id, job.model_dump_json(), job.created_at)
            )
            self._db.commit()

    def get(self, job_id: str) -> Job | None:
        with self._lock:
            row = self._db.execute("SELECT data FROM jobs WHERE id=?", (job_id,)).fetchone()
        return Job.model_validate_json(row[0]) if row else None

    def list(self, limit: int = 200) -> list[Job]:
        with self._lock:
            rows = self._db.execute("SELECT data FROM jobs ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
        return [Job.model_validate_json(r[0]) for r in rows]

    def delete(self, job_id: str) -> None:
        with self._lock:
            self._db.execute("DELETE FROM jobs WHERE id=?", (job_id,))
            self._db.execute("DELETE FROM transcripts WHERE job_id=?", (job_id,))
            self._db.commit()

    def save_transcript(self, job_id: str, segments: list[Segment]) -> None:
        with self._lock:
            self._db.execute(
                "INSERT OR REPLACE INTO transcripts VALUES (?, ?)",
                (job_id, json.dumps([s.model_dump() for s in segments], ensure_ascii=False)),
            )
            self._db.commit()

    def transcript(self, job_id: str) -> list[Segment] | None:
        with self._lock:
            row = self._db.execute("SELECT data FROM transcripts WHERE job_id=?", (job_id,)).fetchone()
        return [Segment(**s) for s in json.loads(row[0])] if row else None


class JobManager:
    """Runs jobs one at a time (transcription saturates the GPU anyway)."""

    def __init__(self, store: JobStore, cache: KVCache):
        self.store = store
        self.cache = cache
        self._queue: asyncio.Queue[str] = asyncio.Queue()
        self._cancel: set[str] = set()
        self._subs: dict[str, set[asyncio.Queue[Job | None]]] = defaultdict(set)
        self._worker: asyncio.Task | None = None

    async def start(self) -> None:
        # Resume anything interrupted by a restart.
        for job in reversed(self.store.list()):
            if not job.finished:
                job.stage, job.progress, job.message = Stage.queued, 0.0, "排队中（服务重启后恢复）"
                self.store.save(job)
                self._queue.put_nowait(job.id)
        self._worker = asyncio.create_task(self._work())

    async def stop(self) -> None:
        if self._worker:
            self._worker.cancel()

    async def submit(self, url: str, options: JobOptions) -> Job:
        now = time.time()
        job = Job(id=uuid.uuid4().hex[:12], url=url, options=options, created_at=now, updated_at=now, message="排队中")
        self.store.save(job)
        await self._queue.put(job.id)
        return job

    def cancel(self, job_id: str) -> Job | None:
        job = self.store.get(job_id)
        if not job or job.finished:
            return job
        self._cancel.add(job_id)
        if job.stage == Stage.queued:
            job.stage, job.message = Stage.cancelled, "已取消"
            self.store.save(job)
            self._publish(job)
        return job

    async def subscribe(self, job_id: str) -> AsyncIterator[Job]:
        q: asyncio.Queue[Job | None] = asyncio.Queue()
        self._subs[job_id].add(q)
        try:
            job = self.store.get(job_id)
            if job:
                yield job
                if job.finished:
                    return
            while True:
                item = await q.get()
                if item is None:
                    return
                yield item
                if item.finished:
                    return
        finally:
            self._subs[job_id].discard(q)

    def _publish(self, job: Job) -> None:
        for q in list(self._subs.get(job.id, ())):
            q.put_nowait(job)

    async def _work(self) -> None:
        while True:
            job_id = await self._queue.get()
            job = self.store.get(job_id)
            if not job or job.finished:
                continue
            await self._run(job)

    async def _run(self, job: Job) -> None:
        async def update(j: Job) -> None:
            j.updated_at = time.time()
            self.store.save(j)
            self._publish(j)

        ctx = pipeline.Context(
            update=update,
            is_cancelled=lambda: job.id in self._cancel,
            cache=self.cache,
            save_transcript=lambda segs: self.store.save_transcript(job.id, segs),
        )
        try:
            await pipeline.run(job, ctx)
        except pipeline.JobCancelled:
            job.stage, job.message = Stage.cancelled, "已取消"
            await update(job)
        except BiliError as e:
            job.stage, job.error, job.message = Stage.failed, str(e), str(e)
            await update(job)
        except Exception as e:  # keep the worker alive whatever happens
            log.exception("job %s failed", job.id)
            job.stage, job.error, job.message = Stage.failed, f"{type(e).__name__}: {e}", "处理失败"
            await update(job)
        finally:
            self._cancel.discard(job.id)
