"""Bộ công cụ (function calling) cho trợ lý tài chính.

Mô hình ngôn ngữ không bao giờ thấy toàn bộ dữ liệu thô; nó gọi các công cụ dưới đây để lấy đúng
con số cần thiết. Các công cụ "propose_*" không ghi dữ liệu: chúng tạo đề xuất để người dùng xác nhận
trên ứng dụng (human-in-the-loop).
"""
from __future__ import annotations

import calendar
from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Any

from app.nlp.text import fold
from app.schemas.common import EXPENSE_KINDS, INCOME_KINDS
from app.schemas.finance import FinanceSnapshot
from app.services import anomaly, budget, forecaster
from app.services.parser import get_parser

DEBT_OUT = {"lend": 1, "collect": -1}
DEBT_IN = {"borrow": 1, "repay": -1}

TOOL_SPECS: list[dict[str, Any]] = [
    {"name": "get_overview", "description": "Tổng quan: số dư các ví, thu/chi tháng này và tháng trước, số giao dịch.",
     "input_schema": {"type": "object", "properties": {}}},
    {"name": "get_category_spending",
     "description": "Chi tiêu (hoặc thu nhập) theo danh mục trong một khoảng thời gian.",
     "input_schema": {"type": "object", "properties": {
         "period": {"type": "string", "enum": ["this_month", "last_month", "last_30_days", "this_year", "custom"]},
         "start": {"type": "string", "description": "YYYY-MM-DD khi period=custom"},
         "end": {"type": "string", "description": "YYYY-MM-DD (bao gồm) khi period=custom"},
         "income": {"type": "boolean", "description": "true để xem thu nhập"}}, "required": ["period"]}},
    {"name": "forecast_month", "description": "Dự báo tổng chi cuối tháng này (kèm khoảng tin cậy) và tháng sau.",
     "input_schema": {"type": "object", "properties": {}}},
    {"name": "find_transactions", "description": "Tìm giao dịch theo từ khóa và/hoặc khoảng thời gian.",
     "input_schema": {"type": "object", "properties": {
         "query": {"type": "string"}, "days": {"type": "integer", "description": "Số ngày gần nhất, mặc định 30"},
         "limit": {"type": "integer"}}}},
    {"name": "get_budget_status", "description": "Tình trạng các ngân sách tháng này: hạn mức, đã dùng, còn lại.",
     "input_schema": {"type": "object", "properties": {}}},
    {"name": "get_debts", "description": "Các khoản cho vay / đi vay còn dư nợ theo từng người.",
     "input_schema": {"type": "object", "properties": {}}},
    {"name": "get_anomalies", "description": "Giao dịch bất thường và danh mục tăng đột biến trong 30 ngày.",
     "input_schema": {"type": "object", "properties": {}}},
    {"name": "recommend_budgets", "description": "Gợi ý ngân sách tháng cho từng danh mục dựa trên lịch sử.",
     "input_schema": {"type": "object", "properties": {
         "savings_rate": {"type": "number", "description": "Tỷ lệ tiết kiệm mục tiêu 0..0.6, mặc định 0.2"}}}},
    {"name": "propose_transaction",
     "description": "Đề xuất ghi một giao dịch từ mô tả tự nhiên (ví dụ 'ăn phở 45k sáng nay'). Người dùng sẽ xác nhận.",
     "input_schema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}},
    {"name": "propose_budget", "description": "Đề xuất đặt ngân sách tháng cho một danh mục. Người dùng sẽ xác nhận.",
     "input_schema": {"type": "object", "properties": {
         "category_id": {"type": "string"}, "amount": {"type": "number"}}, "required": ["category_id", "amount"]}},
]


class FinanceToolkit:
    def __init__(self, snapshot: FinanceSnapshot):
        self.s = snapshot
        self.now = snapshot.resolved_now()
        self.names = snapshot.category_names()
        self.actions: list[dict[str, Any]] = []
        self.handlers: dict[str, Callable[..., Any]] = {spec["name"]: getattr(self, spec["name"]) for spec in TOOL_SPECS}

    def call(self, name: str, args: dict[str, Any] | None) -> Any:
        handler = self.handlers.get(name)
        if handler is None:
            return {"error": f"Không có công cụ {name}"}
        try:
            return handler(**(args or {}))
        except TypeError as exc:
            return {"error": f"Tham số không hợp lệ: {exc}"}

    # ------------------------------------------------------------ tiện ích
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
            e = datetime.fromisoformat(end).replace(tzinfo=self.now.tzinfo) + timedelta(days=1) if end else today + timedelta(days=1)
            return s, e
        return ms, today + timedelta(days=1)

    def _sum(self, s: datetime, e: datetime, kinds: set[str]) -> float:
        return sum(t.amount for t in self.s.transactions
                   if not t.excluded and t.kind in kinds and s <= self._local(t.date) < e)

    # ------------------------------------------------------------ công cụ
    def get_overview(self) -> dict:
        ms, me = self._range("this_month")
        ls, le = self._range("last_month")
        return {
            "today": self.now.date().isoformat(), "currency": self.s.currency,
            "wallets": [{"name": w.name, "balance": round(w.balance), "savings": w.savings} for w in self.s.wallets],
            "total_balance": round(sum(w.balance for w in self.s.wallets)),
            "this_month": {"income": round(self._sum(ms, me, INCOME_KINDS)), "expense": round(self._sum(ms, me, EXPENSE_KINDS))},
            "last_month": {"income": round(self._sum(ls, le, INCOME_KINDS)), "expense": round(self._sum(ls, le, EXPENSE_KINDS))},
            "transaction_count": len(self.s.transactions),
        }

    def get_category_spending(self, period: str = "this_month", start: str | None = None, end: str | None = None,
                              income: bool = False) -> dict:
        s, e = self._range(period, start, end)
        kinds = INCOME_KINDS if income else EXPENSE_KINDS
        totals: dict[str, float] = {}
        for t in self.s.transactions:
            if not t.excluded and t.kind in kinds and s <= self._local(t.date) < e:
                key = self.names.get(t.categoryId or "", "Khác")
                totals[key] = totals.get(key, 0.0) + t.amount
        total = sum(totals.values())
        rows = sorted(totals.items(), key=lambda x: -x[1])
        return {"from": s.date().isoformat(), "to": (e - timedelta(days=1)).date().isoformat(), "total": round(total),
                "categories": [{"name": k, "amount": round(v), "share": round(v / total, 3) if total else 0} for k, v in rows]}

    def forecast_month(self) -> dict:
        f = forecaster.forecast_month(self.s.transactions, self.now)
        return {"spent_so_far": f.spent, "projected_month_total": f.projected, "range_80pct": [f.lower, f.upper],
                "days_left": f.days_left, "allowed_daily_to_match_projection": f.daily_average,
                "next_month_estimate": f.next_month, "method": f.method}

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
            hits.append({"date": self._local(t.date).date().isoformat(), "kind": t.kind, "amount": round(t.amount),
                         "category": self.names.get(t.categoryId or ""), "note": t.note[:80]})
            if len(hits) >= max(1, min(limit, 50)):
                break
        return {"count": len(hits), "transactions": hits}

    def get_budget_status(self) -> dict:
        ms, me = self._range("this_month")
        days_in_month = calendar.monthrange(self.now.year, self.now.month)[1]
        progress = self.now.day / days_in_month
        out = []
        for b in self.s.budgets:
            kinds = INCOME_KINDS if b.income else EXPENSE_KINDS
            used = sum(t.amount for t in self.s.transactions if not t.excluded and t.kind in kinds
                       and ms <= self._local(t.date) < me and (b.categoryId is None or t.categoryId == b.categoryId))
            out.append({"category": self.names.get(b.categoryId or "", "Tổng"), "limit": round(b.amount),
                        "used": round(used), "remaining": round(b.amount - used),
                        "status": "over" if used > b.amount else ("at_risk" if b.amount and used / b.amount > progress + 0.1 else "ok")})
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
        fmt = lambda d: [{"person": people.get(k, "Không rõ"), "amount": round(v)} for k, v in d.items() if v > 0.5]  # noqa: E731
        return {"others_owe_me": fmt(lent), "i_owe_others": fmt(owed)}

    def get_anomalies(self) -> dict:
        found, spikes = anomaly.detect(self.s.transactions, self.now, categories=self.names)
        by_id = {t.id: t for t in self.s.transactions}
        return {
            "anomalies": [{"date": self._local(by_id[a.transaction_id].date).date().isoformat(),
                           "amount": round(by_id[a.transaction_id].amount), "note": by_id[a.transaction_id].note[:60],
                           "reasons": a.reasons} for a in found[:8]],
            "category_spikes": [{"category": self.names.get(s.category_id, "Khác"), "last_30_days": s.recent,
                                 "monthly_baseline": s.baseline, "ratio": s.ratio} for s in spikes[:5]],
        }

    def recommend_budgets(self, savings_rate: float = 0.2) -> dict:
        r = budget.recommend(self.s.transactions, self.s.categories, self.now,
                             savings_rate=max(0.0, min(0.6, float(savings_rate))))
        return {"months_of_history": r["months"], "total": r["total"], "plan_50_30_20": r["plan"],
                "suggestions": [{"category_id": s.category_id, "category": self.names.get(s.category_id),
                                 "amount": s.amount, "group": s.group, "note": s.note} for s in r["suggestions"]]}

    def propose_transaction(self, text: str) -> dict:
        p = get_parser().parse(text, now=self.now, categories=self.s.categories, people=self.s.people,
                               wallets=self.s.wallets, history=self.s.history())
        if not p.amount:
            return {"error": "Không đọc được số tiền, hãy hỏi lại người dùng số tiền."}
        action = {"type": "create_transaction", "data": {
            "kind": p.kind, "amount": p.amount, "date": p.date.isoformat(), "note": p.note,
            "categoryId": p.category_id, "personId": p.person_id, "newPersonName": p.new_person_name,
            "walletId": p.wallet_id, "toWalletId": p.destination_id}, "confidence": p.confidence}
        self.actions.append(action)
        return {"proposed": action["data"] | {"category": self.names.get(p.category_id or "")},
                "note": "Đã tạo đề xuất; người dùng cần bấm xác nhận trên ứng dụng."}

    def propose_budget(self, category_id: str, amount: float) -> dict:
        if category_id not in self.names:
            return {"error": "Không có danh mục này", "valid_ids": list(self.names)[:40]}
        if amount <= 0:
            return {"error": "Số tiền phải dương"}
        month = self.now.date().replace(day=1).isoformat()
        action = {"type": "set_budget", "data": {"categoryId": category_id, "amount": round(amount), "month": month}}
        self.actions.append(action)
        return {"proposed": action["data"] | {"category": self.names[category_id]},
                "note": "Đã tạo đề xuất; người dùng cần bấm xác nhận."}
