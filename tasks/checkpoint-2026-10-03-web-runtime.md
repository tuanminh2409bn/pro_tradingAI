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
  `web-production-backtest-quota-2026-10-03.json` và các ảnh quota mới.
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
- Quota Backtest và Community post/comment/like/share đã có code và bằng chứng
  runtime như các mục dưới. Code còn cần hoàn thiện gồm Referral code/kit/ledger,
  tenant controls, Radar và các flow Admin/push/privacy
  được phép. Còn bộ render 27/27, 8/8 chức năng và role/load/rollback cùng build.
- Chủ tài khoản đã xác nhận nạp DeepSeek; probe AI thật vẫn chờ duyệt cụ thể.
  Điều kiện nguồn/kinh doanh còn thiếu: calendar/social có
  quyền dùng và mẫu thật, quyền phân phối market data, chính sách Referral và
  consent/retention/sink của Data Lake. Owner đã giao chọn phương án kỹ thuật;
  không xin lại quyền triển khai đã có, không tự thanh toán hoặc ký hợp đồng.
- Chưa có ngày nghiệm thu 100% có thể cam kết. Việc code và kiểm thử vẫn tiếp
  tục được trên các phần độc lập; trạng thái unavailable không đóng các chức
  năng mà chủ dự án yêu cầu phải hoạt động đầy đủ.
- Ước lượng sơ bộ cho lập kế hoạch: 10–15 ngày làm việc cho code/kiểm thử còn
  lại sau khi đủ nguồn và quyết định, với phạm vi hiện tại. Chưa phải deadline
  đã cam kết; thời gian chờ nhà cung cấp/giấy phép/nạp số dư không được xác định.

## Community W24 — v1 và sửa khôi phục đã phát hành 03/10

- Đã nối post/comment/like/share qua backend/token và Firestore thật trên
  Emulator. Post/comment retry dùng cùng requestId, comment counter cùng
  transaction; 20 concurrent deliveries chỉ tạo một record. Rules chặn client
  tạo/update post hoặc comment, owner vẫn có quyền xóa post; parent bị xóa thì
  comment không còn được đọc công khai.
- UI có danh sách 100 comment gần nhất, loading/error/retry, giữ draft khi lỗi,
  khóa send khi pending, bỏ callback cũ sau close/reload. Share link không chứa
  UID/token/PII; lookup theo document và mở đúng bài sau đăng nhập mới. Browser
  local đã ghi một post/comment, count like/comment 1/1; like retry giữ 1.
- Source `f11707a` đã lên main/FE/BE/Rules; live container
  `protrading-ai-community-live-f11707a`, rollback giữ bản Backtest `0de11ce`.
  Bundle Web public khớp SHA local; health đạt, API anonymous trả 401. SDK
  read-only xác nhận collection Community và leaderboard đều 0 document;
  browser QA Standard sau reload hiển thị đúng feed trống, không có ranking giả.
- Source FE/Rules follow-up `43fd970` đã lên main và Firebase production;
  public bundle SHA `895669ed8c3eed6669a2f837d12fba14e05d988844b2a363e9a1760dd3afbfe2`
  khớp bản build đã kiểm thử. BE vẫn `f11707a` vì slice này không đổi backend.
  QA giữ phiên đăng nhập sau reload và đọc đúng Community empty state.
- Bản follow-up cho phép owner đọc đúng marker like (không list/write hoặc
  cross-user), tự khôi phục trạng thái đã thích, có retry khi đọc lỗi và bỏ
  callback cũ. Browser đăng nhập mới tự hiện “Đã thích · 1”, không gọi like lại.
- Phát hiện và sửa form đăng nhập Web bị dispose khi auth đang pending;
  giữ draft/controller, hiển thị lỗi đăng nhập được localize. Test Chrome thật
  tái hiện trước sửa và đạt sau sửa; boot loading và Mobile giữ behavior cũ.
- Python Emulator **280/280**, Flutter VM **162 đạt + 1 Web-only skip**,
  test Chrome **1/1**, analyzer 0 error/0 warning và 3 info Mobile cũ.
  Bằng chứng: `web-community-qa-2026-10-03.json` và các ảnh local/production.
