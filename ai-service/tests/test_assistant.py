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


@pytest.mark.parametrize(
    ("question", "intent"),
    [
        ("Thu nhập tháng này có giảm không?", "overview"),
        ("thu nhập tháng 11 là bao nhiêu", "overview"),
        ("Cuối tuần này mình đã chi bao nhiêu?", "overview"),
        ("nếu ăn phở bò mỗi ngày thì sao", "overview"),
        ("Nếu bớt phở bò thì tiết kiệm được bao nhiêu?", "simulate"),
        ("thêm khoản đổ xăng 80k", "record"),
        ("Tổng chi tháng này là bao nhiêu?", "overview"),
        ("trung bình mỗi ngày mình chi bao nhiêu", "overview"),
        ("có khoản nào lạ không", "anomaly"),
        ("cuối tuần mình có tiêu nhiều hơn không", "habits"),
    ],
)
def test_khong_khop_nham_y_dinh(question, intent):
    assert rules.detect_intent(question) == intent


def test_tham_so_dang_chuoi_van_tinh_duoc():
    kit = FinanceToolkit(snap())
    r = kit.call("simulate_saving", {"query": "cà phê", "reduce_percent": "20", "target_times": "10"})
    assert r["by_frequency"]["suggested_times_per_month"] == 10 and r["by_percent"][0]["reduce_percent"] == 20
    assert "error" in kit.call("spending_habits", {"days": "nhiều"})


def test_simulate_args_follow_question():
    from app.services.llm.assistant import pin_simulate_args

    q = "Nếu bớt uống trà sữa xuống 5 lần thì tiết kiệm được bao nhiêu?"
    got = pin_simulate_args(q, {"query": "trà sữa", "reduce_percent": 50})
    assert got == {"query": "trà sữa", "target_times": 5}
    got = pin_simulate_args("nếu giảm 20% cà phê thì sao", {"query": "cà phê", "target_times": 3})
    assert got == {"query": "cà phê", "reduce_percent": 20}
    assert pin_simulate_args("nếu bớt trà sữa", {"query": "trà sữa"}) == {"query": "trà sữa"}


@pytest.mark.parametrize(
    ("question", "intent", "query"),
    [
        ("nếu ít tiền thì nên làm gì", "advice", None),
        ("nếu tôi giảm chi 20% thì tiết kiệm được bao nhiêu", "simulate", ""),
        ("nếu giảm chi tiêu cho cà phê thì sao", "simulate", "cà phê"),
        ("thử cắt trà sữa 50%", "simulate", "trà sữa"),
    ],
)
def test_simulate_needs_target(question, intent, query):
    assert rules.detect_intent(question) == intent
    if query is not None:
        assert rules.simulate_args(question)["query"] == query


def test_rules_empty_data_reads_cleanly():
    empty = FinanceSnapshot(now=NOW, wallets=[], categories=[], people=[], transactions=[])
    text, _ = rules.answer("ví nào còn nhiều tiền nhất", FinanceToolkit(empty))
    assert text == "Tổng số dư các ví: 0đ."
    text, _ = rules.answer("dự báo cuối tháng", FinanceToolkit(empty))
    assert "Chưa có khoản chi" in text


@pytest.mark.anyio
async def test_ollama_cham_qua_thi_dung_luat(monkeypatch):
    import asyncio

    async def handler(request: httpx.Request) -> httpx.Response:
        await asyncio.sleep(1)
        return _tool_call("get_overview")

    s = get_settings()
    for k, v in {"llm_provider": "ollama", "llm_model": "", "llm_base_url": "", "llm_total_seconds": 0.05}.items():
        monkeypatch.setattr(s, k, v)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        r = await Assistant(http).chat(snap(), [{"role": "user", "content": "tháng này chi bao nhiêu"}])
    assert r.provider == "rules" and r.fallback_reason == "llm_timeout" and r.tools_used == ["get_overview"]


