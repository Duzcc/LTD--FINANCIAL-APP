from __future__ import annotations

import calendar
import re
import unicodedata
from datetime import datetime

_NUM_RE = re.compile(r"\d+(?:[.,]\d+)*")
_NON_WORD = re.compile(r"[^0-9a-zA-ZÀ-ỹ\s]+")
_SPACES = re.compile(r"\s+")

ABBREVIATIONS = {
    "cf": "cà phê", "cafe": "cà phê", "coffee": "cà phê", "ck": "chuyển khoản",
    "tt": "thanh toán", "sv": "sinh viên", "nv": "nhân viên", "dt": "điện thoại",
    "đt": "điện thoại", "ko": "không", "k0": "không", "mn": "mọi người",
    "bh": "bảo hiểm", "hp": "học phí", "ts": "trà sữa", "bn": "bao nhiêu",
    "sn": "sinh nhật", "đc": "được", "dc": "được", "lg": "lương",
}


def calendar_date(year: int, month: int, day: int, hour: int = 0) -> datetime | None:
    # Người dùng hay gõ ngày không có thật (31/11, 29/2 năm thường): trả về None thay vì báo lỗi.
    if 1 <= month <= 12 and 1 <= day <= calendar.monthrange(year, month)[1]:
        return datetime(year, month, day, hour)
    return None


def fold(text: str) -> str:
    text = unicodedata.normalize("NFD", text.lower())
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Mn")
    return text.replace("đ", "d")


def normalize(text: str, *, keep_numbers: bool = False) -> str:
    text = unicodedata.normalize("NFC", text or "").lower().strip()
    if not keep_numbers:
        text = _NUM_RE.sub(" 0 ", text)
    text = _NON_WORD.sub(" ", text)
    words = [ABBREVIATIONS.get(w, w) for w in _SPACES.split(text) if w]
    return " ".join(words)


def model_text(text: str) -> str:
    n = normalize(text)
    f = fold(n)
    return n if n == f else f"{n} | {f}"


def fold_keep_numbers(text: str) -> str:
    t = fold(unicodedata.normalize("NFC", text or ""))
    t = re.sub(r"[^a-z0-9.,/]+", " ", t)
    t = re.sub(r"(?<!\d)[.,]|[.,](?!\d)", " ", t)
    return _SPACES.sub(" ", t).strip()
