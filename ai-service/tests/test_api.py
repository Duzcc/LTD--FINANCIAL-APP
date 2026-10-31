"""Kiểm thử API đầu-cuối, bao gồm vòng lặp gọi công cụ với LLM giả lập."""
import json

import httpx
import pytest

from app.core.config import get_settings
from app.services.llm.assistant import Assistant
from tests.conftest import CATEGORIES, NOW, PEOPLE, WALLETS, make_transactions


def snapshot_json():
    return {"now": NOW.isoformat(), "categories": [c.model_dump() for c in CATEGORIES],
            "people": [p.model_dump() for p in PEOPLE], "wallets": [w.model_dump() for w in WALLETS],
            "transactions": [json.loads(t.model_dump_json()) for t in make_transactions(120)]}


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200 and r.json()["modelsLoaded"] is True
    assert "x-request-id" in r.headers


def test_models(client):
    body = client.get("/v1/models").json()
    assert body["models"]["categorizer"]["handwritten_eval"]["accuracy"] > 0.85


def test_categorize(client):
    r = client.post("/v1/categorize", json={"text": "phở bò", "categories": [c.model_dump() for c in CATEGORIES], "income": False})
    assert r.status_code == 200
    assert r.json()["predictions"][0]["categoryId"] == "food"


def test_validation_error_shape(client):
    r = client.post("/v1/categorize", json={"text": "", "categories": []})
    assert r.status_code == 422 and r.json()["error"]["code"] == "VALIDATION_ERROR"


def test_parse(client):
    r = client.post("/v1/parse", json={"text": "cho Minh mượn 500k", "now": NOW.isoformat(),
                                       "people": [p.model_dump() for p in PEOPLE], "wallets": [w.model_dump() for w in WALLETS]})
    body = r.json()
    assert body["kind"] == "lend" and body["amount"] == 500_000 and body["newPersonName"] == "Minh"


@pytest.mark.parametrize("path,key", [("/v1/forecast", "projected"), ("/v1/anomalies", "anomalies"),
                                      ("/v1/budgets/recommend", "suggestions")])
def test_analytics_endpoints(client, path, key):
    r = client.post(path, json={"snapshot": snapshot_json()})
    assert r.status_code == 200, r.text
    assert key in r.json()


def test_search_endpoint(client):
    r = client.post("/v1/search", json={"snapshot": snapshot_json(), "query": "grab tuần này"})
    assert r.status_code == 200 and "start" in r.json()["filters"]


def test_receipt_text_endpoint(client):
    from tests.test_analytics import RECEIPT
    r = client.post("/v1/receipts/parse-text", json={"text": RECEIPT, "categories": [c.model_dump() for c in CATEGORIES]})
    assert r.json()["total"] == 46_000


def test_receipt_scan_without_engines(client):
    r = client.post("/v1/receipts/scan", files={"image": ("r.jpg", b"\xff\xd8fake", "image/jpeg")})
    assert r.status_code in (200, 501)


def test_chat_rules(client):
    for q, expect in [("tháng này mình chi bao nhiêu?", "chi"), ("dự báo cuối tháng", "Dự báo"),
                      ("ai đang nợ mình?", "nợ"), ("ghi giúp ăn bún chả 50k", "Xác nhận")]:
        r = client.post("/v1/chat", json={"snapshot": snapshot_json(), "messages": [{"role": "user", "content": q}]})
        body = r.json()
        assert r.status_code == 200 and body["provider"] == "rules"
        assert expect.lower() in body["reply"].lower(), (q, body["reply"])
    assert body["actions"][0]["type"] == "create_transaction"
    assert body["actions"][0]["data"]["amount"] == 50_000


def test_service_key(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "service_api_key", "secret")
    assert client.post("/v1/parse", json={"text": "phở 45k"}).status_code == 401
    assert client.post("/v1/parse", json={"text": "phở 45k"}, headers={"X-API-Key": "secret"}).status_code == 200
    assert client.get("/health").status_code == 200


@pytest.mark.anyio
async def test_anthropic_tool_loop(monkeypatch):
    """LLM giả: lần 1 gọi forecast_month, lần 2 trả lời dựa trên kết quả công cụ."""
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        calls.append(body)
        assert request.headers["x-api-key"] == "k" and request.headers["anthropic-version"] == "2023-06-01"
        if len(calls) == 1:
            assert any(t["name"] == "forecast_month" for t in body["tools"])
            return httpx.Response(200, json={"content": [{"type": "tool_use", "id": "tu1", "name": "forecast_month", "input": {}}]})
        result = json.loads(body["messages"][-1]["content"][0]["content"])
        return httpx.Response(200, json={"content": [{"type": "text", "text": f"Dự kiến {result['projected_month_total']}"}]})

    s = get_settings()
    for k, v in {"llm_provider": "anthropic", "llm_api_key": "k", "llm_model": "claude-test"}.items():
        monkeypatch.setattr(s, k, v)
    from app.schemas.finance import FinanceSnapshot
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        reply = await Assistant(http).chat(FinanceSnapshot(**snapshot_json()), [{"role": "user", "content": "cuối tháng tiêu bao nhiêu"}])
    assert reply.provider == "anthropic" and reply.tools_used == ["forecast_month"]
    assert reply.reply.startswith("Dự kiến ") and len(calls) == 2


@pytest.mark.anyio
async def test_openai_compat_propose_and_fallback(monkeypatch):
    step = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        step["n"] += 1
        if step["n"] == 1:
            return httpx.Response(200, json={"choices": [{"message": {"content": None, "tool_calls": [
                {"id": "c1", "type": "function", "function": {"name": "propose_transaction",
                                                              "arguments": json.dumps({"text": "cà phê 35k"})}}]}}]})
        if step["n"] == 2:
            return httpx.Response(200, json={"choices": [{"message": {"content": "Đã tạo đề xuất."}}]})
        return httpx.Response(500, text="boom")

    s = get_settings()
    for k, v in {"llm_provider": "openai", "llm_base_url": "http://ollama:11434/v1", "llm_model": "qwen2.5"}.items():
        monkeypatch.setattr(s, k, v)
    from app.schemas.finance import FinanceSnapshot
    snap = FinanceSnapshot(**snapshot_json())
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        a = Assistant(http)
        r1 = await a.chat(snap, [{"role": "user", "content": "ghi cà phê 35k"}])
        r2 = await a.chat(snap, [{"role": "user", "content": "số dư bao nhiêu"}])
    assert r1.provider == "openai" and r1.actions[0]["data"]["amount"] == 35_000
    assert r2.provider == "rules" and r2.fallback_reason == "llm_error" and "số dư" in r2.reply.lower()


@pytest.fixture
def anyio_backend():
    return "asyncio"
