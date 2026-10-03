# Checkpoint Web runtime — 2026-10-03

## Trạng thái

Đang triển khai, chưa nghiệm thu Web 100%. Bản này tiếp nối checkpoint
`checkpoint-2026-10-03-web-production-readiness.md`; không sửa bằng chứng lịch sử.

## Phê duyệt đã thực hiện

- Tạo `AdminSettings/ai_config` còn thiếu từ `deploy/default_ai_master_prompt.txt`;
  giữ nguyên nếu document đã có. Prompt được xác nhận đã tồn tại sau thao tác.
- Cấp `standard` cho QA `ints.minhtn@gmail.com` theo phê duyệt riêng, không cấp Admin.
- Cấp Standard cho bốn tài khoản hoạt động còn thiếu claim `role` và không có
  `admin`; giữ mọi role sẵn có. Tổng năm tài khoản hoạt động có Standard.
- Mật khẩu QA nằm trong Keychain; không ghi credential/token vào repository.

## Code và kiểm thử đã có

- Source BE commit `c7fdc40`; source FE commit `797f486`. Release này giữ
  nguyên các thay đổi Mobile và cleanup ngoài phạm vi chưa commit.

- Pipeline ba specialist SMC/VSA/Macro + aggregator dùng feature summary,
  Master Prompt, temperature 0, timeout, audit đóng và deterministic stage gate.
  Specialist lỗi thì không gọi aggregator, không tạo Layer 4.
- Quota Analysis dựa trên claim được Firebase Admin xác minh, đếm nguyên tử
  trong Firestore, idempotent theo request; Standard hai lượt/tuần UTC.
  80 request đồng thời trên Emulator: 50 nhận lượt, 30 bị chặn, retry không
  cộng thêm và cửa sổ mới reset đúng. Backtest quota còn chưa tích hợp.
- FE đợi trạng thái request thật để kết thúc spinner; lỗi quota/access/timeout
  được dịch EN/VI; kết quả cũ không ghi đè chart đã đổi.
- FE bỏ Bid/Ask/spread tự tính từ giá nến, hiển thị giá chart và chế độ PAPER.
- FE reconnect giữ symbol/timeframe, dispose hủy timer/subscription; full
  snapshot đến muộn được lọc theo symbol/timeframe. BE gửi interval trong
  init/update/tick và bỏ qua thao tác chọn lại cùng giá trị.
- Full Python sau thay đổi WebSocket: 246/246 với Auth/Firestore Emulator.
  Image `49660550a6fc`: 246 ca, 222 đạt, 24 ca Emulator skip trong container
  cô lập mạng, không env production và không mount credential.
- Full Flutter sau tích hợp Backtest: 136/136; 13 ca tập trung Backtest đạt.
  Analyze không error/warning (ba info deprecation Mobile có sẵn).

## Runtime đã chứng minh

- Candidate `bd64ab0fad17`, loopback 8014, background workers tắt; chưa là live.
- QA Standard trên candidate: private API 200; foreign UID 403; anonymous 401.
  Một request ETHUSD M5 hoàn thành, ghi signal trước COMPLETED, quota 1/2,
  nguồn `tradingview:BITSTAMP:ETHUSD:exchange_volume`.
- DeepSeek thật trả HTTP 402 cho cả ba specialist. Audit ghi
  `payment_required`; aggregator bị bỏ qua, fallback=true, setup_ready=false,
  veto=true và không Layer 4. Chưa có bằng chứng bốn lời gọi AI thành công.
- Đã chuyển BE live sang `protrading-ai:web-49660550a6fc`, image SHA
  `a112547fea24f9d61b81f826af8524639d53de036344d3a90900b666dcc073f8`.
  Health localhost/public đạt. Container live cũ dừng và giữ để rollback;
  hai candidate cũ dừng. Candidate mới 8016 giữ để kiểm tra read-only.
- FE Phân tích/Quote/PAPER/reconnect đã phát hành, hash public khớp build:
  `c70917e5b065935f153158e893fc4edc7bc36bc18fcf166fd4c900ba515102f9`.
- Browser QA trên bản này: request BTCUSD M5 COMPLETED, quota tăng từ 1/2
  lên 2/2; request tiếp theo ERROR `quota_exhausted`, counter giữ 2/2,
  spinner kết thúc và thông báo EN được kiểm tra trực tiếp. Reset tuần là
  2026-10-05 00:00 UTC (07:00 Việt Nam). Bằng chứng JSON và ảnh nằm cùng thư mục.
