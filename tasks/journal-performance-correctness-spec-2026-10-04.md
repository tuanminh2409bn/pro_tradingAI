# Journal Web — thống kê từ lệnh đóng đã đo

## Vấn đề có bằng chứng

- Production preview `7c9e938` có một lệnh thắng nhưng Profit Factor 0.00:
  repository thay infinity bằng zero. Break-even bị tính vào average loss,
  làm tỷ lệ average win/average loss tăng sai. Nhãn R:R/Above target dùng
  một đại lượng khác, chưa có initial-risk snapshot để tính R thực sự.
- UI suy ra discipline/risk adherence từ win rate và best/worst P&L, không
  phải số liệu tuân thủ rủi ro. Insight deterministic bị gắn nhãn AI.
- Parser có thể dựng closeTime từ `DateTime.now`/openTime, dựng profit zero
  khi thiếu nguồn, hoặc ném lỗi với numeric payload không đúng kiểu.
- BLoC đọc hai snapshot history/stats độc lập; cần dùng cùng snapshot owner
  để trade table và thống kê nhất quán, loại bỏ kết quả stream owner cũ.

## Quyết định triển khai

- Profit Factor = gross profit / magnitude gross loss. Khi không có loss,
  hiển thị “Chưa có lệnh lỗ”, không suy ra chất lượng chiến lược. All-flat/
  empty hoặc ratio không hữu hạn hiển thị unavailable.
- Average win/average loss chỉ dùng wins > 0 và losses < 0; thiếu một nhóm
  hiển thị unavailable. Không coi đó là R:R từ initial stop/risk.
- Parser chỉ dùng close timestamp/P&L/giá có nguồn hợp lệ, bỏ record hỏng;
  không đoán ngày đóng hoặc profit. Giữ tên field/schema hai dạng hiện có.
- Một history snapshot owner tạo đồng thời stats/table; generation chặn
  callback cũ khi reload/đổi owner/close. Không thêm Firestore query/index.
- Web chỉ trình bày counts/ratio/summary đã đo, không giả psychology/risk
  score hoặc tiền tệ P&L chưa có chứng cứ. Copy mới có EN/VI, audio đọc đúng
  summary đang hiển thị. Không gọi model, sửa claim/quota/broker provider.
- Local reproducing tests trước sửa, rồi schema/malformed/zero/flat/overflow,
  sample arithmetic và owner-stream tests; browser Emulator đúng build.
  Production broker gate giữ nguyên, không nghiệm thu broker/TTS từ fixture.

## Nguồn công thức

[MetaTrader 5 Testing Report](https://www.metatrader5.com/en/terminal/help/algotrading/testing_report)
định nghĩa Profit Factor từ tổng lời/tổng lỗ và average profit trade từ tổng
lời chia số lệnh thắng. Average win/loss ở đây là tỷ lệ hai mẫu đã quan sát,
không phải expected payoff (average net result per trade) hoặc planned R:R.

## Kiểm chứng local — 04/10

- Có test đỏ trước sửa: all-wins/flat/parser (8 lỗi), hai snapshot lệch
  history 42/stats 999, VI dùng en-US, callback audio cũ/start fail/end đồng
  bộ (3 lỗi), và overflow layout ở 390 px/text scale 2.
- Sau sửa: 37/37 target cuối, full Flutter 237 đạt + 2 ca Web-only skip trên
  VM. Analyzer 0 error/0 warning, chỉ 3 deprecated info Mobile có sẵn.
  Web release với Firebase Emulator build thành công, diff check đạt.
- Browser native origin mới 8801 hiển thị EN/VI: 3 lệnh fixture đóng,
  P&L -7.91, win rate 33.3%, Profit Factor 0.61, average win/loss 0.61×;
  wins/losses/flat = 1/1/1. Nhóm lỗ CN 06 UTC chỉ có 1 lệnh -20.25,
  heatmap cùng giờ có đủ 3 lệnh -7.91; giá forex giữ 1.1234567/1.1234568.
- Không có % discipline/risk suy đoán hoặc tiền tệ P&L tự gắn USD.
  Tóm tắt EN/VI có cùng nguồn stats với bảng. Native audio chuyển nút
  Phát→Dừng→Phát; unit tests kiểm tra đúng locale/text và lifecycle.
  Chưa có bằng chứng nghe âm thanh/device voice hoặc playback production.
- Bundle thực phục vụ khớp build: 3,774,131 bytes, SHA
  `a173d2bb8884aa37bf002602b651609adffe6ed7f8fbd6ec24dec54da684862d`.
  Xem `web-local-journal-performance-2026-10-04.json` và ảnh kèm theo.
- Đây là fixture chỉ ở Firebase Emulator, không phải broker/provider thật.
  Origin 8801 chưa trong CORS QA backend nên Trading Room/API tại origin
  này unavailable theo thiết kế; không dùng kết quả Journal để nghiệm thu
  các API đó. Không gọi DeepSeek, tạo QA production hoặc sửa quota/claim.

## Giới hạn nghiệm thu

W18/W19 vẫn cần nguồn broker có tiền tệ, initial-risk snapshot và playback/
CSV production bằng danh tính đúng quyền. Production QA hiện không có
broker link; giữ nguyên gate. Không tuyên bố hoàn thành 100% từ fixture.
