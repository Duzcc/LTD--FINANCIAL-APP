# Kiến trúc hệ thống

Hệ thống gồm **3 phần độc lập**, mỗi phần là một dự án riêng (phụ thuộc, kiểm thử, Dockerfile, README riêng)
và có thể triển khai trên máy chủ khác nhau.

```mermaid
flowchart LR
  subgraph Client["frontend/ — Flutter"]
    UI[Màn hình theo tính năng] --> FP[FinanceProvider<br/>sổ cái offline-first]
    UI --> AR[AiRepository<br/>server-first, device-fallback]
    AR --> OD[Mô hình trên thiết bị<br/>Naive Bayes, parser, insights]
  end
  subgraph API["backend/ — Node.js + Express"]
    R[REST /api/*] --> S[services: ledger, store, sync]
    R --> AIR[/api/ai/*/] --> SN[aiSnapshot<br/>dựng snapshot, quy đổi tiền tệ]
    SN --> AC[aiServiceClient<br/>X-API-Key, timeout, 503]
  end
  subgraph AIS["ai-service/ — Python FastAPI"]
    E[/v1/*/] --> M1[Categorizer<br/>TF-IDF + LogReg + kNN]
    E --> M2[Intent + NER parser]
    E --> M3[Forecaster<br/>Holt / Holt-Winters]
    E --> M4[Anomaly<br/>MAD + IsolationForest]
    E --> M5[Budget · Receipt · Search]
    E --> LLM[Assistant<br/>tool calling]
  end
  FP -- "JWT, /api/sync/batch" --> R
  AR -- "JWT, /api/ai/*" --> AIR
  AC -- "snapshot JSON" --> E
  S --> DB[(MongoDB)]
  LLM -. tùy chọn .-> CL[Claude API / Ollama]
```

## Nguyên tắc thiết kế

| Nguyên tắc | Hiện thực |
|---|---|
| Tách biệt trách nhiệm | Frontend chỉ hiển thị & lưu cục bộ; backend sở hữu dữ liệu và xác thực; AI service chỉ tính toán |
| AI service không trạng thái | Mọi yêu cầu kèm snapshot dữ liệu → nhân bản ngang dễ dàng, không phải đồng bộ dữ liệu người dùng |
| Phòng thủ nhiều lớp | Người dùng không gọi thẳng AI service; backend xác thực JWT, giới hạn tần suất, gửi khóa dịch vụ |
| Suy giảm mềm (graceful degradation) | AI service sập → backend trả 503 `AI_UNAVAILABLE` / trợ lý luật; app → mô hình trên thiết bị |
| Con người quyết định | LLM chỉ *đề xuất* (`propose_transaction`, `propose_budget`), người dùng bấm xác nhận |
| Quyền riêng tư | Snapshot không chứa email/mật khẩu; có thể chạy LLM cục bộ bằng Ollama |

## Luồng "nhập nhanh"

```mermaid
sequenceDiagram
  participant U as Người dùng
  participant App as Flutter
  participant BE as Backend
  participant AI as AI service
  U->>App: "cho Minh mượn 500k hôm qua"
  App->>App: QuickEntryParser (thiết bị) → hiện ngay
  App->>BE: POST /api/ai/parse (sau 650ms gõ)
  BE->>BE: loadState + buildSnapshot
  BE->>AI: POST /v1/parse (X-API-Key)
  AI-->>BE: kind=lend, amount=500000, newPersonName=Minh, confidence=0.99
  BE-->>App: JSON
  App->>App: dùng kết quả tin cậy hơn
  U->>App: Tiếp tục → xác nhận biểu mẫu → lưu (offline-first, đồng bộ sau)
```

## Cấu trúc thư mục

```
Android-NHOM3/
├── frontend/      Flutter (Android, iOS, Web)        → frontend/README.md
├── backend/       Node.js + Express + MongoDB        → backend/README.md, backend/docs/openapi.yaml
├── ai-service/    Python + FastAPI + scikit-learn    → ai-service/README.md, ai-service/MODEL_CARD.md
├── docs/          Kiến trúc, báo cáo môn học
├── tool/          Kịch bản kiểm tra trên macOS
├── docker-compose.yml · Makefile · .github/workflows/ci.yml
```

## Luồng "quét hóa đơn" (OCR)

```mermaid
flowchart LR
  A[Ảnh hóa đơn] --> B{OCR trên điện thoại<br/>Apple Vision iOS / ML Kit Android}
  B -- có chữ --> C[Dựng dòng theo tọa độ + độ nghiêng]
  C -- đăng nhập --> D[/api/ai/receipts/text → AI service: phân tích + gợi ý danh mục/]
  C -- ngoại tuyến --> E[Bộ phân tích Dart trên thiết bị]
  B -- không đọc được --> F[/api/ai/receipts/scan → Apple Vision macOS / Tesseract + khử nghiêng → mô hình thị giác nếu chưa chắc/]
  D & E & F --> G[Bỏ phiếu tổng tiền: dòng TỔNG · khách đưa − tiền thừa · tổng tiền hàng − giảm giá · tổng dòng hàng]
  G --> H[Người dùng xem độ tin cậy, sửa nếu cần → giao dịch chi kèm ảnh]
```

Đánh giá trên 100 ảnh hóa đơn tổng hợp chưa dùng để chỉnh: tổng tiền đúng 98% (Tesseract), 100% (Apple Vision).
