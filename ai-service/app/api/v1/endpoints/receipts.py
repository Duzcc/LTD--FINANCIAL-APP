"""Đọc hóa đơn từ văn bản OCR hoặc ảnh."""
from __future__ import annotations

import json

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from starlette.concurrency import run_in_threadpool

from app.api.deps import get_assistant
from app.schemas.api import ReceiptLine, ReceiptResponse, ReceiptTextRequest
from app.schemas.common import Category
from app.services import receipt
from app.services.categorizer import get_categorizer
from app.services.llm.assistant import Assistant
from app.services.llm.providers import LLMError

router = APIRouter(prefix="/receipts", tags=["receipts"])
MAX_IMAGE = 6 * 1024 * 1024


def _to_response(r: receipt.ReceiptResult, categories: list[Category]) -> ReceiptResponse:
    category_id = None
    expense = [c for c in categories if not c.income]
    if expense and (r.note or r.merchant):
        preds, _ = get_categorizer().predict(r.note or r.merchant or "", expense, income=False, top_k=1)
        if preds and preds[0].probability >= 0.35:
            category_id = preds[0].category_id
    return ReceiptResponse(merchant=r.merchant, total=r.total, date=r.date, note=r.note, source=r.source,
                           items=[ReceiptLine(name=i.name, amount=i.amount) for i in r.items], category_id=category_id,
                           confidence=r.confidence, checks=r.checks, raw_text=r.raw_text[:5000])


@router.post("/parse-text", response_model=ReceiptResponse, summary="Trích xuất hóa đơn từ văn bản OCR")
async def parse_text(body: ReceiptTextRequest) -> ReceiptResponse:
    r = await run_in_threadpool(receipt.parse_receipt_text, body.text)
    return _to_response(r, body.categories)


@router.get("/engines", summary="Các engine OCR khả dụng trên máy chủ")
async def engines(assistant: Assistant = Depends(get_assistant)) -> dict:
    return {"ocr": receipt.available_engines(), "visionLlm": assistant.provider is not None}


@router.post("/scan", response_model=ReceiptResponse, summary="Đọc hóa đơn từ ảnh")
async def scan(image: UploadFile = File(...), categories: str = Form("[]"),
               assistant: Assistant = Depends(get_assistant)) -> ReceiptResponse:
    data = await image.read()
    if len(data) > MAX_IMAGE:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Ảnh quá lớn (tối đa 6MB).")
    media = image.content_type or "image/jpeg"
    if media not in {"image/jpeg", "image/png", "image/webp", "image/heic"}:
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "Chỉ hỗ trợ ảnh JPEG/PNG/WebP.")
    try:
        cats = [Category(**c) for c in json.loads(categories)]
    except (ValueError, TypeError):
        cats = []
    # 1) OCR cục bộ (miễn phí, riêng tư). Đủ tin cậy thì dùng luôn.
    ocr_result = None
    ocr = await run_in_threadpool(receipt.ocr_image, data)
    if ocr:
        text, engine = ocr
        ocr_result = receipt.parse_receipt_text(text)
        ocr_result.source = engine
        if ocr_result.total and ocr_result.confidence >= 0.8:
            return _to_response(ocr_result, cats)
    # 2) Không chắc chắn: hỏi mô hình thị giác (nếu cấu hình)
    if assistant.provider is not None:
        try:
            text = await assistant.provider.complete_vision(receipt.RECEIPT_PROMPT, receipt.b64(data), media)
            r = receipt.from_llm_json(text)
            if r and (r.total or r.items):
                return _to_response(r, cats)
        except LLMError:
            pass
    if ocr_result is not None:
        return _to_response(ocr_result, cats)
    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED,
                        "Máy chủ chưa có engine OCR (Apple Vision/Tesseract) hay mô hình thị giác. Hãy dùng nhận dạng chữ trên điện thoại.")
