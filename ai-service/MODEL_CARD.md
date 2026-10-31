# Model card — Finance AI Service

## 1. Phân loại danh mục (`categorizer`)

- **Nhiệm vụ**: ghi chú giao dịch tiếng Việt → 1 trong 11 danh mục chuẩn (8 chi, 3 thu: food, life, house, self,
  transport, health, child · salary, bonus, business, other_income).
- **Kiến trúc**: `FeatureUnion(TF-IDF từ 1–2 gram, TF-IDF ký tự 2–5 gram "char_wb")` → `LogisticRegression(class_weight="balanced")`.
  Đầu vào được chuẩn hóa thành "câu gốc viết thường | câu bỏ dấu", số → `0`, mở rộng viết tắt (cf, ck, đt, hp…).
  n-gram ký tự giúp chịu được lỗi gõ, không dấu, viết tắt.
- **Cá nhân hóa**: P = (1−w)·P_toàn_cục + w·P_kNN, kNN cosine trên tối đa 2.000 ghi chú gần nhất người dùng đã gán;
  w = min(0,9, sim_max^1,5). Hỗ trợ cả danh mục **tự tạo** (không có trong mô hình toàn cục).
- **Dữ liệu**: tự xây dựng — 7.700 câu sinh từ từ vựng (động từ, mặt hàng, địa điểm, thương hiệu VN) với tăng cường
  (bỏ dấu 30%, viết tắt, hoa/thường, đảo ký tự).
- **Chọn siêu tham số**: GridSearchCV 3-fold, C ∈ {2, 8, 32} → C = 32.
- **Quy trình đánh giá trung thực**: ba tập viết tay độc lập với dữ liệu sinh.
  v1 (118 câu) và v2 (62 câu) đã được dùng để phát hiện lỗ hổng từ vựng (đồ nội thất, sửa chữa, phí đường, chăm sóc
  cá nhân) nên coi là tập *phát triển*; **v3 (48 câu) được viết trước khi huấn luyện lại và chưa từng dùng để điều chỉnh**.

| Tập | Trước khi mở rộng từ vựng | Sau khi mở rộng |
|---|---|---|
| Tổng hợp (20% giữ lại) | acc 0,983 | acc 0,989 |
| v1 viết tay (dev, 118) | acc 0,941 · F1 0,951 | acc 0,983 · F1 0,985 |
| v2 viết tay (dev, 62) | acc 0,903 · F1 0,923 | acc 1,000 |
| **v3 viết tay (kiểm tra, 48)** | — | **acc 0,979 · F1 0,975** |

Lỗi duy nhất ở v3 là câu thu nhập "tiền thuê nhà khách trả" bị đoán thành chi "Nhà cửa"; trong ứng dụng, loại
giao dịch (thu/chi) được xác định trước nên bộ phân loại chỉ chọn trong danh mục thu → không gặp lỗi này.

## 2. Ý định giao dịch (`intent`)

- 9 lớp: expense, income, transfer, lend, collect, interestIncome, borrow, repay, interestExpense.
- Cùng kiến trúc; 4.500 câu tổng hợp. Luật ưu tiên xử lý các mẫu chắc chắn và phân biệt có dấu
  ("trả lãi" ≠ "trả lại", "cho Minh mượn" ≠ "Linh cho mình mượn").
- Tổng hợp: accuracy 0,978 · viết tay (44 câu): 1,000.

## 3. Dự báo chi tiêu (`forecaster`)

- Chi tiêu thường xuyên: hồ sơ thứ-trong-tuần (trimmed mean 56 ngày) × hệ số mức tháng hiện tại (co về 1 đầu tháng),
  kết hợp 60/40 với Holt trên tổng tuần. Khoản lớn (> 4× trung vị): khoản định kỳ hằng tháng cộng nếu chưa tới ngày,
  khoản bất chợt cộng theo tần suất 90 ngày. Tháng sau: Holt-Winters (≥ 24 tháng) / Holt (≥ 4 tháng).
- **Kiểm định lùi** 40 người dùng mô phỏng × 6 tháng, MAPE (%) tổng chi cả tháng:

