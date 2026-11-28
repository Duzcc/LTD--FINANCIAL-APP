# Luồng tài khoản và bảo mật

Tài liệu này mô tả hành vi được triển khai trong frontend Flutter và backend Node.js hiện tại. Các con số ghi là mặc định trong mã; biến môi trường có thể thay đổi một số giá trị khi chạy. Đây là mô tả implementation, không thay thế cấu hình bảo mật production.

## Tóm tắt nhanh

- Đăng ký tạo tài khoản **chưa xác minh email**; người dùng phải xác minh rồi mới đăng nhập.
- Email xác minh và email đặt lại mật khẩu chứa token ngẫu nhiên; backend chỉ lưu SHA-256 của token. Token xác minh chỉ dùng thành công một lần; token đặt lại bị tiêu thụ khi đổi mật khẩu thành công.
- Mật khẩu được hash bằng `bcryptjs` với cost `10`; backend không lưu mật khẩu rõ.
- API đăng nhập bằng access JWT HS256 và refresh token ngẫu nhiên. Mặc định access token hết hạn sau `15m`, refresh token sau `30` ngày.
- Mỗi tài khoản chỉ có **một phiên refresh đang hoạt động**. Đăng nhập mới thay thế phiên trước.
- Các API dữ liệu yêu cầu `Authorization: Bearer <JWT>`; hệ thống hiện không có role như `admin/user` trong JWT.
- Các endpoint auth có giới hạn tổng mặc định `50 yêu cầu / 15 phút / IP`; riêng đăng nhập sai `5` lần sẽ khóa tài khoản `15` phút.
- Access token và refresh token trên ứng dụng được lưu trong `FlutterSecureStorage`, không lưu mật khẩu.

## 1. Quy tắc kiểm tra dữ liệu

### Email

Khi tạo tài khoản, frontend và backend trim khoảng trắng, chuyển email thành chữ thường và dùng kiểm tra nghiêm ngặt:

- Tối đa `254` ký tự; phần trước `@` tối đa `64` ký tự.
- Dạng tổng quát: `local-part@domain.tld`.
- Phần local chấp nhận chữ thường ASCII, số và `. _ % + -`.
- Domain gồm các nhãn chữ thường ASCII, số hoặc `-`; phần cuối có ít nhất 2 chữ cái.
- Không chấp nhận `..`, bắt đầu bằng dấu chấm, hoặc `.@`.
- Ví dụ hợp lệ theo bộ kiểm tra: `an.nguyen+app@example.com`.

Khi đăng nhập, quên mật khẩu hoặc gửi lại xác minh, backend dùng kiểm tra tương thích rộng hơn: email không rỗng, dài tối đa `254` và có `@`. Frontend hiện vẫn dùng kiểm tra nghiêm ngặt khi nhập. Vì vậy dữ liệu cũ có thể được server chấp nhận dù không qua quy tắc tạo mới ở giao diện.

Đây là kiểm tra định dạng, không phải xác minh rằng hộp thư/domain thực sự tồn tại. Việc sở hữu địa chỉ được xác nhận bằng liên kết email.

### Họ tên

- Trim và gộp nhiều khoảng trắng liên tiếp.
- Từ `2` đến `50` ký tự.
- Bắt đầu bằng chữ Unicode; cho phép chữ, dấu cách, dấu chấm, dấu nháy đơn và gạch nối; không nhận số.

### Mật khẩu mới

Áp dụng khi đăng ký, đặt lại mật khẩu và đổi mật khẩu:

- Ít nhất `8` ký tự.
- Không quá `72` byte UTF-8 (giới hạn tương thích bcrypt).
- Phải có ít nhất một chữ Unicode và một chữ số.
- Không được chứa khoảng trắng.
- Không được trùng email (không phân biệt hoa/thường).

Đăng nhập chỉ yêu cầu mật khẩu không rỗng; mật khẩu cũ không bị kiểm tra lại theo quy tắc mật khẩu mới. Backend từ chối mật khẩu đăng nhập dài hơn 72 byte bằng lỗi thông tin đăng nhập chung.

## 2. Đăng ký và xác minh email

1. Người dùng chọn **Đăng ký**, nhập họ tên, email, mật khẩu và xác nhận mật khẩu.
2. Ứng dụng kiểm tra từng ô khi nhập và kiểm tra toàn form khi bấm nút.
3. Frontend chuẩn hóa tên/email rồi gửi `POST /api/auth/register`.
4. Backend kiểm tra dữ liệu, chuẩn hóa email và kiểm tra tài khoản:
   - Email đã xác minh: trả `409 EMAIL_EXISTS`.
   - Email đã có nhưng chưa xác minh: cập nhật họ tên/mật khẩu mới và tạo liên kết xác minh mới; liên kết cũ không còn dùng được.
   - Email mới: tạo user, hash mật khẩu và khởi tạo dữ liệu mặc định (ví dụ ví, danh mục, đối tượng).
