"""Turn a (noisy) Whisper transcript into a song timeline via lyric search.

Approach
--------
1. Clean the transcript (t2s, drop Whisper hallucinations and runs of repeats).
2. Slide a WINDOW-second window in STEP-second steps.
3. For each window, first check whether a recently matched song still explains
   the lines (cheap, no network); otherwise search NetEase by the window's most
   lyric-like lines.
4. Score = share of the window's characters found (fuzzily) in a candidate's
   lyrics. Chat scores low against any lyric, singing scores high, so this one
   number both identifies the song and separates singing from talking.
5. Merge consecutive windows of the same song (tolerating short gaps for chat
   breaks) into timeline entries.

The matcher is incremental: call `feed()` as transcript chunks arrive and
`timeline()` at any time for the current best result.
"""

from __future__ import annotations

import asyncio
import logging
import re
from dataclasses import dataclass, field

from rapidfuzz import fuzz

from .lyrics import Candidate, NeteaseClient
from .models import Segment, SongRef, TimelineEntry
from .text import clean_title, is_hallucination, norm, pinyin, title_key

log = logging.getLogger(__name__)

WINDOW = 30.0
STEP = 15.0
MIN_LINE_CHARS = 4
MIN_WINDOW_CHARS = 8
LINE_MATCH = 72  # partial_ratio needed for a line to count as "in the lyrics"
ACCEPT = 0.5  # window score needed to assign a song
REUSE = 0.6  # score needed to keep a recent song without searching again
MERGE_GAP = 75.0  # same song resumes after a chat break shorter than this
QUIET_GAP = 180.0  # ... or after a longer stretch where little is said:
QUIET_RATE = 40  # chars/minute; chat runs at 150+, and Whisper often drops vocals over loud backing
RECENT_POOL = 6
MIN_ENTRY_CHARS = 14  # an entry must rest on more than one short line
POOL_SLACK = 0.08  # candidates this close to the best are "the same song" votes
PY_MATCH = 80  # pinyin partial_ratio for a homophone-tolerant line match
PY_MIN_LEN = 12  # pinyin is less distinctive; only trust it on longer lines


@dataclass
class _Line:
    start: float
    end: float
    raw: str
    n: str  # normalised


@dataclass
class _Window:
    start: float
    lines: list[_Line]
    cand: Candidate | None = None
    score: float = 0.0
    matched: list[_Line] = field(default_factory=list)
    # Near-best candidates: usually the same song uploaded under other titles.
    pool: list[Candidate] = field(default_factory=list)
    runner_up: Candidate | None = None
    # Every candidate that explains the window well enough (pool included).
    fits: list[Candidate] = field(default_factory=list)

    @property
    def keys(self) -> set[str]:
        return {c.key for c in self.pool}


class _Cleaner:
    """Incremental transcript cleaning: drops hallucinations and Whisper loops."""

    def __init__(self) -> None:
        self.lines: list[_Line] = []
        self._seen = 0
        self._repeat = 0

    def add(self, segments: list[Segment]) -> None:
        for s in segments[self._seen :]:
            text = s.text.strip()
            n = norm(text)
            if len(n) < 2 or is_hallucination(text):
                continue
            if self.lines and self.lines[-1].n == n:
                self._repeat += 1
                if self._repeat >= 2:  # keep at most two identical lines in a row
                    continue
            else:
                self._repeat = 0
            self.lines.append(_Line(s.start, s.end, text, n))
        self._seen = len(segments)


def clean_segments(segments: list[Segment]) -> list[_Line]:
    c = _Cleaner()
    c.add(segments)
    return c.lines


