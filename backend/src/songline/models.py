"""Shared data models (also the API's wire format)."""

from __future__ import annotations

from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field


class VideoPage(BaseModel):
    page: int
    cid: int
    title: str
    duration: int


class VideoInfo(BaseModel):
    bvid: str
    aid: int
    title: str
    owner: str
    cover: str
    duration: int
    page: int = 1
    pages: list[VideoPage] = Field(default_factory=list)
    description: str = ""

    @property
    def url(self) -> str:
        return f"https://www.bilibili.com/video/{self.bvid}" + (f"?p={self.page}" if self.page > 1 else "")


class Segment(BaseModel):
    """One Whisper transcript segment."""

    start: float
    end: float
    text: str


class SongRef(BaseModel):
    title: str
    artist: str
    netease_id: int | None = None


Source = Literal["lyrics", "shazam", "spoken"]


class TimelineEntry(BaseModel):
    start: float
    end: float
    song: SongRef | None  # None = singing detected but not identified
    confidence: float  # 0..1
    sources: list[Source] = Field(default_factory=list)
    evidence: str = ""  # a transcript line that matched
    alternatives: list[SongRef] = Field(default_factory=list)


class Stage(str, Enum):
    queued = "queued"
    resolving = "resolving"
    downloading = "downloading"
    transcribing = "transcribing"
    matching = "matching"
    verifying = "verifying"
    done = "done"
    failed = "failed"
    cancelled = "cancelled"


class JobOptions(BaseModel):
    shazam: bool = True


class Job(BaseModel):
    id: str
    url: str
    options: JobOptions = Field(default_factory=JobOptions)
    stage: Stage = Stage.queued
    progress: float = 0.0  # 0..1 within the whole job
    message: str = ""
    error: str | None = None
    video: VideoInfo | None = None
    timeline: list[TimelineEntry] = Field(default_factory=list)
    created_at: float
    updated_at: float

    @property
    def finished(self) -> bool:
        return self.stage in (Stage.done, Stage.failed, Stage.cancelled)
