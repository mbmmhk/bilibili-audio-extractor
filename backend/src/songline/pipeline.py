"""The end-to-end recognition pipeline, independent of how it is driven (API or CLI)."""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass
from typing import Awaitable, Callable

from . import bili, model
from .audio import SAMPLE_RATE, load_pcm
from .cache import KVCache
from .config import settings
from .fingerprint import Fingerprinter, verify
from .lyrics import NeteaseClient
from .matcher import Matcher
from .models import Job, Segment, Stage
from .transcribe import transcribe_chunks

log = logging.getLogger(__name__)

# Share of overall progress per stage.
_SPAN = {
    Stage.resolving: (0.0, 0.02),
    Stage.downloading: (0.02, 0.10),
    Stage.transcribing: (0.10, 0.82),
    Stage.matching: (0.82, 0.86),
    Stage.verifying: (0.86, 1.0),
}


@dataclass
class Context:
    """What the pipeline needs from its driver."""

    update: Callable[[Job], Awaitable[None]]  # persist + broadcast
    is_cancelled: Callable[[], bool]
    cache: KVCache


class JobCancelled(Exception):
    pass


async def run(job: Job, ctx: Context) -> Job:
    async def set_stage(stage: Stage, frac: float = 0.0, message: str | None = None) -> None:
        if ctx.is_cancelled():
            raise JobCancelled()
        lo, hi = _SPAN.get(stage, (job.progress, job.progress))
        job.stage = stage
        job.progress = round(lo + (hi - lo) * frac, 4)
        if message is not None:
            job.message = message
        await ctx.update(job)

    loop = asyncio.get_running_loop()

    # 1. Resolve + metadata
    await set_stage(Stage.resolving, 0, "解析链接…")
    vid, page = await bili.resolve(job.url)
    job.video = await bili.fetch_info(vid, page)
    await set_stage(Stage.resolving, 1, f"《{job.video.title}》")

    # 2. Audio
    await set_stage(Stage.downloading, 0, "下载音频…")
    last = [0.0]

    def dl_progress(f: float) -> None:
        if f - last[0] >= 0.05 or f >= 1:
            last[0] = f
            asyncio.run_coroutine_threadsafe(set_stage(Stage.downloading, f, f"下载音频 {f:.0%}"), loop)

    settings.ensure_dirs()
    try:
        audio_path = await asyncio.to_thread(
            bili.download_audio, job.video, settings.audio_dir, dl_progress, ctx.is_cancelled
        )
    except bili.Cancelled as e:
        raise JobCancelled() from e
    pcm = await asyncio.to_thread(load_pcm, audio_path)
    duration = len(pcm) / SAMPLE_RATE

    # 3. Transcribe in chunks; match lyrics incrementally so results stream in.
    client = NeteaseClient(ctx.cache)
    matcher = Matcher(client, hint=f"{job.video.title} {job.video.owner}")
    seg_cache = bili.transcript_path(job.video, audio_path.parent)
    segments: list[Segment] = []
    try:
        if seg_cache.exists():
            segments = [Segment(**s) for s in json.loads(seg_cache.read_text())]
            await set_stage(Stage.transcribing, 1, "使用已缓存的转写结果")
        else:
            await set_stage(Stage.transcribing, 0, "加载语音识别模型…")

            def model_progress(done: int, total: int) -> None:  # runs in a worker thread
                if ctx.is_cancelled():
                    raise JobCancelled()
                job.message = model.describe(done, total)
                asyncio.run_coroutine_threadsafe(ctx.update(job), loop)

            await asyncio.to_thread(model.ensure, settings.whisper_model, model_progress)
            await set_stage(Stage.transcribing, 0, "加载语音识别模型…")
            gen = transcribe_chunks(pcm, should_cancel=ctx.is_cancelled)
            while True:
                item = await asyncio.to_thread(next, gen, None)
                if item is None:
                    break
                frac, new = item
                segments.extend(new)
                await matcher.feed(segments)
                job.timeline = await matcher.timeline()
                done = fmt_time(frac * duration)
                await set_stage(Stage.transcribing, frac, f"识别歌词 {done} / {fmt_time(duration)}")
            if ctx.is_cancelled():
                raise JobCancelled()
            seg_cache.write_text(json.dumps([s.model_dump() for s in segments], ensure_ascii=False))

        # 4. Final matching pass
        await set_stage(Stage.matching, 0, "匹配歌曲…")
        await matcher.feed(segments, final=True)
        job.timeline = await matcher.timeline()
        await set_stage(Stage.matching, 1, f"找到 {len(job.timeline)} 首")

        # 5. Fingerprint cross-check
        skipped = 0
        if job.options.shazam:
            await set_stage(Stage.verifying, 0, "音频指纹核对…")
            fp = Fingerprinter(ctx.cache, audio_path.stem)
            try:
                job.timeline, skipped = await verify(
                    fp,
                    pcm,
                    job.timeline,
                    duration,
                    on_progress=lambda f: set_stage(Stage.verifying, f, f"音频指纹核对 {f:.0%}"),
                    should_cancel=ctx.is_cancelled,
                )
            finally:
                await fp.close()
            if ctx.is_cancelled():
                raise JobCancelled()
    finally:
        await client.aclose()

    note = ""
    if job.options.shazam and skipped:
        note = "（音频指纹服务限流，部分核对已跳过）"
    job.stage, job.progress, job.message = Stage.done, 1.0, f"完成：识别出 {len(job.timeline)} 首{note}"
    await ctx.update(job)
    return job


def fmt_time(sec: float) -> str:
    s = int(sec)
    return f"{s // 3600}:{s % 3600 // 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60:02d}:{s % 60:02d}"
