# Journal broker gate — keyboard và accessibility

## Kết quả cần đạt

- Gate chưa có xác nhận broker link chặn pointer, keyboard focus và semantics
  của preview; action kết nối vẫn dùng được với keyboard/trình đọc màn hình.
- Khi link đã xác nhận, child hoạt động bình thường. Khi trạng thái chuyển
  sang khóa hoặc owner thay đổi, focus/snapshot của owner cũ không mở gate mới.
- UID trống, snapshot waiting/error hoặc dữ liệu không có `brokerLinked == true`
  đều hiển thị khóa. Không thêm role/quota/provider, thay Rules/API hay tạo
  broker link giả trong production.
- Dùng các chuỗi EN/VI đã có cho gate, giữ điều hướng Profile hiện tại.

## Bằng chứng và kiểm tra dự kiến

- Production source `7c9e938`: screenshot khóa nhưng rendered accessibility tree
  vẫn chứa nút CSV/TTS và dữ liệu preview. Chưa bấm hoặc cố vượt gate production.
- Tách presentation nhỏ đang dùng thật để widget test không cần Firebase live;
  test focus/semantics thực sự đỏ trước sửa, rồi positive connect/unlocked,
  relock, anonymous gate và layout 390 px.
- Full Flutter/analyzer/Web build, browser Emulator cả locked/unlocked bằng
  fixture đã ghi nhãn; sau release kiểm tra production chỉ có gate semantics.
- Đây là UI guard; quyền data/backend vẫn do Auth/Rules/API thực thi. Không
  suy ra đã hoàn tất broker provider hoặc W18/W19 từ guard này.

## Local đã đạt

- Bốn ca đầu đỏ đúng lỗi semantics, focus, UID null và relock. Sau sửa, gate
  6/6; full Flutter 209 đạt + 2 skip Web-only. Analyzer không error/warning,
  còn 3 info Mobile có sẵn; Web release Emulator build đạt.
- `BrokerLinkGateView` được production gate dùng trực tiếp, không I/O/test
  dependency mới. `ExcludeFocus` giữ cùng ancestry để unfocus khi khóa lại;
  branch preview bị khóa vẫn blur nhưng không có semantics/pointer. Child
  đổi branch khi lock/relock nên lifecycle hiện có được dispose như trước.
- StreamBuilder có key theo owner; chỉ active, không error và flag đúng `true`
  mới mở. UID null/trống khóa không khởi tạo Firebase. Copy dùng EN/VI đã có.
- Browser 8799 xác nhận fixture linked có controls, đổi duy nhất flag fixture
  sang false thì controls/data biến mất khỏi AX, VI đúng và Enter trên nút
  kết nối mở Profile. Restore true mở lại Journal; không sửa production.
- Bằng chứng: `web-local-journal-gate-qa-2026-10-04.json` và hai PNG locked/
  unlocked. Đây là local paper fixture, không chứng minh MetaApi/broker thật.

## Production đã đạt phần guard

- Source `bfc93b0` trên main và Firebase Hosting. Public bundle SHA
  `de9d6e7f286a327242b151df7b15c473c3bb5e50069dcb09a561ba69445aefd1`,
  3,786,221 bytes khớp local build; URL Emulator không lẫn vào production.
- Reload QA Standard, Journal EN/VI chỉ còn gate và action kết nối trong AX;
  không còn dữ liệu preview hoặc nút CSV/filter/TTS. Screenshot VI rõ ràng.
  Không bấm xuyên gate hoặc sửa broker flag production để nghiệm thu.
- Xem `web-production-journal-gate-qa-2026-10-04.json` và screenshot đính kèm.
  BE/Rules giữ nguyên; không gọi DeepSeek hay sửa claim/quota.
