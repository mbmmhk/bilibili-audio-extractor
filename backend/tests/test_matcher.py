import pytest

from songline.lyrics import Candidate
from songline.matcher import MAX_QUERIES, Matcher, clean_segments
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

    async def canonical(self, title, sung=None, prefer=""):
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
    assert c.searches <= 2 * MAX_QUERIES  # one search round, maybe two; not one per window


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


def test_queries_prefer_lyric_lines_over_chat():
    from songline.matcher import _Line, _queries_for

    lines = [_Line(0, 1, t, norm(t)) for t in ["我主要是感觉可能是因为之前吃的", "爱一个人要学会放下", "奢望幸福却也要不惜代价"]]
    qs = _queries_for(lines)
    assert qs[:2] == [norm("奢望幸福却也要不惜代价"), norm("爱一个人要学会放下")]
    assert all("感觉" not in q for q in qs)


def test_homophone_errors_still_match_by_pinyin():
    from songline.lyrics import Candidate
    from songline.matcher import _Line, _Scorer

    cand = Candidate(1, "离人赋", "云汐", [norm("你送的胭脂扣是我的心头"), norm("在那一夜缠绵后")])
    heard = norm("你送的胭脂口是我的新头")  # what Whisper wrote
    assert _Scorer().hit(_Line(0, 1, heard, heard), cand)
    chat = norm("今天吃的火锅特别好吃")
    assert not _Scorer().hit(_Line(0, 1, chat, chat), cand)


def test_vote_merges_title_variants():
    from songline.lyrics import Candidate
    from songline.matcher import _vote, _Window

    lyr = [norm(l) for l in SONG_A]
    a = Candidate(1, "魔术手-陈振祥 伴奏", "陈振祥", lyr)
    b = Candidate(2, "魔术手", "之烨", lyr)
    c = Candidate(3, "路小雨", "Apr光", lyr)
    # Each variant alone gets fewer votes than 路小雨; together they win.
    w1 = _Window(0, [], a, 0.9, pool=[a, c])
    w2 = _Window(15, [], b, 0.9, pool=[b, c])
    assert _vote([w1, w2]).title == "魔术手"


def test_audio_reuse_ignores_cached_transcript(tmp_path):
    from songline.bili import download_audio
    from songline.models import VideoInfo

    (tmp_path / "BV1xx411c7mD_p1.segments.json").write_text("[]")
    (tmp_path / "BV1xx411c7mD_p1.m4a").write_bytes(b"audio")
    v = VideoInfo(bvid="BV1xx411c7mD", aid=1, title="t", owner="o", cover="", duration=1, page=1, pages=[], description="")
    assert download_audio(v, tmp_path).suffix == ".m4a"


class ListClient(FakeClient):
    """Returns the given uploads, in this order, for any matching lyric search."""

    def __init__(self, *cands):
        self.songs = {c.id: c for c in cands}
        self.searches = 0


@pytest.mark.asyncio
async def test_reused_windows_still_vote_for_same_lyric_uploads():
    lyr = [norm(l) for l in SONG_A]
    c = ListClient(Candidate(1, "路小雨", "Apr光", lyr), Candidate(2, "魔术手", "之烨", lyr), Candidate(3, "魔术手-陈振祥 伴奏", "陈振祥", lyr))
    m = Matcher(c)
    await m.feed(segs(SONG_A * 4), final=True)
    assert [e.song.title for e in await m.timeline()] == ["魔术手"]


@pytest.mark.asyncio
async def test_original_named_after_its_hook_keeps_its_title():
    lines = ["我多喜欢你你会知道", "我们在一起的时光", "每一天都是晴朗", "就算以后会遗忘"]
    lyr = [norm(l) for l in lines]
    c = ListClient(Candidate(1, "我多喜欢你，你会知道", "王俊琪", lyr), Candidate(2, "我好喜欢你你知不知道", "糖火烧", lyr))
    m = Matcher(c)
    await m.feed(segs(lines * 4), final=True)
    assert [e.song.title for e in await m.timeline()] == ["我多喜欢你，你会知道"]


@pytest.mark.asyncio
@pytest.mark.parametrize("gap_lines,entries", [(["好厉害"], 1), (["谢谢大家的礼物今天好开心呀", "等我喝口水我们聊会儿天"] * 6, 2)])
async def test_same_song_merges_across_a_quiet_gap_but_not_a_chat_break(gap_lines, entries):
    # 110s between the two halves: too long for a chat break, fine for
    # backing music Whisper did not transcribe.
    first = segs(SONG_B * 2, 0)
    gap = segs(gap_lines, 40, step=6.0)
    second = segs(SONG_B * 2, 150)
    m = Matcher(FakeClient())
    await m.feed(first + gap + second, final=True)
    assert [e.song.title for e in await m.timeline()] == ["当初的我们"] * entries
