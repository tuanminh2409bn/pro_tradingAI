# Kế hoạch hoàn thiện Web ProTrading AI V2.1

Ngày lập: 2026-09-17. Đây là nhánh triển khai **chỉ cho Web** của `tasks/plan.md` và `tasks/todo.md`; mã `Txx` bên dưới trỏ về đầu việc gốc. Không thay trạng thái của checklist tổng khi chưa có bằng chứng mới.

## 1. Đích đến và phạm vi

- Hoàn thiện các trang đăng nhập, Trading Room, Journal, News, Backtest, Community, Radar, Referral, Profile và Admin đang được mở từ `WebDashboardShell`, cùng FastAPI, Firestore, Redis và nhà cung cấp dữ liệu cần thiết cho các luồng đó.
- Chỉ nghiệm thu trên trình duyệt Web. Không làm giao diện, build, ký phát hành, thông báo, rung hoặc mua hàng trên Android/iOS. Các chỉnh sửa ở model/repository/backend dùng chung chỉ được thực hiện khi cần cho Web và phải giữ khả năng biên dịch hiện có.
- `/api/trade` tiếp tục là **paper trading**. Live MetaApi là một sản phẩm/phạm vi riêng, chỉ triển khai sau quyết định G4 và phê duyệt riêng.
- Một mục đạt khi hành vi hoạt động từ dữ liệu thật hoặc trạng thái không khả dụng được ghi nhãn, có test tự động phù hợp và bằng chứng trình duyệt đăng nhập trên cùng mã nguồn/bản build. Fixture chỉ chứng minh logic, không thay thế nghiệm thu runtime.

**Điều kiện hoàn tất Web:** 15 mục Master có phần Web (M-01..M-15), 27/27 mục render R-01..R-27, 8/8 chức năng F-01..F-08, các hàng Web của Tabs 2–7 và Admin/operations trong `tasks/acceptance-matrix.md` đều PASS; token/Rules/API không cho vượt quyền; test Python/Flutter, analyzer không có error/warning, Web release build và staging smoke đạt. M-16 chỉ cần xác nhận đường dẫn Web/API relay liên quan tới Web; phần form Mobile nằm ngoài phạm vi. Không đánh dấu PASS nếu thiếu bằng chứng cùng build.

## 2. Mốc xuất phát

Rà soát điều kiện nghiệm thu hiện tại ngày 2026-10-03:
[Web production readiness](checkpoint-2026-10-03-web-production-readiness.md).
Tài khoản QA và vị trí lưu credential an toàn: [QA access](qa-access.md).

Cập nhật triển khai và nghiệm thu runtime 2026-10-03:
[Analysis/quota, Backtest, Profile, News và cache release](checkpoint-2026-10-03-web-runtime.md).
BE/FE đã phát hành cùng phần source kiểm thử; Backtest BUY/SELL/close, risk lock,
refresh/ack và số dư đã đối soát trên production. Standard Analysis 2/2 và reset
UTC đã được kiểm tra. Các hàng còn thiếu nguồn/chính sách/bằng chứng vẫn mở.
News có thêm 13 bản tin Fed thật và chat được bảo vệ khỏi request trùng/late
response, với [bằng chứng production](web-production-news-qa-2026-10-03.json).
Nguồn social/calendar và AI có số dư vẫn chưa đủ để đóng W20/W21.

