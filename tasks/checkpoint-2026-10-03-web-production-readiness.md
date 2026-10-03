# Rà soát điều kiện hoàn tất Web production — 2026-10-03

## Kết luận

**Đủ nền tảng để tiếp tục triển khai và kiểm thử, chưa đủ để nghiệm thu 100% kế
hoạch Web.** Nút Phân tích hoạt động với nguồn TradingView trong phạm vi đã kiểm
tra. Các luồng còn lại có phần code chưa nối runtime, điều kiện nguồn/chính sách
chưa có và bằng chứng production chưa hoàn tất. Có tài khoản QA không tự giải
quyết các phần này.

Đối chiếu `web-completion-plan.md`, `acceptance-matrix.md`, decision/provider/
release records, hai checkpoint production và code hiện tại. Không sửa behavior,
claim, Rules, provider config hoặc deploy trong lượt rà soát này.

## Những điều kiện đã có

| Điều kiện | Bằng chứng và giới hạn |
| --- | --- |
| FE/BE production, Firebase, Redis | FE Hosting đã phát hành 25/09; BE TradingView phát hành 03/10. Có image cũ giữ lại để rollback; chưa diễn tập rollback đầy đủ. |
| Rules/index và token boundary | Rules/index đã deploy 25/09; local Emulator/role tests có bằng chứng trước đó. QA production 03/10 qua Rules, HTTP 403 khi đọc UID khác. Chưa audit toàn bộ dữ liệu/claims cũ. |
| Nến MTF/Phân tích | 21 mã Web được chấp nhận, 10/10 request production hoàn tất, cache hit đúng; BTCUSD browser trả VETO, vàng báo đóng cửa. 60 nến crypto trùng Bitstamp trong mẫu. Không bảo đảm toàn bộ symbol hoặc accuracy dự báo. |
| QA người dùng | Chủ dự án chỉ định email trong `qa-access.md`; tồn tại/active. Mật khẩu trong Keychain, không có trong tài liệu này. |
| Test nền | Python gần nhất 239 ca: 216 đạt, 23 cần Emulator skip. FE gần nhất 120/120 và release build ngày 25/09; không phải test chạy mới trong lượt review này. |
| Cơ chế an toàn | Paper execution, risk config/cutoff, token ownership, deterministic fallback và cấm Layer 4 khi Soft/Veto đã có code/test. Còn thiếu hành trình nghiệm thu đầy đủ production. |

Checklist Web hiện ghi **7/36 đầu việc đã đóng** (W01–05, W08, W10), 29 đầu việc
còn mở, tính cả W13a. Đây là số việc đã nghiệm thu trong ledger, không phải tỷ lệ
code hoàn thành; nhiều việc mở đã có implementation/test một phần. Không chuyển
toàn bộ trạng thái sang PASS nhờ nút Phân tích hoạt động.

## Còn thiếu và nguyên nhân