- Chưa đăng nội dung QA cho khách hàng trên Community production; W24 còn
  thiếu write-flow production, W25 verified-trade/leaderboard vẫn chưa nghiệm thu.
  Không gọi DeepSeek ở slice này. Probe Analysis/Chat production vẫn chờ câu
  xác nhận cụ thể do cơ chế duyệt tự động yêu cầu.

## Referral W26 — cấp mã và PNG đã qua local, chưa release

- API `/api/referral/identity` lấy UID từ token, cấp code 18 byte ngẫu nhiên,
  registry private và owner document commit cùng transaction. 20 request đồng
  thời giữ một code; retry không đổi code; giữ mọi field cũ không liên quan.
  Không sinh totalEarnings/F1/F2 hoặc tự gán ledger verified.
- Stats phân biệt identity có thật với tiền/count được xác minh. Chỉ ledger
  `VERIFIED` + currency/number hợp lệ mới hiện tiền; thiếu nguồn vẫn hiện “—”.
  BLoC bỏ callback/stream cũ sau reload/close, có retry lỗi API và token/UID guard.
- QR 600×600 và banner gốc 1200×630 tải được từ Web thật. zxing-cpp giải mã
  độc lập cả hai khớp link server; Clipboard cũng khớp. Dependency chọn theo
  quyền delegated: qr_flutter 4.1.0 (BSD-3), qr 3.0.2 transitive; decoder QA chỉ
  ở /tmp, không thêm backend dependency. Mobile giữ biên import bằng stub.
- Emulator 285/285, Flutter full 170 đạt + 1 Web-only skip, gồm 2 widget test
  viewport 390px/copy/ledger unavailable/retry. Analyzer không có
  error/warning, 3 Mobile info cũ; local release build đạt.
- Bằng chứng: `web-referral-qa-2026-10-03.json` và các PNG local đi kèm.
  Chưa deploy slice này. Chưa nối registration attribution từ `ref`, chưa có
  video và W27 ledger/withdrawal. W26/W27 tiếp tục mở; không coi link đã encode
  đúng là toàn bộ chương trình giới thiệu đã hoàn tất.

## Referral registration — tiếp nối ngày 04/10

- Link `?ref=` chỉ nhận một code hợp lệ. Auth BLoC gọi API token sau đăng nhập,
  chống request trùng, giữ phiên/trạng thái trang khi lỗi, có retry và loại kết
  quả khác UID. Event Auth lặp cùng UID giữ pending và kết quả đúng; main shell
  dùng Scaffold key ổn định và dispose dữ liệu trang khi UID đổi.
- Backend chỉ nhận code, identity từ token. User phải hoạt động, tạo sau người
  giới thiệu và trong 24 giờ. Ghi một attribution bất biến dưới own `meta` và
  tăng registeredInviteCount cùng transaction; không đổi role hoặc tạo tiền.
- Browser tạo account mới trên Emulator từ link thật, SDK đối chiếu attribution
  chỉ có code/timestamp và inviter count 1. Hub hiện phản hồi thành công, identity
  riêng cho account mới, đổi sang inviter hiện count 1 và chặn tự giới thiệu.
- Concurrency phát hiện SDK transaction wrapper có trạng thái và read-phase
  contention không được tự retry. Mỗi execution nay có wrapper riêng và tối đa
  ba lần thử với backoff hữu hạn. Referral/Community giữ nguyên transaction,
  20 request/sáu worker và assertions; full Emulator **293/293** đạt.
- Flutter **181 đạt + 1 Web-only skip**, Chrome **1/1**, analyzer không error hoặc
  warning, ba info Mobile cũ. Source cấp mã/PNG trước là `f65e1d2`; cả hai slice
  đang chuẩn bị release. Bằng chứng: `web-referral-registration-qa-2026-10-04.json`.
- W26 còn video cá nhân hóa gốc và production readback; W27 receipts/ledger/
  withdrawal còn mở. Phần này không gọi DeepSeek; không chạy probe AI bị chặn.

### Release và readback Referral — 04/10