@pytest.mark.anyio
async def test_ollama_doi_so_lan_thanh_phan_tram_van_tinh_dung(monkeypatch):
    seen: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        if body["messages"][-1]["role"] != "tool":
            # mô hình hiểu nhầm "xuống 5 lần" thành giảm 50%
            return _tool_call("simulate_saving", {"query": "trà sữa", "reduce_percent": 50})
        seen.append(json.loads(body["messages"][-1]["content"]))
        return httpx.Response(200, json={"choices": [{"message": {"content": seen[-1]["summary"][0]}}]})

    s = get_settings()
    for k, v in {"llm_provider": "ollama", "llm_model": "", "llm_base_url": ""}.items():
        monkeypatch.setattr(s, k, v)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        q = "Nếu bớt trà sữa xuống 2 lần thì tiết kiệm được bao nhiêu?"
        r = await Assistant(http).chat(snap(), [{"role": "user", "content": q}])
    assert seen[0]["by_frequency"]["suggested_times_per_month"] == 2 and seen[0]["by_percent"] == []
    assert r.provider == "ollama" and "còn 2 lần" in r.reply


def test_mo_phong_bot_chung_va_chi_theo_phan_tram():
    kit = FinanceToolkit(snap())
    since = kit.now - timedelta(days=30)
    spent = sum(t.amount for t in kit.s.transactions if t.kind == "expense" and kit._local(t.date) >= since)
    r = kit.simulate_saving("tất cả", reduce_percent=20)
    assert r["query"] == "tổng chi tiêu" and r["by_frequency"] is None
    assert r["by_percent"][0]["monthly_saving"] == round(spent * 0.2, -3)
    # hỏi theo % thì chỉ trả phương án % để mô hình không lấy nhầm số
    only = kit.simulate_saving("cà phê", reduce_percent=30)
    assert only["by_frequency"] is None and len(only["summary"]) == 1
    text, _ = rules.answer("nếu tôi giảm chi 20% thì tiết kiệm được bao nhiêu", kit)
    assert "tổng cộng" in text and "Giảm 20%" in text


def test_trung_binh_moi_ngay_va_thu_nhap_thang_truoc():
    kit = FinanceToolkit(snap())
    o = kit.get_overview()["this_month"]
    assert o["daily_average_spent"] == round(o["expense"] / NOW.day)
    text, _ = rules.answer("chi trung bình mỗi ngày là bao nhiêu", kit)
    assert "/ngày" in text
    text, _ = rules.answer("thu nhập tháng này có giảm không", kit)
    assert "Tháng trước bạn thu" in text


def test_chao_hoi():
    text, used = rules.answer("xin chào", FinanceToolkit(snap()))
    assert text.startswith("Chào bạn") and used == []
    assert rules.detect_intent("chào bạn, ghi cà phê 30k") != "greet"


@pytest.mark.anyio
async def test_ollama_lo_ten_tham_so_thi_dung_luat(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        if body["messages"][-1]["role"] != "tool":
            return _tool_call("get_overview")
        text = 'Mình không so sánh được vì thiếu tham số "end".'
        return httpx.Response(200, json={"choices": [{"message": {"content": text}}]})

    s = get_settings()
    for k, v in {"llm_provider": "ollama", "llm_model": "", "llm_base_url": ""}.items():
        monkeypatch.setattr(s, k, v)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        r = await Assistant(http).chat(snap(), [{"role": "user", "content": "thu nhập tháng này có giảm không"}])
    assert r.provider == "rules" and r.fallback_reason == "leaked_internals"


def test_chi_vuot_xa_thang_truoc_noi_gap_may_lan():
    data = snap()
    last = NOW.replace(day=1) - timedelta(days=3)
    data.transactions = [t for t in data.transactions if t.date.month == NOW.month or t.date.date() == last.date()]
    text, _ = rules.answer("tháng này chi bao nhiêu", FinanceToolkit(data))
    assert "lần cả tháng trước" in text and "%" not in text