- Browser phát hiện cache Flutter cần reload lần hai sau deploy. Đã phát hành
  bootstrap inline, entrypoint có query theo version và gỡ riêng legacy Flutter
  service worker; giữ FCM worker. Hosting `max-age=0, must-revalidate` đã xác
  nhận public. Ba Node regression đạt, một lần reload nhận build mới.
- FE Backtest/Profile/cache cuối đã phát hành, hash public khớp build:
  `81ef7ac34d52cfebdcb84e2e72663c2870019bb20341e3aea5a6f813198185ee`;
  loader version `1408241999`. Profile EN/VI hiển thị đúng 2/2 và ngày reset
  địa phương 2026-10-05 07:00. Không deploy Rules/indexes trong đợt này.

## Backtest — phần code mới

- BLoC dùng `BacktestSimulationEngine` đã có, chỉ đưa nến đến cursor vào chart;
  BUY/SELL/close/step/play/speed tính P&L từ giá đóng nến và đơn vị tài sản.
  Tiền mô phỏng dùng tiền định giá của cặp; không gọi đây là lot của broker,
  không giả spread/commission/slippage.
- Setup cho chọn mã, số dư ảo, mức lỗ và tạo mới/khôi phục. Backtest có riêng
  market connection; chuyển tab không đổi symbol/timeframe của Trading Room.
- Ghi `recording` version 1 trong `backtest_sessions` đã có: lịch sử OHLCV
  đóng bất biến (tối đa 3.000 nến), snapshot replay/trades/risk review. Lịch sử
  ghi một lần; các bước sau chỉ update snapshot và số liệu phiên. Không đổi
  Rules, indexes, public API hoặc document cũ.
- Restore dùng đúng lịch sử đã lưu và dừng playback; đối soát balance,
  entry/exit với nến nhìn thấy, từ chối lệnh/timestamp tương lai. Có lệnh rồi
  thì không rewind; khóa lỗ phải acknowledge đúng review. Lỗi lưu dừng phiên,
  chặn thao tác và cung cấp retry.
- Đây là kết quả luyện tập riêng tư do client tính, không phải performance
  được server/broker xác minh và không được dùng cho leaderboard/hoa hồng.
  Quota Backtest vẫn chưa có chính sách/enforcement hoàn chỉnh.
- Browser production: phiên BTCUSD M5 có 2.999 nến đóng, số dư ảo 1.000 USD,
  ngưỡng lỗ 10 USD; BUY/SELL/close thực sự cập nhật theo cursor. Playback 10X
  dừng tại cursor 98 khi equity 903,11 USD; review ghi lỗ 96,89 USD và hai
  lệnh đã đóng. Refresh giữ nguyên cursor/lệnh/review và vẫn khóa.
- Acknowledge review rồi đóng lệnh còn lại: ba lệnh đóng, balance/equity
  903,1102 USD, open P&L 0. Đọc recording thuộc QA qua Admin SDK đối soát
  mọi entry/exit bằng close của nến nhìn thấy và tính lại balance đều đạt.
  Bản FE cuối khôi phục đúng phiên này, paused, EN/VI hoạt động.
- Bằng chứng: `web-production-backtest-qa-2026-10-03.json`, ảnh `...-lock`,
  `...-restored`, `...-final`; Profile tại `web-production-profile-quota-2026-10-03.png`.
  W22/W23 còn mở cho quyền sử dụng history, quota và phần nghiệm thu liên quan
  của toàn kế hoạch; không biến bằng chứng phiên riêng thành Web 100%.

## Tiếp tục

1. Lưu source và bằng chứng release vào GitHub main theo phê duyệt đã có,
   xác nhận SHA remote sau push.
2. Tiếp tục quota Backtest và kiểm thử các role khác bằng danh tính đúng quyền.
3. Tiếp tục các hàng News, Community, Referral, Admin, Radar, Push, Data Lake
   và role matrix còn mở trong `web-completion-plan.md`.

Việc nạp số dư DeepSeek đang chờ chủ tài khoản. Thiếu Macro/calendar/sentiment
có nguồn, quyền sử dụng thương mại market feed và các hàng nghiệm thu khác
vẫn ngăn tuyên bố hoàn thành 100%; không thay dữ liệu thiếu bằng dữ liệu giả.
