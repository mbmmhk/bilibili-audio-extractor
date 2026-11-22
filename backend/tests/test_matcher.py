import pytest

from songline.lyrics import Candidate
from songline.matcher import Matcher, clean_segments
from songline.models import Segment
from songline.text import norm, title_key

SONG_A = ["今夜的风悄悄月悄悄", "吻你的眉梢", "且把酒满倒人醉倒", "在你的怀抱", "不必问明天此刻最重要", "你的温柔我已逃不掉"]
SONG_B = ["那时的我们太年轻", "太自作聪明", "总是用分手来试探对方的反应", "为了一点点温暖就掏出真心"]


class FakeClient:
    def __init__(self):
        self.songs = {
            1: Candidate(1, "风月吻眉梢", "礼越", [norm(l) for l in SONG_A]),
            2: Candidate(2, "当初的我们", "大壮", [norm(l) for l in SONG_B]),
            # A remix uploaded under a lyric line: must not win the title vote.
            3: Candidate(3, "今夜的风悄悄月悄悄", "某DJ", [norm(l) for l in SONG_A]),
        }
        self.searches = 0

    async def search_lyrics(self, query, limit=5):
        self.searches += 1
        q = norm(query)
        return [c for c in self.songs.values() if any(q[:6] in l or l in q for l in c.lyric_lines)]

    async def canonical(self, title):
        return None


def segs(lines, start=0.0, step=4.0):
    return [Segment(start=start + i * step, end=start + i * step + 3.5, text=t) for i, t in enumerate(lines)]


def transcript():
    chat = ["谢谢大家来看直播", "今天天气真不错啊", "你们想听什么歌", "等我喝口水"]
    return (
        segs(chat, 0)
        + segs(SONG_A * 2, 20)  # ~48s of song A
        + segs(chat * 3, 80)  # ~48s chat
        + segs(["下一首唱当初的我们"], 130)
        + segs(SONG_B * 2, 135)
    )


@pytest.mark.asyncio
async def test_finds_both_songs_with_titles_and_bounds():
    m = Matcher(FakeClient())
    await m.feed(transcript(), final=True)
    tl = await m.timeline()
    assert [e.song.title for e in tl] == ["风月吻眉梢", "当初的我们"]
    a, b = tl
    assert 15 <= a.start <= 24 and a.end <= 70
    assert 130 <= b.start <= 140
    assert "spoken" in b.sources and "spoken" not in a.sources


@pytest.mark.asyncio
async def test_incremental_feed_matches_one_shot():
    """Regression: feeding chunk by chunk used to crash in _grow()."""
    full = transcript()
    one = Matcher(FakeClient())
    await one.feed(full, final=True)
    inc = Matcher(FakeClient())
    for cut in (40, 90, 150):
        await inc.feed([s for s in full if s.start < cut])
        await inc.timeline()
    await inc.feed(full, final=True)
    assert [e.song.title for e in await inc.timeline()] == [e.song.title for e in await one.timeline()]


@pytest.mark.asyncio
async def test_reuses_recent_song_without_searching_again():
    c = FakeClient()
    m = Matcher(c)
    await m.feed(segs(SONG_A * 4, 0), final=True)
    assert c.searches <= 2


@pytest.mark.asyncio
async def test_chat_only_yields_nothing():
    m = Matcher(FakeClient())
    await m.feed(segs(["谢谢大家", "今天聊聊天", "晚饭吃了火锅", "明天见"] * 5), final=True)
    assert await m.timeline() == []


def test_cleaning_drops_hallucinations_and_loops():
    lines = clean_segments(segs(["作曲 李宗盛"] * 3 + ["你好"] * 5 + ["再见"]))
    assert [l.raw for l in lines] == ["你好", "你好", "再见"]


@pytest.mark.parametrize(
    "a,b",
    [("谦让R&B", "谦让"), ("風月吻眉梢 (氛围慢速)", "风月吻眉梢"), ("生分 (伴奏)", "生分"), ("褪黑素 - Live", "褪黑素")],
)
def test_title_key_ignores_versions(a, b):
    assert title_key(a) == title_key(b)