- Checklist tổng ghi 4/50 việc hoàn tất (T13, T14, T18, T20), 41 việc dở, 5 chưa bắt đầu; số này không phải số riêng của Web.
- Baseline mới nhất ngày 2026-09-17: Python discovery 178 test, 166 đạt và 12 ca Emulator được skip khi không có tiến trình local; Firestore Emulator chạy đủ 12 ca Rules, trong đó 3 ca nền đạt và 9 ca bảo mật/chức năng đang đỏ; Flutter 103/103 đạt; `git diff --check` đạt. `flutter analyze --no-fatal-infos --no-fatal-warnings` không có error/warning và còn 5 `info` API cũ (2 Web, 3 Mobile). `flutter build web --release` đạt trên source hiện tại; manifest SHA-256 `04a1c8cbe14b8338c97be3ebab1d4c28c75b85e35571335ee2ba935f9b50719e`, dung lượng 41 MB.
- T27 đã có kiểm tra tín hiệu, token và idempotency cho paper trade trên local. Backend hiện lấy nến phân tích từ nguồn server, kiểm tra lại daily-loss trước paper execution và các API riêng tư chính yêu cầu Firebase ID token; latch/review bền vững vẫn chờ cổng G1.
- Bản release local đã có bằng chứng trình duyệt đăng nhập cho Trading Room, Journal, News, Backtest, Community, Radar, Referral và Profile ở desktop; menu responsive và nhãn trợ năng của Community, Radar, Backtest được kiểm tra thêm ở chiều rộng 600 px. Admin chưa thể nghiệm thu runtime vì tài khoản QA không có custom claim `admin=true`.
- Cập nhật local 2026-09-24: G1 đã được duyệt cho Rules/index trên máy. Firestore Emulator đạt 15/15 ca, gồm query signals và quyền referral/broadcast; ba composite index cho Backtest, trade history và pending requests đã được khai báo. Chưa audit document cũ, chưa kiểm tra browser trên source mới và chưa deploy.
- Cập nhật local 2026-09-25: xem `tasks/checkpoint-2026-09-25-web-local.md`. Firestore Emulator đạt 21/21 ca; Python 212 ca (21 skip ngoài Emulator), Flutter 117/117, Web release build đạt. Browser mới chỉ kiểm tra login chưa đăng nhập; mọi hàng cần provider hoặc luồng đăng nhập vẫn chưa PASS.
- Cập nhật production 2026-10-03: backend TradingView đã triển khai; 21 mã Web có nến được chấp nhận, 10/10 request QA hoàn tất, browser đăng nhập chạy XAUUSD (đóng cửa) và BTCUSD (phân tích/VETO). Đối chiếu 60 nến crypto với Bitstamp trùng OHLCV trong mẫu; Python 239 ca, 216 đạt/23 skip cần Emulator. Xem [checkpoint nguồn nến production](checkpoint-2026-10-03-tradingview-production.md). W09/W11/W12 vẫn cần hoàn tất các hàng nghiệm thu còn lại, quyền nguồn thương mại, phiên forex mở cửa và bằng chứng ba chuyên gia; không suy ra toàn bộ Web hoàn thành.

## 3. Quy tắc thực hiện

1. Mỗi `Wxx` là một lát nhỏ, làm xong và kiểm tra được trong một phiên tập trung. Nếu phải sửa hơn khoảng năm file hoặc hơn một luồng độc lập, chia tiếp trước khi code.
2. Giữ Repository → BLoC → Widget và FastAPI hiện có. Trước khi sửa hành vi, tìm test gần nhất và thêm ca tái hiện khi thực tế.
3. Ghi bằng chứng bằng mã nguồn/build, môi trường, tài khoản thử nghiệm ẩn danh, lệnh test, kịch bản trình duyệt, người rà soát và rủi ro còn lại vào `tasks/acceptance-matrix.md` hoặc bản ghi kèm theo.
4. Không dùng dữ liệu giả trong luồng sản phẩm. Khi nguồn, quyền hoặc bằng chứng không đủ, hiển thị trạng thái không khả dụng và khóa hành động rủi ro.
5. Không gộp thay đổi Rules/schema/API public, dependency, credentials hay deploy vào một task Web thông thường: phải đi qua cổng G tương ứng ở mục 5.

## 4. Danh sách triển khai theo thứ tự

`S` = một ranh giới nhỏ; `M` = một lát repository/backend → state → Web UI tối đa khoảng năm file. Mỗi dòng là một đầu việc chưa được xác nhận hoàn tất cho Web; có thể bỏ qua phần đã có sau khi kiểm tra lại bằng chứng hiện tại.

### P0 — Chốt hợp đồng và bộ kiểm tra (T01–T03, T49)

