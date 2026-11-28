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

Tạo `JWT_SECRET` riêng cho production bằng `node -e "console.log(require('node:crypto').randomBytes(32).toString('base64url'))"`. Không dùng khóa mẫu, khóa development hoặc commit `.env`; production từ chối khóa ngắn hơn 32 byte.

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

## Bảo mật tài khoản

- Mật khẩu được băm bằng bcrypt; backend giới hạn đầu vào ở 72 byte UTF-8 để tránh bcrypt bỏ phần đuôi mật khẩu.
- Đăng ký cần xác minh email qua liên kết dùng một lần; liên kết đặt lại mật khẩu cũng được băm, có hạn dùng và chỉ tiêu thụ khi người dùng gửi mật khẩu mới.
- Đăng nhập chỉ cần email đã xác minh và mật khẩu; mỗi tài khoản chỉ có một phiên hoạt động, đăng nhập mới thay thế phiên cũ.
- Access JWT chỉ chấp nhận HS256, mặc định hết hạn sau 15 phút; refresh token xoay vòng và bị thu hồi khi thay thế phiên hoặc đổi mật khẩu.
- App lưu token trong kho bảo mật hệ điều hành, tự chuyển phiên cũ khỏi `SharedPreferences` và từ chối gửi token qua HTTP tới máy chủ từ xa ở bản release.
- Endpoint xác thực trả `Cache-Control: no-store`; Helmet, giới hạn tốc độ, khóa đăng nhập và thu hồi phiên được bật ở backend.
- Production cần `JWT_SECRET` ngẫu nhiên tối thiểu 32 byte, `PUBLIC_URL` HTTPS, SMTP/Brevo và `CORS_ORIGINS` chỉ chứa các domain frontend thực tế. Không dùng `devLink` ngoài development.

## Biến môi trường

| Biến                                                                           | Ý nghĩa                                                                                                                                                                                                              |
| ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PORT`                                                                         | Cổng API (mặc định 3000)                                                                                                                                                                                             |
| `MONGODB_URI`                                                                  | Chuỗi kết nối MongoDB                                                                                                                                                                                                |
| `JWT_SECRET`                                                                   | Khóa ký JWT; production bắt buộc khóa ngẫu nhiên tối thiểu 32 byte                                                                                                                                                  |
| `JWT_EXPIRES_IN`                                                               | Thời hạn access token (mặc định `15m`); refresh token được xoay vòng riêng                                                                                                                                           |
| `REFRESH_TOKEN_DAYS`                                                           | Thời hạn refresh token (mặc định 30 ngày)                                                                                                                                                                            |
| `AI_SERVICE_URL`, `AI_SERVICE_KEY`, `AI_SERVICE_TIMEOUT_MS`                    | Địa chỉ và khóa dùng chung của AI service (`ai-service/`). Để trống = các API AI trả 503, app dùng mô hình trên thiết bị                                                                                             |
| `AI_PROVIDER`, `AI_API_KEY`, `AI_MODEL`, `AI_BASE_URL`, `AI_MAX_TOKENS`        | LLM trực tiếp — chỉ dùng làm dự phòng cho `/api/ai/chat` khi AI service không chạy                                                                                                                                   |
| `CORS_ORIGINS`                                                                 | Danh sách origin của frontend được phép gọi API, phân tách bằng dấu phẩy (`*` = tất cả)                                                                                                                              |
| `MONGODB_URI`, `MONGODB_DB`                                                    | Chuỗi kết nối MongoDB (máy riêng hoặc Atlas `mongodb+srv://…`) và tên db (mặc định `finance_app`). Chuyển dữ liệu từ MongoDB nhúng (`dev:mem`) sang: chạy `npm run dev:mem` ở một terminal, rồi `npm run db:migrate` |
| `SEPAY_API_TOKEN`, `SEPAY_POLL_SECONDS`                                        | API Token SePay: backend tự hỏi `GET my.sepay.vn/userapi/transactions/list` khi có mã QR đang chờ để đối soát, không cần webhook                                                                                     |
| `PUBLIC_URL`                                                                   | URL công khai của backend cho webhook và liên kết xác minh/đặt lại mật khẩu; production phải dùng HTTPS                                                                                                              |
| `MAX_FAILED_LOGINS`, `LOGIN_LOCK_MINUTES`                                      | Số lần sai mật khẩu trước khi khóa (5), thời gian khóa (15 phút; demo 30 giây đặt `LOGIN_LOCK_MINUTES=0.5`)                                                                                                         |
| `RESET_TOKEN_MINUTES`, `EMAIL_VERIFY_MINUTES`                                  | Thời hạn liên kết đặt lại mật khẩu (15 phút) và xác minh email (24 giờ)                                                                                                                                               |
| `SMTP_*`, `MAIL_FROM`, `BREVO_API_KEY`                                         | Gửi liên kết email; khi development không cấu hình mail, liên kết được log và trả qua `devLink`                                                                                                                      |
| `TZ`                                                                           | Múi giờ tổng hợp báo cáo (mặc định `Asia/Ho_Chi_Minh`)                                                                                                                                                               |

