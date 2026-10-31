"""Dự báo chi tiêu.

1. Cuối tháng hiện tại (theo ngày):
   - Hồ sơ theo thứ trong tuần: trung bình cắt tỉa (trimmed mean) chi tiêu từng thứ trong 8 tuần gần nhất.
   - Hệ số mức (level) của tháng này = thực chi / kỳ vọng theo hồ sơ, co về 1 khi mới đầu tháng.
   - Mô hình Holt (làm trơn hàm mũ kép) trên tổng chi theo tuần khi có ≥ 8 tuần, lấy trung bình hai cách.
   - Tách khoản lớn (> 4 × trung vị): khoản định kỳ (tiền nhà, học phí — lặp lại hằng tháng) được cộng
     nếu chưa tới ngày; khoản bất chợt được cộng theo tần suất kỳ vọng 90 ngày.
   - Khoảng dự báo 80% từ độ lệch chuẩn phần dư theo ngày (theo √số ngày còn lại).
   Kiểm định lùi (ml/evaluate_forecaster.py): MAPE 19,2% so với 47,7% của cách chia đều (run-rate).
2. Tháng tới (theo tháng): Holt-Winters cộng tính mùa vụ 12 tháng khi có ≥ 24 tháng,
   Holt tuyến tính khi có ≥ 4 tháng, ngược lại trung bình.
Tham số làm trơn được chọn bằng tìm kiếm lưới cực tiểu sai số dự báo một bước (SSE).
"""
from __future__ import annotations

import calendar
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from itertools import product

import numpy as np

from app.schemas.common import EXPENSE_KINDS, Transaction


# ---------------------------------------------------------------- mô hình làm trơn hàm mũ
def holt_forecast(y: np.ndarray, horizon: int) -> tuple[np.ndarray, float]:
    """Holt tuyến tính (level + trend). Trả về (dự báo, sai số chuẩn một bước)."""
    best = (np.inf, None)
    for a, b in product((0.1, 0.2, 0.3, 0.5, 0.7, 0.9), (0.01, 0.05, 0.1, 0.2, 0.3)):
        level, trend, sse = y[0], (y[1] - y[0]) if len(y) > 1 else 0.0, 0.0
        for t in range(1, len(y)):
            pred = level + trend
            sse += (y[t] - pred) ** 2
            new_level = a * y[t] + (1 - a) * (level + trend)
            trend = b * (new_level - level) + (1 - b) * trend
            level = new_level
        if sse < best[0]:
            best = (sse, (level, trend))
    level, trend = best[1]
    sigma = float(np.sqrt(best[0] / max(1, len(y) - 2)))
    return np.array([level + (h + 1) * trend for h in range(horizon)]), sigma


def holt_winters_forecast(y: np.ndarray, period: int, horizon: int) -> tuple[np.ndarray, float]:
    """Holt-Winters cộng tính (level + trend + mùa vụ)."""
    best = (np.inf, None)
    init_season = y[:period] - y[:period].mean()
    for a, b, g in product((0.1, 0.3, 0.5, 0.8), (0.01, 0.1, 0.2), (0.05, 0.2, 0.4)):
        level, trend = y[:period].mean(), (y[period:2 * period].mean() - y[:period].mean()) / period
        season = list(init_season)
        sse = 0.0
        for t in range(period, len(y)):
            s = season[t - period]
            pred = level + trend + s
            sse += (y[t] - pred) ** 2
            new_level = a * (y[t] - s) + (1 - a) * (level + trend)
            trend = b * (new_level - level) + (1 - b) * trend
            season.append(g * (y[t] - new_level) + (1 - g) * s)
            level = new_level
        if sse < best[0]:
            best = (sse, (level, trend, season))
    level, trend, season = best[1]
    n = len(y)
    out = np.array([level + (h + 1) * trend + season[n - period + (h % period)] for h in range(horizon)])
    sigma = float(np.sqrt(best[0] / max(1, n - period - 3)))
    return out, sigma


# ---------------------------------------------------------------- tiện ích
def _trimmed_mean(values: list[float], cut: float = 0.15) -> float:
    if not values:
        return 0.0
    v = np.sort(np.asarray(values))
    k = int(len(v) * cut)
    return float(v[k:len(v) - k].mean()) if len(v) > 2 * k else float(v.mean())


