# DeepSeek — chi phí và giới hạn gọi API, 2026-10-03

## Kết luận có bằng chứng

- Người dùng xác nhận ảnh thống kê thuộc hôm nay và key chỉ dùng cho website.
  Ảnh ghi $2,10 / 200 API request / 9.761.761 token: trung bình $0,0105 và
  khoảng 48.809 token/request. Đây là tổng thống kê, không phải giá một lần
  bấm chart. Múi giờ của biểu đồ DeepSeek chưa xác định.
- Mở chart, kéo/zoom, đổi symbol/timeframe chạy luồng dữ liệu thị trường,
  không gọi completion. Nút Phân tích mới tạo analysis request; AI Chat gọi
  completion riêng. Kiểm tra readiness dùng GET balance, không completion.
- Một analysis cache miss hợp lệ dùng tối đa 3 specialist + 1 aggregator.
  Cache hit không gọi LLM; key theo symbol/timeframe/nến đóng, không theo UID;
  single-flight và quota hiện có được giữ nguyên. Cache có TTL, không phải
  lời hứa tất cả lần bấm lại đều miễn phí.
- Source trước foundation `c7fdc40` không đặt max_tokens/thinking/timeout cho
  analysis và dùng SDK mặc định retry. Đây là rủi ro đã xác định trong code,
  chưa đủ bằng chứng kết luận nó gây toàn bộ hóa đơn.

## Đối chiếu production chỉ đọc

- Khoảng khảo sát: từ 2026-10-02 17:00 UTC, tương ứng 00:00 ngày 03/10 VN.
- Firestore theo requestedAt: 18 analysis requests, 16 COMPLETED / 2 ERROR.
  Giờ VN: 12h có 13, 14h có 1, 15h có 3, 16h có 1. 16 signal tạo hôm nay;
  2 audit có tổng 6 specialist payment_required, aggregator skipped.
- Docker log còn giữ: TV live cũ 14 analysis, 5 cache SET / 2 HIT;
  web live cũ 3 analysis / 1 SET; News live cũ 2 chat thất bại;
  services live mới không có analysis/chat ở thời điểm khảo sát.
- Chỉ một BE live bật background worker; các candidate tắt worker.
  Master prompt production dài 1.021 ký tự, không phải OHLC dump dài.
- Những số này không đối chiếu đủ 200 request nhà cung cấp. Log cũ thiếu
  usage/token và có thể thiếu lịch sử; số signal/request không bằng số
  completion. Không dùng sự thiếu log làm bằng chứng không có chi phí.

## Bản sửa

- Giữ hard cap đã có: analysis 1.500 output token/call, chat 600; thinking
  disabled, temperature 0. Không giảm chất lượng bằng cách bỏ specialist.
- Thêm tổng input cap 24.000 byte UTF-8/call. Quá giới hạn bị từ chối trước
  khi gửi provider; không cắt âm thầm bằng chứng giao dịch. Analysis dùng
  fallback an toàn theo pipeline hiện có; chat trả fallback hiện có.
- Chat SDK tắt retry tự động, timeout 20s. Analysis HTTP vốn chỉ gửi một lần.
- Log `[DeepSeek Usage]` chỉ có nhãn call cố định và số prompt/completion/
  total/cache/reasoning token. Thiếu usage để null, không giả định 0.
  Không ghi key, prompt, nội dung chat hoặc UID; không đổi Firestore schema.
- Chưa có trần chi phí USD toàn hệ thống hoặc quota riêng cho Chat. Chặn
  token từng call không thay thế hạn mức tổng số request khi lượng truy cập
  tăng. Chưa đo tỷ lệ tiết kiệm bằng completion trả phí.

## Kiểm chứng local

- 7 regression mới: output/thinking, UTF-8 input tổng, reject payload,
  usage log riêng tư, unknown usage, wiring/retry, HTTP transport offline.
- 13 ca focused cost/private API đạt; oversize Chat không gọi provider.
- Full backend + Auth/Firestore Emulator: 263/263 đạt; py_compile và
  git diff --check đạt. Không gọi completion thật trong đợt điều tra/sửa này.

## Nguồn chính thức

- [DeepSeek Chat Completion](https://api-docs.deepseek.com/api/create-chat-completion/):
  thinking mặc định và các tham số giới hạn output/usage.
- [DeepSeek Pricing](https://api-docs.deepseek.com/quick_start/pricing/):
  giá theo input/cache/output token, không có giá cố định cho một click.
- [OpenAI Python SDK retry](https://github.com/openai/openai-python#retries):
  mặc định retry 2 lần; with_options(max_retries=0) tắt cho từng request.

Để đối chiếu toàn bộ hóa đơn cần chi tiết thời gian/model/input/output/cache/
reasoning từ dashboard nhà cung cấp, không cần gửi API key.
