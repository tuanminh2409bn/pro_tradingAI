# Web production — checkpoint 04/10/2026

## Bản đang phục vụ

- FE source trên GitHub main/Firebase: `6a2745b9188a81a61ab2d85044a9ee468fb3ab15`.
  Public `main.dart.js` khớp byte với build production: 3,803,382 bytes,
  SHA-256 `1f83e0eb1d9588321507321b42a6a250cc272654147232041ee9d44165b5f74d`.
  Endpoint production có mặt; không có endpoint/warning Emulator.
- BE source `7ef3ab68c254244f11cd827113e7be18b584a2a4`, container
  `protrading-ai-referral-live-7ef3ab6`, image `protrading-ai:referral-7ef3ab6`.
  Rules source `43fd970aa1a574d42ac56b7c82cee2ade94dde2c`. Hai phần này không
  thay đổi trong các sửa Journal/Radar/Community/Profile hôm nay.

## Đã sửa và có bằng chứng

- **Journal `c63467e`:** stats/table dùng cùng snapshot; chỉ nhận closed trade
  hợp lệ; tính win/loss/flat, PF/payoff và nhóm loss theo UTC từ mẫu thật.
  Không dựng số liệu tâm lý/risk/tiền tệ khi chưa đo. Sửa EN/VI, audio lifecycle
  và màn hình hẹp. Target 37/37, full Flutter 237 đạt + 2 Web-only VM skip.
  Browser Emulator đối soát 3 paper trades; QA Standard production vẫn bị
  broker gate chặn đúng quyền. Playback thiết bị và broker sample còn mở.
  [Bằng chứng](web-production-journal-performance-2026-10-04.json),
  [spec](journal-performance-correctness-spec-2026-10-04.md).
- **Radar `1487cd8`:** bỏ strength 4/5 cố định và nhãn realtime/USD không đủ
  chứng cứ; giữ precision, snapshot/freshness unverified, selected asset theo
  snapshot mới và clear an toàn. Radar truyền symbol/timeframe đúng vào chart.
  Native production ETHUSD mở ETHUSD/M5 có nến/giá; Emulator ETHUSD/H4 mở
  Day Trading. Không bấm Analyze/Chat/Trade; VETO cũ không chứng minh AI mới.
  Target 14/14, full Flutter 247 đạt + 2 Web-only VM skip.
  [Bằng chứng](web-production-radar-correctness-2026-10-04.json),
  [spec](radar-web-correctness-spec-2026-10-04.md).
- **Community `e43f7f5`:** counter bài/comment dùng count/limit của SDK và
  semantics EN/VI. Native production bản nháp đi 0 → 16 → 0, nhãn VI/EN
  đúng, không đăng nội dung. 14 regression tests đạt; production build đạt.
  Analyzer không error/warning, còn 3 info Mobile đã có; exit code 1 do infos.
  Full 247 là baseline Radar, không ghi thành full rerun cho slice counter.
  [Bằng chứng](web-production-community-counter-2026-10-04.json).
- **Profile `6a2745b`:** seeding kiểm tra UID, metadata lấy từ cùng Auth identity,
  transaction giữ profile đã tồn tại khi contention; chỉ refresh lastSeen.
  5 regression đỏ trước sửa, 7 plugin-boundary cases đạt, full Flutter cuối
  **254 đạt + 2 Web-only VM skip**; analyzer 0 error/warning, 3 info Mobile cũ.
  Native Emulator tạo profile mới/giữ fields cũ/createdAt và foreign UID 403.
  Production QA restore, Profile EN/VI và Journal gate đạt; chọn rõ ETHUSD
  trên Radar mở ETHUSD/M5 có nến/giá 2686.59. Không bấm AI/Chat/Trade.
  Thêm dev declaration cho platform interface đang có; không đổi version
  runtime/dependency production. [Spec](profile-seed-correctness-spec-2026-10-04.md),
  [local](web-local-profile-seed-2026-10-04.json),
  [production](web-production-profile-seed-2026-10-04.json).

## Các mục vẫn mở

- Kế hoạch có **36 hàng nghiệm thu: 7 đóng, 29 mở**. Đây là số hàng, không
  phải phần trăm chức năng. Các slice trên chưa đóng W18/W19/W24/W31/W34.
- DeepSeek: hai GET được duyệt cuối cùng `/user/balance`, `/models` đều **401**;
  key runtime không khớp mask ảnh. Việc nạp tiền được chủ tài khoản xác nhận,
  nhưng chưa có bằng chứng key runtime hợp lệ hoặc AI thành công sau nạp.
- Duyệt tự động đã từ chối đọc key Docker để đối chiếu và probe AI trả phí/
  tạo QA production riêng. Hai yêu cầu phê duyệt cụ thể vẫn đang chờ trả lời.
  Không dùng đường khác đọc secret, bỏ qua quota hoặc nâng QA Standard lên Admin.
- Còn nguồn/quyền sử dụng thương mại market feed, Macro/calendar/sentiment,
  broker/currency/initial-risk sample, TTS playback và ma trận role/tenant thật.
- Còn code onboarding cấp Standard tự động cho đăng ký mới (seeding không cấp
  claim), leaderboard từ dữ liệu broker đã xác minh và tích hợp business.
  QA local có role Standard do setup, không chứng minh pipeline grant-role.
  Một tab QA mất cảnh báo Emulator và lỗi Auth sau reload; fresh-tab login đạt
  nhưng root cause và local session restore chưa nghiệm thu. Production session
  restore đã đạt.
- Radar worker 50–100 asset, AI provenance/freshness, multi-user/load và FCM
  thiết bị chưa nghiệm thu. Ledger/referral accrual/withdrawal/payment policy
  và tích hợp business còn thiếu; Data Lake consent/sink còn tắt.
- Host Ubuntu 16.04/Docker 18.09 chưa đáp ứng runtime được hỗ trợ. Cần host,
  backup, staging SLA/load và rollback drill; không chạy production unconfined.

## Tiếp tục

1. Sau phê duyệt cụ thể: đối chiếu key chỉ đọc từ nguồn được duyệt, rồi probe
   AI/Chat có giới hạn chi phí và QA riêng; không dùng QA đang hết quota.
2. Hoàn thiện các phần code/Emulator còn thiếu trong W25/W27–W33 và thu thập
   bằng chứng production đúng quyền/nguồn cho từng hàng.
3. Chốt host/provider/business gates, chạy staging/role/load/rollback cùng
   manifest trước khi đánh dấu toàn bộ Web PASS.

[Kế hoạch](web-completion-plan.md) · [Ma trận](acceptance-matrix.md) ·
[Lịch sử triển khai](checkpoint-2026-10-03-web-runtime.md) ·
[Providers](provider-matrix.md) · [Runtime](python-runtime-upgrade-2026-10-04.md).
