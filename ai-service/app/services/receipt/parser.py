from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from difflib import SequenceMatcher

from app.nlp.text import calendar_date, fold

_TOTAL_KEYS: list[tuple[str, int]] = [
    ("tong thanh toan", 0),
    ("tong tien thanh toan", 0),
    ("khach phai tra", 0),
    ("khach can tra", 0),
    ("can thanh toan", 0),
    ("phai thanh toan", 0),
    ("grand total", 0),
    ("amount due", 0),
    ("tong cong", 1),
    ("thanh toan", 1),
    ("total", 1),
    ("phai tra", 1),
    ("tong tien", 2),
    ("tong", 3),
    ("cong", 4),
]
_SUBTOTAL = ("tong tien hang", "tam tinh", "subtotal", "cong tien hang", "tien hang")
_CASH = ("tien khach dua", "khach dua", "tien nhan", "khach tra", "cash", "tien mat")
_CHANGE = ("tien thua", "tien thoi", "thoi lai", "tra lai khach", "tien tra lai", "change")
_NOT_ITEM = ("giam gia", "chiet khau", "discount", "vat", "thue", "khuyen mai", "phi dich vu", "service")
_HEADER = ("ten hang", "don gia", "thanh tien", "t.tien", "d.gia", "sl ", "mat hang", "so luong")
_NOT_MERCHANT = (
    "dia chi",
    "dc:",
    "d/c",
    "dt:",
    "dt ",
    "tel",
    "hotline",
    "mst",
    "ma so thue",
    "hoa don",
    "phieu",
    "so hd",
    "ngay",
    "thu ngan",
    "nhan vien",
    "ban hang",
    "www",
    "http",
)
# không có "phiếu thu" vì phiếu thu đưa cho người trả tiền, vẫn là khoản chi
INCOME_MARKERS = (
    "hoan tien",
    "tien hoan",
    "hoan tra",
    "refund",
    "ban da nhan",
    "nhan tien tu",
    "nhan chuyen khoan",
    "ghi co",
    "phieu luong",
    "bang luong",
    "thuc linh",
    "luong thuc nhan",
)
KNOWN_MERCHANTS = (
    "circle k",
    "winmart",
    "bach hoa xanh",
    "highlands",
    "phuc long",
    "co.opmart",
    "coopmart",
    "co.op",
    "7-eleven",
    "gs25",
    "familymart",
    "ministop",
    "lotte",
    "aeon",
    "big c",
    "go!",
    "mm mega",
    "kfc",
    "lotteria",
    "jollibee",
    "pharmacity",
    "long chau",
    "an khang",
    "the coffee house",
    "starbucks",
    "katinat",
    "phuc long",
    "guardian",
    "dien may xanh",
    "the gioi di dong",
    "fahasa",
    "uniqlo",
    "pho thin",
    "bun cha",
    "gong cha",
)

_NUM = re.compile(
    r"(?<![\w.,])(\d{1,3}(?:[.,]\d{3})+|\d{4,9})(?:[.,]0{1,2})?\s*(?:đ|d|vnd|vnđ|dong)?(?![\w])", re.IGNORECASE
)
_DATE_PATTERNS = [
    (re.compile(r"(?<!\d)(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{4}|\d{2})(?!\d)"), "dmy"),
    (re.compile(r"(?<!\d)(\d{4})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{1,2})(?!\d)"), "ymd"),
    (re.compile(r"ngay\s*(\d{1,2})\s*thang\s*(\d{1,2})\s*nam\s*(\d{4})"), "dmy"),
]


@dataclass
class ReceiptItem:
    name: str
    amount: float
    quantity: float | None = None
    unit_price: float | None = None


@dataclass
class ReceiptResult:
    merchant: str | None = None
    total: float | None = None
    date: datetime | None = None
    items: list[ReceiptItem] = field(default_factory=list)
    source: str = "text"
    kind: str = "expense"
    raw_text: str = ""
    confidence: float = 0.0
    checks: list[str] = field(default_factory=list)

    @property
    def note(self) -> str:
        if self.merchant and self.items:
            return f"{self.merchant}: " + ", ".join(i.name for i in self.items[:3])
        return self.merchant or ", ".join(i.name for i in self.items[:3])


