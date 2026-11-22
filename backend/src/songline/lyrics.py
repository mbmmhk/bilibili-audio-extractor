"""NetEase Cloud Music lyric search (unofficial public web API)."""

from __future__ import annotations

import asyncio
import logging
import re
from dataclasses import dataclass

import httpx
from rapidfuzz import fuzz

from .cache import KVCache
from .text import clean_title, norm, pinyin, title_key

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

    async def _songs(self, title: str) -> list[dict]:
        """Song search by title: [{id, name, artists, origin}] in NetEase's order."""
        q = clean_title(title)
        cached = self._cache.get("ne_songs", q)
        if cached is None:
            body = await self._post(
                "https://music.163.com/api/cloudsearch/pc", {"s": q, "type": 1, "limit": 10, "offset": 0}
            )
            cached = []
            for s in (body.get("result") or {}).get("songs") or []:
                o = s.get("originSongSimpleData")
                cached.append(
                    {
                        "id": s["id"],
                        "name": s["name"],
                        "artists": [a["name"] for a in s.get("ar") or []],
                        "origin": o
                        and {"id": o.get("songId"), "name": o.get("name", ""), "artists": [a["name"] for a in o.get("artists") or []]},
                    }
                )
            if body:
                self._cache.set("ne_songs", q, cached)
        return cached

    async def song_lyrics(self, song_id: int) -> list[str]:
        """Normalised lyric lines of one song (credits dropped)."""
        cached = self._cache.get("ne_lrc", str(song_id))
        if cached is None:
            body = await self._post("https://music.163.com/api/song/lyric", {"id": song_id, "lv": 1})
            raw = (body.get("lrc") or {}).get("lyric") or ""
            cached = []
            for line in raw.splitlines():
                text = _LRC_TAG.sub("", line)
                if ":" in text or "：" in text:  # 作词 : …, 吉他 : …
                    continue
                n = norm(text)
                if len(n) >= 2:
                    cached.append(n)
            if body:
                self._cache.set("ne_lrc", str(song_id), cached)
        return cached

    async def canonical(
        self, title: str, sung: list[str] | None = None, prefer: str = ""
    ) -> tuple[str, str, int | None] | None:
        """Best-known original (title, artist, id) of the song that was sung.

        Many different songs share a title (小星星 the nursery rhyme vs 汪苏泷),
        and NetEase lists many covers under each. So among same-title results we
        keep those whose lyrics contain what was `sung`, then prefer, in order:
        an artist named in `prefer` (the streamer singing her own song), the
        original a cover points to, an artist credited as "Cover X" by several
        uploads, and finally NetEase's own ranking.
        """
        key = title_key(title)
        if len(key) < 1:
            return None
        songs = await self._songs(title)
        same = [s for s in songs if title_key(s["name"]) == key]
        if not same:
            # "周传雄-寂寞沙洲冷": try the parts of an artist-title style name.
            parts = [p for p in re.split(r"\s*[-－—]\s*", clean_title(title)) if len(title_key(p)) >= 2]
            for p in reversed(parts) if len(parts) > 1 else []:
                found = await self.canonical(p, sung, prefer)
                if found:
                    return found
            return None

        # Same-title songs that could be the one sung: lyrics fit, or unknown.
        pool, eligible = same, same
        if sung:
            lyrics = await asyncio.gather(*(self.song_lyrics(s["id"]) for s in same))
            fits = [s for s, lyr in zip(same, lyrics) if lyr and _lyrics_fit(sung, lyr)]
            eligible = [s for s, lyr in zip(same, lyrics) if not lyr or s in fits]
            pool = fits or eligible or same

        def ref(s: dict) -> tuple[str, str, int | None]:
            return clean_title(s["name"]), "/".join(s["artists"]), s["id"]

        # Credits for the original: covers pointing at it, uploads named
        # "(Cover X)". Ties go to whoever NetEase ranks first.
        votes: dict[str, list] = {}  # artist -> [count, first position, (title, id)]
        for i, s in enumerate(eligible):
            o = s["origin"]
            if o and title_key(o["name"]) == key and o["artists"]:
                v = votes.setdefault("/".join(o["artists"]), [0, i, (clean_title(o["name"]), o["id"])])
                v[0] += 1
            if m := _COVER_OF.search(s["name"]):
                v = votes.setdefault(m.group(1).strip(), [0, i, (clean_title(title), None)])
                v[0] += 1
        if votes:
            artist, (_, _, (name, sid)) = max(votes.items(), key=lambda kv: (kv[1][0], -_rank(kv[0], eligible, kv[1][1])))
            own = next((s for s in pool if "/".join(s["artists"]) == artist), None)
            return ref(own) if own else (name, artist, sid)

        # No credits: the streamer singing her own song, else NetEase's top hit.
        prefer_n = norm(prefer)
        for s in pool:
            if any(len(a) >= 2 and norm(a) in prefer_n for a in s["artists"]):
                return ref(s)
        return ref(pool[0])


def _rank(artist: str, songs: list[dict], fallback: int) -> int:
    """Position of the artist's own upload in the results (earlier = more canonical)."""
    return next((i for i, s in enumerate(songs) if "/".join(s["artists"]) == artist), fallback)


_LRC_TAG = re.compile(r"\[[^\]]*\]")
_COVER_OF = re.compile(r"cover[\s:：]*([^\)）】\]]+)", re.IGNORECASE)


def _lyrics_fit(sung: list[str], lyric_lines: list[str]) -> bool:
    """Do most of the sung lines appear (fuzzily, or by sound) in these lyrics?"""
    joined = "|".join(lyric_lines)
    joined_py = "|".join(pinyin(l) for l in lyric_lines)
    hits = sum(
        1
        for s in sung
        if fuzz.partial_ratio(s, joined) >= 72 or (len(pinyin(s)) >= 12 and fuzz.partial_ratio(pinyin(s), joined_py) >= 80)
    )
    return hits >= max(1, len(sung) // 2)
