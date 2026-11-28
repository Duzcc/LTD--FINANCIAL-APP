# Frontend — Flutter

Ứng dụng di động Quản lý chi tiêu (Android, iOS, Web). Offline-first: dữ liệu ghi ngay vào thiết bị, đồng bộ lên
backend khi đăng nhập.
Access token và refresh token được lưu trong kho bảo mật của hệ điều hành; phiên cũ trong `SharedPreferences` được chuyển
sang kho này khi nâng cấp.

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
├── main.dart                     khởi động: bộ nhớ, thông báo ví, đồng bộ
├── app/                          FinanceApp, route, Splash, MainScreen, Drawer, thanh điều hướng
├── core/                         dùng chung, không phụ thuộc tính năng
│   ├── network/api_client.dart   gọi REST, chuẩn hóa lỗi (ApiException)
│   ├── services/                 thông báo cục bộ (NotificationService)
│   ├── validation/validators.dart ràng buộc họ tên, email, mật khẩu, tài khoản ngân hàng (khớp backend)
│   ├── utils/                    ngày, đọc/ghi trường JSON
│   ├── theme/                    màu, theme
│   └── widgets/                  thành phần giao diện, biểu đồ
└── features/<tính năng>/
    ├── domain/                   Dart thuần: entities, quy tắc nghiệp vụ, interface
    ├── data/                     datasources (REST, SharedPreferences, kênh native), models, repositories
    └── presentation/
        ├── screens/              mỗi màn hình một tệp
        ├── widgets/              widget dùng lại trong tính năng
        └── providers/            ChangeNotifier (Provider)
```

| Tính năng | domain | data | presentation |
|---|---|---|---|
| `finance` | entities (ví, giao dịch, danh mục, đối tượng, ngân sách; dữ liệu định kỳ cũ được giữ tương thích), `LedgerQueries` (số dư, nợ, tổng thu chi), `LedgerRules` (ràng buộc), `FinanceStore` (interface cho tầng dưới) | `FinanceLocalDataSource`, `SyncRemoteDataSource`, `ChangeTracker` (hàng đợi đồng bộ), `AccountSnapshot` | `FinanceProvider`, icon của entity |
| `auth` | `AccountSession` | `SessionClient` (tự làm mới token, một lần cho các yêu cầu song song), `AuthRemoteDataSource` | đăng nhập/đăng ký xác minh bằng email link, quên mật khẩu |
| `ai` | entities AI, dịch vụ trên thiết bị (Naive Bayes danh mục, parser câu tự nhiên, insights, trợ lý cục bộ, đọc hóa đơn) | `AiRepository` (máy chủ trước, thiết bị dự phòng), `TextRecognizer` (Apple Vision / ML Kit) | nhập nhanh, phân tích, trợ lý, quét hóa đơn, tìm kiếm |
| `banking` | dữ liệu/kết nối cũ được giữ tương thích | `BankRepository` | không còn màn hình kết nối trong ứng dụng |
| `settings` | | | hồ sơ và thao tác tài khoản |
| `home`, `ledger`, `transactions`, `wallets`, `goals` | dùng domain của `finance` | | màn hình, widget |

Quy tắc phụ thuộc: `presentation → data → domain`; `domain` không import Flutter hay tầng trên, `core` không import `features`.
Mọi import dùng `package:finance_app/...` (lint `always_use_package_imports`).

## Kiểm thử

| Tệp | Nội dung |
|---|---|
| `test/finance_provider_test.dart` | quy tắc sổ cái, số dư, ngân sách, vay/nợ |
| `test/sync_test.dart` | đăng nhập, đồng bộ hàng đợi, refresh token (backend giả lập) |
| `test/validators_test.dart` | ràng buộc họ tên, email, mật khẩu |
| `test/auth_email_link_test.dart` | giao diện đăng ký yêu cầu xác minh email; đăng nhập bằng mật khẩu |
| `test/vietqr_test.dart` | cấu trúc VietQR (EMVCo/NAPAS), CRC-16, nội dung chuyển khoản, liên kết ngân hàng của ví |
| `test/receive_qr_test.dart` | màn hình nhận tiền: tạo QR ngoại tuyến, chặn thu nợ vượt số còn lại, tự cập nhật khi tiền về |
| `test/ai_repository_test.dart` | AI phía máy chủ ↔ dự phòng trên thiết bị, hành động trợ lý, phân tích, hóa đơn |
| `test/receipt_parser_test.dart` | đọc hóa đơn: sửa lỗi OCR, bỏ phiếu tổng tiền, dựng dòng ảnh nghiêng |
| `test/features_test.dart` | mô hình trên thiết bị, parser và phân tích |
| `test/widget_test.dart`, `phone_preview_test.dart` | giao diện nhiều cỡ màn hình |
| `integration_test/demo_test.dart` | kịch bản demo 16 bước trên máy ảo (iOS + Android), OCR thật |
| `integration_test/full_features_test.dart` | kiểm tra các chức năng hiện có với backend thật và phiên đăng nhập |
| `integration_test/report_flows_test.dart` | luồng ví, danh mục, giao dịch, ngân sách và đồng bộ |
