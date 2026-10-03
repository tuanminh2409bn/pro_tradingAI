# W26 — video giới thiệu cá nhân hóa trên Web

## Hành vi

- Nút tải video tạo 6 giây artwork ProTrading gốc từ banner hiện có, QR/link
  và code server của tài khoản đang đăng nhập. QR đứng yên, accent chuyển động;
  giữ nhãn giao dịch mô phỏng, không cam kết lợi nhuận, không nhạc/stock/ảnh
  từ bên thứ ba và không upload/call AI.
- Dùng Canvas captureStream + MediaRecorder có sẵn của trình duyệt, ưu tiên
  MP4 H.264 Constrained Baseline nếu hỗ trợ; nếu không thì WebM. Đuôi tệp phải
  khớp container/MIME thật; không dùng MP4 với codec mặc định không xác định.
  Browser không hỗ trợ có trạng thái rõ ràng, PNG vẫn tải được.
- Bounded duration/input/output, một lần export đang chạy; đổi tài khoản/đóng
  trang hủy và không tải code cũ. Dừng mọi track, recorder và revoke Blob URL
  trên success/error/cancel. Không dùng camera/microphone/screen capture.

## Kiểm tra

- Test reject input/MIME/filename và stub không hỗ trợ; widget responsive,
  busy/error. Chrome thực sự encode/decode video, không chỉ mock MediaRecorder.
- Browser Emulator tải file; decoder độc lập kiểm tra container, kích thước,
  thời lượng, QR decode từ frame và chuyển động, không chỉ đuôi file.
- Format/analyzer/Web build; deploy FE source đã commit/main, kiểm tra video
  production bằng QA Standard hiện có. BE `7ef3ab6` không đổi ở lát này.
- Không đóng toàn W26 khi thiếu positive new-registration production; không
  đóng W27 tiền thưởng/rút tiền hoặc toàn kế hoạch từ asset kit.

## Nguồn API

- https://developer.mozilla.org/en-US/docs/Web/API/HTMLCanvasElement/captureStream
- https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder
- https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/mimeType
- https://api.dart.dev/dart-js_interop/JSPromiseToFuture/toDart.html

## Kiểm tra local đã đạt

- VM Flutter suite: 184 đạt, 2 skip dành cho Web/Chrome; Chrome video 4/4,
  trong đó hủy recorder đang chạy rồi encode một file thật thành công.
- Analyzer không error/warning, chỉ còn 3 info deprecated của Profile Mobile
  đã tồn tại trước lát này. Web release QA build đạt.
- Browser origin QA mới `http://127.0.0.1:8793` dùng Auth/Firestore Emulator,
  backend QA 8088 tắt provider/DeepSeek. Account fixture Standard có code
  server thật trong Emulator; không dùng credential production tại origin QA.
  QR/banner/video bị disable trong lúc export, mở lại sau callback thành công.
- File native download được PyAV 19.0.1 và ZXing đọc độc lập: H.264/MP4,
  1200×630, 5.975 giây, 69 frame, 97,261 bytes; đầu/giữa/cuối đều giải mã QR
  đúng payload, accent chuyển động, không audio. Hash/source bundle và ảnh
  browser: `web-local-referral-video-qa-2026-10-04.json` và
  `web-local-referral-video-2026-10-04.png`.
- Trước sửa, IAB chọn VP9 trong MP4 khi MIME không chỉ codec. Native decoder
  tái hiện assertion H.264 đỏ; sau chọn `avc1.424028` đạt. Chrome mặc định
  đã chọn AVC nên không tự tái hiện khác biệt này; không ghi test Chrome
  thành bằng chứng đỏ sai. Decoder chỉ cài trong `/tmp`, không thêm package
  vào ứng dụng hoặc requirements production.
- Chưa có bằng chứng Safari/điện thoại thực; trạng thái unsupported và WebM
  fallback có contract nhưng không suy ra mọi codec/browser đã nghiệm thu.

## Release và kiểm tra production đã đạt

- Source FE `a54d67d080eb12dd09ccd21e33097be3a8feb659` đã nhận ở GitHub
  main và Firebase Hosting. SHA public bundle khớp build local:
  `3a82f7d45ff1ef43c7c7214b95cf7b78677b45fce5f3c133db4b9735fc217d8f`.
- QA Standard hiện có tải video thật bằng nút Web. Decoder độc lập xác nhận
  H.264/MP4 1200×630, 5.964 giây, 69 frame, 99,573 bytes, không audio;
  QR đầu/giữa/cuối khớp link server và accent chuyển động.
- SDK read-only xác nhận code/registry đúng owner, QA vẫn Standard và
  count đăng ký 0; không ghi tiền/claim/quota. BE `7ef3ab6` vẫn healthy/Redis,
  không restart/deploy BE hoặc đổi Rules trong lát này; không gọi DeepSeek.
- Bằng chứng và ảnh: `web-production-referral-video-qa-2026-10-04.json`,
  `web-production-referral-video-2026-10-04.png`.
- W26 vẫn mở vì positive new-account registration production chưa chạy;
  không tạo thêm QA khi bước auto-review riêng còn chờ phê duyệt.