- Main, FE và BE đã nhận source `7ef3ab6`. Live container
  `protrading-ai-referral-live-7ef3ab6`, image ID
  `b2a9518698b73579018e65504c65b17d52a8130a614c41b816c71bc36f86ba94`;
  giữ `protrading-ai-community-live-f11707a` để rollback. Candidate 8022 đã
  dừng sau readback; không đổi Rules/index (source Rules vẫn `43fd970`).
- Image chạy network none: 260 đạt + 33 skip cần Emulator/nguồn ngoài, tổng
  293. Các ca Emulator đã có bằng chứng local đầy đủ 293/293. Public health
  ok/Redis, hai API Referral anonymous trả 401. FE public SHA khớp build:
  `4db48be3be3a0f4fdfa1b83fcdb3e4e1bf50fbf3cea56252bb8c535b85d8a964`.
- Browser production giữ phiên QA, Hub VI hiện code/link riêng thật, count
  đăng ký 0 và tiền chưa xác minh “—”. Clipboard đúng, QR/banner tải thực tế
  giải mã độc lập khớp link server. SDK read-only xác nhận registry đúng owner,
  QA vẫn Standard, không tạo financial fields. Không gọi DeepSeek ở probe.
- W26 còn video và positive new-account registration production. Không tạo
  thêm QA production hoặc vượt qua bước auto-review đang chờ phê duyệt.
  Bằng chứng: `web-production-referral-qa-2026-10-04.json` và ba PNG production.
- Python 3.10.18 trong image báo kết thúc hỗ trợ ở các bản Google SDK mới từ
  hôm nay 04/10. Lát tiếp theo nâng runtime được hỗ trợ, giữ nguyên các version
  dependency production đang dùng và kiểm tra candidate trước cutover.

## Video Referral và runtime — cập nhật 04/10

- FE source `a54d67d` đã lên GitHub main và Firebase Hosting. Public bundle
  SHA `3a82f7d45ff1ef43c7c7214b95cf7b78677b45fce5f3c133db4b9735fc217d8f`
  khớp build production. BE vẫn source `7ef3ab6`, Rules vẫn `43fd970`.
- QA Standard tải video gốc thật: H.264/MP4, 1200×630, 5.964 giây,
  99,573 bytes, không audio. QR đầu/giữa/cuối đều khớp link server; ba nút
  asset khóa khi export và mở lại sau thành công. Bằng chứng JSON/PNG:
  `web-production-referral-video-qa-2026-10-04.json` và
  `web-production-referral-video-2026-10-04.png`.
- Flutter 184 đạt + 2 skip chỉ dành cho Web, Chrome video 4/4; analyzer không
  error/warning, còn 3 info Mobile có sẵn. Không gọi DeepSeek ở lượt kiểm tra.
- Nâng Python 3.12 gặp lỗi tạo thread với default seccomp trên VPS Ubuntu
  16.04/kernel 4.4/Docker 18.09. Không dùng unconfined cho release hoặc live.
  Dockerfile `433a165` đã pin digest Python 3.10.18/Bullseye và constraints
  76 dependency đúng runtime hiện tại; cold candidate pip check/thread đạt,
  Python network-none 260 đạt + 33 skip. Không cutover BE vì app không đổi.
  Nâng host/runtime có hỗ trợ vẫn là gate W35; xem
  `python-runtime-upgrade-2026-10-04.md`.
- W26 còn positive new-account registration production; W27 tiền thưởng/rút
  tiền và các gate provider/role/SLA khác vẫn mở. Toàn kế hoạch chưa 100%.

## Tiếp tục

### Journal controls và DeepSeek — cập nhật 04/10

- FE `3eea7de` đã lên main/Firebase; public bundle SHA
  `8b5d0f090a16d65d5c4ed1fe6f386633742dbef546f713cc00df67c54b71133d`
  khớp build, không lẫn QA URL. CSV/filter dùng danh sách owner đang đọc,
  giữ gate broker. Local browser/decoder qua subset 1/3 và reset 3/3, không
  giả phí và giữ precision/UTC; production QA vẫn JOURNAL LOCKED, mode của
  bản ghi cũ Unverified. Chưa có positive download production.
