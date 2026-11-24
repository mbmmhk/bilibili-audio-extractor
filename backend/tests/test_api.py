import json

import pytest

from fastapi.testclient import TestClient

from songline import api, jobs
from songline.config import Settings
from songline.models import Job, JobOptions, Stage, VideoInfo


def _app(tmp_path, monkeypatch):
    s = Settings(data_dir=tmp_path)
    monkeypatch.setattr(api, "settings", s)
    s.ensure_dirs()
    return s


def test_transcript_is_read_from_the_file_next_to_the_audio(tmp_path, monkeypatch):
    s = _app(tmp_path, monkeypatch)
    video = VideoInfo(bvid="BV1xx411c7mD", aid=1, cover="", page=1, title="t", owner="o", duration=60)
    job = Job(id="j1", url="u", options=JobOptions(), created_at=0, updated_at=0, video=video, stage=Stage.done)
    jobs.JobStore(s.db_path).save(job)
    (s.audio_dir / "BV1xx411c7mD_p1.segments.json").write_text(
        json.dumps([{"start": 1.0, "end": 2.0, "text": "你好"}], ensure_ascii=False)
    )
    with TestClient(api.create_app()) as c:
        assert c.get("/api/jobs/j1/transcript").json()[0]["text"] == "你好"
        assert c.get("/api/jobs/nope/transcript").status_code == 404


@pytest.mark.asyncio
async def test_subscriber_entries_are_dropped_when_streams_end(tmp_path):
    store = jobs.JobStore(tmp_path / "db.sqlite")
    job = Job(id="j1", url="u", options=JobOptions(), created_at=0, updated_at=0, stage=Stage.done)
    store.save(job)
    m = jobs.JobManager(store, cache=None)
    got = [j async for j in m.subscribe("j1")]
    assert [j.id for j in got] == ["j1"]
    assert m._subs == {}