5. Backend tạo token xác minh ngẫu nhiên 32 byte, lưu SHA-256 cùng thời hạn và gửi email.
6. Đăng ký **không tự đăng nhập**. Ứng dụng hiện màn hình chờ xác minh; sau xác minh người dùng quay lại đăng nhập.

Thời hạn xác minh mặc định là `1440` phút (`24` giờ), cấu hình bằng `EMAIL_VERIFY_MINUTES`.

### Liên kết xác minh có dùng một lần không?

Có, đối với thao tác xác minh thực sự:

- Mở trang `GET /api/auth/verify-email?token=...` chỉ hiển thị trang xác nhận; GET này không tiêu thụ token.
- Ứng dụng gửi token bằng `POST /api/auth/verify-email` khi xử lý liên kết deep link. Trang trình duyệt cũng gửi POST khi bấm xác nhận.
- Backend chỉ cập nhật user chưa xác minh, token còn hạn và hash khớp; đồng thời xóa hash/thời hạn khỏi user. POST dùng lại token sẽ bị từ chối.
- Nếu bấm **Gửi lại liên kết xác minh**, token mới thay thế token cũ.

Đăng nhập bằng mật khẩu đúng nhưng email chưa xác minh bị từ chối với `403 EMAIL_NOT_VERIFIED`.

### Gửi email

- Có thể cấu hình SMTP (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `MAIL_FROM`) hoặc Brevo (`BREVO_API_KEY`).
- Development không cấu hình mail: backend in liên kết kiểm tra ra log và có thể trả `devLink` cho ứng dụng.
- Production yêu cầu mail đã cấu hình và `PUBLIC_URL` bắt đầu bằng `https://`; thiếu cấu hình thì thao tác dừng bằng lỗi `503`.
- Gửi lại xác minh cho email không tồn tại/đã xác minh trả thông báo chung. Riêng người dùng chưa xác minh mới được cấp token mới.

## 3. Đăng nhập và phiên làm việc

1. Frontend gửi email và mật khẩu đến `POST /api/auth/login`.
2. Backend chuẩn hóa/kiểm tra email, kiểm tra trạng thái khóa và so sánh mật khẩu với bcrypt hash.
3. Sai email hoặc mật khẩu trả cùng thông báo `401` (“Email hoặc mật khẩu không đúng”) để không phân biệt hai trường hợp.
4. Đúng thông tin nhưng email chưa xác minh trả `403`.
5. Nếu đăng nhập thành công, backend phát access JWT và refresh token; ứng dụng lưu chúng trong kho bảo mật của hệ điều hành.
6. Ứng dụng tải snapshot dữ liệu tài khoản:
   - Tài khoản chưa có dữ liệu: dữ liệu cục bộ được tải lên.
   - Có dữ liệu cả trên máy và server: ứng dụng cho chọn dùng dữ liệu tài khoản hoặc gộp dữ liệu máy lên tài khoản.

### Access token và refresh token

**Access JWT**

- Ký bằng HS256; payload gồm `sub` (user ID), `v` (tokenVersion) và `sid` (session ID), cộng `iat`/`exp` do thư viện JWT tạo.
- Mặc định hết hạn sau `15` phút (`JWT_EXPIRES_IN`).
- JWT được ký, **không được mã hóa**; payload có thể đọc được, vì vậy không nhét mật khẩu hay dữ liệu bí mật vào claims.
- Backend chỉ chấp nhận HS256. JWT sai chữ ký, sai thuật toán, hết hạn hoặc phiên đã bị thu hồi trả `401`.

**Refresh token**

- Sinh từ 48 byte ngẫu nhiên, mã hóa Base64URL.
- Backend chỉ lưu SHA-256 của refresh token, không lưu token thô.
- Mặc định hết hạn sau `30` ngày (`REFRESH_TOKEN_DAYS`).
- Khi refresh, token cũ được thay nguyên tử bằng token mới. Gửi cùng token cũ đồng thời nhiều lần thì chỉ một yêu cầu có thể thành công.

Khi API trả `401`, `SessionClient` dùng refresh token để xin phiên mới; các yêu cầu đồng thời dùng chung một lần refresh rồi gửi lại yêu cầu ban đầu.

### Một phiên trên mỗi tài khoản

