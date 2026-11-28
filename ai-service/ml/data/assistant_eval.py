"""Bộ câu hỏi tiếng Việt để đo trợ lý chọn đúng việc cần làm (công cụ) hay không."""

from __future__ import annotations

# ý định -> công cụ trợ lý phải gọi
INTENT_TOOL = {
    "overview": "get_overview",
    "balance": "get_overview",
    "advice": "get_overview",
    "categories": "get_category_spending",
    "forecast": "forecast_month",
    "allowance": "get_spending_allowance",
    "find": "find_transactions",
    "budget": "get_budget_status",
    "debts": "get_debts",
    "anomaly": "get_anomalies",
    "recommend": "recommend_budgets",
    "record": "propose_transaction",
    "simulate": "simulate_saving",
    "habits": "spending_habits",
}

QUESTIONS: list[tuple[str, str]] = [
    # tổng quan
    ("Tháng này tôi đã tiêu bao nhiêu tiền?", "overview"),
    ("tháng này chi bao nhiêu rồi", "overview"),
    ("Tình hình tài chính của mình tháng này thế nào?", "overview"),
    ("thang nay thu bao nhieu", "overview"),
    ("Cho mình xem tổng quan", "overview"),
    # số dư
    ("Tôi còn bao nhiêu tiền?", "balance"),
    ("số dư các ví", "balance"),
    ("Tổng tài sản hiện tại là bao nhiêu?", "balance"),
    ("ví tiền mặt còn nhiêu", "balance"),
    # danh mục
    ("Tôi tiêu vào đâu nhiều nhất?", "categories"),
    ("Danh mục nào chi nhiều nhất tháng này?", "categories"),
    ("cơ cấu chi tiêu của mình", "categories"),
    ("tháng này chi vào ăn uống bao nhiêu", "categories"),
    # dự báo
    ("Dự báo cuối tháng tôi tiêu bao nhiêu?", "forecast"),
    ("hết tháng mình sẽ tiêu khoảng bao nhiêu", "forecast"),
    ("tháng sau chắc tiêu bao nhiêu", "forecast"),
    # mức được chi
    ("Hôm nay mình được chi bao nhiêu?", "allowance"),
    ("mỗi ngày nên chi bao nhiêu để không vượt", "allowance"),
    ("tuần này chi tối đa bao nhiêu thì ổn", "allowance"),
    # tìm giao dịch
    ("Tìm các giao dịch cà phê", "find"),
    ("tìm khoản trà sữa tuần trước", "find"),
    ("Tôi đã mua trà sữa những lần nào?", "find"),
    ("tim giao dich grab", "find"),
    # ngân sách
    ("Ngân sách tháng này còn bao nhiêu?", "budget"),
    ("mình có vượt hạn mức nào không", "budget"),
    ("ngân sách ăn uống thế nào rồi", "budget"),
    # nợ
    ("Ai đang nợ mình?", "debts"),
    ("mình còn nợ ai không", "debts"),
    ("Linh mượn mình bao nhiêu rồi", "debts"),
    ("các khoản cho vay chưa trả", "debts"),
    # bất thường
    ("Có giao dịch nào bất thường không?", "anomaly"),
    ("khoản chi nào lạ trong tháng", "anomaly"),
    ("có gì đột biến trong chi tiêu không", "anomaly"),
    # gợi ý ngân sách
    ("Gợi ý ngân sách cho tháng sau", "recommend"),
    ("nên đặt ngân sách bao nhiêu cho từng mục", "recommend"),
    ("đề xuất ngân sách giúp mình", "recommend"),
    # ghi giao dịch
    ("Ghi giúp ăn bún chả 50k", "record"),
    ("thêm khoản đổ xăng 80k", "record"),
    ("lưu giúp mình tiền điện 450 nghìn", "record"),
    ("nhập lương tháng 15 triệu", "record"),
    # mô phỏng tiết kiệm
    ("Nếu bớt uống trà sữa thì tiết kiệm được bao nhiêu?", "simulate"),
    ("nếu giảm cà phê xuống 10 lần mỗi tháng thì sao", "simulate"),
    ("thử cắt ăn ngoài 20% xem", "simulate"),
    ("mô phỏng tiết kiệm khi bớt grab", "simulate"),
    ("nếu hạn chế mua sắm thì để dành được bao nhiêu", "simulate"),
    # thói quen
    ("Mình hay tiêu tiền vào buổi nào?", "habits"),
    ("thói quen chi tiêu của mình thế nào", "habits"),
    ("cuối tuần mình có tiêu nhiều hơn không", "habits"),
    ("thứ mấy trong tuần mình chi nhiều nhất", "habits"),
    ("mình hay uống cà phê lúc nào", "habits"),
    # lời khuyên
    ("Làm sao để tiết kiệm hơn?", "advice"),
    ("cho mình lời khuyên tiết kiệm", "advice"),
    ("mẹo quản lý chi tiêu", "advice"),
    ("tiết kiệm thế nào bây giờ", "advice"),
    ("mình nên làm gì để bớt tiêu", "advice"),
]
