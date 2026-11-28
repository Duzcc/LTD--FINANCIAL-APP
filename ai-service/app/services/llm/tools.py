from __future__ import annotations

import calendar
import re
from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Any

from app.nlp.text import fold
from app.schemas.common import EXPENSE_KINDS, INCOME_KINDS
from app.schemas.finance import FinanceSnapshot
from app.services import anomaly, budget, forecaster
from app.services.parser import get_parser

DAY_PARTS = [("sáng", 5, 11), ("trưa", 11, 14), ("chiều", 14, 18), ("tối", 18, 23), ("khuya", 23, 5)]
WEEKDAYS = ["Thứ 2", "Thứ 3", "Thứ 4", "Thứ 5", "Thứ 6", "Thứ 7", "Chủ nhật"]


GENERAL_SPENDING = {"", "tat ca", "chi tieu", "chi", "tieu", "moi thu", "tong chi", "tong chi tieu"}


def _vnd_text(x: float) -> str:
    return f"{round(x):,}đ".replace(",", ".")


def _thousand(x: float) -> int:
    # số tiết kiệm là ước tính nên làm tròn nghìn cho dễ đọc
    return int(round(x, -3))


DEBT_OUT = {"lend": 1, "collect": -1}
DEBT_IN = {"borrow": 1, "repay": -1}

TOOL_SPECS: list[dict[str, Any]] = [
    {
        "name": "get_overview",
        "description": "Tổng quan: số dư các ví, thu/chi tháng này và tháng trước, số giao dịch.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_category_spending",
        "description": "Chi tiêu (hoặc thu nhập) theo danh mục trong một khoảng thời gian.",
        "input_schema": {
            "type": "object",
            "properties": {
                "period": {
                    "type": "string",
                    "enum": ["this_month", "last_month", "last_30_days", "this_year", "custom"],
                },
                "start": {"type": "string", "description": "YYYY-MM-DD khi period=custom"},
                "end": {"type": "string", "description": "YYYY-MM-DD (bao gồm) khi period=custom"},
                "income": {"type": "boolean", "description": "true để xem thu nhập"},
            },
            "required": ["period"],
        },
    },
    {
        "name": "forecast_month",
        "description": "Dự báo tổng chi cuối tháng này (kèm khoảng tin cậy) và tháng sau.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_spending_allowance",
        "description": "Gợi ý mức được chi mỗi ngày từ nay đến cuối tháng để giữ ngân sách / mục tiêu tiết kiệm, "
        "kèm số đã chi hôm nay và các ngân sách danh mục sắp hết.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "find_transactions",
        "description": "Tìm giao dịch theo từ khóa và/hoặc khoảng thời gian. Danh sách kết quả được hiển thị "
        "cho người dùng dưới câu trả lời.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "days": {"type": "integer", "description": "Số ngày gần nhất, mặc định 30"},
                "limit": {"type": "integer"},
            },
        },
    },
    {
        "name": "get_budget_status",
        "description": "Tình trạng các ngân sách tháng này: hạn mức, đã dùng, còn lại.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_debts",
        "description": "Các khoản cho vay / đi vay còn dư nợ theo từng người.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_anomalies",
        "description": "Giao dịch bất thường và danh mục tăng đột biến trong 30 ngày.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "recommend_budgets",
        "description": "Gợi ý ngân sách tháng cho từng danh mục dựa trên lịch sử.",
        "input_schema": {
            "type": "object",
            "properties": {
                "savings_rate": {"type": "number", "description": "Tỷ lệ tiết kiệm mục tiêu 0..0.6, mặc định 0.2"}
            },
        },
    },
    {
        "name": "spending_habits",
        "description": "Thói quen chi tiêu theo buổi trong ngày và thứ trong tuần (sáng/trưa/chiều/tối, ngày thường so với "
        "cuối tuần), có thể lọc theo từ khóa hoặc danh mục. Trả về số liệu và các nhận xét đã tính sẵn.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Từ khóa hoặc tên danh mục, ví dụ 'cà phê' (tùy chọn)"},
                "days": {"type": "integer", "description": "Số ngày gần nhất để xét, mặc định 90"},
            },
        },
    },
    {
        "name": "simulate_saving",
        "description": "Mô phỏng tiền tiết kiệm tiềm năng khi bớt một khoản chi (theo từ khóa như 'trà sữa' hoặc tên "
        "danh mục): giảm theo phần trăm và giảm số lần mua mỗi tháng. Số liệu do hệ thống tính từ lịch sử 30 ngày; "
        "đây là khoản tiềm năng, không phải tiền đã tiết kiệm.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Từ khóa khoản chi, ví dụ 'trà sữa', 'cà phê', 'Ăn uống'"},
                "reduce_percent": {"type": "number", "description": "Mức giảm muốn thử, 1..90 (tùy chọn)"},
                "target_times": {"type": "integer", "description": "Số lần mua mỗi tháng muốn giữ lại (tùy chọn)"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "propose_transaction",
        "description": "Đề xuất ghi một giao dịch từ mô tả tự nhiên (ví dụ 'ăn phở 45k sáng nay'). Người dùng sẽ xác nhận.",
        "input_schema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
    },
    {
        "name": "propose_budget",
        "description": "Đề xuất đặt ngân sách tháng cho một danh mục. Người dùng sẽ xác nhận.",
        "input_schema": {
            "type": "object",
            "properties": {"category_id": {"type": "string"}, "amount": {"type": "number"}},
            "required": ["category_id", "amount"],
        },
    },
]