## Danh sách API

Đặc tả đầy đủ: [`docs/openapi.yaml`](docs/openapi.yaml) (cũng phục vụ tại `GET /api/openapi.yaml`, mở bằng Swagger Editor/Postman).
Backend dựng _snapshot_ dữ liệu (không có email/mật khẩu, đã quy đổi tiền tệ) rồi gửi sang AI service — xem `src/domain/snapshot.js`, `src/integrations/ai-service.client.js`.

Mọi API, trừ `/api/auth/register|login|verify-email|resend-verification|refresh|forgot-password|reset-password` và `/api/health`, đều cần header `Authorization: Bearer <token>`. Lỗi trả về dạng `{ "error": { "code", "message" } }` với mã HTTP 400, 401, 403, 404, 409, 429, 500 hoặc 503.

| Nhóm      | Phương thức & đường dẫn                                                 | Mô tả                                                                                                                                                                                                                                                                                                        |
| --------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Hệ thống  | `GET /api/health`                                                       | Kiểm tra API và kết nối CSDL                                                                                                                                                                                                                                                                                 |
| Tài khoản | `POST /api/auth/register`                                               | Đăng ký `{name, email, password}` (họ tên 2–50 chữ cái; mật khẩu 8–72 byte UTF-8 gồm chữ và số, không khoảng trắng, khác email); gửi liên kết xác minh, chưa cấp phiên; email chưa xác minh có thể đăng ký lại                                                                                           |
|           | `GET/POST /api/auth/verify-email`                                       | GET mở trang xác minh, không tiêu thụ token; POST `{token}` xác minh email một lần. Sau đó đăng nhập bình thường                                                                                                                                                                                          |
|           | `POST /api/auth/resend-verification`                                    | `{email}`; gửi lại liên kết cho email chưa xác minh                                                                                                                                                                                                                                                        |
|           | `POST /api/auth/login`                                                  | `{email, password}` → `{token, refreshToken, user}`; email phải xác minh; sai 5 lần liên tiếp khóa 15 phút (429 `ACCOUNT_LOCKED`); đăng nhập mới thay thế phiên cũ                                                                                                                                        |
|           | `POST /api/auth/forgot-password`                                        | `{email}`; nếu tài khoản tồn tại, gửi liên kết đặt mật khẩu mới                                                                                                                                                                                                                                            |
|           | `GET/POST /api/auth/reset-password`                                     | GET mở form; POST `{token, newPassword, confirmPassword?}` cập nhật mật khẩu một lần và thu hồi phiên cũ; cần đăng nhập lại                                                                                                                                                                                 |
|           | `PUT /api/auth/change-password`                                         | `{oldPassword, newPassword}`; cần mật khẩu hiện tại, trả token mới và thu hồi phiên cũ                                                                                                                                                                                                                      |
|           | `POST /api/auth/logout`                                                 | Đăng xuất và thu hồi phiên hiện tại                                                                                                                                                                                                                                                                         |
|           | `GET/PUT /api/auth/me`                                                  | Xem hoặc sửa hồ sơ `{name, currency, hideBalance}`                                                                                                                                                                                                                                                           |
|           | `DELETE /api/auth/me`                                                   | Xóa tài khoản và toàn bộ dữ liệu `{password}`                                                                                                                                                                                                                                                                |
| Ví        | `GET/POST /api/wallets`, `GET/PUT/DELETE /api/wallets/:id`              | Thêm/sửa/xóa/xem ví; trường `balance` (SoDuHienTai) được tính từ số dư ban đầu và giao dịch; `DELETE ...?cascade=true` xóa kèm giao dịch và ngân sách                                                                                                                                                        |
| Danh mục  | `/api/categories` (lọc `?income=true\|false`)                           | CRUD; chặn trùng tên và chặn xóa danh mục đang dùng                                                                                                                                                                                                                                                          |
| Đối tượng | `/api/people`                                                           | CRUD; chặn xóa đối tượng đang có giao dịch                                                                                                                                                                                                                                                                   |
| Giao dịch | `/api/transactions`                                                     | CRUD; lọc `q, type (expense\|income\|transfer\|debt\|<kind>), walletId, categoryId, personId, from, to`; sắp xếp `sort=date\|amount&order=asc\|desc`; phân trang `page, limit`                                                                                                                               |
| Ngân sách | `/api/budgets` (lọc `?month=2026-10`)                                   | CRUD; trả `used` (số đã dùng); `categoryId=null` là mục tiêu tổng của tháng                                                                                                                                                                                                                                  |
| Báo cáo   | `GET /api/reports/dashboard?month=&currency=`                           | Số dư, thu/chi tháng này và tháng trước, chi theo danh mục, ngân sách, công nợ, giao dịch gần đây                                                                                                                                                                                                            |
|           | `GET /api/reports/summary?from=&to=&groupBy=day\|month`                 | Chuỗi thu/chi theo thời gian và theo danh mục                                                                                                                                                                                                                                                                |
|           | `GET /api/reports/debts`                                                | Sổ nợ theo đối tượng                                                                                                                                                                                                                                                                                         |
| Định kỳ   | `/api/recurring`                                                        | CRUD giao dịch định kỳ `{kind, amount, walletId, frequency, interval, startDate, endDate, nextDate, active}`                                                                                                                                                                                                 |
| Tài khoản | `POST /api/auth/refresh`                                                | Đổi refresh token lấy cặp token mới (xoay vòng)                                                                                                                                                                                                                                                              |
| Ngân hàng | `GET /api/bank/banks`                                                   | Danh sách ngân hàng hỗ trợ VietQR (mã BIN NAPAS)                                                                                                                                                                                                                                                             |
|           | `POST /api/bank/requests`                                               | Tạo yêu cầu nhận tiền `{walletId, amount?, kind: income\|collect, personId?, note}` → mã đối soát `LTDxxxxxx` đặt trong nội dung chuyển khoản của VietQR. Ví phải liên kết ngân hàng (`bankBin`, `bankAccount`, `bankHolder`)                                                                                |
|           | `GET /api/bank/requests[/:id]`, `DELETE /api/bank/requests/:id`         | Xem trạng thái (`pending`, `paid`, `cancelled`, `expired`) / hủy yêu cầu                                                                                                                                                                                                                                     |
|           | `GET /api/bank/sepay`, `POST/DELETE /api/bank/sepay/key`                | Trạng thái kết nối, tạo/thu hồi API key webhook (chỉ trả khóa một lần, lưu bản băm)                                                                                                                                                                                                                          |
|           | `POST /api/bank/sepay/webhook`                                          | SePay gọi khi có tiền vào (header `Authorization: Apikey <khóa>`). Chống trùng theo `id` của SePay; khớp mã đối soát + số tài khoản → tự ghi giao dịch thu nhập/thu nợ; trả `{success: true}`                                                                                                                |
| AI        | `GET /api/ai/status`                                                    | AI service có sẵn sàng không, danh sách tính năng                                                                                                                                                                                                                                                            |
|           | `POST /api/ai/chat`                                                     | `{messages}` → `{reply, source: ai-service\|llm\|rules, actions}`; LLM gọi công cụ, `actions` là đề xuất cần người dùng xác nhận                                                                                                                                                                             |
|           | `POST /api/ai/categorize`                                               | `{text, income?}` → gợi ý danh mục cá nhân hóa theo lịch sử                                                                                                                                                                                                                                                  |
|           | `POST /api/ai/parse`                                                    | `{text}` → giao dịch có cấu trúc từ câu tự nhiên                                                                                                                                                                                                                                                             |
|           | `GET /api/ai/forecast`, `/anomalies`, `/budgets/recommend`, `/insights` | Dự báo, bất thường, gợi ý ngân sách, tổng hợp cho trang chủ                                                                                                                                                                                                                                                  |
|           | `POST /api/ai/search`                                                   | `{query}` → mã giao dịch theo độ liên quan                                                                                                                                                                                                                                                                   |
|           | `POST /api/ai/receipts/text`, `/receipts/scan`                          | Đọc hóa đơn từ văn bản hoặc ảnh base64                                                                                                                                                                                                                                                                       |
| Đồng bộ   | `GET /api/sync`                                                         | Toàn bộ dữ liệu của người dùng (dùng khi đăng nhập trên thiết bị mới)                                                                                                                                                                                                                                        |
|           | `POST /api/sync/batch`                                                  | Áp dụng lần lượt `{ops:[{entity, action: upsert\|delete, id, data}]}` từ hàng đợi ngoại tuyến của app                                                                                                                                                                                                        |

