from songline.fingerprint import Hit, merge_hits, plan_probes
from songline.models import SongRef, TimelineEntry


def entry(start, end, title, conf=0.5):
    return TimelineEntry(start=start, end=end, song=SongRef(title=title, artist="x"), confidence=conf, sources=["lyrics"])


def test_corroborating_hit_adds_source_and_confidence():
    out = merge_hits([entry(0, 200, "生分")], [Hit(100, "生分 (伴奏)", "川青")])
    assert out[0].sources == ["lyrics", "shazam"]
    assert out[0].confidence > 0.5


def test_disagreeing_hit_becomes_alternative_for_weak_match():
    out = merge_hits([entry(0, 200, "你我怎么两清", 0.4)], [Hit(100, "甲乙丙丁", "李佳薇")])
    assert out[0].alternatives[0].title == "甲乙丙丁"


def test_two_gap_hits_create_a_new_entry_single_hit_does_not():
    hits = [Hit(400, "消失的恋人", "江堇"), Hit(460, "消失的恋人", "江堇"), Hit(900, "Heliophobia", "Lee")]
    out = merge_hits([entry(0, 200, "生分")], hits)
    assert [e.song.title for e in out] == ["生分", "消失的恋人"]
    assert out[1].sources == ["shazam"]


def test_probes_skip_confident_entries_and_sweep_gaps():
    pts = plan_probes([entry(0, 200, "a", 0.95), entry(600, 800, "b", 0.4)], 1000)
    assert not any(0 <= p <= 200 for p in pts)  # confident: no probe
    assert any(600 <= p <= 800 for p in pts)  # weak: probed
    assert any(200 < p < 600 for p in pts)  # long gap: swept
