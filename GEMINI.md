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
- Để chạy Web: `flutter run -d chrome`
- Để chạy Android: `flutter run` (Đảm bảo đã mở Emulator/Thiết bị thật)
- Để chạy iOS: `flutter run` (Yêu cầu macOS và Xcode)
