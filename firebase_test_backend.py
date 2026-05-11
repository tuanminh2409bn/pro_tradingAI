import firebase_admin
from firebase_admin import credentials, firestore
import time
import threading
import json
import random

# ==============================================================================
# HƯỚNG DẪN CÀI ĐẶT:
# 1. Cài đặt thư viện: pip install firebase-admin
# 2. Tải file Service Account Key (JSON) từ Firebase Console 
#    (Project Settings -> Service Accounts -> Generate new private key).
# 3. Đổi tên file tải về thành 'firebase-adminsdk.json' và để cùng thư mục với file này.
# ==============================================================================

try:
    # Khởi tạo Firebase bằng Service Account
    cred = credentials.Certificate("firebase-adminsdk.json")
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    print("✅ Đã kết nối Firebase thành công!")
except Exception as e:
    print(f"❌ Lỗi kết nối Firebase (Vui lòng kiểm tra file firebase-adminsdk.json): {e}")
    exit(1)

def simulate_ai_analysis(symbol, timeframe):
    """
    Giả lập thời gian AI (DeepSeek) xử lý và trả về một tín hiệu giả (Mock Signal)
    """
    print(f"⏳ [AI Engine] Đang phân tích dữ liệu {symbol} ở khung {timeframe}...")
    time.sleep(3) # Giả lập delay 3 giây
    
    # Tạo giá giả lập dựa trên symbol
    base_price = 2000.0 if "XAU" in symbol else 60000.0
    entry_price = base_price + random.uniform(-10, 10)
    
    # Random lệnh Mua hoặc Bán
    trade_type = random.choice(['BUY', 'SELL'])
    
    if trade_type == 'BUY':
        sl_price = entry_price - 10
        tp_prices = [entry_price + 15, entry_price + 30]
    else:
        sl_price = entry_price + 10
        tp_prices = [entry_price - 15, entry_price - 30]

    signal_data = {
        'symbol': symbol,
        'type': trade_type,
        'entryPrice': round(entry_price, 2),
        'slPrice': round(sl_price, 2),
        'tpPrices': [round(p, 2) for p in tp_prices],
        'probability': random.randint(70, 95),
        'status': 'ACTIVE',
        'createdAt': firestore.SERVER_TIMESTAMP
    }
    
    return signal_data

def on_snapshot(col_snapshot, changes, read_time):
    """
    Hàm callback lắng nghe realtime từ Firestore
    """
    for change in changes:
        if change.type.name == 'ADDED':
            req_data = change.document.to_dict()
            doc_id = change.document.id
            
            if req_data.get('status') == 'PENDING':
                symbol = req_data.get('symbol', 'UNKNOWN')
                timeframe = req_data.get('timeframe', 'UNKNOWN')
                
                print(f"\n🔔 [Sự kiện mới] Nhận yêu cầu phân tích cho {symbol} ({timeframe}) | ID: {doc_id}")
                
                # Cập nhật trạng thái thành PROCESSING
                change.document.reference.update({'status': 'PROCESSING'})
                
                # Gọi hàm giả lập AI phân tích
                ai_result = simulate_ai_analysis(symbol, timeframe)
                
                # Cập nhật trạng thái thành COMPLETED
                change.document.reference.update({'status': 'COMPLETED'})
                
                # Xóa các signal cũ của symbol này để app nhận signal mới nhất
                # (Tùy chọn: Trong thực tế có thể không cần xóa, nhưng để test thì nên clear)
                old_signals = db.collection('signals').where('symbol', '==', symbol).get()
                for doc in old_signals:
                    db.collection('signals').document(doc.id).update({'status': 'CLOSED'})

                # Push kết quả (Signal) vào collection 'signals' để App nhận được
                db.collection('signals').add(ai_result)
                print(f"✅ Đã phân tích xong và gửi tín hiệu {ai_result['type']} lên Firebase cho {symbol}!")


# Bắt đầu lắng nghe collection 'analysis_requests'
print("🎧 Đang lắng nghe yêu cầu phân tích từ ứng dụng Flutter (Nhấn Ctrl+C để thoát)...")
query_watch = db.collection('analysis_requests').on_snapshot(on_snapshot)

# Giữ cho script chạy liên tục
try:
    # Dùng threading.Event() để script không bị thoát
    threading.Event().wait()
except KeyboardInterrupt:
    print("\n🛑 Đã dừng Backend.")
