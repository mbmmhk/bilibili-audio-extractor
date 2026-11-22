"""Bilibili: URL parsing, metadata and audio download."""

from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Callable
from urllib.parse import parse_qs, urlparse

import httpx
import yt_dlp

from .config import settings
from .models import VideoInfo, VideoPage

log = logging.getLogger(__name__)

_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
_BV = re.compile(r"BV[0-9A-Za-z]{10}")
_AV = re.compile(r"(?:^|[^0-9A-Za-z])av(\d+)", re.IGNORECASE)


class BiliError(Exception):
    pass


def _client() -> httpx.AsyncClient:
    cookies = {"SESSDATA": settings.bili_sessdata} if settings.bili_sessdata else None
    return httpx.AsyncClient(
        headers={"User-Agent": _UA, "Referer": "https://www.bilibili.com/"},
        cookies=cookies,
        timeout=15,
        follow_redirects=True,
    )


async def resolve(raw: str) -> tuple[str | int, int]:
    """Accept a BV id, av id, full URL, or b23.tv short link. Returns (id, page)."""
    raw = raw.strip()
    if "b23.tv" in raw or "bili2233.cn" in raw:
        m = re.search(r"https?://\S+", raw)
        async with _client() as c:
            r = await c.get(m.group(0) if m else raw)
            raw = str(r.url)
    page = 1
    if "://" in raw:
        qs = parse_qs(urlparse(raw).query)
        if qs.get("p", [""])[0].isdigit():
            page = int(qs["p"][0])
    if m := _BV.search(raw):
        return m.group(0), page
    if m := _AV.search(raw):
        return int(m.group(1)), page
    raise BiliError("没有在链接里找到 BV 号，请粘贴 B 站视频链接")


async def fetch_info(vid: str | int, page: int = 1) -> VideoInfo:
    params = {"bvid": vid} if isinstance(vid, str) else {"aid": vid}
    async with _client() as c:
        r = await c.get("https://api.bilibili.com/x/web-interface/view", params=params)
    body = r.json()
    if body.get("code") != 0:
        raise BiliError(f"获取视频信息失败：{body.get('message') or body.get('code')}")
    d = body["data"]
    pages = [VideoPage(page=p["page"], cid=p["cid"], title=p["part"], duration=p["duration"]) for p in d["pages"]]
    page = page if 1 <= page <= len(pages) else 1
    return VideoInfo(
        bvid=d["bvid"],
        aid=d["aid"],
        title=d["title"],
        owner=d["owner"]["name"],
        cover=d["pic"].replace("http://", "https://"),
        duration=pages[page - 1].duration,
        page=page,
        pages=pages,
        description=d.get("desc", ""),
    )


class Cancelled(Exception):
    pass


def download_audio(
    video: VideoInfo,
    dest_dir: Path,
    on_progress: Callable[[float], None] | None = None,
    should_cancel: Callable[[], bool] | None = None,
) -> Path:
    """Download the audio-only stream (no video, no re-encode). Blocking."""
    stem = f"{video.bvid}_p{video.page}"
    existing = [p for p in dest_dir.glob(f"{stem}.*") if p.suffix not in (".part", ".ytdl")]
    if existing:
        return existing[0]

    def hook(d: dict) -> None:
        if should_cancel and should_cancel():
            raise Cancelled()
        if d["status"] == "downloading" and on_progress:
            total = d.get("total_bytes") or d.get("total_bytes_estimate")
            if total:
                on_progress(min(1.0, d.get("downloaded_bytes", 0) / total))

    opts = {
        "format": "bestaudio/best",
        "outtmpl": str(dest_dir / f"{stem}.%(ext)s"),
        "progress_hooks": [hook],
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "http_headers": {"User-Agent": _UA, "Referer": "https://www.bilibili.com/"},
    }
    if settings.bili_sessdata:
        opts["http_headers"]["Cookie"] = f"SESSDATA={settings.bili_sessdata}"
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(video.url, download=True)
            path = Path(ydl.prepare_filename(info))
    except yt_dlp.utils.DownloadError as e:
        if isinstance(e.exc_info[1] if e.exc_info else None, Cancelled):
            raise Cancelled() from e
        raise BiliError(f"下载音频失败：{e}") from e
    if not path.exists():
        raise BiliError("下载完成但找不到音频文件")
    return path