| Việc | Kết quả cần đạt | Kiểm tra để đóng việc | Phụ thuộc |
|---|---|---|---|
| [x] W01 · Ma trận Web (S) | Mỗi yêu cầu Web trong hai tài liệu gốc có ID, trạng thái, test và kịch bản browser; tách nghĩa vụ Mobile ra khỏi mục Web. | `test_v21_web_traceability.py` xác nhận mọi ID trong hợp đồng tổng hợp có automated target, browser target và trạng thái; bảng Web-only tách nghĩa vụ Mobile. Stakeholder sign-off thuộc T01 gốc. | Không |
| [x] W02 · Baseline tái lập (S) | Chốt lệnh test, phiên bản Flutter/Python, cách chạy Firestore Emulator và Web build; xác nhận test bị xóa trước đây đã được thay thế theo ý định. | Python discovery, `flutter test`, `flutter analyze`, `flutter build web --release`; ghi skip/info và mã source. | W01 |
| [x] W03 · Quyết định Web (S) | Có chủ sở hữu và quyết định local cho Rules/schema, role thứ năm, paper/live, nguồn nến/news/DeepSeek/TTS, QR, push, quota, quyền riêng tư và staging. | G1–G7 cùng trạng thái external gate ở `tasks/decisions-v2.1.md` và `tasks/provider-matrix.md`; tài khoản/giấy phép chưa có không được tính là provider runtime PASS. T03 tổng vẫn dở. | W01 |

**Checkpoint P0:** phạm vi Web và bằng chứng nền được nhận diện; không dùng một build cũ để tuyên bố source mới đạt.

### P1 — Danh tính và ranh giới dữ liệu (T04–T08, T07)

| Việc | Kết quả cần đạt | Kiểm tra để đóng việc | Phụ thuộc |
|---|---|---|---|
| [x] W04 · Token cho API riêng tư (M) | Chat, broker, quota, Admin và các route còn lại lấy UID/claim từ Firebase token, từ chối thiếu/hết hạn/sai UID. Giữ trade/close/list/risk đã có. | API tests hợp lệ, hết hạn, giả UID, gọi trực tiếp bỏ qua Web; `python3 -m py_compile server.py`. | W02 |
| [x] W05 · Rules và query theo chủ sở hữu (M) | Signals, chat, backtest, referral, community, FCM token, cutoff và Admin data chỉ cho đúng chủ thể/quyền; index khớp query. | Firestore Emulator positive/negative theo từng collection và cross-user; đối chiếu index. Local 21/21 ngày 2026-09-25, gồm giao dịch like thật; runtime/staging thuộc W06/W35. | W04, G1 |
| [ ] W06 · Quyền Web/Admin ba lớp (M) | UI ẩn/khóa đúng vai trò, Rules chặn truy cập, backend chặn mutation trực tiếp; role chưa được định nghĩa phải fail closed. | Widget role matrix + Emulator + API bypass tests cho Standard/Partner/Professional/Enterprise/Admin. | W04–W05, G3 nếu thêm role |
| [ ] W07 · Biên API an toàn (M) | Hoàn thiện validation, giới hạn đầu vào, CORS/proxy allowlist, lỗi an toàn và idempotency cho các mutation Web ngoài trade. | API adversarial/retry tests, scan log không lộ token/secret, kiểm tra proxy URL/size. | W04 |

**Checkpoint P1:** cổng A đạt trên local/emulator; chưa chuyển sang dữ liệu người dùng thật nếu một đường API/Rules còn vượt quyền.

Cập nhật W06 local 2026-09-25: Auth/Firestore Emulator đã kiểm tra token thật cho Standard, Partner, Professional, Enterprise, `reserved_fifth`, vai trò lạ/thiếu và Admin; widget gate và browser QA cho Standard/Admin/`reserved_fifth` đạt. Xem `checkpoint-2026-09-25-web-w06-qa.md`. W06 vẫn mở cho audit claim Admin hiện có và nghiệm thu cùng build staging; Admin HTTP mutation tương lai thuộc W30 phải có kiểm tra vượt quyền riêng.

Cập nhật W07 local 2026-09-25: URL có cổng sai/ngoài dải bị từ chối trước DNS; image proxy mặc định từ chối mọi host cho đến khi `IMAGE_PROXY_ALLOWED_HOSTS` được cấu hình bằng hostname chính xác của nguồn ảnh được duyệt. Ca CORS/proxy adversarial đạt. W07 vẫn mở cho kiểm tra idempotency các mutation ngoài trade, giới hạn đầu vào và API runtime trên cùng build.

