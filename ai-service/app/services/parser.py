"""Hiểu câu nhập nhanh tiếng Việt (NLU) -> giao dịch có cấu trúc.

Kết hợp:
- mô hình phân loại ý định (loại giao dịch) đã huấn luyện,
- luật ưu tiên cho các mẫu câu chắc chắn (vay/nợ, chuyển tiền, lãi),
- trích xuất thực thể: số tiền, ngày giờ, người, ví,
- bộ phân loại danh mục có cá nhân hóa.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from functools import lru_cache

from app.nlp.entities import find_amount, find_date, find_person
from app.nlp.text import fold
from app.schemas.common import EXPENSE_KINDS, INCOME_KINDS, Category, LabeledText, Person, Wallet

from .categorizer import get_categorizer
from .registry import load_model

DEBT_KINDS = {"lend", "collect", "interestIncome", "borrow", "repay", "interestExpense"}

# Luật có độ chính xác cao, áp dụng trước mô hình.
_RULES: list[tuple[str, str]] = [
    (r"\b(thu lai|lai tiet kiem|lai cho vay)\b", "interestIncome"),
    (r"\bcho\s+\w+(\s\w+)?\s+(muon|vay)\b", "lend"),
    (r"\b(thu no|doi no)\b", "collect"),
    (r"\b\w+\s+tra\s+(no|tien|lai)\b(?!.*\bcho\b)", "collect"),
    (r"\btra\s+(no|tien vay|lai)\b|\btra lai\s+\w+\s+\d", "repay"),
    (r"\b(chuyen|nap|rut)\b.*\b(vi|sang|vao|tiet kiem|heo dat|tien mat|ngan hang)\b", "transfer"),
]
_PRONOUN_START = re.compile(r"^(toi|minh|em|anh|chi|tao)\s+tra\b")


@dataclass
class ParseResult:
    kind: str
    kind_confidence: float
    amount: float | None
    date: datetime
    date_mentioned: bool
    note: str
    category_id: str | None = None
    category_confidence: float = 0.0
    person_id: str | None = None
    new_person_name: str | None = None
    wallet_id: str | None = None
    destination_id: str | None = None
    alternatives: list[tuple[str, float]] = field(default_factory=list)

    @property
    def confidence(self) -> float:
        parts = [0.35 if self.amount else 0.0, 0.3 * self.kind_confidence]
        if self.kind in INCOME_KINDS | EXPENSE_KINDS:
            parts.append(0.35 * self.category_confidence)
        else:
            parts.append(0.35 if (self.person_id or self.new_person_name or self.kind == "transfer") else 0.0)
        return round(min(1.0, sum(parts)), 3)


class QuickEntryParser:
    def __init__(self) -> None:
        self.intent = load_model("intent")

    def classify_kind(self, text: str) -> tuple[str, float, list[tuple[str, float]]]:
        low = text.lower()
        f = fold(text)
        # "trả lãi" (tiền lãi) khác "trả lại" (hoàn trả) khi có dấu; không dấu thì dựa vào ngữ cảnh.
        if "trả lãi" in low or "đóng lãi" in low:
            return "interestExpense", 0.97, []
        if re.search(r"\btra lai\b", f) and "trả lại" not in low and re.search(r"\btra lai\s+(vay|the|ngan hang|thang|khoan)", f):
            return "interestExpense", 0.9, []
        if re.search(r"(nhận|thu)\s+lãi|lãi\s+(tiết kiệm|cho vay|gửi)", low):
            return "interestIncome", 0.95, []
        # "X cho mình/tôi/em mượn" là đi vay chứ không phải cho vay.
        if re.search(r"\bcho\s+(mình|tôi|em|tao|tớ)\s+(mượn|vay)\b", low) or re.search(r"\bcho\s+(toi|tao|to)\s+(muon|vay)\b", f):
            return "borrow", 0.95, []
        if _PRONOUN_START.search(f) and re.search(r"\btra\b", f):
            return "repay", 0.95, []
        if re.search(r"^\s*tra lai\b", f) or "trả lại" in low and re.match(r"^\s*trả lại", low):
            return "repay", 0.93, []
        for pattern, kind in _RULES:
            if re.search(pattern, f):
                return kind, 0.97, []
        proba = self.intent.predict_proba([text])[0]
        order = proba.argsort()[::-1]
        classes = list(self.intent.classes_)
        alts = [(str(classes[i]), round(float(proba[i]), 3)) for i in order[:3]]
        return str(classes[order[0]]), float(proba[order[0]]), alts

    @staticmethod
    def _wallet(text: str, wallets: list[Wallet]) -> tuple[str | None, str | None]:
        f = fold(text)
        hits = [w for w in sorted(wallets, key=lambda w: -len(w.name)) if fold(w.name) and fold(w.name) in f]
        source = hits[0].id if hits else None
        dest = None
        m = re.search(r"\b(sang|vao|qua)\s+(vi\s+)?(.+)$", f)
        if m:
            for w in wallets:
                if fold(w.name) and fold(w.name) in m.group(3):
                    dest = w.id
                    if source == dest:
                        source = next((h.id for h in hits if h.id != dest), None)
                    break
        if source is None and re.search(r"\b(the|ngan hang|chuyen khoan|ck|bank)\b", f):
            source = next((w.id for w in wallets if not w.savings and w.id != "cash"), None)
        if source is None and wallets:
            source = wallets[0].id
        return source, dest

    def parse(self, text: str, *, now: datetime, categories: list[Category], people: list[Person],
              wallets: list[Wallet], history: list[LabeledText] | None = None) -> ParseResult:
        amount = find_amount(text)
        date, mentioned = find_date(text, now)
        kind, kind_conf, alts = self.classify_kind(text)
        person_id, new_name = find_person(text, [p.model_dump() for p in people])
        if kind not in DEBT_KINDS:
            person_id = person_id if kind in INCOME_KINDS | EXPENSE_KINDS else None
            new_name = None
        wallet_id, dest_id = self._wallet(text, wallets)

        # Ghi chú: câu gốc bỏ phần số tiền
        note = text.strip()
        if amount:
            kept = [w for w in note.split() if find_amount(w) is None or re.match(r"^\d{1,2}/\d{1,2}", w)]
            note = " ".join(kept)
        note = re.sub(r"\s+", " ", note).strip()
        note = note[:1].upper() + note[1:] if note else note

        result = ParseResult(kind=kind, kind_confidence=round(kind_conf, 3), amount=amount.value if amount else None,
                             date=date, date_mentioned=mentioned, note=note, person_id=person_id,
                             new_person_name=new_name, wallet_id=wallet_id,
                             destination_id=dest_id if kind == "transfer" else None, alternatives=alts)
        if kind in INCOME_KINDS | EXPENSE_KINDS and categories:
            preds, _ = get_categorizer().predict(note or text, categories, history, income=kind in INCOME_KINDS)
            if preds:
                result.category_id = preds[0].category_id
                result.category_confidence = preds[0].probability
        return result


@lru_cache
def get_parser() -> QuickEntryParser:
    return QuickEntryParser()
