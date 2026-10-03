# protrading_ai

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Kiểm thử backend

Các test Python nằm trong `test/backend/`; module backend chạy thật vẫn ở thư mục gốc.
Chạy từ thư mục gốc của dự án:

```sh
python3 -m unittest discover -s test/backend -p 'test_*.py' -q
```

Chạy riêng một nhóm, ví dụ kiểm tra nguồn nến OANDA:

```sh
python3 -m unittest test.backend.test_v21_oanda_history -q
```

`python3 -m unittest discover -q` vẫn tìm đầy đủ bộ test backend.
Các test Emulator cần Auth/Firestore Emulator trên local như cấu hình trong `firebase.json`.
Script thăm dò mạng TradingView nằm trong `scripts/tradingview_probe.py` và chỉ chạy thủ công.

```sh
python3 scripts/tradingview_probe.py --symbol OANDA:XAUUSD --check-backend
```

Mặc định kiểm tra 151 nến M5/M15/H1/H4/D1 qua kết nối ẩn danh, không gọi APISed.
`--check-backend` dùng cùng bộ đọc và kiểm định nến theo phiên của backend; mã thoát khác 0 khi dữ liệu
không đạt. Lấy được nến không đồng nghĩa có quyền sử dụng cho AI hoặc website thương mại.
APISed chỉ chạy với `--apised` và khóa `APISED_KEY` từ biến môi trường.

Backend chọn nguồn lịch sử bằng `MARKET_HISTORY_PROVIDER=tradingview` hoặc
`oanda_practice` (mặc định). Nguồn TradingView kiểm tra metadata mã/phiên, lấy đúng
120/120/150 nến đóng cho mỗi chế độ và ghi `market_source` vào signal.
Forex/vàng đóng cửa trả trạng thái `market_closed`; lỗi nguồn và các alias USD/USDT
không được phép phát tín hiệu thực thi. Các lịch phiên chưa hỗ trợ báo không khả dụng.

Kiểm tra toàn bộ mã Web trên máy backend:

```sh
python3 scripts/tradingview_probe.py --catalog --check-backend --output /tmp/market-probe.json
```

`PROTRADING_BACKGROUND_WORKERS=0` dành cho container ứng viên trước khi chuyển
traffic: tắt listener và các worker, tránh xử lý trùng request với bản đang chạy.
Giữ giá trị mặc định `1` cho backend phục vụ Web.

Kết quả production ngày 03/10/2026: 21 mã Web được chấp nhận cho phân tích;
10 request QA đạt và 60 nến crypto đối chiếu Bitstamp trùng OHLCV trong mẫu.
Xem [bằng chứng và giới hạn nguồn](tasks/checkpoint-2026-10-03-tradingview-production.md).
