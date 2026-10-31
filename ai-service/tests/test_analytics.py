from datetime import timedelta

from app.schemas.common import Transaction
from app.services import anomaly, budget, forecaster, receipt, search
from tests.conftest import CATEGORIES, NOW


def test_holt_tracks_trend():
    import numpy as np
    y = np.arange(10, 30, dtype=float)
    fc, _ = forecaster.holt_forecast(y, 2)
    assert abs(fc[0] - 30) < 1.5 and abs(fc[1] - 31) < 2


def test_holt_winters_seasonality():
    import numpy as np
    season = np.array([0, 5, 10, 5, 0, -5, -10, -5, 0, 5, 10, 5], dtype=float)
    y = np.concatenate([100 + season] * 3)
    fc, _ = forecaster.holt_winters_forecast(y, 12, 3)
    assert np.allclose(fc, 100 + season[:3], atol=2)


def test_forecast_month(transactions):
    f = forecaster.forecast_month(transactions, NOW)
    assert f.spent > 0 and f.lower <= f.projected <= f.upper
    assert f.projected > f.spent and f.days_left == 11
    assert "weekday_profile" in f.method and f.next_month is not None
    assert "food" in f.by_category


def test_forecast_empty():
    f = forecaster.forecast_month([], NOW)
    assert f.spent == 0 and f.projected == 0


def test_anomaly_large_and_duplicate(transactions):
    big = Transaction(id="big", kind="expense", amount=2_500_000, date=NOW - timedelta(days=2), categoryId="food", note="Nhà hàng")
    d1 = Transaction(id="d1", kind="expense", amount=123_000, date=NOW - timedelta(days=1), categoryId="self", note="áo")
    d2 = Transaction(id="d2", kind="expense", amount=123_000, date=NOW - timedelta(days=1, minutes=-3), categoryId="self", note="áo")
    found, _ = anomaly.detect(transactions + [big, d1, d2], NOW, categories={"food": "Ăn uống"})
    ids = {a.transaction_id: a for a in found}
    assert "big" in ids and "Ăn uống" in ids["big"].reasons[0]
    assert "d2" in ids and ids["d2"].kind == "duplicate"
    assert all(a.transaction_id not in {"t1", "t2"} for a in found)


def test_category_spike(transactions):
    extra = [Transaction(id=f"s{i}", kind="expense", amount=400_000, date=NOW - timedelta(days=i), categoryId="transport",
                         note="taxi") for i in range(1, 8)]
    _, spikes = anomaly.detect(transactions + extra, NOW)
    assert spikes and spikes[0].category_id == "transport"


def test_budget_recommend(transactions):
    r = budget.recommend(transactions, CATEGORIES, NOW, savings_rate=0.2)
    by = {s.category_id: s for s in r["suggestions"]}
    assert by["house"].amount == 5_000_000 and by["house"].group == "needs"
    assert by["coffee"].group == "wants"
    assert all(s.amount % 50_000 == 0 for s in r["suggestions"])
    assert r["plan"]["income"] == 18_000_000


def test_budget_cuts_wants_when_over():
    txs = []
    for m in range(1, 7):
        d = NOW.replace(month=NOW.month - m, day=10)
        txs += [Transaction(id=f"i{m}", kind="income", amount=10_000_000, date=d, categoryId="salary"),
                Transaction(id=f"h{m}", kind="expense", amount=6_000_000, date=d, categoryId="house"),
                Transaction(id=f"s{m}", kind="expense", amount=4_000_000, date=d, categoryId="self")]
    r = budget.recommend(txs, CATEGORIES, NOW, savings_rate=0.2)
    by = {s.category_id: s.amount for s in r["suggestions"]}
    assert by["house"] == 6_000_000 and by["self"] == 2_000_000


RECEIPT = """CỬA HÀNG TIỆN LỢI CIRCLE K
Địa chỉ: 12 Lê Lợi, Q1
HÓA ĐƠN BÁN HÀNG
Ngày: 18/10/2026 19:32
Nước suối Lavie 2 x 6.000 12.000
Bánh mì sandwich 25.000
Mì ly Hảo Hảo 9.000
Tạm tính 46.000
Giảm giá 0
TỔNG CỘNG 46.000
Tiền khách đưa 100.000
Tiền thối lại 54.000"""


def test_receipt_text():
    r = receipt.parse_receipt_text(RECEIPT)
    assert r.total == 46_000 and r.merchant.startswith("CỬA HÀNG")
    assert r.date.day == 18 and r.date.month == 10
    assert [i.amount for i in r.items] == [12_000, 25_000, 9_000]
    assert r.confidence >= 0.8 and "tiền khách đưa − tiền thừa" in r.checks


def test_receipt_llm_json():
    r = receipt.from_llm_json('Kết quả: {"merchant":"Highlands","date":"2026-10-01","total":59000,'
                              '"items":[{"name":"Phin sữa","amount":59000}]}')
    assert r.total == 59_000 and r.items[0].name == "Phin sữa"


def test_search(transactions):
    flt, hits = search.search("cafe tháng này", transactions, CATEGORIES, NOW)
    assert flt.start.day == 1 and hits
    top = {t.categoryId for t, _ in hits[:5]}
    assert top == {"coffee"}
    flt, hits = search.search("chi trên 1tr", transactions, CATEGORIES, NOW)
    assert flt.min_amount == 1_000_000 and all(t.amount >= 1_000_000 for t, _ in hits)