Cập nhật QA full-stack local 2026-09-25: Web + FastAPI + Auth/Firestore Emulator đã chạy cùng nhau; Community post/like và Analyze thiếu nguồn được kiểm tra qua browser. Python 216/216 và Flutter 120/120 đạt, Web release build đạt. Xem `checkpoint-2026-09-25-web-fullstack-qa.md`. Không chuyển các mục W09–W35 sang PASS chỉ nhờ trạng thái empty/unavailable này.

### P2 — Dữ liệu thị trường và AI có nguồn gốc (T09–T19)

| Việc | Kết quả cần đạt | Kiểm tra để đóng việc | Phụ thuộc |
|---|---|---|---|
| [x] W08 · Phiên WebSocket độc lập (M) | Hai phiên khác symbol/timeframe không dùng chung state; P&L luôn lấy mark đúng symbol; ngắt kết nối giải phóng tài nguyên. | Hai-client async test, symbol-flip P&L, lifecycle test. | W02 |
| [ ] W09 · Volume và lịch sử MTF (M) | Server lấy candle `t,o,h,l,c,v` đã đóng, đủ 120/120/150 theo ba mode, căn mốc H1/H4/D1; thiếu/gap thì báo unavailable. | Fixture chín cặp mode/timeframe, gap/weekend/DST, đối chiếu mẫu với nguồn được duyệt. | W08, G5 cho provider |
| [x] W10 · Cache trung lập người dùng (M) | Cache chỉ chứa phân tích thị trường theo key hiện hành; sizing/risk áp sau cache, không lẫn tài khoản; Redis lỗi vẫn deterministic. | 8/8 test cache key/TTL/hit/single-flight, hai ngữ cảnh UID/risk, loại sizing và Redis outage đạt; pipeline chỉ gắn `userId` sau cache. | W09 |
| [ ] W11 · Macro và ba chuyên gia (M) | News có provenance/freshness; mỗi cache miss hợp lệ tạo đúng ba kết quả chuyên gia độc lập từ feature summary, timeout/402/429 fail closed. | Provider adapter sandbox + call-count/prompt/schema/failure tests; không có raw candle/PII trong prompt. | W09–W10, G5 |
| [ ] W12 · Consensus và phát hành tín hiệu (M) | Vote, xác nhận nến, HTF Veto và Layer 1–5 qua schema v2.1; lưu bản ghi audit; không có Layer 4 khi Soft/Veto. | Python golden/parity + Dart fixture tests; kiểm tra payload lưu thật và một chu kỳ analysis đăng nhập. | W11, W04–W05, G1 |

**Checkpoint P2:** cổng B/C đạt; một tín hiệu có thể truy về nến/news nguồn và ba chuyên gia + một aggregator, không dựa vào candle do client tự khai.

### P3 — Trading Room Web hoàn chỉnh (T21–T30)

| Việc | Kết quả cần đạt | Kiểm tra để đóng việc | Phụ thuộc |
|---|---|---|---|
| [ ] W13 · Biểu đồ 27 thành phần (M) | Kiểm tra lại màu, hình học, tương tác Ghost/HTF, X/Y zoom và Forecast trên browser; bổ sung pixel/golden còn thiếu. Chia theo từng Layer khi sửa renderer. | Test painter/gesture hiện có + browser mouse/touchpad, text scale và screenshot từng R-01..R-27. | W12 |
| [ ] W13a · Luồng đầu vào Trading Room (M) | Sync Gate lần đầu, metadata tài khoản có nguồn, ma trận timeframe và Soft Forecast hoạt động trên Web; trạng thái broker thiếu nguồn được ghi nhãn. | Widget tests F-02/F-03/F-05/F-06 + browser first-run, đổi mode/symbol và tài khoản chưa liên kết. | W04, W09, W12 |
| [ ] W14 · Gate giao dịch tại server (M) | Backend tự xác minh tín hiệu, giá/lot/TP, nguồn market đáng tin cậy, daily-loss cutoff và idempotency; refresh/retry không tạo lệnh giấy thứ hai. | API bypass/cross-user/retry tests + Firestore transaction/emulator + Web Hard/Soft/Veto flow. | W04–W05, W09, W12 |
| [ ] W15 · Review và mở khóa cutoff (M) | Cutoff sống qua refresh/thiết bị theo session policy được chốt; cả Analyze và Trade bị khóa; review và acknowledgement được ghi trước khi mở. | Test mốc ngày/timezone, API bypass, review/ack, mất LLM; browser refresh. | W14, G1, quyết định session boundary |
| [ ] W16 · Cảnh báo hai mức trên Web (M) | Soft/Hard không gửi trùng, tôn trọng opt-out, xin quyền trình duyệt đúng lúc và mở đúng tín hiệu khi bấm thông báo. | Fake-clock state tests, FCM sandbox Web foreground/background, deep-link/sound capture. | W12, W05, G2/G5 |
| [ ] W17 · Nghiệm thu Tab 1 Web (S) | 27/27 render và F-01..F-08 có bằng chứng cùng Web build/tài khoản được phân quyền; không còn khẳng định dựa riêng vào fixture. | Ma trận acceptance ký ngày, browser capture cho symbol/mode/gate/paper trade/cutoff. | W06, W13–W16, W13a |