def daily_expense(transactions: list[Transaction], category_id: str | None = None) -> dict[date, float]:
    out: dict[date, float] = {}
    for t in transactions:
        if t.excluded or t.kind not in EXPENSE_KINDS:
            continue
        if category_id and t.categoryId != category_id:
            continue
        d = t.date.date()
        out[d] = out.get(d, 0.0) + t.amount
    return out


@dataclass
class MonthForecast:
    spent: float
    projected: float
    lower: float
    upper: float
    daily_average: float
    days_left: int
    method: str
    by_category: dict[str, dict[str, float]]
    next_month: float | None
    next_month_method: str


def _large_bills(transactions: list[Transaction], today: date, cap: float) -> tuple[float, float]:
    """Khoản lớn (> cap): tách thành định kỳ (tiền nhà, học phí...) và bất chợt.

    Trả về (khoản định kỳ dự kiến còn lại trong tháng, kỳ vọng khoản bất chợt mỗi ngày).
    Định kỳ = xuất hiện ở ≥ 2 trong 3 tháng trước, lệch ngày ≤ 3 và số tiền lệch ≤ 25%.
    """
    month_start = today.replace(day=1)
    big = [t for t in transactions if not t.excluded and t.kind in EXPENSE_KINDS and t.amount > cap]
    prev_months = []
    y, m = today.year, today.month
    for _ in range(3):
        m -= 1
        if m == 0:
            y, m = y - 1, 12
        prev_months.append((y, m))
    def in_month(t, ym):  # noqa: E306
        return (t.date.year, t.date.month) == ym
    recurring_left = 0.0
    recurring_ids: set[str] = set()
    for t in big:
        if not in_month(t, prev_months[0]):
            continue
        matches = [t]
        for ym in prev_months[1:]:
            hit = next((o for o in big if in_month(o, ym) and abs(o.date.day - t.date.day) <= 3
                        and abs(o.amount - t.amount) <= 0.25 * t.amount), None)
            if hit:
                matches.append(hit)
        if len(matches) < 2:
            continue
        recurring_ids.update(x.id for x in matches)
        seen_now = any(o.date.date() >= month_start and abs(o.amount - t.amount) <= 0.25 * t.amount
                       and abs(o.date.day - t.date.day) <= 3 for o in big)
        if not seen_now and t.date.day > today.day:
            recurring_left += float(np.median([x.amount for x in matches]))
    since = today - timedelta(days=90)
    first = min((t.date.date() for t in transactions), default=today)
    window = max(1, (today - max(since, first)).days)
    random_excess = sum(t.amount - cap for t in big if t.id not in recurring_ids and since <= t.date.date() < today)
    return recurring_left, random_excess / window