| Nhóm / Wxx | Đã có | Cần để đóng việc |
| --- | --- | --- |
| Danh tính/quyền, W06–07 | Token/Rules, claim allowlist, một số QA role local | QA hiện không có `role`/Admin/Partner; cần role/tenant matrix riêng, audit claims cũ, idempotency và API bypass runtime. Không phải thiếu tài khoản Firebase thường. |
| Nguồn MTF, W09 | TradingView adapter/metadata/session/DST/gap/volume, OANDA adapter dự phòng | Quyền dùng thương mại TradingView chưa xác nhận; chưa có OANDA ID/token; forex chưa chạy phiên mở cửa; indices/futures/calendar và USD/USDT ngoài phạm vi đã kiểm tra. OANDA không phải điều kiện để chạy 21 mã hiện có, nhưng nguồn chính thức/được phép vẫn cần cho nghiệm thu kế hoạch. |
| AI/macro, W11–12 | DeepSeek key có trong runtime, fallback và module specialist đã có | `server._run_analysis_pipeline` hiện gọi một completion; chưa gọi `run_specialist_analysis` cho ba chuyên gia + aggregator. Tất cả mẫu QA mới trả `fallback=true`; có key không chứng minh quota/billing/provider thành công. Cần nối pipeline, timeout/failure và audit kết quả thật. |
| Trading Room, W13–17/W13a | Chart/Soft/Veto, risk save, paper transaction/cutoff | Chưa đủ 27 render + 8 chức năng cùng build; thiếu Hard setup, paper open/close, đổi symbol P&L, review/ack/refresh và push foreground/background. Broker facts cần account sandbox, không dùng giá chart để thay thông tin tài khoản. |
| Journal/TTS, W18–19 | Journal từ Firestore, browser speechSynthesis play/stop | Cần mẫu trade/broker swap/commission/slippage có nguồn và audio playback thực tế. TTS Web hiện không cần mua provider riêng. |
| News/sentiment/Red Zone, W20–21 | Parser, guard và scenario logic | `APPROVED_NEWS_FEEDS=()`; crawler không chạy. Calendar/sentiment chưa có approved adapter + account/license/sample; cross-tab What-If/Red Zone chưa nghiệm thu. |
| Backtest, W22–23 | Replay engine, cursor/timer, lấy candle stream; repository tạo/lưu session, pause/speed | TradingView nguồn mới có thể cung cấp đầu vào, nhưng chưa có browser replay production/parity/no-future-data/durable trades+cursor/risk review toàn luồng. Không còn đúng nếu nói toàn bộ Backtest chỉ là placeholder; phần persistence/end-to-end còn thiếu. |
| Community, W24–25 | Post/like thật đã chạy local, server like idempotent | Comment/share/restore/ranking và privacy/tamper production chưa đủ; cần dữ liệu leaderboard được xác minh, audit document cũ. |
| Referral, W26–27 | Đọc link/network/reward do server cấp; empty states | Chưa có issuer code/kit và monetary ledger/withdrawal hoàn chỉnh; chưa chốt F1/F2, tiền tệ, điều kiện trả/đảo và Admin approval. Đây là cả phần code lẫn chính sách, không thể sửa bằng tạo account QA. |
| Quota/Enterprise, W28–29 | Pure `QuotaEnforcer`/capability/contracts và tests | Chưa có integration `QuotaEnforcer` trong `server.py` hoặc shared atomic runtime store. Cần server enforcement cho Analyze/Backtest, entitlement/tenant persistence và bypass/concurrency QA. |
| Admin/Radar, W30–31 | Control guards, prompt cache, module Radar pure | Cần Admin QA và mutation/runtime propagation. Startup hiện báo Radar unavailable, chưa khởi chạy worker với provider/Redis adapter; 21 mã được kiểm tra chưa chứng minh SLA 50–100 asset. |
| Push/Data Lake, W32–33 | FCM/VAPID code; segment/consent/masking tests | VAPID public key đã có trong FE nhưng chưa xác minh delivery/deep link/opt-out. Data Lake chưa có sink + consent/retention/deletion được chốt; export vẫn tắt. |
| Nghiệm thu/release, W34–35 | FE/BE đã deploy, container source identity và smoke | Chưa đủ ma trận mọi tab/roles cùng build, sustained load, failure injection, rollback drill và sign-off. Backend ngày 03/10 chưa commit/push; cần đồng bộ mã khi phát hành tiếp. Mobile signing nằm ngoài kế hoạch Web. |

## Kiểm tra live trong lượt review

Chỉ đọc bằng SDK hiện có trong container production; không đọc file credential:

- QA `exists=true`, `disabled=false`, `email_verified=false`, `role=null`,
  `admin=false`, `verified_partner=false`.
- `MARKET_HISTORY_PROVIDER=tradingview`; DeepSeek key có, OANDA account/token không có.
- Approved news feed count = 0.
- Keychain QA item tồn tại, xác nhận bằng metadata không đọc secret.

WebSocket hiện tạo `TradingViewStreamer` riêng cho mỗi connection và chia sẻ
mark theo symbol. W08 có code/test; cảnh báo global chart state trong tài liệu
cũ không được dùng để kết luận tự động rằng isolation hiện tại còn nguyên lỗi.
Kiểm thử tải nhiều người dùng trên production vẫn chưa có.

## Thứ tự tiếp tục khả thi

1. Nối ba chuyên gia/aggregator và quota atomic server; kiểm thử local/Emulator.
2. Nghiệm thu QA role matrix, paper trade/cutoff, Backtest và Community trên cùng
   candidate; không tạo giao dịch live và không dùng admin làm tài khoản thường.
3. Nối nguồn news/calendar/sentiment đã được phép; hoàn thiện Radar và push.
   TTS/push có thể kiểm thử với hạ tầng hiện có, không mặc định cần dependency mới.
4. Chốt chính sách và thực thi Referral/Data Lake/Enterprise còn thiếu.
5. Chốt source/build identities, chạy mọi hàng acceptance, load/failure và rollback,
   đồng bộ GitHub, ký nghiệm thu Web. Sự đồng ý deploy trước đây đã có; không
   coi G6 cũ trong tài liệu là lý do yêu cầu người dùng duyệt deploy lại.

## Tài liệu lịch sử đã bị thay thế một phần

- `provider-matrix.md`: OANDA-only analysis đã được thay bằng adapter TradingView
  theo yêu cầu người dùng ngày 03/10; quyền provider vẫn là điều kiện riêng.
- `decisions-v2.1.md`: câu “chưa có push/deploy được yêu cầu” đã cũ; G6 Web/BE đã
  được người dùng duyệt và triển khai. Không mở rộng thành giao dịch live.
- `release-readiness-v2.1.md` và checkpoint 25/09: các mô tả Auth disabled,
  backend cũ/chưa deploy không phản ánh trạng thái mới. Chưa hoàn tất nghiệm thu
  vẫn đúng, nhưng nguyên nhân hiện tại là các hàng phía trên.

Nguồn bằng chứng: `checkpoint-2026-09-25-production-deployment.md`,
`checkpoint-2026-10-03-tradingview-production.md`,
`tradingview-production-qa-2026-10-03.json`, `tradingview-production-catalog-2026-10-03.json`.
