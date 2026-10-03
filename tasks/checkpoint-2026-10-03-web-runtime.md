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

## News — bản tin có nguồn và chat an toàn

- Source BE `5421586`, FE `e5f535c`; build hash và readback được ghi bên dưới.
- Nguồn text-only được chọn theo quyền lựa chọn provider chủ dự án đã giao:
  RSS chính thức Fed `press_all` và `press_monetary`. Disclaimer của Fed cho
  phép sao chép/phân phối thông tin public domain với dẫn nguồn; không lấy
  ảnh/logo hoặc nội dung bên thứ ba có quyền riêng. Không dùng RSS làm lịch
  HIGH-impact hoặc tự suy ra sentiment/social mentions.
- Parser thuần trong `official_news.py` giới hạn kích thước, từ chối XML
  DTD/entity, URL ngoài nguồn, thiếu/future publication date và bài quá 30 ngày.
  ID ổn định theo URL, timestamp là ngày xuất bản thật; freshness được ghi riêng.
- Worker có timeout, chỉ chạy registry được duyệt và dedupe giữa hai feed.
  Production có 13 bài Fed duy nhất, tất cả publication timestamp khớp,
  `impact=UNRATED`, không có sentiment score. Query FE chỉ nhận record có
  provenance license approved; dữ liệu cũ chưa duyệt được giữ trong DB và không
  hiển thị. Không deploy Rules/indexes hoặc thêm dependency.
- Sentiment cũ thiếu provenance/freshness được hiển thị unavailable; không dùng
  các số legacy làm chỉ số thị trường hiện tại. AI error/fallback hiển thị lỗi
  dịch EN/VI, kết thúc spinner; không biến lỗi thành câu trả lời phân tích.
- News BLoC chặn request trùng, dùng state mới khi response tới, gắn request và
  history với generation/UID để không ghi đè phiên khác. Input/send/clear khóa
  trong lúc xử lý. Clear đợi những write đã nhận trước khi xóa; lỗi giữ lịch sử
  và cho retry. Provider được tạo lại khi UID đổi, dispose bỏ late response.
- BE live `protrading-ai:news-6271bd6007ae`, image SHA
  `8692dbb180407f79ce583bcfa0f9d1703cf34146d47cc6921017866ab53d16f0`;
  localhost/public health đạt, image BE cũ giữ để rollback. FE hiện tại SHA
  `9bc7893891862976c3f1633aa76e51e88dd900502a776c7900d424c5325414c9`
  khớp file public sau deploy.
- Full Python 250/250 với Auth/Firestore Emulator; image cô lập 250 ca gồm
  226 đạt và 24 skip cần Emulator. Full Flutter 147/147, trong đó tám regression
  chat mới; analyzer 0 error/warning và ba Mobile info có sẵn. Web release đạt.
- Browser cùng FE cuối: 13 bài, mở chi tiết và Read Full Article tới đúng URL
  Fed; width 600 px không có overflow log. Gửi câu hỏi nguồn công khai: controls
  bị khóa khi pending, sau đó AI unavailable/spinner dừng/controls mở lại.
  DeepSeek thiếu số dư vẫn chặn phản hồi AI thành công.
- Bằng chứng: `web-production-news-qa-2026-10-03.json` và ba ảnh Fed,
  AI-unavailable, responsive cùng thư mục. W20/W21 vẫn mở cho nguồn social,
  calendar và bằng chứng What-If/Red Zone; không đánh dấu toàn trang News 100%.

## Operations — readiness thật

- Source BE `85e5e6b`. DeepSeek status dùng GET `/user/balance`, HTTP 200 và
  boolean `is_available=true`; không coi root endpoint trả 402/404 là AI online,
  không gọi completion trả phí và không lưu/in số dư hoặc key.
- Data status yêu cầu mark hữu hạn, dương và được nhận trong 180 giây, chia sẻ
  riêng timestamp theo symbol giữa các session; chart state vẫn độc lập.
  MT4 Bridge không được báo online từ HTTP root khi chưa có bridge hoạt động.
- Live `protrading-ai:services-e03feca1d470`, image SHA
  `b82962fc900bc49fcc50e316ea385608ae79c8135a4c40e66919d2e7b21a0cb0`;
  localhost/public health đạt. Container News cũ giữ stopped để rollback.
- Read-only DeepSeek thật: HTTP 200, `is_available=false`. Firestore status
  sau cutover: AI false, MT4 false, Data true, Redis true. Chỉ ghi các field
  status có sẵn, không đổi Rules/schema/public API/dependency.
- Full Python với Emulator 256/256; image cuối cô lập 256 ca gồm 232 đạt,
  24 skip cần Emulator. Sáu regression readiness mới và các ca isolation/local
  WebSocket/async boundary đều đạt.
- WSS public sau cutover nhận BTCUSD/M5 init, 3.000 nến và giá dương;
  probe read-only không gọi Analysis hoặc tạo lệnh.
