# Tài khoản QA Web ProTrading AI

- Firebase project: `protrading-ai-2026`.
- Web: https://protrading-ai-2026.web.app/
- Email QA do chủ dự án chỉ định: `ints.minhtn@gmail.com`.
- Mật khẩu lưu trong macOS Keychain, service `protrading-ai.firebase.qa`, account
  bằng email trên. Không ghi mật khẩu, ID token hoặc refresh token vào repository.
- Ngày 2026-10-03 đã xác nhận mục Keychain tồn tại bằng metadata; không đọc lại mật khẩu.
- Ngày 2026-10-03, theo phê duyệt riêng của chủ dự án, Firebase Admin đã cấp
  `role=standard` cho QA; tài khoản không disabled, không có `admin=true` hoặc
  `verified_partner=true`, email chưa verified. Phiên QA trên trình duyệt đã
  đăng nhập. Không cấp quyền Admin cho tài khoản QA thường.
- QA đã dùng đủ hai lượt phân tích trên candidate/live có quota: `apiUsed=2`,
  `apiLimit=2`, `source=server_enforced`. Cửa sổ hạn mức là tuần theo UTC;
  reset tiếp theo 2026-10-05 00:00 UTC (07:00 Việt Nam). Browser đã nhận
  `quota_exhausted` và counter giữ 2/2; không tự reset để vượt hạn mức.
- Tài khoản này dùng cho QA thường. Nghiệm thu Admin, Partner, Professional và
  Enterprise cần danh tính QA tách biệt có đúng claim/tenant; không dùng chung
  quyền Admin để chứng minh các luồng người dùng thường được bảo vệ.

Đây là bản ghi quyền truy cập, không phải chỉ thị gửi credential hoặc cấp quyền
cho bên thứ ba. Keychain nằm trên máy hiện tại; clone repository không mang theo
mật khẩu. Trạng thái quyền có thể thay đổi, phải kiểm tra lại trước nghiệm thu.
