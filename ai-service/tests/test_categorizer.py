from app.schemas.common import LabeledText
from app.services.categorizer import get_categorizer
from tests.conftest import CATEGORIES


def top(text, history=None, income=False):
    preds, info = get_categorizer().predict(text, CATEGORIES, history, income=income)
    return preds[0].category_id, info


def test_global_model():
    assert top("bún bò huế")[0] == "food"
    assert top("đổ xăng xe máy")[0] == "transport"
    assert top("tiền điện tháng 10")[0] == "life"  # hóa đơn điện nước thuộc Sinh hoạt
    assert top("tiền thuê nhà")[0] == "house"
    assert top("mua thuốc cảm")[0] == "health"
    assert top("lương tháng 10", income=True)[0] == "salary"


def test_unaccented_and_abbreviations():
    assert top("an trua")[0] == "food"
    assert top("grab di lam")[0] == "transport"


def test_personalization_custom_category():
    history = [LabeledText(text=t, categoryId="coffee") for t in ["highlands", "cf sáng", "phúc long", "cà phê sữa"]]
    cid, info = top("highlands coffee", history)
    assert cid == "coffee" and info["personal_weight"] > 0.3


def test_custom_category_without_history_is_not_guessed():
    preds, _ = get_categorizer().predict("abc", [c for c in CATEGORIES if c.id == "coffee"], None, income=False)
    assert preds == []