def clean_ocr_numbers(line: str) -> str:
    def fix(m: re.Match[str]) -> str:
        tok = m.group(0)
        if not any(c.isdigit() for c in tok):
            return tok
        fixed = tok.translate(
            str.maketrans({"O": "0", "o": "0", "D": "0", "l": "1", "I": "1", "|": "1", "S": "5", "B": "8", "Z": "2"})
        )
        return fixed if re.fullmatch(r"\d{1,3}(?:[.,]\d{3})+|\d{4,}", fixed) else tok

    line = re.sub(r"[0-9OolI|SBZD][0-9OolI|SBZD.,]{2,}[0-9OolI|SBZD]", fix, line)
    line = re.sub(r"(\d)\s+([.,])\s*(\d{3})(?!\d)", r"\1\2\3", line)
    line = re.sub(r"(\d)([.,])\s+(\d{3})(?!\d)", r"\1\2\3", line)
    line = re.sub(r"(?<![\d.,])(\d{1,3}) (\d{3})(?![\d.,]| ?x)", r"\1.\2", line)
    return line


def amounts(line: str) -> list[float]:
    out = []
    for m in _NUM.finditer(line):
        raw = m.group(1)
        grouped = re.fullmatch(r"\d{1,3}([.,]\d{3})+", raw) is not None
        if not grouped and len(raw) >= 9:
            continue
        v = float(re.sub(r"[.,]", "", raw))
        if 500 <= v <= 5e9:
            out.append(v)
    return out


def _has(f: str, keys, fuzzy: bool = False) -> bool:
    if any(k in f for k in keys):
        return True
    if not fuzzy:
        return False
    words = f.split()
    for k in keys:
        n = len(k.split())
        if len(k) < 7:
            continue
        for i in range(len(words) - n + 1):
            if SequenceMatcher(None, " ".join(words[i : i + n]), k).ratio() >= 0.88:
                return True
    return False


def receipt_kind(lines: list[str]) -> str:
    text = " ".join(_key(ln) for ln in lines)
    return "income" if any(k in text for k in INCOME_MARKERS) else "expense"


def _key(line: str) -> str:
    f = fold(line)
    return re.sub(r"(?<=[a-z])0|0(?=[a-z])", "o", f)


def _parse_date(lines: list[str]) -> datetime | None:
    now = datetime.now()
    for ln in lines:
        f = fold(ln)
        for pat, order in _DATE_PATTERNS:
            for m in pat.finditer(f):
                a, b, c = (int(x) for x in m.groups())
                d, mth, y = (a, b, c) if order == "dmy" else (c, b, a)
                y = y + 2000 if y < 100 else y
                if not (2000 <= y <= now.year + 1):
                    continue
                dt = calendar_date(y, mth, d)
                if dt is None:
                    continue
                t = re.search(r"(\d{1,2})[:h](\d{2})", f[m.end() : m.end() + 12])
                if t and int(t.group(1)) < 24 and int(t.group(2)) < 60:
                    dt = dt.replace(hour=int(t.group(1)), minute=int(t.group(2)))
                return dt
    return None


def _merchant(lines: list[str]) -> str | None:
    top = lines[:8]
    for ln in top:
        f = _key(ln)
        for k in KNOWN_MERCHANTS:
            if k in f:
                return ln.strip(" -*:=#")[:60]
    for ln in top[:5]:
        f = _key(ln)
        letters = sum(c.isalpha() for c in f)
        if letters >= 3 and not amounts(ln) and not _has(f, _NOT_MERCHANT) and not re.search(r"\d{5,}", ln):
            return ln.strip(" -*:=#")[:60]
    return None


def _quantity(line: str, vals: list[float]) -> tuple[float | None, float | None]:
    if len(vals) >= 2:
        unit, amount = vals[-2], vals[-1]
        count = amount / unit
        if unit <= amount and count == int(count) and count <= 99:
            return count, unit
    m = re.search(r"(?<![\d.,])(\d{1,3})\s*[xX*]\s*[\d.,]+", line)
    if m and vals and int(m.group(1)) > 0:
        return float(m.group(1)), round(vals[-1] / int(m.group(1)))
    return None, None


