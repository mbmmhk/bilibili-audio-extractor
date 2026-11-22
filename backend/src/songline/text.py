"""Chinese text normalisation shared by transcript cleaning and lyric matching."""

from __future__ import annotations

import re
from functools import lru_cache

from opencc import OpenCC

_t2s = OpenCC("t2s")

_PUNCT = re.compile(r"[\s\W_]+", re.UNICODE)

# Whisper hallucinates these on music / silence (subtitle credits, outros).
_HALLUCINATIONS = re.compile(
    r"作曲|作词|编曲|词曲|字幕|感谢观看|谢谢观看|请不吝|点赞|订阅|转发|打赏|明镜|栏目|中文字幕|Zither Harp|Amara",
    re.IGNORECASE,
)

# Version tags that should not split one song into several.
_VERSION_TAGS = re.compile(
    r"[\(（\[【][^\)）\]】]*[\)）\]】]"
    r"|[-－—]\s*(dj|live|伴奏|女版|男版|翻唱|cover).*$"
    r"|\s*(r&b|rnb|dj.*|remix|live|伴奏|女版|男版|0\.\d+x|加速版?|慢速版?|降调版?|升调版?)\s*$",
    re.IGNORECASE,
)


@lru_cache(maxsize=65536)
def to_simplified(s: str) -> str:
    return _t2s.convert(s)


def norm(s: str) -> str:
    """Simplified, lower-case, no punctuation/whitespace."""
    return _PUNCT.sub("", to_simplified(s)).lower()


def is_hallucination(s: str) -> bool:
    return bool(_HALLUCINATIONS.search(s))


def title_key(title: str) -> str:
    """Key used to decide that two NetEase hits are the same song."""
    return norm(_VERSION_TAGS.sub("", to_simplified(title))) or norm(title)


def clean_title(title: str) -> str:
    t = _VERSION_TAGS.sub("", to_simplified(title)).strip()
    return t or title
