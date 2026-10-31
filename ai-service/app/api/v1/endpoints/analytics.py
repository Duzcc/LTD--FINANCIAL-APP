"""Phân tích: dự báo, bất thường, gợi ý ngân sách, tìm kiếm ngữ nghĩa."""
from __future__ import annotations

from dataclasses import asdict

from fastapi import APIRouter
from starlette.concurrency import run_in_threadpool

from app.schemas.api import (
    AnomalyItem,
    AnomalyRequest,
    AnomalyResponse,
    BudgetItem,
    BudgetRequest,
    BudgetResponse,
    ForecastResponse,
    SearchHit,
    SearchRequest,
    SearchResponse,
    SnapshotRequest,
    SpikeItem,
)
from app.services import anomaly, budget, forecaster, search

router = APIRouter(tags=["analytics"])


@router.post("/forecast", response_model=ForecastResponse, summary="Dự báo chi tiêu cuối tháng và tháng sau")
async def forecast(body: SnapshotRequest) -> ForecastResponse:
    s = body.snapshot
    f = await run_in_threadpool(forecaster.forecast_month, s.transactions, s.resolved_now())
    return ForecastResponse(**asdict(f))


@router.post("/anomalies", response_model=AnomalyResponse, summary="Phát hiện giao dịch bất thường")
async def anomalies(body: AnomalyRequest) -> AnomalyResponse:
    s = body.snapshot
    found, spikes = await run_in_threadpool(anomaly.detect, s.transactions, s.resolved_now(), body.lookback_days,
                                            s.category_names())
    return AnomalyResponse(
        anomalies=[AnomalyItem(transaction_id=a.transaction_id, score=a.score, kind=a.kind, reasons=a.reasons) for a in found],
        spikes=[SpikeItem(category_id=x.category_id, recent=x.recent, baseline=x.baseline, ratio=x.ratio) for x in spikes])


@router.post("/budgets/recommend", response_model=BudgetResponse, summary="Gợi ý ngân sách tháng")
async def recommend_budgets(body: BudgetRequest) -> BudgetResponse:
    s = body.snapshot
    r = await run_in_threadpool(budget.recommend, s.transactions, s.categories, s.resolved_now(), body.monthly_income,
                                body.savings_rate)
    return BudgetResponse(suggestions=[BudgetItem(**asdict(x)) for x in r["suggestions"]], total=r["total"],
                          months=r["months"], plan=r["plan"])


@router.post("/search", response_model=SearchResponse, summary="Tìm giao dịch bằng câu tự nhiên")
async def semantic_search(body: SearchRequest) -> SearchResponse:
    s = body.snapshot
    flt, hits = await run_in_threadpool(search.search, body.query, s.transactions, s.categories, s.resolved_now(), body.limit)
    filters = {k: (v.isoformat() if hasattr(v, "isoformat") else sorted(v) if isinstance(v, set) else v)
               for k, v in asdict(flt).items() if v not in (None, "", set())}
    return SearchResponse(filters=filters, hits=[SearchHit(transaction_id=t.id, score=sc) for t, sc in hits])