class _Scorer:
    def __init__(self) -> None:
        self._joined: dict[int, tuple[str, str]] = {}

    def hit(self, ln: _Line, cand: Candidate) -> bool:
        """Is this transcript line (fuzzily) part of the candidate's lyrics?"""
        if len(ln.n) < MIN_LINE_CHARS:
            return False
        joined = self._joined.get(cand.id)
        if joined is None:
            lyric = "|".join(cand.lyric_lines)
            joined = self._joined[cand.id] = (lyric, "|".join(pinyin(l) for l in cand.lyric_lines))
        if fuzz.partial_ratio(ln.n, joined[0]) >= LINE_MATCH:
            return True
        # Fall back to sound: Whisper often picks the wrong homophone, which
        # wrecks character matching on classical-style lyrics.
        py = pinyin(ln.n)
        return len(py) >= PY_MIN_LEN and fuzz.partial_ratio(py, joined[1]) >= PY_MATCH

    def score(self, lines: list[_Line], cand: Candidate) -> tuple[float, list[_Line]]:
        total = matched_chars = 0
        matched: list[_Line] = []
        for ln in lines:
            if len(ln.n) < MIN_LINE_CHARS:
                continue
            total += len(ln.n)
            if self.hit(ln, cand):
                matched_chars += len(ln.n)
                matched.append(ln)
        if total < MIN_WINDOW_CHARS:
            return 0.0, []
        return matched_chars / total, matched


# Words far more common in streamer chat than in lyrics.
_CHAT = re.compile(
    r"你们|谢谢|哈哈|然后|就是|感觉|因为|可能|这个|那个|宝宝|直播|关注|礼物|欢迎|一下|什么|是不是|没有啊|好吧|对吧|主要|刚才|今天"
)
MAX_QUERIES = 3


def _queries_for(lines: list[_Line]) -> list[str]:
    """Several single-line queries, most lyric-like first.

    One garbled or chatty line used to spoil a combined query; searching lines
    separately lets any clean lyric line find the song.
    """

    def rank(n: str) -> float:
        # Long lines are informative, but very long ones are usually merged
        # chat or ASR soup, so length stops helping past 14 chars.
        return min(len(n), 14) - 5 * len(_CHAT.findall(n))

    usable = {ln.n for ln in lines if len(ln.n) >= 6} or {ln.n for ln in lines if len(ln.n) >= 5}
    ordered = sorted(usable, key=lambda n: (rank(n), len(n)), reverse=True)
    return [n[:30] for n in ordered if rank(n) > 0][:MAX_QUERIES]


