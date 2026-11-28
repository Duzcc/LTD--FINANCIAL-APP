# Phân công công việc – Nhóm 03

Mỗi người phụ trách trọn một module: màn hình, trạng thái, API, bảng dữ liệu, kiểm thử, mục báo cáo và slide của module đó.
Danh sách tệp, thư mục cụ thể của từng người nằm trong [`.github/CODEOWNERS`](../.github/CODEOWNERS).

| Thành viên | Module | Thang điểm |
|---|---|---|
| Đinh Tuấn Dũng (trưởng nhóm) | Xác thực, phiên, bảo mật, đồng bộ | 3.1.1, 3.2.2 |
| Đỗ Minh Hiếu | Module 1 – Danh mục, đối tượng, cấu hình | 3.1.2 |
| Hoàng Anh Đức | Module 2 – Giao dịch, sổ giao dịch, định kỳ | 3.1.3 |
| Hoàng Đức Nhiệm | Module 3 – Ngân sách, sổ nợ, tính toán | 3.1.4 |
| Trần Mạnh Hải | Module 4, 5 – Báo cáo, cảnh báo; chủ trì kiểm thử | 3.1.5, 3.1.6, 3.3 |
| Trần Văn Đức | Ví, ngân hàng, trợ lý AI, tích hợp, triển khai | 3.1.3, 4.1.2 |

Cách làm việc: mỗi người tạo nhánh `feature/<tên>`, commit bằng tài khoản GitHub của mình, mở pull request vào `main`. Trước khi mở PR chạy `flutter analyze` và `flutter test` (frontend) hoặc `npm test` (backend).

---

## 1. Đinh Tuấn Dũng – Xác thực, phiên, bảo mật, đồng bộ

**Thư mục chính:** `frontend/lib/features/auth/`, `features/security/`, `core/network/`, `core/validation/`, `features/finance/data/`; backend `auth.*`, `session.service.js`, `mail.service.js`, `sync.*`, `middleware/`.

**Chức năng phụ trách**
- Đăng ký xác minh qua liên kết email; đăng nhập bằng mật khẩu đã xác minh; khôi phục mật khẩu qua email link và đổi mật khẩu bằng mật khẩu hiện tại.
- Mỗi tài khoản chỉ có một phiên; đăng nhập mới thay thế phiên cũ, đăng xuất chỉ thu hồi phiên hiện tại.
- Duy trì phiên trong kho bảo mật hệ điều hành và tự làm mới token khi gặp 401.
- Khóa ứng dụng bằng PIN.
- Sao lưu dữ liệu lên máy chủ (hàng chờ thay đổi, `/sync/batch`, `/sync`).

**API:** `/auth/register`, `/auth/login`, `GET|POST /auth/verify-email`, `/auth/resend-verification`, `/auth/refresh`, `/auth/logout`, `/auth/forgot-password`, `GET|POST /auth/reset-password`; `GET|PUT|DELETE /auth/me`; `PUT /auth/change-password`; `GET /sync`, `POST /sync/batch`.

**Bảng dữ liệu:** `users`, `refreshtokens` (unique theo user).

**Luồng demo:** Đăng ký → xác minh bằng liên kết trong email → đăng nhập → phiên đăng nhập mới thay thế phiên trước → nhập sai mật khẩu 5 lần thì bị khóa 15 phút → đăng xuất.

**Phải giải thích được:** JWT (sub, v, sid) và refresh token dùng một lần; `SessionClient` tự làm mới phiên; `requireAuth` ở backend; vì sao gọi id của người khác trả 404; validator mật khẩu và email.

**Việc cần làm và commit**
1. Cấu hình SMTP/Brevo và `PUBLIC_URL` HTTPS trước khi chạy luồng email trên production.
2. Giữ test xác minh/reset token dùng một lần và đăng nhập một phiên cho mỗi tài khoản.

**Báo cáo:** 2.3, 3.3, 3.5; ca ngoại lệ NE-01 đến NE-05. **Slide:** 1–6 (giới thiệu, kiến trúc, xác thực).

---

