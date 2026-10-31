"""Dữ liệu mẫu dùng chung cho các bài kiểm thử."""
from __future__ import annotations

import itertools
import os
import random
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient

from app.schemas.common import Category, Person, Transaction, Wallet
from app.schemas.finance import FinanceSnapshot

# Không để tệp .env của máy phát triển ảnh hưởng kiểm thử (biến môi trường được ưu tiên hơn .env).
for _k in ("SERVICE_API_KEY", "LLM_PROVIDER", "LLM_API_KEY", "LLM_MODEL", "LLM_BASE_URL", "VISION_MODEL"):
    os.environ[_k] = ""

TZ = ZoneInfo("Asia/Ho_Chi_Minh")
NOW = datetime(2026, 10, 20, 12, 0, tzinfo=TZ)

CATEGORIES = [
    Category(id="food", name="Ăn uống"), Category(id="transport", name="Đi lại"), Category(id="house", name="Nhà cửa"),
    Category(id="self", name="Bản thân"), Category(id="health", name="Sức khỏe"), Category(id="life", name="Sinh hoạt"),
    Category(id="salary", name="Lương", income=True), Category(id="bonus", name="Thưởng", income=True),
    Category(id="coffee", name="Cà phê"),  # danh mục người dùng tự tạo
]
PEOPLE = [Person(id="p1", name="Hà"), Person(id="p2", name="Linh")]
WALLETS = [Wallet(id="cash", name="Tiền mặt", balance=2_000_000), Wallet(id="bank", name="Vietcombank", balance=15_000_000),
           Wallet(id="save", name="Tiết kiệm", savings=True, balance=30_000_000)]


def make_transactions(days: int = 200, seed: int = 7) -> list[Transaction]:
    rnd = random.Random(seed)
    out: list[Transaction] = []
    start = NOW - timedelta(days=days)
    ids = itertools.count()
    for i in range(days + 1):
        d = (start + timedelta(days=i)).replace(hour=8, minute=0)
        if d > NOW:
            break
        weekend = d.weekday() >= 5
        meals = [("Phở bò", 45_000), ("Cơm trưa văn phòng", 40_000), ("Bún chả", 50_000)]
        name, base = rnd.choice(meals)
        out.append(Transaction(id=f"t{next(ids)}", kind="expense", amount=base * (1.6 if weekend else 1), date=d.replace(hour=12),
                               categoryId="food", note=name))
        if rnd.random() < 0.7:
            out.append(Transaction(id=f"t{next(ids)}", kind="expense", amount=rnd.choice([29_000, 35_000, 55_000]), date=d.replace(hour=9),
                                   categoryId="coffee", note=rnd.choice(["cf sáng", "highlands", "trà sữa"])))
        if rnd.random() < 0.3:
            out.append(Transaction(id=f"t{next(ids)}", kind="expense", amount=rnd.choice([30_000, 60_000]), date=d.replace(hour=18),
                                   categoryId="transport", note=rnd.choice(["grab về nhà", "đổ xăng"])))
        if d.day == 5:
            out.append(Transaction(id=f"t{next(ids)}", kind="income", amount=18_000_000, date=d, categoryId="salary", note="Lương tháng"))
            out.append(Transaction(id=f"t{next(ids)}", kind="expense", amount=5_000_000, date=d.replace(hour=20), categoryId="house",
                                   note="Tiền nhà"))
    return out


@pytest.fixture
def transactions() -> list[Transaction]:
    return make_transactions()


@pytest.fixture
def snapshot(transactions) -> FinanceSnapshot:
    return FinanceSnapshot(now=NOW, wallets=WALLETS, categories=CATEGORIES, people=PEOPLE, transactions=transactions)


@pytest.fixture(scope="session")
def client():
    from app.main import create_app

    with TestClient(create_app()) as c:
        yield c
