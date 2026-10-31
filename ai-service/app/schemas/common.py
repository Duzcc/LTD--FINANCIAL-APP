"""Kiểu dữ liệu dùng chung giữa các API."""
from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

Kind = Literal["expense", "income", "transfer", "lend", "collect", "interestIncome", "borrow", "repay", "interestExpense"]
INCOME_KINDS = {"income", "interestIncome"}
EXPENSE_KINDS = {"expense", "interestExpense"}


class Category(BaseModel):
    id: str
    name: str
    income: bool = False


class Person(BaseModel):
    id: str
    name: str


class Wallet(BaseModel):
    id: str
    name: str
    currency: str = "VND"
    balance: float = 0
    savings: bool = False
    target: float = 0


class LabeledText(BaseModel):
    """Ví dụ trong lịch sử người dùng: ghi chú và danh mục họ đã chọn."""
    text: str = Field(max_length=500)
    categoryId: str


class Transaction(BaseModel):
    id: str
    kind: Kind
    amount: float = Field(ge=0)
    date: datetime
    categoryId: str | None = None
    personId: str | None = None
    walletId: str | None = None
    note: str = ""
    excluded: bool = False


class Budget(BaseModel):
    id: str | None = None
    categoryId: str | None = None
    amount: float
    used: float = 0
    income: bool = False
