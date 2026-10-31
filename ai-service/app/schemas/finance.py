"""Ảnh chụp dữ liệu tài chính của một người dùng mà backend gửi kèm yêu cầu.

AI service không lưu dữ liệu người dùng (stateless): mọi thứ cần cho một yêu cầu đều nằm trong snapshot.
"""
from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from pydantic import BaseModel, Field

from .common import Budget, Category, LabeledText, Person, Transaction, Wallet

DEFAULT_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


class FinanceSnapshot(BaseModel):
    currency: str = "VND"
    now: datetime | None = Field(default=None, description="Thời điểm hiện tại của người dùng (có múi giờ).")
    wallets: list[Wallet] = Field(default_factory=list, max_length=200)
    categories: list[Category] = Field(default_factory=list, max_length=500)
    people: list[Person] = Field(default_factory=list, max_length=1000)
    transactions: list[Transaction] = Field(default_factory=list, max_length=20000)
    budgets: list[Budget] = Field(default_factory=list, max_length=500)

    def resolved_now(self) -> datetime:
        if self.now is None:
            return datetime.now(DEFAULT_TZ)
        return self.now if self.now.tzinfo else self.now.replace(tzinfo=DEFAULT_TZ)

    def model_post_init(self, __context) -> None:  # noqa: D401
        """Đưa mọi thời điểm về múi giờ của người dùng để so sánh nhất quán."""
        self.now = now = self.resolved_now()
        tz = now.tzinfo
        for t in self.transactions:
            if t.date.tzinfo is None:
                t.date = t.date.replace(tzinfo=tz)
            else:
                t.date = t.date.astimezone(tz)

    def history(self) -> list[LabeledText]:
        """Ghi chú đã gán danh mục -> dữ liệu cá nhân hóa cho bộ phân loại."""
        return [LabeledText(text=t.note[:500], categoryId=t.categoryId)
                for t in self.transactions if t.note.strip() and t.categoryId][-2000:]

    def category_names(self) -> dict[str, str]:
        return {c.id: c.name for c in self.categories}