def parse_receipt_text(text: str) -> ReceiptResult:
    lines = [clean_ocr_numbers(ln.strip()) for ln in text.splitlines() if ln.strip()]
    r = ReceiptResult(raw_text=text, merchant=_merchant(lines), date=_parse_date(lines), kind=receipt_kind(lines))

    cash = change = subtotal = discount = None
    candidates: list[tuple[int, int, float]] = []
    first_summary = len(lines)
    for i, ln in enumerate(lines):
        f = _key(ln)
        vals = amounts(ln)
        if not vals and i + 1 < len(lines) and not re.search(r"[a-z]{3}", _key(lines[i + 1])):
            vals = amounts(lines[i + 1])
        exact = _has(f, _CHANGE) or _has(f, _CASH) or _has(f, _SUBTOTAL)
        fz = not exact
        if _has(f, _CHANGE, fuzzy=fz):
            change = vals[-1] if vals else change
            first_summary = min(first_summary, i)
            continue
        if _has(f, _CASH, fuzzy=fz) and not _has(f, ("thanh toan bang", "hinh thuc")):
            cash = vals[-1] if vals else cash
            first_summary = min(first_summary, i)
            continue
        if _has(f, _SUBTOTAL, fuzzy=fz):
            subtotal = vals[-1] if vals else subtotal
            first_summary = min(first_summary, i)
            continue
        if _has(f, _NOT_ITEM):
            if _has(f, ("giam gia", "chiet khau", "khuyen mai", "discount")) and vals:
                discount = (discount or 0) + vals[-1]
            first_summary = min(first_summary, i) if i > 2 else first_summary
            continue
        for key, rank in _TOTAL_KEYS:
            if re.search(rf"(?<![a-z]){re.escape(key)}(?![a-z])", f) and vals:
                candidates.append((rank, i, vals[-1]))
                first_summary = min(first_summary, i)
                break

    header_end = next((i for i, ln in enumerate(lines[:first_summary]) if _has(_key(ln) + " ", _HEADER)), -1)
    start = header_end + 1 if header_end >= 0 else 0
    pending_name: str | None = None
    for ln in lines[start:first_summary]:
        f = _key(ln)
        vals = amounts(ln)
        name = re.sub(r"[\d.,]+\s*(đ|d|vnd)?\s*$", "", ln).strip(" .:-*")
        name = re.sub(r"\s+\d+\s*[xX*]?\s*[\d.,]*\s*$", "", name).strip(" .:-*")
        has_text = len(re.findall(r"[a-z]", f)) >= 2
        if _has(f, _NOT_MERCHANT + _NOT_ITEM) or (r.merchant and ln.startswith(r.merchant)) or set(ln) <= set("-=_*. "):
            pending_name = None
            continue
        qty, unit = _quantity(ln, vals)
        if vals and has_text and len(re.sub(r"[^A-Za-zÀ-ỹ]", "", name)) >= 2:
            r.items.append(ReceiptItem(name[:60], vals[-1], qty, unit))
            pending_name = None
        elif vals and pending_name:
            r.items.append(ReceiptItem(pending_name[:60], vals[-1], qty, unit))
            pending_name = None
        elif has_text and not vals:
            pending_name = ln.strip(" .:-*")
    items_sum = sum(i.amount for i in r.items)

    sources: list[tuple[str, float, float]] = []
    if candidates:
        best_rank = min(c[0] for c in candidates)
        for rank, _, v in candidates:
            if rank == best_rank:
                sources.append(("dòng TỔNG", v, 3.0 if rank <= 1 else 2.0))
    if cash and change is not None and cash > change:
        sources.append(("tiền khách đưa − tiền thừa", cash - change, 2.0))
    if subtotal:
        sources.append(
            (
                "tổng tiền hàng − giảm giá" if discount else "tổng tiền hàng",
                subtotal - (discount or 0),
                2.0 if discount else 1.5,
            )
        )
    if len(r.items) >= 2:
        sources.append(("tổng các dòng hàng", items_sum - (discount or 0), 1.5))

    def variants(v: float) -> list[tuple[float, float]]:
        out = [(v, 1.0)]
        if v >= 10_000 and v % 500:
            digits = str(int(v))
            tail = re.sub("[3689]", "0", digits[-3:])
            if tail != digits[-3:]:
                out.append((float(digits[:-3] + tail), 0.9))
            out.append((round(v / 1000) * 1000, 0.8))
        return out

    votes: dict[float, float] = {}
    supporters: dict[float, set[str]] = {}
    for name, v, w in sources:
        for value, k in variants(v):
            key = float(round(value))
            votes[key] = votes.get(key, 0.0) + w * k
            supporters.setdefault(key, set()).add(name)
    confidence = 0.0
    if votes:
        best_value = max(votes, key=lambda x: (votes[x], x % 500 == 0))
        r.total = best_value
        agree = supporters[best_value]
        total_weight = sum(w for _, _, w in sources)
        confidence = 0.35 + 0.5 * votes[best_value] / total_weight + (0.1 if len(agree) >= 2 else 0.0)
        r.checks = sorted(agree)
    if r.total is None:
        allv = [v for ln in lines for v in amounts(ln) if not cash or v < cash]
        if allv:
            r.total, confidence = max(allv), 0.25
            r.checks = ["số lớn nhất trên hóa đơn"]
    if r.date:
        confidence += 0.03
    if r.merchant:
        confidence += 0.02
    r.confidence = round(min(1.0, confidence), 2)
    return r
