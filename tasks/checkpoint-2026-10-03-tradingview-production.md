# TradingView — triển khai và kiểm thử production 2026-10-03

## Kết quả

Backend production đã chọn `MARKET_HISTORY_PROVIDER=tradingview`. Web hiện có đã
chạy nút Phân tích qua Firestore và nhận tín hiệu từ backend mới. Không thay đổi
Firestore Rules/schema, không gửi lệnh giao dịch, không bổ sung dependency production.
Đây là nghiệm thu nguồn nến và luồng phân tích trong phạm vi bên dưới, chưa phải
nghiệm thu 100% toàn bộ kế hoạch Web.

- FE: https://protrading-ai-2026.web.app/
- BE: https://103-69-189-243.sslip.io/
- Live container: `protrading-ai-tv-live-387ec598b9af`.
- Image: `protrading-ai:tv-387ec598b9af`, SHA256
  `2a8cb41efe7d8544eb14b271efcb6ed89ef66fcf410b31e908cf81ebd763f342`.
- 7 file runtime/local có SHA256 trùng nhau; image dựa trên runtime production
  `protrading-ai:7c5ef68`, giữ phiên bản thư viện đang chạy.
- Container live cũ và hai ứng viên đã dừng, giữ lại để khôi phục. Chỉ có một
  backend production đang xử lý listener. Redis tiếp tục hoạt động.
- Khôi phục: dừng `protrading-ai-tv-live-387ec598b9af`, khởi động
  `protrading-ai-live-7c5ef68`, kiểm tra HTTPS `/health`. Rollback chưa diễn tập
  sau chuyển traffic vì bản mới đạt health và kiểm thử; không tuyên bố đã diễn tập.

## Phạm vi nguồn được kiểm tra từ VPS

34 mapping, mỗi mapping M5/M15/H1/H4/D1, tổng cộng 170 kết nối đọc có giới hạn.
150/170 lần nhận đúng danh tính nguồn; 135/170 đầy đủ OHLCV; 120/170 đạt
kiểm định backend theo lịch phiên. Báo cáo: [catalog](tradingview-production-catalog-2026-10-03.json).

| Nhóm | Kết quả |
| --- | --- |
| OANDA: XAUUSD, XAGUSD, EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD, USDCAD, NZDUSD, EURGBP, EURJPY, GBPJPY, EURAUD, GBPAUD, AUDNZD, CADCHF, AUDCAD, NZDJPY | 18 mã đạt cả 5 khung; volume là tick volume. Đóng cửa cuối tuần trả `market_closed`. |
| BITSTAMP: BTCUSD, ETHUSD, XRPUSD | 3 mã đạt cả 5 khung, exchange volume; hoạt động 24/7. |
| BINANCE: BNBUSDT, SOLUSDT, ADAUSDT | Nến đạt cả 5 khung, nhưng 3 alias USD trên Web bị từ chối vì USD khác USDT. |
| FOREXCOM: NAS100, SPX500, UK100 | Nhận nến, thiếu volume; lịch phiên chưa hỗ trợ, không cho thực thi. |
| NYMEX: CL1!, NG1!; OANDA: XPTUSD | Nhận OHLCV, lịch phiên chưa hỗ trợ, không cho thực thi. |
| FOREXCOM: DE40, JPN225; ICEEUR: B1! | Nguồn trả lỗi symbol. |
| FOREXCOM: DJI | Nguồn resolve sang danh tính khác; bị từ chối `provider_symbol_mismatch`. |

**21 mã Web có dữ liệu được chấp nhận cho phân tích**, trong đó 18 mã forex/kim
loại đang đóng cửa tại thời điểm kiểm thử thứ Bảy. Không thay USDT thành USD,
không tạo volume, không chèn nến giả, không làm tròn timestamp để bỏ qua lỗi.
Catalog kiểm tra mapping hiện có; symbol UI ngoài mapping trả không hỗ trợ.

## Bằng chứng production

[QA JSON](tradingview-production-qa-2026-10-03.json): tài khoản QA riêng, claim
`standard`, không quyền admin, ID token chỉ giữ trong bộ nhớ.

- Lưu cấu hình paper 10.000 / risk 1% / max daily loss 5%: HTTP 200.
- Đọc cấu hình UID khác: HTTP 403.
- 10/10 request ghi bằng Firestore REST với ID token qua Rules đạt HTTP 200,
  chuyển `COMPLETED`, nhận signal đúng UID và nguồn TradingView.
