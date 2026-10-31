"""Danh mục chuẩn mà mô hình toàn cục được huấn luyện (trùng mã danh mục mặc định của app)."""
from app.nlp.text import fold

GLOBAL_CATEGORIES = {
    "food": ("Ăn uống", False), "life": ("Sinh hoạt", False), "house": ("Nhà cửa", False),
    "self": ("Bản thân", False), "transport": ("Đi lại", False), "health": ("Sức khỏe", False),
    "child": ("Con cái", False), "salary": ("Lương", True), "bonus": ("Thưởng", True),
    "business": ("Kinh doanh", True), "other_income": ("Thu nhập khác", True),
}
# Nhóm "thiết yếu" theo quy tắc 50/30/20
NEEDS = {"food", "life", "house", "transport", "health", "child"}


def global_label_for(category_id: str, name: str) -> str | None:
    """Ánh xạ danh mục của người dùng sang nhãn toàn cục theo mã hoặc theo tên."""
    if category_id in GLOBAL_CATEGORIES:
        return category_id
    n = fold(name).strip()
    for label, (gname, _) in GLOBAL_CATEGORIES.items():
        if fold(gname) == n:
            return label
    return None
