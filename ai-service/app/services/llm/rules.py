from __future__ import annotations

import re
import unicodedata

from app.nlp.entities import find_amount
from app.nlp.text import fold

from .tools import FinanceToolkit


def _vnd(x: float | None) -> str:
    if x is None:
        return "—"
    return f"{round(x):,}".replace(",", ".") + "đ"


INTENTS: list[tuple[str, str]] = [
    (r"\b(so du|con bao nhieu tien|tong tai san)\b", "balance"),
    (r"\b(duoc chi|nen chi|chi duoc|chi toi da|goi y chi tieu|moi ngay chi)\b", "allowance"),
    (r"\b(bat thuong|dot bien|kha nghi)\b", "anomaly"),
    (r"\b(goi y|de xuat|nen dat|lap)\b.*\bngan sach\b|\bngan sach\b.*\b(goi y|nen)\b", "recommend"),
    (r"\b(du bao|cuoi thang|se tieu|het thang|thang sau)\b", "forecast"),
    (r"\bngan sach\b|\bvuot\b|\bhan muc\b", "budget"),
    (r"\b(no|vay|muon|cho vay)\b", "debts"),
    (r"\bvi\b", "balance"),
    (r"\b(danh muc|nhieu nhat|tieu vao|chi vao|co cau)\b", "categories"),
    (r"\b(tiet kiem|meo|loi khuyen|lam sao|bot tieu|lam gi de|nen lam gi)\b", "advice"),
    (r"\b(tim|giao dich|khoan|lan nao|nhung lan|mua o dau)\b", "find"),
    (r"\b(tong quan|thang nay|chi bao nhieu|thu bao nhieu|tinh hinh)\b", "overview"),
]


# xét trên chữ có dấu: bỏ dấu thì "thu nhập" thành "thu nhap", "phở bò" thành "pho bo" và dễ khớp nhầm
STRICT_INTENTS: list[tuple[str, str]] = [
    (r"\b(nếu|thử)\b.*\b(bớt|giảm|cắt|ít|hạn chế|bỏ)\b|tiết kiệm được bao nhiêu|mô phỏng", "simulate"),
    (r"(?<!thu )\b(ghi|thêm|nhập|lưu)\b.*\d", "record"),
    (
        r"thói quen|hành vi|khung giờ|buổi nào|lúc nào|thứ mấy|ngày nào trong tuần"
        r"|cuối tuần.*(nhiều hơn|ít hơn|so với|hay)|(nhiều hơn|ít hơn).*cuối tuần",
        "habits",
    ),
    (r"^\W*(xin chào|chào|hello|hi|hey|alo)\b(?!.*\d)", "greet"),
    # "lạ", "trùng" bỏ dấu thành "la", "trung" sẽ khớp cả "là", "trung bình"
    (r"\b(lạ|trùng)\b", "anomaly"),
]


def detect_intent(question: str) -> str:
    text = unicodedata.normalize("NFC", question).lower()
    for pattern, intent in STRICT_INTENTS:
        # "nếu ít tiền thì..." có chữ "ít" nhưng không nói bớt khoản nào, để luật thường xử lý
        if re.search(pattern, text) and (intent != "simulate" or _has_target(simulate_args(question))):
            return intent
    f = fold(question)
    for pattern, intent in INTENTS:
        if re.search(pattern, f):
            return intent
    return "overview"


_SIM_TARGET = re.compile(
    r"\b(?:bot|giam|cat|it|han che|bo)\s+(?:uong|mua|an|di|choi|tieu|chi|di an)?\s*(.+?)"
    r"(?:\s+(?:thi|xuong|con|di|moi|mot|duoc|lai|khoang|tu)\b.*|\s+\d.*|\s*[?.!]*)$"
)


def simulate_args(question: str) -> dict:
    text = unicodedata.normalize("NFC", question).lower()
    f = fold(text)
    m = _SIM_TARGET.search(f)
    # fold giữ nguyên độ dài chuỗi nên cắt lại được bản có dấu để hiển thị
    query = text[m.start(1) : m.end(1)] if m else ""
    query = re.sub(r"\b(tiền|khoản|các|những|việc)\b|\d+\s*%?", " ", query)
    # "giảm chi 20%" là bớt chung chung, không phải một khoản cụ thể
    query = re.sub(r"^((chi tiêu|chi|tiêu)\s*)?(cho|vào)\s+|^(chi tiêu|chi|tiêu)$", "", " ".join(query.split()))
    args: dict = {"query": query}
    if p := re.search(r"(\d{1,2})\s*%", f):
        args["reduce_percent"] = int(p.group(1))
    if t := re.search(r"(?:xuong|con|giu)\s*(\d{1,2})\s*lan", f):
        args["target_times"] = int(t.group(1))
    return args


def _has_target(args: dict) -> bool:
    # bớt một khoản cụ thể, hoặc bớt chung chung nhưng có nói bao nhiêu %
    return bool(args["query"] or "reduce_percent" in args)