- Bằng chứng: `web-production-service-readiness-2026-10-03.json`.
  Admin browser vẫn cần danh tính có claim phù hợp; không cấp Admin cho QA
  Standard từ phê duyệt cấp Standard.

## Mốc hoàn thành kế hoạch

- Backtest quota source `0de11ce` đã lên main/FE/BE/Rules. Client tạo phiên
  qua API có token; session + counter commit nguyên tử. Standard 2/tuần,
  Professional 50/ngày, Enterprise 300/ngày; counter độc lập với Analysis.
  Restore không trừ lượt; replay score vẫn là mô phỏng riêng tư.
- Browser production QA tạo hai phiên, hai recording lưu được; lần thứ ba
  báo hết quota tiếng Việt và dừng spinner. Restore vẫn chạy khi hết quota.
  Profile hiển thị Analysis 2/2, Backtest 2/2, reset cả hai 05/10 07:00 VN.
  Emulator 272/272, Flutter 151/151, image 246 đạt + 26 skip; Web build đạt,
  analyzer 0 error/warning và 3 Mobile info có sẵn. Bằng chứng:
  `web-production-backtest-quota-2026-10-03.json` và bốn ảnh quota mới.
- Chủ dự án đã xác nhận nạp DeepSeek và giao lựa chọn phương án để tiếp tục.
  Probe production đã soạn (QA Standard riêng, 1 Analysis + 1 Chat, không PII)
  bị auto-review chặn vì cần xác nhận cụ thể identity/payload/đích/chi phí.
  Đã hỏi qua async input; chưa chạy probe, không vượt QA quota hoặc tự cấp
  Admin. Trong khi chờ tiếp tục phần code/Emulator độc lập.

- Điều tra chi phí DeepSeek và bản sửa cost controls đã lên BE production:
  source `64f7341`, live `protrading-ai:cost-64f7341`. Input cap 24.000 byte
  UTF-8/call, tắt retry Chat, log usage chỉ số token. Giữ output cap 1.500/600,
  thinking disabled, specialist/cache/quota hiện có. Emulator 263/263;
  final image 239 đạt + 24 skip; SDK HTTP mock, health, anonymous 401 và
  WSS public đạt, không gọi completion thật khi kiểm chứng. Chi phí ảnh
  $2,10/200 request chưa đối chiếu đủ với log cũ; không coi là giá một click.
  Chi tiết: `deepseek-cost-investigation-2026-10-03.md`. Chưa có trần USD
  tổng hệ thống hoặc quota Chat riêng; chưa chứng minh mức tiết kiệm thực tế.

- Checklist có 36 mục W, đã đóng 7 và còn 29; nhiều mục mở đã có phần code
  hoặc runtime proof. Đây là số mục nghiệm thu, không phải phần trăm code.
- Code còn cần hoàn thiện gồm quota Backtest, Community comment/share,
  Referral code/kit/ledger, tenant controls, Radar và các flow Admin/push/privacy
  được phép. Còn bộ render 27/27, 8/8 chức năng và role/load/rollback cùng build.
- Điều kiện nguồn/kinh doanh còn thiếu: DeepSeek đủ số dư, calendar/social có
  quyền dùng và mẫu thật, quyền phân phối market data, chính sách Referral và
  consent/retention/sink của Data Lake. Owner đã giao chọn phương án kỹ thuật;
  không xin lại quyền triển khai đã có, không tự thanh toán hoặc ký hợp đồng.
- Chưa có ngày nghiệm thu 100% có thể cam kết. Việc code và kiểm thử vẫn tiếp
  tục được trên các phần độc lập; trạng thái unavailable không đóng các chức
  năng mà chủ dự án yêu cầu phải hoạt động đầy đủ.
- Ước lượng sơ bộ cho lập kế hoạch: 10–15 ngày làm việc cho code/kiểm thử còn
  lại sau khi đủ nguồn và quyết định, với phạm vi hiện tại. Chưa phải deadline
  đã cam kết; thời gian chờ nhà cung cấp/giấy phép/nạp số dư không được xác định.

## Tiếp tục

1. Source News và bằng chứng đã có trên main `6268e60`; lưu tiếp source
   Operations và readback sau release, xác nhận SHA remote sau push.
2. Quota Backtest đã triển khai và chứng minh Standard production. Tiếp tục
   ma trận các role khác bằng danh tính đúng quyền và bước AI thật được duyệt.
3. Tiếp tục các hàng News, Community, Referral, Admin, Radar, Push, Data Lake
   và role matrix còn mở trong `web-completion-plan.md`.

Chủ tài khoản đã xác nhận nạp DeepSeek; bằng chứng AI thành công còn chờ probe
được duyệt. Thiếu Macro/calendar/sentiment
có nguồn, quyền sử dụng thương mại market feed và các hàng nghiệm thu khác
vẫn ngăn tuyên bố hoàn thành 100%; không thay dữ liệu thiếu bằng dữ liệu giả.
