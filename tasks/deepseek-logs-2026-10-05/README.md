# Log DeepSeek và đối chiếu chi phí — 05/10/2026

> Báo cáo này giữ nguyên khoảng log ghi bên dưới, trước bản phát hành mới
> 05/10. Container live sau đó là `protrading-web-quota-live-20261005`.
> Xem [production release](../web-production-release-20261005/README.md) và
> [balance chỉ đọc 09:22 UTC](../web-production-release-20261005/deepseek-balance-final.json).
> Không suy ra request/token/chi phí của bản mới từ bản xuất lịch sử này.

## Kết quả

Đã đọc trực tiếp log Docker còn lưu trên VPS `103.69.189.243`, lọc tại VPS
trước khi xuất. Không gọi completion, không đọc API key hoặc cấu hình credential,
không thay đổi hay khởi động lại dịch vụ.

- Khoảng yêu cầu: **03/10/2026 00:00:00 → 05/10/2026 08:59:59, giờ Việt Nam**.
- Đã đọc **21.561 dòng**, **22 container**; mọi lệnh đọc log trả exit code 0.
- Xuất **82 sự kiện liên quan**. Đây là sự kiện backend, **không phải 82 request
  DeepSeek**: một lượt phân tích có nhiều dòng bắt đầu/cache/kết quả.
- 10 container có tên production; 12 candidate được đánh dấu riêng, loại khỏi
  thống kê production. Phân loại này dựa vào tên container.
- **Không tìm thấy bản ghi `[DeepSeek Usage]` hoặc phản hồi HTTP DeepSeek** trong
  các log đã quét. Tổng request completion, token và tiền đều để `null` (chưa biết),
  không điền 0.

## File chi tiết

- [deepseek-events.csv](deepseek-events.csv): mở bằng Excel; mỗi dòng là một sự
  kiện thực, có giờ Việt Nam, timestamp UTC gốc, container và các trường có trong log.
- [deepseek-events.json](deepseek-events.json): toàn bộ sự kiện, số liệu tổng hợp,
  thời gian đầu/cuối còn lưu của từng container, số dòng đã quét và giới hạn dữ liệu.

CSV để trống các trường không được ghi ở sự kiện tương ứng. Bản xuất không chứa
prompt, nội dung chat, UID, email, IP người dùng, key hoặc body phản hồi nhà cung cấp.
Timestamp UTC giữ độ chính xác gốc; cột giờ Việt Nam hiển thị đến giây.

## Thống kê tìm được

| Nội dung | Số lượng | Ý nghĩa |
|---|---:|---|
| Lượt phân tích bắt đầu | 17 | Không tương đương số request nhà cung cấp |
| Signal đã lưu | 15 | Có thể là fallback; không chứng minh AI trả lời thành công |
| Analysis kết thúc bằng fallback | 15 | Metric `provider_unavailable`; không có HTTP status/token |
| Analysis kết thúc bằng lỗi | 2 | Metric `internal_error` |
| Cache SET | 6 | Ghi kết quả vào cache; kết quả có thể là fallback |
| Cache HIT | 2 | Theo code hiện tại, hit không gọi completion |
| Master prompt fallback | 4 | Thiếu prompt nên dùng thuật toán thay thế |
| Chat thất bại | 2 | Metric `internal_error`; không xác định được phí |
| Bản ghi usage/token | 0 tìm thấy | Không có dữ liệu để tính tiền từng request |

Các metric kết quả gồm 17 analysis và 2 chat. Không suy ra số lần retry hay số
request DeepSeek từ các metric này. Không ghép request và kết quả chỉ bằng thứ tự
log: log hiện chưa có request ID chung để nối chắc chắn khi chạy đồng thời.

## Một số dòng đáng xem

