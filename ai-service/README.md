# Finance AI Service

Dịch vụ AI/ML **độc lập** (Python · FastAPI · scikit-learn) của ứng dụng Quản lý chi tiêu cá nhân.
Ứng dụng di động **không gọi trực tiếp** dịch vụ này: mọi yêu cầu đi qua backend (xác thực người dùng, lấy dữ liệu),
backend gửi kèm *snapshot* dữ liệu cần thiết. Dịch vụ **không lưu dữ liệu người dùng** (stateless) nên có thể nhân bản tự do.

```
Flutter app ──HTTPS/JWT──▶ Backend (Node/Express, MongoDB) ──X-API-Key──▶ AI service (FastAPI)
                                                                            ├─ mô hình scikit-learn (artifacts/)
                                                                            └─ LLM tùy chọn: Claude / Ollama (Qwen, Llama)
```

## Tính năng

| Endpoint | Chức năng | Kỹ thuật |
|---|---|---|
| `POST /v1/categorize` | Gợi ý danh mục từ ghi chú | TF-IDF (từ + ký tự) + Logistic Regression, cá nhân hóa bằng kNN trên lịch sử người dùng |
| `POST /v1/parse` | Nhập nhanh: "cho Minh mượn 500k hôm qua" → giao dịch | Mô hình ý định + luật ưu tiên + trích xuất số tiền/ngày/người/ví |
| `POST /v1/forecast` | Dự báo chi cuối tháng (khoảng 80%) và tháng sau | Hồ sơ thứ-trong-tuần, Holt, Holt-Winters, tách khoản định kỳ |
| `POST /v1/anomalies` | Giao dịch bất thường, nhập trùng, danh mục tăng đột biến | Robust z-score (MAD) + Isolation Forest |
| `POST /v1/budgets/recommend` | Gợi ý ngân sách theo danh mục | Trung vị/phân vị 6 tháng + khung 50/30/20 |
| `POST /v1/receipts/parse-text` · `/scan`, `GET /v1/receipts/engines` | Đọc hóa đơn | OCR Apple Vision (macOS) / Tesseract `vie` có khử nghiêng → dựng dòng → bỏ phiếu tổng tiền; mô hình thị giác khi OCR không chắc |
| `POST /v1/search` | "cafe tháng trước trên 50k" | Hiểu bộ lọc thời gian/số tiền + xếp hạng cosine TF-IDF + đồng nghĩa |
| `POST /v1/chat` | Trợ lý hội thoại | LLM gọi công cụ (function calling) trên dữ liệu thật; tự lùi về trợ lý luật |
| `GET /health`, `GET /v1/models` | Trạng thái, chỉ số mô hình | |

Tài liệu tương tác (OpenAPI): `http://localhost:8000/docs`.

## Chạy nhanh

```bash
make setup          # tạo .venv và cài thư viện (Python ≥ 3.11)
make train          # sinh dữ liệu + huấn luyện + đánh giá -> artifacts/ (≈ 1 phút)
cp .env.example .env
make dev            # http://localhost:8000
make test           # 64 bài kiểm thử
python -m ml.evaluate_receipts --n 100   # đánh giá đọc hóa đơn (cần Tesseract hoặc macOS)
```

Khi khởi động, nếu thiếu mô hình hoặc mô hình được huấn luyện bằng phiên bản thư viện khác, dịch vụ **tự huấn luyện lại**.

### Bật trợ lý LLM (tùy chọn)

- **Claude**: `LLM_PROVIDER=anthropic`, `LLM_API_KEY`, `LLM_MODEL`.
- **Mô hình mở chạy cục bộ (miễn phí, riêng tư)**: cài [Ollama](https://ollama.com), `ollama pull qwen2.5:7b`, rồi
  `LLM_PROVIDER=openai`, `LLM_BASE_URL=http://localhost:11434/v1`, `LLM_MODEL=qwen2.5:7b`.

LLM **không thấy toàn bộ dữ liệu**: nó gọi 10 công cụ (`get_overview`, `forecast_month`, `get_budget_status`, `get_debts`,
`get_anomalies`, `recommend_budgets`, `propose_transaction`, `propose_budget`…) để lấy đúng con số cần thiết.
Các công cụ `propose_*` chỉ tạo **đề xuất** — người dùng phải bấm *Xác nhận* trên ứng dụng (human-in-the-loop).

## Cấu trúc

```
ai-service/
├── app/
│   ├── main.py                 # app factory, middleware (request-id, timing), xử lý lỗi
│   ├── core/                   # cấu hình (pydantic-settings), bảo mật X-API-Key
│   ├── api/v1/endpoints/       # nlp, analytics, receipts, assistant, system
│   ├── schemas/                # hợp đồng dữ liệu (pydantic, camelCase)
│   ├── nlp/                    # chuẩn hóa tiếng Việt, trích xuất thực thể
│   └── services/               # categorizer, parser, forecaster, anomaly, budget, receipt, search
│       └── llm/                # providers (Anthropic, OpenAI-compatible), tools, rules, assistant
├── ml/
│   ├── data/                   # từ vựng, bộ sinh dữ liệu, tập đánh giá viết tay
│   ├── pipelines.py · train.py # huấn luyện + GridSearch + báo cáo
│   └── evaluate_forecaster.py  # kiểm định lùi bộ dự báo
├── artifacts/                  # mô hình đã huấn luyện + metrics.json + forecast_backtest.json
├── tests/                      # pytest: đơn vị + API + vòng lặp gọi công cụ với LLM giả lập
└── MODEL_CARD.md               # mô tả, số liệu đánh giá, giới hạn của mô hình
```
