# Profile seeding — owner và transaction

## Kết quả cần có

`ensureProfileExists(uid)` chỉ dùng metadata của Auth identity khớp UID.
Anonymous, UID khác, hoặc đổi identity trong lúc đọc phải dừng trước khi ghi.
Tạo profile và kiểm tra tồn tại nằm trong cùng Firestore transaction; retry
không ghi đè profile được server hoặc phiên khác tạo trong khoảng đọc/ghi.
Profile đã tồn tại chỉ cập nhật `lastSeen`, giữ `createdAt` và mọi trường khác.

Schema `users/{uid}`, Rules, quota và custom claims không đổi. Profile seeding
không cấp role, không tạo broker account hoặc biến fixture thành business data.
AuthBloc vẫn giữ login khi seeding lỗi; không coi offline seeding là thành công.

## Thay đổi và kiểm thử

- `lib/data/repositories/profile_repository.dart`: capture metadata trước await,
  kiểm tra current UID trước/sau transaction read, dùng get/set/update của SDK.
- `test/profile_seed_identity_test.dart`: 7 regression cases. 5 đỏ trước sửa:
  anonymous/mismatched UID, identity đổi lúc đọc cả new/existing profile, và
  concurrent creation ghi đè fields. Hai cases đúng trước sửa được giữ lại.
- Test dùng class SDK thật với mock platform boundary; không implements class
  sealed và không tắt lint. Platform interface 8.0.1 đang là dependency gián tiếp
  được khai báo thêm ở **dev_dependencies**; không đổi version/package runtime.
- Full Flutter cuối cùng 254 đạt + 2 Web-only VM skip; analyzer không error/
  warning, còn 3 info Mobile cũ (exit 1). Format/diff check và QA build đạt.
- Native browser + Auth/Firestore Emulator: login fixture mới tạo đúng profile;
  fresh-tab login sau khi đặt fixture fields giữ các trường/createdAt, tăng
  lastSeen. Rules đọc UID khác trả 403. Đây là fixture có nhãn, không phải số
  liệu broker được xác minh. Xem `web-local-profile-seed-2026-10-04.json`.

## Giới hạn còn mở

- Một tab QA sau reload mất cảnh báo Emulator và báo Auth unavailable; endpoint
  Auth Emulator vẫn trả 200, asset QA khớp bundle. Fresh tab đúng Emulator login
  và readback đạt. Chưa xác định root cause; không tính reload/session restore
  của tab đó là PASS hoặc suy diễn đã sửa cache. W34 tiếp tục mở.
- `AuthRepository.signUp` hiện chỉ tạo Firebase user. Chưa có writer server cấp
  `role=standard` tự động cho người mới; `consume_operation_quota` vẫn yêu cầu
  claim hợp lệ và từ chối role thiếu/lạ. Cấp Standard thủ công cho các tài khoản
  đã duyệt không hoàn tất onboarding cho tài khoản mới (W28).
- Cơ chế onboarding cần giữ các claims hiện có và refresh token đúng identity:
  Firebase Admin setter thay toàn bộ custom claims, token mới mới nhận claim.
  [Firebase custom claims](https://firebase.google.com/docs/auth/admin/custom-claims).
  Chưa thêm endpoint/worker grant-role hoặc nâng quyền QA production trong slice.
