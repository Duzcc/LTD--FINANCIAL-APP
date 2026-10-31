"""Phát hiện giao dịch bất thường.

Ba lớp tín hiệu, mỗi giao dịch nhận điểm 0..1 và lý do dễ hiểu:
1. Số tiền lớn bất thường so với chính danh mục đó: z-score bền vững
   z = 0.6745·(x − median) / MAD trên log(số tiền) (ít bị ảnh hưởng bởi ngoại lai).
2. Isolation Forest (scikit-learn) trên đặc trưng [log số tiền, giờ, thứ, mã danh mục]
   khi người dùng có ≥ 40 khoản chi — bắt các tổ hợp lạ (ví dụ chi lớn lúc 3h sáng).
3. Trùng lặp: cùng số tiền, cùng danh mục/ghi chú trong vòng 10 phút (nhập hai lần).
Ngoài ra so sánh chi tiêu từng danh mục trong 30 ngày với trung bình 3 tháng trước (tăng đột biến).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta

import numpy as np
from sklearn.ensemble import IsolationForest

from app.nlp.text import fold
from app.schemas.common import EXPENSE_KINDS, Transaction


@dataclass
class Anomaly:
    transaction_id: str
    score: float
    reasons: list[str] = field(default_factory=list)
    kind: str = "amount"


@dataclass
class CategorySpike:
    category_id: str
    recent: float
    baseline: float
    ratio: float


def _robust_z(values: np.ndarray, x: float) -> float:
    med = float(np.median(values))
    mad = float(np.median(np.abs(values - med)))
    if mad < 1e-9:
        return 0.0 if abs(x - med) < 1e-9 else 6.0 * np.sign(x - med)
    return 0.6745 * (x - med) / mad


def detect(transactions: list[Transaction], now: datetime, lookback_days: int = 30,
           categories: dict[str, str] | None = None) -> tuple[list[Anomaly], list[CategorySpike]]:
    names = categories or {}
    expenses = sorted((t for t in transactions if t.kind in EXPENSE_KINDS and not t.excluded and t.amount > 0),
                      key=lambda t: t.date)
    since = now - timedelta(days=lookback_days)
    found: dict[str, Anomaly] = {}

    priority = {"pattern": 0, "amount": 1, "duplicate": 2}

    def add(t: Transaction, score: float, reason: str, kind: str) -> None:
        a = found.setdefault(t.id, Anomaly(t.id, 0.0, [], kind))
        a.score = max(a.score, round(float(min(1.0, score)), 3))
        if priority[kind] > priority[a.kind]:
            a.kind = kind
        if reason not in a.reasons:
            a.reasons.append(reason)

    # 1) Theo danh mục
    by_cat: dict[str, list[Transaction]] = {}
    for t in expenses:
        by_cat.setdefault(t.categoryId or "_", []).append(t)
    for cid, items in by_cat.items():
        if len(items) < 6:
            continue
        for t in items:
            if t.date < since:
                continue
            others = np.log1p([o.amount for o in items if o.id != t.id])
            z = _robust_z(others, float(np.log1p(t.amount)))
            median = float(np.expm1(np.median(others)))
            ratio = t.amount / max(median, 1)
            if z >= 3.5 and ratio >= 2.5 and t.amount - median >= 50_000:
                add(t, 0.5 + min(0.5, (z - 3.5) / 7),
                    f"Cao gấp {ratio:.1f} lần mức thường chi cho {names.get(cid, 'danh mục này')}", "amount")

    # 2) Isolation Forest
    if len(expenses) >= 40:
        cat_index = {c: i for i, c in enumerate(sorted(by_cat))}
        X = np.array([[np.log1p(t.amount), t.date.hour + t.date.minute / 60, t.date.weekday(),
                       cat_index[t.categoryId or "_"]] for t in expenses])
        forest = IsolationForest(n_estimators=200, contamination=0.03, random_state=0).fit(X)
        scores = -forest.score_samples(X)  # cao = bất thường
        threshold = np.quantile(scores, 0.97)
        big = float(np.quantile([t.amount for t in expenses], 0.75))
        for t, s in zip(expenses, scores, strict=False):
            if t.date >= since and s >= threshold and s > 0.6 and (t.date.hour < 5 or t.amount >= big):
                hour = t.date.hour
                reason = "Khoản chi có tổ hợp thời điểm/số tiền hiếm gặp"
                if hour < 5:
                    reason = f"Khoản chi vào lúc {hour}h sáng, khác thói quen"
                add(t, float(min(1.0, s)), reason, "pattern")

    # 3) Trùng lặp
    for i, t in enumerate(expenses):
        if t.date < since:
            continue
        for o in expenses[max(0, i - 6):i]:
            same_text = fold(o.note).strip() == fold(t.note).strip()
            if (o.amount == t.amount and (o.categoryId == t.categoryId or same_text)
                    and abs((t.date - o.date).total_seconds()) <= 600):
                add(t, 0.8, "Có thể bị nhập trùng (cùng số tiền trong vòng 10 phút)", "duplicate")
                break

    # Danh mục tăng đột biến
    spikes: list[CategorySpike] = []
    for cid, items in by_cat.items():
        recent = sum(t.amount for t in items if t.date >= since)
        base_items = [t for t in items if now - timedelta(days=lookback_days * 4) <= t.date < since]
        if not base_items:
            continue
        baseline = sum(t.amount for t in base_items) / 3
        if baseline > 0 and recent > baseline * 1.5 and recent - baseline >= 200_000:
            spikes.append(CategorySpike(cid, round(recent), round(baseline), round(recent / baseline, 2)))
    spikes.sort(key=lambda s: -s.ratio)
    return sorted(found.values(), key=lambda a: -a.score), spikes
