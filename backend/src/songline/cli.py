"""Command line: `songline run <url>` or `songline serve`."""

from __future__ import annotations

import asyncio
import json
import logging
import time
import webbrowser

import typer
from rich.console import Console
from rich.progress import BarColumn, Progress, TextColumn, TimeElapsedColumn
from rich.table import Table

from . import pipeline
from .cache import KVCache
from .config import settings
from .models import Job, JobOptions

app = typer.Typer(add_completion=False, help="识别 B 站视频里唱了哪些歌，输出时间线。")
console = Console()


def _fmt(sec: float) -> str:
    return pipeline.fmt_time(sec)


@app.command()
def run(
    url: str = typer.Argument(..., help="B 站视频链接 / BV 号 / b23.tv 短链"),
    shazam: bool = typer.Option(True, help="用音频指纹交叉核对"),
    as_json: bool = typer.Option(False, "--json", help="输出 JSON"),
) -> None:
    """识别一个视频并打印时间线。"""
    logging.basicConfig(level=logging.WARNING)
    settings.ensure_dirs()
    now = time.time()
    job = Job(id="cli", url=url, options=JobOptions(shazam=shazam), created_at=now, updated_at=now)

    with Progress(TextColumn("{task.description}"), BarColumn(), TextColumn("{task.percentage:>3.0f}%"), TimeElapsedColumn(), console=console, transient=True) as bar:
        task = bar.add_task("准备中", total=1.0)

        async def update(j: Job) -> None:
            bar.update(task, completed=j.progress, description=j.message)

        ctx = pipeline.Context(update=update, is_cancelled=lambda: False, cache=KVCache(settings.data_dir / "cache.db"))
        asyncio.run(pipeline.run(job, ctx))

    if as_json:
        print(json.dumps([e.model_dump() for e in job.timeline], ensure_ascii=False, indent=2))
        return
    v = job.video
    console.print(f"[bold]{v.title}[/]  ·  {v.owner}  ·  {_fmt(v.duration)}\n")
    t = Table(show_header=True, header_style="bold")
    for col in ("时间", "歌曲", "原唱", "可信度", "依据"):
        t.add_column(col)
    for e in job.timeline:
        t.add_row(
            f"{_fmt(e.start)}–{_fmt(e.end)}",
            e.song.title if e.song else "未识别",
            e.song.artist if e.song else "",
            f"{e.confidence:.0%}",
            " ".join({"lyrics": "歌词", "shazam": "指纹", "spoken": "口播"}[s] for s in e.sources),
        )
    console.print(t)


@app.command()
def serve(
    host: str = "127.0.0.1",
    port: int = 8765,
    open_browser: bool = typer.Option(True, "--open/--no-open"),
) -> None:
    """启动本地网页版。"""
    import uvicorn

    from .api import create_app

    if open_browser:
        import threading

        threading.Timer(1.2, lambda: webbrowser.open(f"http://{host}:{port}")).start()
    uvicorn.run(create_app(), host=host, port=port, log_level="warning")


def main() -> None:
    app()
