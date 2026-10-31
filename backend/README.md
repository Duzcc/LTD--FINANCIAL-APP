# Backend – Ứng dụng quản lý chi tiêu cá nhân

RESTful API viết bằng **Node.js + Express.js + MongoDB (Mongoose)**, xác thực bằng **JWT**, mật khẩu băm bằng **bcrypt**.
Backend là một dự án độc lập, chạy trên máy chủ riêng, tách khỏi ứng dụng Flutter (frontend). Hai phía chỉ trao đổi qua HTTP/HTTPS, nên có thể triển khai ở hai máy chủ hoặc hai tên miền khác nhau.

```
Flutter App (máy chủ/thiết bị A) ──HTTPS + JWT──▶ API Node.js (máy chủ B) ──▶ MongoDB
```

## Chạy trên máy phát triển

Yêu cầu: Node.js 18 trở lên, MongoDB 6 trở lên. MongoDB có thể chạy trên máy (`brew install mongodb-community`), trong Docker hoặc dùng MongoDB Atlas.

```sh
cd backend
cp .env.example .env      # sửa JWT_SECRET, MONGODB_URI...
npm install
npm run dev               # http://localhost:3000/api/health
```

Kiểm thử tích hợp (cần MongoDB đang chạy, dùng CSDL `finance_app_test` và xóa nó sau khi chạy):

```sh
npm test
```

## Triển khai lên máy chủ riêng

Cách 1, dùng Docker Compose ở **thư mục gốc** dự án (chạy MongoDB + backend + AI service):

```sh
cd .. && cp .env.example .env && docker compose up -d --build
```

Cách 2, chạy trên VPS hoặc dịch vụ Node (Render, Railway…): đặt biến môi trường như trong `.env.example` với `NODE_ENV=production`, rồi chạy `npm ci --omit=dev && npm start`. Nên đặt máy chủ sau HTTPS (Nginx, Caddy hoặc HTTPS sẵn có của dịch vụ).

Ở phía ứng dụng, trỏ tới backend bằng một trong hai cách:

- lúc build: `flutter run --dart-define=API_URL=https://api.ten-mien.vn`
- trong ứng dụng: màn Đăng nhập → mục **Máy chủ** → nhập địa chỉ → **Kiểm tra** → **Lưu**

Mặc định: máy ảo Android dùng `http://10.0.2.2:3000`; iOS Simulator, macOS và web dùng `http://localhost:3000`. Điện thoại thật cần dùng IP LAN của máy chạy backend, ví dụ `http://192.168.1.10:3000`.

## Biến môi trường

| Biến | Ý nghĩa |
|---|---|
| `PORT` | Cổng API (mặc định 3000) |
| `MONGODB_URI` | Chuỗi kết nối MongoDB |
| `JWT_SECRET` | Khóa ký JWT, **bắt buộc** khi `NODE_ENV=production` |
| `JWT_EXPIRES_IN` | Thời hạn access token (mặc định `1h`) |
| `REFRESH_TOKEN_DAYS` | Thời hạn refresh token (mặc định 30 ngày) |
| `AI_SERVICE_URL`, `AI_SERVICE_KEY`, `AI_SERVICE_TIMEOUT_MS` | Địa chỉ và khóa dùng chung của AI service (`ai-service/`). Để trống = các API AI trả 503, app dùng mô hình trên thiết bị |
| `AI_PROVIDER`, `AI_API_KEY`, `AI_MODEL`, `AI_BASE_URL`, `AI_MAX_TOKENS` | LLM trực tiếp — chỉ dùng làm dự phòng cho `/api/ai/chat` khi AI service không chạy |
| `CORS_ORIGINS` | Danh sách origin của frontend được phép gọi API, phân tách bằng dấu phẩy (`*` = tất cả) |
| `SMTP_*`, `MAIL_FROM` | Gửi email mã quên mật khẩu. Nếu bỏ trống ở chế độ dev, API trả mã trong trường `devCode` để demo |
| `TZ` | Múi giờ tổng hợp báo cáo (mặc định `Asia/Ho_Chi_Minh`) |