**Checkpoint P3:** cổng D đạt trên Web; Soft/Veto/cutoff không thể tạo paper trade qua UI **hoặc gọi API trực tiếp**.

### P4 — Journal và News Web (T31–T35)

| Việc | Kết quả cần đạt | Kiểm tra để đóng việc | Phụ thuộc |
|---|---|---|---|
| [ ] W18 · Journal số liệu broker (M) | Swap/commission/slippage có nguồn và tiền tệ; paper/broker được phân biệt; thiếu dữ liệu hiển thị unavailable. | Model/repository tests với hai schema trade + mẫu broker sandbox được duyệt + browser review. | W04–W05, G5 |
| [ ] W19 · Insight và TTS Web (M) | Heatmap/insight dựa trên trade thật; nút TTS phát/dừng audio thật hoặc trạng thái tắt rõ ràng khi chưa có provider. | Test tính toán, audio lifecycle và browser playback; kiểm tra mất provider. | W18, G2/G5 cho TTS |
| [ ] W20 · News và sentiment có giấy phép (M) | Chỉ nhận nguồn được duyệt, lưu provenance/freshness; nguồn hỏng/không được duyệt fail closed. | Parser/score/dedupe tests + provider sandbox sample + browser empty/error state. | W04–W05, G5 |
| [ ] W21 · What-If và Red Zone liên tab (M) | Scenario không chứa trường đặt lệnh; lưu theo UID; cùng event ID/thời điểm đi từ News sang overlay Trading Room, hết hạn thì xóa. | Python/Dart contract, auth isolation, injected-clock test và browser cross-tab flow. | W20, W12, G1 |

**Checkpoint P4:** cổng E đạt trên Web với mẫu broker/news được phép; không hiển thị số liệu hoặc nguồn giả.

### P5 — Backtest, Community, Referral Web (T36–T41)

Cập nhật production 2026-10-03: quota tạo phiên Backtest qua token API đã
triển khai FE/BE/Rules, session và counter được cấp trong cùng transaction;
Standard 2/tuần, Professional 50/ngày, Enterprise 300/ngày, riêng với Analysis.
Browser QA tạo hai phiên, lần thứ ba bị chặn và vẫn restore phiên cũ được;
Profile đúng 2/2, reset 05/10 07:00 VN. Emulator 272/272 và Flutter 151/151.
Xem `web-production-backtest-quota-2026-10-03.json`. W22/W23/W28 vẫn cần các
chốt quyền nguồn/role/nghiệm thu còn lại; không coi quota là toàn kế hoạch PASS.

