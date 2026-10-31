import pytest

from app.services.parser import get_parser
from tests.conftest import CATEGORIES, NOW, PEOPLE, WALLETS


def parse(text):
    return get_parser().parse(text, now=NOW, categories=CATEGORIES, people=PEOPLE, wallets=WALLETS)


@pytest.mark.parametrize("text,kind", [
    ("ăn phở 45k", "expense"), ("nhận lương 15tr", "income"), ("cho Minh mượn 500k", "lend"),
    ("Linh cho mình mượn 200k", "borrow"), ("trả lại chị Hà 500k", "repay"), ("Hà trả nợ 300k", "collect"),
    ("trả lãi vay ngân hàng 1tr", "interestExpense"), ("nhận lãi tiết kiệm 250k", "interestIncome"),
    ("chuyển 2tr từ Vietcombank sang tiết kiệm", "transfer"), ("tiền lãi thẻ tín dụng 150k", "interestExpense"),
])
def test_kinds(text, kind):
    assert parse(text).kind == kind


def test_full_expense():
    r = parse("ăn phở 45k sáng hôm qua")
    assert r.amount == 45_000 and r.category_id == "food" and r.date.day == 19 and r.date_mentioned
    assert r.confidence > 0.6
    assert "45k" not in r.note


def test_new_person_for_lend():
    r = parse("cho Minh mượn 500k")
    assert r.new_person_name == "Minh" and r.person_id is None


def test_known_person_repay():
    assert parse("trả lại chị Hà 500k").person_id == "p1"


def test_transfer_wallets():
    r = parse("chuyển 2tr từ Vietcombank sang tiết kiệm")
    assert r.wallet_id == "bank" and r.destination_id == "save"