Collection refresh token có unique index theo user. Vì vậy đăng nhập ở thiết bị mới thay thế refresh session trước; access JWT của phiên cũ cũng không còn được chấp nhận vì backend kiểm tra `sid` còn tồn tại trong database. Đây là hành vi **một thiết bị/phiên hoạt động tại một thời điểm**, không phải danh sách nhiều thiết bị.

## 4. Quên và đặt lại mật khẩu

1. Người dùng mở **Quên mật khẩu?**, nhập email và gửi `POST /api/auth/forgot-password`.
2. Backend phân biệt các kết quả:
   - Email chưa đăng ký: trả thông báo “Email này chưa được đăng ký”.
   - Có tài khoản nhưng chưa xác minh: yêu cầu xác minh email trước.
   - Có tài khoản đã xác minh: tạo reset token và gửi email.
3. Reset token là 32 byte ngẫu nhiên; database lưu SHA-256, mặc định có hạn `15` phút (`RESET_TOKEN_MINUTES`).
4. Ứng dụng kiểm tra token qua `POST /api/auth/reset-password/validate`; việc kiểm tra này không tiêu thụ token.
5. Người dùng nhập mật khẩu mới và xác nhận; ứng dụng gửi `POST /api/auth/reset-password`.
6. Backend kiểm tra lại token/hạn dùng và mật khẩu. Khi cập nhật thành công, backend xóa reset token, cập nhật bcrypt hash, reset bộ đếm đăng nhập sai và thu hồi mọi refresh session.
7. `tokenVersion` được tăng để vô hiệu hóa access JWT cũ. Người dùng cần đăng nhập lại.

Reset token chỉ được tiêu thụ khi đổi mật khẩu thành công. Cập nhật có điều kiện trên token/hash/hạn dùng nên hai yêu cầu reset đồng thời không thể cùng thắng. Yêu cầu reset mới thay token cũ.

**Lưu ý riêng tư:** phản hồi quên mật khẩu hiện nói rõ email chưa đăng ký hay chưa xác minh. Điều này tiện cho người dùng sửa email nhưng cũng cho phép suy đoán email nào có tài khoản.

## 5. Đổi mật khẩu khi đang đăng nhập

- Màn hình yêu cầu mật khẩu hiện tại, mật khẩu mới và xác nhận mật khẩu mới.
- Ứng dụng gửi `PUT /api/auth/change-password` với access JWT; API nhận mật khẩu cũ và mật khẩu mới. So khớp xác nhận được thực hiện ở giao diện.
- Backend xác thực mật khẩu cũ bằng bcrypt, kiểm tra quy tắc mật khẩu mới và từ chối mật khẩu mới giống mật khẩu hiện tại.
- Thành công: lưu bcrypt hash mới, tăng `tokenVersion`, xóa refresh session cũ rồi phát một session mới cho thiết bị đang thực hiện đổi mật khẩu. Các token cũ bị thu hồi.

## 6. Đăng xuất

1. Giao diện cảnh báo dữ liệu cục bộ sẽ bị xóa; nếu còn thay đổi chưa đồng bộ thì thử đồng bộ trước và cảnh báo phần chưa đồng bộ có thể mất.
2. Khi xác nhận, ứng dụng gọi `POST /api/auth/logout` với Bearer JWT (kèm refresh token để tương thích phiên cũ).
3. Backend xóa refresh session của `sid` hiện tại. Vì mỗi request xác thực kiểm tra session còn sống, access JWT của session đó cũng bị từ chối.
4. Ứng dụng xóa session trong secure storage, reset dữ liệu trong bộ nhớ và xóa dữ liệu local; sau đó về màn đăng nhập.

Ứng dụng vẫn dọn session/dữ liệu local nếu request logout gặp lỗi mạng. Khi đó server có thể chưa nhận lệnh thu hồi; token phía server còn hiệu lực đến khi hết hạn hoặc bị thay thế. Vì vậy thu hồi server-side cần kết nối được backend.

## 7. Xóa tài khoản

- Trong **Tài khoản → Bảo mật → Xóa tài khoản**, giao diện yêu cầu nhập lại mật khẩu rồi xác nhận thao tác nguy hiểm.
- Frontend gửi `DELETE /api/auth/me` với Bearer JWT và mật khẩu.
- Backend xác minh mật khẩu hiện tại, sau đó xóa user cùng dữ liệu sở hữu: ví, danh mục, đối tượng, giao dịch, ngân sách, giao dịch định kỳ, refresh token, yêu cầu thanh toán và sự kiện ngân hàng.
- Thành công: ứng dụng xóa session và dữ liệu local như khi đăng xuất rồi quay về màn đăng nhập.

