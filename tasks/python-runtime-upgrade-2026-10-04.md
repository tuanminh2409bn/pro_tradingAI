# Backend runtime — nâng Python 3.12

## Kết quả cần đạt

Image production không còn Python 3.10 đã hết hỗ trợ và cảnh báo các bản Google
SDK mới. Chọn Python 3.12 security-supported, đã dùng cho toàn bộ QA local.
Giữ contract API, cổng, credential path, provider, Rules và hành vi nghiệp vụ.

## Phạm vi

- Docker Official Image `python:3.12.15-slim-bookworm`, pin digest sau pull.
- Snapshot 76 package runtime hiện tại ở
  `deploy/backend-production-constraints.txt`; không lấy credential, env hoặc
  URL cài đặt. Cài `requirements.txt` với constraints để không nâng thư viện
  hoặc ép thêm package chỉ cần cho phiên bản Python cũ. Loại pip/setuptools/
  wheel khỏi snapshot vì chúng là build tooling.
- `pip check`, toàn bộ Python tests trong image network none, import/startup,
  candidate health/API auth, SDK read-only/Redis và WSS free-feed. Không gọi
  DeepSeek hoặc tạo QA production trong lát này.
- Candidate loopback tắt workers, cutover sau kiểm tra; giữ image/container
  Referral `7ef3ab6` để rollback. FE không rebuild khi không đổi source Flutter.

## Nguồn và giới hạn

- Python supported-version schedule: https://devguide.python.org/versions/
- Docker Python official tags: https://hub.docker.com/_/python
- Runtime Google SDK warnings thực tế trong readback Referral:
  `web-production-referral-qa-2026-10-04.json`.
- Dependency snapshot không thay thế security updates dài hạn; cập nhật version
  phải qua một lát riêng có kiểm thử. Không tuyên bố W35 hoặc toàn Web đạt 100%
  chỉ nhờ nâng runtime.

## Kết quả candidate trên VPS — chưa cutover

- Host thực tế: Ubuntu 16.04.7, kernel `4.4.0-210-generic`, Docker `18.09.7`,
  libseccomp `2.5.1-1ubuntu1~16.04.1`. Backend đang chạy Debian 11 Bullseye,
  Python 3.10.18, không privileged và không tắt seccomp.
- Pull base Python 3.12.15 đúng digest đã đạt. Build mặc định seccomp thất bại
  ở apt verification; container dùng một lần cũng không tạo được thread Python.
  Chỉ trong chẩn đoán không mount/credential, `seccomp=unconfined` làm apt và
  thread chạy được. Đây là bằng chứng lỗi tương thích host, không phải thiếu
  keyring; **không dùng unconfined cho build release hoặc production**.
- `pip download --only-binary` cũng bị thread denied; chưa có bằng chứng toàn
  bộ dependency cài được hoặc test ứng dụng đạt trong image 3.12 trên VPS.
- Dockerfile giữ default Bullseye đang tương thích. Build arg
  `PYTHON_RUNTIME_IMAGE` cho phép chọn digest Python 3.12 đã ghi ở trên sau
  khi chuẩn bị host mới/snapshot, test candidate và rollback. Constraints vẫn
  giữ version thư viện production; không ép nâng thư viện.
- Cần chuyển sang VPS/OS và Docker được hỗ trợ trước khi nghiệm thu runtime
  Python 3.12. Không nâng OS tại chỗ/reboot host đang phục vụ khách bằng một
  lệnh không có snapshot và môi trường thay thế. Container Referral `7ef3ab6`
  vẫn phục vụ production, FE không thay đổi ở lát runtime này.
- Nguồn chẩn đoán chính thức:
  https://github.com/docker-library/official-images/issues/16829

Log build nằm trên VPS `/tmp/protrading-runtime-base-build-193e6a7.log`.
