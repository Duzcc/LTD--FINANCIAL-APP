"""Tìm kiếm giao dịch bằng ngôn ngữ tự nhiên.

"tiền cafe tháng trước trên 50k" -> lọc thời gian + số tiền + xếp hạng ngữ nghĩa.
Xếp hạng: độ giống cosine trên đặc trưng TF-IDF (từ + ký tự) của mô hình danh mục,
mở rộng truy vấn bằng từ đồng nghĩa và cộng điểm khi danh mục dự đoán của truy vấn trùng danh mục giao dịch.
"""
from __future__ import annotations

import calendar
import re
from dataclasses import dataclass
from datetime import datetime, timedelta

from sklearn.preprocessing import normalize as l2

from app.nlp.entities import find_amount
from app.nlp.text import fold, fold_keep_numbers
from app.schemas.common import EXPENSE_KINDS, INCOME_KINDS, Category, Transaction

from .categorizer import get_categorizer

SYNONYMS = {
    "cafe": "cà phê cafe cf coffee highlands phúc long starbucks",
    "ca phe": "cà phê cafe cf coffee",
    "an": "ăn cơm phở bún bữa trưa bữa tối nhà hàng quán",
    "xang": "xăng đổ xăng petrolimex",
    "grab": "grab be gojek taxi xe ôm",
    "dien": "điện tiền điện evn",
    "nuoc": "nước tiền nước",
    "luong": "lương nhận lương salary",
    "sieu thi": "siêu thị winmart coopmart bách hóa xanh big c",
    "thuoc": "thuốc nhà thuốc pharmacity long châu",
}


@dataclass
class SearchFilters:
    start: datetime | None = None
    end: datetime | None = None
    min_amount: float | None = None
    max_amount: float | None = None
    kinds: set[str] | None = None
    text: str = ""


def parse_query(query: str, now: datetime) -> SearchFilters:
    f = fold_keep_numbers(query)
    flt = SearchFilters()
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    month_start = today.replace(day=1)
    rules = [
        (r"\bhom nay\b", today, today + timedelta(days=1)),
        (r"\bhom qua\b", today - timedelta(days=1), today),
        (r"\btuan nay\b", today - timedelta(days=today.weekday()), today + timedelta(days=1)),
        (r"\btuan (truoc|roi)\b", today - timedelta(days=today.weekday() + 7), today - timedelta(days=today.weekday())),
        (r"\bthang nay\b", month_start, today + timedelta(days=1)),
        (r"\bnam nay\b", today.replace(month=1, day=1), today + timedelta(days=1)),
    ]
    for pattern, s, e in rules:
        if re.search(pattern, f):
            flt.start, flt.end = s, e
            f = re.sub(pattern, " ", f)
            break
    else:
        if re.search(r"\bthang (truoc|roi)\b", f):
            prev_end = month_start
            prev_start = (month_start - timedelta(days=1)).replace(day=1)
            flt.start, flt.end = prev_start, prev_end
            f = re.sub(r"\bthang (truoc|roi)\b", " ", f)
        elif m := re.search(r"\bthang (\d{1,2})\b", f):
            mth = int(m.group(1))
            if 1 <= mth <= 12:
                year = today.year if mth <= today.month else today.year - 1
                flt.start = datetime(year, mth, 1, tzinfo=today.tzinfo)
                flt.end = flt.start + timedelta(days=calendar.monthrange(year, mth)[1])
                f = f.replace(m.group(0), " ")
        elif m := re.search(r"\b(\d{1,3}) ngay (qua|gan day|truoc)\b", f):
            flt.start, flt.end = today - timedelta(days=int(m.group(1)) - 1), today + timedelta(days=1)
            f = f.replace(m.group(0), " ")

    amount_patterns = [
        (r"\b(tren|hon|lon hon|>|tu)\s*", "min"),
        (r"\b(duoi|it hon|nho hon|<|toi da)\s*", "max"),
    ]
    for prefix, which in amount_patterns:
        m = re.search(prefix + r"(?P<amt>\d[\d.,]*\s*(k|tr|trieu|nghin|ngan|d)?)\b", f)
        if m:
            a = find_amount(m.group("amt"))
            if a:
                setattr(flt, f"{which}_amount", a.value)
                f = f.replace(m.group(0), " ")
    if re.search(r"\b(thu|thu nhap|nhan)\b", f) and not re.search(r"\bchi\b", f):
        flt.kinds = set(INCOME_KINDS)
    elif re.search(r"\b(chi|tieu|mua)\b", f):
        flt.kinds = set(EXPENSE_KINDS)
    if re.search(r"\b(vay|no|muon)\b", f):
        flt.kinds = {"lend", "collect", "borrow", "repay", "interestIncome", "interestExpense"}
    stop = r"\b(tien|giao dich|khoan|cac|nhung|tim|cho toi|xem|chi|tieu|thu|o|cua|va|toi|minh)\b"
    flt.text = re.sub(r"\s+", " ", re.sub(stop, " ", f)).strip()
    return flt


def search(query: str, transactions: list[Transaction], categories: list[Category], now: datetime,
           limit: int = 30) -> tuple[SearchFilters, list[tuple[Transaction, float]]]:
    flt = parse_query(query, now)
    pool = []
    for t in transactions:
        d = t.date if t.date.tzinfo or not now.tzinfo else t.date.replace(tzinfo=now.tzinfo)
        if flt.start and d < flt.start or flt.end and d >= flt.end:
            continue
        if flt.min_amount is not None and t.amount < flt.min_amount:
            continue
        if flt.max_amount is not None and t.amount > flt.max_amount:
            continue
        if flt.kinds and t.kind not in flt.kinds:
            continue
        pool.append(t)
    if not pool:
        return flt, []
    if not flt.text:
        return flt, [(t, 1.0) for t in sorted(pool, key=lambda t: t.date, reverse=True)[:limit]]

    expanded = flt.text + " " + " ".join(v for k, v in SYNONYMS.items() if k in flt.text)
    cat_names = {c.id: c.name for c in categories}
    cz = get_categorizer()
    docs = [f"{t.note} {cat_names.get(t.categoryId or '', '')}" for t in pool]
    mat = l2(cz.features.transform(docs))
    q = l2(cz.features.transform([expanded]))
    sims = (mat @ q.T).toarray().ravel()

    # Danh mục người dùng gõ trực tiếp ("ăn uống tháng này")
    named = {c.id for c in categories if fold(c.name) in flt.text}
    preds, _ = cz.predict(expanded, categories)
    predicted = preds[0].category_id if preds and preds[0].probability > 0.5 else None
    scored = []
    for t, s in zip(pool, sims, strict=False):
        score = float(s)
        if t.categoryId in named:
            score += 0.6
        elif predicted and t.categoryId == predicted and score >= 0.05:
            score += 0.25  # chỉ cộng khi bản thân ghi chú đã có liên quan
        if score >= 0.12:
            scored.append((t, round(min(1.0, score), 3)))
    scored.sort(key=lambda x: (-x[1], -x[0].date.timestamp()))
    return flt, scored[:limit]
