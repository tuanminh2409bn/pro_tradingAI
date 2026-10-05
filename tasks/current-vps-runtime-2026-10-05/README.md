# Backend Python 3.12 trên VPS hiện tại — 05/10/2026

> **Artifact lịch sử trước phát hành.** Bản cuối đã cutover BE/FE/Rules,
> index READY, có 331/331 tests local và VPS image, rollback BE thật và
> Redis restore riêng. Key mới trả 200 nhưng balance -0.13 USD.
> W24/W26 mới đóng; hiện 9/36 hàng đóng, 27 mở. Các kết quả 324/401/candidate
> bên dưới giữ nguyên theo thời điểm đo, không phải trạng thái live hiện tại.
> Xem [production release cuối](../web-production-release-20261005/README.md).

## Kết quả

Theo yêu cầu mới của chủ dự án, tiếp tục trên VPS `103.69.189.243`.
Đã build và chạy candidate Python **3.12.15** trên chính VPS đó, giữ Docker
seccomp mặc định. Chưa chuyển traffic, commit/push, deploy FE/Rules/index,
nâng OS/Docker hoặc reboot.

| Kiểm tra | Bằng chứng | Kết quả |
|---|---|---|
| Source/image | `source-manifest.json`, `image-verification.json` | 27 file thực sự trong image khớp hash; Dockerfile được định danh trong archive build. |
| Dependency | `image-verification.json` | `pip check` đạt; 74 package cần dùng khớp 76 constraints. Hai package `async-timeout`/`exceptiongroup` không cần trên Python 3.12 theo marker dependency. |
| Kernel/container | `runtime-probe.json` | 80 tác vụ thread, kế thừa filter sau exec, đọc keyring đạt; file không tồn tại vẫn bị từ chối. Seccomp=2, no-new-privileges=1, capability=0; mount/unshare vẫn bị chặn. |
| Backend local | `test-results.json` | 324/324, không skip; Auth/Firestore/FastAPI Emulator. |
| Backend image trên VPS | `test-results.json` | 324/324, không skip; Emulator local được nối qua SSH vào loopback VPS. |
| Cấu hình hiện hành | `candidate-smoke.json` | Health/Redis đạt; API onboarding/leaderboard/Referral hiện diện; thiếu token trả 401. Worker tắt, chỉ bind loopback, credential mount read-only. |
| DeepSeek được duyệt chỉ đọc | `deepseek-readonly.json` | `/models` và `/user/balance` đều 401. Không gọi completion, không lưu/in key. |
| Chuẩn host | `host-preflight.json` | Chưa đạt: Ubuntu 16.04, kernel 4.4, Docker 18 thấp hơn chuẩn dự án. Probe runtime đạt riêng không đổi kết quả gate này. |

Image cuối:

```text
sha256:d6969706625efed31478dc23d2555119eeb6a99c07d37200e20e6c6e157dc0b1
```

Candidate `protrading-current-vps-candidate-20261005` ở
`127.0.0.1:8019`; `PROTRADING_BACKGROUND_WORKERS=0`.
Production `protrading-ai-referral-live-7ef3ab6` vẫn giữ nguyên và health đạt.
Không chạy mutation hay seed dữ liệu fixture vào Firebase production.

## Nguyên nhân và cách sửa

Docker 18 trả EPERM cho `clone3` và `faccessat2`. Glibc không dùng fallback
khi gặp EPERM: thread không tạo được, còn apt-key tưởng không đọc được public
keyring dù file có 55.918 byte. Chẩn đoán apt được thực hiện trong container
không credential; quyền SYS_PTRACE chỉ dùng để truy vết apt trong probe đó.
Không bật quyền này trên candidate hay production.

`deploy/runtime_seccomp.py` dò hai syscall bằng thao tác không tạo tiến trình
và kiểm tra tồn tại của `/`. Chỉ syscall thực sự trả EPERM mới được bổ sung
filter **từ chối với ENOSYS** để glibc dùng syscall cũ. Không mở syscall,
không thay filter ngoài của Docker. Trên host cho phép syscall mới, giữ nguyên
kiểm tra quyền file hiện đại. ABI không hỗ trợ và lỗi cài filter dừng startup.
Bootstrap chạy cả bước build và entrypoint; helper clone giữ entrypoint mới.

Đối chiếu: [kernel seccomp stacking](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html),
[Docker clone3 issue](https://github.com/moby/moby/issues/42680),
[Linux access/faccessat2](https://man7.org/linux/man-pages/man2/access.2.html),
[Docker default seccomp](https://docs.docker.com/engine/security/seccomp/).

## Giới hạn và bước còn lại

- Đây là compatibility runtime trên VPS cũ, chưa phải chứng nhận host được
  hỗ trợ hoặc đóng W35. Gate Ubuntu/kernel/Docker không bị hạ thấp.
- Nâng guest OS trên cùng VPS QEMU vẫn cần backup có thử khôi phục và console
  cứu hộ của nhà cung cấp. Chưa có bằng chứng hai điều kiện này; chưa nâng OS.
- Root SSH/quyền chung không làm key DeepSeek hợp lệ. Sau hai kiểm tra được
  duyệt cụ thể, cần key hợp lệ qua file an toàn trên VPS; không gửi trong chat.
- Backup/restore, rollback drill, tải/Redis restart, role/device/provider và
  bằng chứng business production vẫn còn. W35 và tổng 29 hàng tiếp tục mở.
- Artifact Web local trước đó vẫn là bằng chứng của lát Web; hash Dockerfile
  trong manifest cũ không đại diện image runtime mới. Dùng manifest tại đây
  để xác định backend candidate này.

Lần đầu bộ QA VPS thiếu bảy module chỉ dùng trong kiểm thử nên discovery lỗi
import; đã bổ sung đúng nguồn vào archive QA riêng và chạy lại đủ 324 ca.
Không sửa assertion, thêm skip hoặc đưa test/fixture vào production image.
