# Journal Web — bộ lọc và xuất CSV

## Kết quả cần quan sát

- Hai control hiện chỉ là Text/Container phải lọc được bảng và tải CSV thật.
  Dùng danh sách đóng lệnh hiện tại do JournalRepository đọc theo UID; không
  query tài khoản khác, tạo giao dịch hoặc gọi AI. Giữ BrokerLinkGate.
- Lọc symbol, LONG/SHORT và lãi/lỗ/hòa vốn; các điều kiện giao nhau. Hủy dialog
  giữ bộ lọc cũ, reset hiện lại tất cả, cập nhật stream không mất dữ liệu gốc.
  Hiển thị số hàng đang xem/tổng số; không đổi số liệu toàn tài khoản phía trên.
- CSV chỉ xuất hàng đang hiển thị, gồm thời điểm đóng UTC, symbol/action,
  lot/entry/exit/netProfit, executionMode và broker metrics/source/currency.
  Phí không có chứng cứ để trống, số âm giữ nguyên, không gắn tiền tệ cho P&L
  khi model không cung cấp. Không xuất UID/token/credential hay document thô.
- UTF-8 BOM, CRLF, quote/escape theo RFC 4180. Text bắt đầu bằng ký tự công
  thức sau khoảng trắng được prefix tab trong field đã quote, gồm biến thể
  full-width. Numeric được sinh từ số hữu hạn, không từ chuỗi đầu vào.
  Đây là CSV cho xem bằng spreadsheet; không tuyên bố an toàn trên mọi app
  hoặc sau mọi cách sửa/lưu lại tệp.
- Desktop và 390px đều có control; không hàng/không hỗ trợ thì export disable.
  Filename cố định + UTC date, download giới hạn 10 MB, revoke Blob URL.
  Nút chống click lặp, lỗi được báo EN/VI, không báo đã lưu thành công khi
  mới chỉ gửi yêu cầu tải cho browser.

## Kiểm tra gần nhất

- Unit: giao điều kiện/reset, giữ thứ tự, CSV precision/UTC/blank metrics,
  text quote/newline/formula/full-width, không NaN/Infinity, input giới hạn.
- Widget: filter Apply/Cancel/Reset, export đúng subset, busy/error,
  stream refresh, empty/unsupported, responsive 390px.
- Browser Emulator: dữ liệu fixture được ghi nhãn QA, tải tệp thật rồi dùng
  Python csv đọc độc lập. Production: QA hiện có, dữ liệu thực hoặc empty
  state; không tạo lệnh/claim/identity production để lấp thiếu bằng chứng.
- Format, analyzer, Web build, review diff rồi release FE theo phê duyệt
  push main/deploy trước đó; không đổi Rules/schema/BE ở lát này.

## Nguồn

- [RFC 4180](https://www.rfc-editor.org/info/rfc4180/)
- [OWASP CSV Injection](https://community.owasp.org/attacks/CSV_Injection)
- [MDN Blob URL](https://developer.mozilla.org/en-US/docs/Web/API/URL/createObjectURL_static)

## Kiểm tra đã có

- Trước triển khai, test mới không compile vì chưa có bộ lọc/encoder; source
  cũ xác nhận hai control chỉ là Text/Container. Sau triển khai, 20/20 test
  tập trung và full Flutter 195 đạt + 2 skip chỉ dành cho Web. Analyzer không
  error/warning, còn đúng 3 info deprecation Mobile tồn tại từ trước.
- Origin QA mới `http://127.0.0.1:8795` xác nhận cảnh báo Emulator trước
  đăng nhập bằng fixture. Origin cũ giữ cache khác realm; không dùng kết quả
  đăng nhập thất bại đó làm bằng chứng bug Auth hay CSV. QA dùng Auth/Firestore
  loopback, không ghi Firebase production, provider/DeepSeek của QA tắt.
- Ba CLOSED paper fixtures gồm lãi/lỗ/hòa vốn; `brokerLinked=true` chỉ là
  test fixture để qua gate trên Emulator, không phải bằng chứng MetaApi.
  Browser chọn BTCUSD + SHORT + lỗ được 1/3, reset được 3/3; tải cả hai CSV.
  Python csv.DictReader đọc tệp native độc lập: 13 cột, số âm/UTC/precision
  forex đúng, executionMode paper, không UID và broker metrics thiếu để trống.
- CSV filename dùng ngày UTC 03/10 trong khi ngày checkpoint local là 04/10;
  đây là quy tắc filename UTC, không sửa timezone để khớp ngày tài liệu.
- JSON và ảnh: `web-local-journal-controls-qa-2026-10-04.json`,
  `web-local-journal-controls-filtered-2026-10-04.png`,
  `web-local-journal-controls-2026-10-04.png`.
- Production QA có một closed record thiếu metadata mode nên hiện Unverified;
  chưa brokerLinked nên Journal
  bị gate chặn; không bật cờ broker hoặc gọi control qua overlay để tạo PASS.
  W18/W19 vẫn cần source broker và browser có danh tính/entitlement đúng.
- Quan sát cần sửa trong lát tiếp theo: Web heatmap chỉ nhận weekday 1–5,
  nên bỏ trade cuối tuần; giá trong bảng cũ làm tròn hai chữ số, khác precision
  CSV. Không coi CSV đã đạt là đã nghiệm thu toàn Journal.

## Release production

- FE source `3eea7de0d337ba93ddc0b101e220eda660370521` đã lên GitHub main
  và Firebase Hosting. Public bundle 3,783,747 bytes có SHA
  `8b5d0f090a16d65d5c4ed1fe6f386633742dbef546f713cc00df67c54b71133d`
  khớp build local; không có URL QA/Emulator, endpoint VPS đúng.
- Reload bằng QA đang đăng nhập thấy hai control thật và bộ đếm 1/1 dưới
  gate JOURNAL LOCKED. Không thao tác xuyên gate; positive CSV production
  vẫn chưa nghiệm thu. Ảnh: `web-production-journal-gate-2026-10-04.png`.
- Guard finite-profit/strict filename cuối cùng có 11/11 target test đạt;
  full suite 195+2 skip ở build trước các guard cuối, không đổi logic khác.
  BE/Rules giữ nguyên và không phát sinh gọi model từ lát này.