Đây là xóa vĩnh viễn, không có bước khôi phục trong luồng này. Backend hiện xóa các collection song song, không nằm trong một transaction MongoDB; nếu database gặp lỗi giữa chừng có thể cần kiểm tra trạng thái các collection đã xóa.

## 8. Xác thực, phân quyền và dữ liệu trả về

### Bearer authentication

Các API riêng tư yêu cầu header:

```http
Authorization: Bearer <access-token>
```

`requireAuth` xác minh chữ ký/HS256, tải user theo `sub`, so sánh `tokenVersion` và kiểm tra `sid` còn trong refresh-session database. Middleware gắn `req.user` và `req.sessionId`; thiếu hoặc không hợp lệ trả `401`.

### Có role `admin/user` không?

Hiện **không thấy role-based authorization** trong luồng tài khoản: User schema không có trường role và JWT không có claim role. JWT chứng minh user/session đã đăng nhập; phân quyền dữ liệu dựa trên user hiện tại và các route được bảo vệ bằng `requireAuth`. Kiểm thử backend cũng xác nhận dữ liệu người dùng này không đọc được bằng tài khoản khác.

### Thông tin user trả về

`User.toJSON()` chỉ xuất `id`, `name`, `email`, `currency`, `hideBalance`, trạng thái xác minh và rates. `passwordHash`, token reset/xác minh, bộ đếm đăng nhập sai và thông tin khóa không được xuất trong user JSON.

## 9. Giới hạn tần suất và khóa đăng nhập

Hai lớp đang hoạt động:

| Cơ chế | Mặc định | Tác động |
|---|---:|---|
| `authLimiter` | 50 request / 15 phút / IP | Trả `429 TOO_MANY_REQUESTS`; áp dụng cho đăng ký, đăng nhập, refresh, quên/đặt lại mật khẩu, POST xác minh/gửi lại xác minh và đổi mật khẩu. |
| Khóa theo tài khoản | 5 lần đăng nhập sai, khóa 15 phút | Chỉ tăng bộ đếm khi email có user và mật khẩu sai; trả `429 ACCOUNT_LOCKED`. Đăng nhập thành công reset bộ đếm/khóa. |

`AUTH_RATE_LIMIT`, `MAX_FAILED_LOGINS` và `LOGIN_LOCK_MINUTES` có thể cấu hình. `authLimiter` dùng IP theo cấu hình Express (`trust proxy` hiện đặt một proxy hop).
`LOGIN_LOCK_MINUTES` tính theo phút và nhận số thập phân; để demo khóa 30 giây, đặt `LOGIN_LOCK_MINUTES=0.5` trong `backend/.env`, sau đó khởi động lại backend. Mặc định vẫn là 15 phút.

Không có cooldown riêng theo từng email trong resend verification/forgot password. Các request này vẫn chịu giới hạn chung theo IP; resend verification tạo token mới và vô hiệu hóa link trước đó. Cơ chế rate limit dùng store mặc định trong process, nên không tự chia sẻ bộ đếm giữa nhiều instance backend và thường reset khi process khởi động lại.

## 10. Các lớp bảo vệ và cấu hình triển khai

- `bcryptjs` cost `10` để hash mật khẩu; so sánh bằng `bcrypt.compare`.
- Action token email và refresh token sinh từ `crypto.randomBytes`; database chỉ lưu hash SHA-256.
- Auth routes đặt `Cache-Control: no-store`; API dùng Helmet và CORS theo `CORS_ORIGINS`.
- CORS mặc định cho phép mọi origin (`*`); production nên đặt danh sách origin cụ thể.
- Ứng dụng Flutter ở release từ chối HTTP tới host bên ngoài; HTTPS là cấu hình cần dùng cho API production. `localhost`, `127.0.0.1`, `::1` và `10.0.2.2` được cho phép cho phát triển cục bộ/emulator.
- Production cần `JWT_SECRET` tối thiểu 32 byte và phải là khóa ngẫu nhiên riêng; giá trị mặc định chỉ dành cho development. Không commit secret.
- Production gửi email cần SMTP hoặc Brevo cùng `PUBLIC_URL` HTTPS; nếu thiếu, server không phát link xác minh/reset.
- Auth endpoints được nhóm trong `backend/src/routes/auth.routes.js`; các endpoint tài chính khác cũng được gắn `requireAuth`.

## 11. API tài khoản tham khảo

Tất cả đường dẫn dưới đây có tiền tố `/api/auth`.