### Loại giao dịch (`kind`)

`expense` (Chi tiêu), `income` (Thu nhập), `transfer` (Chuyển tiền), `lend` (Cho vay), `collect` (Thu nợ), `interestIncome` (Thu lãi), `borrow` (Đi vay), `repay` (Trả nợ), `interestExpense` (Trả lãi).
Tiền gốc vay/nợ và chuyển ví không tính vào thu chi; thu lãi và trả lãi được tính. Thu nợ hoặc trả nợ không được vượt số còn lại của đối tượng đó.

## Ánh xạ với thiết kế CSDL (mục 2.3 của báo cáo)

| Thực thể  | Collection        | Trường chính                                                                                                                                                                                                                                                  |
| --------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| NguoiDung | `users`           | `name` (HoTen), `email` (Email, unique), `passwordHash` (MatKhau đã băm), hash/thời hạn liên kết xác minh và đặt lại mật khẩu, `emailVerified`, `failedLogins`/`lockUntil`, `sepayKeyHash` (khóa webhook SePay đã băm)                                  |
| Vi        | `wallets`         | `name` (TenVi), `savings` (LoaiVi CoBan/TietKiem), `currency` (DonViTien), `opening`, `target` (SoTienMucTieu), `startDate` (NgayBatDau), `deadline` (NgayKetThuc), `bankBin`/`bankAccount`/`bankHolder` (tài khoản ngân hàng liên kết), `user` (MaNguoiDung) |
| DanhMuc   | `categories`      | `name` (TenDanhMuc), `income`, `isDefault` (LoaiDanhMuc MacDinh/KhongMacDinh), `symbol`                                                                                                                                                                       |
| DoiTuong  | `people`          | `name` (TenDoiTuong), `group`                                                                                                                                                                                                                                 |
| GiaoDich  | `transactions`    | `kind` (LoaiGiaoDich), `amount` (SoTien), `date` (NgayGiaoDich), `dueDate` (NgayDenHan), `note` (GhiChu), `walletId` (MaVi), `categoryId` (MaDanhMuc), `personId` (MaDoiTuong), `destinationId`                                                               |
| NganSach  | `budgets`         | `amount` (SoTien), `startDate`/`endDate` (NgayBatDau/NgayKetThuc), `walletId` (MaVi), `categoryId` (MaDanhMuc)                                                                                                                                                |
| —         | `refreshtokens`   | Một refresh token hash cho mỗi người dùng; chỉ mục unique đảm bảo một phiên hoạt động                                                                                                                                                                                                                       |
| —         | `paymentrequests` | Yêu cầu nhận tiền VietQR: `code` (mã đối soát, unique), `walletId`, `kind`, `amount`, `personId`, `status`, `entryId`                                                                                                                                         |
| —         | `bankevents`      | Biến động số dư từ SePay: `providerId` (duy nhất theo người dùng → chống trùng), `amount`, `content`, `result`                                                                                                                                                |

