"""Hiểu ngôn ngữ: gợi ý danh mục và nhập nhanh bằng câu tự nhiên."""
from __future__ import annotations

from fastapi import APIRouter
from starlette.concurrency import run_in_threadpool

from app.schemas.api import CategorizeRequest, CategorizeResponse, CategoryPrediction, ParseRequest, ParseResponse
from app.schemas.finance import FinanceSnapshot
from app.services.categorizer import get_categorizer
from app.services.parser import get_parser
from app.services.registry import metrics

router = APIRouter(tags=["nlp"])


@router.post("/categorize", response_model=CategorizeResponse, summary="Gợi ý danh mục cho ghi chú")
async def categorize(body: CategorizeRequest) -> CategorizeResponse:
    preds, info = await run_in_threadpool(get_categorizer().predict, body.text, body.categories, body.history,
                                          body.income, body.top_k)
    return CategorizeResponse(predictions=[CategoryPrediction(category_id=p.category_id, probability=p.probability) for p in preds],
                              personal_weight=info["personal_weight"], model_version=metrics().get("trained_at", "dev"))


@router.post("/parse", response_model=ParseResponse, summary="Phân tích câu nhập nhanh thành giao dịch")
async def parse(body: ParseRequest) -> ParseResponse:
    now = FinanceSnapshot(now=body.now).resolved_now()
    r = await run_in_threadpool(lambda: get_parser().parse(
        body.text, now=now, categories=body.categories, people=body.people, wallets=body.wallets, history=body.history))
    return ParseResponse(
        kind=r.kind, kind_confidence=r.kind_confidence, amount=r.amount, date=r.date, date_mentioned=r.date_mentioned,
        note=r.note, category_id=r.category_id, category_confidence=r.category_confidence, person_id=r.person_id,
        new_person_name=r.new_person_name, wallet_id=r.wallet_id, to_wallet_id=r.destination_id,
        confidence=r.confidence, alternatives=[{"kind": k, "probability": p} for k, p in r.alternatives])
