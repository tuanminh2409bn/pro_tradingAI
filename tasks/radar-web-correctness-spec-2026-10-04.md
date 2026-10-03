# Radar Web — dữ liệu đo và chart đích

## Lỗi quan sát trên production c63467e

- Panel không có xác nhận AI nhưng vẫn luôn tô bốn trong năm vạch strength.
- Nút Open Trading Room chỉ đổi tab; không truyền symbol/timeframe của asset.
- BLoC giữ selectedAsset object cũ khi snapshot cập nhật/xóa asset.
- UI gắn USD/today/realtime cho các trường không có currency/session/freshness
  tương ứng; header/detail chưa phù hợp bề ngang nhỏ.

## Phạm vi

- Bỏ score không có nguồn, trình bày trạng thái chưa đo/xác nhận. Hiển thị
  giá bản ghi hữu hạn, giữ precision, không tự gắn currency hoặc phiên ngày.
- Mở chart đúng symbol, dùng timeframe chỉ khi có confirmation provenance
  hiện có; xác minh timeframe thuộc matrix và chọn mode phù hợp. Request
  route tạm thời, không sửa schema/REST/Rules hoặc thực hiện phân tích/trade.
- Snapshot Radar cập nhật asset đang chọn; asset mất thì đóng detail. Clear
  selection được giữ, callback stream cũ/error/close không đổi snapshot mới.
- EN/VI, trạng thái push chưa khả dụng, narrow/large-text và retry rõ ràng.
- Tests reproducing trước sửa; native Emulator và production read-only
  chứng minh selected asset → chart. Không gọi DeepSeek, tạo QA/đổi quota,
  bật worker/FCM hoặc suy ra quyền dùng thương mại của feed.

## Cổng còn mở

W31/W32/W34 cần worker/provider/watchlist 50–100, freshness/volume/barrier/
license, real AI confirmation, device push và ma trận role/load. Snapshot
UI hoặc fixture local không thay thế các bằng chứng đó.

## Kiểm chứng local 04/10

- Bốn test tái hiện lỗi đỏ: selected price 2000 thay vì snapshot 2010,
  clear selection bị mở lại, không có strength-unmeasured message và bốn
  RenderFlex overflow ở 390 px/text scale 2 (header overflow 1672 px).
- Sau sửa: target 14/14; toàn Flutter 247 đạt + 2 skip Web-only trên VM.
  Analyzer 0 error/0 warning, 3 deprecated info Mobile có sẵn. Format/diff
  check đạt; Web release với Firebase Emulator build thành công.
- Unit tests kiểm tra cả 5 timeframe M5/M15/H1/H4/D1, mode đúng matrix,
  reset repository interval khớp state; target ETHUSD không bị saved BTCUSD
  ghi đè. Normal navigation vẫn restore saved symbol, xóa target tạm thời.
  Invalid symbol/timeframe bị từ chối. Không gọi phân tích từ chart-entry.
- Native browser origin mới 8803: EN/VI và precision 2688.331234, label
  fixture rõ, strength chưa đo, push tắt. Đóng detail rồi update fixture
  2687.331234→2688.331234: giá thay đổi nhưng panel vẫn đóng. Chọn lại và
  mở chart thành ETHUSD H4/Day Trading. Không bấm Analyze/Chat/Trade.
- Đây là fixture chỉ ở Emulator; confirmationId/provider/model/licenseRef
  đều mang nhãn QA-only, không phải quyền thương mại hoặc AI thật. API local
  origin 8803 chưa được CORS allowlist nên chart price/risk unavailable;
  bằng chứng này chỉ xác nhận route/header/matrix, không phải feed parity.
- QA bundle: 3,777,873 bytes, SHA
  `a8c1989bbbea92a1c053ae753bc452b1aeb0ce59911d78c90340b44dc1ad2740`.
  Xem `web-local-radar-correctness-2026-10-04.json` và hai ảnh local kèm theo.
- Không thêm dependency hoặc thay Firestore/REST/Rules; BE không đổi.
  Chưa đóng W31/W32/W34 hoặc tuyên bố Web 100%.
