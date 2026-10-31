"""Hợp đồng dữ liệu (request/response) của API v1. JSON dùng camelCase giống backend và ứng dụng."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel

from .common import Category, LabeledText, Person, Wallet
from .finance import FinanceSnapshot


class CamelModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


# ---------------------------------------------------------------- danh mục
class CategorizeRequest(CamelModel):
    text: str = Field(min_length=1, max_length=500)
    categories: list[Category] = Field(min_length=1, max_length=500)
    history: list[LabeledText] = Field(default_factory=list, max_length=5000)
    income: bool | None = None
    top_k: int = Field(default=3, ge=1, le=10)


class CategoryPrediction(CamelModel):
    category_id: str
    probability: float


class CategorizeResponse(CamelModel):
    predictions: list[CategoryPrediction]
    personal_weight: float
    model_version: str


# ---------------------------------------------------------------- nhập nhanh
class ParseRequest(CamelModel):
    text: str = Field(min_length=1, max_length=500)
    now: datetime | None = None
    categories: list[Category] = Field(default_factory=list, max_length=500)
    people: list[Person] = Field(default_factory=list, max_length=1000)
    wallets: list[Wallet] = Field(default_factory=list, max_length=200)
    history: list[LabeledText] = Field(default_factory=list, max_length=5000)


class ParseResponse(CamelModel):
    kind: str
    kind_confidence: float
    amount: float | None
    date: datetime
    date_mentioned: bool
    note: str
    category_id: str | None
    category_confidence: float
    person_id: str | None
    new_person_name: str | None
    wallet_id: str | None
    to_wallet_id: str | None
    confidence: float
    alternatives: list[dict[str, Any]]


# ---------------------------------------------------------------- phân tích
class SnapshotRequest(CamelModel):
    snapshot: FinanceSnapshot


class ForecastResponse(CamelModel):
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


class AnomalyRequest(SnapshotRequest):
    lookback_days: int = Field(default=30, ge=1, le=365)


class AnomalyItem(CamelModel):
    transaction_id: str
    score: float
    kind: str
    reasons: list[str]


class SpikeItem(CamelModel):
    category_id: str
    recent: float
    baseline: float
    ratio: float


class AnomalyResponse(CamelModel):
    anomalies: list[AnomalyItem]
    spikes: list[SpikeItem]


class BudgetRequest(SnapshotRequest):
    monthly_income: float | None = Field(default=None, ge=0)
    savings_rate: float = Field(default=0.2, ge=0, le=0.6)


class BudgetItem(CamelModel):
    category_id: str
    amount: float
    history_median: float
    months: int
    group: Literal["needs", "wants"]
    note: str


class BudgetResponse(CamelModel):
    suggestions: list[BudgetItem]
    total: float
    months: int
    plan: dict[str, Any] | None


# ---------------------------------------------------------------- hóa đơn
class ReceiptTextRequest(CamelModel):
    text: str = Field(min_length=1, max_length=20000)
    categories: list[Category] = Field(default_factory=list, max_length=500)


class ReceiptLine(CamelModel):
    name: str
    amount: float


class ReceiptResponse(CamelModel):
    merchant: str | None
    total: float | None
    date: datetime | None
    items: list[ReceiptLine]
    note: str
    category_id: str | None = None
    source: str
    confidence: float = 0.0
    checks: list[str] = Field(default_factory=list, description="Các bằng chứng xác nhận tổng tiền")
    raw_text: str = ""



# ---------------------------------------------------------------- tìm kiếm
class SearchRequest(SnapshotRequest):
    query: str = Field(min_length=1, max_length=200)
    limit: int = Field(default=30, ge=1, le=200)


class SearchHit(CamelModel):
    transaction_id: str
    score: float


class SearchResponse(CamelModel):
    filters: dict[str, Any]
    hits: list[SearchHit]


# ---------------------------------------------------------------- trợ lý
class ChatMessage(CamelModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=4000)


class ChatRequest(SnapshotRequest):
    messages: list[ChatMessage] = Field(min_length=1, max_length=30)


class ChatResponse(CamelModel):
    reply: str
    provider: str
    tools_used: list[str]
    actions: list[dict[str, Any]]
    fallback_reason: str | None = None


# ---------------------------------------------------------------- hệ thống
class HealthResponse(CamelModel):
    status: str
    version: str
    models_loaded: bool
    assistant: str
