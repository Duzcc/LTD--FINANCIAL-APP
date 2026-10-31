"""Kiểm định lùi (backtest) bộ dự báo cuối tháng trên người dùng mô phỏng.

Mỗi người dùng có: mức chi nền, hệ số cuối tuần, khoản cố định đầu tháng (tiền nhà),
khoản lớn ngẫu nhiên, xu hướng tăng/giảm nhẹ. Tại các ngày 5, 10, 15, 20, 25 của 6 tháng cuối,
so sánh sai số tuyệt đối phần trăm (MAPE) của:
  - run_rate: chi đến nay / số ngày đã qua × số ngày trong tháng (cách app cũ dùng)
  - forecaster: hồ sơ thứ-trong-tuần + Holt (dịch vụ hiện tại)

    python -m ml.evaluate_forecaster
"""
from __future__ import annotations

import calendar
import itertools
import json
import random
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np

from app.schemas.common import Transaction
from app.services.forecaster import forecast_month

TZ = ZoneInfo("Asia/Ho_Chi_Minh")


def simulate(seed: int) -> list[Transaction]:
    rnd = random.Random(seed)
    base = rnd.uniform(80_000, 400_000)
    weekend = rnd.uniform(1.0, 2.2)
    rent = rnd.choice([0, 2_500_000, 4_000_000, 6_000_000])
    trend = rnd.uniform(-0.0008, 0.0012)
    start = datetime(2025, 1, 1, 12, tzinfo=TZ)
    out: list[Transaction] = []
    ids = itertools.count()
    for i in range(640):
        d = start + timedelta(days=i)
        level = base * (1 + trend * i) * (weekend if d.weekday() >= 5 else 1)
        amount = max(0.0, rnd.gauss(level, level * 0.35))
        if rnd.random() < 0.15:
            amount = 0.0
        if rnd.random() < 0.03:
            amount += rnd.uniform(5, 20) * base
        if amount:
            out.append(Transaction(id=f"t{next(ids)}", kind="expense", amount=round(amount, -3), date=d))
        if d.day == 3 and rent:
            out.append(Transaction(id=f"t{next(ids)}", kind="expense", amount=rent, date=d))
    return out


def main() -> None:
    errs: dict[str, dict[int, list[float]]] = {"run_rate": {}, "forecaster": {}}
    for seed in range(40):
        txs = simulate(seed)
        for month in range(4, 10):  # 4..9/2026
            last = calendar.monthrange(2026, month)[1]
            actual = sum(t.amount for t in txs if t.date.year == 2026 and t.date.month == month)
            if actual <= 0:
                continue
            for day in (5, 10, 15, 20, 25):
                now = datetime(2026, month, day, 23, tzinfo=TZ)
                seen = [t for t in txs if t.date <= now]
                spent = sum(t.amount for t in seen if t.date.month == month and t.date.year == 2026)
                rr = spent / day * last
                fc = forecast_month(seen, now).projected
                errs["run_rate"].setdefault(day, []).append(abs(rr - actual) / actual)
                errs["forecaster"].setdefault(day, []).append(abs(fc - actual) / actual)
    report = {m: {f"day_{d}": round(float(np.mean(v)) * 100, 1) for d, v in sorted(by.items())} for m, by in errs.items()}
    for m in report:
        report[m]["overall"] = round(float(np.mean([x for v in errs[m].values() for x in v])) * 100, 1)
    print(json.dumps(report, indent=2))
    path = Path(__file__).resolve().parents[1] / "artifacts" / "forecast_backtest.json"
    path.write_text(json.dumps({"metric": "MAPE (%) tổng chi cả tháng", "users": 40, "months": 6, **report}, indent=2,
                               ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