| Ngày dự báo | 5 | 10 | 15 | 20 | 25 | Chung |
|---|---|---|---|---|---|---|
| Chia đều (run-rate) | 125,1 | 54,3 | 30,0 | 19,0 | 10,0 | 47,7 |
| **Forecaster** | **30,0** | **23,0** | **19,3** | **14,9** | **8,7** | **19,2** |

## 4. Phát hiện bất thường (`anomaly`)

Robust z-score trên log(số tiền) theo danh mục (z ≥ 3,5 và ≥ 2,5× trung vị), Isolation Forest (≥ 40 khoản chi,
contamination 3%), nhập trùng (cùng số tiền ≤ 10 phút), danh mục tăng > 1,5× trung bình 3 tháng.

## 5. Đọc hóa đơn (OCR + phân tích)

**Luồng xử lý**
1. *Trên điện thoại* (mặc định, không gửi ảnh đi): Apple Vision (iOS 17+, có tiếng Việt) hoặc Google ML Kit
   (Android) trả về các khối chữ kèm tọa độ và góc nghiêng.
2. *Trên máy chủ* (khi điện thoại không đọc được): Apple Vision (macOS) hoặc Tesseract 5 `vie+eng` (Linux/Docker),
   có tiền xử lý: phóng to ≥ 1400px, tăng tương phản, **khử nghiêng** bằng phân tích hình chiếu (±6°, bước 0,25°),
   nhị phân hóa Otsu (Tesseract). Mô hình thị giác (Claude/Llava) chỉ được hỏi khi OCR có độ tin cậy < 0,8.
3. **Dựng lại dòng**: xoay tâm các khối theo độ nghiêng (trung vị góc của các dòng dài), gom khối cùng hàng —
   nhãn "Tổng thanh toán:" và số "154.000" thường là hai khối riêng.
4. **Phân tích**: sửa lỗi OCR trong số (O→0, l→1, "46. 000"), từ khóa bỏ dấu chịu lỗi chính tả
   ("Tien thira", "T0NG C0NG"), rồi **bỏ phiếu** tổng tiền giữa các nguồn độc lập: dòng TỔNG, tiền khách đưa − tiền thừa,
   tổng tiền hàng − giảm giá, tổng các dòng hàng; mỗi số kèm biến thể sửa lỗi phần nghìn ("454.999" → "454.000").
   Kết quả có độ tin cậy và danh sách bằng chứng khớp. Cùng thuật toán được viết cho cả Python và Dart (ngoại tuyến).

**Đánh giá** (`python -m ml.evaluate_receipts`): ảnh hóa đơn tổng hợp (7 kiểu cửa hàng, máy in nhiệt 80mm, xoay ±2,5°,
mờ, nhiễu, nén JPEG). Bộ dev (seed 2026) dùng để chỉnh thuật toán; **bộ kiểm tra 100 ảnh (seed 777) chưa từng dùng
để chỉnh**:

| Engine | Tổng tiền đúng | Ngày đúng | Cửa hàng đúng | Thời gian/ảnh |
|---|---|---|---|---|
| Tesseract 5 (vie+eng), trước khi có bỏ phiếu & khử nghiêng | 65% (20 ảnh dev) | — | — | — |
| Tesseract 5 (vie+eng) | **98%** | 94% | 96% | 1,2 s |
| Apple Vision (macOS 14) | **100%** | 100% | 97% | 0,8 s |

Giới hạn: ảnh tổng hợp sạch hơn ảnh chụp thật (nhàu, bóng, cong giấy, hóa đơn viết tay). Ứng dụng luôn cho người dùng
sửa tổng tiền trước khi lưu và hiển thị mức tin cậy.

## Giới hạn & đạo đức

- Dữ liệu huấn luyện là dữ liệu tổng hợp; tập viết tay nhỏ — số liệu có sai số. Cá nhân hóa giảm sai lệch theo thời gian.
- Không đưa lời khuyên đầu tư; trợ lý chỉ đề xuất, người dùng luôn xác nhận trước khi ghi dữ liệu.
- Dịch vụ không lưu dữ liệu; khi bật LLM bên ngoài (Claude), các con số tổng hợp từ công cụ được gửi tới nhà cung cấp —
  dùng Ollama nếu cần giữ dữ liệu hoàn toàn trên máy.

Tái lập: `make data && make train && make eval && python -m ml.evaluate_receipts --n 100 --seed 777`.