def forecast_month(transactions: list[Transaction], now: datetime) -> MonthForecast:
    today = now.date()
    days_in_month = calendar.monthrange(today.year, today.month)[1]
    month_start = today.replace(day=1)
    days_left = days_in_month - today.day
    daily = daily_expense(transactions)
    spent = sum(v for d, v in daily.items() if month_start <= d <= today)

    # Ngưỡng "khoản lớn": 4 × trung vị các khoản chi trong 90 ngày (ít nhất 300.000đ)
    recent_amounts = [t.amount for t in transactions if t.kind in EXPENSE_KINDS and not t.excluded
                      and t.date.date() >= today - timedelta(days=90)]
    cap = max(300_000.0, 4 * float(np.median(recent_amounts))) if recent_amounts else float("inf")
    regular: dict[date, float] = {}
    for t in transactions:
        if t.excluded or t.kind not in EXPENSE_KINDS:
            continue
        d = t.date.date()
        regular[d] = regular.get(d, 0.0) + min(t.amount, cap)
    recurring_left, excess_per_day = _large_bills(transactions, today, cap) if recent_amounts else (0.0, 0.0)

    # Hồ sơ theo thứ trong tuần (56 ngày gần nhất) trên chi tiêu thường xuyên
    history_days = [today - timedelta(days=i) for i in range(1, 57)]
    by_wd: dict[int, list[float]] = {i: [] for i in range(7)}
    first_record = min(daily) if daily else today
    for d in history_days:
        if d >= first_record:
            by_wd[d.weekday()].append(regular.get(d, 0.0))
    have_history = sum(len(v) for v in by_wd.values()) >= 14
    profile = {wd: _trimmed_mean(v) for wd, v in by_wd.items()}

    elapsed = [month_start + timedelta(days=i) for i in range(today.day)]
    expected_so_far = sum(profile[d.weekday()] for d in elapsed)
    regular_so_far = sum(regular.get(d, 0.0) for d in elapsed)
    remaining_days = [today + timedelta(days=i) for i in range(1, days_left + 1)]
    if have_history and expected_so_far > 0:
        raw_level = regular_so_far / expected_so_far
        shrink = min(1.0, today.day / 21)  # đầu tháng tin vào lịch sử nhiều hơn
        level = 1 + shrink * (raw_level - 1)
        profile_rest = level * sum(profile[d.weekday()] for d in remaining_days)
        residuals = [regular.get(d, 0.0) - profile[d.weekday()] for d in history_days if d >= first_record]
        sigma_day = float(np.std(residuals)) if residuals else 0.0
        method = "weekday_profile"
    else:
        avg = regular_so_far / max(1, today.day)
        profile_rest = avg * days_left
        sigma_day = float(np.std([regular.get(d, 0.0) for d in elapsed])) if elapsed else 0.0
        method = "run_rate"

    # Holt trên tổng chi thường xuyên theo tuần (nếu đủ dữ liệu) -> trung bình tổ hợp
    weeks = []
    end = today
    while len(weeks) < 26:
        start = end - timedelta(days=6)
        if start < first_record:
            break
        weeks.append(sum(regular.get(start + timedelta(days=i), 0.0) for i in range(7)))
        end = start - timedelta(days=1)
    rest = profile_rest
    if len(weeks) >= 8 and days_left > 0:
        fc, _ = holt_forecast(np.array(weeks[::-1], dtype=float), 1)
        holt_rest = max(0.0, float(fc[0])) / 7 * days_left
        rest = 0.6 * profile_rest + 0.4 * holt_rest
        method += "+holt"
    rest += recurring_left + excess_per_day * days_left
    if recurring_left:
        method += "+recurring"
    projected = spent + rest
    margin = 1.2816 * sigma_day * np.sqrt(max(days_left, 0)) + excess_per_day * days_left

    # Theo danh mục: phân bổ phần còn lại theo tỷ trọng 90 ngày gần nhất
    cat_spent: dict[str, float] = {}
    cat_hist: dict[str, float] = {}
    since = today - timedelta(days=90)
    for t in transactions:
        if t.excluded or t.kind not in EXPENSE_KINDS or not t.categoryId:
            continue
        d = t.date.date()
        if month_start <= d <= today:
            cat_spent[t.categoryId] = cat_spent.get(t.categoryId, 0.0) + t.amount
        if since <= d <= today:
            cat_hist[t.categoryId] = cat_hist.get(t.categoryId, 0.0) + t.amount
    hist_total = sum(cat_hist.values()) or 1.0
    by_category = {
        c: {"spent": round(cat_spent.get(c, 0.0)), "projected": round(cat_spent.get(c, 0.0) + rest * cat_hist.get(c, 0.0) / hist_total)}
        for c in set(cat_spent) | set(cat_hist)
    }

    # Tháng tới theo chuỗi tổng chi hằng tháng
    monthly: list[float] = []
    y, m = today.year, today.month
    for _ in range(36):
        m -= 1
        if m == 0:
            y, m = y - 1, 12
        start = date(y, m, 1)
        if start < first_record.replace(day=1):
            break
        last = calendar.monthrange(y, m)[1]
        monthly.append(sum(v for d, v in daily.items() if start <= d <= date(y, m, last)))
    series = np.array(monthly[::-1] + [projected], dtype=float)
    if len(series) >= 24:
        nxt, _ = holt_winters_forecast(series, 12, 1)
        next_method = "holt_winters"
    elif len(series) >= 4:
        nxt, _ = holt_forecast(series, 1)
        next_method = "holt"
    elif len(series) >= 1:
        nxt, next_method = np.array([series.mean()]), "mean"
    else:
        nxt, next_method = np.array([0.0]), "none"

    return MonthForecast(
        spent=round(spent), projected=round(projected), lower=round(max(spent, projected - margin)),
        upper=round(projected + margin), daily_average=round((projected - spent) / days_left) if days_left else 0,
        days_left=days_left, method=method, by_category=by_category,
        next_month=round(max(0.0, float(nxt[0]))) if next_method != "none" else None, next_month_method=next_method)