class Matcher:
    def __init__(self, client: NeteaseClient, hint: str = ""):
        """`hint`: video title / uploader, used to credit a streamer's own songs."""
        self._client = client
        self._hint = hint
        self._scorer = _Scorer()
        self._cleaner = _Cleaner()
        self._windows: list[_Window] = []
        self._next_start = 0.0
        self._recent: list[Candidate] = []

    @property
    def _lines(self) -> list[_Line]:
        return self._cleaner.lines

    @property
    def processed_until(self) -> float:
        return self._next_start

    async def feed(self, segments: list[Segment], final: bool = False) -> None:
        """Process every window fully covered by `segments` (all of them if final)."""
        self._cleaner.add(segments)
        if not self._lines:
            return
        horizon = self._lines[-1].end if final else self._lines[-1].start - WINDOW
        while self._next_start <= horizon:
            w_start = self._next_start
            lines = [ln for ln in self._lines if w_start <= ln.start < w_start + WINDOW]
            self._windows.append(await self._match_window(w_start, lines))
            self._next_start += STEP

    async def _match_window(self, start: float, lines: list[_Line]) -> _Window:
        w = _Window(start, lines)
        if sum(len(ln.n) for ln in lines if len(ln.n) >= MIN_LINE_CHARS) < MIN_WINDOW_CHARS:
            return w

        # 1) Does a song we just heard still explain these lines?
        scored = sorted(
            ((c, *self._scorer.score(lines, c)) for c in self._recent), key=lambda x: x[1], reverse=True
        )
        if scored and scored[0][1] >= REUSE:
            self._assign(w, scored)
            return w

        # 2) Search by lyrics.
        queries = _queries_for(lines)
        if not queries:
            return w
        found = await asyncio.gather(*(self._client.search_lyrics(q) for q in queries))
        cands = list({c.id: c for batch in found for c in batch}.values())
        ranked = sorted(
            ((c, *self._scorer.score(lines, c)) for c in cands), key=lambda x: x[1], reverse=True
        )
        if ranked and ranked[0][1] >= ACCEPT:
            self._assign(w, ranked)
            for c in reversed(w.pool):
                self._remember(c)
        return w

    @staticmethod
    def _assign(w: _Window, ranked: list) -> None:
        """Best-first (candidate, score, matched lines) -> the window's song and votes.

        Near-best candidates all vote, also when a recent song is reused:
        the same lyrics are often uploaded under several titles
        ("路小雨" / "魔术手"), and the title must not be decided by
        whichever upload happened to be searched first.
        """
        w.cand, w.score, w.matched = ranked[0]
        w.pool = [r[0] for r in ranked if r[1] >= w.score - POOL_SLACK]
        w.fits = [r[0] for r in ranked if r[1] >= ACCEPT]
        others = [r[0] for r in ranked if r[1] < w.score - POOL_SLACK and r[1] >= ACCEPT]
        w.runner_up = others[0] if others else None

    def _remember(self, cand: Candidate) -> None:
        self._recent = [c for c in self._recent if c.key != cand.key]
        self._recent.insert(0, cand)
        del self._recent[RECENT_POOL:]

    # ------------------------------------------------------------------ output

    async def timeline(self) -> list[TimelineEntry]:
        # Group consecutive matched windows that agree on the song (any shared
        # title among their near-best candidates) and are close in time.
        runs: list[list[_Window]] = []
        for w in self._windows:
            if not w.cand:
                continue
            if runs:
                prev = runs[-1]
                prev_end = max(l.end for x in prev for l in x.matched)
                shared = set.intersection(*(x.keys for x in prev[-2:])) & w.keys or (prev[-1].keys & w.keys)
                if shared and w.matched[0].start - prev_end <= MERGE_GAP:
                    prev.append(w)
                    continue
            runs.append([w])

        # Runs can break where near-best titles briefly disagree ("帽衫" vs
        # "你好我有一个帽衫"); rejoin neighbours that voted for the same song.
        runs = [r for r in runs if sum(len(l.n) for l in _core(r)) >= MIN_ENTRY_CHARS]
        joined: list[list[_Window]] = []
        for run in runs:
            if joined and _same_song(_vote(joined[-1]).key, _vote(run).key):
                a, b = _core(joined[-1])[-1].end, _core(run)[0].start
                if b - a <= MERGE_GAP or (b - a <= QUIET_GAP and self._said(a, b, _vote(run)) <= QUIET_RATE * (b - a) / 60):
                    joined[-1] = joined[-1] + run
                    continue
            joined.append(run)
        runs = joined
        cands = [_vote(run) for run in runs]
        cores = [_core(run) for run in runs]

        entries: list[TimelineEntry] = []
        for i, (run, cand) in enumerate(zip(runs, cands)):
            matched = self._grow(cores[i], cand)
            if sum(len(l.n) for l in matched) < MIN_ENTRY_CHARS:
                continue
            mean = sum(w.score for w in run) / len(run)
            conf = mean * (1 - 0.5 ** len(run))  # 1 window -> x0.5, 2 -> x0.75, 3 -> x0.875
            sung = sorted({l.n for l in matched}, key=len, reverse=True)[:12]
            canon = await self._client.canonical(cand.title, sung, self._hint)
            if canon:
                song = SongRef(title=canon[0], artist=canon[1], netease_id=canon[2])
            else:
                song = SongRef(title=clean_title(cand.title), artist=cand.artist, netease_id=cand.id)
            evidence = max(matched, key=lambda l: len(l.n)).raw
            alts = {w.runner_up.key: w.runner_up for w in run if w.runner_up and w.runner_up.key != cand.key}
            entry = TimelineEntry(
                start=matched[0].start,
                end=matched[-1].end,
                song=song,
                confidence=round(conf, 3),
                sources=["lyrics"],
                evidence=evidence,
                alternatives=[SongRef(title=clean_title(a.title), artist=a.artist, netease_id=a.id) for a in alts.values()][:3],
            )
            self._apply_spoken_hint(entry)
            entries.append(entry)
        return _dedupe_overlaps(entries)

    def _said(self, a: float, b: float, cand: Candidate) -> int:
        """Characters spoken between a and b that are not this song's lyrics."""
        return sum(len(l.n) for l in self._lines if a <= l.start < b and not self._scorer.hit(l, cand))

    def _grow(self, core: list[_Line], cand: Candidate) -> list[_Line]:
        """Core lines extended to neighbouring lines that are
        also in this song's lyrics (window edges cut songs short)."""
        if not core:
            return core
        idx = {id(l): i for i, l in enumerate(self._lines)}
        out = list(core)
        for step, bound in ((-1, idx[id(core[0])]), (1, idx[id(core[-1])])):
            i, edge = bound + step, self._lines[bound]
            while 0 <= i < len(self._lines):
                l = self._lines[i]
                if abs(l.start - edge.start) > 45:
                    break
                if self._scorer.hit(l, cand):
                    out.append(l)
                    edge = l
                i += step
        return sorted({id(l): l for l in out}.values(), key=lambda l: l.start)

    def _apply_spoken_hint(self, e: TimelineEntry) -> None:
        """Streamers usually announce songs ("下一首是…", viewer requests)."""
        key = title_key(e.song.title) if e.song else ""
        if len(key) < 2:
            return
        near = "".join(ln.n for ln in self._lines if e.start - 120 <= ln.start <= e.start + 60)
        # Only count it if the title is said outside the sung lyrics themselves.
        sung = "".join(ln.n for ln in self._lines if e.start <= ln.start <= e.end)
        if key in near and near.count(key) > sung.count(key):
            e.sources.append("spoken")
            e.confidence = round(min(1.0, e.confidence + 0.2), 3)