| Method | Endpoint | Bearer JWT | Mục đích |
|---|---|---|---|
| `POST` | `/register` | Không | Tạo tài khoản và gửi link xác minh |
| `POST` | `/verify-email` | Không, cần token email | Xác minh email; token bị tiêu thụ khi thành công |
| `POST` | `/resend-verification` | Không | Cấp lại link xác minh |
| `POST` | `/login` | Không | Xác thực thông tin và phát session |
| `POST` | `/refresh` | Không, cần refresh token | Xoay refresh token và phát access token mới |
| `POST` | `/forgot-password` | Không | Gửi link đặt lại mật khẩu |
| `POST` | `/reset-password/validate` | Không, cần token email | Kiểm tra link, chưa tiêu thụ token |
| `POST` | `/reset-password` | Không, cần token email | Đổi mật khẩu và tiêu thụ token |
| `GET` | `/verify-email`, `/reset-password` | Không, cần token trong query | Trang HTML trung gian; GET chưa thực hiện thao tác cuối |
| `GET` | `/open-app/:action` | Không, cần token trong query | Mở app/deep link hoặc trang web |
| `GET` | `/me` | Có | Đọc user hiện tại |
| `PUT` | `/me` | Có | Cập nhật profile (tên, tiền tệ, ẩn số dư, tỷ giá) |
| `PUT` | `/change-password` | Có | Đổi mật khẩu khi biết mật khẩu cũ |
| `POST` | `/logout` | Có | Thu hồi phiên hiện tại |
| `DELETE` | `/me` | Có + mật khẩu | Xóa tài khoản và dữ liệu |

## 12. Lưu ý bảo mật khi đọc implementation

1. **Token trong URL:** email dùng `GET /api/auth/open-app/:action?token=...`. `morgan` loại log GET cho trang `/verify-email` và `/reset-password`, nhưng không loại rõ route `/open-app`; access log của môi trường có thể ghi URL chứa token. Nên hạn chế quyền đọc log và cân nhắc che query token khi triển khai.
2. **Email enumeration:** login dùng thông báo chung cho email/mật khẩu sai; resend verification cũng trả thông báo chung. Riêng forgot-password hiện trả kết quả phân biệt tài khoản chưa đăng ký/chưa xác minh/đã xác minh.
3. **Rate-limit nhiều instance:** giới hạn mặc định theo IP/process, không phải kho dùng chung; nếu mở rộng nhiều server nên cấu hình store phân tán và proxy/IP đúng.
4. **Logout ngoại tuyến:** local session bị xóa, nhưng server-side revocation chỉ xảy ra khi request đến backend.
5. **Xóa tài khoản:** xóa nhiều collection không dùng transaction như mô tả ở trên; nên có backup/quy trình vận hành database phù hợp.
6. **JWT không mã hóa:** chỉ chữ ký được xác thực; không lưu dữ liệu bí mật trong claims.

## 13. Mã nguồn và kiểm thử liên quan

- Frontend: [màn đăng nhập/đăng ký](../frontend/lib/features/auth/presentation/screens/auth_screen.dart), [quên và đổi mật khẩu](../frontend/lib/features/auth/presentation/screens/forgot_password_screen.dart), [xác minh/đặt lại mật khẩu](../frontend/lib/features/auth/presentation/screens/email_link_screens.dart), [màn tài khoản](../frontend/lib/features/settings/presentation/screens/account_screen.dart), [provider](../frontend/lib/features/finance/presentation/providers/finance_provider.dart), [validation](../frontend/lib/core/validation/validators.dart), [secure session storage](../frontend/lib/features/auth/data/datasources/session_store.dart), [tự refresh session](../frontend/lib/features/auth/data/datasources/session_client.dart), [kiểm tra HTTPS](../frontend/lib/core/network/api_client.dart).
- Backend: [auth routes](../backend/src/routes/auth.routes.js), [auth service](../backend/src/services/auth.service.js), [session/JWT service](../backend/src/services/session.service.js), [validator](../backend/src/validators/auth.validator.js), [rate limit](../backend/src/middleware/rate-limit.js), [auth middleware](../backend/src/middleware/auth.js), [mail service](../backend/src/services/mail.service.js), [User model](../backend/src/models/User.js), [RefreshToken model](../backend/src/models/RefreshToken.js), [user repository](../backend/src/repositories/user.repository.js), [session repository](../backend/src/repositories/session.repository.js), [backend config](../backend/src/config/index.js).
- Kiểm thử liên quan: [api.test.js](../backend/test/api.test.js) và [extra.test.js](../backend/test/extra.test.js) kiểm tra validation, HS256, xác minh email một lần, reset token cạnh tranh, refresh rotation, khóa đăng nhập và phiên đơn.
