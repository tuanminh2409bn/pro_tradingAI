# Web production — bằng chứng phát hành 05/10/2026

## Bản đang chạy

- Source code **`b3668d9`**, nối tiếp nền `9dbfa49`; tài liệu được ghi sau code.
- FE Firebase `protrading-ai-2026`: Hosting version **`713a4e79b2aa6b74`**, phát hành `08:20:56 UTC`. SHA-256 `main.dart.js` **`5bee67a2d577575666ba6ba11bd9696613e4dadc2e1d43edb7bbeba6e9ced1e1`** trùng bundle công khai tải lại.
- BE **`protrading-web-quota-live-20261005`**, image **`sha256:be21990d6d9ca2faf463d4a9d8ae8c25f44ef5dc136777fdcd20c7b9cf1bfe8b`**, Python 3.12.15, Redis/worker hiện hành. Không dùng image QA hay bundle Emulator cho production.
- Rules **`7fc0eb8f-92bd-4d49-baff-e76f6c33a346`**: leaderboard private; wallet/ledger/withdrawal chỉ server ghi. Index leaderboard **`CICAgJiUsZIK` READY**, giữ bốn index cũ.
- [Web production](https://protrading-ai-2026.web.app/).

Manifest: [BE](backend-source-manifest.json), [image verification](image-verification.json), [FE final](web-final-manifest.json), [Firebase final](firebase-final-release.json), [Git source khớp bản deploy](code-source-verification.json).

## Kiểm thử

| Gate | Kết quả cuối |
|---|---|
| Python + Auth/Firestore/API Emulator local | **331/331**, không skip |
| Cùng source trên image VPS | **331/331**, không skip; QA overlay riêng |
| Flutter | **273 đạt**, 2 ca Web-only đã có được skip trên Dart VM |
| Node Web | **8/8** |
| Analyzer | **0 error, 0 warning**, 3 info `activeColor` cũ ở Mobile |
| Production Web release build | PASS |
| Backtest pause regression | Tái hiện đỏ trước sửa; **17/17** đạt sau sửa |

[Kết quả/hash log](test-results.json). Lần VPS trước có một fixture timestamp đi trước đồng hồ máy API; sửa fixture hợp lệ về một phút trước, giữ test từ chối dữ liệu tương lai. Kết quả cuối đều đạt; không thêm skip hay nới assertion. Tests/fixture/credential không được đóng vào image production.

## Luồng thật trên cùng bản cuối

### Standard và quota — tiến độ W06/W28

Hai QA tách riêng đăng ký bằng Web, attribution về cùng inviter. QA cuối tạo trên Hosting version cuối. Backend cấp **Standard**, không Admin; token refresh trước shell. Profile mới: `source=server_enforced`, Analysis **0/2**, Backtest **0/2**, reset UTC tương ứng 12/10 07:00 VN. Save paper risk config qua API đạt.

Quota refresh chỉ đọc counter rồi cập nhật view, không tiêu lượt hoặc reset counter. QA chạy replay/restore giữ Analysis **0/2**, Backtest **1/2**. Ma trận Partner/Professional/Enterprise/Admin production vẫn mở.

Bằng chứng: [readback quota](final-qa-readback.json), [signup risk](standard-signup-risk-gate-final.jpg), [signup quota](standard-signup-quota-final.jpg), [Profile VI](standard-quota-final-vi.jpg).

### Community — **W24 PASS**

QA cuối tạo bài có nhãn `QA FINAL`, thêm một comment, thích một lần qua token API. Copy link thật và mở lại sau navigation/reload khôi phục đúng bài, đã thích, **1 like / 1 comment**. Server readback xác nhận owner QA, một comment document và owner like marker. Nội dung QA được giữ để truy vết, không có dữ liệu khách hàng trong bài.

Bằng chứng: [clipboard link](community-share-final.json), [counters](community-counters-final.jpg), [share restore](community-share-restore-final.jpg), [readback](final-runtime-readback.json). Ownership/cross-user/idempotent retry có tests trong bộ cuối. Leaderboard W25 vẫn cần nguồn broker/consent thực tế.

### Referral — **W26 PASS**

Hai QA đăng ký từ link inviter, attribution đúng; count **0 → 1 → 2**. Reload lại cùng link: readback vẫn **2**, không tăng trùng; cả hai Standard, không Admin. QA cuối có mã riêng do server cấp, không suy từ UID.

Nút production tải QR **600×600**, banner **1200×630**, video H.264 **1200×630**, **6.181 giây / 96,466 byte**. Apple Vision/AVFoundation decode ảnh và frame đầu/giữa/cuối video: QR đều trùng link server. File native nằm trong Downloads máy kiểm thử; JSON ghi tên, kích thước, hash. IAB không phát Playwright download event, nhưng file native tải hoàn chỉnh và được kiểm tra độc lập.

Bằng chứng: [registration/retry](final-runtime-readback.json), [inviter count 2](referral-registration-count-final.jpg), [download/decode/hash](referral-kit-final.json), [giao diện kit](referral-kit-final.jpg), [QA gốc/VI/URL gốc](referral-live-final-vi.jpg). Ảnh inviter mở link chính mình có thông báo từ chối tự referral, không tăng count; URL gốc không có thông báo. Tab cuối đã trả về QA của dự án, không để phiên QA mới. W27 còn cần receipt/refund/withdrawal/chứng từ thật. **Không seed tiền/receipt tài chính vào production; không chuyển tiền thật**.

### Backtest — tiến độ W22/W23

Phiên BTCUSD/M5 dùng **2,999 nến đóng** server. BUY 0.001: `84308.78 → 84007.43`, P&L `-0.30135`; SELL 0.001: `84007.43 → 84142.90`, P&L `-0.13547`; balance **999.56318**, UI **999.56**. Bản cuối restore đúng hai lệnh đóng, cursor và quota. Play/pause giữ cursor ổn định; tick không tích lũy khi storage chậm.

Bằng chứng cuối: [restore](backtest-restore-final.jpg), [pause](backtest-paused-final.jpg), [quota](standard-quota-final.jpg). Ảnh `backtest-*-production.jpg` và ảnh Community/Profile không có hậu tố `final` là bước trung gian trước bản FE cuối. Quyền nguồn/parity rộng và đủ ma trận risk/review vẫn cần để đóng W22/W23.

## Backup, cutover và rollback

- Backup Nginx/config và Redis ở `/root/protrading-backup-20261005`, thư mục 700/file 600; credential tách khỏi artifact/Git.
- Restore Redis vào QA container riêng, SET/SAVE/restart/readback đạt; không restart Redis production. Hai container restore QA cùng volume riêng đã dọn.
- Drill BE thật: V1 → V2 → V1 → V2; mỗi bước health/Redis 200, thiếu token 401; trạng thái cuối V2 hoạt động. [Cutover cuối](protrading-quota-cutover-result-20261005.json).
- Giữ container/image V1 và bản cũ stopped để rollback; ba candidate QA của lượt này stop để trả RAM, không xóa.
- FE rollback version `20cb2d7b6d93edd6` ở channel `rollback-quota-20261005`; bản trước lượt này `8f55a00dd30bbf99` ở `rollback-20261005`. [Metadata](firebase-final-release.json).
- VPS lệch khoảng hai giây gây ID token vừa cấp bị từ chối. Đối chiếu hai HTTPS Date sources rồi chỉ chỉnh đồng hồ tiến **2.036 giây**, không nới auth validation. [Clock repair](clock-repair.json). NTP vẫn chưa sync do UDP không tới nguồn.

## Điều kiện còn mở

Kế hoạch **9/36 hàng đóng, 27 mở**. Test đạt không thay các luồng cần provider, role/device hoặc chứng từ thật.

- Key DeepSeek mới hợp lệ (`/models`, `/user/balance` 200), nhưng [GET balance cuối 09:22 UTC](deepseek-balance-final.json) vẫn **-0.13 USD**, `is_available=false`. Model dùng `deepseek-flash`; **không gọi AI trả phí lượt này**. Cần account của key có số dư trước probe giới hạn chi phí.
- Còn quyền feed/lịch sử thương mại, HIGH-impact/sentiment, broker/fee/currency/initial risk, role/tenant, FCM/audio thiết bị, Radar/load, Data Lake consent/sink/retention.
- Ubuntu 16.04.7/kernel 4.4/Docker 18.09.7 vẫn **`host_eligible=false`**. Bootstrap giữ seccomp chạy Python 3.12 nhưng không làm host đạt chuẩn. Chưa nâng/reboot, chưa có console cứu hộ/restore toàn host; W35 mở.

Rà soát: Codex; source/tests, cùng release browser, Firebase metadata và VPS runtime. Artifact không lưu key/password/token.
