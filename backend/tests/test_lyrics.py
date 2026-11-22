"""Picking the original (title, artist) among same-title NetEase results."""

import pytest

from songline.lyrics import NeteaseClient
from songline.text import norm

SUNG = [norm(l) for l in ["我应该释怀在街头徘徊", "下雨时为你撑伞", "对你的感觉强烈却又不敢说"]]
WANG = [norm(l) for l in ["我应该释怀", "在街头徘徊", "下雨时为你撑伞", "对你的感觉强烈", "却又不敢说"]]
RHYME = [norm(l) for l in ["一闪一闪亮晶晶", "满天都是小星星", "挂在天上放光明"]]


def song(id, name, artists, origin=None):
    return {"id": id, "name": name, "artists": artists, "origin": origin}


class Fake(NeteaseClient):
    def __init__(self, songs, lyrics):
        self.songs_, self.lyrics_ = songs, lyrics

    async def _songs(self, title):
        return self.songs_

    async def song_lyrics(self, song_id):
        return self.lyrics_.get(song_id, [])


@pytest.mark.asyncio
async def test_ignores_same_title_songs_whose_lyrics_dont_fit():
    c = Fake(
        [
            song(1, "小星星", ["儿歌多多"]),
            song(2, "小星星（摇篮曲）", ["太空小狮子"], {"id": 9, "name": "小星星", "artists": ["群星"]}),
            song(3, "小星星", ["汪苏泷"]),
        ],
        {1: RHYME, 2: RHYME, 3: WANG},
    )
    assert await c.canonical("小星星", SUNG) == ("小星星", "汪苏泷", 3)


@pytest.mark.asyncio
async def test_cover_credits_outvote_a_single_origin_pointer():
    c = Fake(
        [
            song(1, "生分", ["落日微醺"]),
            song(2, "生分 (Cover 川青)", ["可乐不加冰"]),
            song(3, "生分(男版)", ["高熙桐"], {"id": 9, "name": "生分", "artists": ["兰益", "天音"]}),
            song(4, "生分 (Cover 川青)", ["大头针off"]),
        ],
        {},
    )
    assert (await c.canonical("生分", SUNG))[1] == "川青"


@pytest.mark.asyncio
async def test_original_beats_the_streamers_own_cover_but_hint_breaks_no_credit_ties():
    songs = [song(1, "娃娃脸", ["一口甜"], {"id": 7, "name": "娃娃脸", "artists": ["后弦"]}), song(7, "娃娃脸", ["后弦"])]
    assert (await Fake(songs, {1: WANG, 7: WANG}).canonical("娃娃脸", SUNG, prefer="一口甜直播"))[1] == "后弦"

    songs = [song(1, "沦陷晚风", ["赵政豪"]), song(2, "沦陷晚风", ["一口甜"])]
    assert (await Fake(songs, {1: WANG, 2: WANG}).canonical("沦陷晚风", SUNG, prefer="一口甜直播"))[1] == "一口甜"


@pytest.mark.asyncio
async def test_artist_title_style_names_are_split():
    c = Fake([song(1, "寂寞沙洲冷", ["周传雄"])], {})
    assert await c.canonical("周传雄-寂寞沙洲冷") == ("寂寞沙洲冷", "周传雄", 1)