def _same_song(a: str, b: str) -> bool:
    """"帽衫" / "你好我有一个帽衫", "谁家" / "谁家-赤热": one title contains the other."""
    short, long_ = sorted((a, b), key=len)
    return a == b or (len(short) >= 2 and short in long_ and len(short) / len(long_) >= 0.25)


def _core(run: list[_Window]) -> list[_Line]:
    return sorted({id(l): l for w in run for l in w.matched}.values(), key=lambda l: l.start)


def _lyric_titled(title: str, cand: Candidate) -> bool:
    """Remixes are often uploaded under a lyric line as the title."""
    k = title_key(title)
    return len(k) >= 6 and any(k in l for l in cand.lyric_lines)


def _vote(run: list[_Window]) -> Candidate:
    """Pick the run's title: most votes across windows, avoiding lyric-line titles."""
    votes: dict[str, float] = {}
    best: dict[str, tuple[float, Candidate]] = {}
    for w in run:
        for rank, c in enumerate(w.pool):
            weight = w.score * (1.0 if rank == 0 else 0.8)
            # Remixes get uploaded under a lyric line; an original can be named
            # after its own hook too, so trust the search's own top hit.
            if rank > 0 and _lyric_titled(c.title, c):
                weight *= 0.3
            votes[c.key] = votes.get(c.key, 0) + weight
            if c.key not in best or weight > best[c.key][0]:
                best[c.key] = (weight, c)
    # "魔术手-陈振祥 伴奏", "周传雄-寂寞沙洲冷", "谁家-赤热" are the same song as
    # the plain title: credit their votes to the shorter key they contain.
    merged = dict(votes)
    for k, v in votes.items():
        for short in votes:
            if short != k and len(short) < len(k) and _same_song(short, k):
                merged[short] += v
    key = max(merged, key=lambda k: (merged[k], -len(k)))
    return best[key][1]


def _dedupe_overlaps(entries: list[TimelineEntry]) -> list[TimelineEntry]:
    """When two entries overlap heavily, keep the more confident one."""
    entries.sort(key=lambda e: e.start)
    out: list[TimelineEntry] = []
    for e in entries:
        if out:
            p = out[-1]
            overlap = min(p.end, e.end) - max(p.start, e.start)
            shorter = min(p.end - p.start, e.end - e.start) or 1
            if overlap / shorter > 0.6:
                if e.confidence > p.confidence:
                    out[-1] = e
                continue
        out.append(e)
    return out