## 2. Đỗ Minh Hiếu – Module 1: Danh mục, đối tượng, cấu hình

**Thư mục chính:** `frontend/lib/features/categories/`, `settings/.../rates_screen.dart`, `wallets/.../currency_selection_screen.dart`; backend `models/Category.js`, `Person.js`, `plugin.js`, `domain/defaults.js`.

**Chức năng phụ trách**
- Thêm, sửa, xóa, chọn danh mục thu/chi và đối tượng (người cho vay, đi vay).
- Danh mục mặc định khi tạo tài khoản; tiền tệ và bảng tỷ giá quy đổi.
- Ràng buộc: không xóa danh mục đang được dùng, không xóa đối tượng đang có giao dịch, không đổi loại thu/chi của danh mục đã dùng.

**API:** `GET|POST /categories`, `GET|PUT|DELETE /categories/:id`; tương tự `/people`.

**Bảng dữ liệu:** `categories`, `people`; trường `user`, `clientId` dùng chung cho mọi bảng.

**Luồng demo:** Thêm danh mục "Thưởng dự án" → dùng cho một khoản thu → thử xóa thì báo "Danh mục đang được sử dụng" → thêm đối tượng "Minh".

**Phải giải thích được:** ERD, từ điển dữ liệu, `ownedPlugin` và chỉ mục duy nhất `(user, clientId)`, quy tắc BR10–BR13.

**Việc cần làm và commit**
1. Thêm test backend: xóa đối tượng đang có giao dịch trả 409.
2. Bổ sung phần `/categories`, `/people` trong `openapi.yaml`.

**Báo cáo:** 2.2 (CSDL), bảng quy tắc nghiệp vụ mục c; NE-06. **Slide:** 7–9.

---

## 3. Hoàng Anh Đức – Module 2: Giao dịch, sổ giao dịch, định kỳ

**Thư mục chính:** `frontend/lib/features/transactions/`, `ledger/`, `recurring/`; backend `models/Transaction.js`, `Recurring.js`, `resource.routes.js`, `resource.controller.js`, `ledger.service.js`, `ledger.repository.js`.

**Chức năng phụ trách**
- Thêm, sửa, xóa giao dịch thu, chi, chuyển tiền, vay/nợ; nút cộng nhanh số tiền.
- Sổ giao dịch: tìm theo ghi chú, lọc theo loại, ví, danh mục, kỳ; sắp xếp.
- Giao dịch định kỳ.

**API:** bộ CRUD dùng chung cho 6 tài nguyên; `GET /transactions?from&to&type&walletId&categoryId&personId&q&sort&order&page&limit`.

**Bảng dữ liệu:** `transactions`, `recurrings`.

**Luồng demo:** Thêm chi 70.000 (Cà phê) → sửa thành 90.000 → tìm "cà phê" → lọc Chi tiêu → chuyển tiền giữa hai ví → xóa giao dịch.

**Phải giải thích được:** biểu mẫu và validator; luồng lưu máy → hàng chờ → `/sync/batch` → kiểm tra lại ở `ledger.service`; `ListView.builder`; vì sao 6 tài nguyên dùng chung một router.

**Việc cần làm và commit**
1. Thêm test Flutter cho tìm kiếm và lọc ở Sổ giao dịch.
2. Ghi đủ tham số lọc của `GET /transactions` vào `openapi.yaml`.

**Báo cáo:** 2.4 (đặc tả API), test flow 3; NE-08, NE-09. **Slide:** 10–12.

---

## 4. Hoàng Đức Nhiệm – Module 3: Ngân sách, sổ nợ, tính toán

**Thư mục chính:** `frontend/lib/features/budgets/`, `finance/domain/ledger_queries.dart`, `ledger_rules.dart`, `money_budget.dart`; backend `models/Budget.js`, `domain/ledger.js`, `domain/constants.js`.

**Chức năng phụ trách**
- Mục tiêu chi tiêu theo tháng, theo danh mục, theo ví; trạng thái còn lại và vượt kế hoạch.
- Sổ nợ: dư nợ theo từng người, chặn thu/trả vượt dư nợ, "Đã tất toán".
- Công thức số dư ví dùng chung cho toàn ứng dụng.

