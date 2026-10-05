# Web completion — checkpoint 05/10/2026

## Kết quả production

Source code `b3668d9`, nối tiếp nền `9dbfa49`. Đã phát hành BE trước FE trên
VPS hiện tại/Firebase theo quyền được duyệt. FE Hosting **`713a4e79b2aa6b74`**,
BE **`protrading-web-quota-live-20261005`**, image
`sha256:be21990d6d9ca2faf463d4a9d8ae8c25f44ef5dc136777fdcd20c7b9cf1bfe8b`.
Bundle công khai trùng SHA-256 bản production đã build; Rules/index mới đã
phát hành, index leaderboard READY. Giữ các thay đổi Mobile/file dọn dẹp đã có.
Bằng chứng cuối ở [production release](web-production-release-20261005/README.md);
fixture trước phát hành ở [local acceptance](web-local-acceptance-2026-10-05/README.md).

| Mục | Phần đã triển khai/kiểm tra | Điều kiện production còn thiếu |
|---|---|---|
| W06/W28 · Standard/quota | UID từ token, fresh role, giữ role hợp lệ/fail closed role lạ. Hai QA đăng ký Web production tự được Standard, không Admin; token refresh trước shell. Profile mới 0/2 Analysis, 0/2 Backtest. Quota view refresh chỉ đọc counter, không tiêu/reset lượt; replay/restore giữ 1/2 Backtest. | Positive production role/tenant matrix. UID lock chỉ trong một process, không phải CAS với writer claim ngoài. |
| **W24 · Community PASS** | Bản cuối: QA post/comment/like/copy link; mở lại link/reload khôi phục đúng owner, đã thích, 1 like/1 comment. Server readback có một comment và owner like marker; ownership/cross-user/retry tests đạt. | W24 đủ; leaderboard W25 riêng còn mở. |
| **W26 · Referral link/kit PASS** | Hai QA đăng ký từ link, attribution đúng; count 0→1→2, reload không tăng trùng. Mã riêng do server cấp; tải QR/banner/H.264 video thật. Decode QR ảnh và frame đầu/giữa/cuối đều trùng link server. | W26 đủ; ledger/chứng từ chi trả W27 riêng còn mở. |
| W27/W30 · Referral money | USD integer cents, F1 20%/F2 5%, hold 14 ngày, minimum USD 20; immutable ledger, receipt/payout reference duy nhất, idempotent retry/reversal, giữ số dư ngay lúc yêu cầu rút. Admin UI ghi nhận receipt, duyệt/từ chối và xác nhận chứng từ chi trả qua API với fresh Admin claim. | Chứng từ kinh doanh thật, đối soát thanh toán và production workflow. Đây là xét duyệt thủ công, không tích hợp gateway hoặc tự chuyển tiền. Tổng thành viên trả phí/mạng broker cũ vẫn unavailable khi chưa có nguồn đối soát. |
| W25 · Leaderboard boundary | Direct Firestore read/write bị chặn, kể cả Admin client; token API kiểm tra role/disabled hiện hành và chỉ trả public DTO có allowlist/finite/freshness <=2 ngày. Query tối đa 20, Web refresh 5 phút. Rules đã deploy, composite index production READY; fixture loại private/stale đạt. | Adapter/publisher broker xác minh, mẫu ranking thật và migration/privacy review. Fixture không chứng minh nguồn broker. |
| W32 · FCM lifecycle | Subscription dispose, UID/generation guard, rotation/disable cleanup và consent/VAPID gate; không tạo token lúc logout. Sender chỉ retire UnregisteredError, không xóa token khi lỗi tạm thời. Worker không hiện notification SDK lần hai; click dùng structured target cùng origin. | VAPID/consent, token rotation/notification-click/delivery trên thiết bị thật, role/segment production đúng quyền. |
| W34 · Web QA | EN/VI Referral, ví/lịch sử theo owner, invalid-money guard, pending/approved/paid UI; browser workflow local và 390px proof. Sửa Auth Emulator reload bằng bootstrap SDK trước FlutterFire hydration; Chrome giữ phiên Standard và ETHUSD/H4 sau reload, không có console error/warning mới. | Accessibility/offline/load cho toàn bộ trang trên cùng release; proof local không thay nghiệm thu production. |
| W22/W23 · Backtest | 2,999 nến server BTCUSD/M5; BUY/SELL/close đối soát balance 999.56318. Bản cuối restore đúng cursor/closed trades/quota; sửa tick queue khi storage chậm, pause production ổn định. | Quyền nguồn/parity rộng và đủ ma trận risk/review. |
| W35 · Host/release | Python 3.12.15 giữ seccomp, 331/331 tests trên VPS image; backup Nginx/RDB, restore Redis/persistence QA độc lập đạt; cutover/rollback BE thật, FE rollback channel, index READY. | Host OS/kernel/Docker dưới chuẩn, NTP chưa sync, console cứu hộ/restore toàn host và load/acceptance dependencies. Chưa nâng/reboot host. |

