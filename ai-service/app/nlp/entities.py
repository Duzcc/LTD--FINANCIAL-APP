"""Trích xuất thực thể từ câu tiếng Việt: số tiền, ngày giờ, tên người."""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timedelta

from .text import fold, fold_keep_numbers

_AMOUNT = re.compile(
    r"(\d+(?:[.,]\d+)*)\s*(k|nghin|ngan|ng|tr|trieu|cu|ty|ti|d|dong|vnd|usd|\$)?(\d{1,3})?\b"
)
_CLASSIFIER = re.compile(r"\s*(ly|cai|chiec|nguoi|phan|lan|ve|goi|hop|chai|cuon|bat|to|dia|suat|kg|km|gio|ngay|thang)\b")
_UNIT = {"k": 1e3, "nghin": 1e3, "ngan": 1e3, "ng": 1e3, "tr": 1e6, "trieu": 1e6, "cu": 1e6, "ty": 1e9, "ti": 1e9}


@dataclass
class Amount:
    value: float
    start: int
    end: int
    explicit_unit: bool


def find_amount(text: str) -> Amount | None:
    """Đọc số tiền: '45k', '1tr2', '1,5tr', '200.000', '2 triệu', 'phở 45' (hiểu là 45.000).

    Ưu tiên số có đơn vị khi câu có nhiều số ("2 ly cà phê 60k" -> 60.000).
    """
    f = fold_keep_numbers(text)
    unitless: Amount | None = None
    for m in _AMOUNT.finditer(f):
        raw, unit, tail = m.group(1), m.group(2), m.group(3)
        before = f[: m.start()]
        after = f[m.end():]
        if unit not in _UNIT and re.search(r"(ngay|thang|luc|gio)\s*$", before):
            continue
        if unit is None and _CLASSIFIER.match(after):
            continue
        if m.end() < len(f) and f[m.end()] == "/":
            continue
        if m.start() > 0 and f[m.start() - 1] == "/":
            continue
        if unit in _UNIT:
            base = float(raw.replace(",", "."))
            value = base * _UNIT[unit]
            if tail:
                value += float(f"0.{tail}") * _UNIT[unit]
            if value > 0:
                return Amount(value, m.start(), m.end(), True)
            continue
        grouped = re.fullmatch(r"\d{1,3}([.,]\d{3})+", raw) is not None
        value = float(re.sub(r"[.,]", "", raw) if grouped else raw.replace(",", "."))
        if unit is None and value < 1000:
            value *= 1000
        if value <= 0:
            continue
        if unit is not None or grouped:
            return Amount(value, m.start(), m.end(), unit is not None)
        if unitless is None:
            unitless = Amount(value, m.start(), m.end(), False)
    return unitless


def find_date(text: str, now: datetime) -> tuple[datetime, bool]:
    """Ngày giao dịch: hôm nay/qua/kia, 'ngày 5', '5/10', buổi sáng/trưa/chiều/tối. Trả về (ngày, có_nhắc_ngày)."""
    f = fold_keep_numbers(text)
    date = now.replace(second=0, microsecond=0)
    mentioned = False
    if re.search(r"\bhom kia\b", f):
        date -= timedelta(days=2)
        mentioned = True
    elif re.search(r"\b(hom qua|toi qua|dem qua|trua qua|sang qua|chieu qua)\b", f):
        date -= timedelta(days=1)
        mentioned = True
    else:
        dm = re.search(r"\b(\d{1,2})\s*/\s*(\d{1,2})(?:\s*/\s*(\d{2,4}))?\b", f)
        day = re.search(r"\bngay\s+(\d{1,2})\b", f)
        try:
            if dm:
                d, mth = int(dm.group(1)), int(dm.group(2))
                y = int(dm.group(3)) if dm.group(3) else now.year
                y = y + 2000 if y < 100 else y
                cand = datetime(y, mth, d, 12)
                if not dm.group(3) and cand > now + timedelta(days=1):
                    cand = cand.replace(year=y - 1)
                date, mentioned = cand, True
            elif day:
                d = int(day.group(1))
                cand = datetime(now.year, now.month, d, 12)
                if cand > now + timedelta(days=1):
                    prev_month = (now.replace(day=1) - timedelta(days=1))
                    cand = datetime(prev_month.year, prev_month.month, d, 12)
                date, mentioned = cand, True
        except ValueError:
            pass
    hour = None
    if re.search(r"\bsang\b", f):
        hour = 8
    elif re.search(r"\btrua\b", f):
        hour = 12
    elif re.search(r"\bchieu\b", f):
        hour = 16
    elif re.search(r"\b(toi|dem)\b", f):
        hour = 20
    if hour is not None:
        date = date.replace(hour=hour, minute=0)
        mentioned = True
    return date, mentioned


_PRONOUNS = {"nợ", "tiền", "cho", "của", "lãi", "mình", "tôi", "em", "anh", "chị", "bạn", "tao", "nó", "ai", "người"}


def original_words(text: str) -> list[str]:
    return [w for w in re.split(r"[^0-9A-Za-zÀ-ỹĐđ]+", text) if w]


def restore_name(text: str, folded_name: str) -> str | None:
    """Lấy lại tên có dấu từ câu gốc ('binh' -> 'Bình'); None nếu là đại từ ('mình')."""
    words = original_words(text)
    parts = folded_name.split()
    for i in range(len(words) - len(parts) + 1):
        if all(fold(words[i + j]) == parts[j] for j in range(len(parts))):
            chunk = words[i : i + len(parts)]
            if " ".join(chunk).lower() in _PRONOUNS:
                return None
            return " ".join(w[:1].upper() + w[1:] for w in chunk)
    return None


def find_person(text: str, known: list[dict]) -> tuple[str | None, str | None]:
    """(id người đã có, tên người mới) xuất hiện trong câu."""
    f = fold(text)
    for p in sorted(known, key=lambda p: -len(p.get("name", ""))):
        n = fold(p.get("name", "")).strip()
        if n and p.get("id") != "self" and re.search(rf"\b{re.escape(n)}\b", f):
            return p["id"], None
    patterns = [
        r"\bcho\s+([a-z]+(?:\s[a-z]+)?)\s+(?:muon|vay)\b",
        r"\b(?:muon|vay)\s+(?:cua\s+|tien\s+)?([a-z]+)\b",
        r"\btra\s+(?:no\s+|tien\s+)?(?:cho\s+)?([a-z]+)\b",
        r"\b(?:thu no|doi no)\s+([a-z]+)\b",
        r"\b([a-z]+)\s+tra\s+(?:no|tien)\b",
    ]
    for pat in patterns:
        m = re.search(pat, f)
        if m:
            name = restore_name(text, m.group(1))
            if name:
                return None, name
    return None, None
