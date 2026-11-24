import httpx
import pytest

from songline import bili

INFO = {
    "code": 0,
    "data": {
        "bvid": "BV1CK1FzMEU8",
        "aid": 1,
        "title": "t",
        "owner": {"name": "o"},
        "pic": "http://x/y.jpg",
        "desc": "",
        "pages": [{"page": 1, "cid": 2, "part": "p1", "duration": 60}],
    },
}


def _fake(monkeypatch, replies):
    """Serve `replies` (status, body) in turn to bili._client(); returns the Cookie headers sent."""
    seen = []
    calls = iter(replies)

    def handler(request):
        if request.url.path.endswith("/finger/spi"):
            return httpx.Response(200, json={"code": 0, "data": {"b_3": "B3", "b_4": "B4"}})
        seen.append(request.headers.get("cookie", ""))
        status, body = next(calls)
        return httpx.Response(status, json=body) if isinstance(body, dict) else httpx.Response(status, text=body)

    monkeypatch.setattr(bili, "_client", lambda: httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(bili, "RETRY_DELAY", 0)
    return seen


@pytest.mark.asyncio
async def test_info_retries_empty_and_blocked_replies(monkeypatch):
    sent = _fake(monkeypatch, [(200, ""), (412, "<html>风控</html>"), (200, INFO)])
    info = await bili.fetch_info("BV1CK1FzMEU8")
    assert info.title == "t" and info.cover.startswith("https://")
    assert all("buvid3=B3" in c for c in sent)  # looks like a browser


@pytest.mark.asyncio
async def test_info_gives_a_readable_error_when_bilibili_keeps_failing(monkeypatch):
    _fake(monkeypatch, [(200, "")] * 3 + [(412, "<html></html>")])
    with pytest.raises(bili.BiliError, match="重新识别.*HTTP 412"):
        await bili.fetch_info("BV1CK1FzMEU8")


def test_download_sends_device_cookies_and_retries_412(tmp_path, monkeypatch):
    import http.cookiejar

    import yt_dlp

    from songline.models import VideoInfo

    attempts, cookies_seen = [], []

    class FakeYDL:
        def __init__(self, opts):
            self.opts = opts
            self.cookiejar = http.cookiejar.CookieJar()

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def extract_info(self, url, download):
            attempts.append(url)
            cookies_seen.append(sorted(c.name for c in self.cookiejar))
            if len(attempts) == 1:
                raise yt_dlp.utils.DownloadError("Unable to download webpage: HTTP Error 412: Precondition Failed")
            (tmp_path / "BV1CK1FzMEU8_p1.m4a").write_bytes(b"audio")
            return {}

        def prepare_filename(self, info):
            return str(tmp_path / "BV1CK1FzMEU8_p1.m4a")

    monkeypatch.setattr(bili.yt_dlp, "YoutubeDL", FakeYDL)
    monkeypatch.setattr(bili, "_device_cookies", lambda: {"buvid3": "B3", "buvid4": "B4"})
    monkeypatch.setattr(bili, "RETRY_DELAY", 0)
    v = VideoInfo(bvid="BV1CK1FzMEU8", aid=1, title="t", owner="o", cover="", duration=1, page=1, pages=[], description="")
    assert bili.download_audio(v, tmp_path).name == "BV1CK1FzMEU8_p1.m4a"
    assert len(attempts) == 2
    assert cookies_seen == [["buvid3", "buvid4"]] * 2


def test_download_uses_playback_audio_when_video_page_keeps_returning_412(tmp_path, monkeypatch):
    import yt_dlp

    from songline.models import VideoInfo, VideoPage

    video = VideoInfo(
        bvid="BV1CK1FzMEU8", aid=1, title="t", owner="o", cover="", duration=1, page=2,
        pages=[
            VideoPage(page=1, cid=2, title="p1", duration=1),
            VideoPage(page=2, cid=3, title="p2", duration=1),
        ],
    )
    audio_url = "https://audio.bilivideo.com/track.m4s"
    expected_path = tmp_path / "BV1CK1FzMEU8_p2.m4a"
    attempts = []

    def playback(request):
        assert request.url.path == "/x/player/playurl"
        assert request.url.params["bvid"] == video.bvid
        assert request.url.params["cid"] == "3"
        assert "buvid3=B3" in request.headers["cookie"]
        return httpx.Response(200, json={"code": 0, "data": {"dash": {
            "audio": [{"base_url": audio_url, "bandwidth": 98000}],
            "video": [{"baseUrl": "https://video.bilivideo.com/track.m4s"}],
        }}})

    class BlockedVideoPage(yt_dlp.YoutubeDL):
        def extract_info(self, url, download):
            attempts.append(url)
            raise yt_dlp.utils.DownloadError("Unable to download webpage: HTTP Error 412: Precondition Failed")

        def process_ie_result(self, info, download):
            assert download
            assert [f["url"] for f in info["formats"]] == [audio_url]
            assert info["formats"][0]["vcodec"] == "none"
            expected_path.write_bytes(b"audio")
            return {**info, "ext": "m4a"}

    client = httpx.Client
    monkeypatch.setattr(bili.httpx, "Client", lambda **kwargs: client(transport=httpx.MockTransport(playback), **kwargs))
    monkeypatch.setattr(bili.yt_dlp, "YoutubeDL", BlockedVideoPage)
    monkeypatch.setattr(bili, "_device_cookies", lambda: {"buvid3": "B3"})
    monkeypatch.setattr(bili, "RETRY_DELAY", 0)

    assert bili.download_audio(video, tmp_path) == expected_path
    assert attempts == [video.url] * bili.DOWNLOAD_ATTEMPTS