Mỗi bản ghi có `_id` kiểu ObjectId làm khóa chính và `clientId` (mã do app tạo, duy nhất theo từng người dùng) để app có thể tạo dữ liệu khi ngoại tuyến rồi đồng bộ sau. API trả `clientId` dưới tên `id`. Mọi truy vấn đều lọc theo `user` nên người dùng chỉ thấy dữ liệu của mình.

## Cấu trúc thư mục

```
src/
  app.js, server.js, dev-memory.js
  config/         biến môi trường
  routes/         khai báo đường dẫn + middleware, gọi controller
  controllers/    đọc request, trả response (không chứa nghiệp vụ)
  services/       nghiệp vụ: auth, session (JWT + refresh token), ledger (CRUD sổ cái), report, sync,
                  ai, bank, sepay (đối soát webhook + User API), mail
  repositories/   truy cập MongoDB qua Mongoose: user, session, ledger, payment-request, bank-event
  domain/         quy tắc thuần: ledger (số dư, nợ, ràng buộc), snapshot gửi AI, financial-context, banks, constants
  validators/     kiểm tra đầu vào: auth, bank, ai
  integrations/   ai-service.client, llm.client (Anthropic/OpenAI), sepay.client
  middleware/     auth (JWT), error, rate-limit, async-handler
  models/         User, Wallet, Category, Person, Transaction, Budget, Recurring, RefreshToken,
                  PaymentRequest, BankEvent
  utils/          errors (ApiError), crypto, time
docs/openapi.yaml  Đặc tả OpenAPI 3
scripts/migrate-db.js  Chuyển dữ liệu từ MongoDB nhúng sang MongoDB thật (npm run db:migrate)
test/            Kiểm thử tích hợp (node:test + supertest, cần Node 22): api, extra, bank, ai (AI service giả lập + E2E)
```