- Full Flutter 195 đạt + 2 skip Web, target cuối 11/11; analyzer 0 error /
  warning, 3 info Mobile cũ. Xem `journal-controls-spec-2026-10-04.md`.
- Hai GET chỉ đọc DeepSeek `/user/balance` và `/models` từ live container
  cùng trả 401. Key đang có không khớp mask screenshot; không in key/số dư,
  không gọi model, tạo QA hoặc sửa env. Đã hỏi nơi lưu key hợp lệ; chờ trả
  lời và phê duyệt paid probe riêng. Tài khoản nạp tiền chưa được xác minh
  qua key đúng. Xem `deepseek-readonly-auth-check-2026-10-04.json`.
- Web heatmap bỏ weekday 6/7 và dùng giờ local trong khi insight dùng UTC;
  bảng giá làm tròn hai chữ số và equity một điểm có phép chia cho zero.
  Các lỗi này đã sửa trong FE `7c9e938` bên dưới; chưa đủ nghiệm thu W19/W34.

### Journal visual — release 04/10

- FE `7c9e938` đã lên main/Firebase. Public bundle 3,785,939 bytes, SHA
  `bf82ac4bd22e0a92224ac53c1b62f8b20d53435749c3012114fab2337338606c`
  khớp local production build. BE `7ef3ab6`, Rules `43fd970` giữ nguyên.
- Giá entry/exit giữ precision, heatmap có bảy ngày theo UTC với count là lệnh;
  single/flat P&L curve có hình học hữu hạn và nhãn đúng cumulative closed P&L.
  Full Flutter 203 đạt + 2 skip Web-only; target 20/20; analyzer không error/
  warning, 3 info Mobile cũ. Native Emulator VI/EN xác nhận Sunday bucket và
  giá forex đầy đủ; không gọi AI.
- Production QA Standard vẫn broker gate; rendered tree xác nhận source UI
  mới nhưng còn descendant semantics của preview bị blur. Chưa thử keyboard
  gate; sẽ có test riêng. Không bypass để export hoặc playback production.
  Xem `journal-visual-correctness-spec-2026-10-04.md` và
  `web-production-journal-visual-qa-2026-10-04.json`.
- Toàn kế hoạch vẫn 7 mục đóng / 29 mục mở. W18/W19 còn broker sample và
  positive entitled runtime; DeepSeek live vẫn 401 và chờ nơi lưu key hợp lệ.

### Journal gate — release 04/10

- `bfc93b0` đã lên main/Firebase; bundle public 3,786,221 bytes SHA
  `de9d6e7f286a327242b151df7b15c473c3bb5e50069dcb09a561ba69445aefd1`
  khớp local. Gate chặn pointer/focus/semantics, UID trống khóa, owner đổi
  reset snapshot; dùng EN/VI hiện có. Bốn reproducing tests đỏ trước sửa,
  sau sửa 6/6; full Flutter 209 đạt + 2 skip, analyzer chỉ 3 info Mobile cũ.
- Native Emulator chuyển fixture true→false→true: relock loại preview khỏi AX,
  Enter nút kết nối mở Profile, restore mở lại controls. Production Standard
  EN/VI chỉ còn gate/action trong AX. Không sửa claim/quota/broker flag thật,
  không gọi AI. Xem `journal-gate-accessibility-spec-2026-10-04.md`.
- W18/W19 vẫn mở. Rà tiếp math/P&L: source trước sửa đang đổi Profit Factor
  all-wins từ infinity thành zero và tính break-even vào mẫu số average loss;
  không được suy ra risk adherence/discipline từ best/worst P&L.

### Journal performance — local verification 04/10

- Đã sửa all-wins PF, break-even average loss, parser đoán ngày/profit,
  stats/table từ hai snapshot, và score discipline/risk suy đoán. BLoC dùng
  một owner snapshot/generation, Web chỉ có measured metrics/summary EN/VI.
  Không sửa Firestore schema/query/Rules hoặc API; legacy schema vẫn đọc.
- Audio dùng LocaleCubit và generation; VI không còn dùng en-US, callback
  cũ/end đồng bộ/start fail không làm sai trạng thái. Full Flutter 237 đạt
  + 2 skip Web-only, target cuối 37/37; analyzer 0 error/warning, 3 info cũ.
