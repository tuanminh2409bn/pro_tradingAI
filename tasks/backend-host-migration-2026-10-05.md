# Chuyển host backend — phương án thực hiện

## Quyết định

**Yêu cầu mới của chủ dự án: tiếp tục trên VPS hiện tại.** Đã chạy thành công
Python 3.12.15 giữ seccomp, **331/331 test Emulator trên VPS image**.
Đã cutover BE trước FE/Rules, index READY và drill rollback BE thật.
Backup config/RDB và restore Redis/persistence QA riêng đạt.
Xem [production release](web-production-release-20261005/README.md).
Máy QEMU có thể nâng guest OS trên cùng VPS, nhưng chưa có console cứu hộ/
restore toàn host; NTP chưa sync. OS/kernel/Docker vẫn chưa đạt, W35 mở.

Phương án máy mới dưới đây là đề xuất trước yêu cầu mới, chỉ giữ làm tham chiếu
nếu chủ dự án đổi lựa chọn; chưa mua máy hoặc thực hiện phương án đó:

Chọn **máy mới Ubuntu 24.04 LTS**, Docker Engine từ nguồn chính thức, giữ seccomp
mặc định; chạy candidate Python 3.12 với dependency constraints hiện có.
Khởi đầu staging 2 vCPU/4 GB RAM, đo tải trước khi quyết định cấu hình production.
Chưa mua máy, chưa nâng/reboot máy hiện tại và chưa cutover.

Máy hiện tại được xác minh trong `python-runtime-upgrade-2026-10-04.md`:
Ubuntu 16.04.7, kernel 4.4, Docker 18.09.7. Trước bootstrap mới, candidate
Python 3.12 không tạo được thread dưới seccomp trên host này. Bootstrap đã
xử lý lỗi đó và lỗi kiểm tra keyring; OS/kernel/Docker vẫn chưa đạt chuẩn.
Cold build Python 3.10 trước đó chỉ là bằng chứng runtime tương thích cũ.

Nguồn: [Docker Engine trên Ubuntu](https://docs.docker.com/engine/install/ubuntu/),
[lịch vòng đời Ubuntu](https://ubuntu.com/about/release-cycle),
[lịch hỗ trợ Python](https://devguide.python.org/versions/).

## Dữ liệu cần để bắt đầu

- IP/SSH key an toàn của host mới, hoặc quyền tạo máy ở nhà cung cấp VPS.
- Snapshot/backup host cũ có thời điểm, checksum và kết quả thử khôi phục.
- Người vận hành thực hiện chuyển credential qua kênh an toàn; không đưa env,
  service account hoặc provider key vào Git, artifact QA hay log.

## Trình tự và bằng chứng

1. **Backup trước thay đổi.** Ghi source/image/container/FE release hiện hành,
   Nginx/TLS, Redis và Firestore Rules/index version. Backup Redis cùng dữ liệu
   cần khôi phục; giữ credential tách khỏi tài liệu bằng chứng. Thử restore sang
   staging. Không suy rằng snapshot tồn tại chỉ vì có quyền root.
2. **Gate host mới.** Chạy `python3 deploy/check_backend_host.py`. Chính sách
   dự án cần Ubuntu 24.04/26.04, kernel >=5.15, Docker >=25 và seccomp mặc định.
   `host_eligible=true` chưa đồng nghĩa release PASS.
3. **Build candidate.** Pull Python 3.12.15 slim Bookworm từ Docker Official
   Image, xác minh và ghi digest thực tế. Build `Dockerfile` với
   `PYTHON_RUNTIME_IMAGE` trỏ đúng digest đó, giữ
   `backend-production-constraints.txt`. Lưu image ID bất biến và `pip check`.
4. **Thread probe.** Trên host mới, chạy:

   ```sh
   python3 deploy/check_backend_host.py --image-id sha256:<IMAGE_ID_64_HEX>
   ```

   Probe chỉ dùng image đã có trên máy, không pull/network/env/mount/port; read
   only, cap-drop ALL, no-new-privileges và giới hạn CPU/RAM/PID. Phải có
   `image_thread_probe=PASS`. Không dùng `seccomp=unconfined` để đạt gate.
5. **Staging.** Giữ cổng backend/Nginx/Redis hiện hành theo cấu hình đã duyệt,
   dùng môi trường và credential staging riêng. Chạy full Python/Flutter/Rules,
   HTTP auth bypass, onboarding Standard, ledger/retry/reversal và browser
   cùng build. Kiểm tra nhiều UID/symbol, quota đồng thời, Radar 50–100 asset,
   Redis restart/cache/single-flight và FCM thiết bị thật. Chỉ bật workers khi
   nguồn và giới hạn chi phí đã được xác nhận; không seed tiền giả vào production.
6. **Runtime/provider.** Xác minh key DeepSeek hợp lệ và usage/chi phí của probe
   được duyệt; bằng chứng feed/broker/TTS cần đúng quyền sử dụng. Theo dõi request
   ID và provenance. Đăng ký tài khoản mới không tự cấp Admin hoặc role chưa biết.
7. **Cutover phối hợp.** BE hỗ trợ `/api/auth/onboarding`, Referral và
   `/api/community/leaderboard` phải
   sẵn sàng trước FE mới; áp dụng Rules/index tương ứng và chờ index READY. Build
   FE mặc định production, không dùng bundle Emulator trong `build/web` hiện tại.
   Chuyển traffic sau smoke và rollback drill; không chỉ đổi IP trong một build cũ.
8. **Rollback.** Giữ host/image/FE cũ trong thời gian quan sát. Khi gate lỗi,
   chuyển traffic và FE về release đã xác minh; bảo toàn ledger bất biến và
   receipt IDs để retry không cộng/chi hai lần. Không xóa hoặc viết lại ledger
   khi rollback. Nếu chưa kiểm tra tương thích schema/Roles/Rules của rollback,
   chưa được cutover. Leaderboard Rules tiếp tục private: rollback phải giữ
   API trả DTO công khai hoặc hiển thị unavailable, không mở lại quyền đọc
   document legacy cho client cũ.

## Trạng thái 05/10

CLI + 2 regression tests đã có, giữ nguyên các ngưỡng. Preflight thực tế trên
VPS hiện tại trả `host_eligible=false` vì OS/kernel/Docker cũ. Probe runtime
riêng và Python 3.12.15 đạt; **331/331** ca trên image cuối đạt. Production
chạy `protrading-web-quota-live-20261005`, giữ worker/config/mount hiện hành;
ba candidate QA của lượt này đã stop để trả RAM. FE/Rules đã phát hành.
Backup config/RDB, Redis restore riêng, rollback V1→V2→V1→V2 và FE rollback
channel đã có. Chưa nâng/reboot OS, chưa có console cứu hộ/restore toàn host;
không dùng bằng chứng Redis để suy toàn host đã an toàn. W35 tiếp tục mở.
