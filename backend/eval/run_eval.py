"""Score the lyric matcher against hand-checked song lists.

Uses the transcripts already cached next to the audio (~/.songline/audio) and the
lookup cache, so it needs no GPU and few network calls. Shazam is not used:
this measures what lyrics alone find.

    uv run python eval/run_eval.py            # all videos
    uv run python eval/run_eval.py BV1yzud64E6B -v
"""

from __future__ import annotations

import asyncio
import json
import sqlite3
import sys
from pathlib import Path

from songline.cache import KVCache
from songline.config import settings
from songline.lyrics import NeteaseClient
from songline.matcher import Matcher, _same_song
from songline.models import Segment
from songline.text import title_key

TRUTH = json.loads((Path(__file__).parent / "truth.json").read_text())
TOLERANCE_MIN = 3.0


def _hint(bvid: str) -> str:
    db = sqlite3.connect(settings.db_path)
    for (data,) in db.execute("SELECT data FROM jobs ORDER BY created_at DESC"):
        v = json.loads(data).get("video") or {}
        if v.get("bvid") == bvid:
            return f"{v['title']} {v['owner']}"
    return ""


def _fmt(sec: float) -> str:
    s = int(sec)
    return f"{s // 3600}:{s % 3600 // 60:02d}:{s % 60:02d}"


async def evaluate(bvid: str, verbose: bool) -> tuple[int, int, int]:
    segs = [Segment(**s) for s in json.loads((settings.audio_dir / f"{bvid}_p1.segments.json").read_text())]
    client = NeteaseClient(KVCache(settings.data_dir / "cache.db"))
    try:
        m = Matcher(client, hint=_hint(bvid))
        await m.feed(segs, final=True)
        timeline = await m.timeline()
    finally:
        await client.aclose()

    truth = [(t[0], t[1], len(t) > 2 and t[2]) for t in TRUTH[bvid]]
    used: set[int] = set()
    found = missed = 0
    lines = []
    for minute, title, optional in truth:
        hit = next(
            (
                i
                for i, e in enumerate(timeline)
                if i not in used
                and e.song
                and _same_song(title_key(e.song.title), title_key(title))
                and e.start / 60 - TOLERANCE_MIN <= minute <= e.end / 60 + TOLERANCE_MIN
            ),
            None,
        )
        if hit is not None:
            used.add(hit)
            found += not optional
            mark = "✓"
        else:
            missed += not optional
            mark = "·" if optional else "✗"
        lines.append(f"  {mark} {minute:>4}′ {title}{'（可选）' if optional else ''}")
    extras = [e for i, e in enumerate(timeline) if i not in used]

    required = sum(1 for t in truth if not t[2])
    print(f"{bvid}: {found}/{required} found, {len(extras)} extra")
    if verbose:
        print("\n".join(l for l in lines if not l.startswith("  ✓")))
        for e in extras:
            title = e.song.title if e.song else "未识别"
            print(f"  + {_fmt(e.start)}–{_fmt(e.end)} {title} ({e.confidence:.0%})")
    return found, required, len(extras)


async def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    verbose = "-v" in sys.argv
    totals = [0, 0, 0]
    for bvid in args or [k for k in TRUTH if not k.startswith("_")]:
        for i, n in enumerate(await evaluate(bvid, verbose)):
            totals[i] += n
    print(f"TOTAL: {totals[0]}/{totals[1]} found, {totals[2]} extra")


if __name__ == "__main__":
    asyncio.run(main())