- Native Emulator 8801 xác nhận 3 lệnh/P&L -7.91, PF/payoff 0.61, counts
  1/1/1 và âm tính CN 06 UTC -20.25. Nút audio Phát→Dừng→Phát; chưa nghe
  voice/device hoặc playback production. Bundle QA khớp served source.
  Xem `journal-performance-correctness-spec-2026-10-04.md` và JSON/PNG local.
- Auto-review từ chối đối chiếu `DEEPSEEK_API_KEY` từ Docker inspect trên
  các container trước khi thực thi vì chưa có phê duyệt riêng cho việc đọc
  credential. Đã hỏi quyền đọc đúng biến/chỉ output boolean/0 phí, hoặc nơi
  lưu an toàn. Không thử qua đường khác. Paid/production-QA probe vẫn chờ
  duyệt trước đó; BE live auth 401 là bằng chứng cuối cùng đã được phép đọc.

### Journal performance — production release 04/10

- `c63467e` đã lên main/Firebase; public bundle 3,788,516 bytes SHA
  `85dfd088431e12d63fc0f391286484b59b5a919841d0277849179b63455bb278`
  khớp local production build, không lẫn QA/Emulator. BE `7ef3ab6`, Rules
  `43fd970` không đổi. QA Standard reload/EN/VI gate đạt; không bypass để
  export/audio. Không gọi AI hoặc ghi auth/quota/broker flag.
- W18/W19 còn sample broker/currency/initial risk và playback/CSV production
  đúng quyền. Tổng kế hoạch vẫn 7 đóng/29 mở; không quy số test thành % hoàn
  thành. Xem `web-production-journal-performance-2026-10-04.json`.

### Radar Web — production release 04/10

- FE `1487cd8` đã lên main/Firebase, public bundle 3,792,258 bytes SHA
  `1122bd039e1a65e971affd4f31d835a516ce84a62567c683047e32d74b2e5d0c`
  khớp local production build. BE `7ef3ab6`/Rules `43fd970` không đổi.
- Bỏ strength 4/5 cố định, nhãn realtime/today/USD thiếu chứng cứ; giá giữ
  precision và snapshot/freshness unverified rõ ràng, EN/VI/narrow/retry.
  Selected detail lấy snapshot mới, clear/removal/reload/error/close an toàn.
- Route target tạm thời truyền symbol/frame qua shell→TradingRoom; target
  thắng saved symbol, repo interval/state/mode đúng matrix; ordinary entry
  vẫn restore saved symbol. Target 14/14, full Flutter 247 + 2 Web-only skip,
  analyzer 0 error/warning và 3 info Mobile cũ. Không thêm dependency.
- Native Emulator đóng detail/update giá giữ closed, chọn lại ETHUSD/H4 mở
  Day Trading. Native production EN/VI, ETHUSD từ Radar mở ETHUSD/M5 có nến/
  giá thật (2686.47 tại capture), khác saved BTCUSD. Không yêu cầu AI/chat/
  trade; VETO có sẵn không phải AI-success proof mới. Journal gate vẫn khóa.
  Xem `radar-web-correctness-spec-2026-10-04.md` và JSON/PNG local/production.
- Read-only smoke trước release còn cho thấy News 13 Fed releases/sentiment
  unavailable, Backtest config hiện đúng, Community feed/leaderboard trống,
  Referral kit/các financial empty-state có thật và Profile MFA disabled có
  lý do. Đây là navigation/render smoke, không phải write/role/provider E2E.
  Community counter đã sửa EN/VI trong FE `e43f7f5`; native production bản
  nháp 0 → 16 → 0 đúng semantics và không đăng bài. W34 chưa đóng; xem
  `web-production-community-counter-2026-10-04.json` và checkpoint 04/10.
- Tổng 36 hàng nghiệm thu: 7 đóng/29 mở. Các gate AI key 401, đọc credential
  và paid/new-QA probe chờ duyệt, broker/license/provider/role/worker/FCM,
  ledger/payment và supported-host/SLA/rollback vẫn cản nghiệm thu 100%.

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
