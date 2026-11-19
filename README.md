# Wisely – Quản lý chi tiêu cá nhân

Đồ án học phần Lập trình di động (261IS26A01), Nhóm 03, GVHD ThS. Nguyễn Hoàng Anh.

Ứng dụng giúp ghi chép thu chi hằng ngày, quản lý ví, vay nợ, ngân sách và xem thống kê. Dữ liệu lưu trên điện
thoại nên không có mạng vẫn dùng được; khi đăng nhập thì dữ liệu được sao lưu lên tài khoản và dùng được trên
nhiều máy. Ngoài ra có trợ lý AI để nhập giao dịch bằng câu tiếng Việt, đọc hóa đơn, dự báo chi tiêu cuối tháng.

## Chức năng

- Tài khoản: đăng ký, đăng nhập có mã OTP gửi qua email, quên và đổi mật khẩu, đăng xuất khỏi mọi thiết bị.
- Ví: ví thường và ví tiết kiệm có mục tiêu, biểu tượng, thông báo; liên kết tài khoản ngân hàng để nhận tiền bằng VietQR.
- Giao dịch: chi, thu, chuyển ví, cho vay, đi vay, thu nợ, trả nợ, tiền lãi; giao dịch định kỳ; đính kèm ảnh hóa đơn.
- Danh mục và đối tượng (người cho vay, cửa hàng…).
- Ngân sách tháng tổng và theo danh mục, cảnh báo khi sắp vượt.
- Tổng quan, sổ nợ, thống kê theo tháng/năm/khoảng ngày, tìm kiếm và lọc.
- Trợ lý AI: nhập nhanh "ăn phở 45k sáng nay", quét hóa đơn, gợi ý danh mục, dự báo cuối tháng, phát hiện khoản chi bất thường.
- Khác: khóa bằng mã PIN, nhắc ghi chép, tỷ giá, xuất Excel/CSV.

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `frontend/` | App Flutter (Android, iOS). Mỗi tính năng một thư mục trong `lib/features/` gồm `domain`, `data`, `presentation`; trạng thái quản lý bằng Provider |
| `backend/` | REST API Node.js + Express + MongoDB: tài khoản, dữ liệu, sao lưu, kết nối SePay |
| `ai-service/` | Python + FastAPI + scikit-learn: phân loại danh mục, phân tích câu, dự báo, đọc hóa đơn |
| `docs/` | Báo cáo môn học, sơ đồ kiến trúc |

App chỉ gọi backend; backend mới gọi sang ai-service. Khi không có mạng hoặc chưa đăng nhập, app dùng phần phân tích
đơn giản chạy ngay trên điện thoại. Sơ đồ chi tiết ở [`docs/architecture.md`](docs/architecture.md).

## Yêu cầu

Flutter 3, Node.js 22, Python 3.11 trở lên, MongoDB (Atlas hoặc cài trên máy). Không có MongoDB thì dùng
`npm run dev:mem` để chạy với MongoDB nhúng.

## Chạy dự án

AI service (cổng 8000):

```bash
cd ai-service
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m ml.train
cp .env.example .env
.venv/bin/python -m uvicorn app.main:app --port 8000
```

Backend (cổng 3000):

```bash
cd backend
npm install
cp .env.example .env      # điền JWT_SECRET, MONGODB_URI, AI_SERVICE_KEY trùng SERVICE_API_KEY bên ai-service
npm run dev               # hoặc npm run dev:mem nếu chưa có MongoDB
```

App:

```bash
cd frontend
flutter pub get
flutter run
```

Mặc định app gọi `http://10.0.2.2:3000` trên máy ảo Android và `http://localhost:3000` trên iOS Simulator.
Chạy trên điện thoại thật thì truyền IP máy tính khi build:
`flutter run --dart-define=API_URL=http://192.168.1.10:3000/api`.

Không chạy backend vẫn dùng được app: ở màn đăng nhập nhập tên rồi chọn **Bắt đầu sử dụng**.

Chạy toàn bộ phía máy chủ bằng Docker: `cp .env.example .env && docker compose up -d --build`.

### Gửi OTP qua Gmail

Tạo mật khẩu ứng dụng tại myaccount.google.com/apppasswords rồi điền vào `backend/.env`:

```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=<gmail>
SMTP_PASS=<mật khẩu ứng dụng>
```

Khi để trống SMTP, mã OTP được in ra log backend.

### Nhận tiền qua SePay

Đặt `SEPAY_API_TOKEN` (tạo ở my.sepay.vn, mục API Access) trong `backend/.env`. Backend sẽ kiểm tra tiền về khi có mã
VietQR đang chờ và tự ghi giao dịch. Nếu muốn dùng webhook thì vào app: Tài khoản → Kết nối ngân hàng → Tạo khóa
webhook, rồi dán URL và khóa vào phần Webhooks trên SePay.

Các biến môi trường khác có giải thích trong `backend/.env.example` và `ai-service/.env.example`.

## Build

```bash
cd frontend
flutter build apk --release --dart-define=API_URL=https://<tên miền>/api
flutter build ios --release --dart-define=API_URL=https://<tên miền>/api
```

## Kiểm thử

```bash
cd ai-service && .venv/bin/python -m pytest
cd backend && npm test
cd frontend && flutter analyze && flutter test
```

Kiểm thử trên máy ảo (cần backend đang chạy):

```bash
cd frontend
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/report_flows_test.dart -d <thiết bị>
```

`report_flows_test` đi lại các luồng trong báo cáo bằng thao tác chạm và nhập; `full_features_test` mở lần lượt mọi
màn hình; `demo_test` chạy từ đăng ký tới quét hóa đơn.

## API

Đặc tả OpenAPI ở [`backend/docs/openapi.yaml`](backend/docs/openapi.yaml), bộ Postman ở
[`backend/postman_collection.json`](backend/postman_collection.json). Lỗi trả về dạng
`{ "error": { "code": "...", "message": "..." } }`.

## Tài liệu

- Báo cáo: [`docs/Bao_cao_LTDD_Nhom03.docx`](docs/Bao_cao_LTDD_Nhom03.docx)
- Mô hình AI: [`ai-service/MODEL_CARD.md`](ai-service/MODEL_CARD.md)