def answer(question: str, kit: FinanceToolkit) -> tuple[str, list[str]]:
    intent = detect_intent(question)
    if intent == "greet":
        return (
            "Chào bạn! Mình có thể xem tình hình thu chi, dự báo cuối tháng, gợi ý ngân sách, "
            'tìm giao dịch hay ghi nhanh một khoản như "ăn trưa 45k". Bạn muốn xem gì?'
        ), []
    if intent == "habits":
        r = kit.spending_habits()
        if not r["count"]:
            return r["note"], ["spending_habits"]
        lines = [f"Trong {r['period_days']} ngày qua (tổng chi {_vnd(r['total'])}):"]
        lines += [f"• {x}" for x in r["highlights"]]
        return "\n".join(lines), ["spending_habits"]
    if intent == "simulate":
        args = simulate_args(question)
        if not _has_target(args):
            return 'Bạn muốn bớt khoản nào? Ví dụ: "nếu bớt trà sữa thì tiết kiệm được bao nhiêu".', []
        r = kit.simulate_saving(**args)
        if not r["count"]:
            return r["note"], ["simulate_saving"]
        if args["query"]:
            head = (
                f"30 ngày qua bạn chi cho {r['query']} {r['count']} lần, tổng {_vnd(r['total_spent'])} "
                f"(trung bình {_vnd(r['average_price'])}/lần)."
            )
        else:
            head = f"30 ngày qua bạn chi tổng cộng {_vnd(r['total_spent'])}."
        lines = [head] + [f"• {x}." for x in r["summary"]]
        lines.append("Đây là khoản tiết kiệm tiềm năng, chưa phải tiền đã để dành.")
        return "\n".join(lines), ["simulate_saving"]
    if intent == "record" and find_amount(question):
        text = re.sub(
            r"^\s*(hãy\s+)?(ghi|thêm|nhập|lưu)(\s+giúp|\s+hộ)?(\s+(tôi|mình|em))?\s*(là|:)?\s*",
            "",
            question,
            flags=re.I,
        )
        r = kit.propose_transaction(text or question)
        if "error" in r:
            return r["error"], ["propose_transaction"]
        p = r["proposed"]
        return (
            f"Mình đã chuẩn bị giao dịch {_vnd(p['amount'])}"
            + (f" vào danh mục {p['category']}" if p.get("category") else "")
            + ". Bấm Xác nhận để lưu nhé."
        ), ["propose_transaction"]

    if intent == "allowance":
        a = kit.get_spending_allowance()
        if a["daily_allowance"] is None:
            return (
                "Mình chưa có ngân sách tổng hay thu nhập tháng này để tính mức chi mỗi ngày. "
                "Hãy đặt ngân sách tổng tháng nhé."
            ), ["get_spending_allowance"]
        basis = "ngân sách tổng" if a["basis"] == "budget" else "thu nhập sau khi để dành 20%"
        lines = [
            f"Theo {basis} ({_vnd(a['month_limit'])}), từ nay đến cuối tháng bạn nên chi tối đa "
            f"{_vnd(a['daily_allowance'])}/ngày.",
            f"Hôm nay đã chi {_vnd(a['spent_today'])}, "
            + (f"còn {_vnd(a['left_today'])}." if a["left_today"] >= 0 else f"vượt {_vnd(-a['left_today'])}."),
        ]
        lines += [f"• {b['category']}: còn {_vnd(b['remaining'])}" for b in a["tight_budgets"][:3]]
        return "\n".join(lines), ["get_spending_allowance"]

    if intent == "forecast":
        f = kit.forecast_month()
        if not f["spent_so_far"] and not f["next_month_estimate"]:
            return "Chưa có khoản chi nào để dự báo. Ghi thêm vài giao dịch rồi hỏi lại nhé.", ["forecast_month"]
        lines = [
            f"Đến nay bạn đã chi {_vnd(f['spent_so_far'])}.",
            f"Dự báo cả tháng khoảng {_vnd(f['projected_month_total'])} "
            f"(80% khả năng trong {_vnd(f['range_80pct'][0])} – {_vnd(f['range_80pct'][1])}).",
        ]
        if f["next_month_estimate"]:
            lines.append(f"Ước tính tháng sau: {_vnd(f['next_month_estimate'])}.")
        return " ".join(lines), ["forecast_month"]

    if intent == "anomaly":
        a = kit.get_anomalies()
        if not a["anomalies"] and not a["category_spikes"]:
            return "Mình chưa thấy giao dịch nào bất thường trong 30 ngày qua.", ["get_anomalies"]
        lines = [f"• {x['date']}: {_vnd(x['amount'])} {x['note']} — {x['reasons'][0]}" for x in a["anomalies"][:5]]
        lines += [f"• {s['category']} tăng gấp {s['ratio']} lần so với trung bình" for s in a["category_spikes"][:3]]
        return "Một số điểm đáng chú ý:\n" + "\n".join(lines), ["get_anomalies"]

    if intent == "recommend":
        r = kit.recommend_budgets()
        if not r["suggestions"]:
            return "Chưa đủ lịch sử chi tiêu (cần ít nhất một tháng trọn) để gợi ý ngân sách.", ["recommend_budgets"]
        lines = [f"• {s['category']}: {_vnd(s['amount'])}" for s in r["suggestions"]]
        return "Gợi ý ngân sách tháng dựa trên lịch sử của bạn:\n" + "\n".join(lines), ["recommend_budgets"]

    if intent == "budget":
        b = kit.get_budget_status()
        if not b["budgets"]:
            return 'Bạn chưa đặt ngân sách nào cho tháng này. Hỏi "gợi ý ngân sách" để mình đề xuất nhé.', [
                "get_budget_status"
            ]
        lines = []
        for x in b["budgets"]:
            tag = {"over": "đã vượt", "at_risk": "có nguy cơ vượt", "ok": "ổn"}[x["status"]]
            lines.append(f"• {x['category']}: dùng {_vnd(x['used'])}/{_vnd(x['limit'])} ({tag})")
        return "Ngân sách tháng này:\n" + "\n".join(lines), ["get_budget_status"]

    if intent == "debts":
        d = kit.get_debts()
        if not d["others_owe_me"] and not d["i_owe_others"]:
            return "Hiện không có khoản vay hay cho vay nào còn dư nợ.", ["get_debts"]
        parts = []
        if d["others_owe_me"]:
            parts.append(
                "Người khác nợ bạn: " + ", ".join(f"{x['person']} {_vnd(x['amount'])}" for x in d["others_owe_me"])
            )
        if d["i_owe_others"]:
            parts.append("Bạn đang nợ: " + ", ".join(f"{x['person']} {_vnd(x['amount'])}" for x in d["i_owe_others"]))
        return ". ".join(parts) + ".", ["get_debts"]

    if intent == "categories":
        c = kit.get_category_spending("this_month")
        if not c["categories"]:
            return "Tháng này chưa có khoản chi nào.", ["get_category_spending"]
        top = c["categories"][:3]
        return (
            "Tháng này bạn chi nhiều nhất cho "
            + ", ".join(f"{x['name']} ({_vnd(x['amount'])}, {round(x['share'] * 100)}%)" for x in top)
            + "."
        ), ["get_category_spending"]

    if intent == "find":
        query = re.sub(r"\b(tim|tìm|giao dịch|khoản|các|những)\b", " ", question, flags=re.I).strip()
        r = kit.find_transactions(query=query, days=90)
        if not r["count"]:
            return "Không tìm thấy giao dịch phù hợp trong 90 ngày qua.", ["find_transactions"]
        lines = [f"• {t['date']}: {_vnd(t['amount'])} {t['note']}" for t in r["transactions"][:8]]
        return f"Tìm thấy {r['count']} giao dịch:\n" + "\n".join(lines), ["find_transactions"]

    o = kit.get_overview()
    if intent == "balance":
        wallets = ", ".join(f"{w['name']}: {_vnd(w['balance'])}" for w in o["wallets"])
        return f"Tổng số dư các ví: {_vnd(o['total_balance'])}." + (f" {wallets}." if wallets else ""), ["get_overview"]

    tm, lm = o["this_month"], o["last_month"]
    msg = f"Tháng này bạn thu {_vnd(tm['income'])}, chi {_vnd(tm['expense'])}."
    f = fold(question)
    if re.search(r"\btrung binh\b", f):
        msg += f" Trung bình {_vnd(tm['daily_average_spent'])}/ngày trong {tm['days_passed']} ngày qua."
    if re.search(r"\bthu nhap\b", f):
        msg += f" Tháng trước bạn thu {_vnd(lm['income'])}."
    if lm["expense"]:
        ratio = tm["expense"] / lm["expense"]
        # tháng trước chi rất ít thì "1400%" khó hiểu, nói "gấp mấy lần" dễ đọc hơn
        if ratio >= 2:
            times = f"{ratio:.1f}".replace(".", ",")
            msg += f" Đã gấp {times} lần cả tháng trước ({_vnd(lm['expense'])})."
        else:
            msg += f" So với cả tháng trước ({_vnd(lm['expense'])}) bạn đã dùng {round(ratio * 100)}%."
    if intent == "advice":
        c = kit.get_category_spending("this_month")
        if c["categories"]:
            top = c["categories"][0]
            msg += (
                f" Danh mục lớn nhất là {top['name']} ({round(top['share'] * 100)}%): thử đặt ngân sách cho nó"
                " và chuyển tự động 10–20% thu nhập vào ví tiết kiệm ngay khi nhận lương."
            )
    return msg, ["get_overview"]
