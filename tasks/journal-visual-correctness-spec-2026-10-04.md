# Journal Web — dữ liệu cuối tuần, UTC và hình học biểu đồ

## Lỗi có bằng chứng

- Heatmap Web lọc weekday 1–5 và chỉ vẽ năm hàng, làm mất trade 6/7; crypto
  có giao dịch cuối tuần. Repository nhóm closeTime giờ local, trong khi
  insight đã nêu ngày/giờ UTC. Native QA có loss Sunday nhưng heatmap trống.
- Bảng giá dùng toStringAsFixed(2), làm entry/exit forex khác nhau thành cùng
  một số. CSV hiện giữ đúng precision, nên bảng và CSV không khớp.
- Equity painter chia width/(count-1); một trade tạo tọa độ NaN. Series có
  các giá trị bằng nhau bị vẽ ở sát mép dưới, khó quan sát.

## Sửa và kiểm tra

- Nhóm thời điểm đóng theo UTC; heatmap Web có đủ 7 ngày, 24 giờ (12 bucket
  hai giờ trên màn hẹp). Tooltip có ngày/khung giờ UTC, count ghi là số lệnh,
  không gắn đơn vị Lots cho tradeCount. Không nhận hour/day/P&L/count hỏng.
- Giữ precision số hữu hạn của entry/exit trong bảng; dữ liệu không hữu hạn
  hiện “—”. Không đổi persistent model, API, broker gate hoặc tạo broker sample.
- Equity một điểm vẽ điểm hữu hạn; series ngang vẽ giữa vùng chart, series
  biến động giữ hình học tương đối. Empty/invalid/zero-size không vẽ giả.
  Nhãn nói đúng dữ liệu đang có: P&L lệnh đóng, không suy ra broker equity.
- Kiểm thử table precision đỏ trước sửa, unit UTC/bucket/weekend/adversarial,
  widget compact/tooltip và kiểm tra pixel cho single/flat/empty equity.
- Browser QA/Emulator dùng đúng fixture đã ghi nhãn, xác nhận bucket Sunday
  có dữ liệu và precision giữ nguyên. Format/analyzer/build, review rồi deploy
  FE theo phê duyệt; server/Rules/provider/quota giữ nguyên.

W18/W19 vẫn cần source broker và bằng chứng playback production đúng quyền;
không đóng cả Journal từ kiểm thử fixture.

## Kiểm tra local đã đạt

- Test widget precision thực sự đỏ với giá 1.1234567/1.1234568 bị mất trước
  sửa; sau sửa đạt. Target 20/20, full Flutter 203 đạt + 2 skip Web-only.
  Pixel tests xác nhận single point/flat line hiển thị, invalid/empty không vẽ.
- Analyzer không error/warning; 3 info Profile Mobile cũ giữ nguyên.
  Web release Emulator build đạt; helper UTC chỉ được dùng ở Web, không đổi
  aggregation Mobile đang có hoặc persistent model/schema.
- Browser origin mới 8797 có cảnh báo Emulator trước nhập credential fixture.
  Journal VI/EN xác nhận Sunday/CN 06:00–06:59 UTC chứa 3 lệnh và P&L -7.91,
  bảng giá giữ 1.1234567/1.1234568 và nhãn biểu đồ P&L lệnh đóng.
  Chỉ dùng paper fixture; cờ broker link trong Emulator không nghiệm thu provider.
- Bằng chứng: `web-local-journal-visual-qa-2026-10-04.json` và
  `web-local-journal-visual-2026-10-04.png`; không gọi model/sửa production.

## Release production đã đọc lại

- Source `7c9e938` đã lên GitHub main/Firebase Hosting. Public `main.dart.js`
  3,785,939 bytes, SHA
  `bf82ac4bd22e0a92224ac53c1b62f8b20d53435749c3012114fab2337338606c`
  khớp build production; không lẫn URL Emulator. BE `7ef3ab6` và Rules
  `43fd970` không đổi trong lát sửa FE này.
- Reload QA Standard xác nhận title P&L lệnh đóng, UTC, đủ bảy ngày và giá
  4525.055/4525.81 qua rendered tree. Screenshot vẫn JOURNAL LOCKED vì QA
  chưa liên kết broker; không bấm xuyên gate để tải CSV hoặc phát TTS.
- Rendered tree còn đọc được descendant của preview bị blur; kiểm tra này
  chưa chứng minh gate chặn keyboard/accessibility. Cần test và sửa riêng.
- Bằng chứng: `web-production-journal-visual-qa-2026-10-04.json` và PNG cùng tên.
  Không gọi model, sửa user/claim/quota/provider. W18/W19 tiếp tục mở.
