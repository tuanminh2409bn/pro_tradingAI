# Điều kiện đóng 29 hàng nghiệm thu Web — 05/10/2026

## Kết luận

Danh sách gốc có 29 hàng mở. Đối chiếu bản production cuối 05/10:
`web-completion-plan.md` có **36 hàng, 9 đã đóng, 27 mở**;
**W24 và W26 mới PASS** bằng bằng chứng cùng release.
Một hàng gồm nhiều điều kiện về code, dữ liệu, quyền truy cập, trình duyệt
và môi trường phát hành. Có tiến độ local vẫn chưa đủ để đánh dấu toàn bộ
hàng PASS. Một số hàng tổng hợp còn phụ thuộc những hàng đứng trước.

Gate cuối: Python Emulator **331/331 local và 331/331 image VPS**, không skip;
Flutter **273 đạt + 2 Web-only VM skip**, Node **8/8**, analyzer 0 error/warning,
production Web build đạt. BE Python 3.12 giữ seccomp và FE/Rules đã deploy,
index READY; có rollback BE thật và restore Redis/persistence QA độc lập.
Key DeepSeek mới hợp lệ nhưng balance gần nhất **-0.13 USD**, chưa khả dụng.
Chi tiết: [production release](web-production-release-20261005/README.md).
Đây chưa phải chứng nhận mọi chức năng production đạt 100%.

## Điều kiện danh sách gốc và cập nhật đóng hàng

Trong cột cuối, tài khoản QA, kịch bản thử, code, backup/restore và báo cáo
nghiệm thu do người triển khai thực hiện sau khi có quyền truy cập cần thiết.
Không yêu cầu chủ dự án tự chạy kiểm thử hay tự viết tích hợp.

