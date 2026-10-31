from datetime import datetime

import pytest

from app.nlp.entities import find_amount, find_date, find_person
from app.nlp.text import fold


@pytest.mark.parametrize("text,value", [
    ("ăn phở 45k", 45_000), ("lương 15tr", 15_000_000), ("mua laptop 1tr2", 1_200_000),
    ("tiền nhà 3,5 triệu", 3_500_000), ("đổ xăng 200.000đ", 200_000), ("phở 45", 45_000),
    ("2 ly cà phê 60k", 60_000), ("vay ngân hàng 1 tỷ", 1_000_000_000), ("ngày 5 đóng học 2tr", 2_000_000),
])
def test_amounts(text, value):
    assert find_amount(text).value == value


def test_no_amount():
    assert find_amount("đi chợ hôm qua") is None


def test_dates():
    now = datetime(2026, 10, 20, 12, 0)
    assert find_date("ăn tối hôm qua 100k", now)[0].day == 19
    d, mentioned = find_date("mua sách 5/10", now)
    assert (d.month, d.day, mentioned) == (10, 5, True)
    assert find_date("cà phê", now) == (now.replace(second=0, microsecond=0), False)


def test_fold():
    assert fold("Đường Lê Lợi") == "duong le loi"


def test_person_known_and_new():
    people = [{"id": "p1", "name": "Hà"}]
    assert find_person("trả chị Hà 500k", people)[0] == "p1"
    pid, new = find_person("cho Minh mượn 500k", people)
    assert pid is None and new == "Minh"
