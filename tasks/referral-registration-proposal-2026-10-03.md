# Referral registration — lát tiếp theo của W26

Chủ dự án đã giao lựa chọn phương án kỹ thuật để hoàn thiện Web. Lát này nối
link `?ref=code` với đăng ký thật; không cấp role, không phát sinh hoa hồng,
không gửi UID/profile đến DeepSeek hoặc người giới thiệu.

- Web đọc duy nhất một query `ref` gồm 24 ký tự hợp lệ. Auth BLoC nhận code
  ở ranh giới Web khi tạo; sau khi có Firebase user, gọi repository/token API.
  BLoC chống duplicate và bỏ kết quả khi UID/phiên auth đổi; lỗi có retry ở Hub.
- POST `/api/referral/registration` nhận chỉ `code` (StrictStr, extra forbidden),
  UID từ token. Account phải còn hoạt động, tạo trong 24 giờ và sau account
  người giới thiệu. Không tự giới thiệu hoặc đổi mã đã ghi nhận. Thứ tự thời
  gian tạo account ngăn chu kỳ mà không suy diễn từ dữ liệu client.
- Lưu một record bất biến dưới `users/{uid}/meta/referral_attribution`, chỉ
  chứa code công khai và thời gian server; không chứa email/UID người khác.
  Counter `registeredInviteCount` dưới `referrals/{owner}` cập nhật cùng
  transaction. Counter là đăng ký Auth, không phải khách hàng trả phí/hoa hồng.
- Replay giữ record/counter; request khác code trả conflict. Unknown code,
  account disabled, timestamp thiếu hoặc nguồn Auth lỗi không ghi dữ liệu.
  Account cũ không được gán lại qua link. UI thông báo kết quả được localize,
  vẫn giữ đăng nhập khi Referral lỗi và không đổi quyền/phí dịch vụ.
- Kiểm chứng: Auth/Firestore Emulator token thật, concurrent duplicate,
  cross-user/tamper Rules, fake-clock age ordering, BLoC đổi UID/pending/retry
  và browser đăng ký tài khoản Emulator mới từ link rồi đối chiếu SDK record.

W27 receipt/commission/settlement/withdrawal và video marketing vẫn là các
lát khác. Không triển khai paid AI probe hoặc tạo QA production khi chưa có
câu trả lời cho bước phê duyệt cụ thể đang chờ.
