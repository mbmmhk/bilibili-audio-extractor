"""Runtime configuration. Everything is overridable via SONGLINE_* env vars."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path


def _env_path(name: str, default: Path) -> Path:
    return Path(os.environ.get(name, default)).expanduser()


@dataclass(frozen=True)
class Settings:
    data_dir: Path = field(default_factory=lambda: _env_path("SONGLINE_DATA", Path.home() / ".songline"))
    whisper_model: str = os.environ.get("SONGLINE_WHISPER_MODEL", "mlx-community/whisper-large-v3-turbo")
    # Transcribe in chunks so progress and partial results stream to the UI.
    chunk_seconds: int = int(os.environ.get("SONGLINE_CHUNK_SECONDS", "600"))
    # Optional Bilibili login cookie (SESSDATA) for videos that need it.
    bili_sessdata: str | None = os.environ.get("SONGLINE_BILI_SESSDATA") or None

    @property
    def audio_dir(self) -> Path:
        return self.data_dir / "audio"

    @property
    def db_path(self) -> Path:
        return self.data_dir / "songline.db"

    @property
    def bin_dir(self) -> Path:
        return self.data_dir / "bin"

    def ensure_dirs(self) -> None:
        for d in (self.data_dir, self.audio_dir, self.bin_dir):
            d.mkdir(parents=True, exist_ok=True)


settings = Settings()