## Danh sách API

Đặc tả đầy đủ: [`docs/openapi.yaml`](docs/openapi.yaml) (cũng phục vụ tại `GET /api/openapi.yaml`, mở bằng Swagger Editor/Postman).
Backend dựng *snapshot* dữ liệu (không có email/mật khẩu, đã quy đổi tiền tệ) rồi gửi sang AI service — xem `src/services/aiSnapshot.js`, `src/clients/aiServiceClient.js`.


Mọi API, trừ nhóm `/api/auth/register|login|forgot-password|reset-password` và `/api/health`, đều cần header `Authorization: Bearer <token>`. Lỗi trả về dạng `{ "error": { "code", "message" } }` với mã HTTP 400, 401, 404, 409 hoặc 500.

| Nhóm | Phương thức & đường dẫn | Mô tả |
|---|---|---|
| Hệ thống | `GET /api/health` | Kiểm tra API và kết nối CSDL |
| Tài khoản | `POST /api/auth/register` | Đăng ký `{name, email, password}`; tạo sẵn ví Tiền mặt, danh mục mặc định, đối tượng “Bản thân” |
| | `POST /api/auth/login` | Đăng nhập `{email, password}` → `{token, user}` |
| | `POST /api/auth/forgot-password` | Gửi mã khôi phục 6 số (hiệu lực 15 phút) qua email |
| | `POST /api/auth/reset-password` | `{email, code, newPassword}`; sai quá 5 lần phải yêu cầu mã mới |
| | `PUT /api/auth/change-password` | `{oldPassword, newPassword}`; trả token mới và thu hồi token cũ |
| | `POST /api/auth/logout` | Đăng xuất, thu hồi mọi token đã cấp |
| | `GET/PUT /api/auth/me` | Xem hoặc sửa hồ sơ `{name, currency, hideBalance}` |
| | `DELETE /api/auth/me` | Xóa tài khoản và toàn bộ dữ liệu `{password}` |
| Ví | `GET/POST /api/wallets`, `GET/PUT/DELETE /api/wallets/:id` | Thêm/sửa/xóa/xem ví; trường `balance` (SoDuHienTai) được tính từ số dư ban đầu và giao dịch; `DELETE ...?cascade=true` xóa kèm giao dịch và ngân sách |
| Danh mục | `/api/categories` (lọc `?income=true\|false`) | CRUD; chặn trùng tên và chặn xóa danh mục đang dùng |
| Đối tượng | `/api/people` | CRUD; chặn xóa đối tượng đang có giao dịch |
| Giao dịch | `/api/transactions` | CRUD; lọc `q, type (expense\|income\|transfer\|debt\|<kind>), walletId, categoryId, personId, from, to`; sắp xếp `sort=date\|amount&order=asc\|desc`; phân trang `page, limit` |
| Ngân sách | `/api/budgets` (lọc `?month=2026-10`) | CRUD; trả `used` (số đã dùng); `categoryId=null` là mục tiêu tổng của tháng |
| Báo cáo | `GET /api/reports/dashboard?month=&currency=` | Số dư, thu/chi tháng này và tháng trước, chi theo danh mục, ngân sách, công nợ, giao dịch gần đây |
| | `GET /api/reports/summary?from=&to=&groupBy=day\|month` | Chuỗi thu/chi theo thời gian và theo danh mục |
| | `GET /api/reports/debts` | Sổ nợ theo đối tượng |
| Định kỳ | `/api/recurring` | CRUD giao dịch định kỳ `{kind, amount, walletId, frequency, interval, startDate, endDate, nextDate, active}` |
| Tài khoản | `POST /api/auth/refresh` | Đổi refresh token lấy cặp token mới (xoay vòng) |
| | `POST /api/auth/verify-email`, `POST /api/auth/resend-verification` | Xác thực email bằng mã 6 số |
| AI | `GET /api/ai/status` | AI service có sẵn sàng không, danh sách tính năng |
| | `POST /api/ai/chat` | `{messages}` → `{reply, source: ai-service\|llm\|rules, actions}`; LLM gọi công cụ, `actions` là đề xuất cần người dùng xác nhận |
| | `POST /api/ai/categorize` | `{text, income?}` → gợi ý danh mục cá nhân hóa theo lịch sử |
| | `POST /api/ai/parse` | `{text}` → giao dịch có cấu trúc từ câu tự nhiên |
| | `GET /api/ai/forecast`, `/anomalies`, `/budgets/recommend`, `/insights` | Dự báo, bất thường, gợi ý ngân sách, tổng hợp cho trang chủ |
| | `POST /api/ai/search` | `{query}` → mã giao dịch theo độ liên quan |
| | `POST /api/ai/receipts/text`, `/receipts/scan` | Đọc hóa đơn từ văn bản hoặc ảnh base64 |
| Đồng bộ | `GET /api/sync` | Toàn bộ dữ liệu của người dùng (dùng khi đăng nhập trên thiết bị mới) |
| | `POST /api/sync/batch` | Áp dụng lần lượt `{ops:[{entity, action: upsert\|delete, id, data}]}` từ hàng đợi ngoại tuyến của app |

