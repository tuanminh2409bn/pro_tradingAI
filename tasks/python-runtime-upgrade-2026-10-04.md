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
