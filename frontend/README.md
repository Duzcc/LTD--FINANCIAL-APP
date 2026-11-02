# Frontend — Flutter

Ứng dụng di động Quản lý chi tiêu (Android, iOS, Web). Offline-first: dữ liệu ghi ngay vào thiết bị, đồng bộ lên
backend khi đăng nhập.

```sh
flutter pub get
flutter run --dart-define=API_URL=http://<máy chủ backend>:3000   # mặc định: localhost / 10.0.2.2 (Android emulator)
flutter analyze && flutter test
open -a Simulator && flutter devices                # flutter run chỉ thấy máy ảo đang chạy
flutter build web --release --no-web-resources-cdn   # bản Web không phụ thuộc CDN
```

## Cấu trúc (feature-first)

```
lib/
├── main.dart                     khởi động: bộ nhớ, thông báo, định kỳ, đồng bộ
├── app/                          FinanceApp (Provider, theme, khóa), MainScreen, thanh điều hướng
├── core/                         dùng chung, không phụ thuộc tính năng
│   ├── network/api_client.dart   gọi REST, chuẩn hóa lỗi
│   ├── banking/vietqr.dart       danh sách ngân hàng (mã BIN), tạo chuỗi VietQR chuẩn EMVCo + CRC
│   ├── validation/validators.dart ràng buộc họ tên, email, mật khẩu, OTP, tài khoản ngân hàng (khớp backend)
│   ├── ocr/                      nhận dạng chữ trên thiết bị (kênh native: Apple Vision / ML Kit), dựng dòng
│   ├── security/                 khóa PIN
│   ├── notifications/            nhắc nhở
│   ├── theme/                    màu, theme
│   └── widgets/                  thành phần giao diện, biểu đồ
├── data/
│   ├── models/finance_models.dart
│   └── finance_provider.dart     sổ cái, quy tắc nghiệp vụ, lưu trữ, đăng nhập & đồng bộ
└── features/
    ├── ai/
    │   ├── data/                 AiRepository (máy chủ trước, thiết bị dự phòng), mô hình dữ liệu AI
    │   ├── on_device/            Naive Bayes danh mục, parser câu tự nhiên, insights, trợ lý cục bộ
    │   └── presentation/         Nhập nhanh (gõ/nói), Phân tích, Trợ lý (xác nhận hành động), Quét hóa đơn, Tìm kiếm AI
    ├── auth/                     đăng nhập/đăng ký → màn hình OTP, quên/đổi mật khẩu
    ├── banking/                  nhận tiền & đòi nợ bằng VietQR, kết nối SePay (BankRepository)
    ├── home/  ledger/  transactions/  wallets/  goals/  statistics/
    ├── recurring/  security/  settings/
```

Quy ước: mọi import dùng `package:finance_app/...` (lint `always_use_package_imports`).

## Kiểm thử

| Tệp | Nội dung |
|---|---|
| `test/finance_provider_test.dart` | quy tắc sổ cái, số dư, ngân sách, vay/nợ |
| `test/sync_test.dart` | đăng nhập hai bước (mật khẩu + OTP), đồng bộ hàng đợi, refresh token (backend giả lập) |
| `test/validators_test.dart` | ràng buộc họ tên, email, mật khẩu, OTP |
| `test/auth_otp_test.dart` | giao diện đăng ký báo lỗi từng ô; đăng nhập phải nhập OTP mới vào app |
| `test/vietqr_test.dart` | cấu trúc VietQR (EMVCo/NAPAS), CRC-16, nội dung chuyển khoản, liên kết ngân hàng của ví |
| `test/receive_qr_test.dart` | màn hình nhận tiền: tạo QR ngoại tuyến, chặn thu nợ vượt số còn lại, tự cập nhật khi tiền về |
| `test/ai_repository_test.dart` | AI máy chủ ↔ dự phòng trên thiết bị, hành động trợ lý, phân tích, hóa đơn |
| `test/receipt_parser_test.dart` | đọc hóa đơn: sửa lỗi OCR, bỏ phiếu tổng tiền, dựng dòng ảnh nghiêng |
| `test/features_test.dart` | mô hình trên thiết bị, định kỳ, khóa, xuất Excel |
| `test/widget_test.dart`, `phone_preview_test.dart` | giao diện nhiều cỡ màn hình |
| `integration_test/demo_test.dart` | kịch bản demo 16 bước trên máy ảo (iOS + Android), OCR thật |
| `integration_test/full_features_test.dart` | đủ 9 nhóm chức năng với backend thật, đồng bộ hai thiết bị, mở mọi màn hình |
