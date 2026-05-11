# ProTrading AI - Nhật ký Dự án & Kế hoạch Phát triển

## 1. Thông tin chung
- **Tên dự án:** ProTrading AI (Version 2.0).
- **Mục tiêu:** Ứng dụng giao dịch tài chính hỗ trợ AI (DeepSeek V3.2) với tín hiệu thời gian thực.
- **Phong cách thiết kế:** Dark Mode Cyberpunk (Bố cục Dynamic UI Rendering 5 lớp).
- **Công nghệ chính:** 
  - **Frontend:** Flutter (iOS, Android, Web).
  - **Quản lý trạng thái:** BLoC (Business Logic Component).
  - **Backend:** Firebase (Authentication, Firestore, Cloud Functions, Storage).

## 2. Tiến độ triển khai - Cập nhật 20/04/2026

### A. Giao diện (UI) - HOÀN THÀNH 100%
- [x] **Web Dashboard:** Đã triển khai trọn bộ 9 màn hình chức năng (Trading Room, Journal, News, Backtest, Community, Referral, Profile, Radar, Admin).
- [x] **Mobile App:** Đã triển khai trọn bộ 9 màn hình chức năng tối ưu cho di động.
- [x] **Mã màu & Theme:** Đã cấu hình hệ thống `AppColors` Cyberpunk chuẩn tài liệu.

### B. Hạ tầng Backend (Firebase) - HOÀN THÀNH 100%
- [x] **Project Firebase:** Khởi tạo thành công project `protrading-ai-2026`.
- [x] **Package Name & Bundle ID:** Đã đồng bộ hóa tất cả về `com.protrading.ai` (Android & iOS).
- [x] **Cấu hình FlutterFire:** Đã tạo file `firebase_options.dart` và nhúng thành công file cấu hình cho Android, iOS, Web.
- [x] **Android Structure:** Đã chuẩn hóa cấu trúc thư mục Kotlin theo package name mới.

## 3. Phân tích Logic BLoC & Data Layer

### Logic đã có khung:
- **TradingRoomBloc, JournalBloc, NewsBloc, BacktestBloc, CommunityBloc, ReferralBloc, ProfileBloc, RadarBloc, AdminBloc.**

### Các phần cần thực hiện tiếp theo (Next Steps):
1.  **Data Repositories:**
    - [ ] `AuthRepository`: Xử lý đăng nhập/đăng ký với Firebase Auth.
    - [ ] `TradingRepository`: Xử lý dữ liệu nến và lệnh thực tế trên Firestore.
    - [ ] `NewsRepository`: Kết nối API tin tức và DeepSeek AI.
2.  **Logic BLoC thực tế:**
    - [ ] Thay thế dữ liệu giả lập (mock data) bằng dữ liệu Stream từ Firebase.
    - [ ] Triển khai `AuthBloc` để bảo mật các trang Dashboard.
3.  **Advanced UI:**
    - [ ] Hoàn thiện `KineticChart` với logic vẽ nến từ dữ liệu thật.

## 4. Ghi chú vận hành
- **Yêu cầu quan trọng (Thương mại hóa):** KHÔNG dùng dữ liệu giả lập (Mock data). Ứng dụng phải chạy bằng dữ liệu thật (Real-time).
- **Backend Data (Python):** Sẽ được triển khai lên **Google Cloud Run** để cấp dữ liệu qua WebSocket cho mọi nền tảng (Localhost & Firebase Hosting) hoạt động 24/7 mà không cần chạy thủ công file `server.py`.
- Để chạy Web: `flutter run -d chrome`
- Để chạy Android: `flutter run` (Đảm bảo đã mở Emulator/Thiết bị thật)
- Để chạy iOS: `flutter run` (Yêu cầu macOS và Xcode)

## 5. Kiến trúc Hệ thống Thương mại (Multi-Tenant & Real Trading)
Mục tiêu: Đưa ứng dụng ProTrading AI thành sản phẩm SaaS (Software as a Service) phục vụ hàng ngàn người dùng cùng lúc, hỗ trợ liên kết tài khoản MT4/MT5 thật thông qua MetaApi Cloud.

### 5.1. Luồng Liên kết Tài khoản MT4/MT5 (Broker Integration)
1. **Frontend (Flutter):** Cung cấp form nhập thông tin (Login, Password, Server Sàn) trong màn hình `Profile`.
2. **Backend (Python - Cloud Run):** Nhận thông tin qua API (yêu cầu xác thực Firebase ID Token). Thay vì đăng nhập trực tiếp, Python gọi API của **MetaApi Cloud** để tạo một hồ sơ (profile) cho tài khoản này trên cloud của MetaApi.
3. **Database (Firestore):** Python lưu lại `MetaApi Account ID` vừa tạo vào Firestore dưới user hiện tại. *(Tuyệt đối không lưu mật khẩu MT4 trên Firestore, MetaApi sẽ chịu trách nhiệm bảo mật).*

### 5.2. Luồng Cập nhật Số dư & Lịch sử lệnh (Real-time Equity/Balance)
1. **Frontend:** Mở kết nối WebSocket tới Server Python, gửi kèm Token xác thực.
2. **Backend (Python):**
   - Kiểm tra Token hợp lệ -> Lấy `MetaApi Account ID` của người dùng từ Firestore.
   - Thiết lập kết nối Synchronization Stream với MetaApi cho tài khoản đó.
   - Liên tục đẩy dữ liệu (Equity, Balance, Open Positions) riêng biệt của từng người dùng qua luồng WebSocket cá nhân của họ.
3. **Market Data (Chart):** Dữ liệu nến (XAUUSD, BTCUSD...) có thể sử dụng chung (1 luồng feed duy nhất từ TradingView hoặc APISed chia sẻ cho tất cả WebSocket) để tối ưu chi phí server.

### 5.3. Luồng Khớp lệnh (Execution Engine)
1. **Frontend:** Người dùng nhấn BUY/SELL (ví dụ 0.1 Lot XAUUSD). App gửi POST Request `(/api/trade)` lên Server Python (kèm Token).
2. **Backend (Python):** Xác thực Token -> Lấy MetaApi Account ID -> Gọi lệnh **Market Order / Pending Order** trực tiếp xuống API của MetaApi.
3. **Database:** Sau khi MetaApi báo khớp lệnh thành công (trả về Ticket ID), lưu thông tin lệnh vào Firestore (`trades/{userId}/{ticketId}`) để làm dữ liệu cho màn hình **Journal (Nhật ký giao dịch)**.

### 5.4. Tiêu chuẩn Bảo mật Production
- Tích hợp **CORS** chặt chẽ trên Backend.
- Yêu cầu xác thực `Authorization: Bearer <Firebase_Token>` cho MỌI endpoint thao tác với tiền.
- Rate Limiting (chống Spam API/DDoS) trên Cloud Run.
