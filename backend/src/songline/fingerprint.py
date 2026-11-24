"""Shazam fingerprint cross-check (unofficial API via shazamio).

Live singers often sing over the original backing track, so fingerprinting
catches many songs that are hard to read from lyrics, and corroborates the rest.
It is rate-limited, so we only sample where it adds information.
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from typing import Awaitable, Callable

import numpy as np
from shazamio import Shazam

from .audio import clip_ogg
from .cache import KVCache
from .models import SongRef, TimelineEntry
from .text import title_key

log = logging.getLogger(__name__)

CLIP = 12.0
GAP_STEP = 60.0
MIN_GAP = 150.0
SKIP_CONFIDENT = 0.85  # lyric matches this strong don't need a second opinion
CONCURRENCY = 2
PROBE_TIMEOUT = 20.0  # shazamio retries 429s internally for minutes otherwise
MAX_FAILURES = 3  # consecutive failures before we give up on the service
BUDGET = 180.0  # whole verification stage, seconds


@dataclass
class Hit:
    t: float
    title: str
    artist: str

    @property
    def key(self) -> str:
        return title_key(self.title)


class Fingerprinter:
    def __init__(self, cache: KVCache, cache_ns: str):
        self._shazam = Shazam()
        self._cache = cache
        self._ns = cache_ns  # per audio file
        self._sem = asyncio.Semaphore(CONCURRENCY)
        self._failures = 0
        self.unavailable = False
        self.skipped = 0

    async def close(self) -> None:
        await self._shazam.close()

    async def probe(self, pcm: np.ndarray, t: float) -> Hit | None:
        key = f"{t:.0f}"
        cached = self._cache.get("shazam:" + self._ns, key)
        if cached is not None:
            return Hit(t, *cached) if cached else None
        data = await asyncio.to_thread(clip_ogg, pcm, t, CLIP)
        async with self._sem:
            if self.unavailable:
                self.skipped += 1
                return None
            return await self._recognize(data, t, key)

    async def _recognize(self, data: bytes, t: float, key: str) -> Hit | None:
        result = None
        try:
            r = await asyncio.wait_for(self._shazam.recognize(data), PROBE_TIMEOUT)
            tr = r.get("track")
            result = [tr["title"], tr.get("subtitle", "")] if tr else []
        except Exception as e:  # timeout / network / rate limit
            log.warning("shazam failed at %.0fs: %r", t, e)
        if result is None:
            self._failures += 1
            if self._failures >= MAX_FAILURES:
                self.unavailable = True
            return None  # don't cache failures
        self._failures = 0
        self._cache.set("shazam:" + self._ns, key, result)
        await asyncio.sleep(1.0)  # be gentle; Shazam throttles bursts
        return Hit(t, *result) if result else None


def plan_probes(entries: list[TimelineEntry], duration: float) -> list[float]:
    """Sample points: middle of each entry, plus a sweep through long gaps
    (songs whose lyrics we could not read, e.g. guitar or unclear audio)."""
    pts: list[float] = []
    for e in entries:
        if e.confidence < SKIP_CONFIDENT:
            pts.append(max(0.0, (e.start + e.end) / 2 - CLIP / 2))
    edges = [0.0] + [x for e in entries for x in (e.start, e.end)] + [duration]
    for a, b in zip(edges[::2], edges[1::2]):
        if b - a >= MIN_GAP:
            t = a + 30
            while t + CLIP < b - 15:
                pts.append(t)
                t += GAP_STEP
    return sorted(p for p in pts if p + CLIP <= duration)


async def verify(
    fp: Fingerprinter,
    pcm: np.ndarray,
    entries: list[TimelineEntry],
    duration: float,
    on_progress: Callable[[float], Awaitable[None]] | None = None,
    should_cancel: Callable[[], bool] | None = None,
) -> tuple[list[TimelineEntry], int]:
    """Returns (timeline, number of probes skipped because of limits)."""
    probes = plan_probes(entries, duration)
    hits: list[Hit] = []
    done = 0

    async def one(t: float) -> None:
        nonlocal done
        if should_cancel and should_cancel():
            return
        h = await fp.probe(pcm, t)
        if h:
            hits.append(h)
        done += 1
        if on_progress:
            await on_progress(done / max(1, len(probes)))

    tasks = [asyncio.create_task(one(t)) for t in probes]
    try:
        await asyncio.wait_for(asyncio.gather(*tasks), BUDGET)
    except asyncio.TimeoutError:
        log.warning("shazam budget exhausted after %d/%d probes", done, len(probes))
    finally:
        # A probe that raised (e.g. the job was cancelled) leaves its siblings running.
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
    skipped = len(probes) - done + fp.skipped
    return merge_hits(entries, hits), skipped


def merge_hits(entries: list[TimelineEntry], hits: list[Hit]) -> list[TimelineEntry]:
    out = [e.model_copy(deep=True) for e in entries]
    unused: list[Hit] = []
    for h in hits:
        inside = [e for e in out if e.start - 5 <= h.t <= e.end + 5]
        if not inside:
            unused.append(h)
            continue
        e = inside[0]
        if e.song and title_key(e.song.title) == h.key:
            if "shazam" not in e.sources:
                e.sources.append("shazam")
                e.confidence = round(min(1.0, e.confidence + 0.25), 3)
        elif e.song and h.key and e.confidence < 0.6:
            # Lyric match is weak and Shazam disagrees: offer Shazam's answer.
            alt = SongRef(title=h.title, artist=h.artist)
            if all(title_key(a.title) != h.key for a in e.alternatives):
                e.alternatives.insert(0, alt)

    # Two consecutive gap hits on the same song = a song lyrics missed.
    unused.sort(key=lambda h: h.t)
    i = 0
    while i < len(unused):
        j = i
        while j + 1 < len(unused) and unused[j + 1].key == unused[i].key and unused[j + 1].t - unused[j].t <= 90:
            j += 1
        if j > i:
            a, b = unused[i], unused[j]
            out.append(
                TimelineEntry(
                    start=a.t,
                    end=b.t + CLIP,
                    song=SongRef(title=a.title, artist=a.artist),
                    confidence=0.6,
                    sources=["shazam"],
                    evidence="（音频指纹识别）",
                )
            )
        i = j + 1
    out.sort(key=lambda e: e.start)
    return out