## Bảo vệ dữ liệu tài chính

- Wallet/ledger/withdrawal chỉ owner đọc; client không ghi, kể cả Admin.
- Rules chặn cả tạo trực tiếp và đổi yêu cầu thường thành
  `REFERRAL_WITHDRAWAL`; test tái hiện 200 trước sửa, 403 sau sửa. Mutation
  Admin thường vẫn được phép đúng quyền. API đối chiếu role/disabled hiện hành.
- Leaderboard cũ cho phép đọc công khai toàn bộ document, nên chỉ lọc UI vẫn
  có thể lộ PII. Test tái hiện direct GET 200; Rules mới trả 403 và API chỉ trả
  đúng trường công khai. Không xóa/migrate document legacy để làm nghiệm thu.
- Transaction concurrency 30 yêu cầu rút khác nhau chỉ chấp nhận một; không
  overdraw hoặc ghi receipt hai lần. Refund sau payout có thể tạo available
  âm để bảo toàn nghĩa vụ kế toán; không mở rút/payout mới khi thiếu tiền.
- Luồng browser fixture: receipt USD 200 → F1 CREDIT USD 40 → HOLD USD 20 →
  APPROVED → PAID với mã chứng từ riêng. SDK readback: available USD 20,
  held USD 0, paid USD 20; ledger còn CREDIT/HOLD/PAYOUT bất biến. **Không có
  chuyển tiền thật**. HOLD/RELEASE hiển thị trung tính để không nhầm trừ hai lần.

## Kiểm thử

- Bản cuối: **331/331 local và 331/331 image VPS**, không skip; QA overlay
  dùng Auth/Firestore/API Emulator riêng, không đưa tests/fixture vào image production.
- Flutter full: **273 đạt, 2 Web-only VM skips**; Node Web: **8/8 đạt**.
- Analyzer: **0 error/warning**, còn 3 info `activeColor` cũ ở Mobile.
- Production Web release build đạt, đã deploy từ
  `/tmp/protrading-web-production-final-20261005`; không deploy `build/web` Emulator.
- Backtest pause regression đỏ trước sửa, **17/17** đạt sau sửa; giữ assertion.
- [Manifest/hash log/results](web-production-release-20261005/test-results.json).
- `py_compile` và `git diff --check` đạt. Local host gate trả ineligible/NOT_RUN
  đúng thực tế, không tính là container startup PASS.
- Luồng tài chính dùng Emulator fixture có nhãn; signup/Community/Referral kit
  có bằng chứng production thật. Không seed receipt/tiền tài chính production,
  không chuyển tiền thật. Backend QA tắt workers/provider; không gọi DeepSeek
  trả phí trong lượt này. Không dùng fixture để đóng hàng production.

Auth reload root cause được đối chiếu source SDK đã khóa và
[FlutterFire issue 11534](https://github.com/firebase/flutterfire/issues/11534):
plugin đợi Auth hydration trong initializeApp trước khi Dart main có thể cấu
hình Emulator. Bootstrap QA dùng đúng JS SDK 12.13.0/tùy chọn initializeAuth
của package hiện hành, gọi connect Auth/Firestore trước hydration; chỉ chạy khi
build bật Emulator và trang có hostname loopback. Production mặc định không
gọi bootstrap. Nếu nâng Firebase packages, phải đối chiếu phiên bản/tùy chọn
bootstrap và kiểm tra reload lại.

## Các gate chưa thể đóng

Kế hoạch **9/36 hàng đóng, 27 mở**; W24/W26 mới đóng bằng chứng cùng release.
Test đạt không thay các gate cần provider/role/device/chứng từ thật; chưa 100%.

- Key DeepSeek mới hợp lệ: `/models` và `/user/balance` **200**, balance gần
  nhất **-0.13 USD**, `is_available=false`. Key root-only trên VPS, không vào
  Git/log. Cần số dư của chính account thuộc key trước probe AI có giới hạn chi phí.
- BE mới chạy trên VPS hiện tại; OS/kernel/Docker vẫn dưới chuẩn. Backup config/
  Redis và restore Redis riêng đạt, chưa có console cứu hộ/restore toàn host để
  nâng guest OS an toàn. NTP chưa sync; không nới auth validation/host gate.
- Còn quyền feed thương mại, Macro/calendar/sentiment, broker/currency/initial
  risk samples, TTS playback, role/tenant matrix và FCM thiết bị thật.
- Còn Radar 50–100 asset/multi-user/load, Redis production restart và Data Lake
  consent/HMAC/sink/retention. Phần unavailable phải giữ nhãn và gate đúng quyền.

Tiếp tục theo [`backend-host-migration-2026-10-05.md`](backend-host-migration-2026-10-05.md)
và [`referral-money-policy-2026-10-05.md`](referral-money-policy-2026-10-05.md).
Không phát hành FE mới một mình: nó phụ thuộc onboarding/Referral/leaderboard
API mới. Rollback giữ leaderboard private; không mở lại Rules công khai để
chạy client cũ.