class FinanceToolkit:
    def __init__(self, snapshot: FinanceSnapshot):
        self.s = snapshot
        self.now = snapshot.resolved_now()
        self.names = snapshot.category_names()
        self.actions: list[dict[str, Any]] = []
        self.handlers: dict[str, Callable[..., Any]] = {
            spec["name"]: getattr(self, spec["name"]) for spec in TOOL_SPECS
        }

    def call(self, name: str, args: dict[str, Any] | None) -> Any:
        handler = self.handlers.get(name)
        if handler is None:
            return {"error": f"Không có công cụ {name}"}
        # tham số sai thì báo lại để AI tự sửa
        try:
            return handler(**(args or {}))
        except (TypeError, ValueError) as exc:
            return {"error": f"Tham số không hợp lệ: {exc}"}

    def _local(self, d: datetime) -> datetime:
        if d.tzinfo is None and self.now.tzinfo is not None:
            return d.replace(tzinfo=self.now.tzinfo)
        return d.astimezone(self.now.tzinfo) if self.now.tzinfo else d

    def _range(self, period: str, start: str | None = None, end: str | None = None) -> tuple[datetime, datetime]:
        today = self.now.replace(hour=0, minute=0, second=0, microsecond=0)
        ms = today.replace(day=1)
        if period == "last_month":
            pe = ms
            return (ms - timedelta(days=1)).replace(day=1), pe
        if period == "last_30_days":
            return today - timedelta(days=29), today + timedelta(days=1)
        if period == "this_year":
            return today.replace(month=1, day=1), today + timedelta(days=1)
        if period == "custom" and start:
            s = datetime.fromisoformat(start).replace(tzinfo=self.now.tzinfo)
            e = (
                datetime.fromisoformat(end).replace(tzinfo=self.now.tzinfo) + timedelta(days=1)
                if end
                else today + timedelta(days=1)
            )
            return s, e
        return ms, today + timedelta(days=1)

    def _sum(self, s: datetime, e: datetime, kinds: set[str]) -> float:
        return sum(
            t.amount for t in self.s.transactions if not t.excluded and t.kind in kinds and s <= self._local(t.date) < e
        )

    def get_overview(self) -> dict:
        ms, me = self._range("this_month")
        ls, le = self._range("last_month")
        expense = self._sum(ms, me, EXPENSE_KINDS)
        return {
            "today": self.now.date().isoformat(),
            "currency": self.s.currency,
            "wallets": [{"name": w.name, "balance": round(w.balance), "savings": w.savings} for w in self.s.wallets],
            "total_balance": round(sum(w.balance for w in self.s.wallets)),
            "this_month": {
                "income": round(self._sum(ms, me, INCOME_KINDS)),
                "expense": round(expense),
                # số đã chi thật, khác với mức nên chi của get_spending_allowance
                "days_passed": self.now.day,
                "daily_average_spent": round(expense / self.now.day),
            },
            "last_month": {
                "income": round(self._sum(ls, le, INCOME_KINDS)),
                "expense": round(self._sum(ls, le, EXPENSE_KINDS)),
            },
            "transaction_count": len(self.s.transactions),
        }

    def get_category_spending(
        self, period: str = "this_month", start: str | None = None, end: str | None = None, income: bool = False
    ) -> dict:
        s, e = self._range(period, start, end)
        kinds = INCOME_KINDS if income else EXPENSE_KINDS
        totals: dict[str, float] = {}
        for t in self.s.transactions:
            if not t.excluded and t.kind in kinds and s <= self._local(t.date) < e:
                key = self.names.get(t.categoryId or "", "Khác")
                totals[key] = totals.get(key, 0.0) + t.amount
        total = sum(totals.values())
        rows = sorted(totals.items(), key=lambda x: -x[1])
        return {
            "from": s.date().isoformat(),
            "to": (e - timedelta(days=1)).date().isoformat(),
            "total": round(total),
            "categories": [
                {"name": k, "amount": round(v), "share": round(v / total, 3) if total else 0} for k, v in rows
            ],
        }

    def forecast_month(self) -> dict:
        f = forecaster.forecast_month(self.s.transactions, self.now)
        return {
            "spent_so_far": f.spent,
            "projected_month_total": f.projected,
            "range_80pct": [f.lower, f.upper],
            "days_left": f.days_left,
            "allowed_daily_to_match_projection": f.daily_average,
            "next_month_estimate": f.next_month,
            "method": f.method,
        }

    def find_transactions(self, query: str = "", days: int = 30, limit: int = 15) -> dict:
        since = self.now - timedelta(days=max(1, min(days, 3650)))
        q = fold(query).strip()
        hits = []
        for t in sorted(self.s.transactions, key=lambda t: t.date, reverse=True):
            if self._local(t.date) < since:
                continue
            hay = fold(f"{t.note} {self.names.get(t.categoryId or '', '')}")
            if q and q not in hay:
                continue
            hits.append(
                {
                    "id": t.id,
                    "date": self._local(t.date).date().isoformat(),
                    "kind": t.kind,
                    "amount": round(t.amount),
                    "category": self.names.get(t.categoryId or ""),
                    "note": t.note[:80],
                }
            )
            if len(hits) >= max(1, min(limit, 50)):
                break
        if hits:
            self.actions = [a for a in self.actions if a["type"] != "show_transactions"]
            self.actions.append({"type": "show_transactions", "data": {"ids": [h["id"] for h in hits]}})
        return {"count": len(hits), "transactions": hits}

    def get_spending_allowance(self) -> dict:
        ms, me = self._range("this_month")
        today = self.now.replace(hour=0, minute=0, second=0, microsecond=0)
        days_in_month = calendar.monthrange(self.now.year, self.now.month)[1]
        days_left = days_in_month - self.now.day + 1
        spent = self._sum(ms, me, EXPENSE_KINDS)
        spent_today = self._sum(today, me, EXPENSE_KINDS)
        overall = next((b for b in self.s.budgets if b.categoryId is None and not b.income), None)
        if overall is not None:
            limit, basis = overall.amount, "budget"
        else:
            income = self._sum(ms, me, INCOME_KINDS)
            if not income:
                ls, le = self._range("last_month")
                income = self._sum(ls, le, INCOME_KINDS)
            limit, basis = (income * 0.8, "income_minus_20pct_savings") if income else (None, "none")
        spent_before_today = spent - spent_today
        daily = round(max(0.0, limit - spent_before_today) / days_left) if limit is not None else None
        tight = [x for x in self.get_budget_status()["budgets"] if x["category"] != "Tổng" and x["status"] != "ok"]
        return {
            "basis": basis,
            "month_limit": round(limit) if limit is not None else None,
            "spent_this_month": round(spent),
            "spent_today": round(spent_today),
            "days_left_incl_today": days_left,
            "daily_allowance": daily,
            "left_today": None if daily is None else round(daily - spent_today),
            "tight_budgets": tight,
        }

    def get_budget_status(self) -> dict:
        ms, me = self._range("this_month")
        days_in_month = calendar.monthrange(self.now.year, self.now.month)[1]
        progress = self.now.day / days_in_month
        out = []
        for b in self.s.budgets:
            kinds = INCOME_KINDS if b.income else EXPENSE_KINDS
            used = sum(
                t.amount
                for t in self.s.transactions
                if not t.excluded
                and t.kind in kinds
                and ms <= self._local(t.date) < me
                and (b.categoryId is None or t.categoryId == b.categoryId)
            )
            out.append(
                {
                    "category": self.names.get(b.categoryId or "", "Tổng"),
                    "limit": round(b.amount),
                    "used": round(used),
                    "remaining": round(b.amount - used),
                    "status": "over"
                    if used > b.amount
                    else ("at_risk" if b.amount and used / b.amount > progress + 0.1 else "ok"),
                }
            )
        return {"month_progress": round(progress, 2), "budgets": out}

    def get_debts(self) -> dict:
        people = {p.id: p.name for p in self.s.people}
        lent: dict[str, float] = {}
        owed: dict[str, float] = {}
        for t in self.s.transactions:
            pid = t.personId or "_"
            if t.kind in DEBT_OUT:
                lent[pid] = lent.get(pid, 0.0) + DEBT_OUT[t.kind] * t.amount
            elif t.kind in DEBT_IN:
                owed[pid] = owed.get(pid, 0.0) + DEBT_IN[t.kind] * t.amount
        fmt = lambda d: [{"person": people.get(k, "Không rõ"), "amount": round(v)} for k, v in d.items() if v > 0.5]
        return {"others_owe_me": fmt(lent), "i_owe_others": fmt(owed)}

    def get_anomalies(self) -> dict:
        found, spikes = anomaly.detect(self.s.transactions, self.now, categories=self.names)
        by_id = {t.id: t for t in self.s.transactions}
        return {
            "anomalies": [
                {
                    "date": self._local(by_id[a.transaction_id].date).date().isoformat(),
                    "amount": round(by_id[a.transaction_id].amount),
                    "note": by_id[a.transaction_id].note[:60],
                    "reasons": a.reasons,
                }
                for a in found[:8]
            ],
            "category_spikes": [
                {
                    "category": self.names.get(s.category_id, "Khác"),
                    "last_30_days": s.recent,
                    "monthly_baseline": s.baseline,
                    "ratio": s.ratio,
                }
                for s in spikes[:5]
            ],
        }

    def recommend_budgets(self, savings_rate: float = 0.2) -> dict:
        r = budget.recommend(
            self.s.transactions, self.s.categories, self.now, savings_rate=max(0.0, min(0.6, float(savings_rate)))
        )
        return {
            "months_of_history": r["months"],
            "total": r["total"],
            "plan_50_30_20": r["plan"],
            "suggestions": [
                {
                    "category_id": s.category_id,
                    "category": self.names.get(s.category_id),
                    "amount": s.amount,
                    "group": s.group,
                    "note": s.note,
                }
                for s in r["suggestions"]
            ],
        }

    def spending_habits(self, query: str | None = None, days: int = 90) -> dict:
        days = max(7, min(int(days or 90), 365))
        since = self.now - timedelta(days=days)
        word = re.compile(rf"\b{re.escape(fold(query).strip())}\b") if query and fold(query).strip() else None
        txs = [
            (self._local(t.date), t)
            for t in self.s.transactions
            if not t.excluded
            and t.kind in EXPENSE_KINDS
            and self._local(t.date) >= since
            and (word is None or word.search(fold(f"{t.note} {self.names.get(t.categoryId or '', '')}")))
        ]
        if not txs:
            return {"query": query, "count": 0, "note": "Chưa đủ giao dịch để nhận ra thói quen."}
        total = sum(t.amount for _, t in txs)
        notes: list[str] = []

        # giao dịch nhập không kèm giờ đều nằm ở 00:00, khi đó không xét theo buổi
        timed = [(d, t) for d, t in txs if (d.hour, d.minute) != (0, 0)]
        by_part = []
        if len(timed) >= len(txs) / 2:
            slots = {}
            for d, t in timed:
                name = next(n for n, a, b in DAY_PARTS if a <= d.hour < b or (a > b and (d.hour >= a or d.hour < b)))
                c, s, cats = slots.get(name, (0, 0.0, {}))
                cats[t.categoryId] = cats.get(t.categoryId, 0.0) + t.amount
                slots[name] = (c + 1, s + t.amount, cats)
            timed_total = sum(t.amount for _, t in timed)
            for name, _, _ in DAY_PARTS:
                if name in slots:
                    c, s, cats = slots[name]
                    top = max(cats, key=cats.get)
                    by_part.append(
                        {
                            "part": name,
                            "count": c,
                            "total": round(s),
                            "share": round(s / timed_total, 3),
                            "top_category": self.names.get(top or "", "Khác"),
                        }
                    )
            peak = max(by_part, key=lambda x: x["total"])
            notes.append(
                f"Chi nhiều nhất vào buổi {peak['part']}: {peak['share'] * 100:.0f}% tổng chi, chủ yếu {peak['top_category']}."
            )
        else:
            notes.append("Phần lớn giao dịch không ghi giờ nên chưa xét được theo buổi trong ngày.")

        week = [0.0] * 7
        for d, t in txs:
            week[d.weekday()] += t.amount
        # số lần mỗi thứ xuất hiện trong khoảng xét, để so trung bình mỗi ngày cho công bằng
        seen = [0] * 7
        day = since.date()
        while day <= self.now.date():
            seen[day.weekday()] += 1
            day += timedelta(days=1)
        by_weekday = [
            {"weekday": WEEKDAYS[i], "total": round(week[i]), "per_day": round(week[i] / seen[i]) if seen[i] else 0}
            for i in range(7)
        ]
        weekday_avg = sum(week[:5]) / max(1, sum(seen[:5]))
        weekend_avg = sum(week[5:]) / max(1, sum(seen[5:]))
        top_day = max(by_weekday, key=lambda x: x["per_day"])
        notes.append(
            f"Ngày chi nhiều nhất trong tuần: {top_day['weekday']} (trung bình {top_day['per_day']:,}đ/ngày).".replace(
                ",", "."
            )
        )
        if weekday_avg and weekend_avg > weekday_avg * 1.2:
            notes.append(f"Cuối tuần chi gấp {weekend_avg / weekday_avg:.1f} lần ngày thường.".replace(".", ",", 1))
        elif weekend_avg and weekday_avg > weekend_avg * 1.2:
            notes.append(f"Ngày thường chi gấp {weekday_avg / weekend_avg:.1f} lần cuối tuần.".replace(".", ",", 1))
        return {
            "query": query,
            "period_days": days,
            "count": len(txs),
            "total": round(total),
            "highlights": notes,
            "by_part_of_day": by_part,
            "by_weekday": by_weekday,
            "weekday_avg_per_day": round(weekday_avg),
            "weekend_avg_per_day": round(weekend_avg),
        }

    def simulate_saving(
        self, query: str = "", reduce_percent: float | None = None, target_times: int | None = None, days: int = 30
    ) -> dict:
        # mô hình nhỏ đôi khi gửi số dạng chuỗi như "20"
        reduce_percent = float(reduce_percent) if reduce_percent not in (None, "") else None
        target_times = int(float(target_times)) if target_times not in (None, "") else None
        since = self.now - timedelta(days=days)
        q = fold(query or "").strip()
        # "giảm chi 20%" không nói khoản nào thì tính trên toàn bộ chi tiêu
        general = q in GENERAL_SPENDING
        # khớp cả từ để "phở" không dính "văn phòng"
        word = re.compile(rf"\b{re.escape(q)}\b")
        hits = [
            t
            for t in self.s.transactions
            if not t.excluded
            and t.kind in EXPENSE_KINDS
            and self._local(t.date) >= since
            and (general or word.search(fold(f"{t.note} {self.names.get(t.categoryId or '', '')}")))
        ]
        label = "tổng chi tiêu" if general else query
        if not hits:
            return {"query": label, "count": 0, "note": f"Không có khoản chi nào khớp '{label}' trong {days} ngày qua."}
        total = sum(t.amount for t in hits)
        times = len(hits)
        avg = total / times
        # quy về một tháng 30 ngày để các phương án so sánh được với nhau
        scale = 30 / days
        monthly, monthly_times = total * scale, times * scale
        # chỉ đưa phương án người dùng hỏi, mô hình nhỏ dễ lấy nhầm số khi có nhiều phương án
        if reduce_percent:
            percents = [round(reduce_percent)]
        elif target_times is None:
            percents = [10, 20, 30]
        else:
            percents = []
        by_percent = [
            {
                "reduce_percent": p,
                "monthly_saving": _thousand(monthly * p / 100),
                "new_monthly_spending": _thousand(monthly * (100 - p) / 100),
            }
            for p in percents
            if 0 < p < 100
        ]
        by_frequency = None
        only_percent = bool(reduce_percent and by_percent and target_times is None)
        # bớt số lần chỉ có nghĩa với một khoản cụ thể; người dùng hỏi theo % thì không đưa thêm để khỏi lẫn
        if not general and not only_percent:
            keep = target_times if target_times is not None else int(monthly_times * 0.7)
            keep = max(0, min(keep, round(monthly_times)))
            by_frequency = {
                "current_times_per_month": round(monthly_times, 1),
                "suggested_times_per_month": keep,
                "average_price": round(avg),
                "monthly_saving": _thousand(max(0.0, monthly_times - keep) * avg),
            }
        summary = (
            [
                f"Giảm còn {by_frequency['suggested_times_per_month']} lần/tháng: tiết kiệm khoảng "
                f"{_vnd_text(by_frequency['monthly_saving'])}/tháng"
            ]
            if by_frequency
            else []
        )
        summary += [
            f"Giảm {x['reduce_percent']}%: tiết kiệm khoảng {_vnd_text(x['monthly_saving'])}/tháng" for x in by_percent
        ]
        return {
            "summary": summary,
            "query": label,
            "period_days": days,
            "count": times,
            "total_spent": round(total),
            "average_price": round(avg),
            "monthly_spending": round(monthly),
            "by_frequency": by_frequency,
            "by_percent": by_percent,
            "note": "Đây là tiền tiết kiệm tiềm năng nếu thay đổi thói quen, chưa phải tiền đã tiết kiệm.",
        }

    def propose_transaction(self, text: str) -> dict:
        p = get_parser().parse(
            text,
            now=self.now,
            categories=self.s.categories,
            people=self.s.people,
            wallets=self.s.wallets,
            history=self.s.history(),
        )
        if not p.amount:
            return {"error": "Không đọc được số tiền, hãy hỏi lại người dùng số tiền."}
        action = {
            "type": "create_transaction",
            "data": {
                "kind": p.kind,
                "amount": p.amount,
                "date": p.date.isoformat(),
                "note": p.note,
                "categoryId": p.category_id,
                "personId": p.person_id,
                "newPersonName": p.new_person_name,
                "walletId": p.wallet_id,
                "toWalletId": p.destination_id,
            },
            "confidence": p.confidence,
        }
        self.actions.append(action)
        return {
            "proposed": action["data"] | {"category": self.names.get(p.category_id or "")},
            "note": "Đã tạo đề xuất; người dùng cần bấm xác nhận trên ứng dụng.",
        }

    def propose_budget(self, category_id: str, amount: float) -> dict:
        if category_id not in self.names:
            return {"error": "Không có danh mục này", "valid_ids": list(self.names)[:40]}
        if amount <= 0:
            return {"error": "Số tiền phải dương"}
        month = self.now.date().replace(day=1).isoformat()
        action = {"type": "set_budget", "data": {"categoryId": category_id, "amount": round(amount), "month": month}}
        self.actions.append(action)
        return {
            "proposed": action["data"] | {"category": self.names[category_id]},
            "note": "Đã tạo đề xuất; người dùng cần bấm xác nhận.",
        }
