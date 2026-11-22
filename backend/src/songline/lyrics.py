"""NetEase Cloud Music lyric search (unofficial public web API)."""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass

import httpx

from .cache import KVCache
from .text import clean_title, norm, title_key

log = logging.getLogger(__name__)

_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36",
    "Referer": "https://music.163.com/",
}


@dataclass
class Candidate:
    id: int
    title: str
    artist: str
    lyric_lines: list[str]  # normalised, non-empty

    @property
    def key(self) -> str:
        return title_key(self.title)


class NeteaseClient:
    def __init__(self, cache: KVCache, concurrency: int = 4):
        self._http = httpx.AsyncClient(headers=_HEADERS, timeout=15)
        self._cache = cache
        self._sem = asyncio.Semaphore(concurrency)

    async def aclose(self) -> None:
        await self._http.aclose()

    async def _post(self, url: str, data: dict) -> dict:
        async with self._sem:
            for attempt in range(4):
                try:
                    r = await self._http.post(url, data=data)
                    r.raise_for_status()
                    body = r.json()
                    if body.get("code") == 200:
                        return body
                    log.warning("netease %s code=%s", url, body.get("code"))
                except (httpx.HTTPError, ValueError) as e:
                    log.warning("netease request failed (%s), retrying", e)
                await asyncio.sleep(1.5 * (attempt + 1))
        return {}

    async def search_lyrics(self, query: str, limit: int = 5) -> list[Candidate]:
        """Find songs whose lyrics contain `query`."""
        cached = self._cache.get("ne_lyric", query)
        if cached is None:
            body = await self._post(
                "https://music.163.com/api/search/get",
                {"s": query, "type": 1006, "limit": limit, "offset": 0},
            )
            cached = [
                {
                    "id": s["id"],
                    "title": s["name"],
                    "artist": "/".join(a["name"] for a in s.get("artists", [])),
                    "lyrics": (s.get("lyrics") or {}).get("txt", ""),
                }
                for s in (body.get("result") or {}).get("songs") or []
            ]
            if body:
                self._cache.set("ne_lyric", query, cached)
        out = []
        for c in cached:
            lines = [norm(l) for l in c["lyrics"].splitlines()]
            lines = [l for l in lines if len(l) >= 2]
            if lines:
                out.append(Candidate(c["id"], c["title"], c["artist"], lines))
        return out

    async def canonical(self, title: str) -> tuple[str, str, int | None] | None:
        """Best-known original (title, artist, id) for a song title.

        NetEase lists many covers under the same name; `originSongSimpleData` on a
        cover points at the original, and results are roughly popularity-ordered.
        """
        key = title_key(title)
        cached = self._cache.get("ne_canon", key)
        if cached is None:
            body = await self._post(
                "https://music.163.com/api/cloudsearch/pc",
                {"s": clean_title(title), "type": 1, "limit": 10, "offset": 0},
            )
            cached = None
            songs = (body.get("result") or {}).get("songs") or []
            same = [s for s in songs if title_key(s["name"]) == key]
            for s in same:
                origin = s.get("originSongSimpleData")
                if origin and title_key(origin.get("name", "")) == key:
                    cached = [
                        clean_title(origin["name"]),
                        "/".join(a["name"] for a in origin.get("artists", [])),
                        origin.get("songId"),
                    ]
                    break
            if cached is None and same:
                best = max(same, key=lambda s: (s.get("pop") or 0, -songs.index(s)))
                cached = [clean_title(best["name"]), "/".join(a["name"] for a in best["ar"]), best["id"]]
            if body:
                self._cache.set("ne_canon", key, cached or [])
        return tuple(cached) if cached else None  # type: ignore[return-value]