| Việc | Kết quả cần đạt | Kiểm tra để đóng việc | Phụ thuộc |
|---|---|---|---|
| [ ] W22 · Replay Backtest trên Web (M) | Repo/BLoC/page dùng lịch sử được duyệt; nút play/pause/x1/x5/x10/cursor chạy thật, bỏ giá/ticker/số dư cố định. | No-future-data unit tests, widget controls, browser playback và parity mẫu lịch sử. | W09, G5 |
| [ ] W23 · Backtest risk và lưu phiên (M) | Entry/exit, P&L và max-loss lock chỉ tính đến cursor; phiên/review/ack khôi phục đúng sau refresh. | No-Repaint, BUY/SELL accounting, tamper/restore tests + browser refresh. | W22, W15, G1 |
| [ ] W24 · Community có danh tính (M) | Post/comment/like/share dùng UID thật, chống gửi lặp, kiểm tra ownership; nút rỗng được nối hoặc gỡ khỏi giao diện. **03/10:** đã nối backend/UID, comment transaction, share deep link; browser thật trên Emulator qua post/comment/like retry/share sau login. Release/readback production đang tiếp tục; xem `web-community-qa-2026-10-03.json`. | Repository/BLoC/widget tests + Rules owner/cross-user + browser flow. | W04–W05 |
| [ ] W25 · Chia sẻ riêng tư và leaderboard (M) | Payload chỉ chứa tỷ lệ tăng trưởng cho phép; xếp hạng từ dữ liệu đã xác minh server-side; dữ liệu cũ có phương án xử lý được duyệt. | Privacy/PII tests, Firestore tamper tests, browser ranking sample. | W24, W18, G1/G7 |
| [ ] W26 · Referral link/kit (M) | Link/QR và asset kit dùng code do server cấp, cá nhân hóa thật, tải được trên Web; không có demo/UID-derived code. | QR decode, asset render/download, cross-user/empty-state tests. | W04–W05, G2/G5 |
| [ ] W27 · Ledger và rút tiền (M) | F1/F2 có chính sách tỷ lệ/tiền tệ, ledger bất biến và xét duyệt Admin đúng quyền; không vượt số dư. | Arithmetic/transaction concurrency, Rules/API/Admin workflow và browser review. | W06, W26, G1 + chính sách hoa hồng |

**Checkpoint P5:** cổng F đạt trên Web; không còn nút giả, danh tính giả hoặc tiền giả trong ba tab.

### P6 — Profile, Admin, Radar và dữ liệu riêng tư (T42–T48)

| Việc | Kết quả cần đạt | Kiểm tra để đóng việc | Phụ thuộc |
|---|---|---|---|
| [ ] W28 · Quota/entitlement Web (M) | Profile chỉ hiển thị quota có `source=server_enforced`; backend atomically đếm/reset và chặn Analyze/Backtest khi hết quota. Không đưa AdMob/IAP Mobile vào Web. | 80-request concurrency, API bypass và browser role/quota states. | W04–W06, G1/G3 |
| [ ] W29 · Partner/Enterprise Web (M) | Chỉ Partner có capability được cấp; Enterprise quản lý đúng subaccount và tổng risk từ snapshot đáng tin cậy, không lộ credential. | Role/tenant/API bypass, aggregate-risk fixtures và browser role matrix. | W28, W14, G1/G3 |
| [ ] W30 · Admin controls có hiệu lực (M) | Prompt, kill switch, risk config và watchlist thay đổi từ Admin tác động backend không cần rebuild; close trade vẫn được phép khi kill switch chặn lệnh mới. | Claim/Rules/API bypass, cache 300 giây, kill-switch analysis/chat/trade, browser save/reload. | W06, W12, W14 |
| [ ] W31 · Radar 50–100 tài sản (M) | Worker quét watchlist thật, chỉ gọi model cho candidate có volume/barrier chứng minh được; kết quả có provenance và mở đúng chart Web. | 50/100 asset tests, 100 reject = 0 model call, Redis restart/concurrency, provider load + browser deep link. | W09–W12, W30, G5 |
| [ ] W32 · Push phân đoạn Web (M) | Admin lọc role/country/device và opt-out trên server, preview/audit không chứa token, FCM gửi và điều hướng Web đúng. | Segment/limit/auth tests, FCM sandbox Web và audit/token-retirement check. | W06, W16, W28, G5/G7 |
| [ ] W33 · DataMasker ranh giới Web (M) | Chỉ export bản ghi đã consent, HMAC pseudonym, retention/deletion đúng chính sách; không có UID/token/PII vào sink/log. | Allowlist/consent/deletion tests, real sink/log sample sau G7. | W04, G7 |

**Checkpoint P6:** cổng G đạt cho các luồng Web; Admin không chỉ là nút giao diện, mọi thay đổi có hiệu lực và bị kiểm soát quyền.