| Hàng | Phần phải hoàn tất/kiểm chứng để đóng | Đầu vào bên ngoài hoặc phụ thuộc |
|---|---|---|
| W06 | UI/Rules/API kiểm tra đủ Standard, Partner, Professional, Enterprise và Admin; chặn vượt quyền và role lạ trên cùng build. | Bộ QA tách biệt đúng quyền trên Firebase; không nâng QA Standard hiện hành thành Admin. |
| W07 | Rà validation, giới hạn/proxy/CORS, lỗi an toàn, retry/idempotency và log sạch của các mutation Web còn lại. | Chủ yếu code/audit/QA của người triển khai; smoke môi trường phát hành. |
| W09 | Đối chiếu nến đã đóng, volume, đủ lịch sử MTF, gap/weekend/DST và forex trong phiên mở; đo tải. | Nguồn nến/lịch sử có quyền dùng cho website khách hàng. TradingView đang có dữ liệu; quyền nguồn và đối chiếu rộng chưa đủ bằng chứng. |
| W11 | Macro có nguồn/thời gian; ba chuyên gia chạy thật, đúng số request và feature summary; kiểm tra timeout/quota/error. | DeepSeek key runtime hợp lệ; nguồn lịch kinh tế/sentiment phù hợp và giới hạn chi phí. |
| W12 | Consensus, xác nhận nến, Veto, Layer 1–5 và audit lưu thật; Soft/Veto không có Layer 4. | W09/W11; một chu kỳ phân tích đăng nhập thành công trên release. |
| W13 | Hoàn thiện/kiểm tra 27 thành phần chart, hình học, Ghost/HTF/Forecast, zoom, gesture, text scale và ảnh từng mục. | W12 và dữ liệu tín hiệu thật; phần renderer/browser QA do người triển khai làm. |
| W13a | First-run Sync Gate, metadata tài khoản đúng nguồn, đổi symbol/mode/timeframe và Soft Forecast. | Dữ liệu broker/tài khoản QA; W09/W12. |
| W14 | Gate server cho tín hiệu/giá/lot/risk, paper execution, retry/idempotency và cross-user; đối soát lệnh trên browser. | W09/W12 và nguồn giá đúng symbol; vẫn paper trading. |
| W15 | Cutoff tồn tại qua refresh, review/ack trước mở khóa, ngày UTC và kiểm tra bypass/mất AI. | W14; chính sách UTC/review đã chọn, không cần chốt lại. |
| W16 | Cảnh báo Soft/Hard, opt-out, không gửi trùng, foreground/background, sound và mở đúng tín hiệu. | FCM/Web VAPID, thiết bị/browser đồng ý nhận push; W12. |
| W17 | Chạy và lưu bằng chứng 27 render + 8 chức năng Trading Room trên cùng build; chốt ma trận nghiệm thu. | W06/W13/W13a/W14/W15/W16. |
| W18 | Journal đối soát trade/fee/swap/slippage/currency và hai schema; thực hiện positive browser flow đúng quyền. | Tài khoản MT4/MT5 demo qua MetaApi hoặc bộ trade sandbox được phép, có dữ liệu phí/tiền tệ. |
| W19 | Insight/heatmap/initial risk đúng nguồn; nghe phát/dừng TTS và export CSV đúng quyền trên browser thật. | W18; thiết bị có voice. TTS đã chọn API trình duyệt. |
| W20 | News, lịch kinh tế và sentiment có nguồn/freshness/quyền sử dụng; test parser/dedupe/error và positive browser. | Feed Fed đã có; feed này chưa thay lịch HIGH-impact hoặc social sentiment. Cần nguồn cho các trường còn thiếu. |
| W21 | What-If và Red Zone đi từ News sang chart cùng event ID/time, theo UID, hết hạn đúng và không đặt lệnh. | W20/W12; thực hiện nối luồng và browser QA. |
| W22 | Replay/play/pause/speed/cursor chạy trên lịch sử được duyệt, không nhìn trước dữ liệu; đối chiếu mẫu. | W09 và historical sample đủ quyền; phần playback/parity còn phải kiểm chứng. |
| W23 | Risk/P&L theo cursor, lock/review/ack và session restore/tamper trên cùng build. | W22/W15; đã có bằng chứng production một phần, cần đủ ma trận. |
| **W24 PASS** | Bản cuối: QA post/comment/like/copy/open share/reload giữ counters 1/1; owner/comment/like marker đúng qua SDK. Ownership/cross-user/retry tests đạt. | Đã đủ: web-production-release-20261005; không tính vào 27 hàng mở. |
| W25 | Publisher ranking từ nguồn broker xác minh; audit dữ liệu legacy; index READY; positive ranking và privacy trên release. | W18, alias/consent được phép và sample broker. API/private Rules mới đã đạt local; fixture không chứng minh nguồn broker. |
| **W26 PASS** | Hai QA signup production attribution đúng; count 0→1→2, reload vẫn 2. Server code/QR/banner/H.264 video tải thật, decode ảnh/frame đầu/giữa/cuối đúng link. | Đã đủ: web-production-release-20261005; không tính vào 27 hàng mở. |
| W27 | Deploy ledger/Admin/owner flow, receipt/refund/withdrawal đối soát, xem số dư và chứng từ PAID trên release. | Receipt thuê bao/chứng từ bên ngoài được phép; policy USD/F1 20%/F2 5%/14 ngày/minimum 20 đã chọn. Không tự chuyển tiền. |
| W28 | Standard onboarding/quota view đã deploy và production signup/Profile/reload đạt. Còn quota/reset/concurrency và role matrix đầy đủ. | W06, QA role/tenant phù hợp; không nâng QA Standard thành Admin. |
| W29 | Partner linking, Enterprise membership/subaccount/risk aggregate và tenant isolation đúng nguồn. | MetaApi/broker demo, QA Partner/Enterprise và dữ liệu membership/risk có nguồn. |
| W30 | Admin prompt/kill switch/risk/watchlist save-reload có hiệu lực BE, cache invalidation và bypass denial; close vẫn được phép. | QA Admin riêng; W12/W14 để positive runtime. |
| W31 | Radar chạy 50–100 tài sản, volume/barrier filter, provenance, candidate-only model calls, multi-user/Redis/load và SLA. | W09/W11/W12/W30; host/nguồn/Redis chạy thật và ngân sách thử có giới hạn. |
| W32 | Push segment/opt-out/limit/audit, token rotation/disable/retirement và notification click trên browser thật. | FCM/Web VAPID, consent, QA theo role và thiết bị; lifecycle/worker đã đạt local. |
| W33 | Nối consent/version, HMAC key, sink, retention/deletion và scan export/log; kiểm tra mẫu giữ/xóa. | Đích lưu và chính sách quyền riêng tư cần chốt/công bố; key qua kênh an toàn. Code tích hợp/kiểm thử do người triển khai làm. |
| W34 | Rà từng trang loading/offline/retry/keyboard/EN-VI/responsive; xử lý lỗi phát hiện; async/load cùng release. | Chủ yếu implementation và browser QA; dữ liệu/quyền phù hợp cho positive flow. |
| W35 | BE/FE/Rules đã deploy, index READY, BE rollback thật và Redis restore/persistence QA riêng đạt. Còn host đạt chuẩn/load/Redis production restart và sign-off phụ thuộc. | VPS hiện tại; console cứu hộ/restore toàn host cần để nâng OS an toàn. NTP chưa sync. Quyền Firebase/GitHub/SSH đã có; W01–W34. |

