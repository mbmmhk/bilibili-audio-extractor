"""HTTP API (and static hosting of the built web UI)."""

from __future__ import annotations

import json
import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import bili
from .cache import KVCache
from .config import settings
from .jobs import JobManager, JobStore
from .models import Job, JobOptions, Segment


class CreateJob(BaseModel):
    url: str
    options: JobOptions = JobOptions()


def create_app() -> FastAPI:
    settings.ensure_dirs()
    store = JobStore(settings.db_path)
    manager = JobManager(store, KVCache(settings.data_dir / "cache.db"))

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        await manager.start()
        yield
        await manager.stop()

    app = FastAPI(title="Songline", lifespan=lifespan)

    def _get(job_id: str) -> Job:
        job = store.get(job_id)
        if not job:
            raise HTTPException(404, "任务不存在")
        return job

    @app.post("/api/jobs", response_model=Job)
    async def create(body: CreateJob) -> Job:
        if not body.url.strip():
            raise HTTPException(400, "请输入链接")
        return await manager.submit(body.url.strip(), body.options)

    @app.get("/api/jobs", response_model=list[Job])
    async def list_jobs() -> list[Job]:
        return store.list()

    @app.get("/api/jobs/{job_id}", response_model=Job)
    async def get(job_id: str) -> Job:
        return _get(job_id)

    @app.get("/api/jobs/{job_id}/events")
    async def events(job_id: str):
        _get(job_id)

        async def stream():
            async for job in manager.subscribe(job_id):
                yield f"data: {job.model_dump_json()}\n\n"

        return StreamingResponse(stream(), media_type="text/event-stream", headers={"Cache-Control": "no-cache"})

    @app.post("/api/jobs/{job_id}/cancel", response_model=Job)
    async def cancel(job_id: str) -> Job:
        _get(job_id)
        return manager.cancel(job_id)

    @app.delete("/api/jobs/{job_id}", status_code=204)
    async def delete(job_id: str) -> None:
        job = _get(job_id)
        if not job.finished:
            manager.cancel(job_id)
        store.delete(job_id)

    @app.get("/api/jobs/{job_id}/transcript", response_model=list[Segment])
    async def transcript(job_id: str) -> list[Segment]:
        job = _get(job_id)
        path = bili.transcript_path(job.video, settings.audio_dir) if job.video else None
        if path and path.exists():
            return [Segment(**s) for s in json.loads(path.read_text())]
        return store.transcript(job_id) or []

    @app.get("/api/jobs/{job_id}/audio")
    async def audio(job_id: str):
        job = _get(job_id)
        if not job.video:
            raise HTTPException(404, "音频尚未下载")
        stem = bili.audio_stem(job.video)
        files = [p for p in settings.audio_dir.glob(f"{stem}.*") if p.suffix in (".m4a", ".mp4", ".webm", ".mp3", ".aac", ".flac", ".opus")]
        if not files:
            raise HTTPException(404, "音频尚未下载")
        return FileResponse(files[0], media_type="audio/mp4" if files[0].suffix in (".m4a", ".mp4") else None)

    web_dir = Path(os.environ.get("SONGLINE_WEB_DIR", Path(__file__).resolve().parents[3] / "frontend" / "dist"))
    if web_dir.is_dir():
        app.mount("/assets", StaticFiles(directory=web_dir / "assets"), name="assets")

        @app.get("/{path:path}", include_in_schema=False)
        async def spa(path: str):
            f = web_dir / path
            return FileResponse(f if path and f.is_file() else web_dir / "index.html")

    return app