| Giờ Việt Nam, 03/10 | Sự kiện | Chi tiết có trong log |
|---|---|---|
| 12:53:22 | BTCUSD / 5 | Thiếu master prompt, cache SET, fallback |
| 12:56:02 | BTCUSD / 5 | Cache HIT, nến `1791006600` |
| 12:56:12 | BTCUSD / 5 | Cache HIT, cùng nến `1791006600` |
| 14:52:03 | BTCUSD / 5 | Cache SET; metric fallback `provider_unavailable`, 2.737 ms |
| 15:45:06 | BTCUSD / 5 | Cache SET; metric fallback `provider_unavailable`, 3.111 ms |
| 15:52:11 | Analysis | Metric failure `internal_error`, 1.623 ms |
| 16:08:33 | Analysis | Metric failure `internal_error`, 1.607 ms |
| 17:29:45 | AI Chat | Failure `internal_error`, 735 ms |
| 17:57:51 | AI Chat | Failure `internal_error`, 621 ms |

Docker timestamp là thời điểm ghi log, có thể chịu ảnh hưởng buffering.
Metric latency là độ trễ thao tác backend, không phải độ trễ riêng của DeepSeek.
Không thấy sự kiện phù hợp bộ lọc trong log container live hiện tại
`protrading-ai-referral-live-7ef3ab6`; điều này không thay thế báo cáo billing.

## Vì sao chưa giải thích được đủ $2,10?

Ảnh người dùng cung cấp ghi **$2,10 / 200 API request / 9.761.761 token**:

- Trung bình **$0,0105/request**, **48.808,805 token/request**.
- $2,10 là tổng của khoảng thống kê trong ảnh, không phải giá một lần mở chart.
- 17 lượt phân tích trong Docker không thể đối chiếu trực tiếp với 200 request.
  Một analysis cache miss có thể gọi 3 specialist và 1 aggregator; chat gọi riêng.
- Múi giờ và phạm vi thống kê trên dashboard chưa được xác nhận.
- Log cũ thiếu usage. Không thể khôi phục input/output/cache/reasoning token,
  model, provider request ID, retry hoặc chi phí từng completion chỉ từ log này.

[Điều tra ngày 03/10](../deepseek-cost-investigation-2026-10-03.md) ghi nhận
18 request trong Firestore, khác 17 lượt bắt đầu thấy trong Docker hiện còn lưu.
Đó là hai nguồn ghi nhận khác nhau; đợt xuất này không truy vấn lại Firestore
và không thay thế số liệu provider. Chưa đủ bằng chứng quy toàn bộ hóa đơn cho
một thao tác chart, kiểm thử hoặc một nguyên nhân cụ thể.

## Cấu hình code hiện tại và phần log còn thiếu

Code `server.py` hiện tại giới hạn input 24.000 byte UTF-8/call, output analysis
1.500 token/call, chat 600 token/call; `temperature=0`, thinking tắt,
timeout 20 giây, SDK chat retry 0. Đây là cấu hình hiện tại, không phải thông số
đã ghi lại của 200 request trong ảnh.

`_record_llm_usage` chỉ ghi usage sau phản hồi thành công, gồm nhãn tác vụ
`smc/vsa/macro/aggregator/chat`, input/output/total/cache/reasoning token.
Chưa ghi chi tiết mọi lần bắt đầu/kết thúc gọi provider, lỗi HTTP, model,
request ID, latency riêng của provider và liên kết cache/correlation trong cùng
một bản ghi. Vì vậy log hiện tại chưa đủ để làm sổ đối chiếu chi phí hoàn chỉnh.

Để xác định đủ 200 request cần xuất Usage/Billing từ dashboard DeepSeek theo
ngày và múi giờ, model, số request, input cache hit/miss, output và chi phí.
Nếu dashboard chỉ cung cấp tổng hợp, vẫn chưa thể phân bổ chính xác từng click.
Không cần API key cho bước đối chiếu đó.

## Kiểm tra bản xuất

- JSON đọc được; CSV đọc lại đúng **82 dòng dữ liệu**.
- Các trường sự kiện nằm trong allowlist; chỉ giữ số, boolean và nhãn cố định.
- Quét định dạng credential, email và trường payload riêng tư: không phát hiện.
- Không có thay đổi source ứng dụng, Rules, schema, dependency hoặc production.
