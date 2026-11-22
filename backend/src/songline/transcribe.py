"""Speech-to-text with Whisper (MLX on Apple Silicon)."""

from __future__ import annotations

import threading
from typing import Callable, Iterator

import numpy as np

from .audio import SAMPLE_RATE, ffmpeg_exe
from .config import settings
from .models import Segment

_lock = threading.Lock()  # one model run at a time; MLX already uses the whole GPU

_PROMPT = "以下是一段中文直播的歌词和聊天，使用简体中文。"


def transcribe_chunks(
    pcm: np.ndarray,
    chunk_seconds: int | None = None,
    should_cancel: Callable[[], bool] | None = None,
) -> Iterator[tuple[float, list[Segment]]]:
    """Yield (fraction_done, new_segments) per chunk so callers can stream results."""
    import mlx_whisper  # heavy import; keep it off the API startup path

    ffmpeg_exe()
    chunk = (chunk_seconds or settings.chunk_seconds) * SAMPLE_RATE
    total = len(pcm)
    for off in range(0, total, chunk):
        if should_cancel and should_cancel():
            return
        piece = pcm[off : off + chunk]
        if len(piece) < SAMPLE_RATE:  # <1s tail
            break
        with _lock:
            r = mlx_whisper.transcribe(
                piece,
                path_or_hf_repo=settings.whisper_model,
                language="zh",
                initial_prompt=_PROMPT,
                condition_on_previous_text=False,  # avoids repetition loops over music
                verbose=None,
            )
        base = off / SAMPLE_RATE
        segs = [
            Segment(start=round(base + s["start"], 2), end=round(base + s["end"], 2), text=s["text"].strip())
            for s in r["segments"]
            if s["text"].strip()
        ]
        yield min(1.0, (off + len(piece)) / total), segs