- BTCUSD: Scalping M5, Day Trading M15, Swing H1; lần lặp M5 nhận cache hit.
  M5/M15 trả VETO; H1 trả SOFT. Tất cả `setup_ready=false`; không có lệnh được gửi.
- XAUUSD cả 3 chế độ và EURUSD Swing trả `market_closed`, không cache kết quả
  không khả dụng. Chưa kiểm thử vàng/forex trong phiên mở cửa.
- BNBUSD từ chối mismatch USD/USDT; US100 từ chối lịch phiên chưa hỗ trợ.
- QA Auth đã disabled và refresh token revoked sau kiểm thử. Dữ liệu QA giữ
  nguyên làm audit. Các lần thử công cụ trước đó cũng khóa QA sau khi kết thúc;
  lỗi ban đầu là token mới chưa đến thời điểm verifier và bộ đối chiếu QA tìm
  trường `timeframe` không tồn tại trên signal, đã sửa công cụ kiểm thử.
- Đối chiếu độc lập 20 nến M5 đã đóng/mã BTCUSD, ETHUSD, XRPUSD với API Bitstamp:
  tổng 60 nến, sai số tuyệt đối OHLC và volume tối đa đều 0 trong mẫu. Kết quả
  này không chứng minh giá forex/vàng hoặc độ đúng dự báo giao dịch.
- Phiên browser người dùng: lưu cấu hình paper hiện có thành công, khóa rủi ro
  được gỡ; bấm XAUUSD nhận `DATA UNAVAILABLE: market_closed`; đổi BTCUSD và bấm
  Phân tích nhận HTF trend, OB/FVG/CHoCH và VETO. Không có console error ghi nhận.
  [Ảnh BTCUSD](tradingview-production-btc-2026-10-03.jpg).

## Code và kiểm thử

- `tradingview_history.py`: bộ đọc dùng chung cho probe/production, kết nối riêng
  cho request phân tích, timeout, kiểm định exact provider identity và OHLCV.
- `market_sessions.py`, `feature_engine.py`: giữ UTC mặc định; hỗ trợ NY17/DST,
  giờ đóng/mở và Good Friday 2026 đã công bố cho metals. Lịch chưa biết fail closed.
- `market_history.py`, `server.py`, `Dockerfile`: chọn provider, truyền lịch phiên,
  giữ cache key/single-flight/ownership; worker ứng viên có thể tắt riêng.
- `scripts/tradingview_probe.py`, `scripts/verify_tradingview_production.py`,
  `deploy/clone_backend_container.py`: công cụ kiểm tra và chuyển container giữ
  cấu hình/secrets trong bộ nhớ, không ghi secrets ra báo cáo.
- Local: 239 tests, 216 pass, 23 skip vì cần Emulator; `git diff --check` đạt.
- Trong image chạy thật: 33 test probe/history/MTF/trusted-history đạt.
- HTTPS health sau triển khai: 200, Redis hoạt động. FE không sửa/rebuild trong
  lần này vì hợp đồng tín hiệu hiện có tương thích và browser chạy thành công.

## Giới hạn còn lại

- Nguồn TradingView anonymous không phải API dữ liệu chính thức; chưa xác nhận
  quyền dùng thương mại/non-display. [TradingView policies](https://www.tradingview.com/policies/).
  Khả năng truy cập hôm nay không bảo đảm SLA hoặc tiếp tục miễn phí.
- Chưa có tài khoản/token OANDA để đối chiếu giá forex/kim loại độc lập hoặc chuyển
  sang nguồn OANDA chính thức. Provider OANDA vẫn được giữ để cấu hình sau.
- Lịch holiday mới/không biết có thể khiến adapter báo không khả dụng; chưa có
  bộ lịch đầy đủ cho futures/indices. [OANDA hours](https://www.oanda.com/bvi-en/cfds/hours-of-operation/),
  [OANDA holiday hours](https://www.oanda.com/uk-en/trading/holiday-trading-hours/).
- Chưa đo tải bền vững/nhiều người dùng; chart streamer toàn cục vẫn là giới hạn
  kiến trúc cũ. `/api/trade` tiếp tục là paper execution.
- Chưa commit/push các thay đổi của lần này; workspace còn thay đổi cleanup/mobile
  trước đó cần tách khi commit. Báo cáo probe ban đầu cùng ngày là lịch sử trước
  adapter, không phải kết quả runtime hiện tại.
