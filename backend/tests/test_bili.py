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
    """Serve `replies` (status, body) in turn to bili._client()."""
    calls = iter(replies)

    def handler(request):
        status, body = next(calls)
        return httpx.Response(status, json=body) if isinstance(body, dict) else httpx.Response(status, text=body)

    monkeypatch.setattr(bili, "_client", lambda: httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(bili, "RETRY_DELAY", 0)


@pytest.mark.asyncio
async def test_info_retries_empty_and_blocked_replies(monkeypatch):
    _fake(monkeypatch, [(200, ""), (412, "<html>风控</html>"), (200, INFO)])
    info = await bili.fetch_info("BV1CK1FzMEU8")
    assert info.title == "t" and info.cover.startswith("https://")


@pytest.mark.asyncio
async def test_info_gives_a_readable_error_when_bilibili_keeps_failing(monkeypatch):
    _fake(monkeypatch, [(200, "")] * 4)
    with pytest.raises(bili.BiliError, match="重新识别"):
        await bili.fetch_info("BV1CK1FzMEU8")
