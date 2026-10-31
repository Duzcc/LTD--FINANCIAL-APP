"""Đọc hóa đơn: OCR (Apple Vision / Tesseract / mô hình thị giác) → dựng dòng → phân tích tiếng Việt."""
from __future__ import annotations

import base64
import contextlib
import json
import re
from datetime import datetime

from .layout import OcrBox, group_rows
from .ocr import available_engines, ocr_image
from .parser import ReceiptItem, ReceiptResult, amounts, clean_ocr_numbers, parse_receipt_text

__all__ = ["OcrBox", "group_rows", "available_engines", "ocr_image", "ReceiptItem", "ReceiptResult", "amounts",
           "clean_ocr_numbers", "parse_receipt_text", "RECEIPT_PROMPT", "from_llm_json", "b64"]

RECEIPT_PROMPT = (
    "Đây là ảnh hóa đơn mua hàng tại Việt Nam. Trả về DUY NHẤT một đối tượng JSON: "
    '{"merchant": string|null, "date": "YYYY-MM-DD"|null, "total": number|null, '
    '"items": [{"name": string, "amount": number}]}. "total" là số khách phải trả sau giảm giá '
    "(không phải tiền khách đưa hay tiền thừa). Số tiền là số nguyên VND, không dấu phân cách."
)


def from_llm_json(text: str) -> ReceiptResult | None:
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        return None
    try:
        data = json.loads(m.group(0))
    except json.JSONDecodeError:
        return None
    r = ReceiptResult(merchant=data.get("merchant"), source="vision-llm", confidence=0.85)
    with contextlib.suppress(TypeError, ValueError):
        r.total = float(data["total"]) if data.get("total") is not None else None
    if data.get("date"):
        with contextlib.suppress(ValueError):
            r.date = datetime.fromisoformat(str(data["date"])[:10])
    for it in data.get("items") or []:
        try:
            r.items.append(ReceiptItem(str(it["name"])[:60], float(it["amount"])))
        except (KeyError, TypeError, ValueError):
            continue
    return r


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode()