**API:** `GET|POST /budgets`, `GET|PUT|DELETE /budgets/:id` (danh sách trả kèm số đã dùng).

**Bảng dữ liệu:** `budgets` (đọc thêm `transactions` để tính).

**Luồng demo:** Đặt mục tiêu Cà phê 100.000 → chi 120.000 → hiện "Vượt 20.000 đ". Cho Minh vay 500.000 → thu 700.000 bị từ chối → thu 500.000 → "Đã tất toán".

**Phải giải thích được:** BR05 (số dư = số dư đầu + Σ số tiền × dấu + tiền chuyển đến), BR06 (số đã dùng), BR07 (dư nợ); hàm `walletEffect`, `balance`, `used`; bảng đối chiếu số liệu 4.1.12.

**Việc cần làm và commit**
1. Thêm test cho ngân sách theo ví và theo tiền tệ.
2. Thêm test backend cho `outstanding` khi thu nợ vượt dư nợ.

**Báo cáo:** 1.3.5 phần a, b; 4.1.12; NE-10, NE-12. **Slide:** 13–15.

---

## 5. Trần Mạnh Hải – Module 4, 5: Báo cáo, cảnh báo, kiểm thử

**Thư mục chính:** `frontend/lib/features/home/`, `statistics/`, `core/widgets/charts.dart`, `core/services/`, `settings/.../reminders_screen.dart`, `excel_export.dart`, `integration_test/`; backend `report.*`, `test/`.

**Chức năng phụ trách**
- Tổng quan, báo cáo thu chi theo tuần/tháng/năm, biểu đồ chi theo danh mục, sổ nợ tổng hợp.
- Nhắc ghi chép, nhắc khoản đến hạn, cảnh báo vượt ngân sách (thông báo cục bộ).
- Xuất Excel/CSV.
- Chủ trì kiểm thử: chạy bộ test tự động, cập nhật bảng kết quả, chụp ảnh minh chứng.

**API:** `GET /reports/dashboard`, `/reports/summary`, `/reports/debts`.

**Luồng demo:** Tổng quan → Báo cáo thu chi tháng → biểu đồ chi theo danh mục → bật nhắc ghi chép → xuất Excel.

**Phải giải thích được:** số trên biểu đồ khớp tổng giao dịch; thông báo cục bộ; cách chạy `flutter test`, `npm test`, integration test trên máy ảo và đọc kết quả.

**Việc cần làm và commit**
1. Chạy lại toàn bộ test trên Android và iOS, cập nhật bảng kết quả kiểm thử.
2. Thêm test: báo cáo tháng bằng tổng các giao dịch trong tháng.

**Báo cáo:** 4.1, 4.2, 4.3. **Slide:** 16–17.

---

## 6. Trần Văn Đức – Ví, ngân hàng, trợ lý AI, tích hợp, triển khai

**Thư mục chính:** `frontend/lib/app/`, `features/wallets/`, `banking/`, `ai/`, `finance_provider.dart`; backend `bank.*`, `sepay.service.js`, `ai.*`, `integrations/`; `ai-service/`, `render.yaml`, `docker-compose.yml`.

**Chức năng phụ trách:** ví cơ bản và ví tiết kiệm, điều chỉnh số dư, nạp/rút, biểu đồ số dư; VietQR, SePay; trợ lý AI, quét hóa đơn; khung ứng dụng, duyệt PR, triển khai Docker lên Render, đóng gói APK.

**Báo cáo:** 3.2, 3.4, 4.4, phụ lục. **Slide:** 18.

---

## Lịch

| Ngày | Việc |
|---|---|
| 27/11 | Nhận phân công, clone repo, đọc thư mục của mình |
| 28–29/11 | Làm việc ở mục "Việc cần làm và commit", viết 3 slide, chạy thử luồng demo |
| 30/11 | Ghép slide, tập vấn đáp chéo |
| 01/12 | Nộp báo cáo, slide, video |
