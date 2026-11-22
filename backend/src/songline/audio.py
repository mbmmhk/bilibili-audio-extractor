"""ffmpeg helpers. We ship ffmpeg via imageio-ffmpeg so users need not install it."""

from __future__ import annotations

import os
import subprocess
from functools import lru_cache
from pathlib import Path

import imageio_ffmpeg
import numpy as np

from .config import settings

SAMPLE_RATE = 16000


@lru_cache(maxsize=1)
def ffmpeg_exe() -> str:
    """Path to ffmpeg; also exposes it as `ffmpeg` on PATH for libraries (mlx-whisper)."""
    exe = imageio_ffmpeg.get_ffmpeg_exe()
    settings.ensure_dirs()
    link = settings.bin_dir / "ffmpeg"
    if not link.exists():
        try:
            link.symlink_to(exe)
        except FileExistsError:
            pass
    os.environ["PATH"] = f"{settings.bin_dir}{os.pathsep}{os.environ.get('PATH', '')}"
    return exe


def load_pcm(path: Path) -> np.ndarray:
    """Decode any audio file to 16 kHz mono float32 (what Whisper expects)."""
    cmd = [ffmpeg_exe(), "-nostdin", "-v", "error", "-i", str(path), "-f", "s16le", "-ac", "1", "-ar", str(SAMPLE_RATE), "-"]
    out = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(out, np.int16).astype(np.float32) / 32768.0


def clip_ogg(pcm: np.ndarray, start: float, seconds: float) -> bytes:
    """Encode a slice of PCM as a small OGG for fingerprinting."""
    a, b = int(start * SAMPLE_RATE), int((start + seconds) * SAMPLE_RATE)
    data = (np.clip(pcm[a:b], -1, 1) * 32767).astype(np.int16).tobytes()
    cmd = [ffmpeg_exe(), "-nostdin", "-v", "error", "-f", "s16le", "-ac", "1", "-ar", str(SAMPLE_RATE), "-i", "-", "-f", "ogg", "-"]
    return subprocess.run(cmd, input=data, capture_output=True, check=True).stdout