## Những thứ thực sự cần từ chủ dự án

1. **Host:** quyền SSH/làm trên VPS hiện tại đã có. Python 3.12 đã chạy được
   với bootstrap giữ seccomp, 331 ca Emulator trên VPS image đạt. OS/kernel/
   Docker vẫn dưới chuẩn. Backup config/RDB, restore Redis riêng và rollback
   đạt; chưa có console cứu hộ/restore toàn host để nâng OS an toàn. NTP chưa sync.
   Không mua/chuyển sang máy mới.
2. **DeepSeek:** key mới đã lưu root-only trên VPS; hai GET chỉ đọc **200**.
   Balance gần nhất **-0.13 USD**, `is_available=false`; cần nạp đúng account
   của key. Không in/lưu key vào Git/log và chưa gọi completion trả phí lượt này.
   Đề xuất probe sau khi số dư khả dụng: một analysis và một chat, tối đa
   USD 0.10, không đổi quota hoặc cấp Admin cho QA Standard.
3. **Dữ liệu/provider:** quyền dùng nguồn nến/lịch sử, lịch kinh tế/sentiment
   trên website khách hàng; ngân sách tối đa và quyền đăng ký dịch vụ nếu nguồn
   cần tài khoản. Người triển khai lựa chọn/tích hợp nguồn, đối chiếu điều khoản
   và giới hạn chi phí trước khi dùng. Không mặc định mọi mục phải mua OANDA/X.
4. **Broker/kinh doanh:** tài khoản MT4/MT5 demo/MetaApi hoặc mẫu sandbox có
   phí/currency/initial risk; receipt thuê bao/chứng từ được phép đối soát cho
   Referral. Các thông tin này khác tài khoản Firebase đăng nhập website.
5. **Thiết bị và chính sách:** browser/thiết bị cho phép push/audio; chấp thuận
   thông báo quyền riêng tư/consent và nơi lưu Data Lake. Người triển khai có
   thể soạn đề xuất cụ thể và bộ QA các role; chủ dự án không cần tự thiết kế.

Không gửi password/token/key trong chat hay đưa vào Git. Quyền push/deploy/SSH
đã có; không xin lại quyền chung. Key mới đã hợp lệ; số dư khả dụng chưa có.
Quyền nguồn, broker/chứng từ và thiết bị/chính sách vẫn cần đúng phạm vi.

## Trình tự kết thúc

- Tiếp tục code/audit/browser QA không phụ thuộc provider, chốt từng điều kiện
  nhỏ trong W06/W07/W13/W21/W28/W30/W34; W24/W26 đã đóng.
- Có host/key/nguồn và sandbox thì chạy data/AI/trading/journal/backtest/radar,
  đối soát request/token/chi phí và lưu bằng chứng.
- Bản 05/10 đã phát hành phối hợp BE/FE/Rules; tiếp tục role/device matrix,
  load, Redis production restart và các gate còn thiếu trên cùng release.
- W17/W35 là nghiệm thu tổng hợp; chỉ đóng sau các phụ thuộc. Chưa có cơ sở
  hứa ngày hoàn thành khi số dư/provider/broker/device/host gate chưa đủ.

Nguồn: `web-completion-plan.md`, `checkpoint-2026-10-05-web-completion.md`,
`web-local-acceptance-2026-10-05/test-results.json`, `provider-matrix.md`,
`backend-host-migration-2026-10-05.md`, `referral-money-policy-2026-10-05.md`.
Provider matrix/decision register có dòng gốc cũ; checkpoint 05/10 và policy
Referral 05/10 và production release 05/10 được ưu tiên khi mô tả tiến độ mới.
