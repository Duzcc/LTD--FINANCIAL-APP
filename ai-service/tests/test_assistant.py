from __future__ import annotations

import json
from datetime import timedelta

import httpx
import pytest

from app.core.config import get_settings
from app.schemas.finance import FinanceSnapshot
from app.services.llm import rules
from app.services.llm.assistant import Assistant, money_in, unverified_money
from app.services.llm.tools import FinanceToolkit
from ml.data.assistant_eval import QUESTIONS

from .conftest import CATEGORIES, NOW, PEOPLE, WALLETS, make_transactions


def snap() -> FinanceSnapshot:
    return FinanceSnapshot(
        now=NOW, wallets=WALLETS, categories=CATEGORIES, people=PEOPLE, transactions=make_transactions()
    )


def test_bo_cau_hoi_danh_gia_dat_it_nhat_90_phan_tram():
    wrong = [q for q, want in QUESTIONS if rules.detect_intent(q) != want]
    assert len(QUESTIONS) >= 50
    assert 1 - len(wrong) / len(QUESTIONS) >= 0.9, wrong


def test_mo_phong_tiet_kiem_tinh_tu_lich_su():
    kit = FinanceToolkit(snap())
    r = kit.simulate_saving("cà phê", reduce_percent=25, target_times=10)
    since = kit.now - timedelta(days=30)
    hits = [t for t in kit.s.transactions if t.categoryId == "coffee" and kit._local(t.date) >= since]
    assert r["count"] == len(hits) and r["total_spent"] == round(sum(t.amount for t in hits))
    assert [x["reduce_percent"] for x in r["by_percent"]] == [25]
    assert r["summary"][0].startswith("Giảm còn 10 lần/tháng")
    assert [x["reduce_percent"] for x in kit.simulate_saving("cà phê")["by_percent"]] == [10, 20, 30]
    fq = r["by_frequency"]
    assert fq["suggested_times_per_month"] == 10
    assert abs(fq["monthly_saving"] - (r["count"] - 10) * r["total_spent"] / r["count"]) <= 500


def test_mo_phong_khop_ca_tu():
    # "phở" không được tính cả "Cơm trưa văn phòng"
    kit = FinanceToolkit(snap())
    since = kit.now - timedelta(days=30)
    pho = [t for t in kit.s.transactions if t.note == "Phở bò" and kit._local(t.date) >= since]
    assert kit.simulate_saving("phở")["count"] == len(pho)


def test_tro_ly_luat_mo_phong_tiet_kiem():
    kit = FinanceToolkit(snap())
    text, used = rules.answer("Nếu bớt uống trà sữa xuống 3 lần thì tiết kiệm được bao nhiêu?", kit)
    assert used == ["simulate_saving"]
    assert "trà sữa" in text and "3 lần/tháng" in text and "tiềm năng" in text


def test_doc_so_tien_trong_cau_tra_loi():
    assert money_in("Chi 1.250.000đ, cà phê 45k, khoảng 1,2 triệu, 18 lần, năm 2026, 20%") == [
        1_250_000,
        45_000,
        1_200_000,
    ]
    results = [{"expense": 1_250_000, "items": [100_000, 200_000]}]
    assert unverified_money("Bạn chi 1.250.000đ, hai khoản cộng lại 300.000đ", results) == []
    assert unverified_money("Bạn chi 9.999.000đ", results) == [9_999_000]


def _tool_call(name: str, args: dict | None = None) -> httpx.Response:
    call = {"id": "c1", "type": "function", "function": {"name": name, "arguments": json.dumps(args or {})}}
    return httpx.Response(200, json={"choices": [{"message": {"content": None, "tool_calls": [call]}}]})


@pytest.mark.anyio
async def test_ollama_mac_dinh_va_chan_so_bia(monkeypatch):
    sent: list[dict] = []
    answers = iter(["Tháng này bạn đã chi 9.999.999đ.", None])

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        sent.append(body)
        assert str(request.url) == "http://localhost:11434/v1/chat/completions"
        assert body["model"] == "qwen2.5:3b" and body["temperature"] == 0.1
        if body["messages"][-1]["role"] != "tool":
            return _tool_call("get_overview")
        real = json.loads(body["messages"][-1]["content"])["this_month"]["expense"]
        assert real.endswith("đ")
        text = next(answers) or f"Tháng này bạn đã chi {real}."
        return httpx.Response(200, json={"choices": [{"message": {"content": text}}]})

    s = get_settings()
    for k, v in {"llm_provider": "ollama", "llm_model": "", "llm_base_url": ""}.items():
        monkeypatch.setattr(s, k, v)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        a = Assistant(http)
        assert a.mode == "ollama"
        bia = await a.chat(snap(), [{"role": "user", "content": "tháng này chi bao nhiêu"}])
        dung = await a.chat(snap(), [{"role": "user", "content": "tháng này chi bao nhiêu"}])
    assert bia.provider == "rules" and bia.fallback_reason == "unverified_numbers"
    assert dung.provider == "ollama" and dung.tools_used == ["get_overview"]


@pytest.fixture
def anyio_backend():
    return "asyncio"


def test_thoi_quen_theo_buoi_va_thu():
    kit = FinanceToolkit(snap())
    r = kit.spending_habits(days=30)
    since = kit.now - timedelta(days=30)
    expense = [t for t in kit.s.transactions if t.kind == "expense" and kit._local(t.date) >= since]
    assert r["count"] == len(expense)
    assert sum(x["total"] for x in r["by_weekday"]) == pytest.approx(r["total"], abs=7)
    assert abs(sum(x["share"] for x in r["by_part_of_day"]) - 1) < 0.01
    assert len(r["by_weekday"]) == 7 and r["highlights"]
    # cà phê trong dữ liệu mẫu luôn ghi lúc 9 giờ sáng
    coffee = kit.spending_habits(query="cà phê", days=30)
    assert [x["part"] for x in coffee["by_part_of_day"]] == ["sáng"]


def test_thoi_quen_khi_khong_ghi_gio():
    data = snap()
    for t in data.transactions:
        t.date = t.date.replace(hour=0, minute=0)
    r = FinanceToolkit(data).spending_habits(days=30)
    assert r["by_part_of_day"] == [] and "không ghi giờ" in r["highlights"][0]


def test_tro_ly_luat_tra_loi_thoi_quen():
    text, used = rules.answer("Mình hay tiêu tiền vào buổi nào?", FinanceToolkit(snap()))
    assert used == ["spending_habits"] and "buổi" in text


@pytest.mark.anyio
async def test_ollama_goi_nham_cong_cu_thi_dung_luat(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        if body["messages"][-1]["role"] != "tool":
            return _tool_call("get_overview")
        return httpx.Response(200, json={"choices": [{"message": {"content": "Bạn tiêu đều mọi ngày."}}]})

    s = get_settings()
    for k, v in {"llm_provider": "ollama", "llm_model": "", "llm_base_url": ""}.items():
        monkeypatch.setattr(s, k, v)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        r = await Assistant(http).chat(snap(), [{"role": "user", "content": "cuối tuần mình có tiêu nhiều hơn không"}])
    assert r.provider == "rules" and r.fallback_reason == "wrong_tool" and r.tools_used == ["spending_habits"]
