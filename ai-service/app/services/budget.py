"""Gợi ý ngân sách tháng.

Với mỗi danh mục chi: lấy chuỗi tổng chi theo tháng (tối đa 6 tháng gần nhất, bỏ tháng hiện tại),
đề xuất = trung vị (ổn định) nhưng không thấp hơn phân vị 40, làm tròn lên 50.000đ.
Nếu biết thu nhập tháng: so khung 50/30/20 (thiết yếu / mong muốn / tiết kiệm) và cắt bớt nhóm
"mong muốn" để đạt mục tiêu tiết kiệm.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import date, datetime

import numpy as np

from app.schemas.common import EXPENSE_KINDS, INCOME_KINDS, Category, Transaction

from .categories import NEEDS, global_label_for


@dataclass
class BudgetSuggestion:
    category_id: str
    amount: float
    history_median: float
    months: int
    group: str  # needs | wants
    note: str


def _round_up(x: float, step: int = 50_000) -> float:
    return float(math.ceil(x / step) * step) if x > 0 else 0.0


def _month_key(d: date) -> tuple[int, int]:
    return d.year, d.month


def recommend(transactions: list[Transaction], categories: list[Category], now: datetime,
              monthly_income: float | None = None, savings_rate: float = 0.2) -> dict:
    current = _month_key(now.date())
    months: list[tuple[int, int]] = []
    y, m = current
    for _ in range(6):
        m -= 1
        if m == 0:
            y, m = y - 1, 12
        months.append((y, m))
    first = min((t.date.date() for t in transactions), default=now.date())
    months = [mm for mm in months if mm >= _month_key(first)]

    spend: dict[str, dict[tuple[int, int], float]] = {}
    income_by_month: dict[tuple[int, int], float] = {}
    for t in transactions:
        if t.excluded:
            continue
        k = _month_key(t.date.date())
        if k not in months:
            continue
        if t.kind in EXPENSE_KINDS and t.categoryId:
            spend.setdefault(t.categoryId, {})
            spend[t.categoryId][k] = spend[t.categoryId].get(k, 0.0) + t.amount
        elif t.kind in INCOME_KINDS:
            income_by_month[k] = income_by_month.get(k, 0.0) + t.amount

    if monthly_income is None and income_by_month:
        monthly_income = float(np.median([income_by_month.get(mm, 0.0) for mm in months]))

    suggestions: list[BudgetSuggestion] = []
    for c in categories:
        if c.income or c.id not in spend:
            continue
        series = np.array([spend[c.id].get(mm, 0.0) for mm in months])
        if not series.any():
            continue
        med = float(np.median(series))
        base = max(med, float(np.percentile(series, 40)))
        label = global_label_for(c.id, c.name)
        group = "needs" if label in NEEDS else "wants"
        note = f"Trung vị {len(months)} tháng gần nhất"
        if series.std() > 0.5 * max(series.mean(), 1):
            note += "; chi tiêu dao động mạnh, nên theo dõi thêm"
        suggestions.append(BudgetSuggestion(c.id, _round_up(base), round(med), len(months), group, note))

    total = sum(s.amount for s in suggestions)
    plan = None
    if monthly_income and monthly_income > 0:
        target_spend = monthly_income * (1 - savings_rate)
        needs = sum(s.amount for s in suggestions if s.group == "needs")
        wants = sum(s.amount for s in suggestions if s.group == "wants")
        if total > target_spend and wants > 0:
            cut = min(wants, total - target_spend)
            factor = (wants - cut) / wants
            for s in suggestions:
                if s.group == "wants":
                    s.amount = _round_up(s.amount * factor)
                    s.note += f"; giảm để đạt mục tiêu tiết kiệm {int(savings_rate * 100)}%"
            total = sum(s.amount for s in suggestions)
        plan = {
            "income": round(monthly_income), "needs": round(needs),
            "wants": round(sum(s.amount for s in suggestions if s.group == "wants")),
            "savings": round(monthly_income - total), "target": {"needs": round(monthly_income * 0.5),
                                                                 "wants": round(monthly_income * 0.3),
                                                                 "savings": round(monthly_income * savings_rate)},
        }
    return {"suggestions": suggestions, "total": round(total), "plan": plan, "months": len(months)}