### P7 — Ổn định và nghiệm thu Web (T49–T50)

| Việc | Kết quả cần đạt | Kiểm tra để đóng việc | Phụ thuộc |
|---|---|---|---|
| [ ] W34 · Web quality pass (M) | Loading/offline/retry/error, keyboard, text scale, responsive, EN/VI và Web deprecation được xử lý theo phạm vi ảnh hưởng; async backend không chặn event loop. Chia kiểm tra theo từng trang/luồng để mỗi thay đổi vẫn nhỏ. | `flutter analyze` không error/warning, focused tests, browser 1280px + hẹp, accessibility/keyboard, async/load tests. | W17–W33 |
| [ ] W35 · Web staging/release (M) | Chốt source manifest, backend image, Web build, Rules/index version; chạy ma trận trên staging, đo tải, tập rollback và ký nghiệm thu. | Python/Flutter suites, `flutter build web --release`, browser smoke cùng build, security/load, rollback drill; deploy chỉ sau G6. | W01–W34, G6 |

**Checkpoint cuối:** mọi hàng Web cần thiết trong ma trận PASS với bằng chứng cùng build, không có lỗi security/trading nghiêm trọng, không có dữ liệu sản phẩm bịa ra. Gói phát hành Mobile không thuộc checkpoint này.

## 5. Cổng quyết định và việc làm được trong lúc chờ

| Cổng | Cần trước khi | Vẫn làm được trên local |
|---|---|---|
| G1 — Rules/schema/index | Đổi đường dữ liệu, lưu cutoff/review/ledger/roles, deploy Rules | Thiết kế, pure model, emulator negative tests |
| G2 — dependency mới | TTS, QR image, notification adapter nếu thư viện hiện có không đáp ứng | Contract, UI trạng thái unavailable, tests với adapter tiêm vào |
| G3 — role thứ năm | Cấp entitlement cho role chưa định nghĩa | Bốn role có tên, unknown role fail closed |
| G4 — live execution | Bất kỳ lệnh MetaApi thật | Paper trade và sandbox tests |
| G5 — provider/license/budget | Dùng news, historical volume, DeepSeek, broker, TTS, FCM thật | Pure logic, fixture có nhãn, adapter và failure tests |
| G6 — staging/production | Deploy, push tới người dùng, thay Rules production | Build và smoke local, chuẩn bị rollback |
| G7 — privacy/consent | Data Lake, segment push, migration leaderboard nhạy cảm | DataMasker/policy tests fail closed |

## 6. Ước lượng và thứ tự ưu tiên

- Ước lượng sơ bộ: **60–90 ngày công full-stack + QA Web**, chưa gồm thời gian chờ duyệt cổng, cấp tài khoản/provider hay sửa phát sinh sau staging. Chốt lại sau P0 khi đã có môi trường và nguồn dữ liệu được duyệt.
- Đường găng: **P0 → P1 → W08–W12 → W14–W17 → P7**. P4/P5 có thể đi sau P1 và chạy thành các lát độc lập nếu contract không thay đổi; P6 phụ thuộc vào identity, role và dữ liệu thị trường.
- Ưu tiên triển khai đầu tiên: W04–W06 (vượt quyền), W08–W09 (nhiễm phiên và thiếu nến tin cậy), W14–W15 (giao dịch/cutoff), rồi W11–W12 (AI thực tế). Không dùng màu xanh của unit test để thay cho các chốt này.

## 7. Nguồn kiểm tra tiến độ

- Hợp đồng và việc gốc: `tasks/requirements-v2.1.md`, `tasks/plan.md`, `tasks/todo.md`.
- Bằng chứng: `tasks/acceptance-matrix.md`, `tasks/tab1-local-acceptance-2026-09-12.md`, `tasks/checkpoint-2026-09-17-trade-api.md`.
- Phê duyệt và phát hành: `tasks/decisions-v2.1.md`, `tasks/release-readiness-v2.1.md`.

Khi đóng một `Wxx`, cập nhật cả mục `Txx` tương ứng và hàng acceptance liên quan; không tự chuyển toàn bộ `Txx` sang `[x]` nếu nghĩa vụ Mobile hoặc cổng khác của checklist tổng vẫn còn.
