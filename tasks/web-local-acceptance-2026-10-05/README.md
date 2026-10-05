# Bằng chứng Web local — 05/10/2026

**Môi trường:** Auth Emulator 9099, Firestore Emulator 8080, FastAPI QA 8088,
Web QA 9081. Synthetic fixtures chỉ có trên loopback; không dùng credential
production, không có chuyển tiền thật hoặc gọi DeepSeek trả phí. Backend QA
có `PROTRADING_LOCAL_QA=1`, `PROTRADING_BACKGROUND_WORKERS=0`; CORS QA process
chỉ bổ sung đúng origin `http://127.0.0.1:9081`.

## Bằng chứng cùng build cuối

- `manifest.json`: source SHA-256/HEAD nền và hashes riêng Web QA/candidate.
- `test-results.json`: kết quả gate và lệnh chạy, tách skips/host NOT_RUN.
- `auth-restore-chrome.png`: sau reload giữ Standard owner, không cần login lại;
  mở đúng ETHUSD/H4 + Day Trading từ structured query. Console không có
  error/warning mới trong khoảng reload. Không bấm Analyze/Chat.
- `referral-paid-chrome.png`: cùng build cuối, EN/VI wallet/historical PAID;
  available USD 20, held USD 0. Không có Admin tab cho owner Standard.
- `referral-readback.json`: đối soát Firestore fixture với integer cents;
  CREDIT 4000/HOLD 2000/PAYOUT 2000, PAID 2000, available 2000/held 0.
- `leaderboard-empty-chrome.png`, `leaderboard-verified-chrome.png`: trước khi
  seed không có ranking; sau seed chỉ một alias có nhãn `[Emulator QA]` xuất
  hiện, không hiện bản ghi private/stale. API đọc tối đa 20 document; Web refresh
  5 phút. Direct Firestore GET/query/write bị Rules chặn, kể cả Admin client.
- `leaderboard-fixture.json`: ba fixture loopback và kết quả browser; đã dọn
  đúng ba document vừa tạo. Đây không phải bằng chứng publisher/broker thật.
- `host-preflight-local.json`: gate thực tế trên Mac local **không đủ điều
  kiện**, image thread probe **NOT_RUN**; không có Docker container proof.

## Bằng chứng trung gian trước sửa bootstrap cuối

`admin-receipt.png`, `referral-pending.png`, `referral-390px.png`,
`referral-paid.png`, `push-chart-target.png`, `push-chart-target-chrome.png`
ghi lại các bước triển khai ban đầu, không có cùng bundle hash với build cuối.
Money/API/role behavior tương ứng được kiểm thử lại bằng gate tự động cuối và
readback trên build cuối. Không dùng ảnh trung gian để ký nghiệm thu cả release.

## Kịch bản đã thực hiện

1. Tạo account bằng Web local, backend tự cấp Standard; SDK kiểm tra claim,
   không seed quyền cho account đăng ký này.
2. Admin fixture ghi nhận một receipt thuê bao USD 200 đã quyết toán >14 ngày;
   F1 owner nhận CREDIT USD 40. Receipt nhập lại không cộng lần hai.
3. Owner yêu cầu USD 20; available giảm còn USD 20, held USD 20, một PENDING.
4. Admin duyệt → APPROVED; chỉ sau nhập mã chứng từ bên ngoài mới ghi PAID.
   Không có gateway/transfer trong kịch bản. Queue không còn pending/approved.
5. Owner đăng nhập lại, đọc PAID/available 20/held 0. Trên build cuối, Chrome
   reload giữ phiên, chuyển EN/VI và đọc đúng ví/lịch sử.
6. Mở structured URI ETHUSD/H4, chọn Day Trading đúng matrix; không tự phân
   tích hoặc thực thi. Market feed trong QA tắt nên chart ghi unavailable.
7. Community dùng API được bảo vệ bằng token. Tạo ba ranking fixture có nhãn
   public/private/stale trong Emulator, chỉ public alias hiện; sau khi lưu ảnh
   xóa đúng ba fixture này. Không mutate leaderboard production.

## Giới hạn

Emulator không chứng minh quyền nguồn/broker, payment receipt/gateway thật,
FCM delivery trên thiết bị, index production READY, nhiều writer Auth claim,
Redis restart/load hoặc host mới. Onboarding role lock chỉ trong một process.
Không mark W25/W27/W28/W32/W34/W35 production PASS từ các fixtures này.
Bundle trong `build/web` đang bật Emulator; **không deploy bundle đó**.