### Loại giao dịch (`kind`)

`expense` (Chi tiêu), `income` (Thu nhập), `transfer` (Chuyển tiền), `lend` (Cho vay), `collect` (Thu nợ), `interestIncome` (Thu lãi), `borrow` (Đi vay), `repay` (Trả nợ), `interestExpense` (Trả lãi).
Tiền gốc vay/nợ và chuyển ví không tính vào thu chi; thu lãi và trả lãi được tính. Thu nợ hoặc trả nợ không được vượt số còn lại của đối tượng đó.

## Ánh xạ với thiết kế CSDL (mục 2.3 của báo cáo)

| Thực thể | Collection | Trường chính |
|---|---|---|
| NguoiDung | `users` | `name` (HoTen), `email` (Email, unique), `passwordHash` (MatKhau đã băm) |
| Vi | `wallets` | `name` (TenVi), `savings` (LoaiVi CoBan/TietKiem), `currency` (DonViTien), `opening`, `target` (SoTienMucTieu), `startDate` (NgayBatDau), `deadline` (NgayKetThuc), `user` (MaNguoiDung) |
| DanhMuc | `categories` | `name` (TenDanhMuc), `income`, `isDefault` (LoaiDanhMuc MacDinh/KhongMacDinh), `symbol` |
| DoiTuong | `people` | `name` (TenDoiTuong), `group` |
| GiaoDich | `transactions` | `kind` (LoaiGiaoDich), `amount` (SoTien), `date` (NgayGiaoDich), `dueDate` (NgayDenHan), `note` (GhiChu), `walletId` (MaVi), `categoryId` (MaDanhMuc), `personId` (MaDoiTuong), `destinationId` |
| NganSach | `budgets` | `amount` (SoTien), `startDate`/`endDate` (NgayBatDau/NgayKetThuc), `walletId` (MaVi), `categoryId` (MaDanhMuc) |

Mỗi bản ghi có `_id` kiểu ObjectId làm khóa chính và `clientId` (mã do app tạo, duy nhất theo từng người dùng) để app có thể tạo dữ liệu khi ngoại tuyến rồi đồng bộ sau. API trả `clientId` dưới tên `id`. Mọi truy vấn đều lọc theo `user` nên người dùng chỉ thấy dữ liệu của mình.

## Cấu trúc thư mục

```
src/
  app.js, server.js, config.js
  models/        User, Wallet, Category, Person, Transaction, Budget, Recurring, RefreshToken
  middleware/    auth (JWT), error, async
  routes/        auth, resources (CRUD chung), reports, sync, ai (cổng tới AI service)
  services/      ledger (nghiệp vụ & ràng buộc), store, mailer, aiSnapshot, ai (LLM dự phòng), defaults, constants
  clients/       aiServiceClient (gọi AI service: khóa dịch vụ, timeout, chuẩn hóa lỗi 503)
docs/openapi.yaml  Đặc tả OpenAPI 3
test/            Kiểm thử tích hợp (node:test + supertest): api, extra, ai (AI service giả lập + E2E)
```
