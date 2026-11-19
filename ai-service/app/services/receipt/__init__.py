from __future__ import annotations

import base64
import json
import re
from datetime import datetime

from app.nlp.text import calendar_date

from .layout import OcrBox, group_rows
from .ocr import available_engines, ocr_image
from .parser import ReceiptItem, ReceiptResult, amounts, clean_ocr_numbers, parse_receipt_text

__all__ = ["OcrBox", "group_rows", "available_engines", "ocr_image", "ReceiptItem", "ReceiptResult", "amounts",
           "clean_ocr_numbers", "parse_receipt_text", "RECEIPT_PROMPT", "from_llm_json", "b64"]

RECEIPT_PROMPT = (
    "Đây là ảnh hóa đơn, biên lai hoặc ảnh chụp giao dịch ngân hàng tại Việt Nam. Trả về DUY NHẤT một đối tượng JSON: "
    '{"kind": "expense"|"income", "merchant": string|null, "date": "YYYY-MM-DD HH:MM"|null, "total": number|null, '
    '"items": [{"name": string, "quantity": number|null, "unitPrice": number|null, "amount": number}]}. '
    '"kind" là "income" khi người giữ ảnh nhận tiền (hoàn tiền, nhận chuyển khoản, phiếu lương), '
    'còn lại là "expense". "date" lấy cả giờ in trên hóa đơn nếu có (không có giờ thì chỉ "YYYY-MM-DD"). '
    '"amount" là thành tiền của dòng hàng. "total" là số khách phải trả sau giảm giá '
    "(không phải tiền khách đưa hay tiền thừa). Số tiền là số nguyên VND, không dấu phân cách."
)


_NUMBER = re.compile(r"-?\d+(?:\.\d+)?")
_ISO_DATE = re.compile(r"(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?")


def _number(value) -> float | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    text = str(value).strip() if value is not None else ""
    return float(text) if _NUMBER.fullmatch(text) else None


def _date(value) -> datetime | None:
    m = _ISO_DATE.match(str(value or ""))
    day = m and calendar_date(int(m[1]), int(m[2]), int(m[3]))
    if not day:
        return None
    if m[4] and int(m[4]) < 24 and int(m[5]) < 60:
        return day.replace(hour=int(m[4]), minute=int(m[5]))
    return day


def from_llm_json(text: str) -> ReceiptResult | None:
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        return None
    try:
        data = json.loads(m.group(0))
    except json.JSONDecodeError:
        return None
    kind = "income" if data.get("kind") == "income" else "expense"
    r = ReceiptResult(merchant=data.get("merchant"), source="vision-llm", confidence=0.85, kind=kind,
                      total=_number(data.get("total")), date=_date(data.get("date")))
    for it in data.get("items") or []:
        amount = _number(it.get("amount")) if isinstance(it, dict) else None
        if amount is None or it.get("name") is None:
            continue
        r.items.append(ReceiptItem(str(it["name"])[:60], amount, _number(it.get("quantity")),
                                   _number(it.get("unitPrice"))))
    return r


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode()
