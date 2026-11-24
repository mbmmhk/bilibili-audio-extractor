"""Fetching the Whisper model (about 1.6 GB) once, with visible progress.

mlx_whisper downloads the model on first use without telling anyone, which
looks like a hang. We fetch it ourselves first and report bytes as they land.
"""

from __future__ import annotations

import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Callable

from huggingface_hub import HfApi, constants, snapshot_download

Progress = Callable[[int, int], None]  # (bytes so far, total bytes or 0 if unknown)

_WEIGHTS = ("*.safetensors", "*.npz")


def cached(repo: str) -> Path | None:
    """The local model folder if the model is fully downloaded, else None."""
    try:
        path = Path(snapshot_download(repo_id=repo, local_files_only=True))
    except Exception:  # not in the cache (or the cache is unreadable)
        return None
    has_weights = any(next(path.glob(p), None) for p in _WEIGHTS)
    return path if (path / "config.json").exists() and has_weights else None


def ensure(repo: str, on_progress: Progress | None = None, poll: float = 1.0) -> Path:
    """Download the model unless cached. `on_progress` may raise to stop waiting
    (the download then finishes in the background and is kept for next time)."""
    if path := cached(repo):
        return path
    total = _total_size(repo)
    pool = ThreadPoolExecutor(max_workers=1)
    job = pool.submit(snapshot_download, repo_id=repo)
    try:
        while True:
            try:
                return Path(job.result(timeout=poll))
            except TimeoutError:
                if on_progress:
                    on_progress(_downloaded(repo), total)
    finally:
        pool.shutdown(wait=False)


def _total_size(repo: str) -> int:
    try:
        info = HfApi().model_info(repo, files_metadata=True)
        return sum(s.size or 0 for s in info.siblings or [])
    except Exception:
        return 0


def _downloaded(repo: str) -> int:
    """Bytes in the repo's cache folder, finished and in-progress files alike."""
    blobs = Path(constants.HF_HUB_CACHE) / f"models--{repo.replace('/', '--')}" / "blobs"
    try:
        return sum(f.stat().st_size for f in blobs.iterdir() if f.is_file())
    except OSError:
        return 0


def describe(done: int, total: int) -> str:
    size = f"{done / 1e9:.2f} / {total / 1e9:.2f} GB" if total else f"{done / 1e9:.2f} GB"
    return f"首次使用，正在下载语音识别模型 {size}（只需下载一次）"
