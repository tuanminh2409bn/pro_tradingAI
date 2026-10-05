# W27 — chính sách và biên kế toán được chọn

Chủ dự án giao lựa chọn phương án và yêu cầu tiếp tục ngày 05/10/2026.
Phạm vi này là kế toán hoa hồng thuê bao và quy trình xét duyệt thủ công.

- USD, lưu số nguyên cent; F1 20%, F2 5% doanh thu thuê bao ròng đã quyết toán,
  làm tròn xuống từng cấp. Không dùng lợi nhuận paper/backtest, đăng ký mới hay
  số dư khách hàng để tính hoa hồng.
- Attribution phải có trước receipt; receipt đủ 14 ngày, UTC; không có chu kỳ F1/F2.
- Chỉ Admin đã xác minh có thể nhập receipt thuê bao đã đối soát bên ngoài. Nguồn
  được ghi `admin_verified_subscription`, không gọi là xác minh tự động từ gateway.
  Hiện chưa có kết nối billing/payment gateway hoặc receipt production thực tế.
- Một receipt reference chỉ ghi nhận một lần; replay với payload khác bị từ chối.
- Rút tối thiểu USD 20, không vượt số dư; mỗi tài khoản một yêu cầu mở. Pending
  giữ tiền; approved chưa chuyển tiền. Rejected trả lại khoản giữ đúng một lần.
- Paid chỉ ghi sau khi Admin nhập mã chứng từ chuyển tiền ngoài hệ thống đã kiểm
  tra; mã payout không tái sử dụng. Website không gọi ngân hàng/chuyển tiền tự động.
- Hoàn tiền tạo bút toán REVERSAL, giữ nguyên CREDIT. Có thể phát sinh số dư âm
  sau payout/refund; chặn rút mới và chặn xác nhận payout còn giữ nếu thiếu nguồn.
- Ví và bút toán dưới `users/{uid}`; client chỉ đọc của mình. Admin thao tác qua
  API token, không sửa trực tiếp financial pending request bằng Firestore client.
- Giữ receipt/payout audit riêng tư. Không ghi bank account, credential hoặc
  nội dung chứng từ vào log; API chỉ nhận reference đã chuẩn hóa.

Các đường mới: POST `/api/admin/referral/receipts`, `/reversals`,
`/withdrawals/review` và POST `/api/referral/withdrawals`.
Không backfill hoặc tự gán VERIFIED cho các số dư cũ chưa được đối soát.

Nghiệm thu production cần Admin đúng quyền, receipt thuê bao/chứng từ thật và
kiểm tra ledger/Roles/API trên cùng build. Fixture Emulator không thay thế các
bằng chứng này. W27 chưa PASS chỉ nhờ arithmetic/transaction tests.
